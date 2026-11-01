"""Lazy library adapters. No unannounced substitute for requested matching."""
from pathlib import Path
import cv2
import numpy as np
from PIL import Image


def load_rgb(path):
    from PIL import ImageOps
    with Image.open(path) as im: return np.asarray(ImageOps.exif_transpose(im).convert('RGB')).copy()


def read_mask(path,shape):
    with Image.open(path) as im: mask=np.asarray(im.convert('L'))>0
    if mask.shape!=shape: raise ValueError(f'Mask dimensions must match the EXIF-oriented image: {path}')
    return mask


class PartSegmenter:
    def __init__(self,settings,resolve): self.settings=settings;self.resolve=resolve;self.sam=None
    def segment(self,rgb,spec):
        if spec.get('mask'): return read_mask(self.resolve(spec['mask']),rgb.shape[:2]),'provided_mask'
        if not self.settings.get('checkpoint'):
            raise ValueError('Provide a reviewed part mask or a local SAM checkpoint plus part box/point prompts.')
        if 'box' not in spec and 'points' not in spec:
            raise ValueError('SAM needs a phone-part box or points; a model name alone does not locate precise part boundaries.')
        if self.sam is None:
            from ultralytics import SAM
            checkpoint=self.resolve(self.settings['checkpoint'])
            if not checkpoint.is_file(): raise FileNotFoundError(f'SAM checkpoint not found: {checkpoint}')
            self.sam=SAM(str(checkpoint))
        kwargs={'source':cv2.cvtColor(rgb,cv2.COLOR_RGB2BGR),'verbose':False,
                'device':self.settings.get('device','cpu')}
        if 'box' in spec: kwargs['bboxes']=[spec['box']]
        if 'points' in spec:
            kwargs['points']=[spec['points']];kwargs['labels']=[spec.get('point_labels',[1]*len(spec['points']))]
        result=self.sam.predict(**kwargs)[0]
        if result.masks is None: raise ValueError('SAM did not return a part mask; refine its prompts.')
        masks=result.masks.data.cpu().numpy()
        index=int(spec.get('mask_index',0))
        if index>=len(masks): raise ValueError('SAM mask_index is out of range.')
        mask=cv2.resize(np.asarray(masks[index],dtype=np.float32),(rgb.shape[1],rgb.shape[0]),
                        interpolation=cv2.INTER_NEAREST)>.5
        return mask,'sam_prompted_proposal'

    def propose(self,rgb,capture_view=None):
        mode=self.settings.get('mode')
        if mode not in ('grounded_sam','whole_phone_outline'):return []
        import torch
        try:from transformers import AutoProcessor,AutoModelForZeroShotObjectDetection
        except ImportError as exc:raise RuntimeError('Automatic phone-outline proposals require requirements-parts.txt.') from exc
        if not hasattr(self,'grounder'):
            model_id=self.settings.get('detector_model','IDEA-Research/grounding-dino-tiny')
            cache=str(Path(__file__).parent/'weights'/'huggingface')
            self.processor=AutoProcessor.from_pretrained(model_id,cache_dir=cache)
            self.grounder=AutoModelForZeroShotObjectDetection.from_pretrained(model_id,cache_dir=cache).eval().to(self.settings.get('device','cpu'))
        if mode=='whole_phone_outline':
            targets=[('Phone_Outline','Phone','the complete outline of a whole mobile phone')]
        else:
            targets=[('Screen','Screen','the display screen of a mobile phone'),
                     ('Back','Back','the back panel of a mobile phone'),
                     ('Frame_Unknown','Frame','the side metal frame of a mobile phone')]
            if capture_view in ('front','back'):targets=[targets[0 if capture_view=='front' else 1]]
            elif capture_view and capture_view.startswith('frame_'):
                facet=capture_view.split('_',1)[1].title()
                if facet not in ('Left','Right','Top','Bottom'):raise ValueError('Invalid frame capture_view.')
                targets=[('Frame_'+facet,'Frame','the side metal frame of a mobile phone')]
        proposals=[]
        for sid,part,text in targets:
            inputs=self.processor(images=Image.fromarray(rgb),text=text+'.',return_tensors='pt').to(self.settings.get('device','cpu'))
            with torch.inference_mode():outputs=self.grounder(**inputs)
            rows=self.processor.post_process_grounded_object_detection(outputs,inputs.input_ids,
                threshold=float(self.settings.get('box_threshold',.3)),text_threshold=.25,target_sizes=[rgb.shape[:2]])[0]
            if not len(rows['boxes']):continue
            best=int(rows['scores'].argmax());box=rows['boxes'][best].cpu().tolist()
            known_frame_facet=sid in ('Frame_Left','Frame_Right','Frame_Top','Frame_Bottom')
            spec={'id':sid,'part':part,'box':box,'reviewed':False,'complete':False,
                  'planar':part in ('Screen','Back','Phone') or known_frame_facet,
                  'proposal_confidence':float(rows['scores'][best])}
            mask,method=self.segment(rgb,spec)
            spec.update(_mask=mask,_method='grounding_dino+'+method);proposals.append(spec)
        # Competing semantic proposals often describe the same visible panel.
        # Keep the strongest rather than inventing overlapping screen/back surfaces.
        accepted=[];occupied=np.zeros(rgb.shape[:2],bool)
        for spec in sorted(proposals,key=lambda s:s['proposal_confidence'],reverse=True):
            if (spec['_mask']&occupied).sum()/max(1,spec['_mask'].sum())>.1:continue
            spec['_mask'] &= ~occupied
            if spec['_mask'].sum()<25:continue
            occupied |= spec['_mask'];accepted.append(spec)
        return accepted


