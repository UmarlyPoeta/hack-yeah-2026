"""Smoke test + measurement for the Bielik endpoint on Modal (issue #6).

Checks that the Ollama API answers, that Bielik keeps the segment JSON Schema, and measures
generation time of ~100 Polish words (cold and warm). Uses only the standard library.

Usage:
  set BIELIK_URL=https://<workspace>--bielik-ollama-serve.modal.run
  set MODAL_KEY=wk-...      (proxy auth token, see README.md)
  set MODAL_SECRET=ws-...
  python server/modal/smoke_test.py [--runs 3] [--poi plwiki:1039593]
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODEL = os.environ.get("LLM_MODEL", "bielik-4.5b-v3.0-instruct:Q8_0")

# The shape #18 asks Bielik for: {title?, text, claims[{text, quote}]}
SEGMENT_SCHEMA = {
    "type": "object",
    "properties": {
        "title": {"type": "string"},
        "text": {"type": "string"},
        "claims": {
            "type": "array",
            "maxItems": 3,
            "items": {
                "type": "object",
                "properties": {"text": {"type": "string"}, "quote": {"type": "string"}},
                "required": ["text", "quote"],
            },
        },
    },
    "required": ["text", "claims"],
}

SYSTEM = (
    "Jesteś przewodnikiem miejskim, który idzie razem ze słuchaczem po Krakowie. "
    "Mówisz po polsku, krótkimi zdaniami, ciepło i konkretnie. "
    "Używasz WYŁĄCZNIE faktów z podanego źródła, ale opowiadasz własnymi słowami: nie przepisuj źródła. "
    "Wybierz 2-3 najciekawsze fakty. Dla każdego dodaj w polu claims krótki (do 12 słów) "
    "dosłowny cytat ze źródła (quote). Nie podawaj liczb ani dat, których nie ma w źródle. "
    "Odpowiadasz wyłącznie JSON-em zgodnym ze schematem."
)


def request(base, path, body=None, timeout=300):
    headers = {"Content-Type": "application/json"}
    if os.environ.get("MODAL_KEY"):
        headers["Modal-Key"] = os.environ["MODAL_KEY"]
        headers["Modal-Secret"] = os.environ.get("MODAL_SECRET", "")
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(base.rstrip("/") + path, data=data, headers=headers)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode())


def norm(s):
    s = re.sub(r"[„”“\"«»]", '"', s)
    return re.sub(r"\s+", " ", s).strip().lower()


def check_grounding(result, source):
    """Same rules as the #18 validator: quotes verbatim in source, numbers in text present in source."""
    src = norm(source)
    bad_quotes = [c["quote"] for c in result.get("claims", []) if norm(c["quote"]) not in src]
    bad_numbers = [n for n in re.findall(r"\d+", result.get("text", "")) if n not in source]
    return bad_quotes, bad_numbers


def arrival(base, poi, max_words):
    prompt = (
        f"Typ segmentu: ARRIVAL. Właśnie dotarliśmy do miejsca: {poi['name']}.\n"
        f"Opowiedz o nim w około {max_words} słowach.\n\nŹRÓDŁO:\n{poi['summary']}"
    )
    body = {
        "model": MODEL,
        "messages": [{"role": "system", "content": SYSTEM}, {"role": "user", "content": prompt}],
        "format": SEGMENT_SCHEMA,
        "stream": False,
        "keep_alive": "30m",
        # Polish is ~2.5 tokens/word; claims add ~150 tokens
        "options": {"temperature": 0.2, "num_predict": int(max_words * 3 + 250)},
    }
    t0 = time.time()
    resp = request(base, "/api/chat", body)
    return resp, time.time() - t0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--poi", default="plwiki:1039593")
    ap.add_argument("--words", type=int, default=100)
    args = ap.parse_args()

    base = os.environ.get("BIELIK_URL") or os.environ.get("OLLAMA_URL")
    if not base:
        sys.exit("Set BIELIK_URL (the URL printed by `modal deploy`).")
    pois = json.loads((ROOT / "fixtures" / "pois-krakow.json").read_text(encoding="utf-8"))["pois"]
    poi = next(p for p in pois if p["id"] == args.poi)

    t0 = time.time()
    version = request(base, "/api/version")
    print(f"/api/version {version} in {time.time() - t0:.1f}s (includes container cold start if it was idle)")
    tags = [m["name"] for m in request(base, "/api/tags")["models"]]
    print(f"models: {tags}")
    if MODEL not in tags:
        sys.exit(f"FAIL: {MODEL} not on the server")

    failures = 0
    for i in range(args.runs):
        resp, wall = arrival(base, poi, args.words)
        content = resp["message"]["content"]
        gen_s = resp.get("eval_duration", 0) / 1e9
        load_s = resp.get("load_duration", 0) / 1e9
        tokens = resp.get("eval_count", 0)
        try:
            result = json.loads(content)
            schema_ok = isinstance(result.get("text"), str) and isinstance(result.get("claims"), list)
        except json.JSONDecodeError:
            result, schema_ok = {}, False
        words = len(result.get("text", "").split())
        bad_quotes, bad_numbers = check_grounding(result, poi["summary"]) if schema_ok else ([], [])
        label = "cold" if i == 0 else "warm"
        print(
            f"\n[{label} #{i + 1}] wall {wall:.1f}s | load {load_s:.1f}s | gen {gen_s:.1f}s "
            f"({tokens} tok, {tokens / gen_s if gen_s else 0:.0f} tok/s) | {words} words | "
            f"schema {'OK' if schema_ok else 'FAIL'} | claims {len(result.get('claims', []))} | "
            f"quotes outside source {len(bad_quotes)} | numbers outside source {bad_numbers}"
        )
        print("  " + result.get("text", content)[:600])
        if not schema_ok:
            print(f"  done_reason={resp.get('done_reason')} (length = cut off by num_predict)")
        failures += not schema_ok
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
