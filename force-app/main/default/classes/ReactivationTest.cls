/**
 * A7: a refusal reason, or N days without a client reply (5 to 7), moves the same deal to Reactivation.
 */
@isTest
private class ReactivationTest {
    @isTest
    static void A7_refusalReasonMovesTheSameDealToReactivation() {
        Opportunity deal = TestData.deal(Pipelines.NEW_CLIENTS, Pipelines.WARM_UP, null);
        deal.Source__c = 'Partner';
        insert as system deal;
        update as system new Opportunity(Id = deal.Id, Refusal_Reason__c = 'Price', Refusal_Type__c = 'True refusal');
        Opportunity updated = TestData.reload(deal.Id);
        Assert.areEqual(Pipelines.REACTIVATION, updated.RecordType.DeveloperName, 'moved to Reactivation');
        Assert.areEqual(Pipelines.DEFERRED_DEMAND, updated.StageName, 'a true refusal lands on Deferred demand');
        Assert.areEqual('Partner', updated.Source__c, 'same record, same source');
        Assert.areEqual(1, [SELECT COUNT() FROM Opportunity WITH SYSTEM_MODE], 'nothing was copied');
    }

    @isTest
    static void A7_refusalTypePicksTheStage() {
        Opportunity waiting = TestData.deal(Pipelines.NEW_CLIENTS, Pipelines.CLOSING, UserInfo.getUserId());
        Opportunity ignored = TestData.deal(Pipelines.NEW_CLIENTS, Pipelines.NEW_LEAD, null);
        Opportunity repeat = TestData.deal(Pipelines.REPEAT_SALES, Pipelines.ANNOUNCEMENT, null);
        insert as system new List<Opportunity>{ waiting, ignored, repeat };
        update as system new List<Opportunity>{
            new Opportunity(Id = waiting.Id, Refusal_Reason__c = 'Timing', Refusal_Type__c = 'Waiting for next period'),
            new Opportunity(Id = ignored.Id, Refusal_Reason__c = 'Personal circumstances', Refusal_Type__c = 'Ignored'),
            new Opportunity(Id = repeat.Id, Refusal_Reason__c = 'Program does not fit', Refusal_Type__c = 'True refusal')
        };
        Assert.areEqual(Pipelines.WAITING_NEXT_PERIOD, TestData.reload(waiting.Id).StageName);
        Assert.areEqual(Pipelines.IGNORED, TestData.reload(ignored.Id).StageName);
        Opportunity fromRepeat = TestData.reload(repeat.Id);
        Assert.areEqual(Pipelines.REACTIVATION, fromRepeat.RecordType.DeveloperName, 'Repeat sales refusals move too');
        Assert.areEqual(Pipelines.DEFERRED_DEMAND, fromRepeat.StageName);
    }

    @isTest
    static void A7_silentDealsMoveAfterTheSetNumberOfDays() {
        Integer days = SalesSettings.silenceDays();
        Opportunity silentNew = TestData.deal(Pipelines.NEW_CLIENTS, Pipelines.NEW_LEAD, null);
        Opportunity repliedRecently = TestData.deal(Pipelines.NEW_CLIENTS, Pipelines.WARM_UP, null);
        repliedRecently.Last_Client_Reply_At__c = Datetime.now().addDays(-1);
        Opportunity silentClosing = TestData.deal(Pipelines.NEW_CLIENTS, Pipelines.CLOSING, UserInfo.getUserId());
        silentClosing.Last_Client_Reply_At__c = Datetime.now().addDays(-(days + 1));
        Opportunity prepaid = TestData.deal(Pipelines.NEW_CLIENTS, Pipelines.PREPAYMENT_RECEIVED, UserInfo.getUserId());
        insert as system new List<Opportunity>{ silentNew, repliedRecently, silentClosing, prepaid };
        Test.setCreatedDate(silentNew.Id, Datetime.now().addDays(-(days + 1)));
        Test.setCreatedDate(repliedRecently.Id, Datetime.now().addDays(-30));
        Test.setCreatedDate(prepaid.Id, Datetime.now().addDays(-30));

        Test.startTest();
        Database.executeBatch(new SilentDealsJob());
        Test.stopTest();

        for (Id movedId : new List<Id>{ silentNew.Id, silentClosing.Id }) {
            Opportunity moved = TestData.reload(movedId);
            Assert.areEqual(Pipelines.REACTIVATION, moved.RecordType.DeveloperName, 'silent deal moved');
            Assert.areEqual(Pipelines.IGNORED, moved.StageName, 'to Ignored');
            Assert.areEqual(SilentDealsJob.NO_REPLY, moved.Refusal_Reason__c, 'reason No reply');
            Assert.areEqual('Ignored', moved.Refusal_Type__c, 'tagged Ignored');
        }
        Assert.areEqual(Pipelines.WARM_UP, TestData.reload(repliedRecently.Id).StageName, 'a recent reply keeps the deal');
        Assert.areEqual(Pipelines.PREPAYMENT_RECEIVED, TestData.reload(prepaid.Id).StageName, 'a client who paid is not chased');
    }

    @isTest
    static void A7_silenceDaysStayBetweenFiveAndSeven() {
        Assert.areEqual(5, SalesSettings.silenceDays(3), 'below the range');
        Assert.areEqual(7, SalesSettings.silenceDays(9), 'above the range');
        Assert.areEqual(6, SalesSettings.silenceDays(6), 'inside the range');
        Assert.areEqual(SalesSettings.DEFAULT_SILENCE_DAYS, SalesSettings.silenceDays(null), 'no setting');
        Integer configured = SalesSettings.silenceDays();
        Assert.isTrue(configured >= 5 && configured <= 7, 'the deployed setting is in range: ' + configured);
    }

    @isTest
    static void A7_jobRunsEveryDay() {
        Test.startTest();
        Id jobId = SilentDealsJob.scheduleDaily();
        Test.stopTest();
        CronTrigger cron = [SELECT CronExpression FROM CronTrigger WHERE Id = :jobId WITH SYSTEM_MODE];
        Assert.areEqual(SilentDealsJob.DAILY_AT_SEVEN, cron.CronExpression, 'every day at 07:00');
    }
}
