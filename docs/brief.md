# Brief: sales pipeline in Salesforce for Quorvale Academy

> A sample brief. Quorvale Academy is a fictional company, and so is everything else here. The brief is
> written the way a client hands it to a contractor: the process is already designed and agreed, and the
> contractor builds it. Every requirement has an id in bold, such as **A1**. The same id names the tests
> that prove it (see [traceability.md](traceability.md)).

## 1. Why this document exists

We want a quote for one defined piece of work, not a range. This brief says what to build, how much of
it, and what counts as done. The pipelines, fields and rules below are final. The contractor implements
them in Salesforce Sales Cloud and does not redesign them.

## 2. The company

| Item | Value |
|---|---|
| What we sell | Cohort-based online programs (data analytics, product management) with fixed start dates |
| Sales flow | Inbound lead, qualification in chat, key call, closing, prepayment, full payment |
| Key call | The one video call where a closer presents the program and asks for a decision |
| Volume | About 100 to 150 new deals a month |
| People | A head of sales, two or three closers who run the calls, one chat manager, one assistant |
| Today | The CRM is used in part, almost nothing is automated, reports are built by hand |
| Channel | A messenger; every conversation runs from one company account |

- **NF1** The automations must cope with our volume in bulk: a whole month of leads (150) arriving at
  once must all become deals, with nothing lost.

## 3. Scope

In scope:

1. Block A, the CRM: three pipelines, fields, reference lists, the priority automations, access rights.
2. Block B, Google Sheets: an automatic, one-way export of deals for a management dashboard.

Out of scope: the website and ad accounts, migrating old deals beyond the current period, sales scripts
and written procedures, and training our team.

Rule for the spreadsheet: data arrives automatically and nobody types into it. The CRM is the only source
of truth about a deal.

## 4. Pipelines

- **PL1** Pipeline 1, New clients, has these 11 stages in this order:

| # | Stage | Owner | The deal leaves the stage when |
|---|---|---|---|
| 1 | New lead | Chat manager | the data needed to qualify the client is collected |
| 2 | Qualification in chat | Chat manager | the three criteria are filled and a grade and a segment are set |
| 3 | Warm-up | Chat manager | the client has gone through the material and confirms interest |
| 4 | Key call scheduled | Chat manager, then closer | a slot is booked and the client confirms it |
| 5 | Key call confirmed | Chat manager | the time of the call arrives |
| 6 | Key call held | Closer | the result of the call is recorded |
| 7 | Closing | Chat manager | the client gives a final answer |
| 8 | Prepayment received | Chat manager | the client pays in full or an instalment plan is approved |
| 9 | Payment received | Chat manager | the client is handed over to the program team |
| 10 | Handed over to preparation | Assistant | the deal is closed as won, with its start period |
| 11 | Conditional refusal | Closer or chat manager | the deal moves to pipeline 2 automatically |

- **PL2** Pipeline 2, Reactivation, holds refusals and silent clients, in 5 stages:

| # | Stage | Owner | The deal leaves the stage when |
|---|---|---|---|
| 1 | Deferred demand | Chat manager | the client says their situation has changed |
| 2 | Waiting for next period | Chat manager | the client pre-books a seat and the deal returns to pipeline 1 |
| 3 | Ignored | Chat manager | the client answers at all |
| 4 | Regular touches | Chat manager | the client answers |
| 5 | Dialogue resumed | Chat manager | re-qualification passes and the deal returns to Key call scheduled |

- **PL3** Pipeline 3, Repeat sales, has 4 stages. Stages 5 to 10 are not repeated in it: after stage 4
  the deal continues in pipeline 1 from stage 5.

| # | Stage | Owner | The deal leaves the stage when |
|---|---|---|---|
| 1 | Building the base | Chat manager | the client falls into the target segment |
| 2 | Announcement and pre-registration | Chat manager | the client fills the pre-registration form |
| 3 | Clarifying the situation | Chat manager | the qualification fields are filled and a grade is set |
| 4 | Key call scheduled | Chat manager, then closer | the slot is booked |

The key rule: a deal that comes back to pipeline 1 comes back as the same record. No new deal is created,
or the source attribution breaks and the lead is counted twice.

## 5. Moving between pipelines

| From, to | Trigger | How |
|---|---|---|
| 1 to 2 | Conditional refusal at any stage | Automatic, when Refusal reason is filled (**A7**) |
| 1 to 2 | 5 to 7 days with no reply from the client | Automatic, with the tag "Ignored" (**A7**) |
| 2 to 1 | Interest confirmed, or a seat pre-booked | By hand, same record, at Key call scheduled (**TR1**) |
| 1 to 3 | Won, and the client falls into the repeat segment | A tag marks the segment; nothing moves automatically (**TR2**) |
| Inside 1 | A false objection was handled | Back to Prepayment received; the deal stays in pipeline 1 (**TR3**) |
| 3 to 1 | The key call is booked | Same record, continues from stage 5 (**TR4**) |

- **TR1** A deal returns from Reactivation to New clients by hand, as the same record, at Key call
  scheduled.
- **TR2** A won deal in the repeat segment gets a tag. It is not moved or copied automatically.
- **TR3** When a false objection is handled, the deal goes back to Prepayment received and never leaves
  pipeline 1.
