# Handoff: finish the iOS app on the Mac

You are picking up the iOS version of Tindeq Scrolling. It was written on a Linux
machine, so **the app target has never been compiled against the iOS SDK.** Your
job is to get it building, run it in the simulator and on a device, fix what
breaks, and get it onto TestFlight. Read `ios/README.md` first for what the app
does and how the code is laid out.

## What the app is

- Android (in `app/`) overlays the real Instagram app via accessibility services.
  iOS can't do that, so this is a **standalone SwiftUI app** that embeds
  `https://www.instagram.com/reels/` in a `WKWebView` with our own UI on top.
- Tindeq Progressor over CoreBluetooth streams force.
  - **Hold ≥ min pull:** reels play.
  - **Below min:** a 3 s warning, then either *lock the feed* (pause and cover it) or *end the session*. This is a user setting.
  - **Spike ≥ scroll pull:** go to the next reel.
- **Reels only:** links and routes outside `/reels`, `/reel/` and the login pages are blocked. Instagram's bottom nav is hidden.
- **Login doesn't count against the user:** the gate only enforces on reels pages, so login and 2FA aren't gated.

## What was verified on Linux

| Check | Result |
|---|---|
| `Packages/TindeqCore` `swift test` (Swift 6.1.2, Linux) | 26/26 pass |
| `xcodegen generate` (XcodeGen 2.42.0, built on Linux) | Project generated; Swift files in Sources, `ReelsBridge.js` + assets in Resources |
| `node --check ReelsBridge.js` | Syntax OK |
| App target (SwiftUI/WebKit/CoreBluetooth) compile | **Not verified**: no iOS SDK on Linux |
| Behavior against live instagram.com | **Not verified** |

## Ground rules

- Don't touch the Android app (`app/`) or `tindeq-sdk/`. The user has uncommitted
  Android work in progress.
- `TindeqCore` is the shared logic. If you change it, keep `swift test` green and
  add tests for new behavior. Gate behavior should stay identical to Android's
  `ForceGateController` (3 s grace, 0.85 re-arm ratio, 600 ms scroll cooldown).
- Don't commit the generated `.xcodeproj` or `Info.plist` (see `ios/.gitignore`). Edit `project.yml`.
- Don't use private APIs, and don't call Instagram's private/GraphQL APIs directly.
  The app only displays Instagram's own website.
- Keep everything that depends on Instagram's markup in `Injected/ReelsBridge.js`.

## Step 1: Prerequisites

```bash
xcode-select -p             # Xcode installed (16 or newer)
brew install xcodegen
cd ios/Packages/TindeqCore && swift test && cd ../..
```

The user must be signed into their Apple Developer account in Xcode → Settings → Accounts.

## Step 2: Configure signing

Edit `ios/project.yml`:

- `PRODUCT_BUNDLE_IDENTIFIER`: replace `com.example.tindeqscrolling` with the
  user's own reverse-DNS ID. Ask them; don't guess. It must be unique in App Store Connect.
- `DEVELOPMENT_TEAM`: their 10-character Team ID. Ask, or read it from Xcode → Settings → Accounts.

Then:

```bash
cd ios
xcodegen generate
```

## Step 3: Get it compiling

```bash
xcodebuild -project TindeqScrolling.xcodeproj -scheme TindeqScrolling \
  -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | grep -E "error|warning: .*isolat" | head -50
```

Pick any installed simulator (`xcrun simctl list devices available`). Places most
likely to need small fixes, since they couldn't be checked against the SDK:

- **Concurrency annotations.** The project uses Swift 5 language mode (`SWIFT_VERSION: 5.0`) with `@MainActor` classes.
  - `ProgressorBLE` uses `@preconcurrency` conformances for the CoreBluetooth delegates.
  - `ReelsWebController` overrides `observeValue` as `nonisolated` and hops back with `MainActor.assumeIsolated`.
  - If the compiler rejects one of these, fix it in the same spirit. Don't switch to Swift 6 mode just to silence warnings.
- **WebKit Swift API labels.** `callAsyncJavaScript(_:contentWorld:)` (async) and the
  async `webView(_:decidePolicyFor:) -> WKNavigationActionPolicy` delegate method.
  If a delegate method signature doesn't exactly match the SDK, Swift may only warn
  ("nearly matches optional requirement") and **never call it**, which would
  silently disable reels-only enforcement. Treat that warning as an error.
- **SwiftUI APIs:** `.contentTransition(.numericText(countsDown:))`, `.background(.bar)`,
  and `@Bindable` local vars inside `body`. All are iOS 17+, so they should be fine.

Fix warnings about actor isolation too, not just errors, where it's cheap.

## Step 4: Simulator smoke test (no Bluetooth needed)

Run the app in the simulator. On the home screen, turn on **Debug → Simulated Progressor**.

1. **Start Reels:** Instagram's login page should load. Log in with a test
   account. Use username/password; "Continue with Facebook" may be blocked in
   embedded web views. During login the "Log in to Instagram…" banner shows and
   **no** warning or lock overlays appear.
