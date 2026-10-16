"""Automations in the metadata: the four flows, the Apex triggers, the settings and the export query."""

import re

import pytest
from sfmeta import CLASSES, FORCE_APP, SHEETS, apex_string_constant, picklist_values, read, text, texts

FLOWS = {
    "A2_Reply_Task": ("Create", "RecordAfterSave"),
    "A3_Grade_Routing": ("Update", "RecordBeforeSave"),
    "A6_Objection_Task": ("Update", "RecordAfterSave"),
    "A7_Refusal_To_Reactivation": ("Update", "RecordBeforeSave"),
}
TRIGGERS = {"LeadTrigger": "Lead", "OpportunityTrigger": "Opportunity", "TaskTrigger": "Task"}


@pytest.mark.parametrize("name", sorted(FLOWS))
def test_flows_are_active_record_triggered_flows_on_opportunity(name):
    flow = read(FORCE_APP / "flows" / f"{name}.flow-meta.xml")
    assert text(flow, "status") == "Active"
    assert text(flow, "processType") == "AutoLaunchedFlow"
    assert text(flow, "start/object") == "Opportunity"
    assert (text(flow, "start/recordTriggerType"), text(flow, "start/triggerType")) == FLOWS[name]
    assert "RecordType.DeveloperName" in text(flow, "start/filterFormula"), "only the three pipelines"


def test_reply_task_is_due_in_thirty_minutes():
    flow = read(FORCE_APP / "flows" / "A2_Reply_Task.flow-meta.xml")
    assert texts(flow, "formulas/expression") == ["{!$Flow.CurrentDateTime} + (30 / 1440)"]


def test_grade_routing_sends_a_to_stage_four_and_b_c_to_stage_three():
    flow = read(FORCE_APP / "flows" / "A3_Grade_Routing.flow-meta.xml")
    targets = {text(a, "name"): text(a, "assignmentItems/value/stringValue") for a in flow.findall("assignments")}
    assert targets == {"Route_To_Key_Call_Scheduled": "Key call scheduled", "Route_To_Warm_Up": "Warm-up"}


@pytest.mark.parametrize("name, obj", sorted(TRIGGERS.items()))
def test_one_trigger_per_object_delegating_to_a_class(name, obj):
    source = (FORCE_APP / "triggers" / f"{name}.trigger").read_text(encoding="utf-8")
    assert re.match(rf"trigger {name} on {obj} \(", source)
    assert len([line for line in source.splitlines() if line.strip()]) <= 8, "logic lives in classes"


def test_every_class_and_trigger_uses_the_project_api_version():
    metas = [*FORCE_APP.joinpath("classes").glob("*-meta.xml"), *FORCE_APP.joinpath("triggers").glob("*-meta.xml")]
    assert metas
    for meta in metas:
        assert text(read(meta), "apiVersion") == "67.0", meta.name


DML = re.compile(r"(?:^|[;{})]|\belse\b)\s*(insert|update|delete|upsert|undelete|merge)\s+(?!as\s+(?:user|system)\b)",
                 re.MULTILINE)
DATABASE_CALL = re.compile(r"\bDatabase\.(insert|update|delete|upsert|undelete|merge|convertLead|query|getQueryLocator"
                           r"|countQuery)\(")
INLINE_QUERY = re.compile(r"\[\s*(SELECT|FIND)\b", re.IGNORECASE)
ACCESS_MODE = re.compile(r"\bWITH\s+(USER|SYSTEM)_MODE\b|\bAccessLevel\.(USER|SYSTEM)_MODE\b", re.IGNORECASE)


def _code_only(source):
    """The Apex source with comments and string literals blanked out, so keywords inside them don't count."""
    return re.sub(r"/\*.*?\*/|//[^\n]*|'(?:\\.|[^'\\])*'", lambda m: re.sub(r"[^\n]", " ", m.group()), source,
                  flags=re.DOTALL)


