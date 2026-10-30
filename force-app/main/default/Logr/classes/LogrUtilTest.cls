/**
 * @description Dedicated unit test suite for LogrUtil helper methods: configuration resolution,
 * caller & Quiddity detection, payload/exception/callout formatting, smart head/tail truncation,
 * ID packing, newline-chunked regex PII masking, and edge-case persistence handling.
 */
@IsTest
@SuppressWarnings(
  'PMD.ApexUnitTestClassShouldHaveRunAs,PMD.MethodNamingConventions'
)
private class LogrUtilTest {
  @TestSetup
  private static void setupTestPermissions() {
    LogrTest.setupTestPermissions();
  }

  @IsTest
  private static void shouldResolveZeroConfigAndCustomSettings_WhenResolveConfigAndParsersCalled() {
    // Given
    Logr_Config__c customConfig = new Logr_Config__c(
      Enabled__c = true,
      Level__c = 'DEBUG',
      Default_Save_Mode__c = 'DIRECT',
      Flush_Debug_On_Error__c = false,
      Mask_Data__c = false,
      Retention_Days__c = 15
    );

    // When
    Test.startTest();
    LogrUtil.ResolvedConfig zeroConfig = LogrUtil.resolveConfig(null);
    LogrUtil.ResolvedConfig resolvedCustom = LogrUtil.resolveConfig(
      customConfig
    );
    Logr.testConfigOverride = customConfig;
    Integer retentionFromLogr = Logr.getRetentionDays();

    Logr.Level parsedValidLevel = LogrUtil.parseLevel(
      ' fine ',
      Logr.Level.INFO
    );
    Logr.Level parsedBlankLevel = LogrUtil.parseLevel('', Logr.Level.WARN);
    Logr.Level parsedInvalidLevel = LogrUtil.parseLevel(
      'UNKNOWN_LEVEL',
      Logr.Level.ERROR
    );

    Logr.SaveMode parsedDirectMode = LogrUtil.parseSaveMode(
      ' direct ',
      Logr.SaveMode.EVENT
    );
    Logr.SaveMode parsedEventMode = LogrUtil.parseSaveMode(
      'EVENT',
      Logr.SaveMode.DIRECT
    );
    Logr.SaveMode parsedBlankMode = LogrUtil.parseSaveMode(
      null,
      Logr.SaveMode.EVENT
    );
    Logr.SaveMode parsedInvalidMode = LogrUtil.parseSaveMode(
      'INVALID',
      Logr.SaveMode.DIRECT
    );
    Test.stopTest();

    // Then
    Assert.isTrue(
      zeroConfig.isEnabled,
      'Zero-config should default to Enabled = true'
    );
    Assert.areEqual(
      Logr.Level.INFO,
      zeroConfig.minimumLevel,
      'Zero-config should default to INFO'
    );
    Assert.areEqual(
      Logr.SaveMode.EVENT,
      zeroConfig.defaultSaveMode,
      'Zero-config should default to EVENT'
    );
    Assert.areEqual(
      30,
      zeroConfig.retentionDays,
      'Zero-config should default to 30 retention days'
    );

    Assert.areEqual(
      Logr.Level.DEBUG,
      resolvedCustom.minimumLevel,
      'Custom config should resolve DEBUG level'
    );
    Assert.areEqual(
      Logr.SaveMode.DIRECT,
      resolvedCustom.defaultSaveMode,
      'Custom config should resolve DIRECT mode'
    );
    Assert.areEqual(
      15,
      retentionFromLogr,
      'Retention days should resolve to 15'
    );

    Assert.areEqual(
      Logr.Level.FINE,
      parsedValidLevel,
      'parseLevel should parse case-insensitive FINE'
    );
    Assert.areEqual(
      Logr.Level.WARN,
      parsedBlankLevel,
      'parseLevel should return fallback on blank'
    );
    Assert.areEqual(
      Logr.Level.ERROR,
      parsedInvalidLevel,
      'parseLevel should return fallback on unrecognized level'
    );

    Assert.areEqual(
      Logr.SaveMode.DIRECT,
      parsedDirectMode,
      'parseSaveMode should parse DIRECT'
    );
    Assert.areEqual(
      Logr.SaveMode.EVENT,
      parsedEventMode,
      'parseSaveMode should parse EVENT'
    );
    Assert.areEqual(
      Logr.SaveMode.EVENT,
      parsedBlankMode,
      'parseSaveMode should return fallback on null'
    );
    Assert.areEqual(
      Logr.SaveMode.DIRECT,
      parsedInvalidMode,
      'parseSaveMode should return fallback on invalid text'
    );
  }

