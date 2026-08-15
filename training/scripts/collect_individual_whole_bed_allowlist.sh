#!/usr/bin/env bash

# Verify and, only when explicitly requested, download the ten individually
# reviewed sea-turtle hatchery sand-bed sources. This is intentionally not a
# category crawler: it accepts no source URLs or record IDs as arguments.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRAINING_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RAW_ROOT="${RAW_ROOT:-$TRAINING_DIR/raw/individual-whole-bed-allowlist}"
PROVENANCE_DIR="${PROVENANCE_DIR:-$TRAINING_DIR/provenance}"
API_URL="https://commons.wikimedia.org/w/api.php"
USER_AGENT="PenyuCommunityIndividualWholeBedCollector/1.0 (provenance-first)"
REQUEST_DELAY_SECONDS="${REQUEST_DELAY_SECONDS:-10}"
FALLBACK_DELAY_SECONDS="${FALLBACK_DELAY_SECONDS:-15}"

MODE=""
for argument in "$@"; do
  case "$argument" in
    --verify)
      if [[ -n "$MODE" ]]; then
        echo "Choose exactly one of --verify or --download." >&2
        exit 64
      fi
      MODE="verify"
      ;;
    --download)
      if [[ -n "$MODE" ]]; then
        echo "Choose exactly one of --verify or --download." >&2
        exit 64
      fi
      MODE="download"
      ;;
    --help|-h)
      cat <<'USAGE'
Usage:
  bash training/scripts/collect_individual_whole_bed_allowlist.sh --verify
  bash training/scripts/collect_individual_whole_bed_allowlist.sh --download

--verify fetches only per-file Commons metadata and writes a provenance
manifest. --download first performs the same checks, then downloads the ten
approved originals into training/raw/individual-whole-bed-allowlist/.

The allowlist is compiled into this script. It has no category discovery and
accepts no source URL, title, or record-id arguments.
USAGE
      exit 0
      ;;
    *)
      echo "Unknown argument: $argument" >&2
      exit 64
      ;;
  esac
done

if [[ -z "$MODE" ]]; then
  echo "Choose --verify or --download. Nothing was requested, so no network access occurred." >&2
  exit 64
fi

for dependency in curl jq file shasum; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    echo "Missing required command: $dependency" >&2
    exit 69
  fi
done

mkdir -p "$PROVENANCE_DIR"
if [[ "$MODE" == "download" ]]; then
  mkdir -p "$RAW_ROOT"
fi

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/penyu-individual-whole-bed.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
ENTRIES_FILE="$TEMP_DIR/entries.ndjson"
DOWNLOAD_ENTRIES_FILE="$TEMP_DIR/download-entries.ndjson"
FAILURES_FILE="$TEMP_DIR/failures.ndjson"

MANIFEST_JSON="$PROVENANCE_DIR/individual-whole-bed-allowlist-images.json"
MANIFEST_CSV="$PROVENANCE_DIR/individual-whole-bed-allowlist-images.csv"
DOWNLOAD_MANIFEST_JSON="$PROVENANCE_DIR/individual-whole-bed-allowlist-downloads.json"
DOWNLOAD_MANIFEST_CSV="$PROVENANCE_DIR/individual-whole-bed-allowlist-downloads.csv"
FAILURES_JSON="$PROVENANCE_DIR/individual-whole-bed-allowlist-failures.json"
FAILURES_CSV="$PROVENANCE_DIR/individual-whole-bed-allowlist-failures.csv"
GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Seed state from previous atomic checkpoints. This makes the collector safe
# to resume after a rate limit: verified metadata and verified local images
# are not rediscovered or redownloaded merely because a later item failed.
: > "$ENTRIES_FILE"
: > "$DOWNLOAD_ENTRIES_FILE"
: > "$FAILURES_FILE"
if [[ -s "$MANIFEST_JSON" ]] && jq -e '.images | type == "array"' "$MANIFEST_JSON" >/dev/null; then
  jq -c '.images[]?' "$MANIFEST_JSON" > "$ENTRIES_FILE"
