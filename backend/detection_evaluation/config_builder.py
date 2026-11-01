"""Build an automatic inspection manifest from user-entered brand/model/photos."""
import json
from pathlib import Path
from .phone_specs import PHONE_SPECS_API_BASE,lookup,lookup_model_code


def prepare(images,brand,model,checkpoint,output,config=None,sam_checkpoint=None,api_base=None,capture_view=None,model_code=None):
    output=Path(output).resolve()
    if output.exists():raise FileExistsError('Inspection configuration already exists; choose another filename.')
    directory=Path(images).resolve()
    paths=sorted(p for p in directory.iterdir() if p.is_file() and p.suffix.lower() in {'.jpg','.jpeg','.png','.webp','.bmp'})
    if not paths:raise ValueError('Image directory contains no supported images.')
    root=Path(__file__).resolve().parent.parent
    checkpoint=Path(checkpoint).resolve()
    if not checkpoint.is_file():raise FileNotFoundError(checkpoint)
    if model_code:
        profile=lookup_model_code(model_code,api_base=api_base or PHONE_SPECS_API_BASE)
        brand=profile.get('brand','')
        model=profile.get('phone_model') or profile.get('model','')
    else:
        profile=lookup(brand,model,api_base=api_base or PHONE_SPECS_API_BASE)
    output.parent.mkdir(parents=True,exist_ok=True)
    profile_path=output.with_suffix('.phone_profile.json')
    if profile_path.exists():raise FileExistsError(profile_path)
    profile_path.write_text(json.dumps(profile,indent=2),encoding='utf-8')
    data={'phone_brand':brand,'phone_model':model,'phone_model_code':model_code,'phone_profile':str(profile_path),
        'confidence_threshold':.3,'combine_complementary':False,
        'defect_model':{'checkpoint':str(checkpoint),'config':str(Path(config).resolve() if config else root/'model2_defect_segmentation/config/config.yaml'),'device':'cpu'},
        'part_segmentation':{'mode':'whole_phone_outline','checkpoint':str(Path(sam_checkpoint).resolve() if sam_checkpoint else root/'detection_evaluation/weights/sam2.1_t.pt'),
            'device':'cpu','detector_model':'IDEA-Research/grounding-dino-tiny','estimate_metric_from_outline':True},
        'matching':{'backend':'lightglue_aliked','device':'cpu','min_inliers':12,'min_inlier_ratio':.65},
        'images':[{'id':f'image_{i+1:03d}','path':str(path)} for i,path in enumerate(paths)]}
    output.write_text(json.dumps(data,indent=2),encoding='utf-8')
    return output
