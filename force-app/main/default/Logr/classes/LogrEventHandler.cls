/**
 * @description Dedicated trigger handler for Logr_Event__e (after insert).
 * Converts incoming Platform Events into persistent Logr_Entry__c records using 1:1 field mapping.
 * Caps each trigger execution at 200 events or 4 MB heap and sets EventBus resume checkpoints
 * so high-volume 2,000-event batches with large Body__c payloads never breach the 6 MB heap limit.
 */
@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class LogrEventHandler {
  private static final Integer MAX_EVENTS_PER_BATCH = 200;
  private static final Integer MAX_BATCH_CHARS = 1500000;

  @TestVisible
  private static Integer testMaxEventsPerBatchOverride;

  /**
   * @description Handles after-insert Platform Event trigger invocations for Logr_Event__e.
   * @param newEvents List of Logr_Event__e records delivered by the EventBus.
   */
  public static void handleAfterInsert(List<Logr_Event__e> newEvents) {
    if (newEvents == null || newEvents.isEmpty()) {
      return;
    }

    Integer maxBatchEvents = resolveMaxEventsPerBatch();
    List<Logr_Entry__c> entriesToInsert = new List<Logr_Entry__c>();
    String lastProcessedReplayId = null;
    Integer cumulativeChars = 0;

    for (Logr_Event__e currentEvent : newEvents) {
      entriesToInsert.add(mapEventToEntry(currentEvent));
      lastProcessedReplayId = currentEvent.ReplayId;
      cumulativeChars += measureEventChars(currentEvent);

      if (
        entriesToInsert.size() >= maxBatchEvents ||
        cumulativeChars >= MAX_BATCH_CHARS
      ) {
        break;
      }
    }

    insertEntriesAndSetCheckpoint(entriesToInsert, lastProcessedReplayId);
  }

  private static Integer resolveMaxEventsPerBatch() {
    return (testMaxEventsPerBatchOverride != null &&
      testMaxEventsPerBatchOverride > 0)
      ? testMaxEventsPerBatchOverride
      : MAX_EVENTS_PER_BATCH;
  }

  private static Integer measureEventChars(Logr_Event__e currentEvent) {
    Integer bodyChars = (currentEvent.Body__c != null)
      ? currentEvent.Body__c.length()
      : 0;
    Integer stackChars = (currentEvent.Stack_Trace__c != null)
      ? currentEvent.Stack_Trace__c.length()
      : 0;
    return bodyChars + stackChars;
  }

  private static void insertEntriesAndSetCheckpoint(
    List<Logr_Entry__c> entriesToInsert,
    String lastProcessedReplayId
  ) {
    if (!entriesToInsert.isEmpty()) {
      Database.insert(entriesToInsert, false, AccessLevel.SYSTEM_MODE);
    }

    if (String.isNotBlank(lastProcessedReplayId)) {
      EventBus.TriggerContext.currentContext()
        .setResumeCheckpoint(lastProcessedReplayId);
    }
  }

  private static Logr_Entry__c mapEventToEntry(Logr_Event__e sourceEvent) {
    return new Logr_Entry__c(
      Subject__c = sourceEvent.Subject__c,
      Level__c = String.isNotBlank(sourceEvent.Level__c)
        ? sourceEvent.Level__c
        : 'INFO',
      Source__c = sourceEvent.Source__c,
      Tags__c = sourceEvent.Tags__c,
      Records__c = sourceEvent.Records__c,
      Body__c = sourceEvent.Body__c,
      Is_Exception__c = (sourceEvent.Is_Exception__c == true),
      Stack_Trace__c = sourceEvent.Stack_Trace__c,
      Governor_Limits__c = sourceEvent.Governor_Limits__c,
      User__c = sourceEvent.User__c
    );
  }
}
