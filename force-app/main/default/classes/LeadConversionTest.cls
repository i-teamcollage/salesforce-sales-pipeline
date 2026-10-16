/**
 * A1: a website form becomes a deal. RR1: nothing reassigns deals except A4. NF1: a month of leads at once.
 */
@isTest
private class LeadConversionTest {
    private static Lead formLead(String firstName, String lastName, String email, String requestType, String utm) {
        return new Lead(FirstName = firstName, LastName = lastName, Email = email,
            Request_Type__c = requestType, UTM_Source__c = utm);
    }

    /** A repeat form, saved the way Web-to-Lead saves it: the standard duplicate rule's alert does not stop it. */
    private static void submitAgain(Lead lead) {
        Database.DMLOptions options = new Database.DMLOptions();
        options.DuplicateRuleHeader.allowSave = true;
        Database.SaveResult result = Database.insert(lead, options, AccessLevel.SYSTEM_MODE);
        Assert.isTrue(result.isSuccess(), String.valueOf(result.getErrors()));
    }

    @isTest
    static void A1_formLeadBecomesADealInNewLead() {
        TestData.createTeam();
        User chatManager = TestData.user('chatmgr');
        Lead lead = formLead('Ilse', 'Varga', 'ilse.varga@example.org', 'Application', 'Facebook');
        System.runAs(chatManager) {
            insert as system lead;
        }
        Lead converted = [SELECT IsConverted, ConvertedAccountId, ConvertedContactId FROM Lead WHERE Id = :lead.Id WITH SYSTEM_MODE];
        Assert.isTrue(converted.IsConverted, 'the lead was converted');
        Opportunity deal = [
            SELECT Id, RecordType.DeveloperName, StageName, Source__c, Request_Type__c, Lead_Author__c, OwnerId
            FROM Opportunity WHERE AccountId = :converted.ConvertedAccountId
            WITH SYSTEM_MODE
        ];
        Assert.areEqual(Pipelines.NEW_CLIENTS, deal.RecordType.DeveloperName, 'in New clients');
        Assert.areEqual(Pipelines.NEW_LEAD, deal.StageName, 'at New lead');
        Assert.areEqual('Paid social', deal.Source__c, 'source from the UTM tag');
        Assert.areEqual('Application', deal.Request_Type__c, 'request type from the form');
        Assert.areEqual(chatManager.Id, deal.Lead_Author__c, 'lead author recorded');
        Assert.areEqual(chatManager.Id, deal.OwnerId, 'owned by the chat manager');
        OpportunityContactRole role = [SELECT ContactId, IsPrimary FROM OpportunityContactRole WHERE OpportunityId = :deal.Id WITH SYSTEM_MODE];
        Assert.areEqual(converted.ConvertedContactId, role.ContactId, 'the new contact is on the deal');
        Assert.isTrue(role.IsPrimary, 'as the primary contact');
    }

    @isTest
    static void A1_sourceComesFromTheUtmTagAndNeverFails() {
        insert as system new List<Lead>{
            formLead('Aino', 'Lehtinen', 'aino@example.org', 'Consultation', null),
            formLead('Bruno', 'Kask', 'bruno@example.org', 'Consultation', 'tiktok'),
            formLead('Cleo', 'Marin', 'cleo@example.org', 'Application', ' GOOGLE ')
        };
        Map<String, String> sources = new Map<String, String>();
        for (Opportunity deal : [SELECT Name, Source__c FROM Opportunity WITH SYSTEM_MODE]) {
            sources.put(deal.Name, deal.Source__c);
        }
        Assert.areEqual('Website', sources.get('Aino Lehtinen - Consultation'), 'no tag means Website');
        Assert.areEqual('Other', sources.get('Bruno Kask - Consultation'), 'an unknown tag means Other');
        Assert.areEqual('Search ads', sources.get('Cleo Marin - Application'), 'tags match without case or spaces');
        Assert.areEqual('Other', SalesSettings.sourceForUtm(new Map<String, String>{ 'x' => 'Not a source' }, 'x'),
            'a mapping to a value outside the list falls back to Other');
    }

    @isTest
    static void A1_leadWithoutRequestTypeIsLeftAlone() {
        Lead walkIn = new Lead(LastName = 'Walk-in', Company = 'Quorvale open day');
        insert as system walkIn;
        Assert.isFalse([SELECT IsConverted FROM Lead WHERE Id = :walkIn.Id WITH SYSTEM_MODE].IsConverted, 'not from a program form');
        Assert.areEqual(0, [SELECT COUNT() FROM Opportunity WITH SYSTEM_MODE]);
    }

