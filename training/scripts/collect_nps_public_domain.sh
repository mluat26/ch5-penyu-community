#!/usr/bin/env bash

# Download the five source-verified Padre Island sea-turtle egg-corral images
# from NPS Gallery. The original download URL is discovered from each record
# page, then the record's license, photographer, and corral description are
# checked before any image is retained.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRAINING_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RAW_ROOT="${RAW_ROOT:-$TRAINING_DIR/raw/nps-public-domain}"
PROVENANCE_DIR="${PROVENANCE_DIR:-$TRAINING_DIR/provenance}"
NPS_GALLERY_BASE="https://npgallery.nps.gov"
USER_AGENT="PenyuCommunityHatcheryDatasetCollector/1.0 (provenance-first)"
REFRESH=false

for argument in "$@"; do
  case "$argument" in
    --refresh)
      REFRESH=true
      ;;
    --help|-h)
      cat <<'USAGE'
Usage: bash training/scripts/collect_nps_public_domain.sh [--refresh]

Downloads only the five source-verified public-domain Padre Island sea-turtle
egg-corral records. Originals go in ignored training/raw/; regenerated
per-image JSON and CSV provenance manifests go in tracked training/provenance/.
USAGE
      exit 0
      ;;
    *)
      echo "Unknown argument: $argument" >&2
      exit 64
      ;;
  esac
done

for dependency in curl jq shasum file perl; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    echo "Missing required command: $dependency" >&2
    exit 69
  fi
done

mkdir -p "$RAW_ROOT" "$PROVENANCE_DIR"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/penyu-nps.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

MANIFEST_JSON="$PROVENANCE_DIR/nps-public-domain-images.json"
MANIFEST_CSV="$PROVENANCE_DIR/nps-public-domain-images.csv"
ENTRIES_FILE="$TEMP_DIR/entries.ndjson"
GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
: > "$ENTRIES_FILE"

# This allow-list is deliberate: the collector must never turn into a general
# NPS scraper. The records share a 2008 Padre Island egg-corral collection,
# but source-level membership does not make every image a hatchery positive.
RECORDS=(
  '68f65b1e-1b32-4a32-aa04-17b5909a40d6|positive|Whole fenced sand corral is visible; annotate the outer corral as hatchery.'
  '7b34d1e4-d31d-4cac-9350-64d1cb0fea8c|hard_negative|Turtle-only beach release; do not annotate as hatchery.'
  '8129555b-4fc1-4430-a1fa-7068ac637cfe|needs_review|Partial corral behind ranger and individual nest foreground; may be a positive only after final box-policy review.'
  '8953e65a-27bf-40fe-ad04-6cd009866d14|hard_negative|Hatchlings on open beach at sunset; do not annotate as hatchery.'
  'e091f743-2c01-49b2-afc9-6ada6b8d9268|hard_negative|Nighttime release boxes and no usable corral; do not annotate as hatchery.'
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

html_field() {
  local page_file="$1"
  local label="$2"

  HTML_FIELD_LABEL="$label" perl -0ne '
    my $label = quotemeta($ENV{HTML_FIELD_LABEL});
    if (m{<label[^>]*>\s*$label\s*:</label>\s*<div[^>]*>(.*?)</div>}si) {
      my $value = $1;
      $value =~ s/<[^>]+>/ /g;
      $value =~ s/&#39;/'"'"'/g;
      $value =~ s/&amp;/\&/g;
      $value =~ s/&quot;/"/g;
      $value =~ s/\s+/ /g;
      $value =~ s/^\s+|\s+$//g;
      print $value;
    }
  ' "$page_file"
}

original_metadata() {
  local page_file="$1"

  perl -0ne '
    if (m{Original\s+jpg\s+Version</label>\s*<div[^>]*>\s*<a\s+href="([^"]+)">[^<]*,\s*([0-9]+)x([0-9]+)</a>}si) {
      print "$1\t$2\t$3";
    }
  ' "$page_file"
}