fi
if [[ -s "$DOWNLOAD_MANIFEST_JSON" ]] && jq -e '.images | type == "array"' "$DOWNLOAD_MANIFEST_JSON" >/dev/null; then
  jq -c '.images[]?' "$DOWNLOAD_MANIFEST_JSON" > "$DOWNLOAD_ENTRIES_FILE"
fi
if [[ -s "$FAILURES_JSON" ]] && jq -e '.failures | type == "array"' "$FAILURES_JSON" >/dev/null; then
  jq -c '.failures[]?' "$FAILURES_JSON" > "$FAILURES_FILE"
fi

# Format:
# id|Commons title|source page URL|facility|country|scene group|license label|
# accepted normalized license keys|acceptable credit tokens|expected MIME|visual review
#
# Keep this list deliberately closed. Adding an image means reviewing its
# individual source page and editing this file in a normal code review.
RECORDS=(
  'rancho-nuevo-kraals|File:Sea Turtle Kraals Rancho Nuevo, Mexico - DPLA - 910d40d932a20c64a822730c0ad53ced.jpg|https://commons.wikimedia.org/wiki/File:Sea_Turtle_Kraals_Rancho_Nuevo,_Mexico_-_DPLA_-_910d40d932a20c64a822730c0ad53ced.jpg|Kemp’s ridley incubation kraal, Rancho Nuevo, Tamaulipas|Mexico|rancho-nuevo-playa-dos|Public Domain|publicdomain;pdus;nocopyrightus|Tom Shearer;USFWS;U.S. Fish and Wildlife Service;Department of the Interior;National Archives|image/jpeg|Whole marked-nest sand bed in a green mesh kraal.'
  'playa-dos-kraals|File:Kemps ridley sea turtle kraals playa dos Mexico.jpg|https://commons.wikimedia.org/wiki/File:Kemps_ridley_sea_turtle_kraals_playa_dos_Mexico.jpg|Kemp’s ridley kraals, Playa Dos|Mexico|rancho-nuevo-playa-dos|Public Domain|publicdomain;pdus;nocopyrightus|Tom Shearer;USFWS;U.S. Fish and Wildlife Service;Department of the Interior;National Archives|image/jpeg|Long mesh sand enclosure, ground-level exterior view.'
  'kalipur-hatchery|File:Turtle hatchery.jpg|https://commons.wikimedia.org/wiki/File:Turtle_hatchery.jpg|Kalipur Beach turtle hatchery, Andaman and Nicobar Islands|India|kalipur-beach|CC BY-SA 4.0|ccbysa40|Arpandhar;Arpan Dhar|image/jpeg|Bamboo-walled sand hatchery with circular nest guards.'
  'tlalcoyunque-exterior|File:TurtleHatcheryTlalcoyunque.JPG|https://commons.wikimedia.org/wiki/File:TurtleHatcheryTlalcoyunque.JPG|Tlalcoyunque hatching area, Guerrero|Mexico|tlalcoyunque|CC BY-SA 4.0|ccbysa40|AlejandroLinaresGarcia|image/jpeg|Wide exterior view of a net-canopy sand bed.'
  'tlalcoyunque-interior|File:TurtleNestingTlalcoyunque.JPG|https://commons.wikimedia.org/wiki/File:TurtleNestingTlalcoyunque.JPG|Tlalcoyunque nesting and hatching area, Guerrero|Mexico|tlalcoyunque|CC BY-SA 4.0|ccbysa40|AlejandroLinaresGarcia|image/jpeg|Interior view with marked nests beneath the canopy.'
  'ventanilla-guarded-nests|File:TurtleNestsVentanilla.JPG|https://commons.wikimedia.org/wiki/File:TurtleNestsVentanilla.JPG|La Ventanilla guarded sea-turtle nests, Tonameca, Oaxaca|Mexico|la-ventanilla|CC BY-SA 3.0|ccbysa30|Thelmadatter|image/jpeg|Outdoor guarded sand-bed site.'
  'san-san-pond-sak-vivero|File:Vivero de tortugas en la playa La Mochila.jpg|https://commons.wikimedia.org/wiki/File:Vivero_de_tortugas_en_la_playa_La_Mochila.jpg|San San Pond Sak beach turtle nursery, Bocas del Toro|Panama|san-san-pond-sak|CC BY-SA 3.0|ccbysa30|Yamireyka Bethancourt;Karen Avila;Antonio Alvarado;Fundación Almanaque Azul|image/jpeg|Landscape beach nursery enclosure.'
  'playa-la-barqueta-vivero|File:Vivero de Tortugas La Mochila.jpg|https://commons.wikimedia.org/wiki/File:Vivero_de_Tortugas_La_Mochila.jpg|Playa La Barqueta Wildlife Refuge turtle nursery, Chiriquí|Panama|playa-la-barqueta|CC BY-SA 3.0|ccbysa30|Héctor Ruíz Palma;Hector Ruiz Palma;Fundación Almanaque Azul|image/jpeg|Distinct beach nursery and enclosure.'
  'ostional-widecast|File:Jairo Mora Sandoval WIDECAST 2.jpg|https://commons.wikimedia.org/wiki/File:Jairo_Mora_Sandoval_WIDECAST_2.jpg|Ostional Beach Leatherback and Pacific Green Sea Turtle Project|Costa Rica|ostional-widecast|CC BY-SA 3.0|ccbysa30|Christine Figgener;Didiher Chacón;Didiher Chacon;WIDECAST|image/jpeg|Volunteers working inside the hatchery enclosure.'
  'playa-mayorquina|File:Playa mayorquina.jpg|https://commons.wikimedia.org/wiki/File:Playa_mayorquina.jpg|Turtle breeding area/reservoir, Morrocoy National Park, Tucacas, Falcón|Venezuela|playa-mayorquina|CC BY 3.0|ccby30|NelsonMendoza99|image/jpeg|Wide outdoor turtle breeding-area/reservoir context.'
)

