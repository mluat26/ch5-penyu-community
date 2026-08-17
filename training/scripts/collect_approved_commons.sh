#!/usr/bin/env bash

# Collect only the explicitly approved Wikimedia Commons hatchery pools. The
# resulting per-image provenance manifests are tracked; source images and the
# HTML contact sheet are intentionally written under ignored training paths.
#
# The collector is deliberately resumable. It writes an atomic provenance
# snapshot after every verified image, records failures separately, and never
# adds a partial/corrupt download to a tracked manifest.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRAINING_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RAW_ROOT="${RAW_ROOT:-$TRAINING_DIR/raw/commons-approved}"
PROVENANCE_DIR="${PROVENANCE_DIR:-$TRAINING_DIR/provenance}"
EXPORT_DIR="${EXPORT_DIR:-$TRAINING_DIR/exports}"
API_URL="https://commons.wikimedia.org/w/api.php"
USER_AGENT="PenyuCommunityHatcheryDatasetCollector/1.1 (provenance-first; contact project maintainers)"
REQUEST_DELAY_SECONDS="${REQUEST_DELAY_SECONDS:-5}"
API_MAX_ATTEMPTS="${API_MAX_ATTEMPTS:-3}"
ORIGINAL_MAX_ATTEMPTS="${ORIGINAL_MAX_ATTEMPTS:-1}"
THUMBNAIL_MAX_ATTEMPTS="${THUMBNAIL_MAX_ATTEMPTS:-2}"
INITIAL_BACKOFF_SECONDS="${INITIAL_BACKOFF_SECONDS:-15}"

REFRESH=false
BUILD_CONTACT_SHEET=true

for argument in "$@"; do
  case "$argument" in
    --refresh)
      REFRESH=true
      ;;
    --no-contact-sheet)
      BUILD_CONTACT_SHEET=false
      ;;
    --help|-h)
      cat <<'USAGE'
Usage: bash training/scripts/collect_approved_commons.sh [--refresh] [--no-contact-sheet]

Downloads only the three user-approved CC BY-SA Wikimedia Commons categories.
Existing verified files are retained. Provenance is atomically checkpointed
after every verified image; failed downloads are recorded separately and can
be retried by running the same command later.
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

mkdir -p "$RAW_ROOT" "$PROVENANCE_DIR" "$EXPORT_DIR"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/penyu-commons.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

STATE_ENTRIES_FILE="$TEMP_DIR/entries.ndjson"
STATE_FAILURES_FILE="$TEMP_DIR/failures.ndjson"
: > "$STATE_ENTRIES_FILE"
: > "$STATE_FAILURES_FILE"

MANIFEST_JSON="$PROVENANCE_DIR/commons-approved-images.json"
MANIFEST_CSV="$PROVENANCE_DIR/commons-approved-images.csv"
FAILURES_JSON="$PROVENANCE_DIR/commons-approved-failures.json"
FAILURES_CSV="$PROVENANCE_DIR/commons-approved-failures.csv"
REVIEW_OVERRIDES_JSON="$PROVENANCE_DIR/commons-approved-review-overrides.json"
CONTACT_SHEET="$EXPORT_DIR/commons-approved-contact-sheet.html"
GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
RECORD_NUMBER=0
RUN_DISCOVERED_RECORDS=0
RUN_VERIFIED_RECORDS=0
RUN_SKIPPED_RECORDS=0
API_FAILURE_REASON=""
DOWNLOAD_FAILURE_REASON=""

# Do not add an arbitrary category argument here. Keeping this list in source
# control prevents accidental collection of a non-approved Commons pool.
APPROVED_CATEGORIES=(
  "Pawikan Conservation Center|pawikan-conservation-center"
  "Sea Turtles egg care center, Visakhapatnam|visakhapatnam-egg-care-center"
  "Ogasawara Marine Center|ogasawara-marine-center"
)

if [[ -s "$MANIFEST_JSON" ]] && jq -e '.images | type == "array"' "$MANIFEST_JSON" >/dev/null; then
  jq -c '.images[]?' "$MANIFEST_JSON" > "$STATE_ENTRIES_FILE"
