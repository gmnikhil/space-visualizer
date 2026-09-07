# Space Visualizer Music observation

Space Visualizer observes Apple Music locally. It never sends playback, library, account, queue, volume, route, sign-in, or other mutating commands.

## Production query contract

`MusicPlaybackQueryAdapter` is the only production playback-observation path.

1. It checks `NSRunningApplication` for bundle ID `com.apple.Music` before invoking AppleScript. If Music is absent, it returns an unavailable/stopped observation and does **not** launch Music.
2. If Music is running, it starts `/usr/bin/osascript` off the UI thread with one fixed `-e` AppleScript source. It does not invoke a shell and accepts no interpolated track text, user input, or command fragments.
3. The helper has a one-second timeout, cancellation termination, and bounded retained stdout/stderr (8 KiB each). Oversize, malformed, canceled, denied, timed-out, and obsolete responses are distinct results.
4. The script reads `player state` first. Each current-track field is read in an independent `try` block, so missing track metadata does not make playback state unavailable.

The adapter returns the following fixed unit-separator-delimited fields:

| Field | Behavior when unavailable |
| --- | --- |
| player state | `.unknown`, never inferred from PCM silence |
| title / artist / album | `nil` |
| player position | `nil` when invalid |
| current-track duration | `nil` when invalid or absent |
| current-track artwork presence | `false` |

PCM format is a capture fact, not a source-quality label. No result claims Lossless, Hi-Res Lossless, Dolby Atmos, source bit depth, or codec unless a supported public interface exposes that information.

## Permission and retry behavior

Before **Enable automatic following**, the app performs no Music query and requests no Automation or system-audio access. The saved preference records only that the user enabled automatic following; it is not a fabricated TCC status.

After explicit consent, the app may perform its initial local query and macOS may show its relevant prompt. A known Automation denial or revocation stops observation and capture, exposes settings/retry guidance, and prevents five-second retry prompts. A retry must be a user action. A later app launch with persisted consent may recheck current playback, but still treats the actual query/capture outcome—not the preference—as authorization truth.

## Notifications and watchdog

Music playback notifications are optional hints only. Their target-Mac support and payload contract must be recorded before use. The two-second active watchdog remains authoritative for pause, stop, Music quit, and track-transition detection. Fresh silent PCM settles visuals but never proves Music paused.

## Target-Mac validation

Run:

```bash
./scripts/verify-music-observation-on-mac.sh
```

The script records the installed Music scripting dictionary, signed bundle identity, and a manual acceptance checklist in `.build/space-visualizer-music-observation.log`.

Complete the checklist from the signed `Space Visualizer.app`:

- With Music quit, enable automatic following and confirm Music does not launch.
- With Music running but no current track, confirm player state is handled separately from missing metadata.
- Verify the actual macOS Automation prompt attributes access acceptably to the signed Space Visualizer bundle and does not weaken the consent explanation because of `/usr/bin/osascript`.
- Verify the actual system-audio prompt from the signed bundle when a Music-only capture session is created.
- Record whether any public Music notification can be observed reliably enough to use as a hint. If not, leave notification hints disabled and retain the watchdog.

If Automation is attributed only to the helper or otherwise fails the consent contract, do not ship this adapter. Record the failure and choose a different supported local mechanism rather than weakening the permission model.
