#!/bin/zsh
set -euo pipefail

if (( $# != 3 )); then
  print -u2 "Usage: $0 <Developer ID Application identity> <notary keychain profile> <output directory>"
  exit 64
fi

task_identity="$1"
task_notary_profile="$2"
task_output_dir="$3"
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_derived_data="$task_root/.build/release"
task_app="$task_derived_data/Build/Products/Release/ImagePeek.app"

[[ -d "$task_app" ]] || { print -u2 "Run package-release.sh first."; exit 1; }
task_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$task_app/Contents/Info.plist")"
task_archive="$task_output_dir/ImagePeek-$task_version.zip"
task_submission_archive="$task_output_dir/ImagePeek-$task_version-notary-submit.zip"
[[ ! -e "$task_archive" ]] || { print -u2 "Refusing to overwrite existing archive: $task_archive"; exit 1; }
[[ ! -e "$task_submission_archive" ]] || { print -u2 "Refusing to overwrite existing submission archive: $task_submission_archive"; exit 1; }

codesign --force --deep --options runtime --timestamp \
  --entitlements "$task_root/ImagePeek/ImagePeek.entitlements" \
  --sign "$task_identity" \
  "$task_app"
codesign --verify --deep --strict --verbose=2 "$task_app"

mkdir -p "$task_output_dir"
ditto -c -k --keepParent "$task_app" "$task_submission_archive"
xcrun notarytool submit "$task_submission_archive" --keychain-profile "$task_notary_profile" --wait
xcrun stapler staple "$task_app"
spctl --assess --type execute --verbose=4 "$task_app"
ditto -c -k --keepParent "$task_app" "$task_archive"

print "Created notarized archive: $task_archive"