clean_metadata() {
  sed -E \
    -e 's/<[^>]*>/ /g' \
    -e 's/&nbsp;/ /g' \
    -e 's/&amp;/\&/g' \
    -e 's/&quot;/"/g' \
    -e 's/&#39;/'"'"'/g' \
    -e 's/[[:space:]]+/ /g' \
    -e 's/^ //' \
    -e 's/ $//'
}

normalise() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]'
}

api_metadata() {
  local title="$1"
  curl --fail --silent --show-error --location \
    --user-agent "$USER_AGENT" --get "$API_URL" \
    --data-urlencode action=query \
    --data-urlencode format=json \
    --data-urlencode formatversion=2 \
    --data-urlencode prop=imageinfo \
    --data-urlencode iiprop='url|size|mime|extmetadata' \
    --data-urlencode iiurlwidth=2048 \
    --data-urlencode "titles=$title"
}

license_is_allowed() {
  local license_key="$1"
  local accepted_keys="$2"
  local candidate
  IFS=';' read -r -a candidates <<< "$accepted_keys"
  for candidate in "${candidates[@]}"; do
    [[ "$license_key" == "$candidate" ]] && return 0
  done
  return 1
}

credit_status() {
  local author="$1"
  local credit="$2"
  local expected_tokens="$3"
  local discovered candidate candidate_key
  discovered="$(normalise "$author $credit")"

  if [[ -z "$discovered" ]]; then
    printf '%s' 'not_discoverable'
    return 0
  fi

  IFS=';' read -r -a candidates <<< "$expected_tokens"
  for candidate in "${candidates[@]}"; do
    candidate_key="$(normalise "$candidate")"
    if [[ -n "$candidate_key" && "$discovered" == *"$candidate_key"* ]]; then
      printf '%s' 'matched'
      return 0
    fi
  done

  printf '%s' 'mismatch'
}

download_once() {
  local download_url="$1"
  local destination="$2"
  curl --fail --silent --show-error --location \
    --user-agent "$USER_AGENT" "$download_url" -o "$destination"
}

atomic_replace() {
  local destination="$1"
  local source="$2"
  mv "$source" "$destination"
}

upsert_json_line() {
  local state_file="$1"
  local source_id="$2"
  local replacement="$3"
  local next_file
  next_file="$(mktemp "$TEMP_DIR/state.XXXXXX")"
  jq -c --arg source_id "$source_id" 'select(.source_id != $source_id)' "$state_file" > "$next_file"
  printf '%s\n' "$replacement" >> "$next_file"
  mv "$next_file" "$state_file"
}

