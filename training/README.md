# Hatchery object-detector training

This folder contains the reproducible macOS training runner for the app's
single-class `hatchery` detector. It trains a bounding-box detector, not a sand
segmentation model. The result is only a first suggestion for the existing
four-corner camera guide; Page 8 remains the user-controlled correction step.

Before collecting data, follow [DATA_COLLECTION.md](DATA_COLLECTION.md) and
record every candidate in [source-manifest.csv](source-manifest.csv).
For a human-reviewed local-image CSV that generates Apple JSON splits, follow
[CURATION.md](CURATION.md).

## Prerequisites

- macOS with the full Xcode installation. This workspace has Xcode 26.6, which
  includes Create ML and the `CreateML` Swift framework.
- Run commands with the full Xcode developer directory because the current
  `xcode-select` setting points at Command Line Tools:

  ```sh
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  ```

- No Python packages are needed. Training uses Apple's `MLObjectDetector` on
  macOS; the exported model runs on iOS with Core ML and Vision.

## Dataset contract

Use a versioned dataset outside Git, for example:

```text
training/datasets/hatchery-v1/
├── train/
│   ├── hatchery_0001.jpg
│   └── annotations.json
├── validation/
│   ├── hatchery_0101.jpg
│   └── annotations.json
└── test/
    ├── hatchery_0121.jpg
    └── annotations.json
```

Each split directory contains all its referenced images and **exactly one**
Apple JSON annotation file. Keep source URLs, licensing, permissions, and
capture notes in a manifest outside those directories. Do not commit raw field
photos or training data to this repository unless their permissions explicitly
allow it.

The only positive label is `hatchery`. Draw the box tightly around the usable
sand bed that should become the grid, not the enclosing tent or canopy. Apply
the same rule to every image. Images without a usable hatchery are valid
negative samples and use an empty annotation array.

Apple JSON uses pixel values. This runner explicitly interprets `x` and `y` as
the upper-left corner of the box, with `width` and `height` in pixels:

```json
[
  {
    "imagefilename": "hatchery_0001.jpg",
    "annotation": [
      {
        "label": "hatchery",
        "coordinates": {
          "x": 123,
          "y": 85,
          "width": 821,
          "height": 566
        }
      }
    ]
  },
  {
    "imagefilename": "no_hatchery_0001.jpg",
    "annotation": []
  }
]
```

For an initial 100–200-photo model, split by **shoot/scene**, not individual
frames: 70% train, 15% validation, and 15% held-out test. Do not train until
the positive examples cover at least 30 independent hatchery/capture-session
groups; augmentations and near-duplicate frames do not count as new groups.
Keep the same physical hatchery and the same capture session in one split
only. Spread negative photos across all three splits; aim for roughly 15–25%
negatives so poles, signs, tents, and bare sand are not mistaken for a
hatchery.

## Optional controlled training augmentation

When the reviewed field set is still small, generate variants only from the
`train` split. Never augment, move, or re-split validation and test images: the
whole point of those sets is to measure whether the model generalises beyond
the images it has seen.

`training/scripts/augment_hatchery_training.swift` is a deterministic local
experiment helper. It preserves every source training image and adds a
horizontal mirror plus a restrained low-light exposure variant. It applies the
exact horizontal box transform for positives and the same photometric variant
to negatives, so class balance is not silently changed.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# First build a new base data set with build_create_ml_dataset.py, then:
mkdir -p training/datasets/hatchery-v2-augmented
xcrun swift training/scripts/augment_hatchery_training.swift \
  training/datasets/hatchery-v2-base/train \
  training/datasets/hatchery-v2-augmented/train
cp -R training/datasets/hatchery-v2-base/validation \
  training/datasets/hatchery-v2-augmented/validation
cp -R training/datasets/hatchery-v2-base/test \
  training/datasets/hatchery-v2-augmented/test
```

This improves resilience to orientation and lighting only; it does not create
new hatchery shapes, camera angles, glare, or motion. Use it as an A/B
experiment against the unchanged held-out set, not as a substitute for more
independent field photos.

## Train and export

The default is transfer learning, a practical first candidate for a small
dataset. Train a second run with `darknet-yolo` against the same splits and
retain the model with the better held-out test mAP and physical-device latency.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
mkdir -p community-challenge/community-challenge/Models

xcrun swift training/HatcheryDetectorTraining.swift \
  training/datasets/hatchery-v1/train \
  training/datasets/hatchery-v1/validation \
  training/datasets/hatchery-v1/test \
  community-challenge/community-challenge/Models/HatcheryDetector.mlmodel \
  --algorithm transfer-learning
```

Optional training cap:

```sh
xcrun swift training/HatcheryDetectorTraining.swift \
  training/datasets/hatchery-v1/train \
  training/datasets/hatchery-v1/validation \
  training/datasets/hatchery-v1/test \
  community-challenge/community-challenge/Models/HatcheryDetector.mlmodel \
  --algorithm darknet-yolo \
  --max-iterations 100
```

The runner prints training, validation, and held-out test mean average
precision at IoU 0.5 and varied IoU. It refuses to overwrite a model; choose a
new output path for an experiment or intentionally remove the old output
yourself.

## Evaluate an exported prototype model

Use the Vision-based evaluator before even considering a model for the app. It
uses the same `.scaleFill` request policy and `hatchery` label contract as the
runtime provider, and reports precision, recall, and F1 at IoU 0.5 and the
runtime confidence threshold of 0.60:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcrun swift training/HatcheryDetectorEvaluation.swift \
  training/exports/HatcheryDetector-v1.mlmodel \
  training/datasets/hatchery-v1/test
```

Treat a small test split only as a smoke check. Do not bundle an export whose
held-out positive scenes fail to detect, regardless of its training metrics.

## Integrate and verify

Commit the raw `HatcheryDetector.mlmodel` under the app source directory. The
synchronized Xcode project includes it automatically and compiles it to an
`.mlmodelc` at build time; do not commit generated `.mlmodelc` output.

Do not bundle or commit an export trained from the local-testing-only web
pool. Keep those artifacts in the ignored `training/exports/` directory; they
are useful for evaluating the pipeline, not for distributing with the app.

The app already loads `HatcheryDetector.mlmodelc` through `VNCoreMLModel` when
it is bundled. A compatible Vision rectangle remains the preferred four-corner
perspective guide. If rectangle detection fails but the model is confident, its
axis-aligned box becomes a conservative four-corner fallback; Page 8 remains
the authority for the user to refine the result. If neither succeeds, the
current Vision/default guide remains.

Build the app after adding the model:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild \
  -project community-challenge/community-challenge.xcodeproj \
  -scheme community-challenge \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  build CODE_SIGNING_ALLOWED=NO
```
