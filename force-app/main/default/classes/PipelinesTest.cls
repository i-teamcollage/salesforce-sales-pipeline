/**
 * PL1 to PL3: the three pipelines, their stages in the brief's order, and no stage from another pipeline.
 */
@isTest
private class PipelinesTest {
    private static final List<String> NEW_CLIENTS_STAGES = new List<String>{
        'New lead', 'Qualification in chat', 'Warm-up', 'Key call scheduled', 'Key call confirmed',
        'Key call held', 'Closing', 'Prepayment received', 'Payment received', 'Handed over to preparation',
        'Conditional refusal'
    };
    private static final List<String> REACTIVATION_STAGES = new List<String>{
        'Deferred demand', 'Waiting for next period', 'Ignored', 'Regular touches', 'Dialogue resumed'
    };
    private static final List<String> REPEAT_SALES_STAGES = new List<String>{
        'Building the base', 'Announcement and pre-registration', 'Clarifying the situation', 'Key call scheduled'
    };

    /** The stages as Salesforce orders them (the sales process shows them in this order). */
    private static List<String> salesforceOrder(List<String> stages) {
        Set<String> wanted = new Set<String>(stages);
        List<String> ordered = new List<String>();
        for (Schema.PicklistEntry entry : Opportunity.StageName.getDescribe().getPicklistValues()) {
            if (wanted.contains(entry.getValue()) && entry.isActive()) {
                ordered.add(entry.getValue());
            }
        }
        return ordered;
    }

    private static void assertPipelineAccepts(String pipeline, List<String> stages) {
        Schema.RecordTypeInfo info = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get(pipeline);
        Assert.isNotNull(info, 'record type ' + pipeline + ' exists');
        Assert.isTrue(info.isActive(), 'record type ' + pipeline + ' is active');
        Assert.areEqual(stages, salesforceOrder(stages), 'stages of ' + pipeline + ' in the brief order');
        List<Opportunity> deals = new List<Opportunity>();
        for (String stage : stages) {
            deals.add(TestData.deal(pipeline, stage, UserInfo.getUserId()));
        }
        List<Database.SaveResult> results = Database.insert(deals, false, AccessLevel.SYSTEM_MODE);
        for (Integer i = 0; i < results.size(); i++) {
            Assert.isTrue(results[i].isSuccess(), stages[i] + ' is accepted in ' + pipeline + ': ' + results[i].getErrors());
        }
    }

    private static void assertRejected(String pipeline, String foreignStage) {
        // No closer, so no key call is booked: a booking moves a repeat-sales deal on to New clients (TR4).
        Database.SaveResult result = Database.insert(TestData.deal(pipeline, foreignStage, null), false, AccessLevel.SYSTEM_MODE);
        Assert.isTrue(TestData.failedWith(result, 'This stage is not in the deal'),
            foreignStage + ' must be rejected in ' + pipeline + ': ' + result.getErrors());
    }

    @isTest
    static void PL1_newClientsHasElevenStagesInOrder() {
        assertPipelineAccepts(Pipelines.NEW_CLIENTS, NEW_CLIENTS_STAGES);
        List<Opportunity> deals = [SELECT StageName, Stage_Order__c FROM Opportunity WHERE RecordType.DeveloperName = 'New_Clients' WITH SYSTEM_MODE];
        Assert.areEqual(11, deals.size(), 'one deal per stage');
        for (Opportunity deal : deals) {
            Integer expected = deal.StageName == 'Conditional refusal' ? 0 : NEW_CLIENTS_STAGES.indexOf(deal.StageName) + 1;
            Assert.areEqual(expected, deal.Stage_Order__c.intValue(), 'stage order of ' + deal.StageName);
        }
    }

    @isTest
    static void PL1_stageFromAnotherPipelineIsRejected() {
        assertRejected(Pipelines.NEW_CLIENTS, 'Ignored');
        assertRejected(Pipelines.NEW_CLIENTS, 'Building the base');
    }

    @isTest
    static void PL2_reactivationHasFiveStagesInOrder() {
        assertPipelineAccepts(Pipelines.REACTIVATION, REACTIVATION_STAGES);
        assertRejected(Pipelines.REACTIVATION, 'Closing');
        for (Opportunity deal : [SELECT Stage_Order__c FROM Opportunity WHERE RecordType.DeveloperName = 'Reactivation' WITH SYSTEM_MODE]) {
            Assert.areEqual(0, deal.Stage_Order__c.intValue(), 'Reactivation stages are not gated');
        }
    }

    @isTest
    static void PL3_repeatSalesHasFourStagesAndNoCopiesOfStagesFiveToTen() {
        assertPipelineAccepts(Pipelines.REPEAT_SALES, REPEAT_SALES_STAGES);
        for (String laterStage : new List<String>{ 'Key call confirmed', 'Key call held', 'Closing', 'Handed over to preparation' }) {
            assertRejected(Pipelines.REPEAT_SALES, laterStage);
        }
        Opportunity keyCall = [
            SELECT Stage_Order__c FROM Opportunity
            WHERE RecordType.DeveloperName = 'Repeat_Sales' AND StageName = 'Key call scheduled'
            WITH SYSTEM_MODE
        ];
        Assert.areEqual(4, keyCall.Stage_Order__c.intValue(), 'Repeat sales stage 4 is the shared Key call scheduled');
    }
}