class LibraryMatcher:
    def __init__(self,settings):
        self.settings=settings;self.backend=settings.get('backend','lightglue_aliked')
        self.extractor=None;self.matcher=None;self.cache={}
    def _features(self,key,rgb):
        import torch
        if self.extractor is None:
            try: from lightglue import LightGlue, ALIKED
            except ImportError as exc:
                raise RuntimeError('Install detection_evaluation/requirements-matching.txt. ALIKED + LightGlue is required; no silent fallback is used.') from exc
            self.device=torch.device(self.settings.get('device','cpu'))
            previous=torch.hub.get_dir()
            torch.hub.set_dir(str(Path(__file__).parent/'weights'/'torch_hub'))
            try:
                self.extractor=ALIKED(max_num_keypoints=int(self.settings.get('max_keypoints',2048))).eval().to(self.device)
                self.matcher=LightGlue(features='aliked').eval().to(self.device)
            finally:torch.hub.set_dir(previous)
        if key not in self.cache:
            tensor=torch.from_numpy(rgb.transpose(2,0,1).copy()).float().div(255).to(self.device)
            with torch.inference_mode(): self.cache[key]=self.extractor.extract(tensor)
        return self.cache[key]
    def points(self,key0,rgb0,key1,rgb1):
        if self.backend=='lightglue_aliked':
            import torch
            a=self._features(key0,rgb0);b=self._features(key1,rgb1)
            with torch.inference_mode(): result=self.matcher({'image0':a,'image1':b})
            matches=result['matches'][0]
            return a['keypoints'][0][matches[:,0]].cpu().numpy(),b['keypoints'][0][matches[:,1]].cpu().numpy()
        if self.backend=='sift':
            # Explicit optional offline baseline, identified in every report.
            sift=cv2.SIFT_create(nfeatures=int(self.settings.get('max_keypoints',2048)))
            k0,d0=sift.detectAndCompute(cv2.cvtColor(rgb0,cv2.COLOR_RGB2GRAY),None)
            k1,d1=sift.detectAndCompute(cv2.cvtColor(rgb1,cv2.COLOR_RGB2GRAY),None)
            if d0 is None or d1 is None: return np.empty((0,2)),np.empty((0,2))
            pairs=cv2.BFMatcher().knnMatch(d0,d1,k=2)
            good=[m for pair in pairs if len(pair)==2 for m,n in [pair] if m.distance<.7*n.distance]
            return np.float32([k0[m.queryIdx].pt for m in good]).reshape(-1,2),np.float32([k1[m.trainIdx].pt for m in good]).reshape(-1,2)
        if self.backend=='provided':
            row=self.settings.get('correspondences',{}).get(key0+'|'+key1)
            if row is not None: return np.asarray(row['source'],np.float32),np.asarray(row['target'],np.float32)
            row=self.settings.get('correspondences',{}).get(key1+'|'+key0)
            if row is not None: return np.asarray(row['target'],np.float32),np.asarray(row['source'],np.float32)
            return np.empty((0,2)),np.empty((0,2))
        raise ValueError('matching.backend must be lightglue_aliked, sift, or provided.')


class DefectPredictor:
    def __init__(self,settings,resolve,threshold):
        self.settings=settings;self.resolve=resolve;self.threshold=threshold;self.predictor=None
    def predict(self,image,output):
        if self.predictor is None:
            from model2_defect_segmentation.inference.predict import Predictor
            config=self.resolve(self.settings['config']);checkpoint=self.resolve(self.settings['checkpoint'])
            self.predictor=Predictor(str(config),str(checkpoint),device=self.settings.get('device','cpu'))
            self.predictor.cfg['confidence_threshold']=self.threshold
        result=self.predictor.predict(image,output_dir=output)
        return result
