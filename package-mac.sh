#!/usr/bin/env bash
# Construit mSM.app à partir des sources Lua + LÖVE installé.
# Usage : ./package-mac.sh
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="mSM"
BUNDLE_ID="eu.askem.msm"
LOVE_APP="/Applications/love.app"

if [ ! -d "$LOVE_APP" ]; then
  echo "❌ LÖVE introuvable à $LOVE_APP"
  echo "   Installez via : brew install --cask love"
  exit 1
fi

echo "▸ 1/6 construction du .love..."
rm -f "$APP_NAME.love"
# On inclut main.lua, parser.lua, exporter.lua, conf.lua ET msm.html
# (msm.html est nécessaire pour la fonction d'export depuis l'app).
zip -q -X "$APP_NAME.love" main.lua parser.lua exporter.lua inline.lua conf.lua msm.html

echo "▸ 2/6 copie du bundle love.app..."
rm -rf "$APP_NAME.app"
cp -R "$LOVE_APP" "$APP_NAME.app"

echo "▸ 3/6 binaire vierge + .love en Resources..."
# La fusion classique (cat love + .love) corrompt le binaire dès qu'on re-signe
# en hardened runtime : codesign réécrit LINKEDIT et écrase le .love appended.
# Solution : binaire LÖVE inchangé + .love placé en Resources/, où LÖVE le
# trouve automatiquement au démarrage via findGameInResources.
cp "$LOVE_APP/Contents/MacOS/love" "$APP_NAME.app/Contents/MacOS/$APP_NAME"
cp "$APP_NAME.love" "$APP_NAME.app/Contents/Resources/$APP_NAME.love"

echo "▸ 3ter/6 helper Mermaid (WKWebView)..."
# Télécharge Mermaid.js si absent (~3 Mo, mis en cache dans tools/)
mkdir -p tools
if [ ! -f tools/mermaid.min.js ]; then
  echo "   → fetch mermaid@11..."
  curl -fLs -o tools/mermaid.min.js https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js
fi
# Compile mmd-render (Swift → Mach-O ~100 Ko) si swiftc est dispo
if command -v xcrun >/dev/null 2>&1; then
  echo "   → compilation mmd-render..."
  xcrun -sdk macosx swiftc -O tools/mmd-render.swift \
    -o "$APP_NAME.app/Contents/MacOS/mmd-render" 2>&1 | tail -5
  cp tools/mermaid.min.js "$APP_NAME.app/Contents/Resources/mermaid.min.js"
else
  echo "   ⚠ xcrun absent, helper non bundlé (fallback npm mmdc)"
fi
chmod +x "$APP_NAME.app/Contents/MacOS/$APP_NAME"
rm "$APP_NAME.app/Contents/MacOS/love"

echo "▸ 3bis/6 icône..."
# Génère icon.png si manquant (via LÖVE + icon-gen/).
if [ ! -f icon.png ]; then
  echo "   → génération via icon-gen/ (brève fenêtre LÖVE)"
  love icon-gen/ >/dev/null 2>&1 &
  for _ in 1 2 3 4 5 6 7 8; do [ -f icon.png ] && break; sleep 1; done
  pkill -f "love icon-gen" 2>/dev/null || true
fi
# Convertit icon.png → icon.icns (sips + iconutil)
if [ -f icon.png ]; then
  TMP_ICONSET="$(mktemp -d)/mSM.iconset"
  mkdir -p "$TMP_ICONSET"
  sips -z 16 16     icon.png --out "$TMP_ICONSET/icon_16x16.png"       >/dev/null
  sips -z 32 32     icon.png --out "$TMP_ICONSET/icon_16x16@2x.png"    >/dev/null
  sips -z 32 32     icon.png --out "$TMP_ICONSET/icon_32x32.png"       >/dev/null
  sips -z 64 64     icon.png --out "$TMP_ICONSET/icon_32x32@2x.png"    >/dev/null
  sips -z 128 128   icon.png --out "$TMP_ICONSET/icon_128x128.png"     >/dev/null
  sips -z 256 256   icon.png --out "$TMP_ICONSET/icon_128x128@2x.png"  >/dev/null
  sips -z 256 256   icon.png --out "$TMP_ICONSET/icon_256x256.png"     >/dev/null
  sips -z 512 512   icon.png --out "$TMP_ICONSET/icon_256x256@2x.png"  >/dev/null
  sips -z 512 512   icon.png --out "$TMP_ICONSET/icon_512x512.png"     >/dev/null
  cp icon.png "$TMP_ICONSET/icon_512x512@2x.png"
  iconutil -c icns "$TMP_ICONSET" -o "$APP_NAME.app/Contents/Resources/$APP_NAME.icns"
  rm -rf "$(dirname "$TMP_ICONSET")"
  # Retire TOUS les restes d'icônes LÖVE :
  #  - Assets.car contient l'asset-catalog compilé avec "OS X AppIcon" (l'icône rouge LÖVE)
  #  - sur macOS moderne, CFBundleIconName prend la priorité et cherche dans Assets.car
  rm -f "$APP_NAME.app/Contents/Resources/Assets.car" \
        "$APP_NAME.app/Contents/Resources/GameIcon.icns" \
        "$APP_NAME.app/Contents/Resources/OS X AppIcon.icns" \
        "$APP_NAME.app/Contents/Resources/Love.icns"
