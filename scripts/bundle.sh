#!/usr/bin/env bash
# Builds Tatami in release mode and assembles dist/Tatami.app.
#
# Signs with the first "Apple Development" identity in the keychain so the
# Accessibility grant survives rebuilds; falls back to ad-hoc signing (CI).
# Set TATAMI_SIGN_IDENTITY to override, or to "-" to force ad-hoc.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGURATION="${CONFIGURATION:-release}"
APP="dist/Tatami.app"

swift build -c "$CONFIGURATION" --product Tatami
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Tatami" "$APP/Contents/MacOS/Tatami"
cp Resources/Info.plist "$APP/Contents/Info.plist"

identity="${TATAMI_SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
    identity="$(security find-identity -v -p codesigning 2>/dev/null \
        | awk '/"Apple Development/ { print $2; exit }')"
fi
if [[ -z "$identity" ]]; then
    identity="-"
    echo "note: no Apple Development identity found; signing ad-hoc." \
        "Accessibility access must be re-granted after each rebuild." >&2
fi

codesign --force --options runtime --timestamp=none --sign "$identity" "$APP"
codesign --verify --strict "$APP"
echo "Built $APP (signed with: $([[ "$identity" == "-" ]] && echo ad-hoc || echo "$identity"))"
