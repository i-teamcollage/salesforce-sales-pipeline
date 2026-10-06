/**
 * A4: booking a key call makes the closer the owner, stamps the booking date and creates the meeting.
 *     The 3-hour rule is the validation rule Key_Call_At_Least_3_Hours_Ahead.
 * A5: two confirmation tasks for the chat manager, 24 hours and 1 hour before the call.
 * TR4: a repeat-sales deal continues in New clients, as the same record, once its call is booked.
 * A6: a deal moves to Key call held only when its key-call meeting has a recording link.
 * A reschedule is a new booking: the meeting and the open confirmation tasks move with the call.
 */
public without sharing class KeyCallService {
    public static final Integer CALL_MINUTES = 60;
    public static final String RECORDING_MESSAGE =
        'Add the call recording link to the key call meeting before moving the deal to Key call held.';

    /** A booking: the call time or the closer was set or changed on a New clients or Repeat sales deal. */
    public static Boolean isBooking(Opportunity deal, Opportunity old) {
        Boolean bookable = Pipelines.isIn(deal, Pipelines.NEW_CLIENTS) || Pipelines.isIn(deal, Pipelines.REPEAT_SALES);
        if (!bookable || deal.Key_Call_At__c == null || deal.Closer__c == null) {
            return false;
        }
        return old == null || deal.Key_Call_At__c != old.Key_Call_At__c || deal.Closer__c != old.Closer__c;
    }

    public static void beforeSave(List<Opportunity> deals, Map<Id, Opportunity> oldMap) {
        for (Opportunity deal : deals) {
            Opportunity old = oldMap == null ? null : oldMap.get(deal.Id);
            if (!isBooking(deal, old)) {
                continue;
            }
            deal.OwnerId = deal.Closer__c;
            deal.Key_Call_Booked_On__c = Date.today();
            if (Pipelines.isIn(deal, Pipelines.REPEAT_SALES) && !Pipelines.isClosed(deal.StageName)) {
                deal.RecordTypeId = Pipelines.recordTypeId(Pipelines.NEW_CLIENTS);
                deal.StageName = Pipelines.KEY_CALL_SCHEDULED;
            }
        }
    }

    public static void afterSave(List<Opportunity> deals, Map<Id, Opportunity> oldMap) {
        List<Opportunity> booked = new List<Opportunity>();
        for (Opportunity deal : deals) {
            if (isBooking(deal, oldMap == null ? null : oldMap.get(deal.Id))) {
                booked.add(deal);
            }
        }
        if (booked.isEmpty()) {
            return;
        }
        Set<Id> ids = new Map<Id, Opportunity>(booked).keySet();
        Map<Id, Event> upcoming = new Map<Id, Event>();
        for (Event meeting : [
            SELECT Id, WhatId FROM Event
            WHERE WhatId IN :ids AND Automation__c = :Activities.A4_KEY_CALL AND StartDateTime > :Datetime.now()
            ORDER BY StartDateTime
        ]) {
            if (!upcoming.containsKey(meeting.WhatId)) {
                upcoming.put(meeting.WhatId, meeting);
            }
        }
        Map<Id, List<Task>> open = Activities.openTasks(
            ids, new Set<String>{ Activities.A5_CONFIRM_24H, Activities.A5_CONFIRM_1H });
        Map<Id, Id> chatManagers = Activities.chatManagers(booked);
        List<Event> events = new List<Event>();
        List<Task> tasks = new List<Task>();
        for (Opportunity deal : booked) {
            Event meeting = upcoming.containsKey(deal.Id)
                ? upcoming.get(deal.Id)
                : new Event(WhatId = deal.Id, Subject = 'Key call', Automation__c = Activities.A4_KEY_CALL);
            meeting.OwnerId = deal.Closer__c;
            meeting.StartDateTime = deal.Key_Call_At__c;
            meeting.EndDateTime = deal.Key_Call_At__c.addMinutes(CALL_MINUTES);
            events.add(meeting);

            Datetime dayBefore = confirmationTime(deal.Key_Call_At__c, 24);
            Datetime hourBefore = confirmationTime(deal.Key_Call_At__c, 1);
            if (!open.containsKey(deal.Id)) {
                Id chatManager = chatManagers.get(deal.Id);
                tasks.add(Activities.timedTask(deal.Id, chatManager, Activities.A5_CONFIRM_24H,
                    'Confirm the key call (24 hours before)', dayBefore));
                tasks.add(Activities.timedTask(deal.Id, chatManager, Activities.A5_CONFIRM_1H,
                    'Confirm the key call (1 hour before)', hourBefore));
                continue;
            }
            for (Task task : open.get(deal.Id)) {
                Activities.moveTimedTask(task, task.Automation__c == Activities.A5_CONFIRM_24H ? dayBefore : hourBefore);
                tasks.add(task);
            }
        }
        upsert events;
        upsert tasks;
    }

    /** Due a number of hours before the call, or now when that moment has already passed. */
    public static Datetime confirmationTime(Datetime callAt, Integer hoursBefore) {
        Datetime due = callAt.addHours(-hoursBefore);
        Datetime now = Datetime.now();
        return due < now ? now : due;
    }

    /** A6: moving to Key call held needs a recording link on the deal's key-call meeting. */
    public static void requireRecording(List<Opportunity> deals, Map<Id, Opportunity> oldMap) {
        List<Opportunity> moving = new List<Opportunity>();
        for (Opportunity deal : deals) {
            if (Pipelines.isIn(deal, Pipelines.NEW_CLIENTS) && deal.StageName == Pipelines.KEY_CALL_HELD
                && oldMap.get(deal.Id).StageName != Pipelines.KEY_CALL_HELD) {
                moving.add(deal);
            }
        }
        if (moving.isEmpty()) {
            return;
        }
        Set<Id> movingIds = new Map<Id, Opportunity>(moving).keySet();
        Set<Id> withRecording = new Set<Id>();
        for (Event meeting : [
            SELECT WhatId FROM Event
            WHERE WhatId IN :movingIds AND Automation__c = :Activities.A4_KEY_CALL AND Recording_URL__c != NULL
        ]) {
            withRecording.add(meeting.WhatId);
        }
        for (Opportunity deal : moving) {
            if (!withRecording.contains(deal.Id)) {
                deal.addError(RECORDING_MESSAGE);
            }
        }
    }
}
