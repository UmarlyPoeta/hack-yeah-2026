#!/usr/bin/env python3
"""Generate demo fixtures for the Krakow Old Town walk.

Writes:
  fixtures/demo-route-krakow.gpx    walking route (~1.6 km), one point every ~8 m
  fixtures/demo-route-krakow.json   the same route as [{lat, lon, t}] (t = seconds from start, 1.3 m/s)
  fixtures/pois-krakow.json         real POIs near the route from Polish Wikipedia, in the Poi contract (docs/CONTRACTS.md),
                                    with importance / role / partOfId (#40); also copied to the app's rawfile

Data source: the MediaWiki GeoSearch and langlinks APIs of pl.wikipedia.org, Wikidata wbgetentities
(P31 instance of, P361 part of). Rules: server/src/pois/poi-rules.json. We do NOT use the Wikidata SPARQL
endpoint here: during the hackathon it was rate-limited to 1 request/minute because of an outage.

Usage: python3 tools/gen_fixtures.py   (needs internet)
"""
import json
import math
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "fixtures"
UA = "SpacerZHistoria-hackathon/0.1 (HackYeah 2026; fixture generator)"
API = "https://pl.wikipedia.org/w/api.php"
WIKIDATA_API = "https://www.wikidata.org/w/api.php"
# shared with the server, so fixtures and /v1/pois classify places the same way (#40)
RULES = json.loads((ROOT / "server" / "src" / "pois" / "poi-rules.json").read_text(encoding="utf-8"))
APP_RAWFILE = ROOT / "Projekt" / "entry" / "src" / "main" / "resources" / "rawfile"
WALK_SPEED_MPS = 1.3
STEP_M = 8.0
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


