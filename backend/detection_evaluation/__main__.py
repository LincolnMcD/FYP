import argparse
import json
from pathlib import Path
from .inspection import run


def main():
    parser=argparse.ArgumentParser(description='Conservative multi-photo phone defect inspection.')
    parser.add_argument('--inspection',help='Inspection JSON with phone model, photos, parts and model checkpoint.')
    parser.add_argument('--output',help='New evidence/report folder.')
    parser.add_argument('--demo',action='store_true',help='Generate and evaluate synthetic fixtures; no model downloads.')
    parser.add_argument('--matching-backend',choices=['lightglue_aliked','sift','provided'])
    parser.add_argument('--prepare-images',help='Create automatic inspection JSON from an image directory.')
    parser.add_argument('--lookup-phone',action='store_true',help='Write a sourced brand/model profile JSON.')
    parser.add_argument('--brand');parser.add_argument('--model');parser.add_argument('--checkpoint')
    parser.add_argument('--config');parser.add_argument('--sam-checkpoint');parser.add_argument('--phone-api')
    args=parser.parse_args()
    if not args.output:parser.error('--output is required')
    if args.prepare_images or args.lookup_phone:
        if not args.brand or not args.model:parser.error('--brand and --model are required')
        if args.lookup_phone:
            from .phone_specs import PHONE_SPECS_API_BASE,lookup
            profile=lookup(args.brand,args.model,api_base=args.phone_api or PHONE_SPECS_API_BASE)
            path=Path(args.output)
            if path.exists():raise FileExistsError(path)
            path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(profile,indent=2),encoding='utf-8')
            print(path.resolve());return
        if not args.checkpoint:parser.error('--checkpoint is required for preparation')
        from .config_builder import prepare
        print(prepare(args.prepare_images,args.brand,args.model,args.checkpoint,args.output,
                      args.config,args.sam_checkpoint,args.phone_api));return
    if args.demo:
        from .demo import create_demo
        source=create_demo(Path(args.output).resolve().with_name(Path(args.output).name+'_inputs'))
    elif args.inspection:source=Path(args.inspection)
    else:parser.error('Provide --inspection or --demo')
    original=json.loads(Path(source).read_text(encoding='utf-8'))
    overrides={'matching':{**original.get('matching',{}),'backend':args.matching_backend}} if args.matching_backend else None
    result=run(source,args.output,overrides=overrides)
    print(json.dumps({'report':str(Path(args.output).resolve()/'report.html'),
                      'defect_ids':result['unique_defect_count'],'grade':result['grade'],
                      'provisional_grade':result['provisional_grade'],'review_items':len(result['review_items'])},indent=2))


if __name__=='__main__':main()
