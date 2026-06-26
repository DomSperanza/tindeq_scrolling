# Tindeq Scrolling

Use a [Tindeq Progressor](https://tindeq.com/) as a gate for Instagram Reels: you must apply finger force on the device to keep the app active and advance from reel to reel. Doom scroll with a side of hangboard training.

## Concept

- An Android **Accessibility Service** monitors Instagram (Reels).
- The app connects to a Tindeq over **Bluetooth LE** and reads live force.
- Scrolling / staying on Reels requires maintaining a target grip force (configurable threshold and hold time).
- Release pressure → scrolling stops or the overlay blocks interaction until you grip again.

## Planned components

| Piece | Role |
|-------|------|
| Android app | BLE client, force logic, accessibility gestures |
| Accessibility Service | Detect Reels UI, perform swipe-to-next-reel |
| Tindeq BLE | Force samples from the Progressor |

## Requirements (target)

- Android 8+ (API 26+) with Bluetooth LE
- Tindeq Progressor (firmware compatible with Tindeq BLE protocol)
- Instagram installed; user grants accessibility + nearby devices permissions

## Project status

Early setup — no implementation yet.

## Development

```bash
# Clone and open in Android Studio when the app module exists
git clone <repo-url>
cd tindeq_scrolling
```

## Disclaimer

This project automates interaction with a third-party app via accessibility APIs. Use at your own risk; it may conflict with Instagram's terms of service. Not affiliated with Tindeq or Meta.

## License

TBD
