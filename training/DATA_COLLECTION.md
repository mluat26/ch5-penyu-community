# Source review and collection

Use [source-manifest.csv](source-manifest.csv) as the provenance log before
downloading anything. The training command, on-disk annotation format, and
split rules live in [README.md](README.md).

## Class policy

The detector has one class: `hatchery`. A positive must show the usable
sea-turtle hatchery bed/enclosure that the user is creating in the app. Draw a
tight axis-aligned box around that usable area, following the exact box rule in
the training README. It is an object detector, not a sand mask or an automatic
final crop: Page 8 remains the manual correction authority.

Use turtles, hatchlings, empty beaches, signs, tents, tanks, poles, and
unrelated fences as negatives unless the target hatchery bed is clearly
visible. Do not reinterpret turtle-only labels as `hatchery` labels.

## Source gate

`source-verified` means the record page, license, and original-download path
were checked during the 2026-08-14 audit. It does **not** mean every image is a
positive. `collection-verified; individual-review-required` means every
retained file still needs its own creator, source URL, license, and visual-fit
review. `hold`, `excluded`, and `not-reviewed` rows may not be downloaded into
the training corpus.

Use this decision order:

1. Prefer the Public Domain USFWS candidates first.
2. Record the individual source URL and visual decision in the manifest.
3. Add source-verified CC0/CC BY candidates only after preserving attribution.
4. Use CC BY-SA material only after explicit project approval; it has
   attribution and ShareAlike obligations.
5. Reject NC, ND, all-rights-reserved, unclear licenses, and every excluded
   row.

Openverse is a discovery tool, not a license guarantee. Its result count is a
search snapshot and each item must be verified at the original source.

## First collection target

Curate 100–200 photos before training a prototype:

- 75–85% whole, clearly visible hatchery beds/enclosures;
- 15–25% difficult negatives, especially sand, tents, poles, signs, cages, and
  turtle tanks;
- varied daylight, night, shadows, angles, distance, obstruction, and hatchery
  layout;
- no near-duplicate frames split across train, validation, and test.

The positive set must also include at least 30 independent physical
hatchery/capture-session groups. A public photo burst, crops of one image, and
augmentations are useful training variation but do not create an independent
evaluation group.

Public material alone is a bootstrap dataset. It cannot establish reliable
performance for the local hatchery until permissioned local field photos are
held out for evaluation. If no high-confidence detection is produced, the app
must keep its existing guide and Page 8 editing fallback.
