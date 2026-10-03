#!/usr/bin/env python3
"""Generate demo fixtures for the Krakow Old Town walk.

Writes:
  fixtures/demo-route-krakow.gpx    walking route (~1.6 km), one point every ~8 m
  fixtures/demo-route-krakow.json   the same route as [{lat, lon, t}] (t = seconds from start, 1.3 m/s)
  fixtures/pois-krakow.json         real POIs near the route from Polish Wikipedia, in the Poi contract (docs/CONTRACTS.md)

Data source: the MediaWiki GeoSearch API of pl.wikipedia.org. We do NOT use the Wikidata SPARQL
endpoint here: during the hackathon it was rate-limited to 1 request/minute because of an outage.

Usage: python3 tools/gen_fixtures.py   (needs internet)
"""
import json
import math
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "fixtures"
UA = "SpacerZHistoria-hackathon/0.1 (HackYeah 2026; fixture generator)"
API = "https://pl.wikipedia.org/w/api.php"
WALK_SPEED_MPS = 1.3
STEP_M = 8.0
RADIUS_M = 120
# coordinate types that describe areas, not places you can stand next to
AREA_TYPES = {"city", "adm1st", "adm2nd", "adm3rd", "country", "region", "isle", "waterbody"}
MAX_DIM_M = 5000

# Barbakan -> Brama Florianska -> ul. Florianska -> Rynek -> ul. Grodzka -> Wawel
WAYPOINTS = [
    (50.06553, 19.94170),
    (50.06490, 19.94145),
    (50.06340, 19.93990),
    (50.06190, 19.93920),
    (50.06155, 19.93730),
    (50.06000, 19.93780),
    (50.05790, 19.93820),
    (50.05650, 19.93870),
    (50.05470, 19.93560),
]


def haversine_m(a, b):
    r = 6371000.0
    p1, p2 = math.radians(a[0]), math.radians(b[0])
    dp, dl = p2 - p1, math.radians(b[1] - a[1])
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


def densify(points):
    out, times, t = [points[0]], [0.0], 0.0
    for a, b in zip(points, points[1:]):
        d = haversine_m(a, b)
        n = max(1, int(d // STEP_M))
        for i in range(1, n + 1):
            f = i / n
            out.append((a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f))
            t += d / n / WALK_SPEED_MPS
            times.append(t)
    return out, times


def geosearch(lat, lon):
    params = {
        "action": "query", "format": "json", "formatversion": "2",
        "generator": "geosearch", "ggscoord": f"{lat}|{lon}", "ggsradius": RADIUS_M, "ggslimit": 20,
        "prop": "coordinates|pageprops|extracts|pageimages|info",
        "coprop": "type|dim", "ppprop": "wikibase_item",
        "exintro": 1, "explaintext": 1, "exlimit": 20,
        "piprop": "thumbnail", "pithumbsize": 640, "inprop": "url",
    }
    req = urllib.request.Request(API + "?" + urllib.parse.urlencode(params), headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp).get("query", {}).get("pages", [])


def to_poi(page):
    coord = (page.get("coordinates") or [{}])[0]
    if "lat" not in coord:
        return None
    dim = str(coord.get("dim") or "0")   # the API returns dim as an int or a string like "1000"
    if coord.get("type") in AREA_TYPES or (dim.isdigit() and int(dim) >= MAX_DIM_M):
        return None
    extract = (page.get("extract") or "").strip()
    if not extract:
        return None
    return {
        "id": f"plwiki:{page['pageid']}",
        "name": page["title"],
        "summary": extract,
        "lat": round(coord["lat"], 6),
        "lon": round(coord["lon"], 6),
        "kind": coord.get("type"),
        "wikidataId": page.get("pageprops", {}).get("wikibase_item"),
        "imageUrl": page.get("thumbnail", {}).get("source"),
        "sourceUrl": page.get("fullurl"),
        "summaryChars": len(extract),
    }


def main():
    OUT.mkdir(exist_ok=True)
    route, times = densify(WAYPOINTS)

    gpx = ['<?xml version="1.0" encoding="UTF-8"?>',
           '<gpx version="1.1" creator="SpacerZHistoria" xmlns="http://www.topografix.com/GPX/1/1">',
           "<trk><name>Krakow: Barbakan - Wawel</name><trkseg>"]
    gpx += [f'<trkpt lat="{lat:.6f}" lon="{lon:.6f}"></trkpt>' for lat, lon in route]
    gpx += ["</trkseg></trk></gpx>", ""]
    (OUT / "demo-route-krakow.gpx").write_text("\n".join(gpx), encoding="utf-8")
    (OUT / "demo-route-krakow.json").write_text(json.dumps(
        [{"lat": round(lat, 6), "lon": round(lon, 6), "t": round(t, 1)} for (lat, lon), t in zip(route, times)],
        indent=1), encoding="utf-8")

    pois = {}
    for lat, lon in WAYPOINTS:
        for page in geosearch(lat, lon):
            poi = to_poi(page)
            if poi:
                pois[poi["id"]] = poi
        time.sleep(0.5)

    ranked = sorted(pois.values(), key=lambda p: -p["summaryChars"])
    for p in ranked:
        del p["summaryChars"]
    (OUT / "pois-krakow.json").write_text(json.dumps(
        {"source": "plwiki-geosearch", "license": "CC BY-SA 4.0 (Wikipedia text)",
         "generatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "pois": ranked},
        ensure_ascii=False, indent=1), encoding="utf-8")
    route_len = sum(haversine_m(a, b) for a, b in zip(route, route[1:]))
    print(f"route: {len(route)} points, {route_len:.0f} m, {times[-1] / 60:.1f} min walk")
    print(f"pois: {len(ranked)} (kinds: {sorted({str(p['kind']) for p in ranked})})")
    for p in ranked[:12]:
        print(f"  {p['name']}")


if __name__ == "__main__":
    main()
