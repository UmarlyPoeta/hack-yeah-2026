#!/usr/bin/env python3
"""Create labels, milestones and issues on GitHub from tools/issues.md using the gh CLI.

  python3 tools/create_issues.py            # dry run: parses and prints the plan, touches nothing
  python3 tools/create_issues.py --apply    # creates everything in the current gh repo

Idempotent: existing labels are updated, existing milestones and issues (same title) are reused.
Issue bodies may reference other issues as {{ID}}; they are resolved to #numbers in a second pass,
so forward references work.
"""
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

BACKLOG = Path(__file__).resolve().parent / "issues.md"

MILESTONES = {
    # due dates in UTC (CEST = UTC+2); M3 has no fixed date until the official deadline is confirmed
    "M0 Fundament": ("2026-10-03T16:00:00Z", "Projekt startuje na emulatorze, spike'i rozstrzygnięte, serwer i Ollama odpowiadają"),
    "M1 Draft E2E": ("2026-10-03T18:00:00Z", "Koncepcja zamrożona: LocationButton -> pozycja -> POI -> ARRIVAL z szablonu"),
    "M2 Feature complete": ("2026-10-04T02:00:00Z", "AI + głos, deep dive, wszystkie ekrany, testy i checklista E2E"),
    "M3 Zgłoszenie": (None, "Podpisany .hap, demo, README, AI_WORKFLOW.md, architektura"),
}

LABELS = {
    "owner:P1": ("1f6feb", "Platforma i integracja"),
    "owner:P2": ("8250df", "Silnik przewodnika"),
    "owner:P3": ("1a7f37", "Dane i serwer bazowy"),
    "owner:P4": ("bf3989", "AI i głos"),
    "owner:P5": ("d4a72c", "UI/UX, odtwarzacz i demo"),
    "area:app": ("c5def5", "Aplikacja ArkTS"),
    "area:server": ("bfdadc", "server/ (Node)"),
    "area:ai": ("f9d0c4", "LLM / TTS"),
    "area:docs": ("e4e669", "Dokumentacja"),
    "type:spike": ("fbca04", "Timeboxowane rozpoznanie, wynik w komentarzu"),
    "type:feature": ("0e8a16", "Funkcja"),
    "type:test": ("5319e7", "Testy / QA"),
    "type:docs": ("0075ca", "Dokumentacja"),
    "prio:P0": ("b60205", "Must, często blokuje innych"),
    "prio:P1": ("d93f0b", "Must"),
    "prio:P2": ("cccccc", "Stretch: tylko gdy P0/P1 gotowe"),
}

SECTION_RE = re.compile(r"^## \[([A-Z0-9-]+)\] (.+)$")
REF_RE = re.compile(r"\{\{([A-Z0-9-]+)\}\}")


def parse(text):
    issues, cur = [], None
    for line in text.splitlines():
        m = SECTION_RE.match(line)
        if m:
            cur = {"id": m.group(1), "title": m.group(2).strip(), "labels": [], "milestone": None, "depends": [], "body": []}
            issues.append(cur)
            continue
        if cur is None:
            continue
        meta = re.match(r"^(labels|milestone|depends):\s*(.*)$", line)
        if meta and not cur["body"]:
            key, val = meta.groups()
            if key == "milestone":
                cur["milestone"] = val.strip() or None
            else:
                cur[key] = [v.strip() for v in val.split(",") if v.strip()]
            continue
        cur["body"].append(line)
    for i in issues:
        i["body"] = "\n".join(i["body"]).strip()
    return issues


def validate(issues):
    ids = {i["id"] for i in issues}
    errors = []
    for i in issues:
        for d in i["depends"] + REF_RE.findall(i["body"]):
            if d not in ids:
                errors.append(f"{i['id']}: unknown reference {d}")
        for lab in i["labels"]:
            if lab not in LABELS:
                errors.append(f"{i['id']}: unknown label {lab}")
        if i["milestone"] not in MILESTONES:
            errors.append(f"{i['id']}: unknown milestone {i['milestone']}")
        owners = [lab for lab in i["labels"] if lab.startswith("owner:")]
        if len(owners) != 1:
            errors.append(f"{i['id']}: needs exactly one owner label")
    return errors


