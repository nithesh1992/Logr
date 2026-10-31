/**
 * @description Controller for the unpackaged Logr Playground test harness.
 * Publishes bulk Logr_Event__e platform events for stress and load testing.
 */
@SuppressWarnings('PMD.ApexCRUDViolation')
public with sharing class LogrPlaygroundController {
  /**
   * @description Publishes a requested number of Logr_Event__e events in a single transaction.
   * @param count Number of events to publish (clamped between 1 and 500, default 250).
   * @return Number of successfully queued platform events.
   */
  @AuraEnabled
  public static Integer publishBulkEvents(Integer count) {
    Integer totalToPublish = (count != null &&
      count > 0 &&
      count <= 500)
      ? count
      : 250;
    List<Logr_Event__e> events = new List<Logr_Event__e>();
    for (Integer i = 1; i <= totalToPublish; i++) {
      events.add(
        new Logr_Event__e(
          Subject__c = 'Bulk Stress Test #' + i,
          Level__c = 'INFO',
          Source__c = 'logrPlayground.bulkBurst',
          Tags__c = 'stress-test,bulk',
          Body__c = 'Bulk test event ' +
            i +
            ' of ' +
            totalToPublish +
            ' testing PlatformEventSubscriberConfig 200 batch cap and 2 partitions.'
        )
      );
    }

    List<Database.SaveResult> results = EventBus.publish(events);
    Integer publishedCount = 0;
    for (Database.SaveResult sr : results) {
      if (sr.isSuccess()) {
        publishedCount++;
      }
    }
    return publishedCount;
  }
}
