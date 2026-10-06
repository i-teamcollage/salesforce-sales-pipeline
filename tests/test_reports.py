"""The report logic: storing an org run without private data, and turning results into the criteria."""

import acceptance_run
import save_org_run
import traceability

RAW = {
    "status": 0,
    "result": {
        "summary": {"outcome": "Passed", "testsRan": 2, "passing": 1, "failing": 1, "skipped": 0,
                    "orgId": "00D000000000001", "username": "someone@example.org", "hostname": "https://x.example",
                    "testStartTime": "2026-10-06T10:00:00.000Z", "testRunCoverage": "91%", "orgWideCoverage": "91%"},
        "tests": [
            {"MethodName": "A3_gradeAGoesToKeyCallScheduled", "Outcome": "Pass", "RunTime": 120,
             "ApexClass": {"Name": "GradeRoutingTest"}, "Message": None},
            {"MethodName": "A4_slotLessThanThreeHoursAheadIsRejected", "Outcome": "Fail", "RunTime": 80,
             "ApexClass": {"Name": "KeyCallTest"}, "Message": "Assertion failed"},
        ],
        "coverage": {"coverage": [
            {"name": "KeyCallService", "totalLines": 90, "totalCovered": 81},
            {"name": "SomeoneElsesClass", "totalLines": 100, "totalCovered": 0},
        ]},
    },
}


def test_a_stored_run_keeps_outcomes_and_coverage_but_nothing_private():
    run = save_org_run.slim(RAW)
    assert run["recorded_at"] == "2026-10-06"
    assert [t["outcome"] for t in run["tests"]] == ["Pass", "Fail"]
    assert run["coverage"][0] == {"name": "KeyCallService", "lines": 90, "covered": 81}
    text = str(run)
    for private in ("00D000000000001", "someone@example.org", "x.example"):
        assert private not in text


def test_org_criteria_count_only_this_projects_apex():
    measures, apex = acceptance_run.org_measures(save_org_run.slim(RAW), {"KeyCallService"})
    assert apex == {"GradeRoutingTest.A3_gradeAGoesToKeyCallScheduled": True,
                    "KeyCallTest.A4_slotLessThanThreeHoursAheadIsRejected": False}
    assert (measures["org_tests_passing"].hits, measures["org_tests_passing"].total) == (1, 2)
    assert (measures["apex_coverage"].hits, measures["apex_coverage"].total) == (81, 90)


def test_a_requirement_passes_only_when_every_test_named_after_it_passed():
    requirements = [
        traceability.Requirement("A3", "grade routing", [], ["GradeRoutingTest.A3_x"], []),
        traceability.Requirement("A4", "key call", [], ["KeyCallTest.A4_y"], []),
        traceability.Requirement("EX2", "hourly", [], [], ["EX2 hourly"]),
        traceability.Requirement("A5", "confirmations", [], ["KeyCallTest.A5_z"], []),
    ]
    apex = {"GradeRoutingTest.A3_x": True, "KeyCallTest.A4_y": False}
    rows = acceptance_run.requirement_rows(requirements, apex, {"EX2 hourly": True})
    assert [row["status"] for row in rows] == ["pass", "fail", "pass", "waiting for the org run"]
