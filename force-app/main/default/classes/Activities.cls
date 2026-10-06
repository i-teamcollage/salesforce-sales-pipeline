/**
 * Builds the tasks the automations create, and decides who gets them.
 * Every automated activity carries Automation__c, so an automation can find and move its own records.
 */
public without sharing class Activities {
    public static final String A1_REPEAT_FORM = 'A1_Repeat_Form';
    public static final String A2_REPLY = 'A2_Reply';
    public static final String A4_KEY_CALL = 'A4_Key_Call';
    public static final String A5_CONFIRM_24H = 'A5_Confirm_24h';
    public static final String A5_CONFIRM_1H = 'A5_Confirm_1h';
    public static final String A6_OBJECTION = 'A6_Objection';
    public static final String A8_PAYMENT_REMINDER = 'A8_Payment_Reminder';
    public static final String A8_PAYMENT_CHECK = 'A8_Payment_Check';

    /** A task due at an exact time (A2, A5): due date, exact deadline and a reminder. */
    public static Task timedTask(Id dealId, Id ownerId, String automation, String subject, Datetime dueAt) {
        Task task = baseTask(dealId, ownerId, automation, subject);
        moveTimedTask(task, dueAt);
        return task;
    }

    /** A task due on a day (A6, A8). */
    public static Task datedTask(Id dealId, Id ownerId, String automation, String subject, Date dueOn) {
        Task task = baseTask(dealId, ownerId, automation, subject);
        task.ActivityDate = dueOn;
        return task;
    }

    public static void moveTimedTask(Task task, Datetime dueAt) {
        task.Due_At__c = dueAt;
        task.ActivityDate = dueAt.date();
        task.IsReminderSet = true;
        task.ReminderDateTime = dueAt;
    }

    private static Task baseTask(Id dealId, Id ownerId, String automation, String subject) {
        return new Task(
            WhatId = dealId,
            OwnerId = ownerId,
            Subject = subject,
            Automation__c = automation,
            Priority = 'High',
            Status = 'Not Started'
        );
    }

    /**
     * The chat manager of each deal: its lead author, the chat manager who had the lead first.
     * When the lead author is missing or inactive, the deal owner gets the task instead.
     */
    public static Map<Id, Id> chatManagers(List<Opportunity> deals) {
        Set<Id> authorIds = new Set<Id>();
        for (Opportunity deal : deals) {
            if (deal.Lead_Author__c != null) {
                authorIds.add(deal.Lead_Author__c);
            }
        }
        Map<Id, User> active = new Map<Id, User>([SELECT Id FROM User WHERE Id IN :authorIds AND IsActive = TRUE]);
        Map<Id, Id> result = new Map<Id, Id>();
        for (Opportunity deal : deals) {
            Boolean usable = deal.Lead_Author__c != null && active.containsKey(deal.Lead_Author__c);
            result.put(deal.Id, usable ? deal.Lead_Author__c : deal.OwnerId);
        }
        return result;
    }

    /** Open tasks of one automation, by deal. */
    public static Map<Id, List<Task>> openTasks(Set<Id> dealIds, Set<String> automations) {
        Map<Id, List<Task>> result = new Map<Id, List<Task>>();
        for (Task task : [
            SELECT Id, WhatId, Automation__c, Due_At__c, ActivityDate, OwnerId
            FROM Task
            WHERE WhatId IN :dealIds AND Automation__c IN :automations AND IsClosed = FALSE
        ]) {
            if (!result.containsKey(task.WhatId)) {
                result.put(task.WhatId, new List<Task>());
            }
            result.get(task.WhatId).add(task);
        }
        return result;
    }
}