fi
if [[ -s "$FAILURES_JSON" ]] && jq -e '.failures | type == "array"' "$FAILURES_JSON" >/dev/null; then
  jq -c '.failures[]?' "$FAILURES_JSON" > "$STATE_FAILURES_FILE"
fi

atomic_replace() {
  local destination="$1"
  local source="$2"
  mv "$source" "$destination"
}

api_get() {
  local attempt response_path delay_seconds curl_error curl_status
  API_FAILURE_REASON=""

  for ((attempt = 1; attempt <= API_MAX_ATTEMPTS; attempt++)); do
    response_path="$(mktemp "$TEMP_DIR/api-response.XXXXXX")"
    curl_status=0
    curl_error="$(curl --fail --silent --show-error --location \
      --user-agent "$USER_AGENT" --get "$API_URL" "$@" -o "$response_path" 2>&1)" || curl_status=$?
    if [[ "$curl_status" -eq 0 ]]; then
      cat "$response_path"
      rm -f "$response_path"
      sleep "$REQUEST_DELAY_SECONDS"
      return 0
    fi

    rm -f "$response_path"
    API_FAILURE_REASON="curl exit ${curl_status}: ${curl_error:-unknown API error}"
    delay_seconds=$((INITIAL_BACKOFF_SECONDS * attempt))
    echo "Commons API request failed; cooling off for ${delay_seconds}s (attempt ${attempt}/${API_MAX_ATTEMPTS}): $API_FAILURE_REASON" >&2
    sleep "$delay_seconds"
  done

  return 1
}

download_image() {
  local download_url="$1"
  local local_path="$2"
  local max_attempts="$3"
  local cool_off_after_last_failure="$4"
  local attempt partial_path delay_seconds curl_error curl_status
  DOWNLOAD_FAILURE_REASON=""

  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    partial_path="$(mktemp "$TEMP_DIR/image-download.XXXXXX")"
    curl_status=0
    curl_error="$(curl --fail --silent --show-error --location \
      --user-agent "$USER_AGENT" "$download_url" -o "$partial_path" 2>&1)" || curl_status=$?
    if [[ "$curl_status" -eq 0 ]]; then
      mv "$partial_path" "$local_path"
      sleep "$REQUEST_DELAY_SECONDS"
      return 0
    fi

    rm -f "$partial_path"
    DOWNLOAD_FAILURE_REASON="curl exit ${curl_status}: ${curl_error:-unknown download error}"
    if (( attempt < max_attempts )) || [[ "$cool_off_after_last_failure" == true ]]; then
      delay_seconds=$((INITIAL_BACKOFF_SECONDS * attempt))
      echo "Image download failed; cooling off for ${delay_seconds}s (attempt ${attempt}/${max_attempts}): $DOWNLOAD_FAILURE_REASON" >&2
      sleep "$delay_seconds"
    fi
  done

  return 1
}

clean_metadata() {
  sed -E \
    -e 's/<[^>]*>/ /g' \
    -e 's/&nbsp;/ /g' \
    -e 's/&amp;/\&/g' \
    -e 's/[[:space:]]+/ /g' \
    -e 's/^ //' \
    -e 's/ $//'
}

extension_for_mime() {
  case "$1" in
    image/jpeg) printf '%s' 'jpg' ;;
    image/png) printf '%s' 'png' ;;
    image/tiff) printf '%s' 'tif' ;;
    image/webp) printf '%s' 'webp' ;;
    *) printf '%s' 'bin' ;;
  esac
}

verified_image_mime() {
  local local_path="$1"
  local detected_mime
  [[ -s "$local_path" ]] || return 1
  detected_mime="$(file --brief --mime-type "$local_path")"
  case "$detected_mime" in
    image/jpeg|image/png|image/tiff|image/webp)
      printf '%s' "$detected_mime"
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

