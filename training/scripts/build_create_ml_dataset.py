#!/usr/bin/env python3
"""Build Apple Create ML object-detector folders from a human-reviewed CSV.

The CSV is the only annotation input. This script deliberately does not infer
boxes, labels, or scene groups from an image. It copies accepted local images
into an ignored output directory and writes one Apple JSON file per split.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path


LABEL = "hatchery"
SPLITS = ("train", "validation", "test")
SPLIT_RATIOS = {"train": 0.70, "validation": 0.15, "test": 0.15}
REQUIRED_COLUMNS = (
    "image_path",
    "source_id",
    "split_group",
    "decision",
    "label",
    "x",
    "y",
    "width",
    "height",
)
DECISIONS = {"positive", "negative", "exclude"}


class CurationError(RuntimeError):
    """A human review CSV cannot safely become a training data set."""


@dataclass(frozen=True)
class BoundingBox:
    x: int
    y: int
    width: int
    height: int

    def apple_json(self) -> dict[str, object]:
        return {
            "label": LABEL,
            "coordinates": {
                "x": self.x,
                "y": self.y,
                "width": self.width,
                "height": self.height,
            },
        }


@dataclass
class ReviewedImage:
    source_path: Path
    source_path_text: str
    source_id: str
    split_group: str
    decision: str
    width: int
    height: int
    boxes: list[BoundingBox] = field(default_factory=list)


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Build deterministic scene-group Create ML splits from a manually reviewed CSV. "
            "See training/CURATION.md."
        )
    )
    parser.add_argument("review_csv", type=Path, help="human-reviewed CSV")
    parser.add_argument("output_dir", type=Path, help="new generated dataset directory")
    parser.add_argument(
        "--seed",
        default="hatchery-v1",
        help="stable split seed (default: hatchery-v1)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="validate reviews and print the planned split without writing files",
    )
    return parser.parse_args()


def required_value(row: dict[str, str], column: str, row_number: int) -> str:
    value = (row.get(column) or "").strip()
    if not value:
        raise CurationError(f"row {row_number}: {column} is required")
    return value


def blank(value: str | None) -> bool:
    return not (value or "").strip()


def parse_pixel(row: dict[str, str], column: str, row_number: int) -> int:
    raw_value = required_value(row, column, row_number)
    try:
        value = int(raw_value)
    except ValueError as error:
        raise CurationError(
            f"row {row_number}: {column} must be an integer pixel value, not {raw_value!r}"
        ) from error
    return value


def resolved_image_path(csv_path: Path, source_path_text: str, row_number: int) -> Path:
    source_path = Path(source_path_text).expanduser()
    if not source_path.is_absolute():
        source_path = csv_path.parent / source_path
    source_path = source_path.resolve()
    if not source_path.is_file():
        raise CurationError(f"row {row_number}: image does not exist: {source_path}")
    if not source_path.suffix:
        raise CurationError(f"row {row_number}: image has no filename extension: {source_path}")
    return source_path


def image_dimensions(image_path: Path) -> tuple[int, int]:
    """Read dimensions with the macOS image utility Create ML users already have."""

    try:
        result = subprocess.run(
            ["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(image_path)],
            check=False,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError as error:
        raise CurationError("sips is required on macOS to validate image dimensions") from error

    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip() or "unknown sips error"
        raise CurationError(f"cannot read image dimensions for {image_path}: {detail}")

    width_match = re.search(r"pixelWidth:\s*(\d+)", result.stdout)
    height_match = re.search(r"pixelHeight:\s*(\d+)", result.stdout)
    if not width_match or not height_match:
        raise CurationError(f"sips returned no pixel dimensions for {image_path}")
    return int(width_match.group(1)), int(height_match.group(1))


def validate_box(
    box: BoundingBox,
    image_path: Path,
    image_width: int,
    image_height: int,
    row_number: int,
) -> None:
    if box.x < 0 or box.y < 0 or box.width <= 0 or box.height <= 0:
        raise CurationError(f"row {row_number}: bounding box must be non-negative with positive size")
    if box.x + box.width > image_width or box.y + box.height > image_height:
        raise CurationError(
            f"row {row_number}: bounding box exceeds {image_path.name} "
            f"({image_width}x{image_height})"
        )


def parse_review_csv(review_csv: Path) -> tuple[list[ReviewedImage], int]:
    if not review_csv.is_file():
        raise CurationError(f"review CSV does not exist: {review_csv}")

    dimensions_cache: dict[Path, tuple[int, int]] = {}
    records_by_path: dict[Path, ReviewedImage] = {}
    excluded_rows = 0

    with review_csv.open("r", encoding="utf-8-sig", newline="") as input_file:
        reader = csv.DictReader(input_file)
        fieldnames = reader.fieldnames or []
        missing = [column for column in REQUIRED_COLUMNS if column not in fieldnames]
        if missing:
            raise CurationError("review CSV is missing required columns: " + ", ".join(missing))

        for row_number, row in enumerate(reader, start=2):
            if all(blank(value) for value in row.values()):
                continue
            if (row.get("image_path") or "").lstrip().startswith("#"):
                continue

            decision = required_value(row, "decision", row_number).lower()
            if decision not in DECISIONS:
                allowed = ", ".join(sorted(DECISIONS))
                raise CurationError(f"row {row_number}: decision must be one of {allowed}")

            if decision == "exclude":
                excluded_rows += 1
                continue

            source_path_text = required_value(row, "image_path", row_number)
            source_path = resolved_image_path(review_csv, source_path_text, row_number)
            source_id = required_value(row, "source_id", row_number)
            split_group = required_value(row, "split_group", row_number)
            if source_path not in dimensions_cache:
                dimensions_cache[source_path] = image_dimensions(source_path)
            width, height = dimensions_cache[source_path]

            if decision == "positive":
                label = required_value(row, "label", row_number)
                if label != LABEL:
                    raise CurationError(
                        f"row {row_number}: positive rows must use the only label {LABEL!r}"
                    )
                box = BoundingBox(
                    x=parse_pixel(row, "x", row_number),
                    y=parse_pixel(row, "y", row_number),
                    width=parse_pixel(row, "width", row_number),
                    height=parse_pixel(row, "height", row_number),
                )
                validate_box(box, source_path, width, height, row_number)
            else:
                if not blank(row.get("label")) or any(
                    not blank(row.get(column)) for column in ("x", "y", "width", "height")
                ):
                    raise CurationError(
                        f"row {row_number}: negative rows must leave label and box columns blank"
                    )
                box = None

            existing = records_by_path.get(source_path)
            if existing is None:
                existing = ReviewedImage(
                    source_path=source_path,
                    source_path_text=source_path_text,
                    source_id=source_id,
                    split_group=split_group,
                    decision=decision,
                    width=width,
                    height=height,
                )
                records_by_path[source_path] = existing
            elif (
                existing.source_id != source_id
                or existing.split_group != split_group
                or existing.decision != decision
            ):
                raise CurationError(
                    f"row {row_number}: repeated image rows must keep source_id, split_group, and decision identical"
                )
            elif decision == "negative":
                raise CurationError(f"row {row_number}: a negative image may appear only once")

            if box is not None:
                existing.boxes.append(box)

    records = list(records_by_path.values())
    if not records:
        raise CurationError("review CSV contains no included positive or negative images")
    if not any(record.decision == "positive" for record in records):
        raise CurationError("review CSV contains no included positive images")
    if len({record.split_group for record in records}) < len(SPLITS):
        raise CurationError("at least three independent split_group values are required")
    return records, excluded_rows


def stable_group_order(split_group: str, seed: str) -> str:
    return hashlib.sha256(f"{seed}:{split_group}".encode("utf-8")).hexdigest()


def assign_splits(records: list[ReviewedImage], seed: str) -> dict[str, str]:
    groups: dict[str, list[ReviewedImage]] = defaultdict(list)
    for record in records:
        groups[record.split_group].append(record)

    targets = {split: len(records) * SPLIT_RATIOS[split] for split in SPLITS}
    assigned_counts = {split: 0 for split in SPLITS}
    assignments: dict[str, str] = {}
    ordered_groups = sorted(groups, key=lambda group: stable_group_order(group, seed))

    # A tiny first pass still needs at least one learnable example. Anchor the
    # first deterministic positive group in training, then balance every other
    # complete group by image count. This never moves individual frames across
    # splits and avoids a valid-looking data set with no training positives.
    positive_groups = [
        group
        for group in ordered_groups
        if any(record.decision == "positive" for record in groups[group])
    ]
    training_anchor = positive_groups[0]
    assignments[training_anchor] = "train"
    assigned_counts["train"] += len(groups[training_anchor])

    for split_group in ordered_groups:
        if split_group == training_anchor:
            continue
        split = min(
            SPLITS,
            key=lambda candidate: assigned_counts[candidate] / targets[candidate],
        )
        assignments[split_group] = split
        assigned_counts[split] += len(groups[split_group])

    return assignments


def output_filename(record: ReviewedImage, index: int) -> str:
    source_slug = re.sub(r"[^a-z0-9]+", "-", record.source_id.lower()).strip("-") or "image"
    path_hash = hashlib.sha256(str(record.source_path).encode("utf-8")).hexdigest()[:12]
    return f"{index:04d}-{source_slug}-{path_hash}{record.source_path.suffix.lower()}"


def apple_annotation(record: ReviewedImage, filename: str) -> dict[str, object]:
    return {
        "imagefilename": filename,
        "annotation": [box.apple_json() for box in record.boxes],
    }


def write_dataset(
    records: list[ReviewedImage],
    assignments: dict[str, str],
    review_csv: Path,
    output_dir: Path,
    seed: str,
    excluded_rows: int,
) -> None:
    if output_dir.exists():
        raise CurationError(f"refusing to overwrite existing output directory: {output_dir}")

    output_dir.parent.mkdir(parents=True, exist_ok=True)
    temporary_dir = Path(tempfile.mkdtemp(prefix=f".{output_dir.name}.", dir=output_dir.parent))

    try:
        ordered_records = sorted(records, key=lambda record: str(record.source_path))
        split_records = {
            split: [record for record in ordered_records if assignments[record.split_group] == split]
            for split in SPLITS
        }
        manifest_images: list[dict[str, object]] = []

        for split in SPLITS:
            split_dir = temporary_dir / split
            split_dir.mkdir()
            annotations: list[dict[str, object]] = []

            for index, record in enumerate(split_records[split], start=1):
                filename = output_filename(record, index)
                shutil.copy2(record.source_path, split_dir / filename)
                annotations.append(apple_annotation(record, filename))
                manifest_images.append(
                    {
                        "dataset_filename": f"{split}/{filename}",
                        "source_path": str(record.source_path),
                        "source_id": record.source_id,
                        "split_group": record.split_group,
                        "split": split,
                        "decision": record.decision,
                        "image_width": record.width,
                        "image_height": record.height,
                        "boxes": [box.apple_json()["coordinates"] for box in record.boxes],
                    }
                )

            with (split_dir / "annotations.json").open("w", encoding="utf-8") as annotation_file:
                json.dump(annotations, annotation_file, indent=2)
                annotation_file.write("\n")

        review_sha256 = hashlib.sha256(review_csv.read_bytes()).hexdigest()
        summary = {
            split: {
                "images": len(split_records[split]),
                "positive_images": sum(record.decision == "positive" for record in split_records[split]),
                "negative_images": sum(record.decision == "negative" for record in split_records[split]),
                "bounding_boxes": sum(len(record.boxes) for record in split_records[split]),
                "split_groups": sorted({record.split_group for record in split_records[split]}),
            }
            for split in SPLITS
        }
        manifest = {
            "schema_version": 1,
            "created_at": datetime.now(timezone.utc).isoformat(),
            "review_csv": str(review_csv.resolve()),
            "review_csv_sha256": review_sha256,
            "seed": seed,
            "annotation_contract": {
                "label": LABEL,
                "units": "pixel",
                "origin": "topLeft",
                "anchor": "topLeft",
            },
            "excluded_rows": excluded_rows,
            "summary": summary,
            "images": manifest_images,
        }
        with (temporary_dir / "dataset-manifest.json").open("w", encoding="utf-8") as manifest_file:
            json.dump(manifest, manifest_file, indent=2)
            manifest_file.write("\n")

        temporary_dir.replace(output_dir)
    except Exception:
        shutil.rmtree(temporary_dir, ignore_errors=True)
        raise


def print_plan(records: list[ReviewedImage], assignments: dict[str, str], excluded_rows: int) -> None:
    print("Planned Create ML split:")
    for split in SPLITS:
        split_records = [record for record in records if assignments[record.split_group] == split]
        positive_images = sum(record.decision == "positive" for record in split_records)
        boxes = sum(len(record.boxes) for record in split_records)
        groups = len({record.split_group for record in split_records})
        print(
            f"  {split}: {len(split_records)} images, {positive_images} positive images, "
            f"{boxes} boxes, {groups} split groups"
        )
        if split != "train" and positive_images == 0:
            print(f"  warning: {split} has no positive image; add an independent positive split_group before evaluation")
    if excluded_rows:
        print(f"  excluded review rows: {excluded_rows}")


def main() -> int:
    arguments = parse_arguments()
    review_csv = arguments.review_csv.expanduser().resolve()
    output_dir = arguments.output_dir.expanduser().resolve()

    try:
        records, excluded_rows = parse_review_csv(review_csv)
        assignments = assign_splits(records, arguments.seed)
        print_plan(records, assignments, excluded_rows)
        if arguments.dry_run:
            print("Dry run complete; no files were written.")
            return 0
        write_dataset(
            records,
            assignments,
            review_csv,
            output_dir,
            arguments.seed,
            excluded_rows,
        )
        print(f"Wrote Create ML data set: {output_dir}")
        return 0
    except CurationError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
