/**
 * NF1: converts one batch of up to 50 form leads in a transaction of its own, for an import too large to
 * convert while it is saved (see LeadConversionService). A lead converted in the meantime is skipped.
 * Its database work runs in system mode on purpose: it acts for the business, whoever saved the record.
 */
public without sharing class LeadConversionJob implements Queueable {
    private final List<Id> leadIds;

    public LeadConversionJob(List<Id> leadIds) {
        this.leadIds = leadIds;
    }

    public void execute(QueueableContext context) {
        List<Lead> leads = [
            SELECT Id, FirstName, LastName, Email, OwnerId, Request_Type__c, UTM_Source__c
            FROM Lead WHERE Id IN :leadIds AND IsConverted = FALSE
            WITH SYSTEM_MODE
        ];
        if (!leads.isEmpty()) {
            LeadConversionService.convertOrKeep(leads);
        }
    }
}
