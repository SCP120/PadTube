#!/usr/bin/env python3
"""AC/BR/EF IDs in docs/use_cases vs the IDs that tests cite (host results + device test headers).
usage: coverage.py [results.jsonl]   Prints covered / not covered; exit 0 (report only)."""
import json, pathlib, re, sys
root = pathlib.Path(__file__).resolve().parent.parent
ids = set()
for p in (root / "docs/use_cases").rglob("*.md"):
    ids |= set(re.findall(r"\*\*((?:AC|BR|EF)-[A-Z0-9]+(?:-[A-Z0-9]+)*)\*\*", p.read_text()))
cited = {}
res = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else root / "build/host/results.jsonl"
if res.exists():
    for line in res.read_text().splitlines():
        r = json.loads(line)
        for i in r.get("ids", "").split():
            cited.setdefault(i, []).append(f"{r['suite']}:{r['name']}")
for p in (root / "tests/device").glob("*.py"):
    m = re.search(r"^# IDs: (.+)$", p.read_text(), re.M)
    for i in (m.group(1).split() if m else []):
        cited.setdefault(i, []).append("device:" + p.stem)
cov = sorted(i for i in ids if i in cited)
miss = sorted(i for i in ids if i not in cited)
print(f"{len(cov)} of {len(ids)} use-case IDs have a test")
for i in miss:
    print("  no test:", i)
