# Changelog

## 0.1.3 (first public release)

**App**
- Reads the OxiPro BP2 (AOJ-33A) over Bluetooth, only ever reading (never clears the cuff's memory). Background
  collecting with the app closed.
- History, charts and each reading explained in plain words, with nine blood pressure scales (NHS home and clinic,
  NICE, ESH 2023, ESC 2024, ACC/AHA, ISH 2020, JNC 7).
- Two people on one cuff: the app decides whose reading it is, and can ask after each sync.
- Sends to Health Connect and Home Assistant when switched on.
- Optional extras: medicines with blood pressure by dose and planned dose changes, NHS 7-day home check, trend and limit
  alerts, reminders, side-effect and coffee/exercise tags, clinic readings, calm mode, gentle streaks, Sunday summary,
  home screen widget, guided reading, quality check, watch context.
- Doctor PDF, spreadsheet and CSV reports; backup and restore; import from a MedM Health export.
- Report a problem: a privacy-safe problem log (no readings, names, addresses or tokens) sent to GitHub, a file or the
  clipboard, plus how to check a new cuff with nRF Connect.

**Home Assistant integration and command line**
- OxiPro BP2 (AOJ protocol) and Viatom/Lepu BP2 (A5 protocol) read over any Home Assistant Bluetooth adapter or
  ESPHome proxy, with sensors and a `bp2_ble_reading` event.
