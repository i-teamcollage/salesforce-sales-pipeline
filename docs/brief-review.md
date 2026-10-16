# Brief review

Before building, a consultant reads the brief for gaps and contradictions and asks the client. Each
question below came from [the brief](brief.md). Because this is a sample, we could not ask anyone, so each
one records the assumption we took and where it lives in the build. A client build starts with these
questions answered in a 30-minute call.

## Contradictions

**1. Five automatic fields, or seven?** Section 6 says 5 of the 21 fields are filled automatically, but
the table marks 7: source, request type, first response time, lead author, warm-up touches, key call
booked on and start period.
*Assumption:* the table is right. All 7 are filled by the system and are read-only for every role.
*Where:* FL1, FL3, FL5, FL6, A1, A2, A4.

**2. Pipeline 3, stage 2: "form filled, deal created".** The deal already exists at stage 1, so it cannot
be created when it leaves stage 2.
*Assumption:* the client fills the pre-registration form while the deal is at stage 2. No field records
the form, so we did not gate this stage. *Question:* should the pre-registration form create the repeat
deal itself, as A1 does for new clients? *Where:* PL3.

**3. "Back to Prepayment received" after a false objection.** A deal cannot go back to a stage it never
reached.
*Assumption:* a deal can wait at Conditional refusal without a refusal reason while a closer works on the
objection. If the objection was false and the client pays, the deal moves to Prepayment received and stays
in New clients. Only a filled refusal reason moves it out. *Where:* TR3, A7.

**4. Closers see "own deals in pipeline 1", but the owner changes only through A4.** After a refusal moves
a deal to Reactivation, the closer still owns it and so still sees it.
*Assumption:* we kept the rule that nothing reassigns deals except A4. *Question:* should a refusal hand
the deal back to the chat manager? It is one line in the A7 flow. *Where:* AC3, RR1.

## Rules the brief does not give

**5. Target date for the full payment (A8).** No rule is given.
*Assumption:* a setting per payment method in Custom Metadata (`Payment_Term__mdt`): days from the
prepayment to the target date, and how many days before it the reminder task falls. Placeholder values:
7 days for a single payment, 10 for bank instalments, 14 for in-house instalments, reminder 2 days before.
The head of sales can change them without code. *Where:* A8.

**6. CPL and CAC need ad spend, which is not in the CRM.** The dashboard block "sources with CPL and CAC"
cannot be computed from deals alone.
*Assumption:* the spreadsheet gets one input sheet, "Ad spend" (month, source, spend). It is the only
thing typed by hand, an exception to the "nobody types" rule. CPL and CAC stay empty until spend is
entered. A client build replaces the sheet with an import from the ad accounts. *Where:* EX4.

**7. Start period "filled from a date".** The brief says it is a list filled automatically, but not from
which date or how.
*Assumption:* cohorts start monthly, and a client joins the cohort of the month after the prepayment. The
field is a formula (`YYYY-MM`) instead of a list, so it cannot drift and nobody has to add a new value
every month. It still groups like a list in the dashboard. *Where:* FL6.

**8. Which Reactivation stage a refusal lands in.** Not given.
*Assumption:* by refusal type. True refusal goes to Deferred demand, waiting for next period goes to
Waiting for next period, ignored goes to Ignored. *Where:* A7.

**9. Which stages the "5 to 7 days silent" rule covers.** Not given.
*Assumption:* New clients stages 1 to 7 and Conditional refusal. From Prepayment received on, the client
has paid, so silence is not a refusal. The day count is a setting (`Sales_Setting__mdt`, default 5). A
validation rule on the setting keeps it between 5 and 7. *Where:* A7.

**10. How the CRM knows the client replied.** The messenger is not connected (integrations are out of
scope).
*Assumption:* a field "Last client reply" that the messenger integration fills in a client build. Until
then the chat manager sets it. When it is empty, the deal's creation time counts. *Where:* A7.

**11. Who receives the A5, A6 and A8 tasks.** The brief names the stage owner (the chat manager), not a
person.
*Assumption:* the deal's lead author, who is the chat manager who worked the lead. If that user is
missing, the deal owner gets the task. *Where:* A5, A6, A8.

**12. A key call booked less than 24 hours ahead.** The 24-hour confirmation would be due in the past.
*Assumption:* it is created due immediately. *Where:* A5.

**13. Rescheduled calls.** "Rescheduled" is an outcome value, but the brief does not say what moves.
*Assumption:* a reschedule is a new booking. The meeting and both confirmation tasks move to the new time,
the booking date becomes the day of the new booking, and the 3-hour rule applies again. *Where:* A4, A5.

**14. A form sent again by someone who already has an open deal.** A1 would open a second deal, which is
exactly the double counting the brief warns about.
*Assumption:* no second deal. A task "The client sent the form again" goes to the open deal instead. A
person whose deals are all closed gets a new deal on their existing account. *Where:* A1.

