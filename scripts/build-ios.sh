#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
out="${XAD_OUTPUT_DIR:-output}"
mkdir -p "$out/objects"
common=(-arch arm64 -isysroot "$sdk" -miphoneos-version-min=17.2 -Os
  -fvisibility=hidden -Wall -Wextra -Werror -Wstrict-prototypes
  -ISources)
for file in XAutoTranslate XGTXEngine XNativeTranslation XTranslationRouter AppleBootstrap; do
  xcrun --sdk iphoneos clang "${common[@]}" -fobjc-arc -fobjc-exceptions -fblocks \
    -c "Sources/$file.m" -o "$out/objects/$file.o"
done
xcrun --sdk iphoneos clang -arch arm64 -isysroot "$sdk" -miphoneos-version-min=17.2 \
  -dynamiclib "$out/objects/XTranslationRouter.o" "$out/objects/XGTXEngine.o" "$out/objects/XNativeTranslation.o" "$out/objects/XAutoTranslate.o" "$out/objects/AppleBootstrap.o" \
  -framework Foundation -framework UIKit -framework CoreGraphics -framework NaturalLanguage -lobjc \
  -Wl,-no_fixup_chains -Wl,-install_name,@rpath/XAutoTranslate-v10.dylib \
  -o "$out/XAutoTranslate-v10.dylib"
codesign --force --sign - --identifier dev.zzy0915.XAutoTranslate.v10 --timestamp=none "$out/XAutoTranslate-v10.dylib"
codesign --verify --strict --verbose=2 "$out/XAutoTranslate-v10.dylib"
xcrun lipo "$out/XAutoTranslate-v10.dylib" -verify_arch arm64
python3 scripts/verify-dylib.py "$out/XAutoTranslate-v10.dylib"
{
  printf 'commit=%s\ndiagnostics=removed\n' "${GITHUB_SHA:-local}"
  xcodebuild -version
  xcrun --sdk iphoneos --show-sdk-version
  xcrun --sdk iphoneos clang --version
  shasum -a 256 "$out/XAutoTranslate-v10.dylib"
} > "$out/build-info.txt"
cp README.md "$out/README.md"
