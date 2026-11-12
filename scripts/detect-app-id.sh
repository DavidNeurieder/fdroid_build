#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="${1:-}"
[ -n "$SRC_DIR" ] && [ -d "$SRC_DIR" ] || { echo ""; exit 0; }

search_gradle_id() {
  local f="$1"
  [ -f "$f" ] || return 1
  local id=""
  id="$(grep -Eo 'applicationId\s*(=)?\s*"[^"]+"' "$f" 2>/dev/null | head -n1 | sed -E 's/.*"([^"]+)".*/\1/' || true)"
  if [ -z "$id" ]; then
    id="$(grep -Eo "applicationId\s*(=)?\s*'[^']+'" "$f" 2>/dev/null | head -n1 | sed -E "s/.*'([^']+)'.*/\1/" || true)"
  fi
  if [ -z "$id" ]; then
    id="$(grep -Eo 'namespace\s*(=)?\s*"[^"]+"' "$f" 2>/dev/null | head -n1 | sed -E 's/.*"([^"]+)".*/\1/' || true)"
  fi
  if [ -n "$id" ]; then
    echo "$id"
    return 0
  fi
  return 1
}

# 1) Common Android/Flutter module locations first
for f in \
  "$SRC_DIR/app/build.gradle" "$SRC_DIR/app/build.gradle.kts" \
  "$SRC_DIR/android/app/build.gradle" "$SRC_DIR/android/app/build.gradle.kts" \
  "$SRC_DIR/app/android/app/build.gradle" "$SRC_DIR/app/android/app/build.gradle.kts"; do
  search_gradle_id "$f" && exit 0 || true
done

# 2) Any gradle file (prefer ones with applicationId)
while IFS= read -r f; do
  search_gradle_id "$f" && exit 0 || true
done < <(find "$SRC_DIR" -maxdepth 6 \( -name 'build.gradle' -o -name 'build.gradle.kts' \) 2>/dev/null)

# 3) AndroidManifest.xml package (fallback)
while IFS= read -r mf; do
  [ -f "$mf" ] || continue
  id="$(grep -Eo 'package="[^"]+"' "$mf" 2>/dev/null | head -n1 | sed -E 's/package="([^"]+)"/\1/' || true)"
  if [ -n "$id" ]; then
    echo "$id"
    exit 0
  fi
done < <(find "$SRC_DIR" -type f -name AndroidManifest.xml 2>/dev/null | head -n 30)

echo ""
