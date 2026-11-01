"""Inspection orchestration: originals -> observations -> identities -> report."""
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import cv2
import numpy as np
from PIL import Image

from .adapters import PartSegmenter,LibraryMatcher,DefectPredictor,load_rgb,read_mask
from .geometry import union,merge_overlapping,calibration,measured,warp,transform,estimate_calibration
from .features import features,severity,image_quality
from .matching import group_observations,registration_for

CLASSES=['Back_Crack','Back_Scratch','Frame_Dent','Frame_Scratch','Screen_Crack','Screen_Discolouration','Screen_Scratch']

# Malaysia smartphone ASP reported for H1 2025. Keep configurable so the fallback
# can be refreshed without changing the evaluation pipeline.
DEFAULT_MARKET_AVERAGE_MYR = 1893.0
DEFAULT_USD_TO_MYR_RATE = 4.0476


def attach_market_price(profile, brand, model, config, resolve):
    """Attach the device MSRP in MYR, falling back to the Malaysia market average."""
    profile = copy.deepcopy(profile)
    raw = profile.get('provider_raw') or {}
    value = raw.get('msrp_usd')
    try:
        amount = float(value)
        if not np.isfinite(amount) or amount <= 0:
            amount = None
    except (TypeError, ValueError):
        amount = None

    # Bundled geometry profiles have no price. Reuse the existing TechAPI
    # lookup/cache path for price metadata while preserving the selected geometry.
    if amount is None and brand and model:
        try:
            from .phone_specs import PHONE_SPECS_API_BASE, lookup
            options = config.get('phone_specs', {})
            api_profile = lookup(
                brand, model,
                catalog_path=resolve(options['catalog']) if options.get('catalog') else None,
                api_base=options.get('api_base') or PHONE_SPECS_API_BASE,
                slug=options.get('slug'),
            )
            api_raw = api_profile.get('provider_raw') or {}
            value = api_raw.get('msrp_usd')
            amount = float(value)
            if not np.isfinite(amount) or amount <= 0:
                amount = None
        except (OSError, ValueError, TypeError, KeyError, TimeoutError):
            amount = None

    if amount is not None:
        try:
            usd_to_myr = float(os.environ.get('USD_TO_MYR_RATE', DEFAULT_USD_TO_MYR_RATE))
        except (TypeError, ValueError):
            usd_to_myr = DEFAULT_USD_TO_MYR_RATE
        if not np.isfinite(usd_to_myr) or usd_to_myr <= 0:
            usd_to_myr = DEFAULT_USD_TO_MYR_RATE
        profile['msrp'] = round(amount * usd_to_myr, 2)
    else:
        try:
            market_average = float(os.environ.get(
                'PHONE_MARKET_AVERAGE_MYR', DEFAULT_MARKET_AVERAGE_MYR
            ))
        except (TypeError, ValueError):
            market_average = DEFAULT_MARKET_AVERAGE_MYR
        if not np.isfinite(market_average) or market_average <= 0:
            market_average = DEFAULT_MARKET_AVERAGE_MYR
        profile['msrp'] = round(market_average, 2)
    return profile


def digest(path):
    h=hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda:stream.read(1024*1024),b''):h.update(block)
    return h.hexdigest()


def safe_id(value):
    if not re.fullmatch(r'[A-Za-z0-9_-]+',value):raise ValueError('IDs must contain only letters, numbers, _ or -.')
    return value


def serial(value):
    if isinstance(value,np.ndarray):return value.tolist()
    if isinstance(value,np.generic):return value.item()
    if isinstance(value,Path):return str(value)
    raise TypeError(type(value).__name__)


def save_mask(mask,path):Image.fromarray(mask.astype(np.uint8)*255).save(path)


def nominal_part_coverage(measurement,part,profile):
    """Approximate defect/whole-part ratio when both physical areas are known."""
    denominator=profile.get('nominal_areas_cm2',{}).get(part)
    numerator=measurement.get('area_cm2')
    if denominator is None or numerator is None or denominator<=0:return None
    return min(1.0,max(0.0,float(numerator)/float(denominator)))


