# Multi-photo phone defect inspection

This folder is independent of Model 1/Model 2 training. It reads a selected Model 2 checkpoint, processes several photographs of **one physical phone**, and creates an evidence-preserving HTML, JSON and CSV report. It does not modify weights, source images or source masks.

## What is implemented

1. The desktop UI accepts a **brand and model name** (for example `Huawei` and `Y9 Prime (2019)`). It searches GetTechAPI's [TechAPI dataset](https://github.com/GetTechAPI/TechAPI) and checks matching records until it finds one with valid body dimensions and display data. It reads TechAPI's static JSON index and detail files from GitHub Pages and caches them locally to avoid repeat downloads. The data is CC-BY-SA 4.0 and is attributed in the report. Display dimensions and part areas are nominal estimates, not exact measured surface areas.
2. For the desktop UI, **Grounding DINO + SAM 2.1** propose one whole-phone outline for approximate pixel-to-area scaling. Separate Screen/Back/Frame masks are not required to assign defects: Model 2's class prefix selects the corresponding part's nominal area from the phone profile. The outline and scale are estimates and are flagged for review. Hand-written manifests can still supply reviewed part masks and explicit calibrations.
3. All raw predictions/masks/confidences are preserved. Predictions at or above the configured confidence (default 0.30) are collected. Same-class overlapping masks in the same image/surface are merged by binary union. Different classes are not merged.
4. Per-image defect area is mapped through the whole-phone outline calibration, then divided by the phone profile's nominal Screen/Back/Frame area according to its class. The result is a rough whole-part coverage estimate; defect masks are not rejected for failing to overlap a separately detected part. Image sharpness/exposure, mask boundary reliability and local Lab color/brightness contrast are also measured. `Weak / Moderate / Strong` is a **relative visual-depth cue**, not physical depth in millimeters.
5. **ALIKED + LightGlue** supplies correspondences. This is ALIKED, the pretrained feature family supported by official LightGlue, not original ALIKE with incompatible descriptors. OpenCV RANSAC registration is restricted to the same declared planar surface/facet, with minimum inliers, inlier ratio, forward/inverse error, spatial spread, reflection/distortion/horizon, surface-overlap and local-support checks. Curved frame views are not registered as one flat plane.
6. Matching requires reliable geometry and same-class mask agreement. Many-to-one matches are rejected. Groups require complete-link agreement and at most one merged observation per source image. Conflicting classes at the same registered location are flagged. Uncertain matches remain separate candidate IDs and enter the review queue; their count is not presented as a certified physical count.
7. One primary observation is selected using completeness, image quality, visibility, confidence, mask quality and registration evidence. Complete primary observations supply final measurements. Optional complementary mask union is enabled only for confirmed groups with reliable direct registrations, sufficiently retained masks and a safe reference canvas. Masks are combined with **binary union**, then geometry is recalculated. Areas and lengths are never added across photographs. Appearance comes from the chosen primary photograph, not a sum/average of different lighting conditions.
8. Per-class and per-part summaries use union masks in a single registered reference coordinate system. Cross-class overlaps count once in total damage. Numeric coverage is in `[0,1]`; unregistered totals remain unknown rather than being summed. Frame facets may be added only as disjoint physical surfaces with compatible calibrated units. Missing surfaces remain explicitly missing.
9. The report includes unique IDs, every source-image ID, primary image, raw and merged masks, confidence, per-image measurements, final area/intensity/severity, class summaries, phone-part summaries, registration diagnostics and an A–D cosmetic grade. Incomplete/uncertain evidence produces a **provisional** grade.

## Exact size versus estimates

The phone-spec API returns body dimensions and display diagonal/resolution scraped from GSMArena. These are not exact active-screen, curved back-panel or frame surface areas. The complete API response and GSMArena source URL are retained in the generated profile and report as source provenance. Rectangular **nominal area estimates** are derived from those returned dimensions:

- Screen: rectangle from display dimensions/aspect ratio; corner and camera cutouts are not known from diagonal alone.
- Back: nominal body height × width.
- Frame: rectangular-prism estimate `2 × (height + width) × thickness`; it is not an exact metal frame area.

The desktop evaluator estimates pixel-to-mm scaling from the whole-phone outline and the closest nominal body/facet aspect ratio in the phone profile. It maps each defect mask to an estimated cm² area, then divides by the specification-derived total area for the defect's class part. This is approximate—especially for frame damage, which may lie on a different plane from the visible phone face—and is added to the review queue. Reviewed planar calibration is preferred for reliable measurements.

The report displays these specification-based estimates separately from image measurements. Automatic outline rectification is approximate and labeled `≈`; it cannot make generic segmentation or nominal specifications exact. Calibrated cm² requires a sourced planar width/height and four ordered correspondences (TL, TR, BR, BL) on the same plane/facet. Reviewed masks exclude cutouts/rounded corners. A phone frame should be split into individually observed planar facets; curved regions require an appropriate 3D/CAD measurement workflow instead of one homography. Without a valid mapping, damage remains in pixels and physical area is unknown.

## Installed environment and weights

Use the isolated environment to access LightGlue, whole-phone outline segmentation, and related analysis dependencies:

```powershell
detection_evaluation/.venv/Scripts/python.exe -m detection_evaluation --help
```

The environment inherits the existing PyTorch/OpenCV installation but keeps additional matching/segmentation dependencies local. Recreate it if moving the folder:

```powershell
python -m venv --system-site-packages detection_evaluation/.venv
detection_evaluation/.venv/Scripts/python.exe -m pip install -r detection_evaluation/requirements-matching.txt -r detection_evaluation/requirements-parts.txt
```

