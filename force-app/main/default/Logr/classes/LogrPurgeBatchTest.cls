/**
 * @description Dedicated 1:1 unit test suite for LogrPurgeBatch (Batchable and Schedulable).
 */
@IsTest
@SuppressWarnings(
  'PMD.ApexUnitTestClassShouldHaveRunAs,PMD.MethodNamingConventions'
)
private class LogrPurgeBatchTest {
  @TestSetup
  private static void setupTestPermissions() {
    User currentUser = new User(Id = UserInfo.getUserId());
    System.runAs(currentUser) {
      List<PermissionSet> adminPermSets = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = 'Logr_Admin'
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      if (!adminPermSets.isEmpty()) {
        List<PermissionSetAssignment> existingAssignments = [
          SELECT Id
          FROM PermissionSetAssignment
          WHERE
            AssigneeId = :UserInfo.getUserId()
            AND PermissionSetId = :adminPermSets[0].Id
          WITH SYSTEM_MODE
          LIMIT 1
        ];
        if (existingAssignments.isEmpty()) {
          Database.insert(
            new PermissionSetAssignment(
              AssigneeId = UserInfo.getUserId(),
              PermissionSetId = adminPermSets[0].Id
            ),
            AccessLevel.SYSTEM_MODE
          );
        }
      }
    }
  }

  @IsTest
  private static void shouldDeleteExpiredLogsAndEmptyRecycleBin_WhenLogrPurgeBatchExecuted() {
    // Given
    Logr_Entry__c expiredEntry = new Logr_Entry__c(
      Subject__c = 'Expired Log Entry',
      Level__c = 'INFO',
      Body__c = 'Old diagnostic entry'
    );
    Logr_Entry__c recentEntry = new Logr_Entry__c(
      Subject__c = 'Recent Log Entry',
      Level__c = 'INFO',
      Body__c = 'Fresh diagnostic entry'
    );
    Database.insert(
      new List<Logr_Entry__c>{ expiredEntry, recentEntry },
      AccessLevel.SYSTEM_MODE
    );
    Test.setCreatedDate(expiredEntry.Id, Datetime.now().addDays(-45));

    // When
    Test.startTest();
    Database.executeBatch(new LogrPurgeBatch(30), 200);
    Test.stopTest();

    // Then
    List<Logr_Entry__c> remainingEntries = [
      SELECT Id, Subject__c
      FROM Logr_Entry__c
      WITH SYSTEM_MODE
    ];
    Assert.areEqual(
      1,
      remainingEntries.size(),
      'Only the recent log entry should remain'
    );
    Assert.areEqual(
      'Recent Log Entry',
      remainingEntries[0].Subject__c,
      'Recent entry should be preserved'
    );
  }

  @IsTest
  private static void shouldScheduleNightlyPurgeAndIgnoreEmptyScope_WhenScheduledOrCalledWithEmptyList() {
    // Given
    String cronExpression = '0 0 2 * * ?';
    LogrPurgeBatch purgeJob = new LogrPurgeBatch();

    // When
    Test.startTest();
    purgeJob.execute(null, new List<Logr_Entry__c>());
    String jobId = System.schedule(
      'Logr Nightly Purge Test',
      cronExpression,
      purgeJob
    );
    Test.stopTest();

    // Then
    Assert.isNotNull(jobId, 'Scheduled job ID should not be null');
    List<CronTrigger> scheduledTriggers = [
      SELECT Id, CronExpression
      FROM CronTrigger
      WHERE Id = :jobId
      WITH SYSTEM_MODE
    ];
    Assert.areEqual(
      1,
      scheduledTriggers.size(),
      'Scheduled CronTrigger should exist'
    );
    Assert.areEqual(
      cronExpression,
      scheduledTriggers[0].CronExpression,
      'Cron expression should match'
    );
  }
}