def infer_frame_facet(mask,profile):
    """Choose a nominal frame facet whose aspect ratio fits an automatic mask."""
    candidates=[]
    for name,spec in profile.get('surfaces',{}).items():
        if name not in ('Frame_Left','Frame_Right','Frame_Top','Frame_Bottom'):continue
        width=float(spec.get('width_mm') or 0);height=float(spec.get('height_mm') or 0)
        if width>0 and height>0:candidates.append((name,spec,max(width,height)/min(width,height)))
    contours,_=cv2.findContours(mask.astype(np.uint8),cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)
    if not candidates or not contours:return None
    sides=sorted(cv2.minAreaRect(max(contours,key=cv2.contourArea))[1],reverse=True)
    if sides[1]<=0:return None
    observed=sides[0]/sides[1]
    name,spec,error=min(candidates,key=lambda row:abs(np.log(max(observed,1e-6)/row[2])))
    # A poor shape match is too ambiguous to turn pixel area into physical area.
    if abs(np.log(max(observed,1e-6)/error))>np.log(3):return None
    return name,spec


def infer_outline_dimensions(mask,profile):
    """Select nominal phone-face dimensions that best fit the whole-phone outline."""
    candidates=[]
    for name,spec in profile.get('surfaces',{}).items():
        if name!='Back' and name not in ('Frame_Left','Frame_Right','Frame_Top','Frame_Bottom'):continue
        width=float(spec.get('width_mm') or 0);height=float(spec.get('height_mm') or 0)
        if width>0 and height>0:candidates.append((name,spec,max(width,height)/min(width,height)))
    contours,_=cv2.findContours(mask.astype(np.uint8),cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)
    if not candidates or not contours:return None
    sides=sorted(cv2.minAreaRect(max(contours,key=cv2.contourArea))[1],reverse=True)
    if sides[1]<=0:return None
    observed=sides[0]/sides[1]
    name,spec,expected=min(candidates,key=lambda row:abs(np.log(max(observed,1e-6)/row[2])))
    if abs(np.log(max(observed,1e-6)/expected))>np.log(3):return None
    return name,spec


def phone_profile(config,resolve):
    model=config.get('phone_model','').strip()
    if not model:raise ValueError('Enter phone_model to identify the inspected device.')
    if config.get('phone_profile'):
        profile=json.loads(resolve(config['phone_profile']).read_text(encoding='utf-8'))
        from .phone_specs import normalized
        expected=normalized(config.get('phone_brand','')+' '+model)
        if config.get('phone_brand') and profile.get('brand') and normalized(config['phone_brand'])!=normalized(profile['brand']):
            raise ValueError('Phone profile/brand mismatch.')
        if normalized(profile.get('phone_model','')) not in (normalized(model),expected):raise ValueError('Phone profile/model mismatch.')
        return attach_market_price(
            profile, config.get('phone_brand', profile.get('brand', '')),
            model, config, resolve
        )
    catalog=json.loads(Path(__file__).with_name('phone_profiles.json').read_text())
    for row in catalog['profiles']:
        if row['phone_model'].casefold()==model.casefold() and (not config.get('phone_brand') or
                row.get('brand','').casefold()==config['phone_brand'].casefold()):
            return attach_market_price(
                row, config.get('phone_brand', row.get('brand', '')),
                model, config, resolve
            )
    if config.get('phone_brand'):
        from .phone_specs import PHONE_SPECS_API_BASE,lookup
        options=config.get('phone_specs',{})
        profile = lookup(config['phone_brand'],model,
            catalog_path=resolve(options['catalog']) if options.get('catalog') else None,
            api_base=options.get('api_base') or PHONE_SPECS_API_BASE,slug=options.get('slug'))
        return attach_market_price(profile, config['phone_brand'], model, config, resolve)
    from .phone_specs import _average_catalog_profile
    profile = _average_catalog_profile('', model, reason='No phone brand was provided for TechAPI lookup.')
    return attach_market_price(profile, '', model, config, resolve)


