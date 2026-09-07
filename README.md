# Space Visualizer

Space Visualizer is a local macOS companion for Apple Music. It follows Music playback automatically and turns fresh, measured Music output into an in-memory spatial scene. Music remains the player; Space Visualizer does not sign in, control playback, save audio, upload data, or use network services.

This repository contains one application. The production identity is:

- App bundle: `Space Visualizer.app`
- Executable: `SpaceVisualizer`
- Bundle identifier: `com.spacevisualizer.app`
- Minimum macOS: 14.2

## Target-Mac verification

The native app requires macOS, Xcode/Swift, Core Audio, Apple Events, and Music.app. Linux and Docker cannot run the native tests or permission flow.

From the repository root on the target Mac, run:

```bash
./scripts/verify-space-visualizer-on-mac.sh
```

The script records environment, package description, debug and optimized release tests, the control fixture, and the signed local bundle in `.build/space-visualizer-verification.log`. A successful build is not hardware acceptance evidence; record route, format, audibility, freshness, and limitations separately.

To inspect the installed Music dictionary and create the signed-bundle Automation/system-audio attribution checklist, run:

```bash
./scripts/verify-music-observation-on-mac.sh
```

This second script does not claim a permission pass by itself: complete the generated `.build/space-visualizer-music-observation-checklist.md` from the signed app and record the actual prompt attribution.

After audio-pipeline changes, run the focused debug/release and static-capture check:

```bash
./scripts/verify-space-visualizer-audio-pipeline-on-mac.sh
```

For the available Thread Sanitizer race check:

```bash
RUN_THREAD_SANITIZER=1 ./scripts/verify-space-visualizer-audio-pipeline-on-mac.sh
```

For an explicitly unoptimized debug app:

```bash
SPACE_VISUALIZER_BUILD_CONFIGURATION=debug ./scripts/build-space-visualizer-app.sh
```

After presentation changes, verify the full-canvas shell and optional diagnostics:

```bash
./scripts/verify-space-visualizer-presentation-on-mac.sh
```

For the normal interactive build and launch:

```bash
./scripts/build-space-visualizer-app.sh
open ".build/Space Visualizer.app"
```

The top-bar **Export image** action renders the current latest scene snapshot as a 3840×2160 PNG, includes available song title/artist/album and position details, and opens a save-location panel. It does not capture the screen, audio, or controls, and the image rendering path has no display link.

The test fixture can be generated independently:

```bash
./scripts/generate-space-visualizer-control-fixture.sh
```

Add `.build/SpaceVisualizerControl.wav` to Music with **File → Add to Library**, then play it from Music. Do not play it in another player: the capture path intentionally targets only the Music process.

## First launch and permissions

The first-run explanation describes two local permissions:

1. **Automation**: reads Music playback state and optional track details. It must not launch Music or mutate playback.
2. **System Audio Recording**: permits the Music-only process tap to analyze transient PCM in memory. It is not microphone input or screen capture.

No permission prompt is requested before the user chooses **Enable automatic following**. If permission is denied or later revoked, Space Visualizer stops affected work, shows retry/System Settings guidance, and does not prompt on every idle check. A new bundle identity may cause macOS to ask again; approve the signed `Space Visualizer.app` only when the prompt matches this explanation.

When Music is absent or paused, the window remains static and performs one bounded playback check every five seconds. When Music is playing, idle polling stops and a bounded active watchdog observes for pause, stop, quit, and track changes. Silence in fresh samples is displayed as silence, not treated as proof that playback stopped. The displayed song position is advanced locally between authoritative Music checks for visual accuracy; it never drives playback state or capture decisions.

## Privacy and scope

Capture is limited to the explicitly resolved Music process and selected route. PCM is bounded, transient, and never written to disk. The app declares no microphone, screen-capture, network, Apple ID, DRM, or private MediaRemote capability. Source-quality labels such as Lossless, Hi-Res Lossless, and Dolby Atmos remain unknown unless a supported public interface exposes them; measured PCM format is shown separately.

Diagnostics and acceptance export are optional and audio-free. Normal use has no required Start capture button, phase-selection workflow, or evidence-recording step.

## Performance acceptance

Use an optimized release build and record Mac model/OS, route, display, window size, and display cadence. Required targets are measured acceptance gates, not claims made by the build:

- idle mean below 2% of one core over 60 seconds;
- active mean below 50% of one core for the recorded M5 Pro workload;
- p95 main-thread frame work within the selected display interval;
- no app-caused interaction stall above 100 ms;
- no monotonic resource or memory growth through the documented 20-cycle run.

The visualizer requests display-synchronized rendering up to 120 Hz, while the system selects the actual cadence. Analysis uses overlapping windows and a latest-result-only handoff.

The release process sampler launches only Space Visualizer and never starts or controls Music. Run it with Music absent/paused for the 60-second idle gate, then with Music playback started manually for the five-minute active gate:

```bash
./scripts/measure-space-visualizer-performance-on-mac.sh idle 60
./scripts/measure-space-visualizer-performance-on-mac.sh active 300
```

It writes an audio-free CSV and Markdown summary under `.build/`; record the optional Diagnostics panel's display-tick p50/p95 values alongside them.

Use `docs/space-visualizer-release-acceptance-checklist.md` for the complete manual permission, route, lifecycle, 20-cycle, and release-handoff evidence packet.

## Rollback

Checkpoint `7c4b0b5` is the documented predecessor boundary. Preserve unrelated working-tree changes and roll back in a separate branch or worktree, for example:

```bash
git switch -c resonant-checkpoint-rollback 7c4b0b5
gn=".build/Resonant.app"
rm -rf "$gn" # only after quitting any old Resonant process
```

Do not reset or delete unrelated user work. The new bundle identity has separate macOS TCC records; never migrate those records manually. If the old `Resonant` entry remains under Privacy & Security, that is stale history for `com.resonant.FeasibilitySpike`, not the current app. Quit/delete any old installed Resonant copy if it is no longer needed, then turn off or remove the old entry directly in System Settings → Privacy & Security. `tccutil` resets may not remove the displayed row on newer macOS; do not delete the TCC database. Reopen System Settings or reboot if the row is only cached.