2. After login you should land on `/reels/`, not the home feed. Instagram's bottom
   tab bar should be hidden.
3. **Gate:** drag the debug slider below the white tick (min) and you get the "Pull harder 3…2…1"
   warning, then a lock that pauses video. Drag above min and it unlocks and the video resumes.
4. **Next reel:** drag past the blue tick (scroll pull) and the feed advances one reel and the HUD
   flashes ↓. Drop below 85% of scroll pull, spike again, and it advances again.
   The **↓ debug button** also advances without the slider.
5. **Diagnostics:** long-press the HUD. `last scroll` should start with `ok:`. If it says
   `stuck:` or `no-bridge`, see Step 6.
6. **Hands-free:** turn it on in Options, start a session, and confirm finger swipes don't
   change reels while taps (mute, like) still work.
7. **End session mode:** with "End the session" selected, drop below min for 3 s. You should return
   home with the red "Session ended" banner.
8. **Reels only:** tap a username or the audio/profile links. Nothing should navigate
   away, or if it does, the app should bounce back to reels. External links do nothing.
9. **Sign out of Instagram** on home clears the login (the next session shows the login page).

## Step 5: Device test with a real Progressor

Build to the user's iPhone. The simulator can't do Bluetooth.

1. First **Connect Progressor** shows the Bluetooth permission prompt.
2. Status goes Scanning → Connecting → Connected. Pull on the device to wake it.
   Live force updates on the home screen and the meter moves.
3. **Tare** zeroes the reading.
4. Repeat the gate, next-reel and hands-free checks from Step 4 with real pulls.
   Confirm the screen doesn't auto-lock during a session (idle timer is disabled).
5. Turn the Progressor off mid-session. You should see the "Progressor disconnected" overlay with
   video paused. **Reconnect** should restore it.
6. Disconnect from home. The Progressor should be sent the sleep command.

## Step 6: Tuning `ReelsBridge.js` against live Instagram

This is the part most likely to need real work, because it was written without
access to Instagram's current markup. Attach Safari Web Inspector (Safari →
Develop → *Simulator/device* → instagram.com; Debug builds set
`isInspectable`), then in the console:

```js
__tindeq.diagnose()     // path, videos found, current reel rect, scroll container
await __tindeq.nextReel() // returns ok:… / stuck:…
```

How it works:

- `currentReel()` picks the `<video>` with the most on-screen area.
- `scrollContainerFor()` walks up to the nearest `overflow-y: auto|scroll` ancestor.
- `nextReel()` scrolls that container by the distance to the next video, or by one
  container height. Fallbacks are an instant jump, then an ArrowDown key event.

Common fixes:

- Instagram may render one `<video>` at a time with a different scroll root.
  Adjust `scrollContainerFor` or the step size.
- If nav hiding misses or over-hides, tune `hideChrome()`. It only hides small
  (≤ 25% of the viewport) fixed or sticky bars with 3+ out-of-reels links, plus
  "Open app" banners.
- If videos don't autoplay with sound, that's Instagram's web default (muted until tap).
  Leave it unless the user asks.

Keep the public API (`nextReel`, `setLocked`, `setHandsFree`, `diagnose`) stable.
Swift calls it.

## Step 7: TestFlight

1. Bump `CURRENT_PROJECT_VERSION` in `project.yml` for each upload, then regenerate.
2. Product → Archive (Release), then Distribute App → App Store Connect → Upload.
   Create the app record in App Store Connect first, with the same bundle ID.
   - Export compliance is already declared: `ITSAppUsesNonExemptEncryption = false`.
   - App Privacy: the app itself collects no data. Instagram's site runs in the web view under Instagram's own policies.
3. **Internal testers** (up to 100 people on the user's App Store Connect team) need no review.
4. **External testers** need Beta App Review. In the review notes, describe the app
   accurately: a Tindeq Progressor training app that shows Instagram's mobile website.
   Provide a test Instagram login, and explain that the app needs a Tindeq Progressor.
   The simulated-force mode is Debug-only and compiled out of Release builds. If
   review rejects because they can't test without hardware, ask the user whether to
   ship a reviewer-accessible demo mode. Be aware of the risk: guideline 5.2.2 covers third-party content, 4.2 covers web wrappers,
   and Instagram's terms may also apply. Public App Store release is uncertain. Flag any rejection to the user rather than
   working around review.

## Known gaps

- Connects to the first Progressor it finds (same as Android). There's no device picker.
- No background Bluetooth mode. The session is foreground-only by design.
- The gate counts down immediately when reels first load, so the user should already be pulling.
  This matches Android. Revisit if testers find it harsh.
- The app icon (`Resources/Assets.xcassets/AppIcon.appiconset`) is a generated placeholder.
- The display name "Tindeq Scrolling" uses Tindeq's brand. Consider renaming before any public release.

## When you're done

Report back to the user with:

- what you changed to get it compiling;
- results of the Step 4 and Step 5 checklists (pass/fail per item);
- any `ReelsBridge.js` tuning you did;
- TestFlight status.