def render_body(issue, numbers):
    def ref(match):
        n = numbers.get(match.group(1))
        return f"#{n}" if n else match.group(0)

    body = REF_RE.sub(ref, issue["body"])
    owner = next(lab for lab in issue["labels"] if lab.startswith("owner:")).split(":")[1]
    deps = ", ".join(f"#{numbers[d]}" if d in numbers else d for d in issue["depends"]) or "brak"
    header = f"**Właściciel:** {owner} (opis roli: `docs/ROLES.md`) · **Zależy od:** {deps}\n\n"
    footer = "\n\n---\nKontrakty: `docs/CONTRACTS.md` · Architektura: `docs/ARCHITECTURE.md` · Testy: `docs/TESTING.md`"
    return header + body + footer


def gh(*args, capture=True):
    res = subprocess.run(["gh", *args], text=True, capture_output=capture, stdin=subprocess.DEVNULL)
    if res.returncode != 0:
        raise SystemExit(f"gh {' '.join(args)} failed:\n{res.stderr}")
    return res.stdout


def with_body_file(body, fn):
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False, encoding="utf-8") as f:
        f.write(body)
        path = f.name
    try:
        return fn(path)
    finally:
        Path(path).unlink(missing_ok=True)


def apply(issues):
    repo = json.loads(gh("repo", "view", "--json", "nameWithOwner"))["nameWithOwner"]
    print(f"repo: {repo}")

    for name, (color, desc) in LABELS.items():
        gh("label", "create", name, "--color", color, "--description", desc, "--force")
    print(f"labels: {len(LABELS)} ok")

    existing_ms = {m["title"]: m["number"] for m in json.loads(gh("api", f"repos/{repo}/milestones?state=all&per_page=100"))}
    for title, (due, desc) in MILESTONES.items():
        if title in existing_ms:
            continue
        args = ["api", f"repos/{repo}/milestones", "-f", f"title={title}", "-f", f"description={desc}"]
        if due:
            args += ["-f", f"due_on={due}"]
        gh(*args)
    print(f"milestones: {len(MILESTONES)} ok")

    existing = {i["title"]: i["number"] for i in json.loads(
        gh("issue", "list", "--state", "all", "--limit", "500", "--json", "number,title"))}
    numbers = {}
    for issue in issues:
        if issue["title"] in existing:
            numbers[issue["id"]] = existing[issue["title"]]
            print(f"  = #{numbers[issue['id']]} {issue['title']} (exists)")
            continue
        args = ["issue", "create", "--title", issue["title"], "--milestone", issue["milestone"]]
        for lab in issue["labels"]:
            args += ["--label", lab]
        url = with_body_file(render_body(issue, numbers), lambda p: gh(*args, "--body-file", p)).strip()
        numbers[issue["id"]] = int(url.rsplit("/", 1)[-1])
        print(f"  + #{numbers[issue['id']]} {issue['title']}")

    # second pass: resolve forward references now that every issue has a number
    for issue in issues:
        with_body_file(render_body(issue, numbers),
                       lambda p: gh("issue", "edit", str(numbers[issue["id"]]), "--body-file", p))
    print(f"issues: {len(issues)} ok, references resolved")


def main():
    issues = parse(BACKLOG.read_text(encoding="utf-8"))
    errors = validate(issues)
    if errors:
        raise SystemExit("backlog errors:\n  " + "\n  ".join(errors))

    by_ms = {}
    for i in issues:
        by_ms.setdefault(i["milestone"], []).append(i)
    for ms, items in by_ms.items():
        print(f"\n{ms} ({len(items)})")
        for i in items:
            owner = next(lab for lab in i["labels"] if lab.startswith("owner:"))
            prio = next((lab for lab in i["labels"] if lab.startswith("prio:")), "")
            deps = f"  <- {', '.join(i['depends'])}" if i["depends"] else ""
            print(f"  [{owner[6:]}] {prio[5:]:2} {i['id']:16} {i['title']}{deps}")
    print(f"\n{len(issues)} issues, {len(LABELS)} labels, {len(MILESTONES)} milestones")

    if "--apply" in sys.argv:
        apply(issues)
    else:
        print("dry run: nothing created. Run with --apply to create on GitHub.")


if __name__ == "__main__":
    main()
