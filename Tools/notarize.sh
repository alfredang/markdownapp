#!/usr/bin/env bash
#
# Build → sign (Developer ID + hardened runtime) → DMG → notarize → staple.
# Produces dist/Markdown Vault.dmg that opens with NO Gatekeeper warnings on any Mac.
#
# Prerequisites (one-time):
#   1. A "Developer ID Application" certificate in your login keychain.
#      Create it: Xcode ▸ Settings ▸ Accounts ▸ (your team) ▸ Manage Certificates… ▸ + ▸
#      "Developer ID Application".  (The ASC API cannot create it — Account Holder only.)
#   2. .env with ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY_PATH (the App Store Connect API
#      key — reused here as the notarytool credential).
#
# Usage:  bash Tools/notarize.sh
set -euo pipefail
cd "$(dirname "$0")/.."

set -a; [ -f .env ] && source .env; set +a

APP_NAME="Markdown Vault"
SCHEME="MarkdownVault"
DERIVED="/tmp/mvrelease"
APP="$DERIVED/Build/Products/Release/$APP_NAME.app"
DMG="dist/$APP_NAME.dmg"
KEY_PATH="${ASC_PRIVATE_KEY_PATH/#\~/$HOME}"

# 1. Resolve the Developer ID Application identity.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Developer ID Application" | head -1 | sed -E 's/.*"([^"]*)".*/\1/')
if [ -z "${IDENTITY:-}" ]; then
  echo "❌ No 'Developer ID Application' certificate in the keychain."
  echo "   Create it once: Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates… ▸ + ▸ Developer ID Application"
  exit 1
fi
echo "▸ Signing identity: $IDENTITY"
for v in ASC_KEY_ID ASC_ISSUER_ID; do
  [ -n "${!v:-}" ] || { echo "❌ $v missing in .env"; exit 1; }
done
[ -f "$KEY_PATH" ] || { echo "❌ ASC key not found: $KEY_PATH"; exit 1; }

# 2. Clean Release build.
echo "▸ Building Release…"
command -v xcodegen >/dev/null && xcodegen generate >/dev/null
xcodebuild -project "$SCHEME.xcodeproj" -scheme "$SCHEME" -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$DERIVED" clean build >/dev/null
echo "  built: $APP"

# 3. Sign with hardened runtime (required for notarization). SwiftTerm is statically linked,
#    so a single deep sign covers the bundle.
echo "▸ Signing with hardened runtime…"
codesign --force --deep --options runtime --timestamp \
  --entitlements Sources/MarkdownVault.entitlements \
  --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

# 4. Package a DMG (app + drag-to-Applications) and sign it too.
echo "▸ Building DMG…"
STAGE=$(mktemp -d); cp -R "$APP" "$STAGE/"; ln -s /Applications "$STAGE/Applications"
mkdir -p dist; rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

# 5. Notarize (using the ASC API key) and wait for the verdict.
echo "▸ Notarizing (this can take a few minutes)…"
xcrun notarytool submit "$DMG" \
  --key "$KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait

# 6. Staple the ticket so it validates offline.
echo "▸ Stapling…"
xcrun stapler staple "$APP"
xcrun stapler staple "$DMG"

echo "▸ Gatekeeper check:"
spctl -a -vvv --type install "$DMG" || true
echo "✅ Done → $DMG (signed · notarized · stapled). Ship it from your website."
