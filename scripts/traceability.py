"""Requirement -> metadata -> tests, built from docs/brief.md and the test sources.

    python scripts/traceability.py           rewrite docs/traceability.md
    python scripts/traceability.py --check   exit 1 if a requirement has no test, a mapped file is missing,
                                             a test names an unknown requirement, or the file is out of date
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sfmeta import CLASSES, ROOT, SHEETS  # noqa: E402

BRIEF = ROOT / "docs" / "brief.md"
OUTPUT = ROOT / "docs" / "traceability.md"
APP = "force-app/main/default/"
ID = r"(?:PL|TR|FL|A|RR|AC|EX|NF)\d+"

# Where each requirement is implemented. Paths are relative to the repository; globs are allowed.
METADATA = {
    "NF1": [APP + "classes/LeadConversionService.cls", APP + "classes/OpportunityTriggerHandler.cls"],
    "PL1": [APP + "objects/Opportunity/recordTypes/New_Clients.recordType-meta.xml",
            APP + "objects/Opportunity/businessProcesses/New_Clients_Process.businessProcess-meta.xml",
            APP + "standardValueSets/OpportunityStage.standardValueSet-meta.xml",
            APP + "objects/Opportunity/validationRules/Stage_Belongs_To_Pipeline.validationRule-meta.xml"],
    "PL2": [APP + "objects/Opportunity/recordTypes/Reactivation.recordType-meta.xml",
            APP + "objects/Opportunity/businessProcesses/Reactivation_Process.businessProcess-meta.xml"],
    "PL3": [APP + "objects/Opportunity/recordTypes/Repeat_Sales.recordType-meta.xml",
            APP + "objects/Opportunity/businessProcesses/Repeat_Sales_Process.businessProcess-meta.xml"],
    "TR1": [APP + "classes/PipelineTransitions.cls"],
    "TR2": [APP + "objects/Account/fields/Repeat_Segment__c.field-meta.xml"],
    "TR3": [APP + "objects/Opportunity/businessProcesses/New_Clients_Process.businessProcess-meta.xml",
            APP + "flows/A7_Refusal_To_Reactivation.flow-meta.xml"],
    "TR4": [APP + "classes/KeyCallService.cls"],
    "FL1": [APP + "objects/Opportunity/fields/*.field-meta.xml"],
    "FL2": [APP + "globalValueSets/*.globalValueSet-meta.xml",
            APP + "objects/Opportunity/recordTypes/*.recordType-meta.xml"],
    "FL3": [APP + "objects/Opportunity/fields/Lead_Author__c.field-meta.xml",
            APP + "objects/Opportunity/validationRules/Lead_Author_Set_Once.validationRule-meta.xml",
            APP + "classes/OpportunityTriggerHandler.cls"],
    "FL4": [APP + "objects/Opportunity/fields/Stage_Order__c.field-meta.xml",
            APP + "objects/Opportunity/validationRules/Gate_Stage_*.validationRule-meta.xml"],
    "FL5": [APP + "objects/Opportunity/fields/Warm_Up_Touches__c.field-meta.xml", APP + "classes/TaskCompletion.cls",
            APP + "triggers/TaskTrigger.trigger"],
    "FL6": [APP + "objects/Opportunity/fields/Start_Period__c.field-meta.xml"],
    "A1": [APP + "triggers/LeadTrigger.trigger", APP + "classes/LeadConversionService.cls",
           APP + "objects/Lead/fields/*.field-meta.xml", APP + "customMetadata/Source_Mapping.*.md-meta.xml",
           "web-to-lead/application-form.html"],
    "A2": [APP + "flows/A2_Reply_Task.flow-meta.xml", APP + "classes/TaskCompletion.cls"],
    "A3": [APP + "flows/A3_Grade_Routing.flow-meta.xml"],
    "A4": [APP + "classes/KeyCallService.cls",
           APP + "objects/Opportunity/validationRules/Key_Call_At_Least_3_Hours_Ahead.validationRule-meta.xml"],
    "A5": [APP + "classes/KeyCallService.cls", APP + "classes/Activities.cls"],
    "A6": [APP + "flows/A6_Objection_Task.flow-meta.xml", APP + "classes/KeyCallService.cls",
           APP + "objects/Activity/fields/Recording_URL__c.field-meta.xml"],
    "A7": [APP + "flows/A7_Refusal_To_Reactivation.flow-meta.xml", APP + "classes/SilentDealsJob.cls",
           APP + "customMetadata/Sales_Setting.Default.md-meta.xml",
           APP + "objects/Opportunity/validationRules/Gate_Stage_11_Refusal.validationRule-meta.xml"],
    "A8": [APP + "classes/PaymentControl.cls", APP + "customMetadata/Payment_Term.*.md-meta.xml"],
    "RR1": [APP + "classes/LeadConversionService.cls", APP + "classes/KeyCallService.cls"],
    "AC1": [APP + "permissionsets/Head_of_Sales.permissionset-meta.xml",
            APP + "objects/Opportunity/Opportunity.object-meta.xml"],
    "AC2": [APP + "permissionsets/Business_Owner.permissionset-meta.xml"],
    "AC3": [APP + "permissionsets/Closer.permissionset-meta.xml",
            APP + "objects/Opportunity/Opportunity.object-meta.xml"],
    "AC4": [APP + "permissionsets/Chat_Manager.permissionset-meta.xml",
            APP + "sharingRules/Opportunity.sharingRules-meta.xml",
            APP + "groups/Chat_Managers.group-meta.xml"],
    "AC5": [APP + "permissionsets/Assistant.permissionset-meta.xml",
            APP + "sharingRules/Opportunity.sharingRules-meta.xml",
            APP + "groups/Assistants.group-meta.xml"],
    "EX1": ["google-sheets/Code.gs", APP + "permissionsets/Sheets_Export.permissionset-meta.xml"],
    "EX2": ["google-sheets/Code.gs"],
    "EX3": ["google-sheets/transform.js", APP + "classes/PipelineTransitions.cls"],
    "EX4": ["google-sheets/transform.js"],
}


@dataclass
class Requirement:
    id: str
    text: str
    metadata: list[str]
    apex_tests: list[str]
    node_tests: list[str]

    @property
    def tests(self) -> list[str]:
        return self.apex_tests + self.node_tests


def brief_requirements() -> list[tuple[str, str]]:
    """(id, text) for each requirement, in the order the brief defines them."""
    found: dict[str, str] = {}
    lines = BRIEF.read_text(encoding="utf-8").splitlines()
    for i, line in enumerate(lines):
        bullet = re.match(rf"^- \*\*({ID})\*\* (.+)$", line)
        row = re.match(rf"^\| \*\*({ID})\*\* \| (.+) \|$", line)
        if bullet:
            text = bullet.group(2)
            for follow in lines[i + 1:]:
                if not follow.startswith("  "):
                    break
                text += " " + follow.strip()
            found.setdefault(bullet.group(1), text.rstrip(":"))
        elif row:
            cells = [cell.strip() for cell in row.group(2).split(" | ")]
            found.setdefault(row.group(1), ": ".join(cells))
    return list(found.items())


def apex_tests() -> dict[str, list[str]]:
    """Requirement id -> ["Class.method"] for every Apex test method named <ID>_<what it proves>."""
    tests: dict[str, list[str]] = {}
    for path in sorted(CLASSES.glob("*Test.cls")):
        source = path.read_text(encoding="utf-8")
        for requirement, rest in re.findall(rf"@isTest\s+static void ({ID})_(\w+)\(\)", source):
            tests.setdefault(requirement, []).append(f"{path.stem}.{requirement}_{rest}")
    return tests


def node_tests() -> dict[str, list[str]]:
    """Requirement id -> ["EX3 one row per deal ..."] for every Node test named after a requirement."""
    tests: dict[str, list[str]] = {}
    for path in sorted(SHEETS.glob("*.test.js")):
        for name in re.findall(r"^test\('([^']+)'", path.read_text(encoding="utf-8"), flags=re.M):
            match = re.match(rf"^({ID}) ", name)
            if match:
                tests.setdefault(match.group(1), []).append(name)
    return tests


def collect() -> list[Requirement]:
    apex, node = apex_tests(), node_tests()
    return [Requirement(rid, text, METADATA.get(rid, []), apex.get(rid, []), node.get(rid, []))
            for rid, text in brief_requirements()]


def problems(requirements: list[Requirement]) -> list[str]:
    issues = []
    known = {r.id for r in requirements}
    for requirement in requirements:
        if not requirement.tests:
            issues.append(f"{requirement.id} has no test named after it")
        if not requirement.metadata:
            issues.append(f"{requirement.id} is not mapped to any metadata")
        for pattern in requirement.metadata:
            if not list(ROOT.glob(pattern)):
                issues.append(f"{requirement.id}: nothing matches {pattern}")
    for rid in sorted((set(apex_tests()) | set(node_tests())) - known):
        issues.append(f"tests are named after {rid}, which is not in the brief")
    for rid in sorted(set(METADATA) - known):
        issues.append(f"{rid} is mapped to metadata but not in the brief")
    return issues


def _short(pattern: str) -> str:
    return "`" + pattern.removeprefix(APP) + "`"


def render(requirements: list[Requirement]) -> str:
    apex_count = sum(len(r.apex_tests) for r in requirements)
    node_count = sum(len(r.node_tests) for r in requirements)
    covered = sum(1 for r in requirements if r.tests)
    lines = [
        "# Traceability",
        "",
        "Generated by `scripts/traceability.py` from [brief.md](brief.md) and the test sources. Do not edit by hand.",
        "",
        "Every requirement of the brief maps to the configuration that implements it and to the tests that prove",
        "it. Apex test methods are named after the requirement and run in a Salesforce org (`make org-test`).",
        "Node tests check the Google Sheets export (`make node-test`). Metadata paths are under",
        "`force-app/main/default/` unless they say otherwise.",
        "",
        f"{len(requirements)} requirements, {covered} with at least one test: {apex_count} Apex test methods and "
        f"{node_count} Node tests.",
        "",
        "| Id | Requirement | Implemented in | Proven by |",
        "|---|---|---|---|",
    ]
    for r in requirements:
        tests = [f"`{t}`" for t in r.apex_tests] + [f"Node: {t[len(r.id) + 1:]}" for t in r.node_tests]
        lines.append(f"| {r.id} | {r.text} | {'<br>'.join(_short(m) for m in r.metadata)} | {'<br>'.join(tests)} |")
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="fail on gaps or an out-of-date docs/traceability.md")
    args = parser.parse_args(argv)
    requirements = collect()
    issues = problems(requirements)
    text = render(requirements)
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text(encoding="utf-8") != text:
            issues.append("docs/traceability.md is out of date: run `make traceability`")
        for issue in issues:
            print(f"FAIL {issue}", file=sys.stderr)
        print(f"{len(requirements)} requirements checked, {len(issues)} problem(s)")
        return 1 if issues else 0
    OUTPUT.write_text(text, encoding="utf-8")
    print(f"docs/traceability.md written: {len(requirements)} requirements, {len(issues)} problem(s)")
    for issue in issues:
        print(f"  {issue}", file=sys.stderr)
    return 1 if issues else 0


if __name__ == "__main__":
    sys.exit(main())
