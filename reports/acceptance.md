# Salesforce sales pipeline: acceptance test

| Criterion | Target | Measured | 95% interval | Result |
|---|---|---|---|---|
| Brief requirements implemented with a passing test | = 100% | 100.0% | 89.3–100.0% | PASS |
| Apex tests passing in a real Salesforce org | = 100% | 100.0% | 93.6–100.0% | PASS |
| Apex code covered by tests | ≥ 90% | 99.3% | 98.0–99.8% | PASS |
| Metadata conformance checks passing | = 100% | 100.0% | 97.7–100.0% | PASS |

71 made-up test cases, recorded 2026-10-16.

All criteria passed.

## Requirements

| Id | Requirement | Tests | Result |
|---|---|---|---|
| NF1 | The automations must cope with our volume in bulk: a whole month of leads (150) arriving at once must all become deals, with nothing lost. | 1 | pass |
| PL1 | Pipeline 1, New clients, has these 11 stages in this order | 2 | pass |
| PL2 | Pipeline 2, Reactivation, holds refusals and silent clients, in 5 stages | 1 | pass |
| PL3 | Pipeline 3, Repeat sales, has 4 stages. Stages 5 to 10 are not repeated in it: after stage 4 the deal continues in pipeline 1 from stage 5. | 1 | pass |
| TR1 | A deal returns from Reactivation to New clients by hand, as the same record, at Key call scheduled. | 3 | pass |
| TR2 | A won deal in the repeat segment gets a tag. It is not moved or copied automatically. | 1 | pass |
| TR3 | When a false objection is handled, the deal goes back to Prepayment received and never leaves pipeline 1. | 1 | pass |
| TR4 | A repeat-sales deal continues in New clients after stage 4, as the same record. | 1 | pass |
| FL1 | A deal carries the 21 fields below (23 in total, because qualification has three criteria). | 1 | pass |
| FL2 | Every field with a list of values is a list, never free text. Free text cannot be added up, and half of the dashboard would not work. Sources, segments, objections and refusal reasons are shared reference lists. | 1 | pass |
| FL3 | Lead author is set by the system once and is never overwritten. | 1 | pass |
| FL4 | Blocking rule: a deal cannot move on to the next stage until the required fields of its current stage are filled. Without this, the data is never collected. | 3 | pass |
| FL5 | Warm-up touches counts up by itself while the deal is in Warm-up. | 1 | pass |
| FL6 | Start period fills in by itself from a date once the client prepays. | 1 | pass |
| A1 | A website form is submitted: Create the deal, fill source and request type, record the lead author | 6 | pass |
| A2 | A deal is created: A task "Reply" due in 30 minutes; the first response time is recorded automatically | 3 | pass |
| A3 | A grade is set: Grade A goes to stage 4; grades B and C go to stage 3 | 3 | pass |
| A4 | A key call is booked: The closer becomes the owner, a meeting is created, and the slot must be at least 3 hours ahead | 3 | pass |
| A5 | 24 hours and 1 hour before the key call: Two confirmation tasks | 3 | pass |
| A6 | The key call is held: The call recording is attached; a task "Day +1: record the objection" | 2 | pass |
| A7 | A refusal, or 5 to 7 days with no reply: The deal moves to pipeline 2 automatically, with a tag | 5 | pass |
| A8 | The prepayment arrives: The target date for the full payment is calculated; two control tasks | 3 | pass |
| RR1 | Switch off round-robin distribution of leads. Closers are chosen by who has a free slot, so nothing reassigns deals automatically except A4. | 1 | pass |
| AC1 | Head of sales: All pipelines, reports, settings, export | 1 | pass |
| AC2 | Owner: Reads everything, reports, export | 1 | pass |
| AC3 | Closer: Own deals in pipeline 1 from stage 4; cannot delete or export | 1 | pass |
| AC4 | Chat manager: Pipelines 1 and 2 in full; cannot delete or export | 1 | pass |
| AC5 | Assistant: Stages 9 and 10 of pipeline 1 only | 1 | pass |
| EX1 | Direction: from the CRM to Google Sheets, one way. Nothing is written back. | 2 | pass |
| EX2 | Frequency: at least once an hour, plus a manual run. | 1 | pass |
| EX3 | Structure: one sheet of raw data, one row per deal, with these 25 columns: id, pipeline, stage, created date, source, request type, grade, segment, lead author, closer, key call booked on, key call date and time, key call outcome, key call result, objection, prepayment date, payment method, full payment date, amount, start period, refusal reason, refusal type, first response time, last activity date, close date. | 7 | pass |
| EX4 | Dashboard sheets built with formulas on top of the raw sheet, in 8 blocks: the month's funnel, conversion rates, by closer, by chat manager, unprocessed leads, enrollment forecast, sources with CPL and CAC, refusal reasons. | 8 | pass |

## Where the numbers come from

- Apex: 56 test methods run in a Salesforce org on 2026-10-16, stored in [org-test-run.json](org-test-run.json).
- Static checks: 160 pytest checks on the metadata XML, run by this script.
- Node: 15 tests of the Google Sheets export, run by this script.
