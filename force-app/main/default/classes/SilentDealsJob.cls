/**
 * A7, second trigger: every day, deals in New clients with no client reply for N days (a setting,
 * 5 to 7, default 5) move to Reactivation at the stage Ignored. They get the refusal reason "No reply"
 * and the refusal type "Ignored", which is the brief's tag "Ignored" in this build.
 * Watched stages: New lead to Closing, and Conditional refusal. From Prepayment received on, the client
 * has paid, so silence is not a refusal. With no reply recorded, the deal's creation time counts.
 *
 * Schedule it once after deploying:  SilentDealsJob.scheduleDaily();
 * Its database work runs in system mode on purpose: it acts for the business, whoever saved the record.
 */
public without sharing class SilentDealsJob implements Schedulable, Database.Batchable<SObject> {
    public static final String JOB_NAME = 'A7 silent deals to Reactivation';
    public static final String DAILY_AT_SEVEN = '0 0 7 * * ?';
    public static final String NO_REPLY = 'No reply';

    public static Id scheduleDaily() {
        return System.schedule(JOB_NAME, DAILY_AT_SEVEN, new SilentDealsJob());
    }

    public void execute(SchedulableContext context) {
        Database.executeBatch(new SilentDealsJob(), 200);
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        Datetime cutoff = Datetime.now().addDays(-SalesSettings.silenceDays());
        Id newClients = Pipelines.recordTypeId(Pipelines.NEW_CLIENTS);
        Set<String> stages = Pipelines.SILENCE_STAGES;
        return Database.getQueryLocator([
            SELECT Id, StageName, Last_Client_Reply_At__c, CreatedDate
            FROM Opportunity
            WHERE RecordTypeId = :newClients AND StageName IN :stages
                AND ((Last_Client_Reply_At__c != NULL AND Last_Client_Reply_At__c < :cutoff)
                    OR (Last_Client_Reply_At__c = NULL AND CreatedDate < :cutoff))
            WITH SYSTEM_MODE
        ]);
    }

    public void execute(Database.BatchableContext context, List<Opportunity> scope) {
        Id reactivation = Pipelines.recordTypeId(Pipelines.REACTIVATION);
        for (Opportunity deal : scope) {
            deal.RecordTypeId = reactivation;
            deal.StageName = Pipelines.IGNORED;
            deal.Refusal_Reason__c = NO_REPLY;
            deal.Refusal_Type__c = Pipelines.IGNORED;
        }
        // A deal that cannot be saved stays where it is; the next run tries again.
        Database.update(scope, false, AccessLevel.SYSTEM_MODE);
    }

    public void finish(Database.BatchableContext context) {
        return;
    }
}
