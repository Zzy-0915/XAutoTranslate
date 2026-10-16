#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
out="${XAD_OUTPUT_DIR:-output}"
mkdir -p "$out/objects"
python3 scripts/vendor-payload.py
common=(-arch arm64 -isysroot "$sdk" -miphoneos-version-min=17.2 -Os
  -fvisibility=hidden -Wall -Wextra -Werror -Wstrict-prototypes
  -ISources)
for file in XAutoTranslate XGTXEngine XNativeTranslation XTranslationRouter XIntegratedPlugin AppleBootstrap; do
  xcrun --sdk iphoneos clang "${common[@]}" -fobjc-arc -fobjc-exceptions -fblocks \
    -c "Sources/$file.m" -o "$out/objects/$file.o"
done
xcrun --sdk iphoneos clang -arch arm64 -isysroot "$sdk" -miphoneos-version-min=17.2 \
  -dynamiclib "$out/objects/XTranslationRouter.o" "$out/objects/XGTXEngine.o" "$out/objects/XNativeTranslation.o" "$out/objects/XAutoTranslate.o" "$out/objects/AppleBootstrap.o" "$out/objects/XIntegratedPlugin.o" \
  -framework Foundation -framework UIKit -framework CoreGraphics -framework NaturalLanguage -lobjc \
  -Wl,-needed_library,output/vendor/BHTwitter.dylib \
  -Wl,-needed_library,output/vendor/libbhFLEX.dylib \
  -Wl,-no_fixup_chains -Wl,-install_name,@rpath/XAutoTranslate-v12.dylib \
  -o "$out/XAutoTranslate-v12.dylib"
codesign --force --sign - --identifier dev.zzy0915.XAutoTranslate.v12 --timestamp=none "$out/XAutoTranslate-v12.dylib"
codesign --verify --strict --verbose=2 "$out/XAutoTranslate-v12.dylib"
xcrun lipo "$out/XAutoTranslate-v12.dylib" -verify_arch arm64
python3 scripts/verify-dylib.py "$out/XAutoTranslate-v12.dylib"
python3 scripts/package-injection.py "$out"
{
  printf 'commit=%s\ntranslation_diagnostics=removed\nintegration=install-time-relative-dependencies\n' "${GITHUB_SHA:-local}"
  xcodebuild -version
  xcrun --sdk iphoneos --show-sdk-version
  xcrun --sdk iphoneos clang --version
  shasum -a 256 "$out/XAutoTranslate-v12.dylib"
} > "$out/build-info.txt"
cp README.md "$out/README.md"

python3 scripts/verify-injection.py "$out/XAutoTranslate-v12-Inject.zip"
python3 scripts/package-deb.py "$out"
