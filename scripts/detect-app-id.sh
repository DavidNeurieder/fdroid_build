#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="${1:-}"
[ -n "$SRC_DIR" ] && [ -d "$SRC_DIR" ] || { echo ""; exit 0; }

trim() { sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }

# 1) Gradle (applicationId / namespace) in common module dirs
for f in \
  "$SRC_DIR/app/build.gradle" "$SRC_DIR/app/build.gradle.kts" \
  "$SRC_DIR/android/app/build.gradle" "$SRC_DIR/android/app/build.gradle.kts" \
  "$SRC_DIR"/**/build.gradle "$SRC_DIR"/**/build.gradle.kts; do
  [ -f "$f" ] || continue
  id="$(grep -Eo 'applicationId\s*(=)?\s*"[^"]+"' "$f" 2>/dev/null | head -n1 | sed -E 's/.*"([^"]+)".*/\1/' || true)"
  if [ -z "$id" ]; then
    id="$(grep -Eo "applicationId\s*(=)?\s*'[^']+'" "$f" 2>/dev/null | head -n1 | sed -E "s/.*'([^']+)'.*/\1/" || true)"
  fi
  if [ -z "$id" ]; then
    id="$(grep -Eo 'namespace\s*(=)?\s*"[^"]+"' "$f" 2>/dev/null | head -n1 | sed -E 's/.*"([^"]+)".*/\1/' || true)"
  fi
  if [ -n "$id" ]; then
    echo "$id"
    exit 0
  fi
done

# 2) AndroidManifest.xml package
while IFS= read -r mf; do
  [ -f "$mf" ] || continue
  id="$(grep -Eo 'package="[^"]+"' "$mf" 2>/dev/null | head -n1 | sed -E 's/package="([^"]+)"/\1/' || true)"
  if [ -n "$id" ]; then
    echo "$id"
    exit 0
  fi
done < <(find "$SRC_DIR" -type f -name AndroidManifest.xml 2>/dev/null | head -n 20)

echo ""