**15. Where the source comes from.** "Filled from the form", but forms carry UTM tags, not our list
values.
*Assumption:* the form sends the raw `utm_source`. A mapping in Custom Metadata (`Source_Mapping__mdt`)
turns it into a source from the list. No tag means Website; an unknown tag means Other. A lead is never
lost because the website sent an unexpected value. *Where:* A1.

**16. A2 on every new deal.** The brief says "a deal is created", so repeat-sales deals created in bulk
would each get a 30-minute reply task.
*Assumption:* as written, A2 runs for every new deal in the three pipelines. *Question:* should it run for
New clients only? *Where:* A2.

**17. A3 in Repeat sales.** Repeat sales has no Warm-up stage.
*Assumption:* A3 routes New clients deals only. *Where:* A3.

## Values the brief does not list

**18. The lists themselves.** The three qualification criteria, the two request types, the four segments,
the three payment methods, the sources, objections and refusal reasons are not named. Section 10 says the
client provides objections and refusal reasons.
*Assumption:* placeholder values that fit a cohort-based school:

| List | Values used |
|---|---|
| Qualification: goal | Career change, Promotion, New skill, Not clear yet |
| Qualification: budget | Ready to pay, Needs instalments, No budget yet |
| Qualification: timing | This cohort, Next cohort, Later |
| Request type | Application, Consultation |
| Segment | Career switcher, Specialist upskilling, Manager, Graduate |
| Payment method | Single payment, Bank instalments, In-house instalments |
| Source | Website, Search ads, Paid social, Email newsletter, Referral, Partner, Repeat client base, Other |
| Objection | Price, Timing, Doubts about results, Needs to consult someone, Format does not fit, Comparing schools |
| Refusal reason | Price, Timing, Chose another provider, Program does not fit, Personal circumstances, No reply |

Sources, segments, objections and refusal reasons are global value sets, so the client's lists replace
ours in one file each. "No reply" is the reason the silence rule records (A7), so every deal in
Reactivation has a reason, as stage 11 requires. *Where:* FL2.

**19. Things the automations need but the table lacks.** A6 attaches a call recording, A7 needs the time
of the last client reply, A8 calculates a target date, and A7 and TR2 use tags.
*Assumption:* one extra deal field, Last client reply. The rest lives where Salesforce keeps such things,
so the deal stays within 25 custom fields:
- the recording link sits on the key-call meeting that A4 creates (that is where call software logs
  recordings), and the deal cannot move to Key call held without it;
- the target full-payment date is the due date of the A8 check task;
- the tag "Ignored" is the refusal type Ignored with the reason No reply, which only the silence rule sets;
- the repeat-segment tag is a Repeat segment box on the client's account, ticked by hand;
- the "period tag" at stage 10 is the Start period field.
*Where:* A6, A7, A8, TR2.

**20. Chat managers see "pipelines 1 and 2", but every Repeat sales stage is theirs.** Section 8 and
section 4 disagree.
*Assumption:* chat managers see all of New clients and Reactivation (a sharing rule) plus the Repeat sales
deals they create (they own them). *Question:* should they also see repeat deals created by the head of
sales? *Where:* AC4.

## How the brief maps to Salesforce

**21. Stage gating.** "Required from stage N" means the field must be filled to move past stage N. A
formula field gives each stage its position in New clients, and one validation rule per field checks it.
Repeat sales stages sit on the same scale: stages 1 and 2 before qualification, stage 3 as the
qualification step, stage 4 as the shared Key call scheduled. Reactivation, Conditional refusal and
Closed Lost are not gated, because a deal can refuse at any stage. Refusal reason and refusal type, the
stage 11 fields, are required for every deal in Reactivation.

**22. Moving between pipelines.** A pipeline is a record type with its own sales process. Moving is a
record type change on the same Opportunity, so the Id and the source survive. A repeat-sales deal joins
New clients at Key call scheduled, the stage both pipelines share, as soon as its call is booked (A4).
Stages 5 to 10 therefore exist once. A deal returning from Reactivation must land at Key call scheduled,
and its old refusal reason, type and Ignored tag are cleared, so a second refusal triggers A7 again.

**23. Stage name.** Salesforce orgs ship a built-in stage called "Qualification", often inactive. Stage 2
is called "Qualification in chat" so it never clashes with it.

**24. Settings and export rights.** "Settings" for the head of sales means Customize Application, which
lets them edit the Custom Metadata settings above. Salesforce grants it only together with Manage Custom
Permissions and Manage Translation, so their permission set has those two as well. A permission set cannot
take away a right that a profile grants, so closers and chat managers get the "Minimum Access - Salesforce"
profile and all their rights from their role's permission set. That is how they end up with neither Delete
nor Export Reports.

**25. Round-robin.** The project ships no assignment rules. Web leads belong to the default lead creator
set in the Web-to-Lead settings (the chat manager), and the deal keeps that owner until A4.

**26. Close date.** Salesforce needs one. New deals get today plus 30 days, and closing a deal sets it to
the day it closed, which is the "close date" column of the export.

**27. Last activity date.** The export uses Salesforce's own Last Activity date (latest task or event).
