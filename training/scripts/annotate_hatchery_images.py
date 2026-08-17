#!/usr/bin/env python3
"""Review local hatchery photos and write Create ML-compatible boxes.

This is deliberately a small localhost-only annotator. It has no external
dependencies, never uploads a photo, and writes the reviewed CSV consumed by
``build_create_ml_dataset.py``. One image gets one decision: a tight box around
the usable sand bed, a negative, or an exclusion.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import mimetypes
import os
import re
import signal
import subprocess
import sys
import tempfile
import webbrowser
from dataclasses import dataclass
from datetime import date
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlparse


LABEL = "hatchery"
DECISIONS = {"positive", "negative", "exclude"}
SUPPORTED_EXTENSIONS = {
    ".avif",
    ".heic",
    ".heif",
    ".jpeg",
    ".jpg",
    ".png",
    ".tif",
    ".tiff",
    ".webp",
}
CSV_FIELDS = (
    "image_path",
    "source_id",
    "split_group",
    "decision",
    "label",
    "x",
    "y",
    "width",
    "height",
    "reviewer",
    "reviewed_at",
    "notes",
)


class AnnotationError(RuntimeError):
    """An annotation cannot safely be saved."""


@dataclass(frozen=True)
class ImageItem:
    index: int
    path: Path
    relative_path: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run a local browser annotator for hatchery bounding boxes."
    )
    parser.add_argument("image_dir", type=Path, help="directory of local photos (scanned recursively)")
    parser.add_argument("review_csv", type=Path, help="CSV to create or resume")
    parser.add_argument(
        "--default-split-group",
        required=True,
        help=(
            "capture/session group to use initially. Keep all frames from one "
            "physical shoot in the same group."
        ),
    )
    parser.add_argument("--reviewer", default="", help="reviewer name written to the CSV")
    parser.add_argument("--port", type=int, default=8765, help="localhost port (default: 8765)")
    parser.add_argument(
        "--open-browser",
        action="store_true",
        help="open the local annotator in the default browser",
    )
    return parser.parse_args()


def normalize_path(path: Path) -> Path:
    return path.expanduser().resolve()


def catalogue_images(root: Path) -> list[ImageItem]:
    if not root.is_dir():
        raise AnnotationError(f"image directory does not exist: {root}")

    paths = sorted(
        (path for path in root.rglob("*") if path.is_file() and path.suffix.lower() in SUPPORTED_EXTENSIONS),
        key=lambda path: str(path.relative_to(root)).lower(),
    )
    if not paths:
        suffixes = ", ".join(sorted(SUPPORTED_EXTENSIONS))
        raise AnnotationError(f"no supported images found under {root} ({suffixes})")

    return [
        ImageItem(index=index, path=path, relative_path=str(path.relative_to(root)))
        for index, path in enumerate(paths)
    ]


def image_size(path: Path) -> tuple[int, int]:
    """Use the same macOS tool as the data-set builder for server-side bounds checks."""

    result = subprocess.run(
        ["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(path)],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        message = result.stderr.strip() or result.stdout.strip() or "unknown sips error"
        raise AnnotationError(f"cannot read {path.name}: {message}")
    width_match = re.search(r"pixelWidth:\s*(\d+)", result.stdout)
    height_match = re.search(r"pixelHeight:\s*(\d+)", result.stdout)
    if not width_match or not height_match:
        raise AnnotationError(f"cannot read pixel dimensions for {path.name}")
    return int(width_match.group(1)), int(height_match.group(1))


class ReviewStore:
    def __init__(
        self,
        output_path: Path,
        items: list[ImageItem],
        default_group: str,
        reviewer: str,
    ) -> None:
        self.output_path = output_path
        self.items = items
        self.default_group = default_group
        self.reviewer = reviewer
        self.item_by_path = {item.path: item for item in items}
        self.rows_by_path: dict[Path, dict[str, str]] = {}
        self.unrelated_rows: list[dict[str, str]] = []
        self.dimensions: dict[Path, tuple[int, int]] = {}
        self._load_existing_rows()

    def _load_existing_rows(self) -> None:
        if not self.output_path.exists():
            return
        with self.output_path.open("r", encoding="utf-8-sig", newline="") as handle:
            reader = csv.DictReader(handle)
            fieldnames = reader.fieldnames or []
            missing = [field for field in CSV_FIELDS if field not in fieldnames]
            if missing:
                raise AnnotationError(
                    f"existing review CSV is missing columns: {', '.join(missing)}"
                )
            for row in reader:
                normalized_row = {field: (row.get(field) or "") for field in CSV_FIELDS}
                source_text = normalized_row["image_path"].strip()
                if not source_text:
                    continue
                path = Path(source_text).expanduser()
                if not path.is_absolute():
                    path = self.output_path.parent / path
                path = path.resolve()
                if path in self.item_by_path:
                    if path in self.rows_by_path:
                        raise AnnotationError(
                            f"existing CSV has multiple rows for {path.name}; this annotator supports one box per image"
                        )
                    self.rows_by_path[path] = normalized_row
                else:
                    self.unrelated_rows.append(normalized_row)

    def review_for(self, item: ImageItem) -> dict[str, str] | None:
        row = self.rows_by_path.get(item.path)
        return dict(row) if row else None

    def source_id_for(self, item: ImageItem, existing: dict[str, str] | None) -> str:
        if existing and existing["source_id"].strip():
            return existing["source_id"].strip()
        slug = re.sub(r"[^a-z0-9]+", "-", Path(item.relative_path).stem.lower()).strip("-")
        digest = hashlib.sha256(item.relative_path.encode("utf-8")).hexdigest()[:10]
        return f"field-{slug or 'image'}-{digest}"

    def dimensions_for(self, item: ImageItem) -> tuple[int, int]:
        if item.path not in self.dimensions:
            self.dimensions[item.path] = image_size(item.path)
        return self.dimensions[item.path]

    def save(self, payload: dict[str, Any]) -> dict[str, str]:
        index = payload.get("index")
        if not isinstance(index, int) or not 0 <= index < len(self.items):
            raise AnnotationError("unknown image")
        item = self.items[index]

        decision = str(payload.get("decision", "")).strip().lower()
        if decision not in DECISIONS:
            raise AnnotationError("decision must be positive, negative, or exclude")

        split_group = str(payload.get("split_group", "")).strip()
        if not split_group:
            raise AnnotationError("split group is required")
        notes = str(payload.get("notes", "")).strip()
        existing = self.rows_by_path.get(item.path)
        row = {field: "" for field in CSV_FIELDS}
        row.update(
            {
                "image_path": str(item.path),
                "source_id": self.source_id_for(item, existing),
                "split_group": split_group,
                "decision": decision,
                "reviewer": self.reviewer,
                "reviewed_at": date.today().isoformat(),
                "notes": notes,
            }
        )

        if decision == "positive":
            box = payload.get("box")
            if not isinstance(box, dict):
                raise AnnotationError("draw a box around the usable sand bed before saving a positive")
            try:
                x = int(box["x"])
                y = int(box["y"])
                width = int(box["width"])
                height = int(box["height"])
            except (KeyError, TypeError, ValueError) as error:
                raise AnnotationError("box must contain integer x, y, width, and height values") from error
            image_width, image_height = self.dimensions_for(item)
            if x < 0 or y < 0 or width <= 0 or height <= 0:
                raise AnnotationError("box must have a non-negative origin and positive size")
            if x + width > image_width or y + height > image_height:
                raise AnnotationError(
                    f"box exceeds the image bounds ({image_width}×{image_height})"
                )
            row.update(
                {
                    "label": LABEL,
                    "x": str(x),
                    "y": str(y),
                    "width": str(width),
                    "height": str(height),
                }
            )

        self.rows_by_path[item.path] = row
        self._write_csv()
        return row

    def _write_csv(self) -> None:
        self.output_path.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(
            "w",
            encoding="utf-8",
            newline="",
            prefix=f".{self.output_path.name}.",
            suffix=".tmp",
            dir=self.output_path.parent,
            delete=False,
        ) as temporary:
            writer = csv.DictWriter(temporary, fieldnames=CSV_FIELDS)
            writer.writeheader()
            for item in self.items:
                row = self.rows_by_path.get(item.path)
                if row:
                    writer.writerow(row)
            for row in self.unrelated_rows:
                writer.writerow(row)
            temporary_path = Path(temporary.name)
        os.replace(temporary_path, self.output_path)

    def state(self) -> dict[str, Any]:
        return {
            "default_split_group": self.default_group,
            "reviewer": self.reviewer,
            "review_csv": str(self.output_path),
            "images": [
                {
                    "index": item.index,
                    "name": item.path.name,
                    "relative_path": item.relative_path,
                    "url": f"/image/{item.index}",
                    "review": self.review_for(item),
                }
                for item in self.items
            ],
        }


class AnnotationServer(ThreadingHTTPServer):
    def __init__(self, address: tuple[str, int], store: ReviewStore) -> None:
        super().__init__(address, AnnotationHandler)
        self.store = store


class AnnotationHandler(BaseHTTPRequestHandler):
    server: AnnotationServer

    def log_message(self, format: str, *args: object) -> None:
        # The terminal should show the startup URL, not noisy browser asset logs.
        return

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        path = urlparse(self.path).path
        if path == "/":
            self._send_html(ANNOTATOR_HTML)
        elif path == "/api/state":
            self._send_json(self.server.store.state())
        elif path.startswith("/image/"):
            self._send_image(path)
        else:
            self.send_error(HTTPStatus.NOT_FOUND)

    def do_POST(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        if urlparse(self.path).path != "/api/save":
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        try:
            content_length = int(self.headers.get("Content-Length", "0"))
            if content_length <= 0 or content_length > 100_000:
                raise AnnotationError("invalid request body")
            payload = json.loads(self.rfile.read(content_length))
            if not isinstance(payload, dict):
                raise AnnotationError("request must be a JSON object")
            row = self.server.store.save(payload)
        except (AnnotationError, json.JSONDecodeError) as error:
            self._send_json({"error": str(error)}, status=HTTPStatus.BAD_REQUEST)
            return
        self._send_json({"ok": True, "review": row})

    def _send_image(self, path: str) -> None:
        raw_index = path.removeprefix("/image/")
        try:
            index = int(raw_index)
            item = self.server.store.items[index]
        except (ValueError, IndexError):
            self.send_error(HTTPStatus.NOT_FOUND)
            return

        mime_type = mimetypes.guess_type(item.path.name)[0] or "application/octet-stream"
        try:
            content = item.path.read_bytes()
        except OSError:
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", mime_type)
        self.send_header("Content-Length", str(len(content)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(content)

    def _send_html(self, content: str) -> None:
        encoded = content.encode("utf-8")
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("Cache-Control", "no-store")
        self.send_header(
            "Content-Security-Policy",
            "default-src 'self'; img-src 'self'; style-src 'unsafe-inline'; script-src 'unsafe-inline'",
        )
        self.end_headers()
        self.wfile.write(encoded)

    def _send_json(self, payload: dict[str, Any], status: HTTPStatus = HTTPStatus.OK) -> None:
        encoded = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(encoded)


ANNOTATOR_HTML = r"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Hatchery box review</title>
  <style>
    :root { color-scheme: dark; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    * { box-sizing: border-box; }
    body { margin: 0; background: #111614; color: #f5f7f5; }
    header { padding: 16px 24px; border-bottom: 1px solid #2e3934; display: flex; align-items: center; justify-content: space-between; gap: 16px; }
    h1 { margin: 0; font-size: 19px; } .subtle, #file, #coordinates { color: #afbbb4; font-size: 13px; }
    main { display: grid; grid-template-columns: minmax(0, 1fr) 330px; min-height: calc(100vh - 76px); }
    #stage { min-width: 0; display: grid; place-items: center; padding: 20px; background: #080b09; }
    #image-wrap { position: relative; max-width: 100%; max-height: calc(100vh - 120px); line-height: 0; }
    #photo { display: block; max-width: min(100%, calc(100vw - 390px)); max-height: calc(100vh - 120px); object-fit: contain; user-select: none; }
    #overlay { position: absolute; inset: 0; cursor: crosshair; touch-action: none; }
    aside { padding: 20px; background: #17201b; border-left: 1px solid #2e3934; overflow-y: auto; }
    h2 { font-size: 15px; margin: 0 0 8px; } p { line-height: 1.45; margin: 8px 0; }
    .instruction { padding: 12px; border-radius: 10px; background: #233329; color: #d2e8d6; font-size: 14px; }
    .form { display: grid; gap: 8px; margin-top: 16px; } label { font-size: 13px; color: #c5d0c8; }
    input, textarea { width: 100%; border: 1px solid #405147; border-radius: 8px; background: #0e1410; color: #f5f7f5; padding: 10px; font: inherit; }
    textarea { min-height: 84px; resize: vertical; }
    .button-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; margin-top: 16px; }
    button { border: 0; border-radius: 8px; min-height: 42px; padding: 9px 12px; color: #fff; background: #405147; font: inherit; font-weight: 600; cursor: pointer; }
    button:hover { filter: brightness(1.12); } button:disabled { opacity: .4; cursor: not-allowed; }
    button.positive { background: #0c8a48; } button.negative { background: #59615d; } button.exclude { background: #7a4a23; }
    button.secondary { background: #29342e; } button.wide { grid-column: 1 / -1; }
    #message { min-height: 21px; margin-top: 14px; font-size: 13px; } #message.error { color: #ffaaa4; } #message.ok { color: #a8e6b9; }
    kbd { border: 1px solid #57675e; border-radius: 4px; padding: 1px 5px; background: #253029; font-size: 11px; }
    @media (max-width: 800px) { main { grid-template-columns: 1fr; } aside { border-left: 0; border-top: 1px solid #2e3934; } #photo { max-width: 100%; max-height: 65vh; } }
  </style>
</head>
<body>
  <header>
    <div><h1>Hatchery bounding-box review</h1><div id="progress" class="subtle"></div></div>
    <div id="coordinates"></div>
  </header>
  <main>
    <section id="stage">
      <div id="image-wrap"><img id="photo" alt="Current local review image"><canvas id="overlay"></canvas></div>
    </section>
    <aside>
      <h2 id="file"></h2>
      <p class="instruction">Drag one tight rectangle around the usable <strong>sand bed</strong> that should become the grid. Do not box the canopy, tent, poles, turtle, or the whole photo.</p>
      <p class="subtle">Only the local browser and this computer see these photos. The CSV is written after every decision.</p>
      <div class="form">
        <label for="group">Capture / session group</label>
        <input id="group" autocomplete="off">
        <label for="notes">Notes (optional)</label>
        <textarea id="notes" placeholder="Occlusion, difficult lighting, or why excluded"></textarea>
      </div>
      <div class="button-grid">
        <button id="positive" class="positive">Save positive <kbd>P</kbd></button>
        <button id="negative" class="negative">No hatchery <kbd>N</kbd></button>
        <button id="exclude" class="exclude">Exclude <kbd>X</kbd></button>
        <button id="clear" class="secondary">Clear box <kbd>⌫</kbd></button>
        <button id="previous" class="secondary">← Previous</button>
        <button id="next" class="secondary">Next →</button>
      </div>
      <p class="subtle">After saving, the next unreviewed photo opens automatically. Use arrows to revisit a review. Split groups prevent near-duplicate frames leaking into evaluation.</p>
      <div id="message"></div>
    </aside>
  </main>
  <script>
    const image = document.getElementById('photo');
    const canvas = document.getElementById('overlay');
    const context = canvas.getContext('2d');
    const groupInput = document.getElementById('group');
    const notesInput = document.getElementById('notes');
    const positiveButton = document.getElementById('positive');
    const message = document.getElementById('message');
    let state, currentIndex = 0, box = null, dragStart = null;

    function current() { return state.images[currentIndex]; }
    function reviewedCount() { return state.images.filter(item => item.review).length; }
    function setMessage(text, kind = '') { message.textContent = text; message.className = kind; }
    function clamp(value, low, high) { return Math.max(low, Math.min(high, value)); }

    function canvasMetrics() {
      const rect = image.getBoundingClientRect();
      const dpr = window.devicePixelRatio || 1;
      canvas.style.width = rect.width + 'px'; canvas.style.height = rect.height + 'px';
      canvas.width = Math.round(rect.width * dpr); canvas.height = Math.round(rect.height * dpr);
      context.setTransform(dpr, 0, 0, dpr, 0, 0);
      return rect;
    }

    function pointFromEvent(event) {
      const rect = image.getBoundingClientRect();
      return { x: clamp(event.clientX - rect.left, 0, rect.width), y: clamp(event.clientY - rect.top, 0, rect.height) };
    }

    function draw() {
      const rect = canvasMetrics();
      context.clearRect(0, 0, rect.width, rect.height);
      if (!box || !image.naturalWidth || !image.naturalHeight) { return; }
      const x = box.x * rect.width / image.naturalWidth;
      const y = box.y * rect.height / image.naturalHeight;
      const width = box.width * rect.width / image.naturalWidth;
      const height = box.height * rect.height / image.naturalHeight;
      context.fillStyle = 'rgba(40, 210, 112, 0.22)'; context.fillRect(x, y, width, height);
      context.strokeStyle = '#39dc79'; context.lineWidth = 3; context.strokeRect(x, y, width, height);
      context.fillStyle = '#ffffff';
      for (const [handleX, handleY] of [[x,y], [x+width,y], [x,y+height], [x+width,y+height]]) {
        context.fillRect(handleX - 4, handleY - 4, 8, 8);
      }
    }

    function updateCoordinates() {
      document.getElementById('coordinates').textContent = box
        ? `x ${box.x} · y ${box.y} · ${box.width} × ${box.height} px`
        : 'Draw a sand-bed box';
      positiveButton.disabled = !box;
    }

    function displayCurrent() {
      const item = current();
      const review = item.review;
      document.getElementById('progress').textContent = `${currentIndex + 1} / ${state.images.length} · ${reviewedCount()} reviewed`;
      document.getElementById('file').textContent = item.relative_path;
      groupInput.value = review?.split_group || state.default_split_group;
      notesInput.value = review?.notes || '';
      box = review?.decision === 'positive' ? {
        x: Number(review.x), y: Number(review.y), width: Number(review.width), height: Number(review.height)
      } : null;
      updateCoordinates();
      image.src = item.url + '?v=' + Date.now();
      setMessage(review ? `Previously saved as ${review.decision}.` : 'Unreviewed');
    }

    function nextIndex(direction, preferUnreviewed) {
      for (let offset = 1; offset < state.images.length; offset += 1) {
        const candidate = (currentIndex + direction * offset + state.images.length) % state.images.length;
        if (!preferUnreviewed || !state.images[candidate].review) return candidate;
      }
      return (currentIndex + direction + state.images.length) % state.images.length;
    }

    async function save(decision) {
      if (decision === 'positive' && !box) { setMessage('Draw the usable sand-bed box first.', 'error'); return; }
      const payload = { index: currentIndex, decision, split_group: groupInput.value, notes: notesInput.value };
      if (box) payload.box = box;
      try {
        const response = await fetch('/api/save', { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(payload) });
        const result = await response.json();
        if (!response.ok) throw new Error(result.error || 'Could not save review');
        current().review = result.review;
        setMessage('Saved locally.', 'ok');
        if (reviewedCount() < state.images.length) { currentIndex = nextIndex(1, true); displayCurrent(); }
        else { displayCurrent(); setMessage('All photos are reviewed. You can revisit any photo with the arrows.', 'ok'); }
      } catch (error) { setMessage(error.message, 'error'); }
    }

    canvas.addEventListener('pointerdown', event => { if (!image.naturalWidth) return; dragStart = pointFromEvent(event); canvas.setPointerCapture(event.pointerId); });
    canvas.addEventListener('pointermove', event => {
      if (!dragStart) return;
      const point = pointFromEvent(event); const rect = image.getBoundingClientRect();
      const left = Math.min(dragStart.x, point.x), top = Math.min(dragStart.y, point.y);
      const width = Math.abs(point.x - dragStart.x), height = Math.abs(point.y - dragStart.y);
      box = { x: Math.round(left * image.naturalWidth / rect.width), y: Math.round(top * image.naturalHeight / rect.height), width: Math.round(width * image.naturalWidth / rect.width), height: Math.round(height * image.naturalHeight / rect.height) };
      draw(); updateCoordinates();
    });
    canvas.addEventListener('pointerup', event => { dragStart = null; try { canvas.releasePointerCapture(event.pointerId); } catch (_) {} });
    image.addEventListener('load', () => { draw(); updateCoordinates(); });
    window.addEventListener('resize', draw);
    document.getElementById('positive').addEventListener('click', () => save('positive'));
    document.getElementById('negative').addEventListener('click', () => save('negative'));
    document.getElementById('exclude').addEventListener('click', () => save('exclude'));
    document.getElementById('clear').addEventListener('click', () => { box = null; draw(); updateCoordinates(); setMessage('Box cleared.'); });
    document.getElementById('previous').addEventListener('click', () => { currentIndex = nextIndex(-1, false); displayCurrent(); });
    document.getElementById('next').addEventListener('click', () => { currentIndex = nextIndex(1, false); displayCurrent(); });
    document.addEventListener('keydown', event => {
      if (['INPUT', 'TEXTAREA'].includes(document.activeElement.tagName)) return;
      if (event.key === 'p' || event.key === 'P') save('positive');
      else if (event.key === 'n' || event.key === 'N') save('negative');
      else if (event.key === 'x' || event.key === 'X') save('exclude');
      else if (event.key === 'Backspace') { event.preventDefault(); box = null; draw(); updateCoordinates(); }
      else if (event.key === 'ArrowLeft') { currentIndex = nextIndex(-1, false); displayCurrent(); }
      else if (event.key === 'ArrowRight') { currentIndex = nextIndex(1, false); displayCurrent(); }
    });

    fetch('/api/state').then(response => response.json()).then(result => { state = result; displayCurrent(); }).catch(error => setMessage(error.message, 'error'));
  </script>
</body>
</html>"""


def main() -> int:
    arguments = parse_args()
    try:
        image_root = normalize_path(arguments.image_dir)
        review_csv = normalize_path(arguments.review_csv)
        default_group = arguments.default_split_group.strip()
        if not default_group:
            raise AnnotationError("--default-split-group cannot be blank")
        if not 1 <= arguments.port <= 65535:
            raise AnnotationError("--port must be between 1 and 65535")
        items = catalogue_images(image_root)
        store = ReviewStore(review_csv, items, default_group, arguments.reviewer.strip())
        server = AnnotationServer(("127.0.0.1", arguments.port), store)
    except (AnnotationError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    url = f"http://127.0.0.1:{arguments.port}"
    print(f"Found {len(items)} supported local images.")
    print(f"Review CSV: {review_csv}")
    print(f"Open {url} in a browser. Press Control-C to stop the local server.")
    if arguments.open_browser:
        webbrowser.open(url)
    signal.signal(signal.SIGINT, lambda *_: server.shutdown())
    try:
        server.serve_forever()
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
