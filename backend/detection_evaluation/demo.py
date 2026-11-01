"""Deterministic synthetic evidence fixture. No real-phone accuracy claims."""
import json
from pathlib import Path
import cv2
import numpy as np
from PIL import Image


def create_demo(folder):
    folder=Path(folder).resolve()
    if folder.exists():raise FileExistsError('Demo input folder already exists; use a new output name.')
    folder.mkdir(parents=True)
    rng=np.random.default_rng(42)
    rgb=np.clip(rng.normal(140,8,(340,260,3)),0,255).astype(np.uint8)
    part=np.zeros((340,260),np.uint8);part[25:315,30:230]=255
    crack=np.zeros_like(part);crack[90:235,110:114]=255
    rgb[crack>0]=[70,75,80]
    H=np.float32([[1,0,8],[0,1,5]])
    Image.fromarray(rgb).save(folder/'screen_a.png')
    Image.fromarray(cv2.warpAffine(rgb,H,(260,340),borderMode=cv2.BORDER_REFLECT)).save(folder/'screen_b.png')
    Image.fromarray(part).save(folder/'screen_part_a.png')
    Image.fromarray(cv2.warpAffine(part,H,(260,340))).save(folder/'screen_part_b.png')
    a=crack.copy();a[180:]=0;b=crack.copy();b[:150]=0
    for name,mask in [('crack_a1',a),('crack_a2',b),('crack_b',cv2.warpAffine(crack,H,(260,340)))]:
        Image.fromarray(mask).save(folder/(name+'.png'))
    back=rgb.copy();backmask=np.zeros_like(part);backmask[180:185,150:185]=255;back[backmask>0]=[90,90,90]
    Image.fromarray(back).save(folder/'back.png');Image.fromarray(backmask).save(folder/'back_scratch.png')
    profile={'phone_model':'Synthetic demonstration device','required_surfaces':['Screen','Back','Frame_Left','Frame_Right','Frame_Top','Frame_Bottom'],
             'surfaces':{name:{'width_mm':60,'height_mm':120,'source':'synthetic calibrated fixture; not a real phone'} for name in ('Screen','Back')}}
    (folder/'profile.json').write_text(json.dumps(profile,indent=2))
    corners=[[30,25],[229,25],[229,314],[30,314]]
    def surface(name,mask,offset=0):
        return {'id':name,'part':name,'mask':mask,'reviewed':True,'complete':True,'planar':True,
                'calibration':{'reviewed':True,'pixels_per_mm':3,
                               'image_points':[[x+(8 if offset else 0),y+(5 if offset else 0)] for x,y in corners]}}
    points=[[x,y] for y in (45,100,155,210,285) for x in (45,85,135,180,215)]
    config={'phone_model':profile['phone_model'],'phone_profile':'profile.json','confidence_threshold':.3,
        'combine_complementary':True,'matching':{'backend':'provided','correspondences':{
            'screen_a|screen_b':{'source':points,'target':[[x+8,y+5] for x,y in points]}}},
        'images':[
            {'id':'screen_a','path':'screen_a.png','surfaces':[surface('Screen','screen_part_a.png')],
             'predictions':[{'class_name':'Screen_Crack','confidence':.94,'mask':'crack_a1.png'},
                            {'class_name':'Screen_Crack','confidence':.91,'mask':'crack_a2.png'}]},
            {'id':'screen_b','path':'screen_b.png','surfaces':[surface('Screen','screen_part_b.png',1)],
             'predictions':[{'class_name':'Screen_Crack','confidence':.89,'mask':'crack_b.png'}]},
            {'id':'back','path':'back.png','surfaces':[surface('Back','screen_part_a.png')],
             'predictions':[{'class_name':'Back_Scratch','confidence':.82,'mask':'back_scratch.png'}]}]}
    path=folder/'inspection.json';path.write_text(json.dumps(config,indent=2))
    return path
