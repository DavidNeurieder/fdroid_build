#!/usr/bin/env bash
set -euo pipefail

die() { printf '[prepare-build] ERROR: %s\n' "$*" >&2; exit 1; }

cmd="${1:-}"
shift || true

if [ "$cmd" != "generate" ]; then
  die "Unknown command: $cmd (expected: generate)"
fi

TEMPLATE=""
OUTPUT=""
APP_ID=""
APP_NAME=""
REPO_URL=""
COMMIT=""
BUILD_TYPE=""
SUBDIR="."

while [ $# -gt 0 ]; do
  case "$1" in
    --template) TEMPLATE="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --app-id) APP_ID="$2"; shift 2 ;;
    --app-name) APP_NAME="$2"; shift 2 ;;
    --repo-url) REPO_URL="$2"; shift 2 ;;
    --commit) COMMIT="$2"; shift 2 ;;
    --build-type) BUILD_TYPE="$2"; shift 2 ;;
    --subdir) SUBDIR="$2"; shift 2 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[ -n "$TEMPLATE" ] && [ -f "$TEMPLATE" ] || die "Template not found"
[ -n "$OUTPUT" ] || die "Output path required"
[ -n "$APP_ID" ] || APP_ID="UNKNOWN.APPLICATION.ID"
[ -n "$APP_NAME" ] || APP_NAME="app"
[ -n "$REPO_URL" ] || die "Repo URL required"
[ -n "$COMMIT" ] || die "Commit required"
[ -n "$BUILD_TYPE" ] || BUILD_TYPE="unknown"

build_block=""
case "$BUILD_TYPE" in
  gradle)
    build_block=$(cat <<'YAML'
    gradle:
      - yes
YAML
)
    ;;
  flutter)
    build_block=$(cat <<'YAML'
    # Flutter build (review and adjust versions/channels as needed)
    sudo:
      - apt-get update
      - apt-get install -y curl unzip xz-utils git
    output: build/app/outputs/flutter-apk/app-release.apk
    srclibs:
      - flutter@stable
    build:
      - $$flutter$$/bin/flutter config --no-analytics
      - $$flutter$$/bin/flutter pub get
      - $$flutter$$/bin/flutter build apk --release
YAML
)
    ;;
  flutter-rust)
    build_block=$(cat <<'YAML'
    # Flutter + Rust build (template). Review carefully and adjust toolchain/NDK/commands.
    # Ensure any custom scripts run inside the F-Droid build environment, not on the host.
    sudo:
      - apt-get update
      - apt-get install -y curl unzip xz-utils git build-essential pkg-config
    output: build/app/outputs/flutter-apk/app-release.apk
    srclibs:
      - flutter@stable
      - rustup@master
    build:
      - $$rustup$$/rustup-init.sh -y
      - source $HOME/.cargo/env
      - rustup default stable
      - # Example (AgainstYesterday): ./app/tool/build_rust_engine_android.sh
      - $$flutter$$/bin/flutter config --no-analytics
      - $$flutter$$/bin/flutter pub get
      - $$flutter$$/bin/flutter build apk --release
YAML
)
    ;;
  *)
    build_block=$(cat <<'YAML'
    # Unknown build system: add appropriate build instructions here.
    # Example for Gradle:
    # gradle:
    #   - yes
YAML
)
    ;;
esac

mkdir -p "$(dirname "$OUTPUT")"
tmp="$(mktemp)"
cp "$TEMPLATE" "$tmp"

# Escape for sed replacement
esc() { printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'; }

sed -i "s/__AUTHOR__/$(esc "$APP_NAME")/g" "$tmp"
sed -i "s/__REPO_URL__/$(esc "$REPO_URL")/g" "$tmp"
sed -i "s/__COMMIT__/$(esc "$COMMIT")/g" "$tmp"
sed -i "s/__SUBDIR__/$(esc "$SUBDIR")/g" "$tmp"

# Inject build block
awk -v block="$build_block" '
  { if ($0=="__BUILD_BLOCK__") { print block; next } print $0 }
' "$tmp" > "$OUTPUT"
rm -f "$tmp"

# Prepend ApplicationID comment/help if unknown
if [ "$APP_ID" = "UNKNOWN.APPLICATION.ID" ]; then
  printf '%s\n' "# TODO: Set the correct ApplicationID and verify all fields." > "$OUTPUT.new"
  cat "$OUTPUT" >> "$OUTPUT.new"
  mv "$OUTPUT.new" "$OUTPUT"
fi