remove_source_failures() {
  local source_id="$1"
  local next_file
  next_file="$(mktemp "$TEMP_DIR/failures.XXXXXX")"
  jq -c --arg source_id "$source_id" 'select(.source_id != $source_id)' "$FAILURES_FILE" > "$next_file"
  mv "$next_file" "$FAILURES_FILE"
}

metadata_entry_for() {
  local source_id="$1"
  jq -c --arg source_id "$source_id" 'select(.source_id == $source_id)' "$ENTRIES_FILE" | tail -n 1
}

download_entry_for() {
  local source_id="$1"
  jq -c --arg source_id "$source_id" 'select(.source_id == $source_id)' "$DOWNLOAD_ENTRIES_FILE" | tail -n 1
}

write_metadata_manifest() {
  local manifest_temp csv_temp
  manifest_temp="$(mktemp "$PROVENANCE_DIR/.individual-whole-bed-allowlist-images.json.XXXXXX")"
  csv_temp="$(mktemp "$PROVENANCE_DIR/.individual-whole-bed-allowlist-images.csv.XXXXXX")"

  jq -s \
    --arg generated_at "$GENERATED_AT" \
    --arg raw_root "${RAW_ROOT#"$TRAINING_DIR/"}" \
    '{schema_version: 1, generated_at: $generated_at, collection_status: "metadata_verified_only", raw_root: $raw_root, source: "Individually reviewed Wikimedia Commons file allowlist", images: sort_by(.source_id)}' \
    "$ENTRIES_FILE" > "$manifest_temp"

  {
    printf '%s\n' 'source_id,source_page_url,original_url,title,facility,country,scene_group,visual_review,expected_license,license,license_url,author,credit,credit_verification,expected_mime,remote_mime,local_filename,local_mime,sha256,width,height,source_page_id,source_timestamp,verified_at'
    jq -r '.images[] | [.source_id, .source_page_url, .original_url, .title, .facility, .country, .scene_group, .visual_review, .expected_license, .license, .license_url, .author, .credit, .credit_verification, .expected_mime, .remote_mime, .local_filename, .local_mime, .sha256, .width, .height, .source_page_id, .source_timestamp, .verified_at] | @csv' "$manifest_temp"
  } > "$csv_temp"

  atomic_replace "$MANIFEST_JSON" "$manifest_temp"
  atomic_replace "$MANIFEST_CSV" "$csv_temp"
}

write_download_manifest() {
  local manifest_temp csv_temp
  manifest_temp="$(mktemp "$PROVENANCE_DIR/.individual-whole-bed-allowlist-downloads.json.XXXXXX")"
  csv_temp="$(mktemp "$PROVENANCE_DIR/.individual-whole-bed-allowlist-downloads.csv.XXXXXX")"

  jq -s \
    --arg generated_at "$GENERATED_AT" \
    --arg raw_root "${RAW_ROOT#"$TRAINING_DIR/"}" \
    '{schema_version: 1, generated_at: $generated_at, raw_root: $raw_root, source: "Individually reviewed Wikimedia Commons file allowlist", images: sort_by(.source_id)}' \
    "$DOWNLOAD_ENTRIES_FILE" > "$manifest_temp"

  {
    printf '%s\n' 'source_id,source_page_url,original_url,download_url,download_variant,download_width,download_height,title,facility,country,scene_group,visual_review,license,license_url,author,credit,expected_mime,remote_mime,local_filename,local_mime,sha256,width,height,source_page_id,source_timestamp,collected_at'
    jq -r '.images[] | [.source_id, .source_page_url, .original_url, .download_url, .download_variant, .download_width, .download_height, .title, .facility, .country, .scene_group, .visual_review, .license, .license_url, .author, .credit, .expected_mime, .remote_mime, .local_filename, .local_mime, .sha256, .width, .height, .source_page_id, .source_timestamp, .collected_at] | @csv' "$manifest_temp"
  } > "$csv_temp"

  atomic_replace "$DOWNLOAD_MANIFEST_JSON" "$manifest_temp"
  atomic_replace "$DOWNLOAD_MANIFEST_CSV" "$csv_temp"
}

