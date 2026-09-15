#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"

# Keep the Swift compiler, SDK, and bundled macro plugins on the same Xcode.
# Honor an explicit Xcode selection; otherwise prefer the standard installation.
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
unset TOOLCHAINS SDKROOT
if ! xcodebuild -version; then
    printf 'Select a full Xcode installation via DEVELOPER_DIR or xcode-select.\n' >&2
    exit 1
fi
SWIFT="$(xcrun --find swift)"
printf 'Swift compiler: %s\n' "$SWIFT"
"$SWIFT" --version

# Interactive performance must be measured with Swift optimization enabled.
# Tests still run in debug; opt in to a debug app with SPACE_VISUALIZER_BUILD_CONFIGURATION=debug.
CONFIGURATION="${SPACE_VISUALIZER_BUILD_CONFIGURATION:-release}"
case "$CONFIGURATION" in
    debug|release) ;;
    *) printf 'Invalid build configuration: %s\n' "$CONFIGURATION" >&2; exit 1 ;;
esac
printf 'Building app configuration: %s\n' "$CONFIGURATION"
"$SWIFT" build -c "$CONFIGURATION" --product SpaceVisualizer
BIN="$("$SWIFT" build -c "$CONFIGURATION" --show-bin-path)/SpaceVisualizer"
APP="$ROOT/.build/Space Visualizer.app"
# Remove only the obsolete generated artifact in this repository. Do not touch
# installed apps or TCC records; macOS owns those separately.
rm -rf "$ROOT/.build/SpaceVisualizer.app" "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SpaceVisualizer"
cp "$ROOT/SpaceVisualizerApp/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/SpaceVisualizerApp/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/SpaceVisualizerApp/SpaceVisualizer.entitlements" "$APP/Contents/Resources/SpaceVisualizer.entitlements"

# Ad-hoc signing is sufficient for a local feasibility run. A Developer ID
# signature/notarization decision belongs to a later production change.
codesign --force --deep --sign - --entitlements "$APP/Contents/Resources/SpaceVisualizer.entitlements" "$APP"
printf '\nBuilt %s\n' "$APP"
printf 'Launch with: open "%s"\n' "$APP"
