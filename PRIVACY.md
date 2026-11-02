# Privacy

Open Cuff is built so your blood pressure readings stay yours. This covers the Android app; the Home Assistant
integration and the command line run on your own computer and send nothing anywhere.

## The short version

- **No account, no sign-up, no adverts, no analytics, no tracking.** The app has no server of its own.
- **Your readings stay on your phone**, in the app's private storage, unless you switch a destination on.
- **Nothing leaves the phone by itself.** Readings only go where you send them (below), and the problem log only goes
  where you send it.

## Where your data can go, and only if you choose

| You switch on or tap | What goes | Where |
|---|---|---|
| **Health Connect** | Each reading's top and bottom numbers, pulse and time | Health Connect on your phone, so apps you allow (such as Samsung Health or Google Fit) can see them |
| **Home Assistant** | New readings from the last 3 hours | Only the Home Assistant address you type in, with the token you give it. The token stays on the phone and is never put in backups |
| **Back up**, **Reports** (PDF, spreadsheet, CSV) | Your readings and settings (never the Home Assistant token) | Wherever you pick in Android's share menu |
| **Report a problem** | The problem log and phone details (see below) | GitHub, a file or the clipboard, as you choose. Nothing is sent until you press submit on GitHub yourself |

Turning a destination off stops new sending straight away. Readings already sent stay in that place, and are removed
there (Health Connect, Home Assistant) the usual way.

## The problem log

The app keeps a short diary of what it did, so problems can be fixed: Bluetooth on or off, finding and connecting to
the cuff, how many readings were copied, sending results, the background service starting or stopping, and crashes.

It **never** contains your readings, names (including a name you gave your cuff), web addresses or tokens; these are
removed before anything is written, and a test checks this. The cuff's Bluetooth address is cut to its last two
characters. The phone details added to a report are its make, model and Android version, the app version and which
features are switched on. The log stays on the phone (about the last 1,500 lines) until you share it or tap Clear.

## What the app reads from Health Connect

Only if you switch on "Context from your watch": last night's sleep and your resting heart rate, to show next to a
reading. They are read on the phone and not stored or sent anywhere.

## Permissions, and why

| Permission | Why |
|---|---|
| Nearby devices (Bluetooth scan and connect), and location on older Android | To find and read your cuff. Location is never used for anything else |
| Notifications | Reminders, "whose reading?" questions, and the small notice while background collecting is on |
| Foreground service, run at start-up, stay awake, ignore battery optimisation | Background collecting, so readings arrive with the app closed. Only while you have it switched on |
| Internet | Only for Home Assistant, and for opening GitHub or the Play Store when you tap a link |
| Health Connect: write blood pressure and heart rate; read sleep and resting heart rate | Only for the Health Connect and watch-context switches above |

## Your cuff

The app only ever reads from the cuff. It never sends the command that clears its memory.

## Removing everything

Uninstalling the app deletes everything it stored on the phone. Copies you sent elsewhere (Health Connect, Home
Assistant, backups, shared files) are not affected.

## Questions

Open an issue: https://github.com/Domocn/open-cuff/issues
