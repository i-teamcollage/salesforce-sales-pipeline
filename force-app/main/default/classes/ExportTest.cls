/**
 * EX1 and EX3, the Salesforce side of the Google Sheets export. The query below is the one the
 * Apps Script sends (google-sheets/transform.js, EXPORT_SOQL); a static test keeps the two identical.
 */
@isTest
private class ExportTest {
    // export-query:start
    private static final String EXPORT_SOQL =
        'SELECT Id, RecordType.Name, StageName, CreatedDate, Source__c, Request_Type__c, Grade__c, Segment__c, ' +
        'Lead_Author__r.Name, Closer__r.Name, Key_Call_Booked_On__c, Key_Call_At__c, Key_Call_Outcome__c, ' +
        'Key_Call_Result__c, Objection__c, Prepayment_Date__c, Payment_Method__c, Full_Payment_Date__c, Amount, ' +
        'Start_Period__c, Refusal_Reason__c, Refusal_Type__c, First_Response_At__c, LastActivityDate, CloseDate, ' +
        'IsClosed FROM Opportunity ' +
        'WHERE RecordType.DeveloperName IN (\'New_Clients\', \'Reactivation\', \'Repeat_Sales\') ORDER BY CreatedDate';
    // export-query:end

    @testSetup
    static void setup() {
        TestData.createTeam();
        Opportunity won = TestData.deal(Pipelines.NEW_CLIENTS, Pipelines.CLOSED_WON, TestData.user('closer1').Id);
        won.OwnerId = TestData.user('chatmgr').Id;
        won.Name = 'Won deal';
        Opportunity refused = TestData.deal(Pipelines.REACTIVATION, Pipelines.IGNORED, null);
        refused.Name = 'Refused deal';
        Opportunity repeat = TestData.deal(Pipelines.REPEAT_SALES, Pipelines.BUILDING_BASE, null);
        repeat.Name = 'Repeat deal';
        Opportunity other = new Opportunity(Name = 'Not a pipeline deal', StageName = 'Qualify', CloseDate = Date.today(),
            RecordTypeId = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('Master').getRecordTypeId());
        insert new List<Opportunity>{ won, refused, repeat, other };
    }

    @isTest
    static void EX1_exportUserReadsEveryDealAndWritesNothing() {
        Id wonId = [SELECT Id FROM Opportunity WHERE Name = 'Won deal'].Id;
        System.runAs(TestData.user('export')) {
            List<Opportunity> rows = Database.query(EXPORT_SOQL, AccessLevel.USER_MODE);
            Assert.areEqual(3, rows.size(), 'every deal of the three pipelines, nothing else');
            Database.SaveResult write = Database.update(new Opportunity(Id = wonId, Amount = 1), false, AccessLevel.USER_MODE);
            Assert.isFalse(write.isSuccess(), 'the export user cannot write');
        }
    }

    @isTest
    static void EX3_queryReturnsTheTwentyFiveColumnsOfEveryDeal() {
        Id wonId = [SELECT Id FROM Opportunity WHERE Name = 'Won deal'].Id;
        Opportunity row = null;
        for (Opportunity deal : Database.query(EXPORT_SOQL)) {
            if (deal.Id == wonId) {
                row = deal;
            }
        }
        Assert.isNotNull(row, 'the won deal is exported');
        Assert.areEqual('New clients', row.RecordType.Name, 'pipeline');
        Assert.areEqual(Pipelines.CLOSED_WON, row.StageName, 'stage');
        Assert.areEqual('Test chatmgr', row.Lead_Author__r.Name, 'lead author by name');
        Assert.areEqual('Test closer1', row.Closer__r.Name, 'closer by name');
        Assert.areEqual('Website', row.Source__c, 'source');
        Assert.areEqual(Date.today(), row.Key_Call_Booked_On__c, 'booking date');
        Assert.areEqual(2400, row.Amount.intValue(), 'amount');
        Assert.isTrue(row.IsClosed, 'closed, so the close date is a real one');
        Assert.isFalse(String.isBlank(row.Start_Period__c), 'start period');
    }

    @isTest
    static void EX3_closingADealStampsItsCloseDate() {
        Opportunity deal = TestData.insertDeal(Pipelines.NEW_CLIENTS, Pipelines.HANDED_OVER, UserInfo.getUserId());
        Assert.areNotEqual(Date.today(), deal.CloseDate, 'an open deal has a planned date');
        update new Opportunity(Id = deal.Id, StageName = Pipelines.CLOSED_WON);
        Assert.areEqual(Date.today(), TestData.reload(deal.Id).CloseDate, 'the day it closed');
    }
}
