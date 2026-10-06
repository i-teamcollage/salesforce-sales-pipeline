/**
 * A1: a website form creates a Lead (Web-to-Lead). This trigger converts it at once into an Account and
 * a Contact (standard lead conversion) and creates the deal in New clients at New lead, with its source
 * and request type filled. The Opportunity trigger records the lead author (FL3).
 * RR1: no assignment rule runs. The deal keeps the lead's owner, the default lead creator.
 * A person who already has an open deal gets a task on that deal instead of a second deal (brief review 14).
 * If anything fails, the conversion is rolled back and the lead simply stays a lead: nothing is lost.
 */
public without sharing class LeadConversionService {
    public static final Integer CONVERT_CHUNK = 100;

    public class ConversionException extends Exception {
    }

    @TestVisible
    private static Boolean failForTest = false;

    public static void beforeInsert(List<Lead> leads) {
        for (Lead lead : leads) {
            if (lead.Request_Type__c != null && String.isBlank(lead.Company)) {
                lead.Company = fullName(lead);
            }
        }
    }

    public static void afterInsert(List<Lead> leads) {
        List<Lead> fromForms = new List<Lead>();
        for (Lead lead : leads) {
            if (lead.Request_Type__c != null && !lead.IsConverted) {
                fromForms.add(lead);
            }
        }
        if (fromForms.isEmpty()) {
            return;
        }
        Savepoint savepoint = Database.setSavepoint();
        try {
            convert(fromForms);
        } catch (Exception error) {
            Database.rollback(savepoint);
            System.debug(LoggingLevel.ERROR, 'A1 kept ' + fromForms.size() + ' lead(s) unconverted: ' + error.getMessage());
        }
    }

    private static void convert(List<Lead> leads) {
        String convertedStatus = [SELECT MasterLabel FROM LeadStatus WHERE IsConverted = TRUE ORDER BY SortOrder LIMIT 1].MasterLabel;
        Map<String, Contact> contactsByEmail = existingContacts(leads);
        List<Database.LeadConvert> requests = new List<Database.LeadConvert>();
        for (Lead lead : leads) {
            Database.LeadConvert request = new Database.LeadConvert();
            request.setLeadId(lead.Id);
            request.setConvertedStatus(convertedStatus);
            request.setDoNotCreateOpportunity(true);
            Contact known = lead.Email == null ? null : contactsByEmail.get(lead.Email.toLowerCase());
            if (known != null) {
                request.setContactId(known.Id);
                request.setAccountId(known.AccountId);
            }
            requests.add(request);
        }
        List<Database.LeadConvertResult> results = new List<Database.LeadConvertResult>();
        for (Integer start = 0; start < requests.size(); start += CONVERT_CHUNK) {
            List<Database.LeadConvert> chunk = new List<Database.LeadConvert>();
            for (Integer i = start; i < Math.min(start + CONVERT_CHUNK, requests.size()); i++) {
                chunk.add(requests[i]);
            }
            results.addAll(Database.convertLead(chunk, false));
        }
        createDeals(new Map<Id, Lead>(leads), results);
    }

    private static void createDeals(Map<Id, Lead> leadsById, List<Database.LeadConvertResult> results) {
        Set<Id> contactIds = new Set<Id>();
        for (Database.LeadConvertResult result : results) {
            if (result.isSuccess()) {
                contactIds.add(result.getContactId());
            }
        }
        Map<Id, Opportunity> openDeals = openDealsByContact(contactIds);
        Map<Id, Id> chatManagers = Activities.chatManagers(openDeals.values());
        List<Opportunity> deals = new List<Opportunity>();
        List<Id> dealContacts = new List<Id>();
        List<Task> repeatTasks = new List<Task>();
        for (Database.LeadConvertResult result : results) {
            if (!result.isSuccess()) {
                continue;
            }
            Lead lead = leadsById.get(result.getLeadId());
            Opportunity open = openDeals.get(result.getContactId());
            if (open != null) {
                repeatTasks.add(Activities.timedTask(open.Id, chatManagers.get(open.Id), Activities.A1_REPEAT_FORM,
                    'The client sent the form again (' + lead.Request_Type__c + ')', Datetime.now().addMinutes(30)));
                continue;
            }
            deals.add(newDeal(lead, result.getAccountId()));
            dealContacts.add(result.getContactId());
        }
        if (failForTest) {
            throw new ConversionException('Simulated failure after conversion');
        }
        insert deals;
        List<OpportunityContactRole> roles = new List<OpportunityContactRole>();
        for (Integer i = 0; i < deals.size(); i++) {
            roles.add(new OpportunityContactRole(OpportunityId = deals[i].Id, ContactId = dealContacts[i], IsPrimary = true));
        }
        insert roles;
        insert repeatTasks;
    }

    private static Opportunity newDeal(Lead lead, Id accountId) {
        Boolean ownedByUser = lead.OwnerId != null && String.valueOf(lead.OwnerId).startsWith('005');
        return new Opportunity(
            Name = (fullName(lead) + ' - ' + lead.Request_Type__c).left(120),
            AccountId = accountId,
            OwnerId = ownedByUser ? lead.OwnerId : UserInfo.getUserId(),
            RecordTypeId = Pipelines.recordTypeId(Pipelines.NEW_CLIENTS),
            StageName = Pipelines.NEW_LEAD,
            CloseDate = Date.today().addDays(30),
            Source__c = SalesSettings.sourceForUtm(lead.UTM_Source__c),
            Request_Type__c = lead.Request_Type__c,
            Warm_Up_Touches__c = 0
        );
    }

    private static Map<String, Contact> existingContacts(List<Lead> leads) {
        Set<String> emails = new Set<String>();
        for (Lead lead : leads) {
            if (lead.Email != null) {
                emails.add(lead.Email.toLowerCase());
            }
        }
        Map<String, Contact> result = new Map<String, Contact>();
        for (Contact known : [SELECT Id, AccountId, Email FROM Contact WHERE Email IN :emails AND AccountId != NULL ORDER BY CreatedDate]) {
            result.put(known.Email.toLowerCase(), known);
        }
        return result;
    }

    private static Map<Id, Opportunity> openDealsByContact(Set<Id> contactIds) {
        Set<String> pipelineNames = Pipelines.ALL_PIPELINES;
        Map<Id, Opportunity> result = new Map<Id, Opportunity>();
        for (OpportunityContactRole role : [
            SELECT ContactId, Opportunity.Id, Opportunity.OwnerId, Opportunity.Lead_Author__c
            FROM OpportunityContactRole
            WHERE ContactId IN :contactIds AND Opportunity.IsClosed = FALSE
                AND Opportunity.RecordType.DeveloperName IN :pipelineNames
        ]) {
            if (!result.containsKey(role.ContactId)) {
                result.put(role.ContactId, role.Opportunity);
            }
        }
        return result;
    }

    private static String fullName(Lead lead) {
        return (String.isBlank(lead.FirstName) ? '' : lead.FirstName + ' ') + lead.LastName;
    }
}
