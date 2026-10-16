/**
 * A8: when the prepayment arrives (prepayment date and payment method both filled), the target date
 * for the full payment is calculated from the payment method's term (Payment_Term__mdt), and two control
 * tasks go to the chat manager: a reminder to the client before the target date, and a check on it.
 * The check task's due date is the target date. If the prepayment date or the method changes later,
 * the open control tasks move to the new dates instead of being duplicated.
 * Its database work runs in system mode on purpose: it acts for the business, whoever saved the record.
 */
public without sharing class PaymentControl {
    public static Date targetDate(Opportunity deal) {
        return deal.Prepayment_Date__c.addDays(SalesSettings.daysToFullPayment(deal.Payment_Method__c));
    }

    public static void afterSave(List<Opportunity> deals, Map<Id, Opportunity> oldMap) {
        List<Opportunity> prepaid = new List<Opportunity>();
        for (Opportunity deal : deals) {
            Opportunity old = oldMap == null ? null : oldMap.get(deal.Id);
            Boolean complete = deal.Prepayment_Date__c != null && deal.Payment_Method__c != null;
            Boolean changed = old == null || deal.Prepayment_Date__c != old.Prepayment_Date__c
                || deal.Payment_Method__c != old.Payment_Method__c;
            if (Pipelines.isPipelineDeal(deal) && complete && changed) {
                prepaid.add(deal);
            }
        }
        if (prepaid.isEmpty()) {
            return;
        }
        Map<Id, List<Task>> open = Activities.openTasks(new Map<Id, Opportunity>(prepaid).keySet(),
            new Set<String>{ Activities.A8_PAYMENT_REMINDER, Activities.A8_PAYMENT_CHECK });
        Map<Id, Id> chatManagers = Activities.chatManagers(prepaid);
        List<Task> tasks = new List<Task>();
        for (Opportunity deal : prepaid) {
            Date target = targetDate(deal);
            Date reminder = target.addDays(-SalesSettings.reminderDaysBefore(deal.Payment_Method__c));
            if (!open.containsKey(deal.Id)) {
                Id chatManager = chatManagers.get(deal.Id);
                tasks.add(Activities.datedTask(deal.Id, chatManager, Activities.A8_PAYMENT_REMINDER,
                    'Remind the client about the full payment', reminder));
                tasks.add(Activities.datedTask(deal.Id, chatManager, Activities.A8_PAYMENT_CHECK,
                    'Check the full payment has arrived', target));
                continue;
            }
            for (Task task : open.get(deal.Id)) {
                task.ActivityDate = task.Automation__c == Activities.A8_PAYMENT_CHECK ? target : reminder;
                tasks.add(task);
            }
        }
        upsert as system tasks;
    }
}
