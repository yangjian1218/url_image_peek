#!/bin/zsh
set -euo pipefail

task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_output_dir="${1:-$task_root/artifacts}"
task_derived_data="$task_root/.build/release"
task_app="$task_derived_data/Build/Products/Release/ImagePeek.app"
task_signing_identity="${IMAGEPEEK_CODESIGN_IDENTITY:-NotchBar Development}"

mkdir -p "$task_output_dir"

xcodebuild \
  -project "$task_root/ImagePeek.xcodeproj" \
  -scheme ImagePeek \
  -configuration Release \
  -derivedDataPath "$task_derived_data" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$task_signing_identity" \
  build

[[ -d "$task_app" ]] || { print -u2 "Missing Release app: $task_app"; exit 1; }
codesign --verify --deep --strict --verbose=2 "$task_app"

task_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$task_app/Contents/Info.plist")"
task_archive="$task_output_dir/ImagePeek-$task_version-development-signed.zip"
task_checksum="$task_archive.sha256"

if [[ -e "$task_archive" || -e "$task_checksum" ]]; then
  print -u2 "Refusing to overwrite existing release artifact for version $task_version"
  exit 1
fi

# Avoid AppleDouble metadata files in the distributable archive.
ditto -c -k --keepParent --norsrc "$task_app" "$task_archive"
unzip -tq "$task_archive" >/dev/null
zipinfo -1 "$task_archive" | grep -q '^ImagePeek.app/' || {
  print -u2 "Archive does not contain ImagePeek.app"
  exit 1
}
shasum -a 256 "$task_archive" > "$task_checksum"
print "Created development-signed archive: $task_archive"
print "Created SHA-256 checksum: $task_checksum"