write_failure_manifest() {
  local failures_temp csv_temp
  failures_temp="$(mktemp "$PROVENANCE_DIR/.individual-whole-bed-allowlist-failures.json.XXXXXX")"
  csv_temp="$(mktemp "$PROVENANCE_DIR/.individual-whole-bed-allowlist-failures.csv.XXXXXX")"

  jq -s \
    --arg generated_at "$GENERATED_AT" \
    '{schema_version: 1, generated_at: $generated_at, failures: sort_by(.source_id, .stage)}' \
    "$FAILURES_FILE" > "$failures_temp"

  {
    printf '%s\n' 'source_id,source_page_url,original_url,title,stage,reason,attempted_at'
    jq -r '.failures[] | [.source_id, .source_page_url, .original_url, .title, .stage, .reason, .attempted_at] | @csv' "$failures_temp"
  } > "$csv_temp"

  atomic_replace "$FAILURES_JSON" "$failures_temp"
  atomic_replace "$FAILURES_CSV" "$csv_temp"
}

record_failure() {
  local source_id="$1"
  local source_page_url="$2"
  local original_url="$3"
  local title="$4"
  local stage="$5"
  local reason="$6"
  local failure_json
  failure_json="$(jq -n \
    --arg source_id "$source_id" \
    --arg source_page_url "$source_page_url" \
    --arg original_url "$original_url" \
    --arg title "$title" \
    --arg stage "$stage" \
    --arg reason "$reason" \
    --arg attempted_at "$GENERATED_AT" \
    '{source_id: $source_id, source_page_url: $source_page_url, original_url: $original_url, title: $title, stage: $stage, reason: $reason, attempted_at: $attempted_at}')"
  upsert_json_line "$FAILURES_FILE" "$source_id" "$failure_json"
  write_failure_manifest
}

metadata_cache_is_valid() {
  local entry="$1"
  local source_id="$2"
  local title="$3"
  local source_page_url="$4"
  local expected_license="$5"
  local accepted_license_keys="$6"
  local expected_credit_tokens="$7"
  local expected_mime="$8"
  local cached_license cached_license_key cached_author cached_credit cached_credit_status

  [[ -n "$entry" ]] || return 1
  [[ "$(jq -r '.source_id // empty' <<< "$entry")" == "$source_id" ]] || return 1
  [[ "$(jq -r '.title // empty' <<< "$entry")" == "$title" ]] || return 1
  [[ "$(jq -r '.source_page_url // empty' <<< "$entry")" == "$source_page_url" ]] || return 1
  [[ "$(jq -r '.expected_license // empty' <<< "$entry")" == "$expected_license" ]] || return 1
  [[ "$(jq -r '.expected_mime // empty' <<< "$entry")" == "$expected_mime" ]] || return 1
  [[ "$(jq -r '.remote_mime // empty' <<< "$entry")" == "$expected_mime" ]] || return 1
  [[ -n "$(jq -r '.original_url // empty' <<< "$entry")" ]] || return 1
  [[ -n "$(jq -r '.width // empty' <<< "$entry")" ]] || return 1
  [[ -n "$(jq -r '.height // empty' <<< "$entry")" ]] || return 1

  cached_license="$(jq -r '.license // empty' <<< "$entry")"
  cached_license_key="$(normalise "$cached_license")"
  license_is_allowed "$cached_license_key" "$accepted_license_keys" || return 1
  cached_author="$(jq -r '.author // empty' <<< "$entry")"
  cached_credit="$(jq -r '.credit // empty' <<< "$entry")"
  cached_credit_status="$(credit_status "$cached_author" "$cached_credit" "$expected_credit_tokens")"
  [[ "$cached_credit_status" != 'mismatch' ]]
}

