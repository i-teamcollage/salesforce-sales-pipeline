/**
 * TR1 to TR4: moving between pipelines keeps the same record, its Id and its source.
 */
@isTest
private class TransitionsTest {
    @isTest
    static void TR1_returnFromReactivationKeepsTheSameRecord() {
        Opportunity deal = TestData.deal(Pipelines.NEW_CLIENTS, Pipelines.WARM_UP, null);
        deal.Source__c = 'Search ads';
        insert deal;

        update new Opportunity(Id = deal.Id, Refusal_Reason__c = 'Timing', Refusal_Type__c = 'Waiting for next period');
        Opportunity refused = TestData.reload(deal.Id);
        Assert.areEqual(Pipelines.REACTIVATION, refused.RecordType.DeveloperName, 'the refusal moved it to Reactivation');

        update new Opportunity(Id = deal.Id, RecordTypeId = Pipelines.recordTypeId(Pipelines.NEW_CLIENTS),
            StageName = Pipelines.KEY_CALL_SCHEDULED);
        Opportunity back = TestData.reload(deal.Id);
        Assert.areEqual(Pipelines.NEW_CLIENTS, back.RecordType.DeveloperName, 'back in New clients');
        Assert.areEqual(Pipelines.KEY_CALL_SCHEDULED, back.StageName, 'at Key call scheduled');
        Assert.areEqual('Search ads', back.Source__c, 'the source survives the round trip');
        Assert.isNull(back.Refusal_Reason__c, 'the old refusal reason is cleared');
        Assert.isNull(back.Refusal_Type__c, 'the old refusal type is cleared');
        Assert.areEqual(1, [SELECT COUNT() FROM Opportunity], 'no second deal was created');
    }

    @isTest
    static void TR1_returnMustLandAtKeyCallScheduled() {
        Opportunity deal = TestData.insertDeal(Pipelines.REACTIVATION, Pipelines.DEFERRED_DEMAND, null);
        Database.SaveResult result = Database.update(new Opportunity(Id = deal.Id,
            RecordTypeId = Pipelines.recordTypeId(Pipelines.NEW_CLIENTS), StageName = Pipelines.QUALIFICATION), false);
        Assert.isTrue(TestData.failedWith(result, PipelineTransitions.RETURN_STAGE_MESSAGE), String.valueOf(result.getErrors()));
    }

    @isTest
    static void TR1_returnRequiresRequalification() {
        Opportunity deal = TestData.deal(Pipelines.REACTIVATION, Pipelines.IGNORED, null);
        deal.Grade__c = null;
        insert deal;
        Database.SaveResult result = Database.update(new Opportunity(Id = deal.Id,
            RecordTypeId = Pipelines.recordTypeId(Pipelines.NEW_CLIENTS), StageName = Pipelines.KEY_CALL_SCHEDULED), false);
        Assert.isTrue(TestData.failedWith(result, 'To move past Qualification in chat'), String.valueOf(result.getErrors()));
    }

    @isTest
    static void TR2_wonDealInRepeatSegmentIsNotMovedOrCopied() {
        Account client = new Account(Name = 'Mira Talvik');
        insert client;
        Opportunity deal = TestData.deal(Pipelines.NEW_CLIENTS, Pipelines.CLOSED_WON, UserInfo.getUserId());
        deal.AccountId = client.Id;
        insert deal;

        update new Account(Id = client.Id, Repeat_Segment__c = true);
        Opportunity updated = TestData.reload(deal.Id);
        Assert.areEqual(Pipelines.CLOSED_WON, updated.StageName, 'the won deal stays won');
        Assert.areEqual(Pipelines.NEW_CLIENTS, updated.RecordType.DeveloperName, 'and stays in New clients');
        Assert.areEqual(1, [SELECT COUNT() FROM Opportunity], 'no repeat-sales deal is created automatically');
        Assert.isTrue([SELECT Repeat_Segment__c FROM Account WHERE Id = :client.Id].Repeat_Segment__c, 'the client carries the tag');
    }

    @isTest
    static void TR3_falseObjectionGoesBackToPrepaymentInsideNewClients() {
        Opportunity deal = TestData.insertDeal(Pipelines.NEW_CLIENTS, Pipelines.CLOSING, UserInfo.getUserId());
        update new Opportunity(Id = deal.Id, StageName = Pipelines.CONDITIONAL_REFUSAL);
        Assert.areEqual(Pipelines.NEW_CLIENTS, TestData.reload(deal.Id).RecordType.DeveloperName,
            'without a refusal reason the deal waits in New clients');

        update new Opportunity(Id = deal.Id, StageName = Pipelines.PREPAYMENT_RECEIVED,
            Objection__c = 'Price', Decision_Control_Date__c = Date.today());
        Opportunity updated = TestData.reload(deal.Id);
        Assert.areEqual(Pipelines.PREPAYMENT_RECEIVED, updated.StageName, 'back to Prepayment received');
        Assert.areEqual(Pipelines.NEW_CLIENTS, updated.RecordType.DeveloperName, 'never left New clients');
    }

    @isTest
    static void TR4_repeatDealContinuesInNewClientsWhenItsCallIsBooked() {
        Opportunity deal = TestData.deal(Pipelines.REPEAT_SALES, Pipelines.KEY_CALL_SCHEDULED, null);
        deal.Source__c = 'Repeat client base';
        insert deal;

        update new Opportunity(Id = deal.Id, Key_Call_At__c = Datetime.now().addDays(2), Closer__c = UserInfo.getUserId());
        Opportunity updated = TestData.reload(deal.Id);
        Assert.areEqual(deal.Id, updated.Id, 'same record');
        Assert.areEqual(Pipelines.NEW_CLIENTS, updated.RecordType.DeveloperName, 'continues in New clients');
        Assert.areEqual(Pipelines.KEY_CALL_SCHEDULED, updated.StageName, 'at the shared Key call scheduled');
        Assert.areEqual('Repeat client base', updated.Source__c, 'the source survives');
        Assert.areEqual(1, [SELECT COUNT() FROM Opportunity], 'nothing was cloned');
    }
}
