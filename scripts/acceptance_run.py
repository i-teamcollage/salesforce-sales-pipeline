"""Measure the four acceptance criteria and write reports/acceptance.json and reports/acceptance.md.

    python scripts/acceptance_run.py                  measure and write the reports
    python scripts/acceptance_run.py readme           refresh the README results block from the report
    python scripts/acceptance_run.py readme --check   exit 1 if the README block is out of date

Inputs:
  reports/org-test-run.json  the Apex run stored from a real org (`make org-test`). Without it, the criteria
                             that need the org are reported as not measured; nothing is guessed.
  tests/                     the static conformance tests, run here with pytest
  google-sheets/             the Node tests of the export, run here with node --test

Exit code 1 when a measured criterion fails. A criterion that cannot be measured yet (no org run stored)
shows as "n/a" and FAIL in the report and the README, but does not fail the command, so CI stays useful.
"""

from __future__ import annotations

import json
import math
import os
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import traceability  # noqa: E402
from acceptance import (  # noqa: E402
    Measure,
    evaluate,
    load_criteria,
    rate,
    report_dict,
    results_block,
    terminal_table,
    update_readme,
    write_reports,
)
from sfmeta import FORCE_APP, ROOT  # noqa: E402

REPORTS = ROOT / "reports"
ORG_RUN = REPORTS / "org-test-run.json"
README = ROOT / "README.md"
NOT_MEASURED = Measure(value=math.nan)


def junit(path: Path, qualify: bool = True) -> dict[str, bool]:
    """Test name -> passed, from a JUnit XML file (pytest and node both write one)."""
    results = {}
    for case in ET.parse(path).getroot().iter("testcase"):
        name = case.get("name", "")
        if qualify and case.get("classname"):
            name = f"{case.get('classname')}.{name}"
        failed = any(child.tag in ("failure", "error", "skipped") for child in case)
        results[name] = not failed
    return results


def run_static_checks() -> dict[str, bool]:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "pytest.xml"
        subprocess.run([sys.executable, "-m", "pytest", "-q", "-p", "no:cacheprovider", f"--junitxml={out}"],
                       cwd=ROOT, capture_output=True, check=False)
        return junit(out) if out.exists() else {}


def run_node_tests() -> dict[str, bool]:
    node = os.environ.get("NODE", "node")
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "node.xml"
        subprocess.run([node, "--test", "--test-reporter=junit", f"--test-reporter-destination={out}",
                        "google-sheets/transform.test.js"], cwd=ROOT, capture_output=True, check=False)
        return junit(out, qualify=False) if out.exists() else {}


def project_apex() -> set[str]:
    """Apex classes and triggers of this project that count for coverage (not the test classes)."""
    names = set()
    classes = FORCE_APP.joinpath("classes").glob("*.cls")
    triggers = FORCE_APP.joinpath("triggers").glob("*.trigger")
    for path in [*classes, *triggers]:
        if "@isTest" not in path.read_text(encoding="utf-8"):
            names.add(path.stem)
    return names


def org_measures(org_run: dict, project: set[str]) -> tuple[dict[str, Measure], dict[str, bool]]:
    """Apex results by "Class.method", plus the two org criteria, from a stored org run."""
    apex = {f"{t['class']}.{t['method']}": t["outcome"] == "Pass" for t in org_run["tests"]}
    counted = [row for row in org_run["coverage"] if row["name"] in project]
    measures = {
        "org_tests_passing": rate(sum(apex.values()), len(apex)),
        "apex_coverage": rate(sum(r["covered"] for r in counted), sum(r["lines"] for r in counted)),
    }
    return measures, apex


def requirement_rows(requirements, apex: dict[str, bool], node: dict[str, bool]) -> list[dict]:
    """One row per requirement: it passes when every test named after it ran and passed."""
    rows = []
    for requirement in requirements:
        results = [apex.get(t) for t in requirement.apex_tests] + [node.get(t) for t in requirement.node_tests]
        if results and all(result is True for result in results):
            status = "pass"
        elif any(result is False for result in results):
            status = "fail"
        else:
            status = "waiting for the org run"
        rows.append({"id": requirement.id, "text": requirement.text, "tests": len(results), "status": status})
    return rows


