/**
 * A6: a deal moves to Key call held only with the call recording, and the chat manager gets
 * "Day +1: record the objection".
 */
@isTest
private class CallHeldTest {
    @testSetup
    static void team() {
        TestData.createTeam();
    }

    private static Opportunity confirmedCall() {
        Opportunity deal = TestData.deal(Pipelines.NEW_CLIENTS, Pipelines.KEY_CALL_CONFIRMED, TestData.user('closer1').Id);
        deal.OwnerId = TestData.user('chatmgr').Id;
        insert deal;
        return deal;
    }

    @isTest
    static void A6_keyCallHeldNeedsTheRecording() {
        Opportunity deal = confirmedCall();
        Database.SaveResult result = Database.update(new Opportunity(Id = deal.Id, StageName = Pipelines.KEY_CALL_HELD), false);
        Assert.isTrue(TestData.failedWith(result, KeyCallService.RECORDING_MESSAGE), String.valueOf(result.getErrors()));
    }

    @isTest
    static void A6_recordingLetsTheDealMoveAndCreatesTheObjectionTask() {
        Opportunity deal = confirmedCall();
        Event meeting = [SELECT Id FROM Event WHERE WhatId = :deal.Id AND Automation__c = :Activities.A4_KEY_CALL];
        update new Event(Id = meeting.Id, Recording_URL__c = 'https://recordings.example/quorvale/call-7');
        update new Opportunity(Id = deal.Id, StageName = Pipelines.KEY_CALL_HELD);

        Assert.areEqual(Pipelines.KEY_CALL_HELD, TestData.reload(deal.Id).StageName, 'moved');
        Task objection = [SELECT OwnerId, ActivityDate, Subject FROM Task WHERE WhatId = :deal.Id AND Automation__c = :Activities.A6_OBJECTION];
        Assert.areEqual(Date.today().addDays(1), objection.ActivityDate, 'due the day after');
        Assert.areEqual(TestData.user('chatmgr').Id, objection.OwnerId, 'for the chat manager');
        Assert.areEqual('Day +1: record the objection', objection.Subject);
    }
}
