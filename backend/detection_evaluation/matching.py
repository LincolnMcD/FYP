"""Conservative identity assignment: geometry plus same-class mask agreement."""
import cv2
import numpy as np
from .geometry import mask_iou,warp,register_points,transform


def registration_for(a,b,images,surfaces,matcher,options,cache):
    key=(a['image_id'],b['image_id'],a['surface_id'])
    if key in cache:return cache[key]
    reverse=(b['image_id'],a['image_id'],a['surface_id'])
    if reverse in cache:
        old=cache[reverse];result=dict(old)
        if old['reliable']:
            result['H']=np.linalg.inv(old['H']);result['source_hull']=old['target_hull'];result['target_hull']=old['source_hull']
        cache[key]=result;return result
    sa=surfaces[(a['image_id'],a['surface_id'])];sb=surfaces[(b['image_id'],b['surface_id'])]
    if not sa.get('planar') or not sb.get('planar'):
        result={'reliable':False,'reason':'surface_not_declared_planar','H':None}
    else:
        src,dst=matcher.points(a['image_id'],images[a['image_id']]['rgb'],b['image_id'],images[b['image_id']]['rgb'])
        result=register_points(src,dst,sa['mask'],sb['mask'],options)
        if result['reliable'] and sa.get('metric') and sb.get('metric'):
            # Independent metric calibrations must agree with feature registration.
            probe=np.asarray(result['source_hull'],np.float32)
            p=(transform(probe,sa['metric']['H'])+.5)/sa['metric']['axis_pixels_per_mm']
            q=(transform(transform(probe,result['H']),sb['metric']['H'])+.5)/sb['metric']['axis_pixels_per_mm']
            error=float(np.median(np.linalg.norm(p-q,axis=1)))
            result['calibration_disagreement_mm']=error
            if error>float(options.get('max_calibration_disagreement_mm',2)):
                result.update(reliable=False,reason='metric_calibrations_disagree',H=None)
    cache[key]=result;return result


def defect_agreement(a,b,registration,options):
    if not registration['reliable']: return False,0.,registration['reason']
    projected=warp(a['mask'],registration['H'],b['mask'].shape)
    iou,containment=mask_iou(projected,b['mask'])
    ratio=max(projected.sum(),b['mask'].sum())/max(1,min(projected.sum(),b['mask'].sum()))
    ys,xs=np.where(b['mask'])
    if not len(xs): return False,0.,'empty_mask'
    # Avoid extrapolating a plausible global transform into unsupported damage regions.
    hull=np.asarray(registration['target_hull'],np.float32)
    contours,_=cv2.findContours(b['mask'].astype(np.uint8),cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)
    points=np.concatenate(contours).reshape(-1,2)
    supported=(cv2.pointPolygonTest(hull,(float(xs.mean()),float(ys.mean())),True)>=-3 and
               np.mean([cv2.pointPolygonTest(hull,(float(x),float(y)),True)>=-3 for x,y in points])>=.9)
    enough=(iou>=float(options.get('mask_iou',.5)) or
            containment>=float(options.get('mask_containment',.8)) and ratio<=3)
    return bool(enough and supported),float(iou),('confirmed' if enough and supported else 'mask_or_local_support_uncertain')


def group_observations(observations,images,surfaces,matcher,options):
    cache={};edges={};reviews=[]
    for i,a in enumerate(observations):
        for j in range(i+1,len(observations)):
            b=observations[j]
            if a['image_id']==b['image_id'] or a['class_name']!=b['class_name'] or a['surface_id']!=b['surface_id']:continue
            reg=registration_for(a,b,images,surfaces,matcher,options,cache)
            confirmed,score,reason=defect_agreement(a,b,reg,options)
            edges[(i,j)]={'confirmed':confirmed,'score':score,'reason':reason}
            if not reg['reliable'] or (not confirmed and score>.05):
                reviews.append({'observation_ids':[a['id'],b['id']],'reason':reason})
    for i,a in enumerate(observations):
        for b in observations[i+1:]:
            if a['image_id']==b['image_id'] or a['surface_id']!=b['surface_id'] or a['class_name']==b['class_name']:continue
            reg=registration_for(a,b,images,surfaces,matcher,options,cache)
            if reg['reliable'] and mask_iou(warp(a['mask'],reg['H'],b['mask'].shape),b['mask'])[0]>=.5:
                reviews.append({'observation_ids':[a['id'],b['id']],'reason':'conflicting_classes_at_same_registered_location'})
    # If one observation maps to several candidates in the same other photo,
    # keep every such identity ambiguous instead of choosing by tiny score differences.
    for i,a in enumerate(observations):
        by_image={}
        for (x,y),edge in edges.items():
            if not edge['confirmed'] or i not in (x,y):continue
            other=y if x==i else x
            by_image.setdefault(observations[other]['image_id'],[]).append((x,y))
        for keys in by_image.values():
            if len(keys)>1:
                for key in keys:edges[key]['confirmed']=False
                reviews.append({'observation_ids':[a['id']],'reason':'ambiguous_many_to_one_match'})
    groups=[]
    for i,a in enumerate(observations):
        fits=[g for g in groups if all(observations[j]['image_id']!=a['image_id'] and
              edges.get(tuple(sorted((i,j))),{}).get('confirmed',False) for j in g)]
        if len(fits)==1:fits[0].append(i)
        else:
            groups.append([i])
            if len(fits)>1:reviews.append({'observation_ids':[a['id']],'reason':'ambiguous_group_identity'})
    return [[observations[i] for i in g] for g in groups],cache,reviews
