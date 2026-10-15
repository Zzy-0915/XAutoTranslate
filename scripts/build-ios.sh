#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
out="${XAD_OUTPUT_DIR:-output}"
diag="${XAD_DIAGNOSTICS:-1}"
[[ "$diag" == 0 || "$diag" == 1 ]] || { echo 'XAD_DIAGNOSTICS must be 0 or 1' >&2; exit 1; }
mkdir -p "$out/objects"
common=(-arch arm64 -isysroot "$sdk" -miphoneos-version-min=17.2 -Os
  -fvisibility=hidden -Wall -Wextra -Werror -Wstrict-prototypes
  "-DXAD_DIAGNOSTICS=$diag" -ISources)
for file in XDiagnostics; do
  xcrun --sdk iphoneos clang "${common[@]}" -std=c11 -c "Sources/$file.c" -o "$out/objects/$file.o"
done
for file in XAutoTranslate XGTXEngine XNativeTranslation XTranslationRouter XDwellGate AppleBootstrap; do
  xcrun --sdk iphoneos clang "${common[@]}" -fobjc-arc -fobjc-exceptions -fblocks \
    -c "Sources/$file.m" -o "$out/objects/$file.o"
done
xcrun --sdk iphoneos clang -arch arm64 -isysroot "$sdk" -miphoneos-version-min=17.2 \
  -dynamiclib "$out/objects/XDwellGate.o" "$out/objects/XTranslationRouter.o" "$out/objects/XGTXEngine.o" "$out/objects/XNativeTranslation.o" "$out/objects/XAutoTranslate.o" "$out/objects/XDiagnostics.o" "$out/objects/AppleBootstrap.o" \
  -framework Foundation -framework UIKit -framework CoreGraphics -framework NaturalLanguage -lobjc \
  -Wl,-no_fixup_chains -Wl,-install_name,@rpath/XAutoTranslate-v8.dylib \
  -o "$out/XAutoTranslate-v8.dylib"
codesign --force --sign - --identifier dev.zzy0915.XAutoTranslate.v8 --timestamp=none "$out/XAutoTranslate-v8.dylib"
codesign --verify --strict --verbose=2 "$out/XAutoTranslate-v8.dylib"
xcrun lipo "$out/XAutoTranslate-v8.dylib" -verify_arch arm64
python3 scripts/verify-dylib.py "$out/XAutoTranslate-v8.dylib" "$diag"
{
  printf 'commit=%s\ndiagnostics=%s\n' "${GITHUB_SHA:-local}" "$diag"
  xcodebuild -version
  xcrun --sdk iphoneos --show-sdk-version
  xcrun --sdk iphoneos clang --version
  shasum -a 256 "$out/XAutoTranslate-v8.dylib"
} > "$out/build-info.txt"
cp README.md "$out/README.md"
