# Tindeq Scrolling

Android app that gates Instagram Reels behind Tindeq pull force. Hold a minimum pull to keep Reels usable; spike higher to auto-swipe to the next reel.

An iOS version lives in [`ios/`](ios/README.md). iOS can't overlay other apps, so it is a standalone app that plays Instagram's web Reels with the same pull gate.

## How it works

1. Enable **Tindeq Scrolling** in Android accessibility settings (Instagram only).
2. In the app: set min pull + scroll pull thresholds, enable the gate, connect your Progressor over BLE.
3. Open Instagram Reels:
   - Below min pull → fullscreen overlay blocks interaction.
   - At/above min pull → Reels work normally.
   - Brief pull at/above scroll threshold → accessibility swipe to next reel.

BLE protocol matches the TypeScript SDK in `tindeq-sdk/` (Tindeq Progressor GATT service).

## Project layout

```
app/                          Android app (Kotlin)
  ble/                        Progressor GATT client
  accessibility/              Instagram overlay + swipe gestures
  service/                    Foreground BLE service
ios/                          iOS app (SwiftUI + WKWebView), see ios/README.md
tindeq-sdk/                   Reference TS SDK (not used at runtime)
```

## Build & deploy (Android Studio)

1. Open this repo root in Android Studio (`File → Open` → select `tindeq_scrolling`).
2. Let Gradle sync (Android Studio will download the wrapper if needed).
3. Connect a physical Android device (API 26+, BLE required; emulator won't work for Tindeq).
4. **Run** (green play) to install on the device.

From terminal (after wrapper exists):

```bash
./gradlew :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

## On-device test checklist

1. Grant Bluetooth (+ notifications on Android 13+) when prompted.
2. Settings → Accessibility → **Tindeq Scrolling** → On.
3. App: enable gate, tap **Connect Progressor** (device must be awake/nearby).
4. Open Instagram → Reels tab.
5. Verify live force updates in the app.
6. Release pull below min → overlay should block Reels.
7. Hold min pull → overlay clears.
8. Spike to scroll threshold → should swipe to next reel.

## Tuning

| Setting | Default | Purpose |
|---------|---------|---------|
| Min pull | 2.0 kg | Force required to keep Instagram open |
| Scroll pull | 8.0 kg | Spike force that triggers next-reel swipe |

Scroll re-arms after force drops below ~85% of scroll pull.

## Known gaps (pre-production)

- No device picker UI (auto-scans for nearest Progressor/Tindeq name).
- Swipe path is a fixed vertical gesture; may need per-device tuning.
- Instagram UI changes can break gesture targeting.
- Tare only works while BLE service is connected.

## Disclaimer

Uses accessibility APIs to automate Instagram. Not affiliated with Tindeq or Meta; use at your own risk.

## License

TBD
