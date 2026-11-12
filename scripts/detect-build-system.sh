#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="${1:-}"
[ -n "$SRC_DIR" ] && [ -d "$SRC_DIR" ] || { echo "BUILD_TYPE=unknown"; echo "SUBDIR=."; exit 0; }

has_flutter=0
has_rust=0
has_gradle=0

[ -f "$SRC_DIR/pubspec.yaml" ] && has_flutter=1
if find "$SRC_DIR" -maxdepth 4 -name Cargo.toml 2>/dev/null | grep -q .; then
  has_rust=1
fi
if find "$SRC_DIR" -maxdepth 4 \( -name 'build.gradle' -o -name 'build.gradle.kts' \) 2>/dev/null | grep -q .; then
  has_gradle=1
fi

subdir="."
if [ "$has_flutter" -eq 1 ]; then
  subdir="."
  # Common Flutter android subdir is handled by F-Droid/flutter build context, keep root
elif [ -f "$SRC_DIR/app/build.gradle" ] || [ -f "$SRC_DIR/app/build.gradle.kts" ]; then
  subdir="."
elif [ -f "$SRC_DIR/android/build.gradle" ] || [ -f "$SRC_DIR/android/build.gradle.kts" ]; then
  subdir="android"
fi

if [ "$has_flutter" -eq 1 ] && [ "$has_rust" -eq 1 ]; then
  echo "BUILD_TYPE=flutter-rust"
  echo "SUBDIR=$subdir"
  exit 0
fi

if [ "$has_flutter" -eq 1 ]; then
  echo "BUILD_TYPE=flutter"
  echo "SUBDIR=$subdir"
  exit 0
fi

if [ "$has_gradle" -eq 1 ]; then
  echo "BUILD_TYPE=gradle"
  echo "SUBDIR=$subdir"
  exit 0
fi

echo "BUILD_TYPE=unknown"
echo "SUBDIR=."
