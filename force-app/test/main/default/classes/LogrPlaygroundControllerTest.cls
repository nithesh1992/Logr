/**
 * @description Unit tests for LogrPlaygroundController.
 */
@IsTest
private class LogrPlaygroundControllerTest {
  @IsTest
  static void shouldPublishBulkEvents_WhenCountProvided() {
    Test.startTest();
    Integer published = LogrPlaygroundController.publishBulkEvents(250);
    Test.stopTest();

    Assert.areEqual(
      250,
      published,
      'Expected 250 events to be published successfully.'
    );
  }

  @IsTest
  static void shouldHandleNullOrZeroCount_WhenDefaultRequested() {
    Test.startTest();
    Integer publishedNull = LogrPlaygroundController.publishBulkEvents(null);
    Integer publishedZero = LogrPlaygroundController.publishBulkEvents(0);
    Test.stopTest();

    Assert.areEqual(
      250,
      publishedNull,
      'Expected default 250 events when count is null.'
    );
    Assert.areEqual(
      250,
      publishedZero,
      'Expected default 250 events when count is zero.'
    );
  }
}