def api_get(url, params, tries=8):
    """GET with retries: Wikipedia answers 'cirrussearch-too-busy-error' or 429/503 under load."""
    for attempt in range(tries):
        try:
            req = urllib.request.Request(url + "?" + urllib.parse.urlencode(params), headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = json.load(resp)
            if "error" not in data:
                return data
            err = data["error"].get("code")
        except urllib.error.HTTPError as e:
            err = f"http {e.code}"
        if attempt == tries - 1:
            raise RuntimeError(err)
        time.sleep(min(60, 5 * 2 ** attempt))


def chunks(items, size=50):
    for i in range(0, len(items), size):
        yield items[i:i + size]


DETAIL_PROPS = {
    "prop": "coordinates|pageprops|extracts|pageimages|info",
    "coprop": "type|dim", "colimit": "max", "ppprop": "wikibase_item",
    "exintro": 1, "explaintext": 1, "exlimit": "max",
    "piprop": "thumbnail", "pithumbsize": 640, "pilimit": "max", "inprop": "url",
}


def details(selector):
    """Pages with coordinates, Wikidata id, intro and image; extracts come 20 at a time, so follow continue."""
    pages, cont = {}, {}
    for _ in range(6):
        data = api_get(API, {"action": "query", "format": "json", "formatversion": "2", **selector, **DETAIL_PROPS, **cont})
        for p in data.get("query", {}).get("pages", []):
            pages[p["pageid"]] = {**pages.get(p["pageid"], {}), **p}
        if "continue" not in data:
            break
        cont = data["continue"]
    return list(pages.values())


def geosearch_near(lat, lon):
    return details({"generator": "geosearch", "ggscoord": f"{lat}|{lon}",
                    "ggsradius": RULES["nearRadiusM"], "ggslimit": RULES["nearLimit"]})


def geosearch_ids(lat, lon):
    data = api_get(API, {"action": "query", "format": "json", "formatversion": "2", "list": "geosearch",
                         "gscoord": f"{lat}|{lon}", "gsradius": RULES["farRadiusM"], "gslimit": RULES["farLimit"]})
    return [g["pageid"] for g in data.get("query", {}).get("geosearch", [])]


def langlink_counts(pageids):
    counts = {}
    for batch in chunks(pageids):
        cont = {}
        for _ in range(40):
            data = api_get(API, {"action": "query", "format": "json", "formatversion": "2", "prop": "langlinks",
                                 "lllimit": "max", "pageids": "|".join(map(str, batch)), **cont})
            for p in data.get("query", {}).get("pages", []):
                counts[p["pageid"]] = counts.get(p["pageid"], 0) + len(p.get("langlinks", []))
            if "continue" not in data:
                break
            cont = data["continue"]
    return counts


def wikidata_claims(qids):
    out = {}
    for batch in chunks(sorted(set(qids))):
        data = api_get(WIKIDATA_API, {"action": "wbgetentities", "format": "json", "props": "claims", "ids": "|".join(batch)})
        for qid, e in data.get("entities", {}).items():
            claims = e.get("claims", {})
            target = lambda prop: [s["mainsnak"].get("datavalue", {}).get("value", {}).get("id")
                                   for s in claims.get(prop, []) if s["mainsnak"].get("datavalue")]
            out[qid] = {"p31": target("P31"), "p361": target("P361")}
    return out


# --- signals (#40): same rules and formulas as server/src/pois/signals.js -----------------------------

def importance_from_langlinks(n):
    return round(min(1.0, math.log(1 + max(0, n)) / math.log(1 + RULES["importanceLanglinksCap"])), 3)


def importance_from_summary(summary):
    return round(min(1.0, len(summary or "") / RULES["importanceSummaryFallbackChars"]), 3)


def classify_by_classes(p31):
    excluded = len(p31) > 0 and all(c in RULES["excludedClasses"] for c in p31)
    return ("area" if any(c in RULES["areaClasses"] for c in p31) else "sight"), excluded


def classify_by_name(name):
    role = "area" if any(name.startswith(p) for p in RULES["areaNamePrefixes"]) else "sight"
    return role, any(name.startswith(p) for p in RULES["excludedNamePrefixes"])


def apply_signals(pois, langlinks, claims):
    id_by_qid = {p["wikidataId"]: p["id"] for p in pois if p["wikidataId"]}
    out = []
    for p in pois:
        pageid = int(p["id"].split(":")[1])
        importance = (importance_from_langlinks(langlinks.get(pageid, 0)) if langlinks is not None
                      else importance_from_summary(p["summary"]))
        c = claims.get(p["wikidataId"]) if claims is not None and p["wikidataId"] else None
        role, excluded = classify_by_classes(c["p31"]) if c else classify_by_name(p["name"])
        if excluded:
            continue
        part_of = None
        if c:
            part_of = next((id_by_qid[q] for q in c["p361"] if q in id_by_qid and id_by_qid[q] != p["id"]), None)
        out.append({**p, "importance": importance, "role": role, "partOfId": part_of})
    ids = {p["id"] for p in out}
    for p in out:
        if p["partOfId"] and p["partOfId"] not in ids:
            p["partOfId"] = None
    return out


def to_poi(page):
    coords = page.get("coordinates") or []
    coord = next((c for c in coords if c.get("primary")), coords[0] if coords else {})
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

    # two searches per waypoint (#40): nearest places + important places in a wide radius
    pois, far_ids = {}, set()
    for lat, lon in WAYPOINTS:
        for page in geosearch_near(lat, lon):
            poi = to_poi(page)
            if poi:
                pois[poi["id"]] = poi
        far_ids.update(geosearch_ids(lat, lon))
        time.sleep(0.3)
    near_ids = {int(i.split(":")[1]) for i in pois}
    far_ids -= near_ids
    counts = langlink_counts(sorted(near_ids | far_ids))
    important = [i for i in sorted(far_ids) if importance_from_langlinks(counts.get(i, 0)) >= RULES["farMinImportance"]]
    for batch in chunks(important):
        for page in details({"pageids": "|".join(map(str, batch))}):
            poi = to_poi(page)
            if poi:
                pois[poi["id"]] = poi
    claims = wikidata_claims([p["wikidataId"] for p in pois.values() if p["wikidataId"]])
    ranked = sorted(apply_signals(list(pois.values()), counts, claims), key=lambda p: (-p["importance"], p["name"]))

    (OUT / "pois-krakow.json").write_text(json.dumps(
        {"source": "plwiki-geosearch", "license": "CC BY-SA 4.0 (Wikipedia text)",
         "generatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "pois": ranked},
        ensure_ascii=False, indent=1), encoding="utf-8")
    (APP_RAWFILE / "pois-krakow.json").write_text((OUT / "pois-krakow.json").read_text(encoding="utf-8"), encoding="utf-8")
    route_len = sum(haversine_m(a, b) for a, b in zip(route, route[1:]))
    print(f"route: {len(route)} points, {route_len:.0f} m, {times[-1] / 60:.1f} min walk")
    print(f"pois: {len(ranked)}, areas: {sum(p['role'] == 'area' for p in ranked)}, "
          f"with partOfId: {sum(p['partOfId'] is not None for p in ranked)}")
    for p in ranked[:12]:
        print(f"  {p['importance']:.2f} {p['role']:5} {p['name']}")
    for must in ("Zamek Królewski na Wawelu", "Bazylika Archikatedralna"):
        print(f"  {'OK ' if any(p['name'].startswith(must) for p in ranked) else 'MISSING'} {must}")


if __name__ == "__main__":
    main()