  @IsTest
  private static void shouldFormatPayloadsCalloutsAndExceptions_WhenFormattingHelpersCalled() {
    // Given
    IllegalArgumentException rootCause = new IllegalArgumentException(
      'Root cause error'
    );
    CalloutException wrapperException = new CalloutException(
      'Wrapper callout error',
      rootCause
    );

    HttpRequest request = new HttpRequest();
    request.setMethod('GET');
    request.setEndpoint('https://api.example.com/health');

    // When
    Test.startTest();
    String detectedSource = LogrUtil.detectCallerAndContext();
    String nullPayloadText = LogrUtil.serializePayload(null);
    String stringPayloadText = LogrUtil.serializePayload('Plain string');
    String blobPayloadText = LogrUtil.serializePayload(
      Blob.valueOf('hello world')
    );
    String exceptionPayloadText = LogrUtil.serializePayload(wrapperException);
    String mapPayloadText = LogrUtil.serializePayload(
      new Map<String, Integer>{ 'count' => 5 }
    );
    String nullExceptionText = LogrUtil.formatExceptionDetails(null);
    String nullResponseCallout = LogrUtil.formatCalloutSummary(
      'Health Check Timeout',
      request,
      null
    );
    String limitsSnapshot = LogrUtil.buildGovernorLimitsSnapshot(125L);
    Test.stopTest();

    // Then
    Assert.isTrue(
      detectedSource.contains('LogrUtilTest'),
      'detectCallerAndContext should identify LogrUtilTest'
    );
    Assert.areEqual(
      '',
      nullPayloadText,
      'Null payload should serialize to empty string'
    );
    Assert.areEqual(
      'Plain string',
      stringPayloadText,
      'String payload should remain unchanged'
    );
    Assert.areEqual(
      '[Blob: 11 bytes]',
      blobPayloadText,
      'Blob payload should format byte length'
    );
    Assert.isTrue(
      exceptionPayloadText.contains('Caused by:'),
      'Nested exception should format causal chain'
    );
    Assert.isTrue(
      mapPayloadText.contains('"count" : 5'),
      'Map payload should serialize as pretty JSON'
    );
    Assert.isNull(
      nullExceptionText,
      'formatExceptionDetails(null) should return null'
    );
    Assert.isTrue(
      nullResponseCallout.contains('Response: null'),
      'Null HttpResponse should log Response: null'
    );
    Assert.isTrue(
      limitsSnapshot.contains('Time: 125ms'),
      'Governor limits snapshot should include elapsed time'
    );
  }

  @IsTest
  private static void shouldTruncateAndPackIdsSafely_WhenLimitsExceeded() {
    // Given
    String oversizedBody =
      'HEAD_START_' +
      'A'.repeat(70000) +
      '\n' +
      'Z'.repeat(70000) +
      '_TAIL_END';
    List<String> twentyIds = new List<String>();
    for (Integer index = 10; index < 30; index++) {
      twentyIds.add('0010000000000' + index + 'AAA');
    }
    List<String> singleHugeCorrelationId = new List<String>{ 'X'.repeat(300) };

    // When
    Test.startTest();
    String shortBody = LogrUtil.truncateBodySmart('Short body');
    String truncatedBody = LogrUtil.truncateBodySmart(oversizedBody);
    String blankTruncate = LogrUtil.safeTruncate('', 10);
    String packedStandardIds = LogrUtil.packIdsWithinLimit(twentyIds, 255);
    String packedHugeId = LogrUtil.packIdsWithinLimit(
      singleHugeCorrelationId,
      255
    );
    Test.stopTest();

    // Then
    Assert.areEqual(
      'Short body',
      shortBody,
      'Short body should not be truncated'
    );
    Assert.isTrue(
      truncatedBody.length() <= 131072,
      'Truncated body must fit within 131,072 chars'
    );
    Assert.isTrue(
      truncatedBody.startsWith('HEAD_START_'),
      'Head of oversized body should be preserved'
    );
    Assert.isTrue(
      truncatedBody.endsWith('_TAIL_END'),
      'Tail of oversized body should be preserved'
    );
    Assert.isTrue(
      truncatedBody.contains('TRUNCATED'),
      'Truncation marker should be inserted'
    );
    Assert.areEqual(
      '',
      blankTruncate,
      'Blank string should remain blank on safeTruncate'
    );
    Assert.isTrue(
      packedStandardIds.length() <= 255,
      'Packed IDs must not exceed 255 chars'
    );
    Assert.areEqual(
      255,
      packedHugeId.length(),
      'Single oversized correlation ID should be safely truncated to 255 chars'
    );
  }

