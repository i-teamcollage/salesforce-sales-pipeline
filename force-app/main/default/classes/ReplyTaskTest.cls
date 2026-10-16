/**
 * A2: a new deal gets a "Reply" task due in 30 minutes; completing it stamps the first response time once.
 */
@isTest
private class ReplyTaskTest {
    @isTest
    static void A2_newDealGetsAReplyTaskDueInThirtyMinutes() {
        Datetime startedAt = Datetime.now();
        Opportunity deal = TestData.insertDeal(Pipelines.NEW_CLIENTS, Pipelines.NEW_LEAD, null);
        Datetime endedAt = Datetime.now();
        Task reply = [
            SELECT OwnerId, Due_At__c, IsClosed, Subject FROM Task
            WHERE WhatId = :deal.Id AND Automation__c = :Activities.A2_REPLY
            WITH SYSTEM_MODE
        ];
        Assert.areEqual(deal.OwnerId, reply.OwnerId, 'for the deal owner');
        Assert.isFalse(reply.IsClosed, 'open');
        Assert.isTrue(reply.Due_At__c >= startedAt.addMinutes(30).addSeconds(-1) && reply.Due_At__c <= endedAt.addMinutes(30).addSeconds(1),
            'due 30 minutes after creation: ' + reply.Due_At__c);
    }

    @isTest
    static void A2_completingTheReplyStampsTheFirstResponseOnce() {
        Opportunity deal = TestData.insertDeal(Pipelines.NEW_CLIENTS, Pipelines.NEW_LEAD, null);
        Assert.isNull(deal.First_Response_At__c, 'no response yet');
        Task reply = [SELECT Id FROM Task WHERE WhatId = :deal.Id AND Automation__c = :Activities.A2_REPLY WITH SYSTEM_MODE];
        update as system new Task(Id = reply.Id, Status = 'Completed');
        Datetime stamped = TestData.reload(deal.Id).First_Response_At__c;
        Assert.isNotNull(stamped, 'stamped when the reply task is completed');

        Task another = new Task(WhatId = deal.Id, Subject = 'Reply to the client', Automation__c = Activities.A2_REPLY,
            Status = 'Not Started', OwnerId = UserInfo.getUserId());
        insert as system another;
        update as system new Task(Id = another.Id, Status = 'Completed');
        Assert.areEqual(stamped, TestData.reload(deal.Id).First_Response_At__c, 'stamped once, never moved');
    }

    @isTest
    static void A2_everyPipelineGetsTheReplyTask() {
        Opportunity repeat = TestData.insertDeal(Pipelines.REPEAT_SALES, Pipelines.BUILDING_BASE, null);
        Assert.areEqual(1, [SELECT COUNT() FROM Task WHERE WhatId = :repeat.Id AND Automation__c = :Activities.A2_REPLY WITH SYSTEM_MODE],
            'the brief says every new deal');
        // No record type: the running user's default, the master record type (Salesforce refuses its id when named).
        Opportunity other = new Opportunity(Name = 'Outside the pipelines', StageName = 'Qualify', CloseDate = Date.today());
        insert as system other;
        Assert.areEqual(0, [SELECT COUNT() FROM Task WHERE WhatId = :other.Id WITH SYSTEM_MODE], 'other opportunities are left alone');
    }
}
