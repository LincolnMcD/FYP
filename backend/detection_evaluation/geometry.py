"""Mask geometry, calibrated planar measurements and registration gates."""
import cv2
import numpy as np


def union(masks, shape):
    result=np.zeros(shape,bool)
    for mask in masks: result |= np.asarray(mask,bool)
    return result


def mask_iou(a,b):
    intersection=int((a&b).sum()); total=int((a|b).sum())
    return intersection/max(1,total), intersection/max(1,min(int(a.sum()),int(b.sum())))


def warp(mask,H,shape):
    return cv2.warpPerspective(mask.astype(np.uint8),np.asarray(H,float),(shape[1],shape[0]),
                               flags=cv2.INTER_NEAREST,borderMode=cv2.BORDER_CONSTANT)>0


def transform(points,H):
    return cv2.perspectiveTransform(np.asarray(points,np.float32).reshape(-1,1,2),np.asarray(H,float)).reshape(-1,2)


def merge_overlapping(items):
    """Transitive union only when same-class, same-surface masks really intersect."""
    groups=[]
    for item in items:
        hits=[i for i,g in enumerate(groups) if g['class_name']==item['class_name']
              and g['surface_id']==item['surface_id'] and (g['mask']&item['mask']).any()]
        group=dict(item); group['mask']=item['mask'].copy()
        group['raw_ids']=list(item.get('raw_ids',[item['id']]))
        group['confidences']=list(item.get('confidences',[item['confidence']]))
        for i in reversed(hits):
            old=groups.pop(i); group['mask'] |= old['mask']
            group['raw_ids']+=old['raw_ids']; group['confidences']+=old['confidences']
            if old.get('complete_override') is False:group['complete_override']=False
        group['confidence']=max(group['confidences']); groups.append(group)
    return groups


def geometry(mask):
    contours,_=cv2.findContours(mask.astype(np.uint8),cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)
    ys,xs=np.where(mask)
    rect=cv2.minAreaRect(np.column_stack((xs,ys)).astype(np.float32)) if len(xs) else ((0,0),(0,0),0)
    short,long=sorted(rect[1])
    return {'area_pixels':int(mask.sum()),'perimeter_pixels':float(sum(cv2.arcLength(c,True) for c in contours)),
            'major_axis_pixels':float(long),'minor_axis_pixels':float(short),
            'components':int(cv2.connectedComponents(mask.astype(np.uint8))[0]-1)}


def calibration(surface, profile):
    """Four reviewed coplanar correspondences map pixels to a metric plane."""
    data=surface.get('calibration')
    if not data: return None
    if not (data.get('reviewed') or data.get('estimated')) or not surface.get('planar',False):
        raise ValueError('Metric calibration requires reviewed correspondences on a planar surface/facet.')
    width=float(profile.get('width_mm',0)); height=float(profile.get('height_mm',0))
    if width<=0 or height<=0 or not profile.get('source'):
        raise ValueError('Calibrated surfaces require sourced width_mm and height_mm in the phone profile.')
    points=np.asarray(data['image_points'],np.float32)
    if points.shape!=(4,2) or not np.isfinite(points).all() or not cv2.isContourConvex(points):
        raise ValueError('Calibration needs four convex ordered image corners (TL, TR, BR, BL).')
    if abs(cv2.contourArea(points))<25: raise ValueError('Calibration quadrilateral is too small.')
    # Corner coordinates describe a known planar rectangle, not a screen diagonal.
    density=min(float(data.get('pixels_per_mm',5)),2047/max(width,height))
    if density<=0: raise ValueError('pixels_per_mm must be positive.')
    columns=max(1,int(np.ceil(width*density)));rows=max(1,int(np.ceil(height*density)))
    target=np.float32([[-.5,-.5],[columns-.5,-.5],[columns-.5,rows-.5],[-.5,rows-.5]])
    H=cv2.getPerspectiveTransform(points,target)
    return {'H':H,'shape':(rows,columns),'area_per_pixel_mm2':width*height/(rows*columns),
            'axis_pixels_per_mm':np.array([columns/width,rows/height]),
            'pixels_per_mm':density,'source':profile['source'],
            'estimated':bool(data.get('estimated') or profile.get('dimension_status')=='nominal_rectangle_estimate')}


def estimate_calibration(mask,profile):
    if not profile.get('width_mm') or not profile.get('height_mm'):return None
    contours,_=cv2.findContours(mask.astype(np.uint8),cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)
    contour=max(contours,key=cv2.contourArea);hull=cv2.convexHull(contour)
    quad=cv2.approxPolyDP(hull,.02*cv2.arcLength(hull,True),True).reshape(-1,2)
    if len(quad)!=4:quad=cv2.boxPoints(cv2.minAreaRect(contour))
    center=quad.mean(0);quad=quad[np.argsort(np.arctan2(quad[:,1]-center[1],quad[:,0]-center[0]))]
    quad=np.roll(quad,-int(np.argmin(quad.sum(1))),axis=0)
    first=np.linalg.norm(quad[1]-quad[0]);second=np.linalg.norm(quad[2]-quad[1])
    if (profile['height_mm']>profile['width_mm'])==(first>second):quad=np.roll(quad,-1,axis=0)
    return {'reviewed':False,'estimated':True,'image_points':quad.astype(float).tolist(),'pixels_per_mm':5}


