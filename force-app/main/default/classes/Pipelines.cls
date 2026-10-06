/**
 * The three pipelines of the brief (PL1 to PL3) and their stage names, in one place.
 * A pipeline is an Opportunity record type with its own sales process.
 */
public inherited sharing class Pipelines {
    public static final String NEW_CLIENTS = 'New_Clients';
    public static final String REACTIVATION = 'Reactivation';
    public static final String REPEAT_SALES = 'Repeat_Sales';

    // Pipeline 1, New clients
    public static final String NEW_LEAD = 'New lead';
    public static final String QUALIFICATION = 'Qualification in chat';
    public static final String WARM_UP = 'Warm-up';
    public static final String KEY_CALL_SCHEDULED = 'Key call scheduled';
    public static final String KEY_CALL_CONFIRMED = 'Key call confirmed';
    public static final String KEY_CALL_HELD = 'Key call held';
    public static final String CLOSING = 'Closing';
    public static final String PREPAYMENT_RECEIVED = 'Prepayment received';
    public static final String PAYMENT_RECEIVED = 'Payment received';
    public static final String HANDED_OVER = 'Handed over to preparation';
    public static final String CONDITIONAL_REFUSAL = 'Conditional refusal';

    // Pipeline 2, Reactivation
    public static final String DEFERRED_DEMAND = 'Deferred demand';
    public static final String WAITING_NEXT_PERIOD = 'Waiting for next period';
    public static final String IGNORED = 'Ignored';
    public static final String REGULAR_TOUCHES = 'Regular touches';
    public static final String DIALOGUE_RESUMED = 'Dialogue resumed';

    // Pipeline 3, Repeat sales (its stage 4 is the shared KEY_CALL_SCHEDULED)
    public static final String BUILDING_BASE = 'Building the base';
    public static final String ANNOUNCEMENT = 'Announcement and pre-registration';
    public static final String CLARIFYING = 'Clarifying the situation';

    public static final String CLOSED_WON = 'Closed Won';
    public static final String CLOSED_LOST = 'Closed Lost';

    public static final Set<String> ALL_PIPELINES = new Set<String>{ NEW_CLIENTS, REACTIVATION, REPEAT_SALES };

    /** Stages the silence rule (A7) watches: New clients 1 to 7 and Conditional refusal. */
    public static final Set<String> SILENCE_STAGES = new Set<String>{
        NEW_LEAD, QUALIFICATION, WARM_UP, KEY_CALL_SCHEDULED, KEY_CALL_CONFIRMED,
        KEY_CALL_HELD, CLOSING, CONDITIONAL_REFUSAL
    };

    private static Map<String, Id> idsByName;

    /** Record type Id of a pipeline, from the describe cache (no query). */
    public static Id recordTypeId(String developerName) {
        if (idsByName == null) {
            idsByName = new Map<String, Id>();
            Map<String, Schema.RecordTypeInfo> infos =
                Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName();
            for (String name : new List<String>{ NEW_CLIENTS, REACTIVATION, REPEAT_SALES }) {
                if (infos.containsKey(name)) {
                    idsByName.put(name, infos.get(name).getRecordTypeId());
                }
            }
        }
        return idsByName.get(developerName);
    }

    /** True when the deal is in one of the three pipelines; other opportunities are left alone. */
    public static Boolean isPipelineDeal(Opportunity deal) {
        return deal.RecordTypeId != null && (
            deal.RecordTypeId == recordTypeId(NEW_CLIENTS) ||
            deal.RecordTypeId == recordTypeId(REACTIVATION) ||
            deal.RecordTypeId == recordTypeId(REPEAT_SALES));
    }

    public static Boolean isIn(Opportunity deal, String developerName) {
        return deal.RecordTypeId != null && deal.RecordTypeId == recordTypeId(developerName);
    }

    public static Boolean isClosed(String stageName) {
        return stageName == CLOSED_WON || stageName == CLOSED_LOST;
    }
}
