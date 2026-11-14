#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

usage() {
  cat <<'EOF'
Usage:
  ./build.sh <github-url> [--ref <branch-or-tag> | --commit <sha>] [--existing]

Options:
  --ref <ref>       Branch or tag to build
  --commit <sha>    Exact commit to build
  --existing        Use existing recipe at apps/<RepoName>/metadata.yml
  -h, --help        Show help
EOF
}

log() { printf '[build] %s\n' "$*"; }
warn() { printf '[build] WARN: %s\n' "$*" >&2; }
die() { printf '[build] ERROR: %s\n' "$*" >&2; exit 1; }

if [ $# -lt 1 ]; then usage; exit 1; fi

GITHUB_URL=""
REF=""
COMMIT=""
EXISTING=0

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --ref)
      [ $# -ge 2 ] || die "--ref requires a value"
      REF="$2"; shift 2 ;;
    --commit)
      [ $# -ge 2 ] || die "--commit requires a value"
      COMMIT="$2"; shift 2 ;;
    --existing)
      EXISTING=1; shift ;;
    --*)
      die "Unknown option: $1" ;;
    *)
      if [ -z "$GITHUB_URL" ]; then
        GITHUB_URL="$1"; shift
      else
        die "Unexpected argument: $1"
      fi
      ;;
  esac
done

[ -n "$GITHUB_URL" ] || die "GitHub URL is required"
[ -z "$REF" ] || [ -z "$COMMIT" ] || die "Use either --ref or --commit, not both"

