# Compatible devices

Open Cuff reads blood pressure monitors over Bluetooth Low Energy without their vendor app. This page says which
monitors work today, which should work, and how to find out about yours.

| Monitor | Open Cuff app (Android) | Home Assistant and command line | Status |
|---|---|---|---|
| **OxiPro BP2** (made by AOJ Medical, model AOJ-33A) | Yes | Yes | Tested, used every day |
| Other **AOJ Medical** blood pressure monitors that advertise service `FFE0` | Should work | Should work | Untested, please report |
| **Viatom / Lepu BP2, BP2A, BP2W** (advertise as `BP2...`, frames start `A5`) | Not yet | Yes | Untested, built from the manufacturer's public demo |
| Monitors using the **standard Bluetooth Blood Pressure service** `0x1810` (many Omron, A&D, Beurer, Rossmax, Silvercrest and Qardio models) | Not yet, planned | Not yet | Not supported yet |
| Anything with its own private protocol | No | No | Needs the protocol worked out, see [adding-devices.md](adding-devices.md) |

"Should work" means the monitor uses a protocol Open Cuff already speaks, but nobody has confirmed it with that model.
If yours works (or doesn't), please say so in an issue, it helps the next person.

> **No warranty.** This list is a best effort and some of it is reported by other users. A model marked "Should work"
> or "Untested" may not work, or may behave differently. Check your own monitor's screen against what the app shows.
>
> **Your cuff's memory.** Open Cuff only reads from a monitor and never sends the command that clears its memory.
> Some monitors delete their stored readings after any successful download, whatever app does it, and some apps
> (including other tools) clear them for you. If you have readings on a monitor you haven't backed up, keep a copy
> before trying a new app or a monitor that isn't marked Tested.

## Full device list

[devices.csv](devices.csv) lists about 390 Bluetooth health devices (blood pressure monitors first, then pulse
oximeters, scales, glucose meters, thermometers, ECG and others) with brand, model, connection type and where Open Cuff
stands with each. Device types and connections are best guesses from the model names, not checked against every
device. Only the OxiPro BP2 is tested; for anything else, check it as below.

## Find out what your monitor speaks

You need the free **nRF Connect** app (Android or iOS). **Only read, never write:** don't tap the up-arrow (write)
buttons, because the wrong bytes can clear a cuff's memory. Nothing below needs them.

1. **Scanner.** Switch the cuff's Bluetooth on (take a reading, or press its Bluetooth button) and pull down to scan.
   Find it by name. If you can't tell which it is, hold the phone right next to the cuff: its signal jumps.
2. **Advertising details.** Tap its row and note the name and the **service UUIDs**:
   - `FFE0` with a name like `OxiPro BP2`: the AOJ protocol, so Open Cuff should read it.
   - A name starting `BP2` and service `14839ac4-...` (Viatom): works with Home Assistant and the command line.
   - `1810` (Blood Pressure): the standard format. Not in Open Cuff yet, but adding it is straightforward.
   - Anything else: a private protocol.
3. **Connect.** Tap Connect while the cuff's Bluetooth is on and take a screenshot of the services list. Each
   characteristic shows READ, WRITE, NOTIFY or INDICATE.
4. **Catch a reading.**
   - Standard `1810` cuffs: under Blood Pressure, turn on indications for **Blood Pressure Measurement (2A35)** with
     the triple-arrow button, then take a reading. nRF Connect usually decodes it for you (for example 124/77 mmHg,
     pulse 72). If it does, the cuff only needs the standard reader added.
   - Other cuffs: turn on notifications for each NOTIFY or INDICATE characteristic, then take a reading or sync.
5. **Save the log.** Menu > **Log** > Share, and note the numbers the cuff showed on its own screen so the bytes can
   be matched.

## Asking for your cuff, or reporting a problem

- **Your cuff isn't supported yet (or you've found that one works):** open a
  [Support my cuff](https://github.com/Domocn/open-cuff/issues/new?template=new-cuff.yml) issue with the name, the
  service UUIDs, the screenshot from step 3 and the log from step 5. In the app the same link is under **More >
  Report a problem > New cuff, or one that won't connect?**
- **Something went wrong:** in the app, **More > Report a problem > Report on GitHub** opens an issue with your phone
  model, the app version and the app's problem log already filled in. The log never contains your readings, names,
  addresses or tokens. If the cuff won't connect, an nRF Connect log from step 5 helps too.

Made-up numbers are fine for test readings. Please don't post real readings you'd rather keep private.

## Safety

Open Cuff only ever reads from a monitor. It never sends the commands that clear a monitor's memory or change its
settings (apart from setting the clock on Viatom monitors, which the command line does only when asked).
