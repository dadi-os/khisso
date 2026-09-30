#!/usr/bin/env bash
# Build Dadi.xcframework (macOS arm64+x86_64, iOS arm64, iOS simulator arm64)
# from cmd/dadi as static c-archives, with a module map so Swift can
# `import Dadi`. Output: build/Dadi.xcframework
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
OUT="$ROOT/build"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

MACOS_MIN=14.0
IOS_MIN=26.0

archive() {
  local name="$1" goos="$2" goarch="$3" sdk="$4" target="$5"
  local dir="$WORK/$name"
  mkdir -p "$dir"
  local sysroot cc
  sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
  cc="$(xcrun --sdk "$sdk" --find clang)"
  echo "→ $name ($goos/$goarch, $target)"
  CGO_ENABLED=1 GOOS="$goos" GOARCH="$goarch" \
    CC="$cc" CGO_CFLAGS="-isysroot $sysroot -target $target" CGO_LDFLAGS="-isysroot $sysroot -target $target" \
    go build -trimpath -buildmode=c-archive -o "$dir/libdadi.a" ./cmd/dadi
}

headers() {
  local dir="$1"
  mkdir -p "$dir/Headers"
  cp "$WORK/macos-arm64/libdadi.h" "$dir/Headers/dadi.h"
  cat > "$dir/Headers/module.modulemap" <<'MAP'
module Dadi {
  header "dadi.h"
  export *
}
MAP
}

archive macos-arm64 darwin arm64 macosx "arm64-apple-macos$MACOS_MIN"
archive macos-amd64 darwin amd64 macosx "x86_64-apple-macos$MACOS_MIN"
archive ios-arm64 ios arm64 iphoneos "arm64-apple-ios$IOS_MIN"
archive ios-sim-arm64 ios arm64 iphonesimulator "arm64-apple-ios$IOS_MIN-simulator"

mkdir -p "$WORK/macos"
lipo -create "$WORK/macos-arm64/libdadi.a" "$WORK/macos-amd64/libdadi.a" -output "$WORK/macos/libdadi.a"

for slice in macos ios-arm64 ios-sim-arm64; do
  headers "$WORK/$slice"
done

rm -rf "$OUT/Dadi.xcframework"
mkdir -p "$OUT"
xcodebuild -create-xcframework \
  -library "$WORK/macos/libdadi.a" -headers "$WORK/macos/Headers" \
  -library "$WORK/ios-arm64/libdadi.a" -headers "$WORK/ios-arm64/Headers" \
  -library "$WORK/ios-sim-arm64/libdadi.a" -headers "$WORK/ios-sim-arm64/Headers" \
  -output "$OUT/Dadi.xcframework"

echo "→ $OUT/Dadi.xcframework"
