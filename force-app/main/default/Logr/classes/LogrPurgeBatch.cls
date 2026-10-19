/**
 * @description Schedulable and Batchable job that deletes expired Logr_Entry__c records older than
 * Logr_Config__c.Retention_Days__c (default 30 days) and hard-purges them from the Recycle Bin.
 */
@SuppressWarnings('PMD.ApexCRUDViolation,PMD.EmptyStatementBlock')
global with sharing class LogrPurgeBatch implements Database.Batchable<SObject>, Schedulable {
  private static final Integer DEFAULT_BATCH_SIZE = 2000;
  private final Integer customRetentionDays;

  /**
   * @description Default constructor that reads Retention_Days__c from Logr_Config__c.
   */
  global LogrPurgeBatch() {
    this(null);
  }

  /**
   * @description Constructor allowing an explicit retention window override in days.
   * @param overrideRetentionDays Number of days of logs to retain.
   */
  global LogrPurgeBatch(Integer overrideRetentionDays) {
    this.customRetentionDays = overrideRetentionDays;
  }

  /**
   * @description Schedulable entry point to execute the purge batch with a 2,000-record scope.
   * @param schedulableContext Salesforce SchedulableContext.
   */
  global void execute(SchedulableContext schedulableContext) {
    Database.executeBatch(
      new LogrPurgeBatch(this.customRetentionDays),
      DEFAULT_BATCH_SIZE
    );
  }

  /**
   * @description Queries Logr_Entry__c records created prior to the configured retention cutoff date.
   * @param batchContext Salesforce BatchableContext.
   * @return Database.QueryLocator for expired Logr_Entry__c records.
   */
  global Database.QueryLocator start(Database.BatchableContext batchContext) {
    Integer effectiveDays = (this.customRetentionDays != null &&
      this.customRetentionDays > 0)
      ? this.customRetentionDays
      : Logr.getRetentionDays();
    Datetime cutoffTimestamp = System.now().addDays(-effectiveDays);
    return Database.getQueryLocator(
      [
        SELECT Id
        FROM Logr_Entry__c
        WHERE CreatedDate < :cutoffTimestamp
        WITH SYSTEM_MODE
      ]
    );
  }

  /**
   * @description Deletes expired Logr_Entry__c records in the current batch scope and empties them
   * from the Salesforce Recycle Bin.
   * @param batchContext Salesforce BatchableContext.
   * @param expiredLogs List of expired Logr_Entry__c records to delete.
   */
  global void execute(
    Database.BatchableContext batchContext,
    List<Logr_Entry__c> expiredLogs
  ) {
    if (expiredLogs == null || expiredLogs.isEmpty()) {
      return;
    }
    List<Database.DeleteResult> deleteResults = Database.delete(
      expiredLogs,
      false,
      AccessLevel.SYSTEM_MODE
    );
    List<Id> purgedIds = new List<Id>();
    for (Database.DeleteResult currentDeleteResult : deleteResults) {
      if (currentDeleteResult.isSuccess()) {
        purgedIds.add(currentDeleteResult.getId());
      }
    }
    if (!purgedIds.isEmpty()) {
      Database.emptyRecycleBin(purgedIds);
    }
  }

  /**
   * @description Post-processing hook executed when the purge batch completes.
   * @param batchContext Salesforce BatchableContext.
   */
  global void finish(Database.BatchableContext batchContext) {
    // No post-batch actions required
  }
}
