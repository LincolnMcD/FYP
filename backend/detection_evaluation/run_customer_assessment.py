"""Run Model 2 and the existing multi-image evaluator for one trade-in request."""
import json
import sys
from pathlib import Path

from detection_evaluation.inspection import CLASSES, run


CLASS_FIELDS = {
    "Back_Crack": "backCrack",
    "Back_Scratch": "backScratch",
    "Frame_Scratch": "frameScratch",
    "Frame_Dent": "frameDent",
    "Screen_Crack": "screenCrack",
    "Screen_Scratch": "screenScratch",
    "Screen_Discolouration": "screenDiscolouration",
}


def build_result(report, manifest, output_dir):
    unique = report.get("unique_defects", [])
    class_results = report.get("summary", {}).get("classes", {})
    has_scored_severity = any(
        row.get("severity", {}).get("ordinal") is not None for row in unique
    )
    all_images_reliable = bool(report.get("images")) and all(
        image.get("quality", {}).get("acceptable", False) for image in report["images"]
    )
    grade = report.get("grade")
    if grade is None and ((not unique and all_images_reliable) or has_scored_severity):
        grade = report.get("provisional_grade")
    phone_profile = report.get("phone_profile", {})
    result = {
        "evaluationID": manifest["evaluationID"],
        "tradeInRequestID": manifest["tradeInRequestID"],
        "grade": grade,
        "msrp": phone_profile.get("msrp"),
        "classes": {},
        "parts": {},
        "images": [],
        "other": {
            "provisionalGrade": report.get("provisional_grade"),
            "reviewItems": report.get("review_items", []),
            "gradeRequiresReview": bool(report.get("grade_requires_review", True)),
            "coverageMethod": report.get("coverage_method"),
            "genericDimensions": bool(phone_profile.get("generic_fallback", False)),
            "dimensionsMethod": phone_profile.get("dimensions_method") or phone_profile.get("body_dimensions_method"),
            "dimensionSource": phone_profile.get("source"),
            "fallbackSampleCount": phone_profile.get("fallback_sample_count"),
            "phoneDimensionsMm": {
                **(phone_profile.get("body_dimensions_mm") or {}),
                "screenWidth": (phone_profile.get("surfaces", {}).get("Screen") or {}).get("width_mm"),
                "screenHeight": (phone_profile.get("surfaces", {}).get("Screen") or {}).get("height_mm"),
            },
            "modelVersion": "model2_defect_segmentation",
        },
    }

    for class_name in CLASSES:
        field = CLASS_FIELDS[class_name]
        aggregate = class_results.get(class_name, {})
        defects = [row for row in unique if row.get("class_name") == class_name]
        count = int(aggregate.get("count", len(defects)))
        area_cm2 = aggregate.get("total_area_cm2")
        if count == 0:
            area, coverage, severity = 0, 0, None
        else:
            area = float(area_cm2) if area_cm2 is not None else None
            coverage = aggregate.get("coverage")
            ordinals = [row.get("severity", {}).get("ordinal") for row in defects]
            ordinals = [int(value) for value in ordinals if value is not None]
            severity = ["Low", "Minor", "Major", "Critical"][max(ordinals)] if ordinals else None
        result["classes"][field] = {
            "count": count,
            "area": area,
            "coverage": coverage,
            "severity": severity,
        }

    part_results = report.get("summary", {}).get("phone_parts", {})
    for part in ("Screen", "Back", "Frame"):
        source = part_results.get(part, {})
        defects = [row for row in unique if row.get("part") == part]
        count = len(defects)
        surface_area = source.get("surface_area_cm2") or source.get("nominal_area_cm2_estimate")
        damage_area = source.get("defect_area_cm2")
        if count == 0:
            damage_area, coverage = 0, 0
        elif damage_area is not None:
            coverage = source.get("coverage")
        else:
            coverage = None
        result["parts"][part.lower()] = {
            "surfaceArea": float(surface_area) if surface_area is not None else None,
            "dmgArea": float(damage_area) if damage_area is not None else None,
            "dmgCoverage": coverage,
        }

    for image in manifest["images"]:
        image_dir = output_dir / image["id"]
        predictions_path = image_dir / "original_predictions.json"
        predictions = json.loads(predictions_path.read_text(encoding="utf-8"))
        visualization = predictions.get("visualization_path")
        result["images"].append({
            "imageID": image["id"],
            "imageView": image.get("capture_view") or image["id"],
            "sourcePath": image["path"],
            "evaluatedPath": str(Path(visualization).resolve()) if visualization else None,
            "imageStatus": predictions.get("image_status", "processed"),
            "defectCount": predictions.get("defect_count", 0),
        })
    return result


def main():
    if len(sys.argv) != 3:
        raise SystemExit("Usage: run_customer_assessment.py <manifest.json> <output_dir>")
    manifest_path = Path(sys.argv[1]).resolve()
    output_dir = Path(sys.argv[2]).resolve()
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    model2_code_root = manifest.get("model2_code_root")
    if model2_code_root:
        model2_code_root = str(Path(model2_code_root).resolve())
        if model2_code_root not in sys.path:
            sys.path.insert(0, model2_code_root)
    report = run(manifest_path, output_dir)
    result = build_result(report, manifest, output_dir)
    (output_dir / "customer_evaluation.json").write_text(
        json.dumps(result, indent=2, ensure_ascii=False, allow_nan=False), encoding="utf-8"
    )
    print(json.dumps({"success": True, "result": str(output_dir / "customer_evaluation.json")}))


if __name__ == "__main__":
    main()
