#!/usr/bin/env bash
set -euo pipefail

# Run on macOS after `npm run ios:sync`. No certificate, profile or Apple account
# is needed here: AltServer performs personal-device signing on the user's PC.
if [[ "$(uname -s)" != "Darwin" ]]; then
  printf '%s\n' 'This build needs macOS. On Windows, run the prepared GitHub Actions workflow.' >&2
  exit 1
fi

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_root="$project_root/build"
mkdir -p "$build_root"
staging_root="$(mktemp -d "$build_root/ipa.XXXXXX")"

xcodebuild \
  -project "$project_root/ios/App/App.xcodeproj" \
  -scheme App \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -archivePath "$staging_root/Takt.xcarchive" \
  -derivedDataPath "$staging_root/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' \
  archive

app_path="$staging_root/Takt.xcarchive/Products/Applications/App.app"
if [[ ! -f "$app_path/App" ]]; then
  printf '%s\n' 'Xcode did not produce the expected App.app executable.' >&2
  exit 1
fi

mkdir -p "$staging_root/Payload"
ditto "$app_path" "$staging_root/Payload/App.app"
(
  cd "$staging_root"
  zip -qry Takt.ipa Payload
)
cp "$staging_root/Takt.ipa" "$build_root/Takt.ipa"
unzip -t "$build_root/Takt.ipa" > /dev/null
printf 'IPA created: %s\n' "$build_root/Takt.ipa"
