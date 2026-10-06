/**
 * FL1, FL2, FL3, FL5, FL6: the brief's fields, their lists, and the fields the system fills.
 * Stage gating (FL4) is in StageGatingTest.
 */
@isTest
private class FieldsTest {
    private static final Map<String, Schema.DisplayType> BRIEF_FIELDS = new Map<String, Schema.DisplayType>{
        'Source__c' => Schema.DisplayType.PICKLIST,
        'Request_Type__c' => Schema.DisplayType.PICKLIST,
        'First_Response_At__c' => Schema.DisplayType.DATETIME,
        'Lead_Author__c' => Schema.DisplayType.REFERENCE,
        'Qualification_Goal__c' => Schema.DisplayType.PICKLIST,
        'Qualification_Budget__c' => Schema.DisplayType.PICKLIST,
        'Qualification_Timing__c' => Schema.DisplayType.PICKLIST,
        'Grade__c' => Schema.DisplayType.PICKLIST,
        'Segment__c' => Schema.DisplayType.PICKLIST,
        'Warm_Up_Touches__c' => Schema.DisplayType.DOUBLE,
        'Key_Call_Booked_On__c' => Schema.DisplayType.DATE,
        'Key_Call_At__c' => Schema.DisplayType.DATETIME,
        'Closer__c' => Schema.DisplayType.REFERENCE,
        'Key_Call_Outcome__c' => Schema.DisplayType.PICKLIST,
        'Key_Call_Result__c' => Schema.DisplayType.PICKLIST,
        'Objection__c' => Schema.DisplayType.PICKLIST,
        'Decision_Control_Date__c' => Schema.DisplayType.DATE,
        'Prepayment_Date__c' => Schema.DisplayType.DATE,
        'Payment_Method__c' => Schema.DisplayType.PICKLIST,
        'Full_Payment_Date__c' => Schema.DisplayType.DATE,
        'Start_Period__c' => Schema.DisplayType.STRING,
        'Refusal_Reason__c' => Schema.DisplayType.PICKLIST,
        'Refusal_Type__c' => Schema.DisplayType.PICKLIST
    };

    private static final Map<String, List<String>> LISTS = new Map<String, List<String>>{
        'Request_Type__c' => new List<String>{ 'Application', 'Consultation' },
        'Grade__c' => new List<String>{ 'A', 'B', 'C' },
        'Segment__c' => new List<String>{ 'Career switcher', 'Specialist upskilling', 'Manager', 'Graduate' },
        'Key_Call_Outcome__c' => new List<String>{ 'Held', 'No-show', 'Rescheduled', 'Cancelled' },
        'Key_Call_Result__c' => new List<String>{ 'Purchase', 'Thinking', 'Refusal' },
        'Payment_Method__c' => new List<String>{ 'Single payment', 'Bank instalments', 'In-house instalments' },
        'Refusal_Type__c' => new List<String>{ 'True refusal', 'Waiting for next period', 'Ignored' }
    };

    private static List<String> activeValues(Schema.DescribeFieldResult field) {
        List<String> values = new List<String>();
        for (Schema.PicklistEntry entry : field.getPicklistValues()) {
            if (entry.isActive()) {
                values.add(entry.getValue());
            }
        }
        return values;
    }

    @isTest
    static void FL1_dealCarriesTheTwentyThreeBriefFields() {
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.Opportunity.fields.getMap();
        Assert.areEqual(23, BRIEF_FIELDS.size(), '21 rows, 23 fields');
        for (String name : BRIEF_FIELDS.keySet()) {
            Assert.isTrue(fields.containsKey(name), name + ' exists');
            Schema.DescribeFieldResult describe = fields.get(name).getDescribe();
            Assert.areEqual(BRIEF_FIELDS.get(name), describe.getType(), name + ' has the brief type');
            if (describe.getType() == Schema.DisplayType.REFERENCE) {
                Assert.areEqual(User.SObjectType, describe.getReferenceTo()[0], name + ' points to a user');
            }
        }
        Assert.isTrue(fields.get('Start_Period__c').getDescribe().isCalculated(), 'start period is filled by the system');
    }

