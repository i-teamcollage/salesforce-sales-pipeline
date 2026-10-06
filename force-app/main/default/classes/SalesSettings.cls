/**
 * Settings the head of sales can change without code, in Custom Metadata (Setup > Custom Metadata Types):
 *   Sales_Setting__mdt.Default  silence days for A7 (5 to 7, kept in range by a validation rule)
 *   Payment_Term__mdt           per payment method: days to full payment and reminder days (A8)
 *   Source_Mapping__mdt         utm_source to Source (A1)
 * Every value has a safe default, so a missing record never stops an automation.
 */
public inherited sharing class SalesSettings {
    public static final Integer DEFAULT_SILENCE_DAYS = 5;
    public static final Integer DEFAULT_REMINDER_DAYS = 2;
    public static final String NO_TAG_SOURCE = 'Website';
    public static final String UNKNOWN_TAG_SOURCE = 'Other';

    private static final Map<String, Integer> DEFAULT_TERMS = new Map<String, Integer>{
        'Single payment' => 7,
        'Bank instalments' => 10,
        'In-house instalments' => 14
    };

    /** A7: days of silence before a deal moves to Reactivation. */
    public static Integer silenceDays() {
        Sales_Setting__mdt setting = Sales_Setting__mdt.getInstance('Default');
        return silenceDays(setting == null ? null : setting.Silence_Days__c);
    }

    /** The brief allows 5 to 7 days; anything else is brought back into that range. */
    public static Integer silenceDays(Decimal configured) {
        Integer days = configured == null ? DEFAULT_SILENCE_DAYS : configured.intValue();
        return Math.min(7, Math.max(5, days));
    }

    /** A8: days from the prepayment to the target full-payment date. */
    public static Integer daysToFullPayment(String paymentMethod) {
        Payment_Term__mdt term = findTerm(paymentMethod);
        if (term != null && term.Days_To_Full_Payment__c != null) {
            return term.Days_To_Full_Payment__c.intValue();
        }
        return DEFAULT_TERMS.containsKey(paymentMethod) ? DEFAULT_TERMS.get(paymentMethod) : 7;
    }

    /** A8: how many days before the target date the reminder task falls. */
    public static Integer reminderDaysBefore(String paymentMethod) {
        Payment_Term__mdt term = findTerm(paymentMethod);
        return term != null && term.Reminder_Days_Before__c != null
            ? term.Reminder_Days_Before__c.intValue()
            : DEFAULT_REMINDER_DAYS;
    }

    private static Payment_Term__mdt findTerm(String paymentMethod) {
        for (Payment_Term__mdt term : Payment_Term__mdt.getAll().values()) {
            if (term.Payment_Method__c == paymentMethod) {
                return term;
            }
        }
        return null;
    }

    /** A1: the Source value for a form's utm_source. */
    public static String sourceForUtm(String utmSource) {
        Map<String, String> mapping = new Map<String, String>();
        for (Source_Mapping__mdt row : Source_Mapping__mdt.getAll().values()) {
            if (String.isNotBlank(row.UTM_Source__c)) {
                mapping.put(row.UTM_Source__c.trim().toLowerCase(), row.Source__c);
            }
        }
        return sourceForUtm(mapping, utmSource);
    }

    /** Never returns a value the restricted Source picklist would reject, so a lead is never lost. */
    public static String sourceForUtm(Map<String, String> mapping, String utmSource) {
        if (String.isBlank(utmSource)) {
            return NO_TAG_SOURCE;
        }
        String source = mapping.get(utmSource.trim().toLowerCase());
        return (source != null && validSources().contains(source)) ? source : UNKNOWN_TAG_SOURCE;
    }

    private static Set<String> validSources() {
        Set<String> values = new Set<String>();
        for (Schema.PicklistEntry entry : Opportunity.Source__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                values.add(entry.getValue());
            }
        }
        return values;
    }
}