def run(inspection_path,output_dir,matcher=None,predictor=None,overrides=None):
    inspection_path=Path(inspection_path).resolve();base=inspection_path.parent
    config=json.loads(inspection_path.read_text(encoding='utf-8'))
    config.update(overrides or {})
    def resolve(name):
        path=Path(name);return path.resolve() if path.is_absolute() else (base/path).resolve()
    threshold=float(config.get('confidence_threshold',.3))
    if not 0<threshold<1:raise ValueError('confidence_threshold must be in (0,1).')
    profile=phone_profile(config,resolve)
    output=Path(output_dir).resolve()
    if output.exists():raise FileExistsError('Choose a new inspection output directory to preserve earlier evidence.')
    output.mkdir(parents=True)
    (output/'inspection_input.json').write_text(json.dumps(config,indent=2),encoding='utf-8')
    (output/'phone_profile.json').write_text(json.dumps(profile,indent=2),encoding='utf-8')
    segmenter=PartSegmenter(config.get('part_segmentation',{}),resolve)
    matcher=matcher or LibraryMatcher(config.get('matching',{}))
    predictor=predictor or DefectPredictor(config.get('defect_model',{}),resolve,threshold)
    images={};surfaces={};observations=[];review=[]
    if profile.get('generic_fallback'):
        review.append({
            'reason':'generic_phone_dimensions_used',
            'sample_count':profile.get('fallback_sample_count'),
            'dimensions_method':profile.get('dimensions_method'),
        })
    device_ids={row.get('device_id',config.get('device_id','one_phone')) for row in config['images']}
    if len(device_ids)!=1:raise ValueError('Use one physical phone per inspection; different device IDs cannot be consolidated.')
    for number,spec in enumerate(config['images']):
        image_id=safe_id(spec.get('id',f'image_{number+1:03d}'))
        if image_id in images:raise ValueError('Image IDs must be unique.')
        source=resolve(spec['path']);rgb=load_rgb(source);folder=output/image_id;folder.mkdir()
        # Byte-exact original and separate EXIF-normalized analysis image are both retained.
        original=folder/('original'+source.suffix.lower());shutil.copy2(source,original)
        oriented=folder/'oriented.png';Image.fromarray(rgb).save(oriented)
        image={'id':image_id,'source_path':str(source),'original_path':str(original),
               'analysis_image_path':str(oriented),'sha256':digest(source),'rgb':rgb,
               'quality':image_quality(rgb),'surface_ids':[],'raw_predictions':[]}
        images[image_id]=image
        if not image['quality']['acceptable']:review.append({'image_id':image_id,'reason':'image_quality_insufficient'})
        occupied=np.zeros(rgb.shape[:2],bool)
        surface_specs=spec.get('surfaces') or segmenter.propose(rgb,spec.get('capture_view'))
        for surface_spec in surface_specs:
            sid=safe_id(surface_spec['id']);part=surface_spec['part']
            allowed_parts=('Phone',) if config.get('part_segmentation',{}).get('mode')=='whole_phone_outline' else ('Screen','Back','Frame')
            if part not in allowed_parts:raise ValueError(f'Surface part must be one of {allowed_parts}.')
            key=(image_id,sid)
            if key in surfaces:raise ValueError('Surface IDs must be unique within an image.')
            if '_mask' in surface_spec:
                mask,method=surface_spec['_mask'],surface_spec['_method']
                surface_spec={k:v for k,v in surface_spec.items() if not k.startswith('_')}
            else:mask,method=segmenter.segment(rgb,surface_spec)
            if not mask.any():raise ValueError('Part segmentation produced an empty mask.')
            if (occupied&mask).any():raise ValueError('Part/facet masks overlap. Review boundaries before measuring coverage.')
            occupied |= mask
            surface={**surface_spec,'mask':mask,'image_id':image_id,'method':method,'valid_part':True}
            if not surface.get('reviewed'):review.append({'image_id':image_id,'surface_id':sid,'reason':'part_boundary_not_reviewed'})
            dimensions=profile.get('surfaces',{}).get(sid,{})
            if part=='Phone' and sid=='Phone_Outline':
                inferred=infer_outline_dimensions(mask,profile)
                if inferred:
                    surface['scale_reference']=inferred[0]
                    dimensions=inferred[1]
                    review.append({'image_id':image_id,'surface_id':sid,'reason':'whole_phone_outline_scale_estimated',
                                   'scale_reference':inferred[0]})
            elif part=='Frame' and sid=='Frame_Unknown':
                inferred=infer_frame_facet(mask,profile)
                if inferred:
                    surface['facet_estimate']=inferred[0]
                    surface['planar']=True
                    dimensions=inferred[1]
                    review.append({'image_id':image_id,'surface_id':sid,'reason':'frame_facet_inferred_from_mask_shape',
                                   'estimated_facet':inferred[0]})
            if not surface.get('calibration') and surface.get('planar') and config.get('part_segmentation',{}).get('estimate_metric_from_outline',False):
                estimated=estimate_calibration(mask,dimensions)
                if estimated:surface['calibration']=estimated
            surface['metric']=calibration(surface,dimensions)
            dimension_status=profile.get('surfaces',{}).get(sid,{}).get('dimension_status')
            if surface['metric'] and dimension_status=='nominal_rectangle_estimate':
                review.append({'image_id':image_id,'surface_id':sid,'reason':'metric_dimensions_are_nominal_estimates'})
            if surface['metric'] and surface['metric'].get('estimated'):
                review.append({'image_id':image_id,'surface_id':sid,'reason':'automatic_metric_geometry_is_approximate'})
            surface['mask_path']=str(folder/f'part_{sid}.png');save_mask(mask,Path(surface['mask_path']))
            surfaces[key]=surface;image['surface_ids'].append(sid)
        if spec.get('prediction_json'):
            raw_result=json.loads(resolve(spec['prediction_json']).read_text(encoding='utf-8'))
            prediction_base=resolve(spec['prediction_json']).parent
        elif 'predictions' in spec:
            raw_result={'image_status':'processed','defects':spec['predictions']};prediction_base=base
        else:
            raw_result=predictor.predict(source,folder/'predictions');prediction_base=base
        (folder/'original_predictions.json').write_text(json.dumps(raw_result,indent=2),encoding='utf-8')
        if raw_result.get('image_status','processed')!='processed':
            review.append({'image_id':image_id,'reason':'defect_predictions_withheld_or_unreliable'})
        collected=[]
        for index,prediction in enumerate(raw_result.get('defects',[])):
            confidence=float(prediction['confidence'])
            if not np.isfinite(confidence) or not 0<=confidence<=1:raise ValueError('Invalid prediction confidence.')
            class_name=prediction['class_name']
            if class_name not in CLASSES:raise ValueError(f'Unknown defect class {class_name}.')
            name=prediction.get('mask_path') or prediction.get('mask')
            if not name:raise ValueError('Every prediction requires its binary mask.')
            path=Path(name)
            if not path.is_absolute():
                candidate=prediction_base/path
                path=candidate if candidate.exists() else resolve(name)
            mask=read_mask(path,rgb.shape[:2]);raw_id=f'{image_id}_raw_{index+1:03d}'
            mask_path=folder/f'{raw_id}.png';save_mask(mask,mask_path)
            raw={**prediction,'id':raw_id,'confidence':confidence,'mask_path':str(mask_path),
                 'above_threshold':confidence>=threshold,'area_pixels':int(mask.sum())}
            image['raw_predictions'].append(raw)
            if confidence<threshold or not mask.any():continue
            part=class_name.split('_',1)[0]
            outline_mode=config.get('part_segmentation',{}).get('mode')=='whole_phone_outline'
            candidates=[s for (im,_),s in surfaces.items() if im==image_id and
                        (s['part']==part or outline_mode and s['id']=='Phone_Outline')]
            candidates.sort(key=lambda s:int((s['mask']&mask).sum()),reverse=True)
            if outline_mode and candidates:
                # The class prefix identifies Frame/Back/Screen; the whole-phone
                # outline supplies scale without requiring a separate part mask.
                surface=candidates[0]
            elif not candidates or not (candidates[0]['mask']&mask).any():
                sid='Unassigned_'+part;key=(image_id,sid)
                if key not in surfaces:
                    surfaces[key]={'id':sid,'part':part,'mask':np.ones(mask.shape,bool),'reviewed':False,
                        'complete':False,'planar':False,'valid_part':False,'metric':None,'image_id':image_id}
                surface=surfaces[key]
                review.append({'observation_ids':[raw_id],'reason':'defect_not_assigned_to_valid_phone_part'})
            else:
                surface=candidates[0]
                if sum(bool((s['mask']&mask).any()) for s in candidates)>1:
                    review.append({'observation_ids':[raw_id],'reason':'defect_spans_multiple_frame_facets'})
            collected.append({'id':raw_id,'image_id':image_id,'surface_id':surface['id'],'part':part,
                'class_name':class_name,'confidence':confidence,'mask':mask,
                'complete_override':prediction.get('complete')})
        merged=merge_overlapping(collected)
        all_masks=union([o['mask'] for o in merged],rgb.shape[:2])
        for index,item in enumerate(merged):
            item['id']=f'{image_id}_obs_{index+1:03d}'
            surface=surfaces[(image_id,item['surface_id'])]
            item['features']=features(rgb,item['mask'],surface,all_masks,surface['metric'],item['confidence'],item.get('complete_override'))
            if config.get('part_segmentation',{}).get('mode')=='whole_phone_outline':
                item['features']['measurement']=measured(item['mask'],np.ones(item['mask'].shape,bool),surface['metric'])
                item['features']['measurement']['coverage']=None
                item['features']['measurement']['coverage_scope']='whole_part_spec_estimate'
            if not surface['valid_part']:
                item['features']['measurement'].update(coverage=None,surface_area_pixels=None)
            item['features']['measurement']['whole_part_coverage_estimate']=nominal_part_coverage(
                item['features']['measurement'],item['part'],profile)
            item['features']['measurement']['whole_part_area_cm2_estimate']=profile.get('nominal_areas_cm2',{}).get(item['part'])
            item['mask_path']=str(folder/(item['id']+'.png'));save_mask(item['mask'],Path(item['mask_path']))
            observations.append(item)
    if not images:raise ValueError('Inspection requires at least one image.')
    groups,registrations,matching_review=group_observations(observations,images,surfaces,matcher,config.get('matching',{}))
    review+=matching_review;uniques=[]
    (output/'unique_defects').mkdir()
    for index,group in enumerate(groups):
        def rank(obs):
            reliability=[r.get('inlier_ratio',0) for key,r in registrations.items()
                         if r['reliable'] and obs['image_id'] in key[:2] and key[2]==obs['surface_id']]
            score=obs['features']['selection_score']+.1*(max(reliability) if reliability else (1 if len(group)==1 else 0))
            return (obs['features']['sufficiently_complete'],score)
        primary=max(group,key=rank);final_mask=primary['mask'].copy();method='primary_observation'
        part=surfaces[(primary['image_id'],primary['surface_id'])]
        if not primary['features']['sufficiently_complete'] and len(group)>1 and config.get('combine_complementary',False):
            candidates=[final_mask];safe=True
            for other in group:
                if other is primary:continue
                reg=registration_for(other,primary,images,surfaces,matcher,config.get('matching',{}),registrations)
                if not reg['reliable']:safe=False;break
                contours,_=cv2.findContours(other['mask'].astype(np.uint8),cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)
                points=np.concatenate(contours).reshape(-1,2);mapped=transform(points,reg['H'])
                h,w=final_mask.shape
                fits=((mapped[:,0]>=0)&(mapped[:,0]<w)&(mapped[:,1]>=0)&(mapped[:,1]<h)).mean()
                projected=warp(other['mask'],reg['H'],final_mask.shape)
                retention=float((projected&part['mask']).sum()/max(1,projected.sum()))
                if fits<.95 or retention<.95:safe=False;break
                candidates.append(projected)
            if safe:final_mask=union(candidates,final_mask.shape);method='registered_binary_union'
            else:review.append({'observation_ids':[o['id'] for o in group],'reason':'unsafe_complementary_union_rejected'})
        outline_mode=config.get('part_segmentation',{}).get('mode')=='whole_phone_outline'
        if not outline_mode:final_mask &= part['mask']
        measurement=measured(final_mask,np.ones(final_mask.shape,bool),part['metric']) if outline_mode else measured(
            final_mask,part['mask'],part['metric'])
        measurement['coverage_scope']='whole_part_spec_estimate' if outline_mode else (
            'whole_surface' if part.get('complete') and part.get('reviewed') else 'visible_surface_only')
        if outline_mode:
            measurement['coverage']=None
        if not part['valid_part']:measurement.update(coverage=None,surface_area_pixels=None)
        measurement['whole_part_coverage_estimate']=nominal_part_coverage(measurement,primary['part'],profile)
        measurement['whole_part_area_cm2_estimate']=profile.get('nominal_areas_cm2',{}).get(primary['part'])
        visual=primary['features']['appearance']
        severity_measurement=measurement
        if outline_mode and measurement['whole_part_coverage_estimate'] is not None:
            severity_measurement={**measurement,'coverage':measurement['whole_part_coverage_estimate']}
        rating=severity(severity_measurement,visual,config.get('severity_rubric'))
        if not part.get('complete') or not part.get('reviewed'):rating['requires_review']=True
        uid=f'Defect{index+1:03d}';mask_path=output/'unique_defects'/f'{uid}.png';save_mask(final_mask,mask_path)
        if not primary['features']['sufficiently_complete']:
            review.append({'unique_defect_id':uid,'reason':'complete_defect_extent_not_established'})
        if rating['requires_review']:review.append({'unique_defect_id':uid,'reason':'appearance_or_surface_measurement_uncertain'})
        record={'id':uid,'class_name':primary['class_name'],'part':primary['part'],'surface_id':primary['surface_id'],
            'source_image_ids':sorted({o['image_id'] for o in group}),'observation_ids':[o['id'] for o in group],
            'primary_observation_id':primary['id'],'reference_image_id':primary['image_id'],
            'measurement_method':method,'measurement':measurement,'appearance':visual,'severity':rating,
            'appearance_source_observation_id':primary['id'],'mask_path':str(mask_path),'mask':final_mask,
            'sufficiently_complete':primary['features']['sufficiently_complete']}
        uniques.append(record)
        for obs in group:obs['unique_defect_id']=uid
    summary=aggregate(uniques,images,surfaces,matcher,registrations,config,review,output,profile)
    # Global grade is a transparent cosmetic heuristic, never a functional safety verdict.
    ordinals=[u['severity']['ordinal'] for u in uniques if u['severity']['ordinal'] is not None]
    worst=max(ordinals,default=0);letter='ABCD'[worst]
    report={'schema_version':1,'phone_model':config['phone_model'],'phone_profile':profile,
        'coverage_method':'whole_phone_outline_estimate' if config.get('part_segmentation',{}).get('mode')=='whole_phone_outline' else 'part_surface_measurement',
        'confidence_threshold':threshold,'matching_backend':config.get('matching',{}).get('backend','lightglue_aliked'),
        'unique_defect_count':len(uniques),'count_status':'provisional_candidates' if review else 'confirmed_in_observed_views',
        'grade':letter if not review else None,'provisional_grade':letter,'grade_requires_review':bool(review),
        'grade_basis':'worst unique cosmetic severity: Low=A, Minor=B, Major=C, Critical=D; unvalidated rubric',
        'physical_depth_measured':False,'review_items':review,'summary':summary,
        'device_id':next(iter(device_ids)),
        'images':[{k:v for k,v in image.items() if k!='rgb'} for image in images.values()],
        'surfaces':[{k:v for k,v in s.items() if k not in ('mask','metric')} for s in surfaces.values()],
        'observations':[{k:v for k,v in o.items() if k!='mask'} for o in observations],
        'unique_defects':[{k:v for k,v in u.items() if k!='mask'} for u in uniques],
        'registrations':[{'source_image_id':k[0],'target_image_id':k[1],'surface_id':k[2],**v} for k,v in registrations.items()],
        'notes':['No areas or lengths are summed across photographs.',
                 ('Whole-phone outline supplies an approximate pixel-to-area scale; part coverage uses nominal API areas.'
                  if config.get('part_segmentation',{}).get('mode')=='whole_phone_outline'
                  else 'Physical cm2 requires reviewed planar calibration; pixels are otherwise reported.'),
                 'Weak/Moderate/Strong describes appearance contrast, not measured depth.',
                 'Uncertain identities remain separate and may overcount pending review.']}
    model=config.get('defect_model',{});report['model_provenance']=dict(model)
    if model.get('checkpoint') and resolve(model['checkpoint']).is_file():report['model_provenance']['checkpoint_sha256']=digest(resolve(model['checkpoint']))
    (output/'report.json').write_text(json.dumps(report,indent=2,default=serial,allow_nan=False),encoding='utf-8')
    from .report import write_report
    write_report(report,output)
    return report


