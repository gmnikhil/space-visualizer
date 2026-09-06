# Resonant feasibility spike

This repository now contains the native macOS feasibility spike for the approved Resonant companion direction. Apple Music remains the player; this diagnostic attempts to observe Music metadata and permitted audio output without signing into Apple Music or recording audio.

## Current environment

The implementation must be built and exercised on macOS. Docker/Linux cannot load SwiftUI, Core Audio, Apple Events, Music.app, or macOS privacy permissions.

## Run on the M5 Pro

From the repository root on the Mac, run the captured verification first:

```bash
./scripts/verify-on-mac.sh
```

The script records the environment, package description, test output, fixture generation, and app build in `.build/resonant-verification.log`. It automatically prefers `/Applications/Xcode.app` when installed. `uname -s` must print `Darwin` and the test suite must pass before hardware testing.

The app bundle now defaults to an optimized **release** build. Verification runs both debug and release tests; compare Activity Monitor usage only after quitting the old process and opening the rebuilt bundle. For debugging, `RESONANT_BUILD_CONFIGURATION=debug ./scripts/build-resonant-app.sh` explicitly builds an unoptimized app.

To launch the already-built diagnostic:

```bash
open .build/Resonant.app
```

Use **Connect to Music** or **Start capture** to request the corresponding permission in context. Approve only the permissions described by the app; microphone and screen capture are not part of this spike.

Inspect the actual Music scripting dictionary when documenting the target Mac:

```bash
./scripts/inspect-music-interface.sh
```

This writes `.build/Music.sdef.xml`. See `docs/apple-music-scriptable-interface.md` for the exact fields used.

Run the unprotected control fixture before Apple Music tests:

```bash
./scripts/generate-control-fixture.sh
```

Because the tap is intentionally isolated to the Music process, add `.build/ResonantControl.wav` to Music with **File → Add to Library**, then play it from Music. Do not play the fixture in QuickTime or another app; that would correctly produce no Music-process samples.

Then use the diagnostic window to test, in order:

1. Local unprotected control played by Music through built-in speakers.
2. Streamed Apple Music track through built-in speakers.
3. Downloaded Apple Music track through built-in speakers.
4. Repeat the above on AirPlay if available.

The app exports an audio-free evidence report. A successful build does not prove that protected Apple Music playback is capturable; the report must contain the measured result.

## Performance verification

The display link requests up to 120 Hz; macOS and the attached display choose the actual cadence. FFT analysis runs on a serial worker with one overwrite-only feature slot, while diagnostic state is published at most four times per second. Only the visual subtree observes high-frequency features. Stop cancels the worker and clears the latest result. Audio frames use overlapping windows and discard backlog rather than replaying it.

After building, check scrolling and CPU during at least two minutes of capture, then check idle CPU after Stop. These architecture changes are not a measured latency or CPU guarantee. Music metadata queries still use the main-thread AppleScript adapter and remain a possible source of brief UI stalls.

## Scope boundary

This is a feasibility diagnostic, not the production visualizer. The 2D signal panel and projected 3D shape preview validate the combined visual direction. The polished Metal scene engine, library, lyrics, cloud processing, microphone capture, DRM workarounds, and App Store distribution are out of scope.
