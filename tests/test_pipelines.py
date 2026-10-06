"""Pipelines in the metadata: record types, sales processes, the stage list and stage order."""

import re

import pytest
from sfmeta import FORCE_APP, OPPORTUNITY, business_process, field, read, text, texts

NEW_CLIENTS = [
    "New lead", "Qualification in chat", "Warm-up", "Key call scheduled", "Key call confirmed", "Key call held",
    "Closing", "Prepayment received", "Payment received", "Handed over to preparation", "Conditional refusal",
]
REACTIVATION = ["Deferred demand", "Waiting for next period", "Ignored", "Regular touches", "Dialogue resumed"]
REPEAT_SALES = [
    "Building the base", "Announcement and pre-registration", "Clarifying the situation", "Key call scheduled",
]

PIPELINES = {
    "New_Clients": NEW_CLIENTS + ["Closed Won", "Closed Lost"],
    "Reactivation": REACTIVATION + ["Closed Lost"],
    "Repeat_Sales": REPEAT_SALES + ["Closed Lost"],
}


@pytest.mark.parametrize("name", sorted(PIPELINES))
def test_each_pipeline_is_an_active_record_type_with_its_own_sales_process(name):
    record_type = read(OPPORTUNITY / "recordTypes" / f"{name}.recordType-meta.xml")
    assert text(record_type, "active") == "true"
    assert text(record_type, "businessProcess") == f"{name}_Process"


@pytest.mark.parametrize("name, stages", sorted(PIPELINES.items()))
def test_each_sales_process_has_the_brief_stages_in_order(name, stages):
    assert business_process(f"{name}_Process") == stages


def test_repeat_sales_does_not_repeat_stages_five_to_ten():
    repeat = set(business_process("Repeat_Sales_Process"))
    assert repeat.isdisjoint(NEW_CLIENTS[4:10])


def test_the_stage_list_holds_every_stage_and_keeps_the_org_defaults():
    root = read(FORCE_APP / "standardValueSets" / "OpportunityStage.standardValueSet-meta.xml")
    values = {text(v, "fullName"): v for v in root.findall("standardValue")}
    for stage in NEW_CLIENTS + REACTIVATION + REPEAT_SALES:
        assert stage in values, stage
        assert text(values[stage], "closed") == "false", stage
    assert text(values["Closed Won"], "won") == "true"
    assert text(values["Closed Lost"], "closed") == "true"
    assert {"Qualify", "Meet & Present", "Propose", "Negotiate"} <= set(values), "installing removes nothing"


def test_salesforce_order_follows_each_pipeline():
    root = read(FORCE_APP / "standardValueSets" / "OpportunityStage.standardValueSet-meta.xml")
    order = texts(root, "standardValue/fullName")
    for stages in (NEW_CLIENTS, REACTIVATION, REPEAT_SALES):
        positions = [order.index(stage) for stage in stages]
        assert positions == sorted(positions), stages


def test_stage_order_formula_numbers_the_new_clients_flow():
    formula = text(field("Stage_Order__c"), "formula")
    for number, stage in enumerate(NEW_CLIENTS[:10], start=1):
        assert re.search(rf'"{re.escape(stage)}",\s*{number},', formula), stage
    assert '"Closed Won", 11,' in formula
    assert '"Clarifying the situation", 2,' in formula, "repeat sales qualification sits on stage 2"
    assert "Conditional refusal" not in formula, "a refusal can happen at any stage, so it is not gated"
    assert 'RecordType.DeveloperName = "New_Clients"' in formula, "other opportunities are never gated"


def test_a_validation_rule_keeps_every_stage_inside_its_pipeline():
    rule = read(OPPORTUNITY / "validationRules" / "Stage_Belongs_To_Pipeline.validationRule-meta.xml")
    formula = text(rule, "errorConditionFormula")
    assert text(rule, "active") == "true"
    for name, stages in PIPELINES.items():
        branch = formula.split(f'"{name}",', 1)[1].split("0),", 1)[0]
        for stage in stages:
            assert f'"{stage}", 1' in branch, (name, stage)
