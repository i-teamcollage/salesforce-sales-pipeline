/**
 * One entry point for the Opportunity trigger. The order matters:
 * the lead author is recorded (FL3) before A4 can hand the deal to the closer.
 * The record-triggered flows (A2, A3, A6, A7) run alongside; see force-app/main/default/flows.
 */
public without sharing class OpportunityTriggerHandler {
    public static void run() {
        switch on Trigger.operationType {
            when BEFORE_INSERT {
                beforeInsert(Trigger.new);
            }
            when BEFORE_UPDATE {
                beforeUpdate(Trigger.new, (Map<Id, Opportunity>) Trigger.oldMap);
            }
            when AFTER_INSERT {
                KeyCallService.afterSave(Trigger.new, null);
                PaymentControl.afterSave(Trigger.new, null);
            }
            when AFTER_UPDATE {
                KeyCallService.afterSave(Trigger.new, (Map<Id, Opportunity>) Trigger.oldMap);
                PaymentControl.afterSave(Trigger.new, (Map<Id, Opportunity>) Trigger.oldMap);
            }
        }
    }

    /** FL3: the lead author is the owner at creation, whatever was typed in. */
    public static void beforeInsert(List<Opportunity> deals) {
        for (Opportunity deal : deals) {
            if (Pipelines.isPipelineDeal(deal)) {
                deal.Lead_Author__c = deal.OwnerId;
            }
        }
        KeyCallService.beforeSave(deals, null);
    }

    public static void beforeUpdate(List<Opportunity> deals, Map<Id, Opportunity> oldMap) {
        PipelineTransitions.beforeUpdate(deals, oldMap);
        KeyCallService.beforeSave(deals, oldMap);
        KeyCallService.requireRecording(deals, oldMap);
    }
}
