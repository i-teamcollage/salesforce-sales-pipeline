trigger TaskTrigger on Task (after insert, after update) {
    TaskCompletion.afterSave(Trigger.new, (Map<Id, Task>) Trigger.oldMap);
}
