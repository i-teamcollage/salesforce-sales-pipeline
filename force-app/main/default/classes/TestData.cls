/**
 * Made-up people and deals for the tests. Users get the "Minimum Access - Salesforce" profile and all
 * their rights from the project's permission sets, as the install guide says.
 */
@isTest
public class TestData {
    public static final String PROFILE_NAME = 'Minimum Access - Salesforce';
    public static final Map<String, String> ROLES = new Map<String, String>{
        'chatmgr' => 'Chat_Manager',
        'closer1' => 'Closer',
        'head' => 'Head_of_Sales',
        'owner' => 'Business_Owner',
        'assist' => 'Assistant',
        'export' => 'Sheets_Export'
    };

    private static final Map<String, Integer> POSITIONS = new Map<String, Integer>{
        'New lead' => 1, 'Qualification in chat' => 2, 'Warm-up' => 3, 'Key call scheduled' => 4,
        'Key call confirmed' => 5, 'Key call held' => 6, 'Closing' => 7, 'Prepayment received' => 8,
        'Payment received' => 9, 'Handed over to preparation' => 10, 'Closed Won' => 11,
        'Building the base' => 1, 'Announcement and pre-registration' => 1, 'Clarifying the situation' => 2
    };

    private static String domain() {
        return UserInfo.getOrganizationId() + '.quorvale.test';
    }

    /** Creates the team: one user per role, with the role's permission set and public group. */
    public static void createTeam() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Id profileId = [SELECT Id FROM Profile WHERE Name = :PROFILE_NAME WITH SYSTEM_MODE LIMIT 1].Id;
            Map<String, User> users = new Map<String, User>();
            for (String alias : ROLES.keySet()) {
                users.put(alias, new User(
                    Alias = alias, FirstName = 'Test', LastName = alias,
                    Email = alias + '@' + domain(), Username = alias + '@' + domain(),
                    ProfileId = profileId, TimeZoneSidKey = 'Europe/Berlin', LocaleSidKey = 'en_GB',
                    EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'));
            }
            insert as system users.values();
            Map<String, Id> permissionSets = new Map<String, Id>();
            for (PermissionSet permissionSet : [SELECT Id, Name FROM PermissionSet WHERE Name IN :ROLES.values() WITH SYSTEM_MODE]) {
                permissionSets.put(permissionSet.Name, permissionSet.Id);
            }
            List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
            for (String alias : ROLES.keySet()) {
                assignments.add(new PermissionSetAssignment(
                    AssigneeId = users.get(alias).Id, PermissionSetId = permissionSets.get(ROLES.get(alias))));
            }
            insert as system assignments;
            Map<String, Id> groups = new Map<String, Id>();
            for (Group publicGroup : [SELECT Id, DeveloperName FROM Group WHERE DeveloperName IN ('Chat_Managers', 'Assistants') WITH SYSTEM_MODE]) {
                groups.put(publicGroup.DeveloperName, publicGroup.Id);
            }
            insert as system new List<GroupMember>{
                new GroupMember(GroupId = groups.get('Chat_Managers'), UserOrGroupId = users.get('chatmgr').Id),
                new GroupMember(GroupId = groups.get('Assistants'), UserOrGroupId = users.get('assist').Id)
            };
        }
    }

    /**
     * The shares the two criteria-based sharing rules create. Salesforce applies those rules just after a
     * transaction commits, and a test never commits (checked in a Developer Edition, also after Test.stopTest),
     * so a test of what a role sees adds them here. tests/test_access.py checks the rules themselves.
     */
    public static void shareAsTheRulesDo(List<Opportunity> deals) {
        Map<String, Id> groups = new Map<String, Id>();
        for (Group publicGroup : [SELECT Id, DeveloperName FROM Group WHERE DeveloperName IN ('Chat_Managers', 'Assistants') WITH SYSTEM_MODE]) {
            groups.put(publicGroup.DeveloperName, publicGroup.Id);
        }
        List<OpportunityShare> shares = new List<OpportunityShare>();
        for (Opportunity deal : [SELECT Id, RecordType.DeveloperName, StageName FROM Opportunity WHERE Id IN :deals WITH SYSTEM_MODE]) {
            String pipeline = deal.RecordType.DeveloperName;
            if (pipeline == Pipelines.NEW_CLIENTS || pipeline == Pipelines.REACTIVATION) {
                shares.add(new OpportunityShare(OpportunityId = deal.Id, UserOrGroupId = groups.get('Chat_Managers'),
                    OpportunityAccessLevel = 'Edit'));
            }
            if (pipeline == Pipelines.NEW_CLIENTS
                && (deal.StageName == Pipelines.PAYMENT_RECEIVED || deal.StageName == Pipelines.HANDED_OVER)) {
                shares.add(new OpportunityShare(OpportunityId = deal.Id, UserOrGroupId = groups.get('Assistants'),
                    OpportunityAccessLevel = 'Edit'));
            }
        }
        insert as system shares;
    }

