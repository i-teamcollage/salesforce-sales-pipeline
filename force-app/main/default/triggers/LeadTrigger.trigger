trigger LeadTrigger on Lead (before insert, after insert) {
    if (Trigger.isBefore) {
        LeadConversionService.beforeInsert(Trigger.new);
    } else {
        LeadConversionService.afterInsert(Trigger.new);
    }
}
