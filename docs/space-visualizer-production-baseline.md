# Space Visualizer production baseline

Recorded before implementation changes on branch `space-visualizer-production`.

- Rollback checkpoint: `7c4b0b5f235cb5b6656a8b9087043c2d9717f46b`
- Baseline branch: `space-visualizer-production`
- Starting working-tree change preserved: untracked `openspec/changes/space-visualizer-production/`
- Recorded environment: Linux `6.8.0-117-generic aarch64` (not the target macOS machine)

## Verification results

| Command | Result |
| --- | --- |
| `swift test --parallel` | Not run: Swift is unavailable (`command not found`, exit 127) |
| `swift test -c release --parallel` | Not run: Swift is unavailable (`command not found`, exit 127) |
| macOS app build/performance run | Not run: macOS/Xcode/Activity Monitor tools are unavailable |

The debug/release and native performance baselines must be rerun on the target Mac before release readiness is claimed. These unavailable-environment results are recorded rather than treated as passing.

## Native verification note

The Linux coding environment cannot execute SwiftPM, Core Audio, TCC prompts, or macOS profiling tools. The target Mac has since completed the focused audio-pipeline debug/release tests and static capture checks. A Thread Sanitizer run remains an explicit target-Mac check:

```bash
RUN_THREAD_SANITIZER=1 ./scripts/verify-space-visualizer-audio-pipeline-on-mac.sh
```