review_fields_for() {
  local local_filename="$1"
  if [[ -s "$REVIEW_OVERRIDES_JSON" ]]; then
    jq -c --arg local_filename "$local_filename" \
      '.overrides[$local_filename] // {review_disposition: "needs_human_review", review_note: ""}' \
      "$REVIEW_OVERRIDES_JSON"
  else
    printf '%s' '{"review_disposition":"needs_human_review","review_note":""}'
  fi
}

write_success_manifest() {
  local collection_status="$1"
  local image_temp csv_temp
  image_temp="$(mktemp "$PROVENANCE_DIR/.commons-approved-images.json.XXXXXX")"
  csv_temp="$(mktemp "$PROVENANCE_DIR/.commons-approved-images.csv.XXXXXX")"

  jq -s \
    --arg generated_at "$GENERATED_AT" \
    --arg collection_status "$collection_status" \
    --arg raw_root "${RAW_ROOT#"$TRAINING_DIR/"}" \
    --argjson approved_categories '["Category:Pawikan Conservation Center", "Category:Sea Turtles egg care center, Visakhapatnam", "Category:Ogasawara Marine Center"]' \
    '{schema_version: 2, generated_at: $generated_at, collection_status: $collection_status, raw_root: $raw_root, approved_categories: $approved_categories, images: sort_by(.category, .title)}' \
    "$STATE_ENTRIES_FILE" > "$image_temp"

  {
    printf '%s\n' 'local_filename,category,source_page_url,original_url,download_url,download_variant,download_width,download_height,title,author,credit,license,license_url,mime,width,height,sha256,review_disposition,review_note,collected_at'
    jq -r '.images[] | [.local_filename, .category, .source_page_url, .original_url, .download_url, .download_variant, .download_width, .download_height, .title, .author, .credit, .license, .license_url, .mime, .width, .height, .sha256, .review_disposition, .review_note, .collected_at] | @csv' "$image_temp"
  } > "$csv_temp"

  atomic_replace "$MANIFEST_JSON" "$image_temp"
  atomic_replace "$MANIFEST_CSV" "$csv_temp"
}

write_failure_manifest() {
  local failures_temp csv_temp
  failures_temp="$(mktemp "$PROVENANCE_DIR/.commons-approved-failures.json.XXXXXX")"
  csv_temp="$(mktemp "$PROVENANCE_DIR/.commons-approved-failures.csv.XXXXXX")"

  jq -s \
    --arg generated_at "$GENERATED_AT" \
    '{schema_version: 1, generated_at: $generated_at, failures: sort_by(.failure_key)}' \
    "$STATE_FAILURES_FILE" > "$failures_temp"

  {
    printf '%s\n' 'failure_key,category,source_page_url,original_url,title,stage,reason,attempted_at'
    jq -r '.failures[] | [.failure_key, .category, .source_page_url, .original_url, .title, .stage, .reason, .attempted_at] | @csv' "$failures_temp"
  } > "$csv_temp"

  atomic_replace "$FAILURES_JSON" "$failures_temp"
  atomic_replace "$FAILURES_CSV" "$csv_temp"
}

remove_failure() {
  local failure_key="$1"
  local next_file
  next_file="$(mktemp "$TEMP_DIR/failures.XXXXXX")"
  jq -c --arg failure_key "$failure_key" 'select(.failure_key != $failure_key)' "$STATE_FAILURES_FILE" > "$next_file"
  mv "$next_file" "$STATE_FAILURES_FILE"
}

record_failure() {
  local failure_key="$1"
  local category="$2"
  local source_page_url="$3"
  local original_url="$4"
  local title="$5"
  local stage="$6"
  local reason="$7"
  local next_file failure_record
  next_file="$(mktemp "$TEMP_DIR/failures.XXXXXX")"
  jq -c --arg failure_key "$failure_key" 'select(.failure_key != $failure_key)' "$STATE_FAILURES_FILE" > "$next_file"
  failure_record="$(jq -cn \
    --arg failure_key "$failure_key" \
    --arg category "$category" \
    --arg source_page_url "$source_page_url" \
    --arg original_url "$original_url" \
    --arg title "$title" \
    --arg stage "$stage" \
    --arg reason "$reason" \
    --arg attempted_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{failure_key: $failure_key, category: $category, source_page_url: $source_page_url, original_url: $original_url, title: $title, stage: $stage, reason: $reason, attempted_at: $attempted_at}')"
  printf '%s\n' "$failure_record" >> "$next_file"
  mv "$next_file" "$STATE_FAILURES_FILE"
  write_failure_manifest
}

