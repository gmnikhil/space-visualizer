# Space Visualizer

### A quiet space for Music.

Space Visualizer is a native macOS companion for Apple Music that turns the music playing on your Mac into a live, audio-reactive visual scene. It follows playback automatically, bringing sound into motion while Apple Music remains in charge of listening.

## See it in action

[![Space Visualizer demo](./videos/space_visualizer_short.gif)](./videos/space_visualizer_short.mp4)

## Features

- **Visuals driven by real audio** — the scene responds to the energy and frequency content of Music’s output, rather than a canned animation.
- **Stereo frequency pairs** — 28 balls cover 14 frequency regions. Each left/right pair shares a region, with height following its own channel. Orange represents bass, mint mids, and purple treble. Positions stay fixed; bass settles more slowly and treble responds more sharply. Mono and unknown multichannel layouts use matching energy on both sides.
- **Automatic playback following** — follows playback and track changes, settling into a quiet waiting state when Music is paused or stopped.
- **An immersive canvas** — a spacious visual scene with minimal controls and display-synchronized rendering.
- **Manual frame-rate control** — choose 30, 60, or 120 FPS under **Visualizer → Frame Rate** in the macOS menu bar to compare smoothness and power usage. Defaults to 60 FPS, remembers your selection, and applies changes immediately. These are caps; actual cadence depends on your display and macOS.
- **Now-playing details** — available song title, artist, album, and playback position appear alongside the visuals.
- **4K image export** — save the current scene as a 3840 × 2160 PNG with available track details, without capturing the screen or recording audio.
- **Uninterrupted listening** — does not mute Music, change the volume, skip tracks, or take over playback.
- **Window-aware activity** — capture and visualization suspend when the window is hidden or closed, and resume observation when it reopens.

## Made for Apple Music on Mac

Space Visualizer requires **macOS 14.2 or later** and the **Music app**. It is a visual companion, not a music player or a streaming service.

Automatic following uses two macOS permissions:

- **Automation** to read Music’s playback state and track details.
- **System Audio Recording** to analyze Music’s audio for visualization.

Permission requests begin only after automatic following is enabled. The app does not launch Music or start playback on its own.

Open **Visualizer → Diagnostics…** for the active automatic-following session's signal status, measured route/format, and audio-free report export. Playback alone does not imply capture has started; diagnostics distinguish waiting for input, live audio, silence, and inactive capture. Diagnostics also shows window visibility, the scheduled poller, whether a playback check is in progress, and its last start/completion times and result. These fields are included in exported reports.

Fully covered, hidden, and minimized windows suspend work. Revealing the window rechecks playback immediately; bringing an already-visible window to the foreground also requests a check without restarting healthy capture. If recovery ever stalls, open Diagnostics and export a report before restarting the app.

## Testing stereo reactions on Mac

Build with `scripts/build-space-visualizer-app.sh` and run `swift test`. Play stereo control audio through Music: left-only then right-only tones should lift the corresponding side; centered tones should lift matching partners equally. Different tones in each channel should activate different pairs. The central rings continue responding to the broad mixed signal.

Compare 30 / 60 / 120 FPS with the same track, window size, sample rate, and power state. Pair response timing should stay consistent. Compare release-build CPU and Energy Impact with the previous version; stereo frequency analysis adds worker-side FFT work, so battery impact must be measured rather than assumed. Also check silence, pause/resume, window hiding, and Reduce Motion.

## Local by design

Music audio is analyzed temporarily in memory—it is never saved or uploaded. Capture targets Music, not the microphone or other apps’ audio.

Space Visualizer requires no account, Apple ID sign-in, or network service of its own. Exported images contain the visual scene and available track details, never audio.

**Your music stays in Music. Space Visualizer gives it a space to move.**
