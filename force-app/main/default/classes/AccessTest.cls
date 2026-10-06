/**
 * AC1 to AC5: what each role sees and may do. Sharing is Private; rights come from the role's
 * permission set, and visibility from ownership plus the two criteria-based sharing rules.
 * Every check runs as the user, with user-mode queries and DML.
 */
@isTest
private class AccessTest {
    private static final Set<String> ALL_DEALS = new Set<String>{
        'Early', 'Closer call', 'Stage 9', 'Stage 10', 'Head closing', 'Refused', 'Repeat of head'
    };

    @testSetup
    static void setup() {
        TestData.createTeam();
        Id chatManager = TestData.user('chatmgr').Id;
        Id closer = TestData.user('closer1').Id;
        Id head = TestData.user('head').Id;
        List<Opportunity> deals = new List<Opportunity>{
            named(TestData.deal(Pipelines.NEW_CLIENTS, Pipelines.QUALIFICATION, null), 'Early', chatManager),
            named(TestData.deal(Pipelines.NEW_CLIENTS, Pipelines.KEY_CALL_CONFIRMED, closer), 'Closer call', chatManager),
            named(TestData.deal(Pipelines.NEW_CLIENTS, Pipelines.PAYMENT_RECEIVED, closer), 'Stage 9', chatManager),
            named(TestData.deal(Pipelines.NEW_CLIENTS, Pipelines.HANDED_OVER, head), 'Stage 10', chatManager),
            named(TestData.deal(Pipelines.NEW_CLIENTS, Pipelines.CLOSING, head), 'Head closing', chatManager),
            named(TestData.deal(Pipelines.REACTIVATION, Pipelines.DEFERRED_DEMAND, null), 'Refused', chatManager),
            named(TestData.deal(Pipelines.REPEAT_SALES, Pipelines.BUILDING_BASE, null), 'Repeat of head', head)
        };
        insert deals;
    }

    private static Opportunity named(Opportunity deal, String name, Id ownerId) {
        deal.Name = name;
        deal.OwnerId = ownerId;
        return deal;
    }

    private static Id dealId(String name) {
        return [SELECT Id FROM Opportunity WHERE Name = :name].Id;
    }

    private static Set<String> visible() {
        Set<String> names = new Set<String>();
        for (Opportunity deal : [SELECT Name FROM Opportunity WITH USER_MODE]) {
            names.add(deal.Name);
        }
        return names;
    }

    private static Boolean canEdit(Id recordId) {
        Opportunity change = new Opportunity(Id = recordId, Last_Client_Reply_At__c = Datetime.now());
        return Database.update(change, false, AccessLevel.USER_MODE).isSuccess();
    }

    private static Boolean canDelete(Id recordId) {
        return Database.delete(new Opportunity(Id = recordId), false, AccessLevel.USER_MODE).isSuccess();
    }

    /** A system permission from the user's profile or any assigned permission set. */
    private static Boolean has(String alias, String permission) {
        User person = TestData.user(alias);
        Set<Id> setIds = new Set<Id>();
        for (PermissionSetAssignment assignment : [SELECT PermissionSetId FROM PermissionSetAssignment WHERE AssigneeId = :person.Id]) {
            setIds.add(assignment.PermissionSetId);
        }
        for (PermissionSet profileSet : [SELECT Id FROM PermissionSet WHERE ProfileId = :person.ProfileId]) {
            setIds.add(profileSet.Id);
        }
        for (PermissionSet permissionSet : Database.query('SELECT ' + permission + ' FROM PermissionSet WHERE Id IN :setIds')) {
            if ((Boolean) permissionSet.get(permission)) {
                return true;
            }
        }
        return false;
    }

    @isTest
    static void AC1_headOfSalesHasEverythingIncludingSettingsAndExport() {
        Id early = dealId('Early');
        Id repeat = dealId('Repeat of head');
        System.runAs(TestData.user('head')) {
            Assert.areEqual(ALL_DEALS, visible(), 'all pipelines');
            Assert.isTrue(canEdit(early), 'edits deals of others');
            Assert.isTrue(canDelete(repeat), 'may delete');
        }
        Assert.isTrue(has('head', 'PermissionsRunReports'), 'reports');
        Assert.isTrue(has('head', 'PermissionsExportReport'), 'export');
        Assert.isTrue(has('head', 'PermissionsCustomizeApplication'), 'settings');
    }

    @isTest
    static void AC2_ownerReadsEverythingAndChangesNothing() {
        Id early = dealId('Early');
        System.runAs(TestData.user('owner')) {
            Assert.areEqual(ALL_DEALS, visible(), 'reads everything');
            Assert.isFalse(canEdit(early), 'cannot edit');
            Assert.isFalse(canDelete(early), 'cannot delete');
        }
        Assert.isTrue(has('owner', 'PermissionsRunReports'), 'reports');
        Assert.isTrue(has('owner', 'PermissionsExportReport'), 'export');
    }

    @isTest
    static void AC3_closerSeesOnlyOwnDealsFromKeyCallOnAndCannotDeleteOrExport() {
        Id own = dealId('Closer call');
        Id closerId = TestData.user('closer1').Id;
        System.runAs(TestData.user('closer1')) {
            Assert.areEqual(new Set<String>{ 'Closer call', 'Stage 9' }, visible(), 'only the deals A4 handed over');
            Assert.isTrue(canEdit(own), 'works on own deals');
            Assert.isFalse(canDelete(own), 'cannot delete');
        }
        for (Opportunity deal : [SELECT RecordType.DeveloperName, Stage_Order__c FROM Opportunity WHERE OwnerId = :closerId]) {
            Assert.areEqual(Pipelines.NEW_CLIENTS, deal.RecordType.DeveloperName, 'in pipeline 1');
            Assert.isTrue(deal.Stage_Order__c >= 4, 'from stage 4 on');
        }
        Assert.isFalse(has('closer1', 'PermissionsExportReport'), 'no export');
    }

    @isTest
    static void AC4_chatManagerSeesPipelinesOneAndTwoAndCannotDeleteOrExport() {
        Id headClosing = dealId('Head closing');
        Set<String> expected = new Set<String>(ALL_DEALS);
        expected.remove('Repeat of head');
        System.runAs(TestData.user('chatmgr')) {
            Assert.areEqual(expected, visible(), 'all of New clients and Reactivation, not the repeat deal of another user');
            Assert.isTrue(canEdit(headClosing), 'edits deals owned by others in pipeline 1');
            Assert.isFalse(canDelete(headClosing), 'cannot delete');
        }
        Assert.isFalse(has('chatmgr', 'PermissionsExportReport'), 'no export');
    }

    @isTest
    static void AC5_assistantSeesOnlyStagesNineAndTen() {
        Id stage9 = dealId('Stage 9');
        System.runAs(TestData.user('assist')) {
            Assert.areEqual(new Set<String>{ 'Stage 9', 'Stage 10' }, visible(), 'stages 9 and 10 only');
            Database.SaveResult move = Database.update(new Opportunity(Id = stage9, StageName = Pipelines.HANDED_OVER,
                Full_Payment_Date__c = Date.today()), false, AccessLevel.USER_MODE);
            Assert.isTrue(move.isSuccess(), 'hands the client over: ' + move.getErrors());
            Assert.isFalse(canDelete(stage9), 'cannot delete');
        }
        Assert.isFalse(has('assist', 'PermissionsExportReport'), 'no export');
    }
}
