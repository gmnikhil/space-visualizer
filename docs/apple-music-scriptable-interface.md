# Apple Music metadata interface

The feasibility spike observes Music through its macOS AppleScript dictionary. It never sends `play`, `pause`, `stop`, `next`, `previous`, seek, volume, queue, library, or sign-in commands.

## Properties used

`AppleScriptMusicQuery` asks the running Music application for the current track and normalizes these dictionary properties:

| AppleScript expression | Diagnostic field | Missing/invalid behavior |
| --- | --- | --- |
| `current track` → `name` | `TrackSnapshot.title` | `nil` / `Unknown title` |
| `current track` → `artist` | `TrackSnapshot.artist` | `nil` / `Unknown artist` |
| `current track` → `album` | `TrackSnapshot.album` | `nil` / `Unknown album` |
| `player state` | `TrackSnapshot.playbackState` | `.unknown` |
| `player position` | `TrackSnapshot.position` | `nil` if negative/non-finite |
| `current track` → `duration` | `TrackSnapshot.duration` | `nil` if non-positive/non-finite |
| `current track` → `artworks` count | `TrackSnapshot.artworkAvailable` | `false` |

The script returns a seven-item Apple Event list. The adapter checks the item count before reading it and maps AppleScript errors to independent metadata states. Metadata failure does not invalidate audio capture.

## Inspect the installed dictionary

On the target Mac, run:

```bash
./scripts/inspect-music-interface.sh
```

The command writes the installed dictionary to `.build/Music.sdef.xml`. Review that file with the macOS version and Music build recorded in the diagnostic report. The exact dictionary is a host dependency and must not be inferred from the presence of a track title alone.

## Permission behavior

The first user action that connects to Music or starts capture may cause macOS to request Automation permission. After a denial, the app stops automatic metadata retries. A retry occurs only when the user presses **Retry Music access**, **Connect to Music**, **Refresh**, or **Start capture**. The app does not request Apple ID credentials.
