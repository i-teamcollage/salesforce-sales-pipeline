/**
 * What happens when a task on a deal is completed.
 * A2: completing the "Reply" task stamps the deal's first response time, once.
 * FL5: every task completed while the deal is in Warm-up adds one to its warm-up touches.
 */
public without sharing class TaskCompletion {
    public static void afterSave(List<Task> tasks, Map<Id, Task> oldMap) {
        Set<String> closedStatuses = closedStatuses();
        List<Task> completed = new List<Task>();
        Set<Id> dealIds = new Set<Id>();
        for (Task task : tasks) {
            Boolean closedNow = closedStatuses.contains(task.Status);
            Boolean closedBefore = oldMap != null && closedStatuses.contains(oldMap.get(task.Id).Status);
            if (closedNow && !closedBefore && task.WhatId != null
                && task.WhatId.getSObjectType() == Opportunity.SObjectType) {
                completed.add(task);
                dealIds.add(task.WhatId);
            }
        }
        if (completed.isEmpty()) {
            return;
        }
        Map<Id, Opportunity> deals = new Map<Id, Opportunity>([
            SELECT Id, RecordTypeId, StageName, First_Response_At__c, Warm_Up_Touches__c
            FROM Opportunity WHERE Id IN :dealIds
        ]);
        Map<Id, Opportunity> changed = new Map<Id, Opportunity>();
        for (Task task : completed) {
            Opportunity deal = deals.get(task.WhatId);
            if (deal == null || !Pipelines.isPipelineDeal(deal)) {
                continue;
            }
            if (task.Automation__c == Activities.A2_REPLY && deal.First_Response_At__c == null) {
                deal.First_Response_At__c = Datetime.now();
                changed.put(deal.Id, deal);
            }
            if (deal.StageName == Pipelines.WARM_UP) {
                deal.Warm_Up_Touches__c = (deal.Warm_Up_Touches__c == null ? 0 : deal.Warm_Up_Touches__c) + 1;
                changed.put(deal.Id, deal);
            }
        }
        update changed.values();
    }

    private static Set<String> closedStatuses() {
        Set<String> result = new Set<String>();
        for (TaskStatus status : [SELECT ApiName, MasterLabel FROM TaskStatus WHERE IsClosed = TRUE]) {
            result.add(status.ApiName);
            result.add(status.MasterLabel);
        }
        return result;
    }
}
