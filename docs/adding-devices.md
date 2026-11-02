# Adding another monitor

Each new monitor needs its protocol: the bytes the phone sends, and how to read the replies. First check
[compatible-devices.md](compatible-devices.md) and find out what your monitor speaks. There are three cases, from
easiest to hardest.

1. **It uses the standard Bluetooth Blood Pressure service (`0x1810`).** No detective work: the format is published by
   the Bluetooth SIG. Open an issue with the monitor's name and service list.
2. **It shares a protocol Open Cuff already supports.** AOJ Medical monitors that advertise `FFE0` use the protocol in
   `bp2ble/aoj.py`. Try it and report back.
3. **It has its own private protocol.** It has to be worked out by watching how the monitor talks to its own app.
   The rest of this guide is for this case.

## Watching the conversation with the vendor app

You only need your own monitor and phone, and nothing from the vendor app is copied or shared: you are recording the
Bluetooth traffic between two devices you own, to make them work with other software.

1. On Android, turn on **Developer options** and **Enable Bluetooth HCI snoop log**, then turn Bluetooth off and on.
2. Open the vendor app, pair the monitor and sync a few readings you know (write down the numbers and times).
3. Get the log with `adb bugreport bugreport.zip` (it is inside, under `FS/data/log/bt/` or `FS/data/misc/bluetooth/logs/`)
   and open `btsnoop_hci.log` in **Wireshark**.
4. Filter on `btatt` and look at the writes the phone sends and the notifications that come back. Readings are usually
   easy to spot once you know the numbers: for example 121/79 shows up as the bytes `79 4F` in some order.
5. Work out:
   - the service and which characteristics are write and notify,
   - the frame layout (fixed header bytes, a length, a command byte, the data, a checksum),
   - the checksum (CRC-8 variants are common; try them against a few frames),
   - the sequence the app sends to get stored readings, and whether each reading needs an acknowledgement.

## Rules for new protocols

- **Read-only.** Never send anything that deletes readings or changes settings. If a command's meaning is unclear,
  leave it out. Note any dangerous commands in a comment so nobody sends them by accident.
- Put the frame building and parsing in a small module like `bp2ble/aoj.py`, with tests built from frames you
  captured (made-up readings are fine; never commit real ones).
- Add the monitor to [compatible-devices.md](compatible-devices.md).