fi

echo "▸ 4/6 patch Info.plist..."
PLIST="$APP_NAME.app/Contents/Info.plist"
PB="/usr/libexec/PlistBuddy"

"$PB" -c "Set :CFBundleExecutable $APP_NAME"        "$PLIST"
"$PB" -c "Set :CFBundleName $APP_NAME"              "$PLIST"
"$PB" -c "Set :CFBundleIdentifier $BUNDLE_ID"       "$PLIST"
"$PB" -c "Set :CFBundleShortVersionString 1.0"      "$PLIST" 2>/dev/null \
  || "$PB" -c "Add :CFBundleShortVersionString string 1.0" "$PLIST"
"$PB" -c "Set :CFBundleIconFile $APP_NAME"          "$PLIST" 2>/dev/null \
  || "$PB" -c "Add :CFBundleIconFile string $APP_NAME" "$PLIST"
# Supprime CFBundleIconName : référence à un asset catalog qu'on vient de retirer.
# Sans lui, macOS retombe sur CFBundleIconFile → notre mSM.icns.
"$PB" -c "Delete :CFBundleIconName"                 "$PLIST" 2>/dev/null || true

# Retire les associations existantes (love) et ajoute .md / .markdown
"$PB" -c "Delete :CFBundleDocumentTypes"            "$PLIST" 2>/dev/null || true
"$PB" -c "Delete :UTExportedTypeDeclarations"       "$PLIST" 2>/dev/null || true
"$PB" -c "Add :CFBundleDocumentTypes array"                                   "$PLIST"
"$PB" -c "Add :CFBundleDocumentTypes:0 dict"                                  "$PLIST"
"$PB" -c "Add :CFBundleDocumentTypes:0:CFBundleTypeName string Markdown"      "$PLIST"
"$PB" -c "Add :CFBundleDocumentTypes:0:CFBundleTypeRole string Viewer"        "$PLIST"
"$PB" -c "Add :CFBundleDocumentTypes:0:LSHandlerRank string Alternate"        "$PLIST"
"$PB" -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions array"          "$PLIST"
"$PB" -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions:0 string md"          "$PLIST"
"$PB" -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions:1 string markdown"    "$PLIST"

echo "▸ 5/6 signature..."
# Détecte un certificat Developer ID Application (Louis Montagne). Sinon ad-hoc.
SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
  | awk -F\" '/Developer ID Application/ {print $2; exit}')"
if [ -n "$SIGN_IDENTITY" ]; then
  echo "   → identité : $SIGN_IDENTITY"
  ENTITLEMENTS="$(pwd)/entitlements.plist"
  # Le binaire fusionné (love + .love) hérite d'une signature linker ad-hoc
  # qui bloque la re-signature stricte. On la supprime d'abord.
  codesign --remove-signature "$APP_NAME.app/Contents/MacOS/$APP_NAME" >/dev/null 2>&1 || true
  # Signe frameworks/dylibs/bundles intégrés (pas d'entitlements pour eux)
  find "$APP_NAME.app/Contents/Frameworks" \
    \( -name "*.dylib" -o -name "*.framework" -o -name "*.bundle" \) 2>/dev/null \
    | while read -r item; do
        codesign --force --options runtime --timestamp \
          --sign "$SIGN_IDENTITY" "$item" >/dev/null 2>&1
      done
  # Signe le binaire principal AVEC les entitlements JIT (LuaJIT en a besoin)
  codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_IDENTITY" "$APP_NAME.app/Contents/MacOS/$APP_NAME" >/dev/null 2>&1
  # Signe mmd-render (helper Mermaid) si présent
  if [ -f "$APP_NAME.app/Contents/MacOS/mmd-render" ]; then
    codesign --force --options runtime --timestamp \
      --sign "$SIGN_IDENTITY" "$APP_NAME.app/Contents/MacOS/mmd-render" >/dev/null 2>&1
  fi
  # Signe le bundle (les entitlements ne sont attachés qu'au binaire principal)
  codesign --force --options runtime --timestamp --deep \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_IDENTITY" "$APP_NAME.app" >/dev/null 2>&1 || {
      echo "   ⚠ signature développeur échouée, fallback ad-hoc"
      codesign --force --deep --sign - "$APP_NAME.app" >/dev/null 2>&1 || true
    }
  codesign --verify --deep --strict --verbose=2 "$APP_NAME.app" 2>&1 | tail -3 || true
else
  echo "   → ad-hoc (aucun Developer ID trouvé)"
  codesign --force --deep --sign - "$APP_NAME.app" >/dev/null 2>&1 || true
fi

echo "▸ 6/6 nettoyage des attributs quarantine..."
find "$APP_NAME.app" -exec xattr -d com.apple.quarantine {} \; 2>/dev/null || true

echo ""
echo "✅ $APP_NAME.app construit."
echo ""
echo "Pour l'utiliser :"
echo "  1. mv $APP_NAME.app /Applications/"
echo "  2. ouvrez-la une fois (double-clic) pour que macOS l'enregistre"
echo "  3. glissez-la sur le Dock pour l'épingler"
echo "  4. glissez un .md sur l'icône du Dock → le deck s'ouvre"
echo "  5. dans l'app, touche E = exporter en HTML autonome (dialogue de sauvegarde)"
