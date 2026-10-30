/**
 * @description End-to-end unit and bulk test suite for Logr public API,
 * LogrEventHandler / LogrEventTrigger, and LogrPurgeBatch.
 */
@IsTest
@SuppressWarnings(
  'PMD.ApexDoc,PMD.ApexUnitTestClassShouldHaveRunAs,PMD.MethodNamingConventions'
)
public class LogrTest {
  @TestSetup
  public static void setupTestPermissions() {
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
  private static void shouldPersistLogViaPlatformEvent_WhenDefaultSaveCalled() {
    // Given
    Account sampleAccount = new Account(Name = 'Logr Test Account');
    Database.insert(sampleAccount, AccessLevel.SYSTEM_MODE);

    // When
    Test.startTest();
    Logr logger = Logr.start('Order Fulfillment Telemetry')
      .tag('OMS')
      .tags(new List<String>{ 'Checkout', 'OMS' })
      .recordId(sampleAccount.Id)
      .recordIds(new List<SObject>{ sampleAccount })
      .recordIds(new Set<Id>{ sampleAccount.Id })
      .recordIds(new List<String>{ 'EXT-CORR-001' });

    logger.add('Validated order header');
    logger.add('Account Payload', sampleAccount);
    logger.info('Inventory reserved');
    logger.info('Step Metrics', new Map<String, Object>{ 'items' => 3 });
    logger.warn('High latency warning');
    logger.warn('Latency Details', '480ms');

    Database.SaveResult publishResult = logger.saveViaEvent();
    Test.getEventBus().deliver();
    Test.stopTest();

    // Then
    Assert.isNotNull(
      publishResult,
      'Expected a non-null SaveResult from EventBus.publish'
    );
    Assert.isTrue(
      publishResult.isSuccess(),
      'Expected Platform Event publish to succeed'
    );

    List<Logr_Entry__c> savedEntries = [
      SELECT
        Subject__c,
        Level__c,
        Source__c,
        Tags__c,
        Records__c,
        Body__c,
        Is_Exception__c,
        Stack_Trace__c,
        Governor_Limits__c,
        User__c
      FROM Logr_Entry__c
      WITH SYSTEM_MODE
    ];
    Assert.areEqual(
      1,
      savedEntries.size(),
      'Expected exactly 1 Logr_Entry__c record persisted via event'
    );
    Logr_Entry__c entry = savedEntries[0];
    Assert.areEqual(
      'Order Fulfillment Telemetry',
      entry.Subject__c,
      'Subject should match'
    );
    Assert.areEqual(
      'WARN',
      entry.Level__c,
      'Highest severity should escalate to WARN'
    );
    Assert.isTrue(
      entry.Source__c.contains('LogrTest'),
      'Source should auto-detect caller class LogrTest'
    );
    Assert.areEqual(
      'OMS, Checkout',
      entry.Tags__c,
      'Tags should be deduplicated and comma-separated'
    );
    Assert.isTrue(
      entry.Records__c.contains(sampleAccount.Id),
      'Records__c should contain the Account Id'
    );
    Assert.isTrue(
      entry.Records__c.contains('EXT-CORR-001'),
      'Records__c should contain external correlation Id'
    );
    Assert.isTrue(
      entry.Body__c.contains('----------'),
      'Body steps should be separated by ----------'
    );
    Assert.isFalse(
      entry.Is_Exception__c,
      'Is_Exception__c should be false for non-error log'
    );
    Assert.isTrue(
      entry.Governor_Limits__c.contains('CPU:'),
      'Governor_Limits__c should include CPU metrics'
    );
    Assert.areEqual(
      UserInfo.getUserName(),
      entry.User__c,
      'User__c should stamp running username'
    );
  }

  @IsTest
  private static void shouldPersistLogDirectly_WhenSaveDirectCalled() {
    // Given
    Logr logger = new Logr()
      .subject('Direct DML Save Test')
      .source('CustomService.run (SYNC)')
      .tag('DirectMode');

    // When
    Test.startTest();
    logger.info('Persisting directly without Platform Event');
    Database.SaveResult directResult = logger.saveDirect();
    Test.stopTest();

    // Then
    Assert.isNotNull(directResult, 'Expected SaveResult from direct insert');
    Assert.isTrue(directResult.isSuccess(), 'Direct DML insert should succeed');

    Logr_Entry__c savedEntry = [
      SELECT Subject__c, Level__c, Source__c, Tags__c, Body__c
      FROM Logr_Entry__c
      WHERE Id = :directResult.getId()
      WITH SYSTEM_MODE
    ];
    Assert.areEqual(
      'Direct DML Save Test',
      savedEntry.Subject__c,
      'Subject should match updated subject'
    );
    Assert.areEqual('INFO', savedEntry.Level__c, 'Level should be INFO');
    Assert.areEqual(
      'CustomService.run (SYNC)',
      savedEntry.Source__c,
      'Custom source override should persist'
    );
    Assert.areEqual('DirectMode', savedEntry.Tags__c, 'Tag should match');
  }

  @IsTest
  private static void shouldFlushDebugAndFineSteps_WhenErrorLoggedAndFlushEnabled() {
    // Given
    Logr normalLogger = Logr.start('Normal Info Transaction');
    normalLogger.fine('Fine detail skipped on normal info');
    normalLogger.debug(
      'Debug detail skipped on normal info',
      new Map<String, String>{ 'k' => 'v' }
    );
    normalLogger.info('Standard info step');

    Logr failingLogger = Logr.start('Failing Transaction');
    failingLogger.fine('Fine step preserved on error', 'fine-payload');
    failingLogger.debug('Debug step preserved on error');

    // When
    Test.startTest();
    normalLogger.saveDirect();
    try {
      Account invalidAccount = new Account();
      Database.insert(invalidAccount, AccessLevel.SYSTEM_MODE);
    } catch (Exception dmlException) {
      failingLogger.error('Account insert failed', dmlException);
    }
    failingLogger.saveDirect();
    Test.stopTest();

    // Then
    Map<String, Logr_Entry__c> entriesBySubject = new Map<String, Logr_Entry__c>();
    for (Logr_Entry__c entry : [
      SELECT Subject__c, Level__c, Body__c, Is_Exception__c, Stack_Trace__c
      FROM Logr_Entry__c
      WITH SYSTEM_MODE
    ]) {
      entriesBySubject.put(entry.Subject__c, entry);
    }

    Logr_Entry__c infoEntry = entriesBySubject.get('Normal Info Transaction');
    Assert.isFalse(
      infoEntry.Body__c.contains('Debug detail skipped'),
      'DEBUG step should not be persisted when transaction succeeds at INFO level'
    );
    Assert.isTrue(
      infoEntry.Body__c.contains('Standard info step'),
      'INFO step should be persisted'
    );

    Logr_Entry__c errorEntry = entriesBySubject.get('Failing Transaction');
    Assert.areEqual(
      'ERROR',
      errorEntry.Level__c,
      'Failing transaction should escalate to ERROR'
    );
    Assert.isTrue(errorEntry.Is_Exception__c, 'Is_Exception__c should be true');
    Assert.isNotNull(
      errorEntry.Stack_Trace__c,
      'Stack_Trace__c should be populated'
    );
    Assert.isTrue(
      errorEntry.Body__c.contains('Fine step preserved on error'),
      'FINE step should be flushed into Body__c when error occurs'
    );
    Assert.isTrue(
      errorEntry.Body__c.contains('Debug step preserved on error'),
      'DEBUG step should be flushed into Body__c when error occurs'
    );
  }

  @IsTest
  private static void shouldOverflowRecordIdsIntoBody_WhenRecordsListExceeds255Chars() {
    // Given
    List<String> twentyIds = new List<String>();
    for (Integer index = 10; index < 30; index++) {
      twentyIds.add('ORD-CORR-00000' + index);
    }

    // When
    Test.startTest();
    Logr logger = Logr.start('Record Overflow Test').recordIds(twentyIds);
    logger.info('Processing batch of 20 records');
    Database.SaveResult saveResult = logger.saveDirect();
    Test.stopTest();

    // Then
    Logr_Entry__c entry = [
      SELECT Records__c, Body__c
      FROM Logr_Entry__c
      WHERE Id = :saveResult.getId()
      WITH SYSTEM_MODE
    ];
    Assert.isTrue(
      entry.Records__c.length() <= 255,
      'Records__c must fit within 255 characters'
    );
    Assert.isTrue(
      entry.Body__c.contains('[Records Full List (20)]:'),
      'Full list of record IDs should overflow into Body__c'
    );
    Assert.isTrue(
      entry.Body__c.contains('ORD-CORR-0000029'),
      'Body__c should contain the trailing record ID that overflowed Records__c'
    );
  }

  @IsTest
  private static void shouldCaptureCalloutAndDmlResultsTelemetry_WhenHelpersCalled() {
    // Given
    HttpRequest req = new HttpRequest();
    req.setMethod('POST');
    req.setEndpoint('https://api.example.com/orders');
    req.setBody('{"orderId":"ORD-100"}');

    HttpResponse okRes = new HttpResponse();
    okRes.setStatusCode(200);
    okRes.setStatus('OK');
    okRes.setBody('{"status":"queued"}');

    HttpResponse warnRes = new HttpResponse();
    warnRes.setStatusCode(429);
    warnRes.setStatus('Too Many Requests');

    HttpResponse errRes = new HttpResponse();
    errRes.setStatusCode(503);
    errRes.setStatus('Service Unavailable');

    List<Account> accountsToInsert = new List<Account>{
      new Account(Name = 'Valid Account'),
      new Account()
    };

    // When
    Test.startTest();
    Logr logger = Logr.start('Integration & Partial DML Telemetry');
    logger.callout('Order Create 200', req, okRes);
    logger.callout('Order Rate Limit 429', req, warnRes);
    logger.callout('Order Outage 503', req, errRes);

    List<Database.SaveResult> dmlResults = Database.insert(
      accountsToInsert,
      false,
      AccessLevel.SYSTEM_MODE
    );
    logger.dmlResults('Insert Accounts', dmlResults, accountsToInsert);
    logger.error(
      'Additional labeled error payload',
      new Map<String, String>{ 'code' => 'E1' }
    );
    logger.error(
      'Labeled exception overload',
      new IllegalArgumentException('Labeled exception')
    );
    logger.error(new IllegalArgumentException('Direct exception argument'));
    logger.error('Plain string error message');
    logger.add(Blob.valueOf('binary payload'));

    Database.SaveResult saveResult = logger.saveDirect();
    Test.stopTest();

    // Then
    Logr_Entry__c entry = [
      SELECT Level__c, Is_Exception__c, Records__c, Body__c
      FROM Logr_Entry__c
      WHERE Id = :saveResult.getId()
      WITH SYSTEM_MODE
    ];
    Assert.areEqual(
      'ERROR',
      entry.Level__c,
      'Failed callout and partial DML failure should escalate to ERROR'
    );
    Assert.isTrue(entry.Is_Exception__c, 'Is_Exception__c should be true');
    Assert.isTrue(
      entry.Body__c.contains('POST https://api.example.com/orders'),
      'Callout endpoint should be logged'
    );
    Assert.isTrue(
      entry.Body__c.contains('Succeeded: 1, Failed: 1'),
      'DML summary counts should be logged'
    );
    Assert.isTrue(
      entry.Body__c.contains('[Blob: 14 bytes]'),
      'Blob payload should log byte size'
    );
  }

  @IsTest
  private static void shouldSupportFlowInvocableAndLwcAuraEnabled_WhenCalledFromDeclarativeAndClient() {
    // Given
    Logr.FlowLogRequest flowReq = new Logr.FlowLogRequest();
    flowReq.subject = 'Flow Fault Logged';
    flowReq.message = 'Failed to update Order status';
    flowReq.level = 'ERROR';
    flowReq.source = 'Order_After_Save_Flow';
    flowReq.tags = 'Flow, OMS';
    flowReq.recordId = 'ORD-CORR-FLOW-1';
    flowReq.faultMessage = 'FIELD_CUSTOM_VALIDATION_EXCEPTION: Order locked';
    flowReq.saveMode = 'DIRECT';

    // When
    Test.startTest();
    List<Logr.FlowLogResult> flowOutputs = Logr.saveFlowLogs(
      new List<Logr.FlowLogRequest>{ flowReq }
    );
    Boolean lwcSaved = Logr.saveClientLog(
      'LWC Checkout Error',
      'Card token expired',
      'ERROR',
      'checkoutSummary',
      'LWC, Stripe',
      'ORD-CORR-LWC-2',
      'TypeError: Cannot read properties of undefined\n  at CheckoutSummary.handlePay',
      'DIRECT'
    );
    Test.stopTest();

    // Then
    Assert.areEqual(1, flowOutputs.size(), 'Expected 1 FlowLogResult');
    Assert.isTrue(
      flowOutputs[0].isSuccess,
      'Flow log result should report success'
    );
    Assert.isTrue(lwcSaved, 'LWC saveClientLog should return true');

    List<Logr_Entry__c> entries = [
      SELECT Subject__c, Source__c, Level__c, Is_Exception__c, Stack_Trace__c
      FROM Logr_Entry__c
      WITH SYSTEM_MODE
      ORDER BY Subject__c ASC
    ];
    Assert.areEqual(
      2,
      entries.size(),
      'Both Flow and LWC entries should be persisted'
    );
    Assert.areEqual(
      'Order_After_Save_Flow (FLOW)',
      entries[0].Source__c,
      'Flow source should include (FLOW)'
    );
    Assert.areEqual(
      'checkoutSummary (LWC)',
      entries[1].Source__c,
      'LWC source should include (LWC)'
    );
    Assert.isTrue(
      entries[1].Stack_Trace__c.contains('TypeError'),
      'LWC stack trace should be stored'
    );
  }

  @IsTest
  private static void shouldRespectCustomSettingAndSaveAll_WhenConfigured() {
    // Given
    Database.insert(
      new Logr_Config__c(
        SetupOwnerId = UserInfo.getOrganizationId(),
        Enabled__c = true,
        Level__c = 'INFO',
        Default_Save_Mode__c = 'DIRECT',
        Flush_Debug_On_Error__c = true,
        Mask_Data__c = true,
        Retention_Days__c = 14
      ),
      AccessLevel.SYSTEM_MODE
    );

    // When
    Test.startTest();
    Logr firstLogger = Logr.start('Batch Item 1').info('Step 1');
    Logr secondLogger = Logr.start('Batch Item 2').warn('Step 2');
    List<Database.SaveResult> batchResults = Logr.saveAll();

    Logr.testConfigOverride = new Logr_Config__c(Enabled__c = false);
    Logr disabledLogger = Logr.start('Disabled Logger')
      .error('Should not persist');
    Database.SaveResult disabledResult = disabledLogger.save();
    Test.stopTest();

    // Then
    Assert.isNotNull(firstLogger, 'First logger created');
    Assert.isNotNull(secondLogger, 'Second logger created');
    Assert.areEqual(
      2,
      batchResults.size(),
      'saveAll() should persist both active loggers'
    );
    Assert.isNull(
      disabledResult,
      'Disabled logger should return null SaveResult'
    );
    Assert.areEqual(
      2,
      [SELECT COUNT() FROM Logr_Entry__c WITH SYSTEM_MODE],
      'Only the 2 enabled logs should exist'
    );
  }
}