SAM 2.1 tiny is stored in `weights/sam2.1_t.pt`. ALIKED/LightGlue weights use `weights/torch_hub`; Grounding DINO uses `weights/huggingface`. First-use downloads require internet. The pinned LightGlue implementation is from its official repository. `sift` is an explicit alternative baseline, never a silent replacement. `provided` accepts known correspondences for deterministic tests/manual registration evidence, not claimed learned matching.

## Desktop UI

From the project root, run:

```powershell
python ui.py
```

No Node API server is needed. From the project root, run:

```powershell
python ui.py
```

The UI defaults to the TechAPI dataset base URL `https://gettechapi.github.io/TechAPI`. To inspect a TechAPI phone record directly in PowerShell, use a record slug from the index:

```powershell
$slug = "huawei-y9-prime-2019-4gb-128gb-4g-lte"
Invoke-RestMethod "https://gettechapi.github.io/TechAPI/v1/smartphones/$slug/index.json" | ConvertTo-Json -Depth 20
```

The UI stages copies of the selected photos and creates a timestamped run folder under `detection_evaluation/runs`, then opens the report when complete. By default it uses GPU when PyTorch detects one, otherwise CPU. On first use or after the local index cache expires, it downloads the smartphone index once and then fetches the selected model's detail records as needed.

## Run with your phone photographs

Example for an iPhone 15 (replace it with the actual inspected model):

```powershell
detection_evaluation/.venv/Scripts/python.exe -m detection_evaluation --prepare-images "C:/path/to/phone_photos" --brand Apple --model "iPhone 15" --checkpoint model2_defect_segmentation/runs/auto_hard_negative_from_hn/saved_models/best.pt --output detection_evaluation/inspection.json
detection_evaluation/.venv/Scripts/python.exe -m detection_evaluation --inspection detection_evaluation/inspection.json --output detection_evaluation/runs/inspection_001
```

The first command creates editable inspection/profile JSON with whole-phone-outline scaling. The second runs defect detection, matching and reporting. Use a new output directory for each inspection. Only phone model text/specification requests and model-weight downloads go online; photos are processed locally.

TechAPI is used when preparing a profile from brand/model text or through the UI. Pass `--phone-api https://gettechapi.github.io/TechAPI` to set a different TechAPI static base. Supply `phone_specs.slug` in a hand-written manifest when a model name is ambiguous. If no matching API, cached, or bundled profile is available, lookup returns an explicitly flagged generic profile using the arithmetic mean of bundled profiles with complete dimensions. This fallback is not device-specific, adds a review item, and makes the grade provisional. Full custom profiles can be supplied through `phone_profile`.

## Reviewed boundary/calibration example

Replace automatic proposals for a photo with explicit surfaces when accurate measurements are needed:

```json
{
  "id": "front_01",
  "path": "photos/front_01.jpg",
  "surfaces": [{
    "id": "Screen", "part": "Screen",
    "mask": "masks/front_01_screen.png",
    "reviewed": true, "complete": true, "planar": true,
    "visibility": 1.0,
    "calibration": {
      "reviewed": true,
      "image_points": [[100,50],[500,50],[500,850],[100,850]]
    }
  }]
}
```

All masks/prompts/corners use **EXIF-oriented original-image coordinates**. A complete flag asserts that the whole part is visible; it should not be set for an occluded/partial view. Surface masks in one photo must be disjoint. IDs must remain consistent across photographs (e.g. Screen or Frame_Left). A custom profile supplies `surfaces.Screen.width_mm`, `height_mm` and `source`; production values must describe the actual known reference rectangle. Do not copy the example corners to unrelated images.

Instead of live inference, an image can reference an existing Model 2 `prediction_json`; or provide `predictions` with `class_name`, `confidence`, and binary `mask` paths. This preserves raw evidence and supports offline analysis. Paths in inspection JSON are relative to that file unless absolute. Prediction JSON mask paths are resolved relative to its own file when needed.

## Severity and grade rubric

Default per-defect area-coverage thresholds are 0.1%, 1%, and 5% for Low/Minor/Major/Critical. Reliable strong local contrast can increase a non-Low severity by one level. This is a configurable **unvalidated cosmetic heuristic**, not a physical-depth, structural, repair-cost or functional-safety assessment. Missing boundaries/lighting/completeness enter the review queue. A–D maps the worst consolidated severity to A/B/C/D; the output grade remains provisional when required surfaces or other evidence are unresolved. Mean class severity is an explicitly ordinal heuristic, not a physically calibrated average.

## Demo and tests

```powershell
python -m detection_evaluation --demo --output detection_evaluation/runs/my_demo
detection_evaluation/.venv/Scripts/python.exe -m detection_evaluation --demo --matching-backend lightglue_aliked --output detection_evaluation/runs/my_lightglue_demo
python -m unittest detection_evaluation.tests.test_inspection -q
```

Demo photographs and physical dimensions are synthetic fixtures, not measured real-phone performance. Tests cover repeated-photo counting, preservation, uncertain registration, same-class union, geometric rejection, calibrated units, complementary union without area summation, model lookup, cross-class conflicts and device separation.

Primary library references: [LightGlue](https://github.com/cvg/LightGlue), [Grounding DINO](https://huggingface.co/docs/transformers/model_doc/grounding-dino), [SAM 2](https://docs.ultralytics.com/models/sam-2/), [OpenCV homography](https://docs.opencv.org/4.x/d1/de0/tutorial_py_feature_homography.html).