for record in "${RECORDS[@]}"; do
  IFS='|' read -r asset_id annotation_role visual_review <<< "$record"
  source_page_url="$NPS_GALLERY_BASE/AssetDetail/$asset_id"
  page_file="$TEMP_DIR/$asset_id.html"
  echo "Verifying $source_page_url"
  fetch_record "$source_page_url" > "$page_file"

  title="$(html_field "$page_file" 'Title')"
  description="$(html_field "$page_file" 'Description')"
  license="$(html_field "$page_file" 'Constraints Information')"
  author="$(html_field "$page_file" 'Photographer')"
  original_file_name="$(html_field "$page_file" 'Original File Name')"
  metadata="$(original_metadata "$page_file")"
  license_lower="$(printf '%s' "$license" | tr '[:upper:]' '[:lower:]')"

  if [[ "$title" != 'Sea turtle egg corral work at Padre Island National Seashore in 2008.' || \
        "$description" != *'used a fenced area, a corral, to incubate nests from Kemp'"'"'s ridley sea turtles'* || \
        "$license_lower" != 'public domain' || \
        "$author" != 'NPS Staff Division of Sea Turtle Science and Recovery' || \
        -z "$original_file_name" || \
        -z "$metadata" ]]; then
    echo "NPS record no longer matches the approved public-domain egg-corral source: $source_page_url" >&2
    exit 65
  fi

  IFS=$'\t' read -r original_relative_url width height <<< "$metadata"
  original_url="$NPS_GALLERY_BASE$original_relative_url"
  expected_original_url="$NPS_GALLERY_BASE/GetAsset/$asset_id/original.jpg?"
  if [[ "$original_url" != "$expected_original_url" ]]; then
    echo "NPS record exposes an unexpected original URL: $source_page_url" >&2
    exit 65
  fi

  local_filename="nps-pais-egg-corral-$asset_id.jpg"
  local_path="$RAW_ROOT/$local_filename"
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
    --arg source_id "nps-pais-egg-corral-$asset_id" \
    --arg collection 'Padre Island National Seashore sea turtle egg corral, 2008' \
    --arg split_group 'nps-pais-egg-corral-2008' \
    --arg annotation_role "$annotation_role" \
    --arg visual_review "$visual_review" \
    --arg local_filename "$relative_filename" \
    --arg source_page_url "$source_page_url" \
    --arg original_url "$original_url" \
    --arg original_file_name "$original_file_name" \
    --arg title "$title" \
    --arg description "$description" \
    --arg author "$author" \
    --arg credit "$author" \
    --arg license 'Public Domain' \
    --arg license_url "$source_page_url" \
    --arg facility 'Padre Island National Seashore' \
    --arg mime "$mime_type" \
    --arg width "$width" \
    --arg height "$height" \
    --arg sha256 "$sha256" \
    --arg verified_at "$GENERATED_AT" \
    '{source_id: $source_id, collection: $collection, split_group: $split_group, annotation_role: $annotation_role, visual_review: $visual_review, local_filename: $local_filename, source_page_url: $source_page_url, original_url: $original_url, original_file_name: $original_file_name, title: $title, description: $description, author: $author, credit: $credit, license: $license, license_url: $license_url, facility: $facility, mime: $mime, width: $width, height: $height, sha256: $sha256, verified_at: $verified_at}' \
    >> "$ENTRIES_FILE"
done

jq -s \
  --arg generated_at "$GENERATED_AT" \
  --arg raw_root "${RAW_ROOT#"$TRAINING_DIR/"}" \
  '{schema_version: 1, generated_at: $generated_at, raw_root: $raw_root, source: "National Park Service NPGallery", images: sort_by(.source_id)}' \
  "$ENTRIES_FILE" > "$MANIFEST_JSON"

{
  printf '%s\n' 'source_id,collection,split_group,annotation_role,visual_review,local_filename,source_page_url,original_url,original_file_name,title,description,author,credit,license,license_url,facility,mime,width,height,sha256,verified_at'
  jq -r '.images[] | [.source_id, .collection, .split_group, .annotation_role, .visual_review, .local_filename, .source_page_url, .original_url, .original_file_name, .title, .description, .author, .credit, .license, .license_url, .facility, .mime, .width, .height, .sha256, .verified_at] | @csv' "$MANIFEST_JSON"
} > "$MANIFEST_CSV"

printf 'Collected %s source-verified public-domain NPS images.\n' "$(jq '.images | length' "$MANIFEST_JSON")"
printf 'Provenance JSON: %s\n' "$MANIFEST_JSON"
printf 'Provenance CSV: %s\n' "$MANIFEST_CSV"
