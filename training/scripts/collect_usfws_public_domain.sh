#!/usr/bin/env bash

# Download the five source-verified Cape Romain turtle hatchery photos from
# FWS. Every run revalidates that the record exposes the expected original,
# credit, and Public Domain license before saving an image locally.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRAINING_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RAW_ROOT="${RAW_ROOT:-$TRAINING_DIR/raw/usfws-public-domain}"
PROVENANCE_DIR="${PROVENANCE_DIR:-$TRAINING_DIR/provenance}"
USER_AGENT="Mozilla/5.0 (compatible; PenyuCommunityDatasetCollector/1.0; +https://github.com/mluat26/ch5-penyu-community)"
FWS_MEDIA_BASE="https://www.fws.gov/media"
FWS_IMAGE_BASE="https://www.fws.gov/sites/default/files/images/2024-03-5"
REFRESH=false

for argument in "$@"; do
  case "$argument" in
    --refresh)
      REFRESH=true
      ;;
    --help|-h)
      cat <<'USAGE'
Usage: bash training/scripts/collect_usfws_public_domain.sh [--refresh]

Downloads only the five source-verified, public-domain Cape Romain turtle
hatchery records. Source images are placed in ignored training/raw/ and the
tracked CSV and JSON manifests are regenerated under training/provenance/.
USAGE
      exit 0
      ;;
    *)
      echo "Unknown argument: $argument" >&2
      exit 64
      ;;
  esac
done

for dependency in curl jq shasum file; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    echo "Missing required command: $dependency" >&2
    exit 69
  fi
done

mkdir -p "$RAW_ROOT" "$PROVENANCE_DIR"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/penyu-usfws.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

MANIFEST_JSON="$PROVENANCE_DIR/usfws-public-domain-images.json"
MANIFEST_CSV="$PROVENANCE_DIR/usfws-public-domain-images.csv"
ENTRIES_FILE="$TEMP_DIR/entries.ndjson"
GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
: > "$ENTRIES_FILE"

# slug | FWS original image id | caption captured from the FWS record page.
# Keep this allow-list in source control: no arbitrary FWS URLs are accepted.
RECORDS=(
  'turtle-nest-hatchery|12133|Refuge Manager Kevin Godsea standing by a 25 nest hatchery on Cape Island, SC.'
  'turtle-nest-hatchery-0|12134|From left to right, volunteer Katie Snipes, Refuge Manger Kevin Godsea, and ES biologist Melissa Bimbi relocating loggerhead sea turtle nests into a hatchery on Cape Island, SC.'
  'turtle-nest-hatchery-1|12138|Replacing the top on a 25 nests hatchery after completing nest relocation on Cape Island, SC.'
  'turtle-nest-hatchery-2|12139|50 nests hatchery on Cape Island sandbagged to protect it from predicted possible tropical storm activity.'
  'turtle-nest-hatchery-3|12141|Refuge Manager Kevin Godsea by a 25 nest hatchery on Cape Island, SC.'
)

fetch_record() {
  local source_page_url="$1"
  curl --fail --silent --show-error --location --retry 3 --retry-all-errors \
    --user-agent "$USER_AGENT" "$source_page_url"
}

download_original() {
  local original_url="$1"
  local local_path="$2"
  local partial_path
  partial_path="$(mktemp "$TEMP_DIR/original.XXXXXX")"
  if curl --fail --silent --show-error --location --retry 3 --retry-all-errors \
    --user-agent "$USER_AGENT" "$original_url" -o "$partial_path"; then
    mv "$partial_path" "$local_path"
  else
    rm -f "$partial_path"
    return 1
  fi
}

for record in "${RECORDS[@]}"; do
  IFS='|' read -r slug image_id caption <<< "$record"
  source_page_url="$FWS_MEDIA_BASE/$slug"
  original_url="$FWS_IMAGE_BASE/$image_id.jpg"
  local_filename="usfws-$slug.jpg"
  local_path="$RAW_ROOT/$local_filename"

  echo "Verifying $source_page_url"
  page_html="$(fetch_record "$source_page_url")"

  # Do not trust an image URL alone: the FWS record must explicitly identify
  # it as public domain, attribute it to USFWS, and expose this exact original.
  if [[ "$page_html" != *'Media Usage Rights/License'* || \
        "$page_html" != *'>Public Domain<'* || \
        "$page_html" != *'Hillebrand, Steve/USFWS'* || \
        "$page_html" != *"href=\"$original_url\" class=\"photoswipe\""* || \
        "$page_html" != *'data-pswp-width="3504" data-pswp-height="2336"'* ]]; then
    echo "FWS record no longer matches the approved public-domain source: $source_page_url" >&2
    exit 65
  fi

  if [[ "$REFRESH" == true || ! -s "$local_path" ]]; then
    echo "Downloading $original_url"
    download_original "$original_url" "$local_path"
  fi

  mime_type="$(file -b --mime-type "$local_path")"
  if [[ "$mime_type" != 'image/jpeg' ]]; then
    echo "Downloaded file is not JPEG: $local_path ($mime_type)" >&2
    exit 65
  fi

  sha256="$(shasum -a 256 "$local_path" | awk '{print $1}')"
  relative_filename="${local_path#"$TRAINING_DIR/"}"

  jq -n \
    --arg source_id "usfws-$slug" \
    --arg local_filename "$relative_filename" \
    --arg source_page_url "$source_page_url" \
    --arg original_url "$original_url" \
    --arg title 'Turtle nest hatchery' \
    --arg caption "$caption" \
    --arg author 'Hillebrand, Steve' \
    --arg credit 'Hillebrand, Steve/USFWS' \
    --arg license 'Public Domain' \
    --arg license_url "$source_page_url" \
    --arg facility 'Cape Romain National Wildlife Refuge' \
    --arg scene_group 'cape-romain-turtle-nest-hatchery-sequence' \
    --arg mime "$mime_type" \
    --arg width '3504' \
    --arg height '2336' \
    --arg sha256 "$sha256" \
    --arg verified_at "$GENERATED_AT" \
    '{source_id: $source_id, local_filename: $local_filename, source_page_url: $source_page_url, original_url: $original_url, title: $title, caption: $caption, author: $author, credit: $credit, license: $license, license_url: $license_url, facility: $facility, scene_group: $scene_group, mime: $mime, width: $width, height: $height, sha256: $sha256, verified_at: $verified_at}' \
    >> "$ENTRIES_FILE"
done

jq -s \
  --arg generated_at "$GENERATED_AT" \
  --arg raw_root "${RAW_ROOT#"$TRAINING_DIR/"}" \
  '{schema_version: 1, generated_at: $generated_at, raw_root: $raw_root, source: "U.S. Fish & Wildlife Service", images: sort_by(.source_id)}' \
  "$ENTRIES_FILE" > "$MANIFEST_JSON"

{
  printf '%s\n' 'source_id,local_filename,source_page_url,original_url,title,caption,author,credit,license,license_url,facility,scene_group,mime,width,height,sha256,verified_at'
  jq -r '.images[] | [.source_id, .local_filename, .source_page_url, .original_url, .title, .caption, .author, .credit, .license, .license_url, .facility, .scene_group, .mime, .width, .height, .sha256, .verified_at] | @csv' "$MANIFEST_JSON"
} > "$MANIFEST_CSV"

printf 'Collected %s source-verified public-domain USFWS images.\n' "$(jq '.images | length' "$MANIFEST_JSON")"
printf 'Provenance JSON: %s\n' "$MANIFEST_JSON"
printf 'Provenance CSV: %s\n' "$MANIFEST_CSV"
