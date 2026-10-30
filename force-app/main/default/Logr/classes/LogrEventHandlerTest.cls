/**
 * @description Dedicated 1:1 unit and bulk test suite for LogrEventHandler and LogrEventTrigger.
 */
@IsTest
@SuppressWarnings(
  'PMD.ApexUnitTestClassShouldHaveRunAs,PMD.MethodNamingConventions'
)
private class LogrEventHandlerTest {
  @TestSetup
  private static void setupTestPermissions() {
    LogrTest.setupTestPermissions();
  }

  @IsTest
  private static void shouldCheckpointAndCapEvents_WhenBulk251PlatformEventsPublished() {
    // Given: 251 Platform Events (exceeds the 200-event per-trigger-batch cap in LogrEventHandler)
    List<Logr_Event__e> bulkEvents = new List<Logr_Event__e>();
    for (Integer index = 0; index < 251; index++) {
      bulkEvents.add(
        new Logr_Event__e(
          Subject__c = 'Bulk Event #' + index,
          Level__c = (index == 0) ? null : 'INFO',
          Source__c = 'BulkService.execute (BATCH)',
          Body__c = 'Bulk payload #' + index,
          Is_Exception__c = (index == 0),
          Stack_Trace__c = (index == 0)
            ? 'Class.BulkService.execute: line 42'
            : null,
          User__c = UserInfo.getUserName()
        )
      );
    }

    // When
    Test.startTest();
    EventBus.publish(bulkEvents);
    Test.getEventBus().deliver();
    Test.getEventBus().deliver();
    Test.stopTest();

    // Then
    Integer persistedCount = [
      SELECT COUNT()
      FROM Logr_Entry__c
      WHERE Source__c = 'BulkService.execute (BATCH)'
      WITH SYSTEM_MODE
    ];
    Assert.areEqual(
      251,
      persistedCount,
      'All 251 Platform Events should be persisted across checkpointed trigger deliveries'
    );
  }

  @IsTest
  private static void shouldRespectCustomBatchLimitAndIgnoreEmptyInput_WhenHandleAfterInsertCalled() {
    // Given
    LogrEventHandler.testMaxEventsPerBatchOverride = 2;
    List<Logr_Event__e> threeEvents = new List<Logr_Event__e>{
      new Logr_Event__e(
        Subject__c = 'Cap Event 1',
        Level__c = 'INFO',
        Body__c = '1'
      ),
      new Logr_Event__e(
        Subject__c = 'Cap Event 2',
        Level__c = 'INFO',
        Body__c = '2'
      ),
      new Logr_Event__e(
        Subject__c = 'Cap Event 3',
        Level__c = 'INFO',
        Body__c = '3'
      )
    };

    // When
    Test.startTest();
    LogrEventHandler.handleAfterInsert(null);
    LogrEventHandler.handleAfterInsert(new List<Logr_Event__e>());
    LogrEventHandler.handleAfterInsert(threeEvents);
    Test.stopTest();

    // Then
    Integer insertedCount = [
      SELECT COUNT()
      FROM Logr_Entry__c
      WHERE Subject__c LIKE 'Cap Event %'
      WITH SYSTEM_MODE
    ];
    Assert.areEqual(
      2,
      insertedCount,
      'testMaxEventsPerBatchOverride = 2 should cap processing at 2 events in a single call'
    );
  }
}