    @isTest
    static void FL2_listFieldsAreRestrictedPicklists() {
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.Opportunity.fields.getMap();
        for (String name : BRIEF_FIELDS.keySet()) {
            Schema.DescribeFieldResult describe = fields.get(name).getDescribe();
            if (describe.getType() == Schema.DisplayType.PICKLIST) {
                Assert.isTrue(describe.isRestrictedPicklist(), name + ' accepts only its list');
                Assert.isFalse(activeValues(describe).isEmpty(), name + ' has values');
            }
        }
        for (String name : LISTS.keySet()) {
            Assert.areEqual(LISTS.get(name), activeValues(fields.get(name).getDescribe()), name + ' values');
        }
        Database.SaveResult free = Database.insert(new Opportunity(Name = 'Free text', StageName = 'New lead',
            CloseDate = Date.today(), RecordTypeId = Pipelines.recordTypeId(Pipelines.NEW_CLIENTS),
            Grade__c = 'Very good'), false);
        Assert.isFalse(free.isSuccess(), 'a value outside the list is refused');
    }

    @isTest
    static void FL3_leadAuthorIsSetOnceAndNeverChanges() {
        TestData.createTeam();
        User chatManager = TestData.user('chatmgr');
        User head = TestData.user('head');
        Opportunity deal = TestData.deal(Pipelines.NEW_CLIENTS, Pipelines.NEW_LEAD, null);
        deal.OwnerId = chatManager.Id;
        deal.Lead_Author__c = head.Id;
        insert deal;
        Assert.areEqual(chatManager.Id, TestData.reload(deal.Id).Lead_Author__c, 'the owner at creation, not what was typed');

        Database.SaveResult change = Database.update(new Opportunity(Id = deal.Id, Lead_Author__c = head.Id), false);
        Assert.isTrue(TestData.failedWith(change, 'The lead author is set once'), String.valueOf(change.getErrors()));

        update new Opportunity(Id = deal.Id, Key_Call_At__c = Datetime.now().addDays(1), Closer__c = TestData.user('closer1').Id);
        Opportunity updated = TestData.reload(deal.Id);
        Assert.areEqual(TestData.user('closer1').Id, updated.OwnerId, 'A4 handed the deal to the closer');
        Assert.areEqual(chatManager.Id, updated.Lead_Author__c, 'the lead author survives the hand-over');
    }

    @isTest
    static void FL5_warmUpTouchesCountCompletedTasksDuringWarmUp() {
        Opportunity deal = TestData.insertDeal(Pipelines.NEW_CLIENTS, Pipelines.WARM_UP, null);
        insert new List<Task>{
            new Task(WhatId = deal.Id, Subject = 'Sent the program guide', Status = 'Completed'),
            new Task(WhatId = deal.Id, Subject = 'Shared a graduate story', Status = 'Completed')
        };
        Task open = new Task(WhatId = deal.Id, Subject = 'Follow up on the guide', Status = 'Not Started');
        insert open;
        Assert.areEqual(2, TestData.reload(deal.Id).Warm_Up_Touches__c.intValue(), 'two completed touches');

        update new Task(Id = open.Id, Status = 'Completed');
        Assert.areEqual(3, TestData.reload(deal.Id).Warm_Up_Touches__c.intValue(), 'completing a task counts');

        update new Opportunity(Id = deal.Id, StageName = Pipelines.KEY_CALL_SCHEDULED);
        insert new Task(WhatId = deal.Id, Subject = 'After warm-up', Status = 'Completed');
        Assert.areEqual(3, TestData.reload(deal.Id).Warm_Up_Touches__c.intValue(), 'only Warm-up touches count');
    }

    @isTest
    static void FL6_startPeriodIsTheMonthAfterThePrepayment() {
        Opportunity deal = TestData.deal(Pipelines.NEW_CLIENTS, Pipelines.NEW_LEAD, null);
        deal.Prepayment_Date__c = Date.newInstance(2026, 10, 5);
        insert deal;
        Assert.areEqual('2026-11', TestData.reload(deal.Id).Start_Period__c);

        update new Opportunity(Id = deal.Id, Prepayment_Date__c = Date.newInstance(2026, 12, 14));
        Assert.areEqual('2027-01', TestData.reload(deal.Id).Start_Period__c, 'the year rolls over');

        update new Opportunity(Id = deal.Id, Prepayment_Date__c = null);
        Assert.isTrue(String.isBlank(TestData.reload(deal.Id).Start_Period__c), 'empty until the client prepays');
    }
}
