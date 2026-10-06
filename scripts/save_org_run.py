"""Store an Apex test run from a real org as reports/org-test-run.json.

    python scripts/save_org_run.py RAW.json reports/org-test-run.json

RAW.json is the output of `sf apex run test --code-coverage --result-format json` (with or without --json).
Only what the report needs is kept: per-test outcomes and per-class line coverage. The org id, user name
and host are dropped, so the stored run contains nothing private.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path


def slim(raw: dict) -> dict:
    result = raw.get("result", raw)
    summary = result.get("summary", {})
    tests = [
        {
            "class": (test.get("ApexClass") or {}).get("Name") or test.get("FullName", ".").split(".")[0],
            "method": test.get("MethodName"),
            "outcome": test.get("Outcome"),
            "message": test.get("Message"),
            "run_time_ms": test.get("RunTime"),
        }
        for test in result.get("tests", [])
    ]
    coverage_block = result.get("coverage") or {}
    rows = coverage_block.get("coverage", []) if isinstance(coverage_block, dict) else coverage_block
    coverage = [
        {
            "name": row.get("name"),
            "lines": int(row.get("totalLines") or 0),
            "covered": int(row.get("totalCovered") or 0),
        }
        for row in rows
    ]
    started = str(summary.get("testStartTime") or "")
    return {
        "recorded_at": started[:10] or None,
        "outcome": summary.get("outcome"),
        "tests_ran": summary.get("testsRan", len(tests)),
        "passing": summary.get("passing"),
        "failing": summary.get("failing"),
        "skipped": summary.get("skipped"),
        "test_run_coverage": summary.get("testRunCoverage"),
        "org_wide_coverage": summary.get("orgWideCoverage"),
        "tests": sorted(tests, key=lambda t: (t["class"] or "", t["method"] or "")),
        "coverage": sorted(coverage, key=lambda c: c["name"] or ""),
    }


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    raw_path, out_path = Path(argv[0]), Path(argv[1])
    text = raw_path.read_text(encoding="utf-8")
    try:
        raw = json.loads(text[text.index("{"):])
    except ValueError:
        print(f"{raw_path} holds no test run: {text[:300]}", file=sys.stderr)
        return 1
    run = slim(raw)
    if not run["tests"]:
        print(f"{raw_path} has no test results; nothing stored", file=sys.stderr)
        return 1
    out_path.write_text(json.dumps(run, indent=2) + "\n", encoding="utf-8")
    print(f"{out_path}: {run['tests_ran']} tests, {run['passing']} passing, recorded {run['recorded_at']}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
