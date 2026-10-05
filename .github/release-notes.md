TouchGate is a macOS menu-bar app that requests Touch ID when you open protected apps, while leaving background messages and tasks running.

## Install

Requires macOS 14 or newer and working Touch ID.

1. Download `TouchGate-macos-arm64.zip` for Apple silicon or `TouchGate-macos-x64.zip` for Intel.
2. Unzip and drag **TouchGate.app** to **Applications**.
3. Launch **TouchGate** from Finder, Spotlight, or Raycast. Reopen it the same way after quitting.
4. Add protected apps. No Accessibility or Screen Recording permission is needed.

Locked windows now receive opaque, nonactivating covers instead of being hidden or minimized. Apps keep running in place, and unrelated foreground windows remain usable. Click a cover to retry an unlock after cancellation. Window geometry refreshes approximately every 200 milliseconds.

Touch ID appears inside TouchGate's unlock window using Apple's embedded authentication control, avoiding a separate panel competing for focus. In Settings, **Ask for Touch ID** offers **Every app switch** (default) or **Once per launch**. Both modes relock on sleep, screen locking, or Lock now. A mode change requires authentication.

No Terminal or Xcode installation is required. SHA-256 checksum files accompany each ZIP.

These builds are ad-hoc signed, without Developer ID signing or notarization. If macOS blocks opening, follow [Apple's instructions](https://support.apple.com/102445) in System Settings → Privacy & Security. Do not disable Gatekeeper globally.

To update, quit TouchGate and replace the app in Applications. Your protected-app list remains in macOS preferences. If Start at login was enabled, check it again after moving the app.

TouchGate is a casual privacy barrier. It does not secure app data, notification previews, or prevent force-quitting. Apple handles fingerprint authentication.
