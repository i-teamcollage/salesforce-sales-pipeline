/**
 * TR1: a deal comes back from Reactivation to New clients by hand, as the same record, at Key call
 *      scheduled. Its old refusal reason and type are cleared, so a second refusal triggers A7 again.
 *      The gating rules then make it pass re-qualification (stages 1 to 3).
 * EX3: closing a deal sets its close date to the day it closed (the export's "close date").
 * The refusal itself (New clients or Repeat sales to Reactivation) is the A7 flow.
 */
public without sharing class PipelineTransitions {
    public static final String RETURN_STAGE_MESSAGE =
        'A deal comes back from Reactivation at Key call scheduled. Pick that stage.';

    public static void beforeUpdate(List<Opportunity> deals, Map<Id, Opportunity> oldMap) {
        Id reactivation = Pipelines.recordTypeId(Pipelines.REACTIVATION);
        Id newClients = Pipelines.recordTypeId(Pipelines.NEW_CLIENTS);
        for (Opportunity deal : deals) {
            Opportunity old = oldMap.get(deal.Id);
            if (old.RecordTypeId == reactivation && deal.RecordTypeId == newClients) {
                if (deal.StageName != Pipelines.KEY_CALL_SCHEDULED) {
                    deal.addError(RETURN_STAGE_MESSAGE);
                    continue;
                }
                deal.Refusal_Reason__c = null;
                deal.Refusal_Type__c = null;
            }
            if (Pipelines.isPipelineDeal(deal) && Pipelines.isClosed(deal.StageName) && deal.StageName != old.StageName) {
                deal.CloseDate = Date.today();
            }
        }
    }
}
