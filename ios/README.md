# Tindeq Scrolling for iOS

A standalone iOS app that plays Instagram Reels from Instagram's mobile website
inside the app, gated by Tindeq Progressor pull force:

- **Hold** at least min pull → reels keep playing.
- **Drop below** min pull → 3 s warning, then either the feed locks (video
  paused, covered until you pull again) or the session ends. Your choice in Options.
- **Spike** to scroll pull → jumps to the next reel.
- **Hands-free only** (optional) → finger swipes between reels are blocked; taps still work.

iOS doesn't allow one app to control another, so instead of overlaying the
Instagram app (as the Android version does) this app embeds
`instagram.com/reels/` in a `WKWebView`. You log in on Instagram's own page,
and the login persists like Safari's.

## Layout

```
ios/
  project.yml                 XcodeGen spec (the .xcodeproj is generated, not committed)
  Packages/TindeqCore/        Platform-independent Swift package, unit tested
    ForceGate.swift           Gate state machine (port of Android ForceGateController)
    TindeqProtocol.swift      Progressor BLE packet format
    InstagramRoutes.swift     Reels-only navigation policy
    WeightUnit.swift, GateSettings.swift
  TindeqScrolling/
    App/                      App entry, AppModel (state + wiring), settings persistence
    BLE/ProgressorBLE.swift   CoreBluetooth client
    Web/                      WKWebView controller, Instagram login helpers
    Injected/ReelsBridge.js   Script injected into instagram.com: next reel, pause, nav hiding
    Views/                    SwiftUI: home/settings, session, HUD, overlays
  HANDOFF.md                  Build/test/TestFlight steps for finishing on a Mac
```

## Build

```bash
brew install xcodegen
cd ios
xcodegen generate
open TindeqScrolling.xcodeproj
```

Set your team and bundle ID in `project.yml` first (see `HANDOFF.md`).

Core logic tests run anywhere Swift does, including Linux:

```bash
cd ios/Packages/TindeqCore && swift test
```

## Debug features (Debug builds only)

- **Simulated Progressor** toggle on the home screen: drives force from a slider so
  you can test in the simulator, which has no Bluetooth.
- **↓ button** in a session: calls next-reel without pulling.
- **Long-press the force HUD**: shows what `ReelsBridge.js` sees (scroll container,
  videos, last scroll result).
- The web view is inspectable from Safari → Develop menu.

## Caveats

- `ReelsBridge.js` depends on Instagram's web markup. When Instagram changes it,
  next-reel or nav hiding may break; that file is the place to fix it.
- Not affiliated with Tindeq or Meta. Embedding Instagram's site and automating
  scrolling may conflict with Instagram's terms, and with App Store guidelines for a
  public release. TestFlight beta testing is the realistic target.
