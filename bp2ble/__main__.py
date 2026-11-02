"""Command line: python -m bp2ble [scan | info | readings] [--address AA:BB:..] [--json] [--debug]"""
from __future__ import annotations

import argparse
import asyncio
import json
import logging
import sys

from .client import BP2Client, find_bp2


async def main() -> int:
    ap = argparse.ArgumentParser(prog="bp2ble", description="Read stored readings from a BP2-family blood pressure monitor.")
    ap.add_argument("action", choices=["scan", "info", "readings"], nargs="?", default="readings")
    ap.add_argument("--address", help="Bluetooth address of the monitor (skips the name search)")
    ap.add_argument("--timeout", type=float, default=20.0, help="seconds to search for the monitor")
    ap.add_argument("--json", action="store_true", help="print readings as JSON")
    ap.add_argument("--sync-time", action="store_true", help="set the monitor clock to this computer's time")
    ap.add_argument("--debug", action="store_true", help="show every Bluetooth packet")
    a = ap.parse_args()
    logging.basicConfig(level=logging.DEBUG if a.debug else logging.WARNING, format="%(message)s")

    print("Looking for the monitor. Tap the menu and Start/Stop buttons together to switch its Bluetooth on.", file=sys.stderr)
    dev = await find_bp2(a.timeout, a.address)
    if not dev:
        print("No BP2 monitor found.", file=sys.stderr)
        return 1
    print(f"Found {dev.name} at {dev.address}", file=sys.stderr)
    if a.action == "scan":
        return 0

    async with BP2Client(dev) as bp:
        if a.sync_time:
            print("Clock set." if await bp.sync_time() else "Monitor refused the clock change.", file=sys.stderr)
        if a.action == "info":
            print((await bp.get_info()).hex())
            return 0
        readings = await bp.readings()

    if a.json:
        print(json.dumps([r.as_dict() for r in readings], indent=2))
    else:
        for r in readings:
            flag = "  irregular pulse" if r.irregular else ""
            print(f"{r.time:%Y-%m-%d %H:%M}  {r.systolic}/{r.diastolic}  pulse {r.pulse}{flag}")
        print(f"{len(readings)} readings", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