def aggregate(uniques,images,surfaces,matcher,registrations,config,review,output,profile):
    summaries=[]
    outline_mode=config.get('part_segmentation',{}).get('mode')=='whole_phone_outline'
    for sid in sorted({sid for (_,sid),s in surfaces.items() if s.get('valid_part') and
                       not (outline_mode and sid=='Phone_Outline')}):
        options=[s for (_,key),s in surfaces.items() if key==sid]
        part_names={s['part'] for s in options}
        if len(part_names)!=1:raise ValueError('A surface ID cannot describe different phone parts across photos.')
        reference=max(options,key=lambda s:(bool(s.get('reviewed') and s.get('complete')),images[s['image_id']]['quality']['score']))
        shape=reference['mask'].shape;reference_id=reference['image_id'];class_masks={};unmapped=[]
        for defect in [d for d in uniques if d['surface_id']==sid]:
            if defect['reference_image_id']==reference_id:mask=defect['mask']
            else:
                a={'image_id':defect['reference_image_id'],'surface_id':sid}
                b={'image_id':reference_id,'surface_id':sid}
                reg=registration_for(a,b,images,surfaces,matcher,config.get('matching',{}),registrations)
                if not reg['reliable']:unmapped.append(defect['id']);continue
                mask=warp(defect['mask'],reg['H'],shape)
            class_masks.setdefault(defect['class_name'],[]).append(mask&reference['mask'])
        all_masks=union([mask for masks in class_masks.values() for mask in masks],shape)
        full=measured(all_masks,reference['mask'],reference['metric'])
        classes={}
        for name in CLASSES:
            if reference['part']!='Phone' and not name.startswith(reference['part']+'_'):continue
            rows=[d for d in uniques if d['surface_id']==sid and d['class_name']==name]
            m=measured(union(class_masks.get(name,[]),shape),reference['mask'],reference['metric'])
            complete=not any(row['id'] in unmapped for row in rows)
            values=[r['severity']['ordinal'] for r in rows if r['severity']['ordinal'] is not None]
            classes[name]={'count':len(rows),'measurement':m,'total_area_cm2':m['area_cm2'] if complete else None,
                'coverage':m['coverage'] if complete else None,'aggregation_complete':complete,
                'mean_severity_ordinal':float(np.mean(values)) if values else None,
                'mean_severity_label':['Low','Minor','Major','Critical'][min(3,int(np.ceil(np.mean(values))))] if values else None}
        if unmapped:review.append({'surface_id':sid,'reason':'surface_summary_cannot_register_all_observations','unique_defect_ids':unmapped})
        complete=bool(reference.get('complete') and reference.get('reviewed') and not unmapped)
        if not complete:review.append({'surface_id':sid,'reason':'whole_surface_coverage_not_established'})
        save_mask(all_masks,output/f'summary_{sid}.png')
        summaries.append({'surface_id':sid,'part':reference['part'],'reference_image_id':reference_id,
            'surface_area_cm2':full['surface_area_cm2'],'surface_area_pixels':full['surface_area_pixels'],
            'measurement':full,'visible_region_coverage':full['coverage'],
            'whole_surface_coverage':full['coverage'] if complete else None,'complete':complete,
            'unmapped_unique_defects':unmapped,'classes':classes,'union_mask_path':str(output/f'summary_{sid}.png')})
    required=[] if outline_mode else profile.get('required_surfaces',config.get('required_surfaces',['Screen','Back','Frame_Left','Frame_Right','Frame_Top','Frame_Bottom']))
    missing=set(required)-{s['surface_id'] for s in summaries}
    if missing:review.append({'reason':'required_surfaces_not_observed','surface_ids':sorted(missing)})
    parts={};class_totals={}
    for name in ('Screen','Back','Frame'):
        rows=[s for s in summaries if s['part']==name]
        if outline_mode:
            defects=[d for d in uniques if d['part']==name]
            areas=[d['measurement'].get('area_cm2') for d in defects]
            damage=sum(areas) if areas and all(value is not None for value in areas) else None
            nominal=profile.get('nominal_areas_cm2',{}).get(name)
            parts[name]={'surface_area_cm2':None,'defect_area_cm2':damage,
                         'coverage':min(1.,damage/nominal) if damage is not None and nominal else None,
                         'surface_ids':[],'nominal_area_cm2_estimate':nominal,
                         'status':'estimated_from_whole_phone_outline' if damage is not None else 'incomplete_or_uncalibrated'}
            continue
        # Sum only disjoint physical facets measured in common physical units.
        calibrated=bool(rows) and all(s['surface_area_cm2'] is not None and s['complete'] for s in rows)
        if name=='Frame' and any(str(s).startswith('Frame') for s in missing):calibrated=False
        area=sum(s['surface_area_cm2'] for s in rows) if calibrated else None
        damage=sum(s['measurement']['area_cm2'] for s in rows) if calibrated else None
        parts[name]={'surface_area_cm2':area,'defect_area_cm2':damage,
                     'coverage':min(1.,damage/area) if area else None,'surface_ids':[s['surface_id'] for s in rows],
                     'nominal_area_cm2_estimate':profile.get('nominal_areas_cm2',{}).get(name),
                     'status':'measured_complete_visible_surfaces' if calibrated else 'incomplete_or_uncalibrated'}
    for name in CLASSES:
        rows=[d for d in uniques if d['class_name']==name];part=name.split('_')[0]
        if outline_mode:
            areas=[d['measurement'].get('area_cm2') for d in rows]
            area=sum(areas) if rows and all(value is not None for value in areas) else None
            nominal=profile.get('nominal_areas_cm2',{}).get(part)
            levels=[d['severity']['ordinal'] for d in rows if d['severity']['ordinal'] is not None]
            class_totals[name]={'count':len(rows),'total_area_cm2':area,
                'coverage':min(1.,area/nominal) if area is not None and nominal else None,
                'mean_severity_ordinal':float(np.mean(levels)) if levels else None,
                'mean_severity_label':['Low','Minor','Major','Critical'][min(3,int(np.ceil(np.mean(levels))))] if levels else None}
            continue
        metrics=[s['classes'][name] for s in summaries if name in s['classes']]
        area_known=parts[part]['surface_area_cm2'] is not None and all(m['total_area_cm2'] is not None for m in metrics)
        area=sum(m['total_area_cm2'] for m in metrics) if area_known else None
        levels=[d['severity']['ordinal'] for d in rows if d['severity']['ordinal'] is not None]
        class_totals[name]={'count':len(rows),'total_area_cm2':area,
            'coverage':min(1.,area/parts[part]['surface_area_cm2']) if area_known else None,
            'mean_severity_ordinal':float(np.mean(levels)) if levels else None,
            'mean_severity_label':['Low','Minor','Major','Critical'][min(3,int(np.ceil(np.mean(levels))))] if levels else None}
    return {'surfaces':summaries,'phone_parts':parts,'classes':class_totals,'missing_surfaces':sorted(missing)}
