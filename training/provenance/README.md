# Generated Commons provenance

Run the approved collector from the repository root:

```sh
bash training/scripts/collect_approved_commons.sh
```

It is intentionally restricted to the three CC BY-SA category pools approved
for this prototype. It downloads originals into ignored
`training/raw/commons-approved/` and regenerates these tracked manifests:

- `commons-approved-images.json` — machine-readable source records;
- `commons-approved-images.csv` — review-friendly tabular source records.
- `commons-approved-failures.json` / `.csv` — explicit records for metadata,
  download, or verification failures; retry the same command after a cooldown.
- `commons-approved-review-overrides.json` — human review dispositions for
  particular verified images. The initial Pawikan files are hard-negative
  candidates and are never hatchery positives.

Every retained image must have its own original URL, Commons source page,
author, credit, license, license URL, category, and local filename recorded.
It additionally records the exact downloaded URL/variant and downloaded
dimensions, so an allowed 2048px Commons derivative remains attributable to
its original source. The collector tries an original once, then uses the
documented 2048px derivative after a 15-second cooldown; only that fallback
gets one lightweight retry. It atomically checkpoints successful, file-verified
records after every image; partial files do not enter a tracked success
manifest.
The companion contact sheet is a derived local preview at
`training/exports/commons-approved-contact-sheet.html`; it is intentionally
ignored and must not replace individual source-license review.

Use `--refresh` to redownload originals and `--no-contact-sheet` for manifest
generation only. The collector has no arbitrary category argument, so it cannot
silently collect a non-approved pool.

## NPS public-domain egg corral

Run the bounded NPS collector from the repository root:

```sh
bash training/scripts/collect_nps_public_domain.sh
```

It accepts no arbitrary asset URL. Before each download, it rechecks each
NPGallery record's public-domain constraint, NPS Staff credit, egg-corral
description, and the original-file link exposed by that record. It writes the
five originals to ignored `training/raw/nps-public-domain/` and regenerates:

- `nps-public-domain-images.json`;
- `nps-public-domain-images.csv`.

All five are a correlated 2008 Padre Island source group. Keep the group in a
single train/validation/test partition to prevent scene leakage. The manifest's
`annotation_role` and `visual_review` are authoritative: it includes one
whole-corral positive, one needs-review image, and three hard negatives. A
shared NPS collection title is not a valid reason to label turtle-only images
as hatchery.
