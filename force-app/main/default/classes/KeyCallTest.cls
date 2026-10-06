/**
 * A4: booking the key call hands the deal to the closer, stamps the booking date and creates the meeting,
 * at least 3 hours ahead. A5: two confirmation tasks, 24 hours and 1 hour before the call.
 */
@isTest
private class KeyCallTest {
    @testSetup
    static void team() {
        TestData.createTeam();
    }

    private static Opportunity readyToBook() {
        Opportunity deal = TestData.deal(Pipelines.NEW_CLIENTS, Pipelines.KEY_CALL_SCHEDULED, null);
        deal.OwnerId = TestData.user('chatmgr').Id;
        insert deal;
        return deal;
    }

    private static List<Task> confirmations(Id dealId) {
        Set<String> automations = new Set<String>{ Activities.A5_CONFIRM_24H, Activities.A5_CONFIRM_1H };
        return [
            SELECT Automation__c, Due_At__c, OwnerId, IsReminderSet, ReminderDateTime FROM Task
            WHERE WhatId = :dealId AND Automation__c IN :automations AND IsClosed = FALSE
            ORDER BY Due_At__c
        ];
    }

    @isTest
    static void A4_bookingHandsTheDealToTheCloserAndCreatesTheMeeting() {
        Opportunity deal = readyToBook();
        User closer = TestData.user('closer1');
        Datetime callAt = TestData.hoursAhead(48);
        update new Opportunity(Id = deal.Id, Key_Call_At__c = callAt, Closer__c = closer.Id);

        Opportunity booked = TestData.reload(deal.Id);
        Assert.areEqual(closer.Id, booked.OwnerId, 'the closer becomes the owner');
        Assert.areEqual(Date.today(), booked.Key_Call_Booked_On__c, 'booking date stamped');
        Event meeting = [SELECT OwnerId, StartDateTime, EndDateTime FROM Event WHERE WhatId = :deal.Id AND Automation__c = :Activities.A4_KEY_CALL];
        Assert.areEqual(closer.Id, meeting.OwnerId, 'the meeting is in the closer calendar');
        Assert.areEqual(callAt, meeting.StartDateTime, 'at the booked time');
        Assert.areEqual(callAt.addMinutes(KeyCallService.CALL_MINUTES), meeting.EndDateTime, 'for one hour');
    }

    @isTest
    static void A4_slotLessThanThreeHoursAheadIsRejected() {
        Opportunity deal = readyToBook();
        Database.SaveResult result = Database.update(new Opportunity(Id = deal.Id,
            Key_Call_At__c = Datetime.now().addHours(2), Closer__c = TestData.user('closer1').Id), false);
        Assert.isTrue(TestData.failedWith(result, 'at least 3 hours ahead'), String.valueOf(result.getErrors()));
    }

    @isTest
    static void A4_rescheduleMovesTheMeetingInsteadOfAddingOne() {
        Opportunity deal = readyToBook();
        Id closerId = TestData.user('closer1').Id;
        update new Opportunity(Id = deal.Id, Key_Call_At__c = Datetime.now().addDays(2), Closer__c = closerId);
        Datetime moved = TestData.hoursAhead(96);
        update new Opportunity(Id = deal.Id, Key_Call_At__c = moved);
        List<Event> meetings = [SELECT StartDateTime FROM Event WHERE WhatId = :deal.Id AND Automation__c = :Activities.A4_KEY_CALL];
        Assert.areEqual(1, meetings.size(), 'one meeting');
        Assert.areEqual(moved, meetings[0].StartDateTime, 'at the new time');
    }

    @isTest
    static void A5_twoConfirmationsDueTwentyFourHoursAndOneHourBefore() {
        Opportunity deal = readyToBook();
        Datetime callAt = TestData.hoursAhead(72);
        update new Opportunity(Id = deal.Id, Key_Call_At__c = callAt, Closer__c = TestData.user('closer1').Id);
        List<Task> tasks = confirmations(deal.Id);
        Assert.areEqual(2, tasks.size(), 'two confirmation tasks');
        Assert.areEqual(Activities.A5_CONFIRM_24H, tasks[0].Automation__c);
        Assert.areEqual(callAt.addHours(-24), tasks[0].Due_At__c, '24 hours before');
        Assert.areEqual(callAt.addHours(-1), tasks[1].Due_At__c, '1 hour before');
        for (Task task : tasks) {
            Assert.areEqual(TestData.user('chatmgr').Id, task.OwnerId, 'for the chat manager who had the lead');
            Assert.isTrue(task.IsReminderSet, 'with a reminder');
            Assert.areEqual(task.Due_At__c, task.ReminderDateTime, 'at the due time');
        }
    }

    @isTest
    static void A5_rescheduleMovesBothConfirmations() {
        Opportunity deal = readyToBook();
        update new Opportunity(Id = deal.Id, Key_Call_At__c = Datetime.now().addDays(3), Closer__c = TestData.user('closer1').Id);
        Datetime moved = TestData.hoursAhead(120);
        update new Opportunity(Id = deal.Id, Key_Call_At__c = moved);
        List<Task> tasks = confirmations(deal.Id);
        Assert.areEqual(2, tasks.size(), 'still two tasks, not four');
        Assert.areEqual(moved.addHours(-24), tasks[0].Due_At__c);
        Assert.areEqual(moved.addHours(-1), tasks[1].Due_At__c);
    }

    @isTest
    static void A5_callLessThanADayAheadIsConfirmedAtOnce() {
        Opportunity deal = readyToBook();
        Datetime startedAt = Datetime.now();
        update new Opportunity(Id = deal.Id, Key_Call_At__c = Datetime.now().addHours(5), Closer__c = TestData.user('closer1').Id);
        List<Task> tasks = confirmations(deal.Id);
        Assert.isTrue(tasks[0].Due_At__c >= startedAt.addSeconds(-1) && tasks[0].Due_At__c <= Datetime.now().addSeconds(1),
            'the 24-hour confirmation is due now: ' + tasks[0].Due_At__c);
    }
}
