#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"

# Interactive performance must be measured with Swift optimization enabled.
# Tests still run in debug; opt in to a debug app with RESONANT_BUILD_CONFIGURATION=debug.
CONFIGURATION="${RESONANT_BUILD_CONFIGURATION:-release}"
case "$CONFIGURATION" in
    debug|release) ;;
    *) printf 'Invalid build configuration: %s\n' "$CONFIGURATION" >&2; exit 1 ;;
esac
printf 'Building app configuration: %s\n' "$CONFIGURATION"
swift build -c "$CONFIGURATION" --product Resonant
BIN="$(swift build -c "$CONFIGURATION" --show-bin-path)/Resonant"
APP="$ROOT/.build/Resonant.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Resonant"
cp "$ROOT/ResonantApp/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/ResonantApp/Resonant.entitlements" "$APP/Contents/Resources/Resonant.entitlements"

# Ad-hoc signing is sufficient for a local feasibility run. A Developer ID
# signature/notarization decision belongs to a later production change.
codesign --force --deep --sign - --entitlements "$APP/Contents/Resources/Resonant.entitlements" "$APP"
printf '\nBuilt %s\n' "$APP"
printf 'Launch with: open "%s"\n' "$APP"
