#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_root="$project_root/build/native"
mkdir -p "$build_root"
project="$project_root/native/Takt.xcodeproj"

xcodebuild -project "$project" -scheme Takt -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -archivePath "$build_root/Takt.xcarchive" -derivedDataPath "$build_root/device-derived" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' archive

device_app="$build_root/Takt.xcarchive/Products/Applications/Takt.app"
test -f "$device_app/Takt"
staging="$(mktemp -d "$build_root/package.XXXXXX")"
mkdir -p "$staging/Payload"
ditto "$device_app" "$staging/Payload/Takt.app"
(cd "$staging" && zip -qry "$project_root/build/Takt-Native.ipa" Payload)

xcodebuild -project "$project" -scheme Takt -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$build_root/simulator-derived" \
  ONLY_ACTIVE_ARCH=NO 'ARCHS=arm64 x86_64' CODE_SIGNING_ALLOWED=NO build

sim_app="$build_root/simulator-derived/Build/Products/Debug-iphonesimulator/Takt.app"
test -f "$sim_app/Takt"
ditto -c -k --sequesterRsrc --keepParent "$sim_app" "$project_root/build/Takt-Simulator.zip"
printf 'Native device and simulator builds are ready.\n'
