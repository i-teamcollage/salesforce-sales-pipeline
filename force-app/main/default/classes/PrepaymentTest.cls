/**
 * A8: the prepayment sets the target date for the full payment (a setting per payment method)
 * and two control tasks for the chat manager.
 */
@isTest
private class PrepaymentTest {
    @testSetup
    static void team() {
        TestData.createTeam();
    }

    private static Opportunity atPrepayment() {
        Opportunity deal = TestData.deal(Pipelines.NEW_CLIENTS, Pipelines.PREPAYMENT_RECEIVED, TestData.user('closer1').Id);
        deal.OwnerId = TestData.user('chatmgr').Id;
        insert deal;
        return deal;
    }

    private static Map<String, Task> controlTasks(Id dealId) {
        Map<String, Task> tasks = new Map<String, Task>();
        Set<String> automations = new Set<String>{ Activities.A8_PAYMENT_REMINDER, Activities.A8_PAYMENT_CHECK };
        for (Task task : [
            SELECT Automation__c, ActivityDate, OwnerId FROM Task
            WHERE WhatId = :dealId AND Automation__c IN :automations AND IsClosed = FALSE
        ]) {
            tasks.put(task.Automation__c, task);
        }
        return tasks;
    }

    @isTest
    static void A8_prepaymentSetsTheTargetDateAndTwoControlTasks() {
        Opportunity deal = atPrepayment();
        Date paidOn = Date.today();
        update new Opportunity(Id = deal.Id, Prepayment_Date__c = paidOn, Payment_Method__c = 'Bank instalments');

        Date target = paidOn.addDays(SalesSettings.daysToFullPayment('Bank instalments'));
        Assert.areEqual(target, PaymentControl.targetDate(TestData.reload(deal.Id)), 'target date from the setting');
        Map<String, Task> tasks = controlTasks(deal.Id);
        Assert.areEqual(2, tasks.size(), 'two control tasks');
        Assert.areEqual(target, tasks.get(Activities.A8_PAYMENT_CHECK).ActivityDate, 'the check falls on the target date');
        Assert.areEqual(target.addDays(-SalesSettings.reminderDaysBefore('Bank instalments')),
            tasks.get(Activities.A8_PAYMENT_REMINDER).ActivityDate, 'the reminder comes first');
        Assert.areEqual(TestData.user('chatmgr').Id, tasks.get(Activities.A8_PAYMENT_CHECK).OwnerId, 'for the chat manager');
    }

    @isTest
    static void A8_everyPaymentMethodHasItsOwnTerm() {
        Map<String, Payment_Term__mdt> terms = new Map<String, Payment_Term__mdt>();
        for (Payment_Term__mdt term : Payment_Term__mdt.getAll().values()) {
            terms.put(term.Payment_Method__c, term);
        }
        for (Schema.PicklistEntry method : Opportunity.Payment_Method__c.getDescribe().getPicklistValues()) {
            Assert.isTrue(terms.containsKey(method.getValue()), 'a term for ' + method.getValue());
            Assert.areEqual(terms.get(method.getValue()).Days_To_Full_Payment__c.intValue(),
                SalesSettings.daysToFullPayment(method.getValue()), 'the setting is used for ' + method.getValue());
        }
        Assert.areEqual(7, SalesSettings.daysToFullPayment('Unknown method'), 'safe default');
        Assert.areEqual(SalesSettings.DEFAULT_REMINDER_DAYS, SalesSettings.reminderDaysBefore('Unknown method'), 'safe default');
    }

    @isTest
    static void A8_changingTheMethodMovesTheTasks() {
        Opportunity deal = atPrepayment();
        update new Opportunity(Id = deal.Id, Prepayment_Date__c = Date.today(), Payment_Method__c = 'Single payment');
        update new Opportunity(Id = deal.Id, Payment_Method__c = 'In-house instalments');
        Map<String, Task> tasks = controlTasks(deal.Id);
        Assert.areEqual(2, tasks.size(), 'still two tasks, not four');
        Assert.areEqual(Date.today().addDays(SalesSettings.daysToFullPayment('In-house instalments')),
            tasks.get(Activities.A8_PAYMENT_CHECK).ActivityDate, 'moved to the new target date');
    }
}
