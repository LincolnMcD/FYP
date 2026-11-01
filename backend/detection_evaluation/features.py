"""Image quality, local appearance and configurable cosmetic severity."""
import cv2
import numpy as np
from .geometry import measured


def image_quality(rgb):
    gray=cv2.cvtColor(rgb,cv2.COLOR_RGB2GRAY)
    blur=float(cv2.Laplacian(gray,cv2.CV_64F).var())
    clipped=float(((gray<8)|(gray>247)).mean())
    score=float(np.clip(blur/150,0,1)*(1-clipped))
    return {'sharpness':blur,'clipped_fraction':clipped,'score':score,
            'acceptable':bool(min(gray.shape)>=64 and blur>=15 and clipped<.4)}


def appearance(rgb,mask,part,all_defects):
    lab=cv2.cvtColor(rgb,cv2.COLOR_RGB2LAB).astype(np.float32)
    lab[:,:,0]*=100/255;lab[:,:,1:]-=128
    radius=max(3,round(min(mask.shape)*.015))
    ring=(cv2.dilate(mask.astype(np.uint8),np.ones((radius*2+1,radius*2+1),np.uint8))>0)&part&~all_defects
    gray=cv2.cvtColor(rgb,cv2.COLOR_RGB2GRAY)
    ring &= (gray>8)&(gray<247)
    result={'intensity':'unknown','apparent_depth_cue':'unknown','delta_e76':None,'robust_local_change':None,
            'reference_pixels':int(ring.sum()),'reliability':'low','physical_depth':None,
            'depth_note':'Apparent depth cue is based on local appearance contrast; physical depth is not measured.'}
    if ring.sum()<30 or mask.sum()<3: return result
    reference=np.median(lab[ring],axis=0); defect=np.median(lab[mask],axis=0)
    delta=float(np.linalg.norm(defect-reference))
    residual=np.linalg.norm(lab[ring]-reference,axis=1)
    noise=max(2.,float(np.median(residual))*1.4826)
    z=delta/noise
    intensity='Strong' if delta>=15 and z>=3 else ('Moderate' if delta>=5 and z>=1.5 else 'Weak')
    highlights=float(((gray[mask]<8)|(gray[mask]>247)).mean())
    result.update(intensity=intensity,apparent_depth_cue=intensity,delta_e76=delta,robust_local_change=z,
                  reliability='moderate' if highlights<.25 and noise<12 else 'low',
                  highlight_fraction=highlights,reference_texture_scale=noise)
    return result


def features(rgb,mask,surface,all_defects,metric,confidence,complete_override=None):
    part=surface['mask'];quality=image_quality(rgb)
    clipped=mask&part; fraction=float(clipped.sum()/max(1,mask.sum()))
    stats=measured(clipped,part,metric); visual=appearance(rgb,clipped,part,all_defects)
    edge=np.zeros(mask.shape,bool);edge[[0,-1],:]=True;edge[:,[0,-1]]=True
    part_edge=part&~(cv2.erode(part.astype(np.uint8),np.ones((3,3),np.uint8))>0)
    boundary=bool((clipped&(edge|part_edge)).any())
    mask_score=float(np.clip(confidence,0,1)*fraction*(.7 if boundary else 1))
    complete=bool(surface.get('complete',False) and surface.get('reviewed',False) and not boundary
                  and quality['acceptable'] and fraction>=.9 and mask.sum()>=3)
    if complete_override is False: complete=False
    visibility=float(surface.get('visibility',1. if surface.get('complete') else .5))
    if not 0<=visibility<=1: raise ValueError('visibility must be in [0,1].')
    score=.35*quality['score']+.25*mask_score+.2*visibility+.2*confidence
    return {'measurement':stats,'appearance':visual,'image_quality':quality,
            'mask_quality':{'score':mask_score,'fraction_inside_surface':fraction,'touches_boundary':boundary},
            'visibility':visibility,'sufficiently_complete':complete,'selection_score':float(score)}


def severity(measurement,visual,rubric=None):
    rubric=rubric or {};levels=['Low','Minor','Major','Critical']
    if measurement.get('coverage') is None:
        return {'label':'Unknown','ordinal':None,'rubric':'surface denominator unavailable',
                'requires_review':True,'functional_or_structural_safety_assessed':False}
    thresholds=rubric.get('coverage_thresholds',[.02,.10,.30])
    if len(thresholds)!=3 or not 0<thresholds[0]<thresholds[1]<thresholds[2]<=1:
        raise ValueError('Severity coverage thresholds must be three increasing fractions in (0,1].')
    index=sum(measurement['coverage']>=t for t in thresholds)
    if visual['intensity']=='Strong' and visual['reliability']!='low' and index>=1:
        index=min(3,index+1)
    return {'label':levels[index],'ordinal':index,'rubric':'unvalidated cosmetic area/appearance heuristic',
            'requires_review':visual['reliability']=='low',
            'functional_or_structural_safety_assessed':False}