upsert_success() {
  local source_page_url="$1"
  local success_record="$2"
  local next_file
  next_file="$(mktemp "$TEMP_DIR/entries.XXXXXX")"
  jq -c --arg source_page_url "$source_page_url" 'select(.source_page_url != $source_page_url)' "$STATE_ENTRIES_FILE" > "$next_file"
  printf '%s\n' "$success_record" >> "$next_file"
  mv "$next_file" "$STATE_ENTRIES_FILE"
  remove_failure "$source_page_url"
  write_success_manifest "in_progress"
  write_failure_manifest
}

collect_metadata_record() {
  local metadata_path="$1"
  local category="$2"
  local category_slug="$3"
  local original_url source_page_url thumbnail_url title author credit license license_url mime width height thumb_width thumb_height
  original_url="$(jq -r '.imageinfo[0].url // empty' "$metadata_path")"
  source_page_url="$(jq -r '.imageinfo[0].descriptionurl // empty' "$metadata_path")"
  thumbnail_url="$(jq -r '.imageinfo[0].thumburl // empty' "$metadata_path")"
  title="$(jq -r '.title // empty' "$metadata_path")"
  author="$(jq -r '.imageinfo[0].extmetadata.Artist.value // empty' "$metadata_path" | clean_metadata)"
  credit="$(jq -r '.imageinfo[0].extmetadata.Credit.value // empty' "$metadata_path" | clean_metadata)"
  license="$(jq -r '.imageinfo[0].extmetadata.LicenseShortName.value // empty' "$metadata_path" | clean_metadata)"
  license_url="$(jq -r '.imageinfo[0].extmetadata.LicenseUrl.value // empty' "$metadata_path")"
  mime="$(jq -r '.imageinfo[0].mime // empty' "$metadata_path")"
  width="$(jq -r '.imageinfo[0].width // empty' "$metadata_path")"
  height="$(jq -r '.imageinfo[0].height // empty' "$metadata_path")"
  thumb_width="$(jq -r '.imageinfo[0].thumbwidth // empty' "$metadata_path")"
  thumb_height="$(jq -r '.imageinfo[0].thumbheight // empty' "$metadata_path")"

  if [[ -z "$original_url" || -z "$source_page_url" || -z "$license" ]]; then
    record_failure "${source_page_url:-category:$category:$title}" "Category:$category" "$source_page_url" "$original_url" "$title" "metadata" "Missing required Commons image metadata"
    return 1
  fi

  if [[ "$license" != *"CC BY-SA"* && "$license" != *"CC-BY-SA"* ]]; then
    record_failure "$source_page_url" "Category:$category" "$source_page_url" "$original_url" "$title" "license" "Per-file license is not CC BY-SA; excluded from this approved-only collection"
    return 1
  fi

  local hash extension filename category_dir local_path local_filename verified_mime download_url download_variant download_width download_height failure_reason
  hash="$(printf '%s' "$source_page_url" | shasum -a 256 | awk '{print substr($1, 1, 12)}')"
  extension="$(extension_for_mime "$mime")"
  filename="${category_slug}-${hash}.${extension}"
  category_dir="$RAW_ROOT/$category_slug"
  local_path="$category_dir/$filename"
  local_filename="${local_path#"$TRAINING_DIR/"}"
  mkdir -p "$category_dir"
  download_url="$original_url"
  download_variant="original"
  download_width="$width"
  download_height="$height"

  if [[ "$REFRESH" == true ]] || ! verified_image_mime "$local_path" >/dev/null; then
    echo "Downloading $title"
    if ! download_image "$original_url" "$local_path" "$ORIGINAL_MAX_ATTEMPTS" true; then
      failure_reason="original download failed: $DOWNLOAD_FAILURE_REASON"
      if [[ -n "$thumbnail_url" ]]; then
        echo "Trying 2048px Commons derivative for $title" >&2
        if download_image "$thumbnail_url" "$local_path" "$THUMBNAIL_MAX_ATTEMPTS" false; then
          download_url="$thumbnail_url"
          download_variant="thumbnail_2048"
          download_width="$thumb_width"
          download_height="$thumb_height"
        else
          failure_reason+="; thumbnail download failed: $DOWNLOAD_FAILURE_REASON"
          record_failure "$source_page_url" "Category:$category" "$source_page_url" "$original_url" "$title" "download" "$failure_reason"
          return 1
        fi
      else
        record_failure "$source_page_url" "Category:$category" "$source_page_url" "$original_url" "$title" "download" "$failure_reason; no 2048px derivative URL supplied by Commons"
        return 1
      fi
    fi
  fi

  if ! verified_mime="$(verified_image_mime "$local_path")"; then
    record_failure "$source_page_url" "Category:$category" "$source_page_url" "$original_url" "$title" "verification" "Downloaded/cache file is not a supported image; it was excluded from the success manifest"
    return 1
  fi

  local sha256 review_fields review_disposition review_note success_record
  sha256="$(shasum -a 256 "$local_path" | awk '{print $1}')"
  review_fields="$(review_fields_for "$local_filename")"
  review_disposition="$(jq -r '.review_disposition // "needs_human_review"' <<< "$review_fields")"
  review_note="$(jq -r '.review_note // ""' <<< "$review_fields")"
  success_record="$(jq -cn \
    --arg local_filename "$local_filename" \
    --arg category "Category:$category" \
    --arg source_page_url "$source_page_url" \
    --arg original_url "$original_url" \
    --arg download_url "$download_url" \
    --arg download_variant "$download_variant" \
    --arg download_width "$download_width" \
    --arg download_height "$download_height" \
    --arg title "$title" \
    --arg author "$author" \
    --arg credit "$credit" \
    --arg license "$license" \
    --arg license_url "$license_url" \
    --arg mime "$verified_mime" \
    --arg width "$width" \
    --arg height "$height" \
    --arg sha256 "$sha256" \
    --arg review_disposition "$review_disposition" \
    --arg review_note "$review_note" \
    --arg collected_at "$GENERATED_AT" \
    '{local_filename: $local_filename, category: $category, source_page_url: $source_page_url, original_url: $original_url, download_url: $download_url, download_variant: $download_variant, download_width: $download_width, download_height: $download_height, title: $title, author: $author, credit: $credit, license: $license, license_url: $license_url, mime: $mime, width: $width, height: $height, sha256: $sha256, review_disposition: $review_disposition, review_note: $review_note, collected_at: $collected_at}')"
  upsert_success "$source_page_url" "$success_record"
  RUN_VERIFIED_RECORDS=$((RUN_VERIFIED_RECORDS + 1))
}

