# Wakey Wakey

A gentle wake-up alarm that helps you get up on your own and keep a steady sleep schedule.

**Try the web version:** https://anipupper.github.io/WakeyWakey/

- **Gentle alarm:** soft chimes that build only slightly in volume, with a different chime each day so you don't tune it out.
- **Consistency streak:** Luna the moon (drawn in tonight's real moon phase) cheers you on for every morning you're up on time, on your own.
- **Flexible schedule:** one time for every day, weekdays plus weekends, or custom times for each day.
- **Phone-down tracking:** see when your phone went down each night compared with your bedtime goal.

## What's in here

| Folder | What it is |
| --- | --- |
| `ios/` | The iPhone app (SwiftUI). Uses AlarmKit, so alarms ring even when the phone is locked, and can import sleep from Apple Health. Open `ios/WakeyWakey.xcodeproj` in Xcode 27 (iOS 26+). |
| `web/` | The original web prototype, published to GitHub Pages. Alarms only ring while the page is open. |

## Running the web version locally

```bash
python3 serve.py
```

Then open http://localhost:8000.
