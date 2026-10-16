/**
 * FL4: a deal cannot move past a stage until the fields required from that stage are filled.
 * One case per gated field, then one deal walked through every stage with the automations running.
 * (The lead author is always set by the system, so FieldsTest.FL3 covers it.)
 */
@isTest
private class StageGatingTest {
    private static final List<List<String>> CASES = new List<List<String>>{
        // field, stage it is required from, the next stage
        new List<String>{ 'Source__c', 'New lead', 'Qualification in chat' },
        new List<String>{ 'Request_Type__c', 'New lead', 'Qualification in chat' },
        new List<String>{ 'First_Response_At__c', 'New lead', 'Qualification in chat' },
        new List<String>{ 'Qualification_Goal__c', 'Qualification in chat', 'Warm-up' },
        new List<String>{ 'Qualification_Budget__c', 'Qualification in chat', 'Warm-up' },
        new List<String>{ 'Qualification_Timing__c', 'Qualification in chat', 'Warm-up' },
        new List<String>{ 'Grade__c', 'Qualification in chat', 'Warm-up' },
        new List<String>{ 'Segment__c', 'Qualification in chat', 'Warm-up' },
        new List<String>{ 'Warm_Up_Touches__c', 'Warm-up', 'Key call scheduled' },
        new List<String>{ 'Key_Call_At__c', 'Key call scheduled', 'Key call confirmed' },
        new List<String>{ 'Closer__c', 'Key call scheduled', 'Key call confirmed' },
        new List<String>{ 'Key_Call_Booked_On__c', 'Key call scheduled', 'Key call confirmed' },
        new List<String>{ 'Key_Call_Outcome__c', 'Key call held', 'Closing' },
        new List<String>{ 'Key_Call_Result__c', 'Key call held', 'Closing' },
        new List<String>{ 'Objection__c', 'Closing', 'Prepayment received' },
        new List<String>{ 'Decision_Control_Date__c', 'Closing', 'Prepayment received' },
        new List<String>{ 'Prepayment_Date__c', 'Prepayment received', 'Payment received' },
        new List<String>{ 'Payment_Method__c', 'Prepayment received', 'Payment received' },
        new List<String>{ 'Full_Payment_Date__c', 'Payment received', 'Handed over to preparation' }
    };

    @isTest
    static void FL4_eachRequiredFieldBlocksItsStage() {
        List<Opportunity> deals = new List<Opportunity>();
        for (List<String> gate : CASES) {
            Opportunity deal = TestData.deal(Pipelines.NEW_CLIENTS, gate[2], UserInfo.getUserId());
            deal.StageName = gate[1];
            deals.add(deal);
        }
        insert as system deals;

        List<Opportunity> moves = new List<Opportunity>();
        for (Integer i = 0; i < CASES.size(); i++) {
            Opportunity move = new Opportunity(Id = deals[i].Id, StageName = CASES[i][2]);
            move.put(CASES[i][0], null);
            moves.add(move);
        }
        List<Database.SaveResult> results = Database.update(moves, false, AccessLevel.SYSTEM_MODE);
        for (Integer i = 0; i < CASES.size(); i++) {
            Assert.isTrue(TestData.failedWith(results[i], 'To move past ' + CASES[i][1]),
                CASES[i][0] + ' must block the move past ' + CASES[i][1] + ': ' + results[i].getErrors());
        }
    }

    @isTest
    static void FL4_refusalNeedsAReasonAndAType() {
        Opportunity noType = TestData.deal(Pipelines.REACTIVATION, Pipelines.DEFERRED_DEMAND, null);
        noType.Refusal_Type__c = null;
        Opportunity noReason = TestData.deal(Pipelines.REACTIVATION, Pipelines.DEFERRED_DEMAND, null);
        noReason.Refusal_Reason__c = null;
        for (Database.SaveResult result : Database.insert(new List<Opportunity>{ noType, noReason }, false, AccessLevel.SYSTEM_MODE)) {
            Assert.isTrue(TestData.failedWith(result, 'A refusal needs both'), String.valueOf(result.getErrors()));
        }
    }

    @isTest
    static void FL4_completeDealMovesThroughEveryStage() {
        Opportunity deal = TestData.insertDeal(Pipelines.NEW_CLIENTS, Pipelines.NEW_LEAD, null);
        Task reply = [SELECT Id FROM Task WHERE WhatId = :deal.Id AND Automation__c = :Activities.A2_REPLY WITH SYSTEM_MODE];
        update as system new Task(Id = reply.Id, Status = 'Completed');

        update as system new Opportunity(Id = deal.Id, StageName = Pipelines.QUALIFICATION, Qualification_Goal__c = 'New skill',
            Qualification_Budget__c = 'Needs instalments', Qualification_Timing__c = 'Next cohort', Segment__c = 'Manager');
        update as system new Opportunity(Id = deal.Id, Grade__c = 'A');
        Assert.areEqual(Pipelines.KEY_CALL_SCHEDULED, TestData.reload(deal.Id).StageName, 'A3 routed grade A');

        update as system new Opportunity(Id = deal.Id, Key_Call_At__c = Datetime.now().addDays(1), Closer__c = UserInfo.getUserId());
        update as system new Opportunity(Id = deal.Id, StageName = Pipelines.KEY_CALL_CONFIRMED);
        Event meeting = [SELECT Id FROM Event WHERE WhatId = :deal.Id AND Automation__c = :Activities.A4_KEY_CALL WITH SYSTEM_MODE];
        update as system new Event(Id = meeting.Id, Recording_URL__c = 'https://recordings.example/quorvale/call-1');
        update as system new Opportunity(Id = deal.Id, StageName = Pipelines.KEY_CALL_HELD);
        update as system new Opportunity(Id = deal.Id, StageName = Pipelines.CLOSING, Key_Call_Outcome__c = 'Held', Key_Call_Result__c = 'Purchase');
        update as system new Opportunity(Id = deal.Id, StageName = Pipelines.PREPAYMENT_RECEIVED, Objection__c = 'Timing',
            Decision_Control_Date__c = Date.today().addDays(2));
        update as system new Opportunity(Id = deal.Id, Prepayment_Date__c = Date.today(), Payment_Method__c = 'Single payment');
        update as system new Opportunity(Id = deal.Id, StageName = Pipelines.PAYMENT_RECEIVED);
        update as system new Opportunity(Id = deal.Id, StageName = Pipelines.HANDED_OVER, Full_Payment_Date__c = Date.today());
        update as system new Opportunity(Id = deal.Id, StageName = Pipelines.CLOSED_WON);

        Opportunity won = TestData.reload(deal.Id);
        Assert.areEqual(Pipelines.CLOSED_WON, won.StageName, 'the deal reached the end');
        Assert.areEqual(Date.today(), won.CloseDate, 'closing set the close date');
        Assert.areEqual(1, [SELECT COUNT() FROM Task WHERE WhatId = :deal.Id AND Automation__c = :Activities.A6_OBJECTION WITH SYSTEM_MODE]);
        Set<String> payment = new Set<String>{ Activities.A8_PAYMENT_REMINDER, Activities.A8_PAYMENT_CHECK };
        Assert.areEqual(2, [SELECT COUNT() FROM Task WHERE WhatId = :deal.Id AND Automation__c IN :payment WITH SYSTEM_MODE]);
    }
}
