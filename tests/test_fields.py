"""Fields of the brief: types, restricted lists, global value sets, and a gating rule for every gated field."""

import pytest
from sfmeta import field, field_names, picklist_values, text, validation_rules

# The 21 rows of the brief's table (23 fields), their Salesforce type and the stage they are required from.
BRIEF_FIELDS = {
    "Source__c": ("Picklist", 1),
    "Request_Type__c": ("Picklist", 1),
    "First_Response_At__c": ("DateTime", 1),
    "Lead_Author__c": ("Lookup", 1),
    "Qualification_Goal__c": ("Picklist", 2),
    "Qualification_Budget__c": ("Picklist", 2),
    "Qualification_Timing__c": ("Picklist", 2),
    "Grade__c": ("Picklist", 2),
    "Segment__c": ("Picklist", 2),
    "Warm_Up_Touches__c": ("Number", 3),
    "Key_Call_Booked_On__c": ("Date", 4),
    "Key_Call_At__c": ("DateTime", 4),
    "Closer__c": ("Lookup", 4),
    "Key_Call_Outcome__c": ("Picklist", 6),
    "Key_Call_Result__c": ("Picklist", 6),
    "Objection__c": ("Picklist", 7),
    "Decision_Control_Date__c": ("Date", 7),
    "Prepayment_Date__c": ("Date", 8),
    "Payment_Method__c": ("Picklist", 8),
    "Start_Period__c": ("Text", 8),
    "Full_Payment_Date__c": ("Date", 9),
    "Refusal_Reason__c": ("Picklist", 11),
    "Refusal_Type__c": ("Picklist", 11),
}
GLOBAL_VALUE_SETS = {
    "Source__c": "Sales_Sources",
    "Segment__c": "Client_Segments",
    "Objection__c": "Objections",
    "Refusal_Reason__c": "Refusal_Reasons",
}
LIST_SIZES = {"Request_Type__c": 2, "Grade__c": 3, "Segment__c": 4, "Key_Call_Outcome__c": 4, "Key_Call_Result__c": 3,
              "Payment_Method__c": 3, "Refusal_Type__c": 3}


def test_the_brief_has_twenty_three_fields_and_the_object_stays_within_twenty_five():
    assert len(BRIEF_FIELDS) == 23
    names = field_names()
    assert set(BRIEF_FIELDS) <= set(names)
    assert len(names) <= 25, "fits even the smallest Salesforce editions"


@pytest.mark.parametrize("name", sorted(BRIEF_FIELDS))
def test_field_type_matches_the_brief(name):
    assert text(field(name), "type") == BRIEF_FIELDS[name][0]


@pytest.mark.parametrize("name", sorted(n for n, (kind, _) in BRIEF_FIELDS.items() if kind == "Picklist"))
def test_every_list_is_a_restricted_picklist(name):
    element = field(name)
    gvs = text(element, "valueSet/valueSetName")
    assert gvs or text(element, "valueSet/restricted") == "true", name
    assert picklist_values(name), name
    if name in GLOBAL_VALUE_SETS:
        assert gvs == GLOBAL_VALUE_SETS[name], "shared reference list"
    if name in LIST_SIZES:
        assert len(picklist_values(name)) == LIST_SIZES[name]


def test_user_fields_point_to_users_and_start_period_is_filled_by_the_system():
    for name in ("Lead_Author__c", "Closer__c"):
        assert text(field(name), "referenceTo") == "User"
    formula = text(field("Start_Period__c"), "formula")
    assert "ADDMONTHS(Prepayment_Date__c, 1)" in formula


def _gate_rules():
    return {name: text(rule, "errorConditionFormula") for name, rule in validation_rules().items()
            if text(rule, "active") == "true"}


@pytest.mark.parametrize("name", sorted(BRIEF_FIELDS))
def test_every_gated_field_has_a_validation_rule_for_its_stage(name):
    stage = BRIEF_FIELDS[name][1]
    if stage == 11:
        rule = _gate_rules()["Gate_Stage_11_Refusal"]
        assert name in rule and 'RecordType.DeveloperName = "Reactivation"' in rule
        return
    matching = [f for f in _gate_rules().values() if f"Stage_Order__c > {stage}," in f and name in f]
    assert matching, f"{name} must block the move past stage {stage}"


def test_lead_author_is_locked_once_set():
    rule = _gate_rules()["Lead_Author_Set_Once"]
    assert "ISCHANGED(Lead_Author__c)" in rule and "PRIORVALUE(Lead_Author__c)" in rule


def test_key_call_must_be_at_least_three_hours_ahead():
    assert "Key_Call_At__c < NOW() + 3/24" in _gate_rules()["Key_Call_At_Least_3_Hours_Ahead"]


def test_validation_rules_fit_the_twenty_rule_limit():
    assert len(_gate_rules()) <= 20
