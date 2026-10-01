#!/usr/bin/env python3
"""Export the route checkpoint XY data used by SPZ's poll track preview."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "spz-races" / "data" / "tracks.lua"
OUTPUT = Path(__file__).resolve().parents[1] / "public" / "tracks.json"
TEXT = SOURCE.read_text(encoding="utf-8")
track_pattern = re.compile(r'^  \["([^"]+)"\] = \{(.*?)(?=^  \["|^\})', re.M | re.S)
tracks = []
for match in track_pattern.finditer(TEXT):
    key, block = match.groups()
    name = re.search(r'name\s*=\s*"([^"]+)"', block)
    kind = re.search(r'type\s*=\s*"([^"]+)"', block)
    laps = re.search(r'laps\s*=\s*(\d+)', block)
    points = [[float(x), float(y)] for x, y in re.findall(
        r'coords\s*=\s*vector3\(\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)', block)]
    if points:
        tracks.append({"id": key, "name": name.group(1) if name else key,
                       "type": kind.group(1) if kind else "unknown",
                       "laps": int(laps.group(1)) if laps else 1,
                       "points": points})
OUTPUT.write_text(json.dumps({"source": "SPZ.Tracks", "tracks": tracks}, separators=(",", ":")), encoding="utf-8")
print(f"Exported {len(tracks)} track routes to {OUTPUT}")
