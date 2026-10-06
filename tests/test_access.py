"""Access rights in the metadata: Private sharing, one permission set per role, two criteria rules."""

import pytest
from sfmeta import FORCE_APP, OPPORTUNITY, ROOT, permission_set, read, text, texts

ROLES = ["Head_of_Sales", "Business_Owner", "Closer", "Chat_Manager", "Assistant"]
SYSTEM_FILLED = ["First_Response_At__c", "Lead_Author__c", "Warm_Up_Touches__c", "Key_Call_Booked_On__c",
                 "Stage_Order__c", "Start_Period__c"]


def objects(name):
    return {text(o, "object"): o for o in permission_set(name).findall("objectPermissions")}


def user_permissions(name):
    root = permission_set(name)
    return {text(p, "name") for p in root.findall("userPermissions") if text(p, "enabled") == "true"}


def test_opportunity_sharing_is_private():
    root = read(OPPORTUNITY / "Opportunity.object-meta.xml")
    assert text(root, "sharingModel") == "Private"


@pytest.mark.parametrize("name", ROLES + ["Sheets_Export"])
def test_one_permission_set_per_role(name):
    assert permission_set(name).find("label") is not None


@pytest.mark.parametrize("name", ["Closer", "Chat_Manager", "Assistant"])
def test_restricted_roles_cannot_delete_or_export(name):
    for obj, permissions in objects(name).items():
        assert text(permissions, "allowDelete") == "false", (name, obj)
        assert text(permissions, "modifyAllRecords") == "false", (name, obj)
        assert text(permissions, "viewAllRecords") == "false", (name, obj)
    assert not user_permissions(name) & {"ExportReport", "RunReports", "ModifyAllData", "ViewAllData"}, name


def test_head_of_sales_has_everything():
    opportunity = objects("Head_of_Sales")["Opportunity"]
    assert text(opportunity, "modifyAllRecords") == "true"
    assert {"ExportReport", "RunReports", "CustomizeApplication"} <= user_permissions("Head_of_Sales")


@pytest.mark.parametrize("name", ["Business_Owner", "Sheets_Export"])
def test_read_only_roles_read_everything_and_write_nothing(name):
    for obj, permissions in objects(name).items():
        for flag in ("allowCreate", "allowEdit", "allowDelete", "modifyAllRecords"):
            assert text(permissions, flag) == "false", (name, obj, flag)
    assert text(objects(name)["Opportunity"], "viewAllRecords") == "true"
    for item in permission_set(name).findall("fieldPermissions"):
        assert text(item, "editable") == "false", (name, text(item, "field"))


def test_owner_has_reports_and_export_and_the_export_user_has_the_api():
    assert {"ExportReport", "RunReports"} <= user_permissions("Business_Owner")
    assert "ApiEnabled" in user_permissions("Sheets_Export")


@pytest.mark.parametrize("name", ROLES + ["Sheets_Export"])
def test_system_filled_fields_are_read_only_for_everyone(name):
    fields = {text(f, "field"): f for f in permission_set(name).findall("fieldPermissions")}
    for field in SYSTEM_FILLED:
        assert text(fields[f"Opportunity.{field}"], "editable") == "false", (name, field)


def test_closer_sees_only_the_pipelines_a_closer_works_in():
    root = permission_set("Closer")
    visible = set(texts(root, "recordTypeVisibilities/recordType"))
    assert visible == {"Opportunity.New_Clients", "Opportunity.Reactivation"}


def test_criteria_rules_share_pipelines_one_and_two_and_stages_nine_and_ten():
    root = read(FORCE_APP / "sharingRules" / "Opportunity.sharingRules-meta.xml")
    rules = {text(r, "fullName"): r for r in root.findall("sharingCriteriaRules")}
    chat = rules["Chat_Managers_Pipelines_1_And_2"]
    assert text(chat, "sharedTo/group") == "Chat_Managers"
    assert texts(chat, "criteriaItems/value") == ["New clients,Reactivation"]
    assistants = rules["Assistants_Stages_9_And_10"]
    assert text(assistants, "sharedTo/group") == "Assistants"
    stages = "Payment received,Handed over to preparation"
    assert set(texts(assistants, "criteriaItems/value")) == {"New clients", stages}
    for group in ("Chat_Managers", "Assistants"):
        assert (FORCE_APP / "groups" / f"{group}.group-meta.xml").exists()


def test_no_assignment_rules_so_nothing_reassigns_leads_round_robin():
    assert not list(ROOT.joinpath("force-app").rglob("*.assignmentRules-meta.xml"))