    public static User user(String alias) {
        String username = alias + '@' + domain();
        return [SELECT Id, Alias, ProfileId FROM User WHERE Username = :username WITH SYSTEM_MODE LIMIT 1];
    }

    /** A time on the hour, about this many hours ahead (stored date-times drop milliseconds). */
    public static Datetime hoursAhead(Integer hours) {
        Datetime base = Datetime.now().addHours(hours);
        return Datetime.newInstanceGmt(base.yearGmt(), base.monthGmt(), base.dayGmt(), base.hourGmt(), 0, 0);
    }

    /** Where a stage sits in the New clients flow, as the Stage_Order__c formula says. */
    public static Integer position(String stage) {
        return POSITIONS.containsKey(stage) ? POSITIONS.get(stage) : 0;
    }

    /**
     * An unsaved deal at a stage, with every field required before that stage filled in.
     * A deal past Key call scheduled needs a closer; Reactivation deals look like a qualified deal
     * that was refused.
     */
    public static Opportunity deal(String pipeline, String stage, Id closerId) {
        Opportunity deal = new Opportunity(
            Name = 'Quorvale test deal', CloseDate = Date.today().addDays(30), Amount = 2400,
            RecordTypeId = Pipelines.recordTypeId(pipeline), StageName = stage,
            Source__c = 'Website', Request_Type__c = 'Application', Warm_Up_Touches__c = 0);
        Integer reached = position(stage);
        if (pipeline == Pipelines.REACTIVATION) {
            deal.Refusal_Reason__c = 'Price';
            deal.Refusal_Type__c = 'True refusal';
            reached = 4;
        }
        if (reached > 1) {
            deal.First_Response_At__c = Datetime.now().addHours(-2);
        }
        if (reached > 2) {
            deal.Qualification_Goal__c = 'Career change';
            deal.Qualification_Budget__c = 'Ready to pay';
            deal.Qualification_Timing__c = 'This cohort';
            deal.Grade__c = 'B';
            deal.Segment__c = 'Career switcher';
        }
        if (reached > 4) {
            deal.Key_Call_At__c = Datetime.now().addDays(1);
            deal.Closer__c = closerId;
        }
        if (reached > 6) {
            deal.Key_Call_Outcome__c = 'Held';
            deal.Key_Call_Result__c = 'Thinking';
        }
        if (reached > 7) {
            deal.Objection__c = 'Price';
            deal.Decision_Control_Date__c = Date.today().addDays(3);
        }
        if (reached > 8) {
            deal.Prepayment_Date__c = Date.today();
            deal.Payment_Method__c = 'Single payment';
        }
        if (reached > 9) {
            deal.Full_Payment_Date__c = Date.today();
        }
        return deal;
    }

    public static Opportunity insertDeal(String pipeline, String stage, Id closerId) {
        Opportunity created = deal(pipeline, stage, closerId);
        insert as system created;
        return reload(created.Id);
    }

    public static Opportunity reload(Id dealId) {
        return [
            SELECT Id, Name, RecordTypeId, RecordType.DeveloperName, StageName, OwnerId, Source__c, Request_Type__c,
                Lead_Author__c, First_Response_At__c, Grade__c, Warm_Up_Touches__c, Key_Call_At__c, Closer__c,
                Key_Call_Booked_On__c, Refusal_Reason__c, Refusal_Type__c, Prepayment_Date__c, Payment_Method__c,
                Start_Period__c, Stage_Order__c, CloseDate, AccountId
            FROM Opportunity WHERE Id = :dealId
            WITH SYSTEM_MODE
        ];
    }

    /** True when the message of a failed save contains the text. */
    public static Boolean failedWith(Database.SaveResult result, String text) {
        if (result.isSuccess()) {
            return false;
        }
        for (Database.Error error : result.getErrors()) {
            if (error.getMessage().contains(text)) {
                return true;
            }
        }
        return false;
    }
}
