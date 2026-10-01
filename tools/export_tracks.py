#!/usr/bin/env python3
"""Export the route checkpoint XY data used by SPZ's poll track preview."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "spz-races" / "data" / "tracks.lua"
OUTPUT = Path(__file__).resolve().parents[1] / "public" / "tracks.json"
GEOJSON_OUTPUT = Path(__file__).resolve().parents[1] / "public" / "tracks.geojson"
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

def game_to_map(x, y):
    if y < -1000:
        lon = -3.03663255576895e-9*x*x + 0.0200175350440883*x - 97.211789757094
        lat = 6.23122700084464e-14*y**4 + 4.20129073856139e-10*y**3 + 2.33168021020044e-6*y*y + 0.0240131069198339*y + 14.1346597090657
    elif y < 2000:
        lon = 2.04927570146569e-8*x*x + 0.0199382651698616*x - 97.2328189248356
        lat = -5.48114969721267e-14*y**4 - 1.7644651413213e-10*y**3 - 6.69398961485353e-7*y*y + 0.019446455419011*y + 11.948776738614
    elif y < 5000:
        lon = 1.14491978248603e-8*x*x + 0.0199665146367798*x - 97.2865999889282
        lat = -7.50970630545523e-15*y**4 + 2.42587620752238e-10*y**3 - 3.39800162545523e-6*y*y + 0.02514652658967*y + 7.49474095495398
    else:
        lon = -4.51344244634536e-8*x*x + 0.0200135106227036*x - 97.1355799536373
        lat = -2.33545837309061e-14*y**4 + 6.7194107532233e-10*y**3 - 7.73181068541832e-6*y*y + 0.0443322941450463*y - 23.9182574396233
    return [lon, lat]

features = []
for track in tracks:
    coords = [game_to_map(x, y) for x, y in track["points"]]
    if track["type"] == "circuit" and coords and coords[-1] != coords[0]:
        coords.append(coords[0])
    features.append({
        "type": "Feature",
        "geometry": {"type": "LineString", "coordinates": coords},
        "properties": {
            "name": track["name"],
            "type": track["type"],
            "stroke": "#ff712e" if track["type"] == "circuit" else "#4dd4ff",
            "stroke-width": 2,
            "stroke-opacity": 0.82,
        },
    })
GEOJSON_OUTPUT.write_text(json.dumps({"type": "FeatureCollection", "features": features}, separators=(",", ":")), encoding="utf-8")
print(f"Exported {len(tracks)} route tracks to tracks.json and tracks.geojson")