if [[ ! "$GITHUB_URL" =~ ^https://github\.com/[^/]+/[^/]+(/)?$ ]]; then
  die "Invalid GitHub URL. Expected: https://github.com/<owner>/<repo>"
fi

REPO_NAME="$(basename "${GITHUB_URL%.git}")"
[ -n "$REPO_NAME" ] || die "Could not determine repository name"

APP_NAME="$REPO_NAME"
WORK_BASE="$ROOT/.work"
SRC_DIR="$WORK_BASE/${APP_NAME}-src"
OUT_DIR="$ROOT/output/$APP_NAME"
META_DEST_DIR="$ROOT/apps/$APP_NAME"
mkdir -p "$WORK_BASE" "$OUT_DIR" "$META_DEST_DIR"

# Activate venv if present
if [ -f "$ROOT/.venv/bin/activate" ]; then
  # shellcheck disable=SC1091
  source "$ROOT/.venv/bin/activate"
fi

command -v git >/dev/null 2>&1 || die "git is required"
command -v fdroid >/dev/null 2>&1 || die "fdroid is required (run ./install.sh first)"
[ -d "$ROOT/fdroiddata/.git" ] || [ -d "$ROOT/fdroiddata" ] || die "fdroiddata directory not found"

# Resolve fdroiddata python env: prefer repo .venv
FDROID_CMD=(fdroid)

log "Cloning source repository: $GITHUB_URL"
rm -rf "$SRC_DIR"
if [ -n "$REF" ]; then
  git clone --depth 1 --branch "$REF" "$GITHUB_URL" "$SRC_DIR"
elif [ -n "$COMMIT" ]; then
  git clone "$GITHUB_URL" "$SRC_DIR"
  git -C "$SRC_DIR" checkout --detach "$COMMIT"
else
  git clone --depth 1 "$GITHUB_URL" "$SRC_DIR"
fi

REVISION="$(git -C "$SRC_DIR" rev-parse HEAD)"
log "Source revision: $REVISION"

log "Detecting application ID and build system..."
APP_ID="$("$ROOT/scripts/detect-app-id.sh" "$SRC_DIR" || true)"
if [ -z "$APP_ID" ]; then
  APP_ID="UNKNOWN.APPLICATION.ID"
  warn "Could not detect application ID automatically. Using placeholder: $APP_ID"
else
  log "Detected application ID: $APP_ID"
fi

BUILD_INFO="$("$ROOT/scripts/detect-build-system.sh" "$SRC_DIR")"
BUILD_TYPE="$(printf '%s\n' "$BUILD_INFO" | awk -F= '$1=="BUILD_TYPE"{print $2}')"
SUBDIR="$(printf '%s\n' "$BUILD_INFO" | awk -F= '$1=="SUBDIR"{print $2}')"
[ -n "$BUILD_TYPE" ] || die "Failed to detect build type"
[ -n "$SUBDIR" ] || SUBDIR="."
log "Detected build type: $BUILD_TYPE (subdir: $SUBDIR)"

RECIPE_PATH="$META_DEST_DIR/metadata.yml"
if [ "$EXISTING" -eq 1 ]; then
  [ -f "$RECIPE_PATH" ] || die "--existing requested but $RECIPE_PATH not found"
  log "Using existing recipe: $RECIPE_PATH"
else
  if [ -f "$RECIPE_PATH" ]; then
    log "Recipe exists, reusing: $RECIPE_PATH (edit it if needed)"
  else
    log "Generating metadata template: $RECIPE_PATH"
    "$ROOT/scripts/prepare-build.sh" generate \
      --template "$ROOT/templates/app.yml" \
      --output "$RECIPE_PATH" \
      --app-id "$APP_ID" \
      --app-name "$APP_NAME" \
      --repo-url "$GITHUB_URL" \
      --commit "$REVISION" \
      --build-type "$BUILD_TYPE" \
      --subdir "$SUBDIR"
    warn "Generated recipe is a template. Review/edit $RECIPE_PATH before relying on it."
  fi
fi

# Determine metadata filename expected by fdroiddata (Application ID)
META_APP_ID="$APP_ID"
if [ "$META_APP_ID" = "UNKNOWN.APPLICATION.ID" ]; then
  # Try to read from recipe if user filled it in
  if grep -q '^ApplicationID:' "$RECIPE_PATH" 2>/dev/null; then
    META_APP_ID="$(awk '/^ApplicationID:/{print $2; exit}' "$RECIPE_PATH" | tr -d '"' || true)"
  fi
fi
[ -n "$META_APP_ID" ] && [ "$META_APP_ID" != "UNKNOWN.APPLICATION.ID" ] || die "Application ID unknown. Set it in $RECIPE_PATH (and/or ensure detection works) before building."

FDROID_META_DIR="$ROOT/fdroiddata/metadata"
mkdir -p "$FDROID_META_DIR"
cp "$RECIPE_PATH" "$FDROID_META_DIR/${META_APP_ID}.yml"
log "Installed metadata to fdroiddata/metadata/${META_APP_ID}.yml"

# Copy patches for this app if any
if [ -d "$META_DEST_DIR/patches" ] && [ "$(ls -A "$META_DEST_DIR/patches" 2>/dev/null | wc -l)" -gt 0 ]; then
  mkdir -p "$ROOT/fdroiddata/metadata/${META_APP_ID}"
  cp -R "$META_DEST_DIR/patches/." "$ROOT/fdroiddata/metadata/${META_APP_ID}/" || true
  log "Copied patches to fdroiddata/metadata/${META_APP_ID}/"
fi

BUILD_LOG="$OUT_DIR/build.log"
STATUS="FAILURE"

set +e
(
  set -euo pipefail
  cd "$ROOT/fdroiddata"
  log "Running: fdroid readmeta"
  if ! "${FDROID_CMD[@]}" readmeta; then
    warn "fdroid readmeta failed (continuing to attempt build for ${META_APP_ID})"
  fi
  log "Running: fdroid build ${META_APP_ID} --verbose"
  "${FDROID_CMD[@]}" build "$META_APP_ID" --verbose
) 2>&1 | tee "$BUILD_LOG"
RC=${PIPESTATUS[0]}
set -e

# Collect artifacts (only for this app; clear stale APKs in output first)
rm -f "$OUT_DIR"/*.apk 2>/dev/null || true
FOUND_APK=0

copy_apk_if_match() {
  local apk="$1"
  local base
  base="$(basename "$apk")"
  # Accept APKs clearly belonging to this app id or built in app-specific dirs
  case "$base" in
    "${META_APP_ID}_"*.apk|\
    "${META_APP_ID}-"*.apk|\
    "${META_APP_ID}."*.apk)
      cp -f "$apk" "$OUT_DIR/"
      FOUND_APK=1
      ;;
  esac
}

# Shared dirs: copy only APKs for this application id
for d in "$ROOT/fdroiddata/unsigned" "$ROOT/fdroiddata/repo" "$ROOT/fdroiddata/tmp"; do
  [ -d "$d" ] || continue
  while IFS= read -r -d '' apk; do
    copy_apk_if_match "$apk"
  done < <(find "$d" -maxdepth 1 -type f -name '*.apk' -print0 2>/dev/null || true)
done

# App-specific build dir: copy APKs produced for this app
if [ -d "$ROOT/fdroiddata/build/$META_APP_ID" ]; then
  while IFS= read -r -d '' apk; do
    base="$(basename "$apk")"
    if [[ "$base" == "${META_APP_ID}"* ]] || [[ "$apk" == *"/$META_APP_ID/"* ]]; then
      cp -f "$apk" "$OUT_DIR/"
      FOUND_APK=1
    else
      # Fallback: include build outputs from this app's build dir (e.g. app-release.apk)
      cp -f "$apk" "$OUT_DIR/"
      FOUND_APK=1
    fi
  done < <(find "$ROOT/fdroiddata/build/$META_APP_ID" -type f -name '*.apk' -print0 2>/dev/null || true)
fi

cp "$FDROID_META_DIR/${META_APP_ID}.yml" "$OUT_DIR/metadata.yml" 2>/dev/null || cp "$RECIPE_PATH" "$OUT_DIR/metadata.yml" || true

if [ "$RC" -eq 0 ] && [ "$FOUND_APK" -eq 1 ]; then
  STATUS="SUCCESS"
elif [ "$RC" -eq 0 ] && [ "$FOUND_APK" -ne 1 ]; then
  STATUS="SUCCESS (no APK copied)"
else
  STATUS="FAILURE"
fi

APK_PATH="(not found)"
if [ "$FOUND_APK" -eq 1 ]; then
  APK_PATH="$(find "$OUT_DIR" -maxdepth 1 -type f -name '*.apk' | sort | head -n 1 || true)"
  [ -n "$APK_PATH" ] || APK_PATH="(copied, see output dir)"
fi

cat <<EOF

=================================
 F-Droid build finished
=================================

Application: ${APP_NAME}
Application ID: ${META_APP_ID}
Source: ${GITHUB_URL}
Revision: ${REVISION}

Build status: ${STATUS}

APK:
${APK_PATH}

Log:
${BUILD_LOG}

Metadata:
${OUT_DIR}/metadata.yml
EOF

if [ "$RC" -ne 0 ]; then
  exit "$RC"
fi
if [ "$FOUND_APK" -ne 1 ]; then
  warn "Build completed but no APK was found/copied for ${META_APP_ID}. Check build.log and fdroiddata outputs."
fi