- **TR4** A repeat-sales deal continues in New clients after stage 4, as the same record.

## 6. Fields and reference lists

- **FL1** A deal carries the 21 fields below (23 in total, because qualification has three criteria).
- **FL2** Every field with a list of values is a list, never free text. Free text cannot be added up, and
  half of the dashboard would not work. Sources, segments, objections and refusal reasons are shared
  reference lists.

| # | Field | Type | Filled by | Required from stage |
|---|---|---|---|---|
| 1 | Source | List | Automatically, from the form | 1 |
| 2 | Request type | List of 2 values | Automatically, from the form used | 1 |
| 3 | First response time | Date and time | System | 1, automatic |
| 4 | Lead author | User | System, set once and never overwritten | 1, automatic |
| 5 | Qualification, 3 criteria | 3 lists | Chat manager | 2 |
| 6 | Grade | List: A, B, C | Chat manager | 2 |
| 7 | Segment | List of 4 values | Chat manager | 2 |
| 8 | Warm-up touches | Number | System, counts up | 3, automatic |
| 9 | Key call booked on | Date | System | 4, automatic |
| 10 | Key call date and time | Date and time | Chat manager | 4 |
| 11 | Closer | User | Chat manager | 4 |
| 12 | Key call outcome | List: held, no-show, rescheduled, cancelled | Closer | 6 |
| 13 | Key call result | List: purchase, thinking, refusal | Closer | 6 |
| 14 | Objection | List from the objections reference | Chat manager | 7 |
| 15 | Decision control date | Date | Closer | 7 |
| 16 | Prepayment date | Date | Chat manager | 8 |
| 17 | Payment method | List of 3 values | Chat manager | 8 |
| 18 | Full payment date | Date | Chat manager | 9 |
| 19 | Start period | List | Automatically, from a date | 8, automatic |
| 20 | Refusal reason | List from the refusal reasons reference | Closer or chat manager | 11 |
| 21 | Refusal type | List: true refusal, waiting for next period, ignored | Closer or chat manager | 11 |

In total: 21 fields, 5 of them filled automatically.

- **FL3** Lead author is set by the system once and is never overwritten.
- **FL4** Blocking rule: a deal cannot move on to the next stage until the required fields of its current
  stage are filled. Without this, the data is never collected.
- **FL5** Warm-up touches counts up by itself while the deal is in Warm-up.
- **FL6** Start period fills in by itself from a date once the client prepays.

## 7. Priority automations

The first release has eight scenarios. Everything else is a second phase and is not part of this quote.

| Id | Trigger | Action |
|---|---|---|
| **A1** | A website form is submitted | Create the deal, fill source and request type, record the lead author |
| **A2** | A deal is created | A task "Reply" due in 30 minutes; the first response time is recorded automatically |
| **A3** | A grade is set | Grade A goes to stage 4; grades B and C go to stage 3 |
| **A4** | A key call is booked | The closer becomes the owner, a meeting is created, and the slot must be at least 3 hours ahead |
| **A5** | 24 hours and 1 hour before the key call | Two confirmation tasks |
| **A6** | The key call is held | The call recording is attached; a task "Day +1: record the objection" |
| **A7** | A refusal, or 5 to 7 days with no reply | The deal moves to pipeline 2 automatically, with a tag |
| **A8** | The prepayment arrives | The target date for the full payment is calculated; two control tasks |

Second phase, quoted separately: a closing sequence of touches, scheduled reactivation campaigns, a limit
on warm-up touches, tasks for the assistant, automatic tags for repeat sales.

- **RR1** Switch off round-robin distribution of leads. Closers are chosen by who has a free slot, so
  nothing reassigns deals automatically except A4.

## 8. Access rights

| Id | Role | Access |
|---|---|---|
| **AC1** | Head of sales | All pipelines, reports, settings, export |
| **AC2** | Owner | Reads everything, reports, export |
| **AC3** | Closer | Own deals in pipeline 1 from stage 4; cannot delete or export |
| **AC4** | Chat manager | Pipelines 1 and 2 in full; cannot delete or export |
| **AC5** | Assistant | Stages 9 and 10 of pipeline 1 only |

## 9. Export to Google Sheets

- **EX1** Direction: from the CRM to Google Sheets, one way. Nothing is written back.
- **EX2** Frequency: at least once an hour, plus a manual run.
- **EX3** Structure: one sheet of raw data, one row per deal, with these 25 columns: id, pipeline, stage,
  created date, source, request type, grade, segment, lead author, closer, key call booked on, key call
  date and time, key call outcome, key call result, objection, prepayment date, payment method, full
  payment date, amount, start period, refusal reason, refusal type, first response time, last activity
  date, close date.
- **EX4** Dashboard sheets built with formulas on top of the raw sheet, in 8 blocks: the month's funnel,
  conversion rates, by closer, by chat manager, unprocessed leads, enrollment forecast, sources with CPL
  and CAC, refusal reasons.

## 10. What we provide

- Admin access to Salesforce.
- Access to our payment platform, and confirmation that payment statuses can be read from it.
- The list of active traffic sources and their UTM tags.
- Access to the website forms, or the contact of the person who runs them.
- The messenger account used for chats.
- A Google account for the dashboard file.
- The reference lists of objections and refusal reasons, ready to load.
