"""Portable HTML and CSV inspection reports with per-image evidence links."""
import csv
import html
from pathlib import Path
import cv2
import numpy as np
from PIL import Image


def number(value,digits=3):return '—' if value is None else f'{value:.{digits}f}'
def esc(value):return html.escape(str(value))


def write_report(report,output):
    output=Path(output)
    phone_profile=report.get('phone_profile') or {}
    whole_outline=report.get('coverage_method')=='whole_phone_outline_estimate'
    def link(path):return esc(Path(path).resolve().relative_to(output).as_posix())
    def area(m):
        prefix='≈ ' if m.get('area_accuracy')=='approximate_nominal_geometry' else ''
        return prefix+number(m['area_cm2'])+' cm²' if m['area_cm2'] is not None else str(m['area_pixels'])+' px² (no image scale)'
    def coverage(value):return '—' if value is None else f'{value*100:.2f}%'
    def nominal_coverage(m):
        value=m.get('whole_part_coverage_estimate')
        return '— (phone-outline scale unavailable)' if value is None else f'≈ {value*100:.2f}%'
    def apparent_depth(appearance):
        cue=appearance.get('apparent_depth_cue',appearance.get('intensity','unknown'))
        delta=appearance.get('delta_e76')
        if cue=='unknown':return 'Unknown'
        suffix=f', ΔE {number(delta,1)}' if delta is not None else ''
        return esc(cue)+' (contrast cue'+suffix+')'
    observations={o['id']:o for o in report['observations']}
    sections=[]
    for image in report['images']:
        with Image.open(image['analysis_image_path']) as im:rgb=np.asarray(im.convert('RGB')).copy()
        rows=[]
        for obs in report['observations']:
            if obs['image_id']!=image['id']:continue
            mask=np.asarray(Image.open(obs['mask_path']).convert('L'))>0
            rgb[mask]=(.5*rgb[mask]+.5*np.array([255,70,40])).astype(np.uint8)
            ys,xs=np.where(mask)
            if len(xs):cv2.putText(rgb,obs['unique_defect_id'],(int(xs.min()),max(15,int(ys.min()))),cv2.FONT_HERSHEY_SIMPLEX,.5,(255,220,0),1)
            f=obs['features'];m=f['measurement']
            visible_cell='' if whole_outline else f'<td>{coverage(m["coverage"])}</td>'
            rows.append(f'<tr><td>{esc(obs["unique_defect_id"])}</td><td>{esc(obs["class_name"])}</td>'
                f'<td>{number(obs["confidence"])}</td><td>{area(m)}</td>{visible_cell}'
            f'<td>{nominal_coverage(m)}</td><td>{apparent_depth(f["appearance"])}</td><td><a href="{link(obs["mask_path"])}">Merged observation mask</a></td></tr>')
        overlay=Path(image['analysis_image_path']).with_name('inspection_overlay.png');Image.fromarray(rgb).save(overlay)
        raw=''.join(f'<li>{esc(r["id"])} — {esc(r["class_name"])}; confidence {number(r["confidence"])}; '
                    f'{"collected" if r["above_threshold"] else "below threshold"}; '
                    f'<a href="{link(r["mask_path"])}">original prediction mask</a></li>' for r in image['raw_predictions'])
        sections.append(f'<section><h3>{esc(image["id"])}</h3><div class="photos"><a href="{link(image["original_path"])}"><img src="{link(image["analysis_image_path"])}" alt="Original image"></a>'
            f'<img src="{link(overlay)}" alt="Defect ID overlay"></div><p>Sharpness: {number(image["quality"]["sharpness"])}; image-quality acceptable: {image["quality"]["acceptable"]}.</p>'
            '<table><tr><th>Unique ID</th><th>Class</th><th>Confidence</th><th>Per-image area</th>'
            +('' if whole_outline else '<th>Visible-part coverage</th>')
            +'<th>Whole-part coverage (spec estimate)</th><th>Relative visual-depth cue</th><th>Evidence</th></tr>'
            +''.join(rows)+'</table><details><summary>Every raw prediction and confidence</summary><ul>'+raw+'</ul></details></section>')
    unique_rows=[];csv_rows=[]
    for row in report['unique_defects']:
        m=row['measurement'];primary=observations[row['primary_observation_id']]
        visible_cell='' if whole_outline else f'<td>{coverage(m["coverage"])}</td>'
        unique_rows.append(f'<tr><td>{esc(row["id"])}</td><td>{esc(row["class_name"])}</td><td>{area(m)}</td>'
            f'{visible_cell}<td>{nominal_coverage(m)}</td><td>{apparent_depth(row["appearance"])}</td>'
            f'<td>{esc(row["severity"]["label"])}</td><td>{esc(row["measurement_method"])}</td>'
            f'<td>{esc(", ".join(row["source_image_ids"]))}</td><td>{esc(row["primary_observation_id"])}</td>'
            f'<td><a href="{link(row["mask_path"])}">Final mask</a></td></tr>')
        csv_rows.append({'id':row['id'],'class':row['class_name'],'part':row['part'],'surface_id':row['surface_id'],
            'area_cm2':m['area_cm2'],'area_pixels':m['area_pixels'],'coverage':m['coverage'],
            'whole_part_coverage_estimate':m.get('whole_part_coverage_estimate'),
            'intensity':row['appearance']['intensity'],'apparent_depth_cue':row['appearance'].get('apparent_depth_cue',row['appearance']['intensity']),
            'severity':row['severity']['label'],'source_image_ids':';'.join(row['source_image_ids']),
            'primary_observation_id':row['primary_observation_id'],'measurement_method':row['measurement_method']})
    class_rows=''.join(f'<tr><td>{esc(k)}</td><td>{v["count"]}</td><td>{number(v["total_area_cm2"])}</td>'
        f'<td>{coverage(v["coverage"])}</td><td>{esc(v["mean_severity_label"] or "—")}</td></tr>' for k,v in report['summary']['classes'].items())
    part_rows=''.join(f'<tr><td>{esc(k)}</td><td>{number(v["nominal_area_cm2_estimate"])} (estimate)</td><td>{number(v["defect_area_cm2"])}</td>'
        f'<td>{coverage(v["coverage"])}</td><td>{esc(v["status"])}</td></tr>' for k,v in report['summary']['phone_parts'].items())
    surface_rows=''.join(f'<tr><td>{esc(s["surface_id"])}</td><td>{number(s["surface_area_cm2"])}</td><td>{s["surface_area_pixels"]}</td>'
        f'<td>{coverage(s["visible_region_coverage"])}</td><td>{coverage(s["whole_surface_coverage"])}</td><td>{esc(s["reference_image_id"])}</td></tr>' for s in report['summary']['surfaces'])
    reviews=''.join('<li>'+esc(str(row))+'</li>' for row in report['review_items']) or '<li>No automated review flags; human inspection is still recommended.</li>'
    grade=report['grade'] or report['provisional_grade']+' (provisional — review required)'
    page='''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Phone defect inspection</title><style>body{font:15px system-ui;background:#f3f5f8;color:#1b2432;margin:0;padding:32px;max-width:1500px}h1{margin-bottom:4px}section,.card{background:white;padding:22px;border-radius:12px;margin:18px 0;overflow:auto}table{border-collapse:collapse;width:100%;font-size:13px}th,td{padding:10px;border-bottom:1px solid #e3e7ed;text-align:left}th{background:#eaf0f7}.photos{display:flex;gap:16px}.photos img{max-height:360px;max-width:45vw;object-fit:contain}a{color:#165fba}.notice{border-left:5px solid #cc8600;background:#fff4d9;padding:16px}details{margin:16px 0}small{color:#596575}</style>'''
    page+=f'<h1>{esc(report["phone_model"])} · inspection report</h1><p>Cosmetic grade: <strong>{esc(grade)}</strong> · '
    page+=f'{report["unique_defect_count"]} defect IDs ({esc(report["count_status"])}) · confidence ≥ {number(report["confidence_threshold"])} · matcher: {esc(report["matching_backend"])}</p>'
    if phone_profile.get('api_provider')=='TechAPI' or phone_profile.get('model_code_lookup'):
        source_links=' · '.join(f'<a href="{esc(url)}">source</a>' for url in phone_profile.get('source_urls',[]))
        page+=f'<p>{esc(phone_profile.get("data_attribution","Data from TechAPI"))} · {esc(phone_profile.get("data_license","CC-BY-SA 4.0; attribute Data from TechAPI and share alike"))} · '
        page+=f'<a href="{esc(phone_profile.get("source","https://github.com/GetTechAPI/TechAPI"))}">phone specification source</a>{(" · "+source_links) if source_links else ""}</p>'
    page+='<p class="notice">Whole-phone outline and nominal body dimensions provide an approximate pixel-to-area scale. Each defect class selects its nominal Screen, Back or Frame denominator. Frame pixels can lie on a different plane from the phone face, so the resulting area and coverage are estimates and require review. Relative visual-depth cue reflects local contrast, not physical depth. Severity and grade are unvalidated cosmetic heuristics. Defects with uncertain identities remain provisional.</p>'
    coverage_heading='' if whole_outline else '<th>Visible-part coverage</th>'
    page+='<section><h2>Unique physical-defect candidates</h2><table><tr><th>ID</th><th>Class</th><th>Estimated area</th>'+coverage_heading+'<th>Whole-part coverage (spec estimate)</th><th>Relative visual-depth cue</th><th>Severity</th><th>Consolidation</th><th>All source images</th><th>Primary observation</th><th>Mask</th></tr>'+''.join(unique_rows)+'</table><p>Whole-part coverage = estimated defect area ÷ specification-derived nominal total area for Screen, Back or Frame. The whole-phone outline provides approximate pixel-to-area scale.</p></section>'
    page+='<section><h2>Class summary</h2><p>Areas use binary unions within each registered surface, including overlap between different defect IDs. Unknown/unregistered totals stay blank.</p><table><tr><th>Class</th><th>Count</th><th>Total area cm²</th><th>Part coverage</th><th>Mean severity (ordinal heuristic)</th></tr>'+class_rows+'</table></section>'
    surface_detail='' if whole_outline else '<h3>Individual planar surfaces / frame facets</h3><table><tr><th>Surface</th><th>Area cm²</th><th>Area px² in measurement space</th><th>Visible coverage</th><th>Whole-surface coverage</th><th>Reference image</th></tr>'+surface_rows+'</table>'
    page+='<section><h2>Phone-part summary</h2><p>Nominal part areas are estimates calculated from the phone specification dimensions. Damage area and coverage use the whole-phone-outline scale estimate.</p><table><tr><th>Part</th><th>Specification-based nominal cm²</th><th>Damage cm²</th><th>Coverage</th><th>Status</th></tr>'+part_rows+'</table>'+surface_detail+'</section>'
    page+='<h2>Per-image evidence</h2>'+''.join(sections)+'<section><h2>Review queue</h2><ul>'+reviews+'</ul></section>'
    page+='<p><a href="report.json">Complete JSON with registration diagnostics</a> · <a href="unique_defects.csv">Unique defects CSV</a></p></html>'
    (output/'report.html').write_text(page,encoding='utf-8')
    fields=['id','class','part','surface_id','area_cm2','area_pixels','coverage','whole_part_coverage_estimate','intensity','apparent_depth_cue','severity','source_image_ids','primary_observation_id','measurement_method']
    with (output/'unique_defects.csv').open('w',newline='',encoding='utf-8-sig') as stream:
        writer=csv.DictWriter(stream,fieldnames=fields);writer.writeheader();writer.writerows(csv_rows)
