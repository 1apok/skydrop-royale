#!/usr/bin/env bash
# Builds SKYDROP.ipa on macOS (Xcode required).
# Unsigned by default; signs automatically when IOS_P12, IOS_P12_PASSWORD and IOS_PROFILE are set
# (paths to your .p12 certificate and .mobileprovision file).
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT_VERSION="4.5.1"
GODOT="${GODOT:-}"
WORK="build/tools"
mkdir -p "$WORK" build/ios out

if [[ -z "$GODOT" ]]; then
  if [[ ! -d "$WORK/Godot.app" ]]; then
    echo "Downloading Godot $GODOT_VERSION..."
    curl -fsSL -o "$WORK/godot.zip" "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_macos.universal.zip"
    unzip -q -o "$WORK/godot.zip" -d "$WORK"
  fi
  GODOT="$WORK/Godot.app/Contents/MacOS/Godot"
fi

TPL_DIR="$HOME/Library/Application Support/Godot/export_templates/${GODOT_VERSION}.stable"
if [[ ! -f "$TPL_DIR/ios.zip" ]]; then
  echo "Downloading export templates..."
  curl -fsSL -o "$WORK/templates.tpz" "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_export_templates.tpz"
  mkdir -p "$TPL_DIR"
  unzip -q -o -j "$WORK/templates.tpz" "templates/ios.zip" "templates/version.txt" -d "$TPL_DIR"
fi

echo "Exporting Xcode project..."
"$GODOT" --headless --import >/dev/null 2>&1 || true
"$GODOT" --headless --export-release "iOS" build/ios/SKYDROP.xcodeproj

echo "Building app..."
xcodebuild -project build/ios/SKYDROP.xcodeproj -scheme SKYDROP -configuration Release \
  -sdk iphoneos -destination "generic/platform=iOS" -derivedDataPath build/dd \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" \
  build | tail -n 5

APP="$(find build/dd/Build/Products/Release-iphoneos -maxdepth 1 -name '*.app' | head -n 1)"
rm -rf out/Payload && mkdir -p out/Payload
cp -R "$APP" out/Payload/
APP_IN="out/Payload/$(basename "$APP")"

if [[ -n "${IOS_P12:-}" && -n "${IOS_PROFILE:-}" ]]; then
  echo "Signing..."
  KC="skydrop-build.keychain"
  security delete-keychain "$KC" >/dev/null 2>&1 || true
  security create-keychain -p skydrop "$KC"
  security set-keychain-settings "$KC"
  security unlock-keychain -p skydrop "$KC"
  security import "$IOS_P12" -k "$KC" -P "${IOS_P12_PASSWORD:-}" -T /usr/bin/codesign
  security list-keychains -d user -s "$KC" $(security list-keychains -d user | tr -d '"')
  security set-key-partition-list -S apple-tool:,apple: -s -k skydrop "$KC" >/dev/null
  security cms -D -i "$IOS_PROFILE" > build/profile.plist
  /usr/libexec/PlistBuddy -x -c "Print :Entitlements" build/profile.plist > build/entitlements.plist
  APP_ID="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' build/profile.plist)"
  BUNDLE="${APP_ID#*.}"
  if [[ "$BUNDLE" != *"*"* ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE" "$APP_IN/Info.plist"
  fi
  cp "$IOS_PROFILE" "$APP_IN/embedded.mobileprovision"
  IDENTITY="$(security find-identity -v -p codesigning "$KC" | head -n 1 | awk '{print $2}')"
  find "$APP_IN" \( -name '*.framework' -o -name '*.dylib' \) -print0 | while IFS= read -r -d '' lib; do
    codesign -f -s "$IDENTITY" "$lib"
  done
  codesign -f -s "$IDENTITY" --entitlements build/entitlements.plist "$APP_IN"
  security delete-keychain "$KC" || true
  NAME="SKYDROP.ipa"
else
  NAME="SKYDROP-unsigned.ipa"
fi

(cd out && rm -f "$NAME" && zip -qry "$NAME" Payload)
echo "Done: out/$NAME"