def _enclosed(code, start, opening, closing):
    """The text from `start` (an opening bracket) to its matching closing bracket."""
    depth = 0
    for index in range(start, len(code)):
        depth += {opening: 1, closing: -1}.get(code[index], 0)
        if depth == 0:
            return code[start:index + 1]
    raise AssertionError(f"unbalanced {opening} at {start}")


@pytest.mark.parametrize("path", sorted([*CLASSES.glob("*.cls"), *FORCE_APP.joinpath("triggers").glob("*.trigger")]),
                         ids=lambda path: path.name)
def test_every_database_operation_states_its_access_mode(path):
    # From API 67.0 a statement without one runs with the running user's permissions, so each one says.
    code = _code_only(path.read_text(encoding="utf-8"))
    line = lambda index: code.count("\n", 0, index) + 1  # noqa: E731
    missing = [f"line {line(m.start(1))}: {m.group(1)}" for m in DML.finditer(code)]
    for match in DATABASE_CALL.finditer(code):
        if not ACCESS_MODE.search(_enclosed(code, match.end() - 1, "(", ")")):
            missing.append(f"line {line(match.start())}: Database.{match.group(1)}")
    for match in INLINE_QUERY.finditer(code):
        if not ACCESS_MODE.search(_enclosed(code, match.start(), "[", "]")):
            missing.append(f"line {line(match.start())}: inline {match.group(1).upper()}")
    assert not missing, missing


def test_the_test_suite_runs_every_test_class():
    suite = read(FORCE_APP / "testSuites" / "Sales_Pipeline.testSuite-meta.xml")
    classes = sorted(path.stem for path in CLASSES.glob("*Test.cls"))
    assert sorted(texts(suite, "testClassName")) == classes


def test_silence_days_setting_is_between_five_and_seven():
    record = read(FORCE_APP / "customMetadata" / "Sales_Setting.Default.md-meta.xml")
    days = int(float(text(record.find("values"), "value")))
    assert 5 <= days <= 7
    rules = FORCE_APP / "objects" / "Sales_Setting__mdt" / "validationRules"
    rule = read(rules / "Silence_Days_Between_5_And_7.validationRule-meta.xml")
    assert "Silence_Days__c < 5" in text(rule, "errorConditionFormula")


def _metadata_values(prefix):
    rows = []
    for path in sorted((FORCE_APP / "customMetadata").glob(f"{prefix}.*.md-meta.xml")):
        values = {text(v, "field"): text(v, "value") for v in read(path).findall("values")}
        rows.append(values)
    return rows


def test_every_payment_method_has_a_target_date_term():
    terms = {row["Payment_Method__c"]: row for row in _metadata_values("Payment_Term")}
    assert set(terms) == set(picklist_values("Payment_Method__c"))
    for row in terms.values():
        assert int(float(row["Days_To_Full_Payment__c"])) > int(float(row["Reminder_Days_Before__c"])) >= 0


def test_utm_mappings_point_to_real_sources():
    sources = set(picklist_values("Source__c"))
    rows = _metadata_values("Source_Mapping")
    assert rows
    for row in rows:
        assert row["Source__c"] in sources, row
        assert row["UTM_Source__c"] == row["UTM_Source__c"].lower()


def test_every_automation_tag_used_in_code_exists_on_activities():
    values = set(picklist_values("Automation__c", obj="Activity"))
    source = (CLASSES / "Activities.cls").read_text(encoding="utf-8")
    used = set(re.findall(r"= '(A\d_\w+)';", source))
    for flow in FLOWS:
        flow_source = (FORCE_APP / "flows" / f"{flow}.flow-meta.xml").read_text(encoding="utf-8")
        used |= set(re.findall(r"<stringValue>(A\d_\w+)</stringValue>", flow_source))
    assert used and used <= values, used - values


def test_the_export_reads_exactly_what_the_apex_test_proves():
    sheets = apex_string_constant((SHEETS / "transform.js").read_text(encoding="utf-8"))
    apex = apex_string_constant((CLASSES / "ExportTest.cls").read_text(encoding="utf-8"))
    assert sheets == apex
    assert sheets.startswith("SELECT Id, RecordType.Name, StageName,")
