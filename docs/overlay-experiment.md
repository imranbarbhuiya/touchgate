# Window-cover experiment: reverted

The overlay implementation was committed as `ea0d6cd` and tagged `v0.3.0`. It is retained in Git history for reference, but was reverted after hands-on testing on October 5, 2026.

The experiment used nonactivating opaque panels, CoreGraphics window bounds and stacking metadata, foreground-window occlusion, and a 200 ms refresh interval. Its aim was to keep protected apps in place and reduce focus changes from minimization, without requiring Accessibility or Screen Recording permission.

## Findings

- The user reported that focusing the hotbar removed the overlay and exposed protected app content.
- Touch ID sometimes failed to receive focus even after clicking.
- All 11 automated state and geometry tests passed, and the local release build succeeded. Those checks did not validate real desktop stacking or biometric focus reliably enough.
- An initial UI check showed the embedded unlock control, but did not establish reliable covering through app switches and cancellation.

The exact source of the exposure was not established. Foreground-window subtraction and panel ordering require further investigation; passing geometry tests does not prove that covers remain effective on a live desktop.

## Decision

Restore the previous hiding/minimization implementation. Keep the experiment and these findings in history, rather than shipping the overlay behavior as the stable default. A future attempt needs hands-on tests covering hotbar focus, app switching, cancellation, repeated unlocks, Spaces, full-screen windows, and multiple displays before release.