  @IsTest
  private static void shouldScrubSensitivePiiAcrossNewlineChunks_WhenMaskSensitiveTextCalled() {
    // Given
    List<String> lines = new List<String>();
    for (Integer index = 0; index < 45; index++) {
      lines.add(
        'Line ' +
          index +
          ' padding text to cross 2000-character chunk boundary cleanly.'
      );
    }
    lines.add('Customer Email: jane.doe@example.com');
    lines.add('Customer SSN: 123-45-6789');
    lines.add('Customer Card: 4532 0151 1283 0366');
    lines.add('Customer Phone: (415) 555-2671');
    lines.add('Client IP: 192.168.1.105');
    String multiChunkPayload = String.join(lines, '\n');

    List<Logr_Data_Mask_Rule__mdt> customRulesWithInvalidRegex = new List<Logr_Data_Mask_Rule__mdt>{
      new Logr_Data_Mask_Rule__mdt(
        DeveloperName = 'Invalid_Rule',
        Regex__c = '[unclosed-group',
        Replacement__c = '[BROKEN]',
        Is_Active__c = true,
        Sort_Order__c = 1
      ),
      new Logr_Data_Mask_Rule__mdt(
        DeveloperName = 'Secret_Token_Rule',
        Regex__c = 'SECRET-[0-9]{4}',
        Replacement__c = null,
        Is_Active__c = true,
        Sort_Order__c = 2
      )
    };

    // When
    Test.startTest();
    String blankMasked = LogrUtil.maskSensitiveText('', null);
    String defaultMasked = LogrUtil.maskSensitiveText(multiChunkPayload, null);
    String customMasked = LogrUtil.maskSensitiveText(
      'Token is SECRET-9876',
      customRulesWithInvalidRegex
    );
    String emptyRulesMasked = LogrUtil.maskSensitiveText(
      'No rules active',
      new List<Logr_Data_Mask_Rule__mdt>()
    );
    Test.stopTest();

    // Then
    Assert.areEqual(
      '',
      blankMasked,
      'Blank input should return blank immediately'
    );
    Assert.isFalse(
      defaultMasked.contains('jane.doe@example.com'),
      'Email should be redacted'
    );
    Assert.isFalse(
      defaultMasked.contains('123-45-6789'),
      'SSN should be redacted'
    );
    Assert.isFalse(
      defaultMasked.contains('4532 0151 1283 0366'),
      'Credit card should be redacted'
    );
    Assert.isFalse(
      defaultMasked.contains('(415) 555-2671'),
      'US Phone should be redacted'
    );
    Assert.isFalse(
      defaultMasked.contains('192.168.1.105'),
      'IPv4 should be redacted'
    );
    Assert.isTrue(
      defaultMasked.contains('[REDACTED-EMAIL]'),
      'Email token should appear'
    );
    Assert.areEqual(
      'Token is [REDACTED]',
      customMasked,
      'Invalid regex should be skipped and null Replacement__c should default to [REDACTED]'
    );
    Assert.areEqual(
      'No rules active',
      emptyRulesMasked,
      'Empty rule list should return original text'
    );
  }

  @IsTest
  private static void shouldHandleEdgeCasesInAppendAndSaveHelpers_WhenNullOrSuccessfulInputsProvided() {
    // Given
    Account validAccount = new Account(Name = 'LogrUtil DML Success Account');
    List<Database.SaveResult> successfulDmlResults = Database.insert(
      new List<SObject>{ validAccount },
      false,
      AccessLevel.SYSTEM_MODE
    );
    Logr logger = new Logr();

    // When
    Test.startTest();
    LogrUtil.appendStep(logger, null, 'Step Label Only', null);
    LogrUtil.appendException(logger, 'Exception message without object', null);
    LogrUtil.appendCallout(logger, 'Null Response Callout', null, null);
    LogrUtil.appendDmlResults(
      logger,
      'Empty DML Results',
      new List<Database.SaveResult>(),
      null
    );
    LogrUtil.appendDmlResults(
      logger,
      'Successful DML Results',
      successfulDmlResults,
      new List<SObject>{ validAccount }
    );

    List<Logr.FlowLogResult> emptyFlowResults = LogrUtil.saveFlowLogs(
      new List<Logr.FlowLogRequest>()
    );
    List<Database.SaveResult> emptySaveMany = LogrUtil.saveMany(
      new List<Logr>(),
      Logr.SaveMode.DIRECT
    );
    List<Database.SaveResult> emptyPersist = LogrUtil.persistEntries(
      new List<Logr_Entry__c>(),
      Logr.SaveMode.DIRECT
    );
    Boolean clientErrorWithoutStack = LogrUtil.saveClientLog(
      null,
      null,
      'ERROR',
      null,
      null,
      null,
      null,
      'DIRECT'
    );
    Database.SaveResult loggerSaveResult = logger.saveDirect();
    Test.stopTest();

    // Then
    Assert.areEqual(
      0,
      emptyFlowResults.size(),
      'Empty Flow requests should return empty results'
    );
    Assert.areEqual(
      0,
      emptySaveMany.size(),
      'Empty saveMany should return empty results'
    );
    Assert.areEqual(
      0,
      emptyPersist.size(),
      'Empty persistEntries should return empty results'
    );
    Assert.isTrue(
      clientErrorWithoutStack,
      'saveClientLog with default values should succeed'
    );
    Assert.isTrue(
      loggerSaveResult.isSuccess(),
      'Logger saveDirect should succeed'
    );
    Assert.areEqual(
      'Step Label Only',
      [
        SELECT Subject__c
        FROM Logr_Entry__c
        WHERE Id = :loggerSaveResult.getId()
        WITH SYSTEM_MODE
      ]
      .Subject__c,
      'Blank initial subject should auto-populate from first step label'
    );
  }
}
