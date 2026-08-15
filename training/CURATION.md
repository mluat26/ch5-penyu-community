# Local-image curation bootstrap

This is the manual bridge between reviewed local images and the existing
Create ML trainer. It never predicts a label or a bounding box. A person must
visually inspect every included image at useful resolution first.

## Fast local box review (recommended for 100–200 photos)

`training/scripts/annotate_hatchery_images.py` is an offline, localhost-only
review tool. It draws exactly one box per image and writes this CSV format as
you work; it does not upload photos or infer a label. Give it one capture
session at a time so its default `split_group` is correct:

```sh
python3 training/scripts/annotate_hatchery_images.py \
  /Users/andrian/Downloads/hatchery \
  training/reviews/hatchery-field-2026-08.csv \
  --default-split-group hatchery-site-a-session-20260814 \
  --reviewer Andrian \
  --open-browser
```

Open the printed `http://127.0.0.1:8765` address if the browser does not open.
For each image, drag a tight box around the usable sand bed and press
`P`/“Save positive”; press `N` for a reviewed negative and `X` for an image
that is too ambiguous or occluded to train on. `←` and `→` revisit images.
Every save is atomic, so stopping the server and rerunning the same command
resumes the review CSV.

The input directory and `training/reviews/` are Git-ignored. Keep the same
physical hatchery and burst/session in one `split_group` (the editable field in
the tool); run a separate batch/default group for each independent session.
Do not label the roof, tent, poles, turtle, or the full photograph—the single
`hatchery` box must follow only the sand bed that the app should grid.

## 1. Start a review CSV

Copy the template somewhere outside Git, then replace the examples:

```sh
cp training/templates/reviewed-hatchery-images.template.csv \
  /path/outside-the-repository/hatchery-review.csv
```

The required columns are:

| Column | Required for | Meaning |
| --- | --- | --- |
| `image_path` | positive/negative | Absolute path, or path relative to the review CSV. |
| `source_id` | positive/negative | Stable provenance identifier. |
| `split_group` | positive/negative | The whole shoot/session/source group. Never reuse a physical hatchery session across different values. |
| `decision` | every row | `positive`, `negative`, or `exclude`. |
| `label` | positive | Exactly `hatchery`. |
| `x`, `y`, `width`, `height` | positive | Integer pixels: upper-left origin and upper-left anchor. |

Use one positive row per box. Multiple positive rows may refer to the same
image only when they repeat the same `source_id`, `split_group`, and
`decision`. A negative is exactly one row with its label and box columns blank.
An `exclude` row is never copied into the generated data set.

For positives, draw a tight rectangle around the usable sand bed that should
become the grid. Do not label a turtle, tank, tent, sign, or an uninspected
image as `hatchery`.

## 2. Validate the plan before copying images

```sh
python3 training/scripts/build_create_ml_dataset.py \
  /path/outside-the-repository/hatchery-review.csv \
  training/datasets/hatchery-v1 \
  --seed hatchery-v1 \
  --dry-run
```

The script validates every included local image with macOS `sips`, rejects
out-of-bounds boxes, and requires at least three independent `split_group`
values. It assigns complete groups deterministically to approximate a 70/15/15
train/validation/test split. The assignment favors split integrity over exact
row percentages, so inspect the printed counts before continuing.

## 3. Build the Create ML folders

Run the same command without `--dry-run`:

```sh
python3 training/scripts/build_create_ml_dataset.py \
  /path/outside-the-repository/hatchery-review.csv \
  training/datasets/hatchery-v1 \
  --seed hatchery-v1
```

It refuses to overwrite an existing output directory. It copies—not moves or
edits—the accepted local images and produces this ignored generated structure:

```text
training/datasets/hatchery-v1/
├── dataset-manifest.json
├── train/
│   ├── annotations.json
│   └── …images
├── validation/
│   ├── annotations.json
│   └── …images
└── test/
    ├── annotations.json
    └── …images
```

Each split contains exactly one Apple JSON annotation file plus its referenced
images, matching the existing `HatcheryDetectorTraining.swift` runner. The
root manifest records the review CSV checksum, source paths, groups, generated
filenames, and split assignment for later audit.

## 4. Train only after checking the split summary

Use the existing command from [README.md](README.md). Do not promote the
prototype model until its held-out test set includes genuinely independent,
permission-cleared local scenes. The camera must retain the existing manual
guide and Page 8 edit fallback regardless of model score.