def measure(org_run: dict | None) -> tuple[dict[str, Measure], list[dict], dict]:
    requirements = traceability.collect()
    static = run_static_checks()
    node = run_node_tests()
    measures = {"static_checks": rate(sum(static.values()), len(static))}
    apex: dict[str, bool] = {}
    if org_run:
        org, apex = org_measures(org_run, project_apex())
        measures.update(org)
    else:
        measures.update(org_tests_passing=NOT_MEASURED, apex_coverage=NOT_MEASURED)
    rows = requirement_rows(requirements, apex, node)
    passed = sum(1 for row in rows if row["status"] == "pass")
    measures["requirements_covered"] = rate(passed, len(rows)) if org_run else NOT_MEASURED
    counts = {
        "requirements": len(rows),
        "apex_test_methods": sum(len(r.apex_tests) for r in requirements),
        "node_tests": len(node),
        "static_tests": len(static),
    }
    return measures, rows, counts


def details(rows: list[dict], org_run: dict | None, counts: dict) -> str:
    lines = ["## Requirements", "", "| Id | Requirement | Tests | Result |", "|---|---|---|---|"]
    lines += [f"| {r['id']} | {r['text']} | {r['tests']} | {r['status']} |" for r in rows]
    lines += ["", "## Where the numbers come from", ""]
    if org_run:
        lines.append(f"- Apex: {org_run['tests_ran']} test methods run in a Salesforce org on "
                     f"{org_run['recorded_at']}, stored in [org-test-run.json](org-test-run.json).")
    else:
        lines.append("- Apex: no run stored yet. The org criteria are not measured until `make org-test` runs the "
                     f"{counts['apex_test_methods']} Apex test methods in a Salesforce org that allows Apex.")
    lines.append(f"- Static checks: {counts['static_tests']} pytest checks on the metadata XML, run by this script.")
    lines.append(f"- Node: {counts['node_tests']} tests of the Google Sheets export, run by this script.")
    return "\n".join(lines)


def cmd_measure() -> int:
    org_run = json.loads(ORG_RUN.read_text(encoding="utf-8")) if ORG_RUN.exists() else None
    measures, rows, counts = measure(org_run)
    outcomes = evaluate(load_criteria(ROOT / "acceptance.toml"), measures)
    meta = {
        "title": "Salesforce sales pipeline: acceptance test",
        "items": counts["apex_test_methods"] + counts["node_tests"],
        "recorded_at": org_run["recorded_at"] if org_run else None,
        "org_run": "stored" if org_run else "pending",
        **counts,
    }
    report = report_dict(outcomes, meta)
    write_reports(report, REPORTS, details(rows, org_run, counts))
    print(terminal_table(outcomes))
    unmeasured = [o.criterion.id for o in outcomes if math.isnan(o.measure.value)]
    failed = [o.criterion.id for o in outcomes if not o.passed and o.criterion.id not in unmeasured]
    if unmeasured:
        print(f"\nNot measured yet (no Apex run stored): {', '.join(unmeasured)}")
    print(f"{'FAILED' if failed else 'OK'}: details in reports/acceptance.md")
    return 1 if failed else 0


def cmd_readme(check: bool) -> int:
    report = json.loads((REPORTS / "acceptance.json").read_text(encoding="utf-8"))
    changed = update_readme(README, results_block(report), check=check)
    if check:
        print("README results are out of date: run `make readme`" if changed else "README results are up to date")
        return 1 if changed else 0
    print("README results updated" if changed else "README results already up to date")
    return 0


def main(argv: list[str]) -> int:
    if argv[:1] == ["readme"]:
        return cmd_readme(check="--check" in argv)
    return cmd_measure()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
