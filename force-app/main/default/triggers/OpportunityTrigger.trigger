trigger OpportunityTrigger on Opportunity (before insert, before update, after insert, after update) {
    OpportunityTriggerHandler.run();
}
