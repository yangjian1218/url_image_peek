#!/bin/zsh
set -euo pipefail

task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_output_dir="${1:-$task_root/artifacts}"
task_derived_data="$task_root/.build/release"
task_app="$task_derived_data/Build/Products/Release/ImagePeek.app"
task_archive="$task_output_dir/ImagePeek-1.0.0-unsigned.zip"

if [[ -e "$task_archive" ]]; then
  print -u2 "Refusing to overwrite existing archive: $task_archive"
  exit 1
fi

mkdir -p "$task_output_dir"

xcodebuild \
  -project "$task_root/ImagePeek.xcodeproj" \
  -scheme ImagePeek \
  -configuration Release \
  -derivedDataPath "$task_derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  build

[[ -d "$task_app" ]] || { print -u2 "Missing Release app: $task_app"; exit 1; }

# Avoid AppleDouble metadata files in the distributable archive.
ditto -c -k --keepParent --norsrc "$task_app" "$task_archive"
print "Created unsigned archive: $task_archive"