for category_entry in "${APPROVED_CATEGORIES[@]}"; do
  category="${category_entry%%|*}"
  category_slug="${category_entry##*|}"
  continuation=""

  while :; do
    request=(
      --data-urlencode 'action=query'
      --data-urlencode 'format=json'
      --data-urlencode 'formatversion=2'
      --data-urlencode 'generator=categorymembers'
      --data-urlencode "gcmtitle=Category:$category"
      --data-urlencode 'gcmnamespace=6'
      --data-urlencode 'gcmtype=file'
      --data-urlencode 'gcmlimit=max'
      --data-urlencode 'prop=imageinfo'
      --data-urlencode 'iiprop=url|extmetadata|size|mime'
      --data-urlencode 'iiurlwidth=2048'
    )
    if [[ -n "$continuation" ]]; then
      request+=(--data-urlencode "gcmcontinue=$continuation")
    fi

    category_page="$TEMP_DIR/${category_slug}-$(printf '%s' "${continuation:-first}" | shasum -a 256 | awk '{print substr($1, 1, 8)}').json"
    if ! api_get "${request[@]}" > "$category_page"; then
      record_failure "category:$category" "Category:$category" "" "" "$category" "category_enumeration" "$API_FAILURE_REASON"
      RUN_SKIPPED_RECORDS=$((RUN_SKIPPED_RECORDS + 1))
      break
    fi

    records_file="$TEMP_DIR/${category_slug}-records-$RECORD_NUMBER.ndjson"
    jq -c '.query.pages[]? | select(.imageinfo[0] != null)' "$category_page" > "$records_file"
    while IFS= read -r page_record; do
      [[ -z "$page_record" ]] && continue
      RECORD_NUMBER=$((RECORD_NUMBER + 1))
      RUN_DISCOVERED_RECORDS=$((RUN_DISCOVERED_RECORDS + 1))
      metadata_path="$TEMP_DIR/metadata-$RECORD_NUMBER.json"
      printf '%s\n' "$page_record" > "$metadata_path"
      if ! collect_metadata_record "$metadata_path" "$category" "$category_slug"; then
        RUN_SKIPPED_RECORDS=$((RUN_SKIPPED_RECORDS + 1))
      fi
    done < "$records_file"

    continuation="$(jq -r '.continue.gcmcontinue // empty' "$category_page")"
    [[ -z "$continuation" ]] && break
  done
