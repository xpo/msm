#!/usr/bin/env bash
# Construit mSM.app, le signe, puis emballe dans un .dmg signé.
# Usage : ./package-dmg.sh
set -euo pipefail

APP_NAME="mSM"
VOL_NAME="mSM"
DMG_PATH="release/${APP_NAME}.dmg"

cd "$(dirname "$0")"

# 1) build + sign de l'app via package-mac.sh
echo "▸ build de l'app via package-mac.sh"
./package-mac.sh >/dev/null

# 2) détecte l'identité (la même que pour l'app)
SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
  | awk -F\" '/Developer ID Application/ {print $2; exit}')"

# 3) prépare un dossier de mise en scène pour le DMG
STAGE="$(mktemp -d)/dmg-stage"
mkdir -p "$STAGE"
cp -R "${APP_NAME}.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# 4) crée le DMG (compressé UDZO, lecture seule)
mkdir -p release
rm -f "$DMG_PATH"
echo "▸ création du DMG"
hdiutil create -volname "$VOL_NAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  -fs HFS+ \
  -imagekey zlib-level=9 \
  "$DMG_PATH" >/dev/null

rm -rf "$(dirname "$STAGE")"

# 5) signe le DMG si on a une vraie identité
if [ -n "$SIGN_IDENTITY" ]; then
  echo "▸ signature du DMG (${SIGN_IDENTITY})"
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH" >/dev/null 2>&1 || {
    echo "   ⚠ signature DMG échouée (réseau ou identité manquante)"
  }
  echo "▸ vérification :"
  codesign --verify --verbose=2 "$DMG_PATH" 2>&1 | tail -3 || true
  spctl -a -t open --context context:primary-signature -v "$DMG_PATH" 2>&1 | tail -2 || true
fi

echo
echo "✅ $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))"
echo
echo "Pour distribuer hors Gatekeeper sans avertissement, il faut notariser :"
echo "  xcrun notarytool submit '$DMG_PATH' --apple-id <email> --team-id DWLLGDWF4U --password <app-specific> --wait"
echo "  xcrun stapler staple '$DMG_PATH'"
