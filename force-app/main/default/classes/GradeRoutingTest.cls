/**
 * A3: grade A goes to Key call scheduled, grades B and C go to Warm-up.
 */
@isTest
private class GradeRoutingTest {
    private static Opportunity qualifiedWithoutGrade() {
        Opportunity deal = TestData.deal(Pipelines.NEW_CLIENTS, Pipelines.WARM_UP, null);
        deal.StageName = Pipelines.QUALIFICATION;
        deal.Grade__c = null;
        return deal;
    }

    @isTest
    static void A3_gradeAGoesToKeyCallScheduled() {
        Opportunity deal = qualifiedWithoutGrade();
        insert deal;
        update new Opportunity(Id = deal.Id, Grade__c = 'A');
        Assert.areEqual(Pipelines.KEY_CALL_SCHEDULED, TestData.reload(deal.Id).StageName);
    }

    @isTest
    static void A3_gradesBAndCGoToWarmUp() {
        Opportunity gradeB = qualifiedWithoutGrade();
        Opportunity gradeC = qualifiedWithoutGrade();
        insert new List<Opportunity>{ gradeB, gradeC };
        update new List<Opportunity>{
            new Opportunity(Id = gradeB.Id, Grade__c = 'B'),
            new Opportunity(Id = gradeC.Id, Grade__c = 'C')
        };
        Assert.areEqual(Pipelines.WARM_UP, TestData.reload(gradeB.Id).StageName, 'grade B');
        Assert.areEqual(Pipelines.WARM_UP, TestData.reload(gradeC.Id).StageName, 'grade C');
    }

    @isTest
    static void A3_laterStagesAndOtherPipelinesAreNotRouted() {
        Opportunity closing = TestData.insertDeal(Pipelines.NEW_CLIENTS, Pipelines.CLOSING, UserInfo.getUserId());
        Opportunity repeat = TestData.insertDeal(Pipelines.REPEAT_SALES, Pipelines.CLARIFYING, null);
        update new List<Opportunity>{
            new Opportunity(Id = closing.Id, Grade__c = 'A'),
            new Opportunity(Id = repeat.Id, Grade__c = 'A')
        };
        Assert.areEqual(Pipelines.CLOSING, TestData.reload(closing.Id).StageName, 'a later stage stays put');
        Assert.areEqual(Pipelines.CLARIFYING, TestData.reload(repeat.Id).StageName, 'Repeat sales has no Warm-up');
    }
}