for record in "${RECORDS[@]}"; do
  IFS='|' read -r source_id title source_page_url facility country scene_group expected_license accepted_license_keys expected_credit_tokens expected_mime visual_review <<< "$record"
  original_url=""
  thumbnail_url=""
  thumbnail_width=""
  thumbnail_height=""
  cached_metadata="$(metadata_entry_for "$source_id")"

  # A prior metadata checkpoint is enough to resume downloading. The static
  # allowlist and stored metadata are rechecked before it is trusted.
  if [[ "$MODE" == 'download' ]] && metadata_cache_is_valid "$cached_metadata" "$source_id" "$title" "$source_page_url" "$expected_license" "$accepted_license_keys" "$expected_credit_tokens" "$expected_mime"; then
    original_url="$(jq -r '.original_url' <<< "$cached_metadata")"
    width="$(jq -r '.width' <<< "$cached_metadata")"
    height="$(jq -r '.height' <<< "$cached_metadata")"
    remote_mime="$(jq -r '.remote_mime' <<< "$cached_metadata")"
    license="$(jq -r '.license' <<< "$cached_metadata")"
    license_url="$(jq -r '.license_url // empty' <<< "$cached_metadata")"
    author="$(jq -r '.author // empty' <<< "$cached_metadata")"
    credit="$(jq -r '.credit // empty' <<< "$cached_metadata")"
    source_timestamp="$(jq -r '.source_timestamp // empty' <<< "$cached_metadata")"
    source_page_id="$(jq -r '.source_page_id // empty' <<< "$cached_metadata")"
    credit_verification="$(credit_status "$author" "$credit" "$expected_credit_tokens")"
  else
    echo "Verifying $source_page_url"
    if ! response="$(api_metadata "$title")"; then
      record_failure "$source_id" "$source_page_url" "" "$title" 'metadata' 'Single Commons metadata request failed.'
      sleep "$REQUEST_DELAY_SECONDS"
      continue
    fi
    sleep "$REQUEST_DELAY_SECONDS"

    if ! page="$(jq -ce '.query.pages[0] | select(.missing | not) | select((.imageinfo | length) > 0)' <<< "$response")"; then
      record_failure "$source_id" "$source_page_url" "" "$title" 'metadata' 'Commons response did not contain image metadata.'
      continue
    fi
    image_info="$(jq -ce '.imageinfo[0]' <<< "$page")"
    remote_mime="$(jq -r '.mime // empty' <<< "$image_info")"
    license="$(jq -r '.extmetadata.LicenseShortName.value // empty' <<< "$image_info" | clean_metadata)"
    license_url="$(jq -r '.extmetadata.LicenseUrl.value // empty' <<< "$image_info")"
    if [[ -z "$license_url" ]]; then
      license_url="$source_page_url"
    fi
    author="$(jq -r '.extmetadata.Artist.value // empty' <<< "$image_info" | clean_metadata)"
    credit="$(jq -r '.extmetadata.Credit.value // empty' <<< "$image_info" | clean_metadata)"
    original_url="$(jq -r '.url // empty' <<< "$image_info")"
    thumbnail_url="$(jq -r '.thumburl // empty' <<< "$image_info")"
    thumbnail_width="$(jq -r '.thumbwidth // empty' <<< "$image_info")"
    thumbnail_height="$(jq -r '.thumbheight // empty' <<< "$image_info")"
    width="$(jq -r '.width // empty' <<< "$image_info")"
    height="$(jq -r '.height // empty' <<< "$image_info")"
    source_timestamp="$(jq -r '.timestamp // empty' <<< "$image_info")"
    source_page_id="$(jq -r '.pageid // empty' <<< "$page")"
    license_key="$(normalise "$license")"
    credit_verification="$(credit_status "$author" "$credit" "$expected_credit_tokens")"

    if [[ "$remote_mime" != "$expected_mime" || -z "$license" || -z "$original_url" || -z "$width" || -z "$height" ]]; then
      record_failure "$source_id" "$source_page_url" "$original_url" "$title" 'metadata' 'Required MIME, license, original URL, or dimensions are missing or unexpected.'
      continue
    fi
    if ! license_is_allowed "$license_key" "$accepted_license_keys"; then
      record_failure "$source_id" "$source_page_url" "$original_url" "$title" 'metadata' "License no longer matches ${expected_license}: ${license}."
      continue
    fi
    if [[ "$credit_verification" == 'mismatch' ]]; then
      record_failure "$source_id" "$source_page_url" "$original_url" "$title" 'metadata' 'Discoverable source credit no longer matches the reviewed attribution.'
      continue
    fi

    metadata_entry="$(jq -n \
      --arg source_id "$source_id" \
      --arg source_page_url "$source_page_url" \
      --arg original_url "$original_url" \
      --arg title "$title" \
      --arg facility "$facility" \
      --arg country "$country" \
      --arg scene_group "$scene_group" \
      --arg visual_review "$visual_review" \
      --arg expected_license "$expected_license" \
      --arg license "$license" \
      --arg license_url "$license_url" \
      --arg author "$author" \
      --arg credit "$credit" \
      --arg credit_verification "$credit_verification" \
      --arg expected_mime "$expected_mime" \
      --arg remote_mime "$remote_mime" \
      --arg width "$width" \
      --arg height "$height" \
      --arg source_page_id "$source_page_id" \
      --arg source_timestamp "$source_timestamp" \
      --arg verified_at "$GENERATED_AT" \
      '{source_id: $source_id, source_page_url: $source_page_url, original_url: $original_url, title: $title, facility: $facility, country: $country, scene_group: $scene_group, visual_review: $visual_review, expected_license: $expected_license, license: $license, license_url: $license_url, author: $author, credit: $credit, credit_verification: $credit_verification, expected_mime: $expected_mime, remote_mime: $remote_mime, local_filename: "", local_mime: "", sha256: "", width: $width, height: $height, source_page_id: $source_page_id, source_timestamp: $source_timestamp, verified_at: $verified_at}')"
    upsert_json_line "$ENTRIES_FILE" "$source_id" "$metadata_entry"
    write_metadata_manifest
  fi

  if [[ "$MODE" == 'verify' ]]; then
    remove_source_failures "$source_id"
    write_failure_manifest
    continue
  fi

  local_path="$RAW_ROOT/${source_id}.jpg"
  cached_download="$(download_entry_for "$source_id")"
  local_mime=""
  sha256=""
  download_url=""
  download_variant=""
  download_width=""
  download_height=""
  if [[ -s "$local_path" ]]; then
    local_mime="$(file --brief --mime-type "$local_path")"
    sha256="$(shasum -a 256 "$local_path" | awk '{print $1}')"
    expected_sha256="$(jq -r '.sha256 // empty' <<< "$cached_download")"
    if [[ "$local_mime" == "$expected_mime" && ( -z "$expected_sha256" || "$expected_sha256" == "$sha256" ) ]]; then
      download_url="$(jq -r '.download_url // empty' <<< "$cached_download")"
      download_variant="$(jq -r '.download_variant // empty' <<< "$cached_download")"
      download_width="$(jq -r '.download_width // empty' <<< "$cached_download")"
      download_height="$(jq -r '.download_height // empty' <<< "$cached_download")"
      # The pre-checkpoint collector could only have stored an original at
      # this path, so retaining its verified JPEG records that provenance.
      download_url="${download_url:-$original_url}"
      download_variant="${download_variant:-original}"
      download_width="${download_width:-$width}"
      download_height="${download_height:-$height}"
    else
      local_mime=""
      sha256=""
    fi
  fi

  if [[ -z "$sha256" ]]; then
    partial_path="$(mktemp "$TEMP_DIR/download.XXXXXX")"
    download_url="$original_url"
    download_variant='original'
    download_width="$width"
    download_height="$height"
    echo "Downloading original $original_url"
    if ! download_once "$download_url" "$partial_path"; then
      rm -f "$partial_path"
      echo "Original download failed; attempting one 2048px API thumbnail fallback after cooldown." >&2
      sleep "$FALLBACK_DELAY_SECONDS"

      # Cached metadata from older runs has no thumbnail URL. Obtain one
      # single, explicit iiurlwidth=2048 response only after original failure.
      if [[ -z "$thumbnail_url" ]]; then
        if ! fallback_response="$(api_metadata "$title")"; then
          record_failure "$source_id" "$source_page_url" "$original_url" "$title" 'thumbnail_metadata' 'Single iiurlwidth=2048 metadata request failed after original download failure.'
          sleep "$REQUEST_DELAY_SECONDS"
          continue
        fi
        sleep "$REQUEST_DELAY_SECONDS"
        thumbnail_url="$(jq -r '.query.pages[0].imageinfo[0].thumburl // empty' <<< "$fallback_response")"
        thumbnail_width="$(jq -r '.query.pages[0].imageinfo[0].thumbwidth // empty' <<< "$fallback_response")"
        thumbnail_height="$(jq -r '.query.pages[0].imageinfo[0].thumbheight // empty' <<< "$fallback_response")"
      fi
      if [[ -z "$thumbnail_url" || -z "$thumbnail_width" || -z "$thumbnail_height" ]]; then
        record_failure "$source_id" "$source_page_url" "$original_url" "$title" 'thumbnail_metadata' 'The iiurlwidth=2048 response did not expose an exact thumbnail URL and dimensions.'
        continue
      fi

      partial_path="$(mktemp "$TEMP_DIR/thumbnail.XXXXXX")"
      download_url="$thumbnail_url"
      download_variant='thumbnail_2048'
      download_width="$thumbnail_width"
      download_height="$thumbnail_height"
      echo "Downloading documented 2048px fallback $download_url"
      if ! download_once "$download_url" "$partial_path"; then
        rm -f "$partial_path"
        record_failure "$source_id" "$source_page_url" "$original_url" "$title" 'download' 'Original and one documented 2048px thumbnail download attempt failed.'
        sleep "$REQUEST_DELAY_SECONDS"
        continue
      fi
    fi

    local_mime="$(file --brief --mime-type "$partial_path")"
    if [[ "$local_mime" != "$expected_mime" ]]; then
      rm -f "$partial_path"
      record_failure "$source_id" "$source_page_url" "$original_url" "$title" 'download' "Downloaded content MIME was ${local_mime}, expected ${expected_mime}."
      continue
    fi
    sha256="$(shasum -a 256 "$partial_path" | awk '{print $1}')"
    mv "$partial_path" "$local_path"
    sleep "$REQUEST_DELAY_SECONDS"
  fi

  relative_filename="${local_path#"$TRAINING_DIR/"}"
  download_entry="$(jq -n \
    --arg source_id "$source_id" \
    --arg source_page_url "$source_page_url" \
    --arg original_url "$original_url" \
    --arg download_url "$download_url" \
    --arg download_variant "$download_variant" \
    --arg download_width "$download_width" \
    --arg download_height "$download_height" \
    --arg title "$title" \
    --arg facility "$facility" \
    --arg country "$country" \
    --arg scene_group "$scene_group" \
    --arg visual_review "$visual_review" \
    --arg license "$license" \
    --arg license_url "$license_url" \
    --arg author "$author" \
    --arg credit "$credit" \
    --arg expected_mime "$expected_mime" \
    --arg remote_mime "$remote_mime" \
    --arg local_filename "$relative_filename" \
    --arg local_mime "$local_mime" \
    --arg sha256 "$sha256" \
    --arg width "$width" \
    --arg height "$height" \
    --arg source_page_id "$source_page_id" \
    --arg source_timestamp "$source_timestamp" \
    --arg collected_at "$GENERATED_AT" \
    '{source_id: $source_id, source_page_url: $source_page_url, original_url: $original_url, download_url: $download_url, download_variant: $download_variant, download_width: $download_width, download_height: $download_height, title: $title, facility: $facility, country: $country, scene_group: $scene_group, visual_review: $visual_review, license: $license, license_url: $license_url, author: $author, credit: $credit, expected_mime: $expected_mime, remote_mime: $remote_mime, local_filename: $local_filename, local_mime: $local_mime, sha256: $sha256, width: $width, height: $height, source_page_id: $source_page_id, source_timestamp: $source_timestamp, collected_at: $collected_at}')"
  upsert_json_line "$DOWNLOAD_ENTRIES_FILE" "$source_id" "$download_entry"
  remove_source_failures "$source_id"
  write_download_manifest
  write_failure_manifest
done

printf 'Metadata provenance: %s\n' "$MANIFEST_JSON"
if [[ "$MODE" == 'download' ]]; then
  printf 'Download provenance: %s\n' "$DOWNLOAD_MANIFEST_JSON"
  printf 'Failure provenance: %s\n' "$FAILURES_JSON"
fi