done

if [[ "$RUN_SKIPPED_RECORDS" -eq 0 ]]; then
  collection_status="complete"
else
  collection_status="complete_with_failures"
fi
write_success_manifest "$collection_status"
write_failure_manifest

if [[ "$BUILD_CONTACT_SHEET" == true ]]; then
  contact_temp="$(mktemp "$EXPORT_DIR/.commons-approved-contact-sheet.html.XXXXXX")"
  {
    printf '%s\n' '<!doctype html><html lang="en"><meta charset="utf-8"><title>Approved Commons hatchery review</title><style>body{font:14px -apple-system,sans-serif;margin:24px;background:#f5f5f5}main{display:grid;grid-template-columns:repeat(auto-fill,minmax(250px,1fr));gap:16px}article{background:#fff;padding:10px;border-radius:8px;box-shadow:0 1px 4px #0002}img{width:100%;height:185px;object-fit:contain;background:#eee}p{margin:7px 0;word-break:break-word}.meta{color:#555;font-size:12px}.negative{color:#9b1c1c}</style><h1>Approved Commons hatchery review</h1><p>Derived local preview. Review each image against the tracked provenance manifest before annotation.</p><main>'
    jq -r '
      def html: tostring | gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;") | gsub("\\\""; "&quot;");
      .images[] |
      "<article><a href=\"" + .source_page_url + "\"><img loading=\"lazy\" src=\"../" + .local_filename + "\" alt=\"" + (.title | html) + "\"></a><p><strong>" + (.title | html) + "</strong></p><p class=\"meta " + (if .review_disposition == "hard_negative_candidate" then "negative" else "" end) + "\">" + (.category | html) + "<br>" + (.license | html) + "<br>" + (.author | html) + "<br>Review: " + (.review_disposition | html) + "</p></article>"
    ' "$MANIFEST_JSON"
    printf '%s\n' '</main></html>'
  } > "$contact_temp"
  atomic_replace "$CONTACT_SHEET" "$contact_temp"
fi

image_count="$(jq '.images | length' "$MANIFEST_JSON")"
failure_count="$(jq '.failures | length' "$FAILURES_JSON")"
printf 'Verified approved Commons images: %s\n' "$image_count"
printf 'Current failures/skips: %s\n' "$failure_count"
printf 'Provenance JSON: %s\n' "$MANIFEST_JSON"
printf 'Provenance CSV: %s\n' "$MANIFEST_CSV"
printf 'Failure JSON: %s\n' "$FAILURES_JSON"
printf 'Failure CSV: %s\n' "$FAILURES_CSV"
if [[ "$BUILD_CONTACT_SHEET" == true ]]; then
  printf 'Contact sheet: %s\n' "$CONTACT_SHEET"
fi
