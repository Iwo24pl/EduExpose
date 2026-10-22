import json
import subprocess
import sys

raw = subprocess.check_output([
    "xcrun", "simctl", "list", "devices", "available", "-j"
])
devices = json.loads(raw)["devices"]

candidates = []
for runtime, items in devices.items():
    for device in items:
        if device.get("isAvailable") and "iPhone" in device["name"]:
            candidates.append((runtime, device["udid"]))

if not candidates:
    sys.exit("No available iPhone simulator found")

candidates.sort(reverse=True)
print(candidates[0][1])