    @isTest
    static void A1_secondFormFromAnOpenDealAddsATaskNotADeal() {
        insert as system formLead('Ilse', 'Varga', 'ilse.varga@example.org', 'Application', 'facebook');
        submitAgain(formLead('Ilse', 'Varga', 'ilse.varga@example.org', 'Consultation', 'google'));
        Assert.areEqual(1, [SELECT COUNT() FROM Opportunity WITH SYSTEM_MODE], 'still one deal');
        Assert.areEqual(1, [SELECT COUNT() FROM Contact WITH SYSTEM_MODE], 'still one contact');
        Opportunity deal = [SELECT Id FROM Opportunity WITH SYSTEM_MODE];
        Assert.areEqual(1, [SELECT COUNT() FROM Task WHERE WhatId = :deal.Id AND Automation__c = :Activities.A1_REPEAT_FORM WITH SYSTEM_MODE],
            'the chat manager is told on the open deal');
    }

    @isTest
    static void A1_pastClientGetsANewDealOnTheSameAccount() {
        insert as system formLead('Pavel', 'Ost', 'pavel.ost@example.org', 'Application', 'newsletter');
        Opportunity first = [SELECT Id, AccountId FROM Opportunity WITH SYSTEM_MODE];
        update as system new Opportunity(Id = first.Id, StageName = Pipelines.CLOSED_LOST);
        submitAgain(formLead('Pavel', 'Ost', 'pavel.ost@example.org', 'Consultation', 'newsletter'));
        Opportunity second = [SELECT AccountId, StageName FROM Opportunity WHERE Id != :first.Id WITH SYSTEM_MODE];
        Assert.areEqual(first.AccountId, second.AccountId, 'same client account');
        Assert.areEqual(Pipelines.NEW_LEAD, second.StageName, 'a fresh deal at New lead');
    }

    @isTest
    static void A1_failedConversionKeepsTheLead() {
        LeadConversionService.failForTest = true;
        Lead lead = formLead('Nora', 'Belle', 'nora.belle@example.org', 'Application', 'partner');
        insert as system lead;
        Assert.isFalse([SELECT IsConverted FROM Lead WHERE Id = :lead.Id WITH SYSTEM_MODE].IsConverted, 'the lead is kept, not lost');
        Assert.areEqual(0, [SELECT COUNT() FROM Opportunity WITH SYSTEM_MODE], 'no half-made deal');
        Assert.areEqual(0, [SELECT COUNT() FROM Account WITH SYSTEM_MODE], 'the conversion was rolled back');
    }

    @isTest
    static void RR1_onlyTheKeyCallChangesTheOwner() {
        TestData.createTeam();
        User chatManager = TestData.user('chatmgr');
        User closer = TestData.user('closer1');
        System.runAs(chatManager) {
            insert as system formLead('Ruth', 'Andersen', 'ruth.andersen@example.org', 'Application', 'referral');
        }
        Opportunity deal = [SELECT Id, OwnerId FROM Opportunity WITH SYSTEM_MODE];
        Assert.areEqual(chatManager.Id, deal.OwnerId, 'no assignment rule moved the new deal');

        Task reply = [SELECT Id FROM Task WHERE WhatId = :deal.Id AND Automation__c = :Activities.A2_REPLY WITH SYSTEM_MODE];
        update as system new Task(Id = reply.Id, Status = 'Completed');
        update as system new Opportunity(Id = deal.Id, StageName = Pipelines.QUALIFICATION, Qualification_Goal__c = 'Promotion',
            Qualification_Budget__c = 'Ready to pay', Qualification_Timing__c = 'This cohort', Segment__c = 'Manager');
        update as system new Opportunity(Id = deal.Id, Grade__c = 'B');
        Assert.areEqual(chatManager.Id, TestData.reload(deal.Id).OwnerId, 'stage moves and A3 keep the owner');

        update as system new Opportunity(Id = deal.Id, StageName = Pipelines.KEY_CALL_SCHEDULED);
        update as system new Opportunity(Id = deal.Id, Key_Call_At__c = Datetime.now().addDays(1), Closer__c = closer.Id);
        Assert.areEqual(closer.Id, TestData.reload(deal.Id).OwnerId, 'A4 is the only reassignment');
    }

    @isTest
    static void NF1_aMonthOfLeadsArrivingAtOnceAllBecomeDeals() {
        List<Lead> leads = new List<Lead>();
        for (Integer i = 0; i < 150; i++) {
            leads.add(formLead('Lead', 'Number ' + i, 'lead' + i + '@example.org',
                Math.mod(i, 2) == 0 ? 'Application' : 'Consultation', 'google'));
        }
        Test.startTest();
        insert as system leads;
        Assert.areEqual(3, Limits.getQueueableJobs(), 'converted by three jobs of fifty, right after the save');
        Test.stopTest();
        Assert.areEqual(150, [SELECT COUNT() FROM Lead WHERE IsConverted = TRUE WITH SYSTEM_MODE], 'every lead converted');
        Assert.areEqual(150, [SELECT COUNT() FROM Opportunity WHERE RecordType.DeveloperName = 'New_Clients' AND StageName = 'New lead' WITH SYSTEM_MODE],
            'one deal per lead');
        Assert.areEqual(150, [SELECT COUNT() FROM Task WHERE Automation__c = :Activities.A2_REPLY WITH SYSTEM_MODE], 'and one reply task each');
    }
}