def measured(mask,part_mask,metric=None):
    mask=mask&part_mask
    if metric:
        part=warp(part_mask,metric['H'],metric['shape']); defect=warp(mask,metric['H'],metric['shape'])&part
        scale=metric['pixels_per_mm']; stats=geometry(defect)
        pixel_area=metric.get('area_per_pixel_mm2',1/(scale*scale))
        stats.update(area_cm2=stats['area_pixels']*pixel_area/100,
                     surface_area_cm2=float(part.sum())*pixel_area/100,
                     major_axis_mm=stats['major_axis_pixels']/scale,
                     perimeter_mm=stats['perimeter_pixels']/scale,
                     measurement_space='rectified_metric_plane',
                     area_accuracy='approximate_nominal_geometry' if metric.get('estimated') else 'calibrated_from_supplied_reference')
    else:
        part=part_mask; defect=mask; stats=geometry(mask)
        stats.update(area_cm2=None,surface_area_cm2=None,major_axis_mm=None,perimeter_mm=None,
                     measurement_space='image_pixels')
    stats.update(coverage=float(defect.sum()/max(1,part.sum())),surface_area_pixels=int(part.sum()))
    return stats


def register_points(src,dst,source_mask,target_mask,options=None):
    options=options or {}; result={'reliable':False,'reason':'insufficient_correspondences','H':None}
    src=np.asarray(src,np.float32).reshape(-1,2); dst=np.asarray(dst,np.float32).reshape(-1,2)
    minimum=int(options.get('min_inliers',12)); threshold=float(options.get('ransac_pixels',3))
    if len(src)!=len(dst) or len(src)<minimum: return result
    inside=[]
    for a,b in zip(src,dst):
        x,y=np.round(a).astype(int); u,v=np.round(b).astype(int)
        inside.append(0<=y<source_mask.shape[0] and 0<=x<source_mask.shape[1]
                      and 0<=v<target_mask.shape[0] and 0<=u<target_mask.shape[1]
                      and source_mask[y,x] and target_mask[v,u])
    src=src[inside];dst=dst[inside]
    if len(src)<minimum: return result
    H,inliers=cv2.findHomography(src,dst,cv2.RANSAC,threshold,maxIters=5000,confidence=.999)
    if H is None or not np.isfinite(H).all() or abs(np.linalg.det(H))<1e-10:
        result['reason']='degenerate_homography';return result
    flags=inliers.ravel().astype(bool); a=src[flags];b=dst[flags]
    errors=np.linalg.norm(transform(a,H)-b,axis=1)
    inverse_errors=np.linalg.norm(transform(b,np.linalg.inv(H))-a,axis=1)
    source_hull=cv2.convexHull(a);target_hull=cv2.convexHull(b)
    spread=min(abs(cv2.contourArea(source_hull))/max(1,source_mask.sum()),
               abs(cv2.contourArea(target_hull))/max(1,target_mask.sum()))
    result.update(inliers=int(flags.sum()),matches=len(src),inlier_ratio=float(flags.mean()),
                  median_error_pixels=float(np.median(errors)),p95_error_pixels=float(np.percentile(errors,95)),
                  spatial_support=float(spread))
    result['inverse_median_error_pixels']=float(np.median(inverse_errors))
    if flags.sum()<minimum or flags.mean()<float(options.get('min_inlier_ratio',.65)):
        result['reason']='too_many_outliers';return result
    if (max(np.median(errors),np.median(inverse_errors))>float(options.get('max_median_error',2))
            or max(np.percentile(errors,95),np.percentile(inverse_errors,95))>threshold*2):
        result['reason']='large_reprojection_error';return result
    if spread<float(options.get('min_spatial_support',.05)):
        result['reason']='matches_too_concentrated';return result
    ys,xs=np.where(source_mask);cx=float(xs.mean());cy=float(ys.mean())
    probes=np.float32([[cx,cy],[cx+1,cy],[cx,cy+1]])
    mapped=transform(probes,H);J=np.column_stack((mapped[1]-mapped[0],mapped[2]-mapped[0]))
    singular=np.linalg.svd(J,compute_uv=False)
    # Reject reflections, near-singular transforms and extreme local foreshortening.
    if np.linalg.det(J)<=0 or singular[-1]<.1 or singular[0]>10 or singular[0]/singular[-1]>5:
        result['reason']='implausible_local_geometry';return result
    corners=np.float32([[xs.min(),ys.min()],[xs.max(),ys.min()],[xs.max(),ys.max()],[xs.min(),ys.max()]])
    denominators=np.column_stack((corners,np.ones(4)))@H[2]
    if np.min(np.abs(denominators))<1e-6 or np.min(denominators)*np.max(denominators)<=0:
        result['reason']='projective_horizon_crosses_surface';return result
    transformed=warp(source_mask,H,target_mask.shape)
    _,containment=mask_iou(transformed,target_mask)
    if containment<float(options.get('min_surface_overlap',.5)):
        result['reason']='surface_misalignment';return result
    result.update(reliable=True,reason='passed',H=H,source_hull=source_hull.reshape(-1,2),
                  target_hull=target_hull.reshape(-1,2))
    return result
