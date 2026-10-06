"""Every requirement of the brief is implemented somewhere and proven by a test named after it."""

import traceability


def test_the_brief_defines_all_thirty_two_requirements():
    ids = [rid for rid, _ in traceability.brief_requirements()]
    assert len(ids) == len(set(ids)) == 32
    for prefix, count in {"PL": 3, "TR": 4, "FL": 6, "A": 8, "RR": 1, "AC": 5, "EX": 4, "NF": 1}.items():
        assert len([rid for rid in ids if rid.rstrip("0123456789") == prefix]) == count, prefix


def test_every_requirement_has_a_test_and_existing_metadata():
    assert traceability.problems(traceability.collect()) == []


def test_salesforce_requirements_are_proven_by_apex_tests():
    for requirement in traceability.collect():
        if not requirement.id.startswith("EX"):
            assert requirement.apex_tests, f"{requirement.id} needs an Apex test that runs in the org"


def test_the_traceability_document_is_up_to_date():
    expected = traceability.render(traceability.collect())
    assert traceability.OUTPUT.read_text(encoding="utf-8") == expected, "run `make traceability`"
