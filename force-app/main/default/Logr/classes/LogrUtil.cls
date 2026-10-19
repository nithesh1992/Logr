/**
 * @description Internal utility and persistence helper for Logr.
 * Encapsulates step formatting, error/DML/callout telemetry, Flow & LWC entry points,
 * caller/Quiddity detection, smart head/tail truncation, newline-chunked regex PII masking,
 * and governor-safe persistence.
 */
@SuppressWarnings(
  'PMD.ApexCRUDViolation,PMD.CyclomaticComplexity,PMD.CognitiveComplexity,PMD.ExcessiveParameterList,PMD.StdCyclomaticComplexity'
)
public without sharing class LogrUtil {
  public static final String STEP_DIVIDER = '\n----------\n';
  public static final Integer MAX_BODY_LENGTH = 130000;
  public static final Integer BODY_HEAD_LENGTH = 60000;
  public static final Integer BODY_TAIL_LENGTH = 65000;
  public static final Integer MAX_STACK_LENGTH = 32000;
  public static final Integer MAX_TEXT_255 = 255;
  public static final Integer MAX_USER_LENGTH = 80;
  private static final Integer MASK_CHUNK_SIZE = 2000;

  public static final Map<Logr.Level, Integer> LEVEL_RANK = new Map<Logr.Level, Integer>{
    Logr.Level.FINE => 1,
    Logr.Level.DEBUG => 2,
    Logr.Level.INFO => 3,
    Logr.Level.WARN => 4,
    Logr.Level.ERROR => 5
  };

  private static List<CompiledMaskRule> cachedMaskRules;

  public class ResolvedConfig {
    public Boolean isEnabled = true;
    public Logr.Level minimumLevel = Logr.Level.INFO;
    public Logr.SaveMode defaultSaveMode = Logr.SaveMode.EVENT;
    public Boolean flushDebugOnError = true;
    public Boolean maskData = true;
    public Integer retentionDays = 30;
  }

  private class CompiledMaskRule {
    public Pattern regexPattern;
    public String replacementToken;

    public CompiledMaskRule(Pattern regexPattern, String replacementToken) {
      this.regexPattern = regexPattern;
      this.replacementToken = replacementToken;
    }
  }

  /**
   * @description Appends a timestamped step to a Logr instance and updates its highest severity level.
   */
  public static Logr appendStep(
    Logr logger,
    Logr.Level stepLevel,
    String stepLabel,
    Object payload
  ) {
    Logr.Level effectiveLevel = (stepLevel != null)
      ? stepLevel
      : Logr.Level.INFO;
    if (
      !logger.hasExplicitLevel ||
      LEVEL_RANK.get(effectiveLevel) > LEVEL_RANK.get(logger.highestLevel)
    ) {
      logger.highestLevel = effectiveLevel;
      logger.hasExplicitLevel = true;
    }
    if (effectiveLevel == Logr.Level.ERROR) {
      logger.isExceptionFlag = true;
    }

    String serializedPayload = serializePayload(payload);
    if (String.isBlank(logger.subjectText)) {
      String candidateSubject = String.isNotBlank(stepLabel)
        ? stepLabel
        : serializedPayload;
      logger.subjectText = safeTruncate(candidateSubject, MAX_TEXT_255);
    }

    Long nowMs = System.currentTimeMillis();
    Long elapsedMs =
      nowMs -
      (logger.startTimestampMs != null ? logger.startTimestampMs : nowMs);
    String timestampPrefix =
      '[' +
      Datetime.now().formatGMT('HH:mm:ss.SSS') +
      ' | +' +
      elapsedMs +
      'ms | ' +
      effectiveLevel.name() +
      '] ';

    String stepBody;
    if (String.isNotBlank(stepLabel) && String.isNotBlank(serializedPayload)) {
      String separator = serializedPayload.contains('\n') ? ':\n' : ': ';
      stepBody = timestampPrefix + stepLabel + separator + serializedPayload;
    } else if (String.isNotBlank(stepLabel)) {
      stepBody = timestampPrefix + stepLabel;
    } else {
      stepBody = timestampPrefix + serializedPayload;
    }

    logger.steps.add(new Logr.LogStep(effectiveLevel, stepBody));
    logger.hasUnsavedSteps = true;
    return logger;
  }

  public static Logr appendErrorPayload(
    Logr logger,
    String stepLabel,
    Object payload
  ) {
    logger.isExceptionFlag = true;
    return appendStep(logger, Logr.Level.ERROR, stepLabel, payload);
  }

  /**
   * @description Extracts exception stack trace, causal chain, and any failed DmlException record IDs.
   */
  public static Logr appendException(
    Logr logger,
    String errorMessage,
    Exception caughtException
  ) {
    logger.isExceptionFlag = true;
    if (caughtException == null) {
      return appendStep(logger, Logr.Level.ERROR, null, errorMessage);
    }

    logger.exceptionStackTrace = formatExceptionDetails(caughtException);
    if (caughtException instanceof DmlException) {
      DmlException dmlError = (DmlException) caughtException;
      for (Integer rowIndex = 0; rowIndex < dmlError.getNumDml(); rowIndex++) {
        String failedId = dmlError.getDmlId(rowIndex);
        if (String.isNotBlank(failedId)) {
          logger.recordId(failedId);
        }
      }
    }

    String exceptionHeader =
      caughtException.getTypeName() +
      ': ' +
      caughtException.getMessage();
    String combinedMessage = String.isNotBlank(errorMessage)
      ? errorMessage + ' | ' + exceptionHeader
      : exceptionHeader;
    return appendStep(logger, Logr.Level.ERROR, null, combinedMessage);
  }

  /**
   * @description Formats HTTP callout telemetry and escalates severity on 4xx (WARN) or 5xx/null (ERROR).
   */
  public static Logr appendCallout(
    Logr logger,
    String calloutLabel,
    HttpRequest httpRequest,
    HttpResponse httpResponse
  ) {
    Logr.Level calloutLevel = Logr.Level.INFO;
    Integer statusCode = (httpResponse != null)
      ? httpResponse.getStatusCode()
      : 0;
    if (httpResponse == null || statusCode >= 500) {
      calloutLevel = Logr.Level.ERROR;
      logger.isExceptionFlag = true;
    } else if (statusCode >= 400) {
      calloutLevel = Logr.Level.WARN;
    }
    return appendStep(
      logger,
      calloutLevel,
      null,
      formatCalloutSummary(calloutLabel, httpRequest, httpResponse)
    );
  }

  /**
   * @description Inspects Database.SaveResult[] for partial DML outcomes, records affected IDs, and escalates on row errors.
   */
  public static Logr appendDmlResults(
    Logr logger,
    String operationLabel,
    List<Database.SaveResult> saveResults,
    List<SObject> sourceRecords
  ) {
    if (saveResults == null || saveResults.isEmpty()) {
      return logger;
    }
    Integer successCount = 0;
    Integer failureCount = 0;
    List<String> errorDetails = new List<String>();

    for (Integer index = 0; index < saveResults.size(); index++) {
      Database.SaveResult currentResult = saveResults[index];
      if (currentResult.isSuccess()) {
        successCount++;
        logger.recordId(currentResult.getId());
      } else {
        failureCount++;
        if (
          sourceRecords != null &&
          index < sourceRecords.size() &&
          sourceRecords[index]?.Id != null
        ) {
          logger.recordId(sourceRecords[index].Id);
        }
        for (Database.Error dbError : currentResult.getErrors()) {
          errorDetails.add(
            'Row ' +
              index +
              ' [' +
              dbError.getStatusCode() +
              ']: ' +
              dbError.getMessage()
          );
        }
      }
    }

    String summaryHeader =
      (String.isNotBlank(operationLabel) ? operationLabel : 'DML Results') +
      ' — Succeeded: ' +
      successCount +
      ', Failed: ' +
      failureCount;
    if (failureCount > 0) {
      logger.isExceptionFlag = true;
      return appendStep(
        logger,
        Logr.Level.ERROR,
        summaryHeader,
        String.join(errorDetails, '\n')
      );
    }
    return appendStep(logger, Logr.Level.INFO, null, summaryHeader);
  }

  /**
   * @description Bulk-safe handler for Flow @InvocableMethod requests.
   */
  public static List<Logr.FlowLogResult> saveFlowLogs(
    List<Logr.FlowLogRequest> flowRequests
  ) {
    List<Logr.FlowLogResult> flowResults = new List<Logr.FlowLogResult>();
    if (flowRequests == null || flowRequests.isEmpty()) {
      return flowResults;
    }

    ResolvedConfig currentConfig = resolveConfig(Logr.testConfigOverride);
    Map<Logr.SaveMode, List<Logr>> loggersByMode = new Map<Logr.SaveMode, List<Logr>>{
      Logr.SaveMode.EVENT => new List<Logr>(),
      Logr.SaveMode.DIRECT => new List<Logr>()
    };

    for (Logr.FlowLogRequest requestItem : flowRequests) {
      Logr flowLogger = createExternalLogger(
        requestItem.subject,
        'Flow Log',
        requestItem.source,
        'Flow',
        'FLOW',
        requestItem.tags,
        requestItem.recordId
      );

      Logr.Level requestedLevel = parseLevel(
        requestItem.level,
        Logr.Level.INFO
      );
      if (String.isNotBlank(requestItem.faultMessage)) {
        flowLogger.isExceptionFlag = true;
        flowLogger.exceptionStackTrace = requestItem.faultMessage;
        requestedLevel = Logr.Level.ERROR;
      }

      String bodyContent = String.isNotBlank(requestItem.message)
        ? requestItem.message
        : (String.isNotBlank(requestItem.faultMessage)
            ? requestItem.faultMessage
            : flowLogger.subjectText);
      appendStep(flowLogger, requestedLevel, null, bodyContent);

      Logr.SaveMode targetMode = parseSaveMode(
        requestItem.saveMode,
        currentConfig.defaultSaveMode
      );
      loggersByMode.get(targetMode).add(flowLogger);

      Logr.FlowLogResult resultItem = new Logr.FlowLogResult();
      resultItem.isSuccess = true;
      flowResults.add(resultItem);
    }

    for (Logr.SaveMode modeKey : loggersByMode.keySet()) {
      List<Logr> modeGroup = loggersByMode.get(modeKey);
      if (!modeGroup.isEmpty()) {
        saveMany(modeGroup, modeKey);
      }
    }
    return flowResults;
  }

  /**
   * @description Handler for LWC @AuraEnabled saveClientLog calls.
   */
  public static Boolean saveClientLog(
    String subject,
    String message,
    String level,
    String source,
    String tags,
    String recordId,
    String stackTrace,
    String saveMode
  ) {
    Logr clientLogger = createExternalLogger(
      subject,
      'Client Log',
      source,
      'LWC',
      'LWC',
      tags,
      recordId
    );

    Logr.Level clientLevel = parseLevel(level, Logr.Level.INFO);
    if (String.isNotBlank(stackTrace)) {
      clientLogger.isExceptionFlag = true;
      clientLogger.exceptionStackTrace = stackTrace;
      if (LEVEL_RANK.get(clientLevel) < LEVEL_RANK.get(Logr.Level.ERROR)) {
        clientLevel = Logr.Level.ERROR;
      }
    } else if (clientLevel == Logr.Level.ERROR) {
      clientLogger.isExceptionFlag = true;
    }

    appendStep(
      clientLogger,
      clientLevel,
      null,
      String.isNotBlank(message) ? message : clientLogger.subjectText
    );

    ResolvedConfig currentConfig = resolveConfig(Logr.testConfigOverride);
    Logr.SaveMode targetMode = parseSaveMode(
      saveMode,
      currentConfig.defaultSaveMode
    );
    Database.SaveResult saveResult = clientLogger.save(targetMode);
    return saveResult != null && saveResult.isSuccess();
  }

  private static Logr createExternalLogger(
    String rawSubject,
    String fallbackSubject,
    String rawSource,
    String defaultLabel,
    String contextBadge,
    String csvTags,
    String csvRecordIds
  ) {
    Logr logger = new Logr(
      String.isNotBlank(rawSubject) ? rawSubject : fallbackSubject
    );
    String formattedSource = String.isNotBlank(rawSource)
      ? (rawSource.contains('(')
          ? rawSource
          : rawSource + ' (' + contextBadge + ')')
      : defaultLabel + ' (' + contextBadge + ')';
    logger.source(formattedSource);
    if (String.isNotBlank(csvTags)) {
      logger.tags(csvTags.split(','));
    }
    if (String.isNotBlank(csvRecordIds)) {
      logger.recordIds(csvRecordIds.split(','));
    }
    return logger;
  }

  public static List<Database.SaveResult> saveAllPending(
    List<Logr> allLoggers,
    Logr.SaveMode explicitSaveMode
  ) {
    List<Logr> pendingLoggers = new List<Logr>();
    if (allLoggers != null) {
      for (Logr candidateLogger : allLoggers) {
        if (candidateLogger != null && candidateLogger.hasUnsavedSteps) {
          pendingLoggers.add(candidateLogger);
        }
      }
    }
    return saveMany(pendingLoggers, explicitSaveMode);
  }

  public static List<Database.SaveResult> saveMany(
    List<Logr> loggersToSave,
    Logr.SaveMode requestedMode
  ) {
    List<Database.SaveResult> emptyResults = new List<Database.SaveResult>();
    if (loggersToSave == null || loggersToSave.isEmpty()) {
      return emptyResults;
    }

    ResolvedConfig currentConfig = resolveConfig(Logr.testConfigOverride);
    if (!currentConfig.isEnabled) {
      for (Logr skippedLogger : loggersToSave) {
        if (skippedLogger != null) {
          skippedLogger.resetAfterSave();
        }
      }
      return emptyResults;
    }

    List<Logr_Entry__c> builtEntries = new List<Logr_Entry__c>();
    for (Logr loggerInstance : loggersToSave) {
      if (loggerInstance == null) {
        continue;
      }
      Logr_Entry__c entryRecord = buildLogEntry(loggerInstance, currentConfig);
      loggerInstance.resetAfterSave();
      if (entryRecord != null) {
        builtEntries.add(entryRecord);
      }
    }

    Logr.SaveMode effectiveMode = (requestedMode != null)
      ? requestedMode
      : currentConfig.defaultSaveMode;
    return persistEntries(builtEntries, effectiveMode);
  }

  private static Logr_Entry__c buildLogEntry(
    Logr logger,
    ResolvedConfig currentConfig
  ) {
    Integer minRank = LEVEL_RANK.get(currentConfig.minimumLevel);
    Integer highestRank = LEVEL_RANK.get(
      logger.highestLevel != null ? logger.highestLevel : Logr.Level.INFO
    );
    Boolean includeDebugSteps =
      currentConfig.flushDebugOnError &&
      logger.highestLevel == Logr.Level.ERROR;

    if (highestRank < minRank && !includeDebugSteps) {
      return null;
    }

    List<String> includedLines = new List<String>();
    for (Logr.LogStep currentStep : logger.steps) {
      Integer stepRank = LEVEL_RANK.get(currentStep.stepLevel);
      if (includeDebugSteps || stepRank >= minRank) {
        includedLines.add(currentStep.formattedLine);
      }
    }

    String resolvedRecordsField = null;
    if (!logger.recordIdList.isEmpty()) {
      String fullJoinedIds = String.join(logger.recordIdList, ', ');
      if (fullJoinedIds.length() <= MAX_TEXT_255) {
        resolvedRecordsField = fullJoinedIds;
      } else {
        resolvedRecordsField = packIdsWithinLimit(
          logger.recordIdList,
          MAX_TEXT_255
        );
        includedLines.add(
          '[Records Full List (' +
            logger.recordIdList.size() +
            ')]: ' +
            fullJoinedIds
        );
      }
    }

    if (includedLines.isEmpty() && String.isNotBlank(logger.subjectText)) {
      includedLines.add(logger.subjectText);
    }

    String rawBody = String.join(includedLines, STEP_DIVIDER);
    String truncatedBody = truncateBodySmart(rawBody);
    String truncatedStack = safeTruncate(
      logger.exceptionStackTrace,
      MAX_STACK_LENGTH
    );

    if (currentConfig.maskData) {
      truncatedBody = maskSensitiveText(
        truncatedBody,
        Logr.testMaskRulesOverride
      );
      truncatedStack = maskSensitiveText(
        truncatedStack,
        Logr.testMaskRulesOverride
      );
    }

    Long elapsedMs =
      System.currentTimeMillis() -
      (logger.startTimestampMs != null
        ? logger.startTimestampMs
        : System.currentTimeMillis());

    return new Logr_Entry__c(
      Subject__c = safeTruncate(
        String.isNotBlank(logger.subjectText)
          ? logger.subjectText
          : 'Log Entry',
        MAX_TEXT_255
      ),
      Level__c = (logger.highestLevel != null
          ? logger.highestLevel
          : Logr.Level.INFO)
        .name(),
      Source__c = safeTruncate(logger.sourceName, MAX_TEXT_255),
      Tags__c = logger.tagList.isEmpty()
        ? null
        : safeTruncate(String.join(logger.tagList, ', '), MAX_TEXT_255),
      Records__c = resolvedRecordsField,
      Body__c = truncatedBody,
      Is_Exception__c = (logger.isExceptionFlag == true),
      Stack_Trace__c = truncatedStack,
      Governor_Limits__c = buildGovernorLimitsSnapshot(elapsedMs),
      User__c = safeTruncate(UserInfo.getUserName(), MAX_USER_LENGTH)
    );
  }

  public static ResolvedConfig resolveConfig(Logr_Config__c testOverride) {
    ResolvedConfig resolved = new ResolvedConfig();
    Logr_Config__c activeSetting = (testOverride != null)
      ? testOverride
      : Logr_Config__c.getInstance();

    if (
      activeSetting == null || (testOverride == null && activeSetting.Id == null)
    ) {
      return resolved;
    }

    resolved.isEnabled = (activeSetting.Enabled__c == true);
    resolved.minimumLevel = parseLevel(activeSetting.Level__c, Logr.Level.INFO);
    resolved.defaultSaveMode = parseSaveMode(
      activeSetting.Default_Save_Mode__c,
      Logr.SaveMode.EVENT
    );
    resolved.flushDebugOnError = (activeSetting.Flush_Debug_On_Error__c == true);
    resolved.maskData = (activeSetting.Mask_Data__c == true);
    if (
      activeSetting.Retention_Days__c != null &&
      activeSetting.Retention_Days__c > 0
    ) {
      resolved.retentionDays = Integer.valueOf(activeSetting.Retention_Days__c);
    }
    return resolved;
  }

  public static Logr.Level parseLevel(
    String levelText,
    Logr.Level fallbackLevel
  ) {
    if (String.isBlank(levelText)) {
      return fallbackLevel;
    }
    String normalized = levelText.trim().toUpperCase();
    for (Logr.Level candidate : Logr.Level.values()) {
      if (candidate.name() == normalized) {
        return candidate;
      }
    }
    return fallbackLevel;
  }

  public static Logr.SaveMode parseSaveMode(
    String modeText,
    Logr.SaveMode fallbackMode
  ) {
    if (String.isBlank(modeText)) {
      return fallbackMode;
    }
    String normalized = modeText.trim().toUpperCase();
    if (normalized == 'DIRECT') {
      return Logr.SaveMode.DIRECT;
    }
    if (normalized == 'EVENT') {
      return Logr.SaveMode.EVENT;
    }
    return fallbackMode;
  }

  public static String detectCallerAndContext() {
    String callerLocation = 'Apex';
    String stackTrace = new DmlException().getStackTraceString();
    if (String.isNotBlank(stackTrace)) {
      for (String traceLine : stackTrace.split('\n')) {
        String trimmedLine = traceLine.trim();
        if (
          String.isNotBlank(trimmedLine) &&
          !trimmedLine.startsWith('Class.Logr.') &&
          !trimmedLine.startsWith('Class.Logr:') &&
          !trimmedLine.startsWith('Class.LogrUtil.') &&
          !trimmedLine.startsWith('Class.LogrUtil:')
        ) {
          callerLocation = extractCleanCallerName(trimmedLine);
          break;
        }
      }
    }
    return safeTruncate(
      callerLocation + ' (' + detectExecutionContext() + ')',
      MAX_TEXT_255
    );
  }

  private static String extractCleanCallerName(String stackLine) {
    String cleaned = stackLine;
    if (cleaned.startsWith('Class.')) {
      cleaned = cleaned.substringAfter('Class.');
    } else if (cleaned.startsWith('Trigger.')) {
      cleaned = cleaned.substringAfter('Trigger.');
    }
    if (cleaned.contains(':')) {
      cleaned = cleaned.substringBefore(':');
    }
    return String.isNotBlank(cleaned) ? cleaned.trim() : 'AnonymousApex';
  }

  private static String detectExecutionContext() {
    if (Trigger.isExecuting && Trigger.operationType != null) {
      return String.valueOf(Trigger.operationType);
    }
    Request currentReq = Request.getCurrent();
    Quiddity currentQuiddity = (currentReq != null)
      ? currentReq.getQuiddity()
      : null;
    if (currentQuiddity == null) {
      return 'SYNC';
    }
    switch on currentQuiddity {
      when QUEUEABLE {
        return 'QUEUEABLE';
      }
      when BATCH_APEX, BATCH_ACS, BATCH_CHUNK_PARALLEL, BATCH_CHUNK_SERIAL {
        return 'BATCH';
      }
      when FUTURE {
        return 'FUTURE';
      }
      when SCHEDULED {
        return 'SCHEDULED';
      }
      when AURA {
        return 'AURA';
      }
      when INVOCABLE_ACTION {
        return 'FLOW';
      }
      when REST {
        return 'REST';
      }
      when else {
        return currentQuiddity.name();
      }
    }
  }

  public static String formatCalloutSummary(
    String calloutLabel,
    HttpRequest httpRequest,
    HttpResponse httpResponse
  ) {
    List<String> summaryParts = new List<String>();
    if (String.isNotBlank(calloutLabel)) {
      summaryParts.add(calloutLabel);
    }
    if (httpRequest != null) {
      summaryParts.add(
        httpRequest.getMethod() + ' ' + httpRequest.getEndpoint()
      );
      if (String.isNotBlank(httpRequest.getBody())) {
        summaryParts.add('Request Body: ' + httpRequest.getBody());
      }
    }
    if (httpResponse != null) {
      summaryParts.add(
        'Status: ' +
          httpResponse.getStatusCode() +
          ' ' +
          String.valueOf(httpResponse.getStatus())
      );
      if (String.isNotBlank(httpResponse.getBody())) {
        summaryParts.add('Response Body: ' + httpResponse.getBody());
      }
    } else {
      summaryParts.add('Response: null');
    }
    return String.join(summaryParts, '\n');
  }

  public static String serializePayload(Object payload) {
    if (payload == null) {
      return '';
    }
    if (payload instanceof String) {
      return (String) payload;
    }
    if (payload instanceof Blob) {
      return '[Blob: ' + ((Blob) payload).size() + ' bytes]';
    }
    if (payload instanceof Exception) {
      return formatExceptionDetails((Exception) payload);
    }
    try {
      return JSON.serializePretty(payload);
    } catch (Exception serializationFailure) {
      return String.valueOf(payload);
    }
  }

  public static String formatExceptionDetails(Exception caughtException) {
    if (caughtException == null) {
      return null;
    }
    List<String> exceptionLines = new List<String>();
    Exception currentError = caughtException;
    Integer depth = 0;
    while (currentError != null && depth < 5) {
      String prefix = (depth == 0) ? '' : 'Caused by: ';
      exceptionLines.add(
        prefix + currentError.getTypeName() + ': ' + currentError.getMessage()
      );
      String traceText = currentError.getStackTraceString();
      if (String.isNotBlank(traceText)) {
        exceptionLines.add(traceText);
      }
      currentError = currentError.getCause();
      depth++;
    }
    return String.join(exceptionLines, '\n');
  }

  public static String packIdsWithinLimit(
    List<String> allIds,
    Integer maxChars
  ) {
    List<String> fittingIds = new List<String>();
    Integer currentLength = 0;
    for (String singleId : allIds) {
      Integer separatorLength = fittingIds.isEmpty() ? 0 : 2;
      if (currentLength + separatorLength + singleId.length() > maxChars) {
        break;
      }
      fittingIds.add(singleId);
      currentLength += separatorLength + singleId.length();
    }
    return fittingIds.isEmpty()
      ? safeTruncate(allIds[0], maxChars)
      : String.join(fittingIds, ', ');
  }

  public static String truncateBodySmart(String rawBody) {
    if (String.isBlank(rawBody) || rawBody.length() <= MAX_BODY_LENGTH) {
      return rawBody;
    }
    Integer omittedCount =
      rawBody.length() - (BODY_HEAD_LENGTH + BODY_TAIL_LENGTH);
    String marker =
      '\n... [TRUNCATED ' +
      omittedCount +
      ' CHARS BY LOGR] ...\n';
    return rawBody.substring(0, BODY_HEAD_LENGTH) +
      marker +
      rawBody.substring(rawBody.length() - BODY_TAIL_LENGTH);
  }

  public static String safeTruncate(String inputText, Integer maxLength) {
    if (String.isBlank(inputText)) {
      return inputText;
    }
    return inputText.length() <= maxLength
      ? inputText
      : inputText.substring(0, maxLength);
  }

  public static String maskSensitiveText(
    String inputText,
    List<Logr_Data_Mask_Rule__mdt> testRulesOverride
  ) {
    if (String.isBlank(inputText)) {
      return inputText;
    }
    List<CompiledMaskRule> activeRules = getCompiledMaskRules(testRulesOverride);
    if (activeRules.isEmpty()) {
      return inputText;
    }

    List<String> maskedChunks = new List<String>();
    Integer totalLength = inputText.length();
    Integer cursor = 0;
    Integer cpuThreshold = (Limits.getLimitCpuTime() * 80) / 100;

    while (cursor < totalLength) {
      if (Limits.getCpuTime() >= cpuThreshold) {
        maskedChunks.add(inputText.substring(cursor));
        break;
      }
      Integer windowEnd = Math.min(cursor + MASK_CHUNK_SIZE, totalLength);
      if (windowEnd < totalLength) {
        Integer lastNewlineIndex = inputText.lastIndexOf('\n', windowEnd);
        if (lastNewlineIndex > cursor) {
          windowEnd = lastNewlineIndex + 1;
        }
      }
      String currentChunk = inputText.substring(cursor, windowEnd);
      for (CompiledMaskRule rule : activeRules) {
        currentChunk = rule.regexPattern.matcher(currentChunk)
          .replaceAll(rule.replacementToken);
      }
      maskedChunks.add(currentChunk);
      cursor = windowEnd;
    }
    return String.join(maskedChunks, '');
  }

  private static List<CompiledMaskRule> getCompiledMaskRules(
    List<Logr_Data_Mask_Rule__mdt> testRulesOverride
  ) {
    if (cachedMaskRules != null && testRulesOverride == null) {
      return cachedMaskRules;
    }
    List<Logr_Data_Mask_Rule__mdt> rawRules = (testRulesOverride != null)
      ? testRulesOverride
      : [
          SELECT Regex__c, Replacement__c, Is_Active__c, Sort_Order__c
          FROM Logr_Data_Mask_Rule__mdt
          WHERE Is_Active__c = TRUE
          WITH SYSTEM_MODE
          ORDER BY Sort_Order__c ASC NULLS LAST
        ];

    List<CompiledMaskRule> compiledList = new List<CompiledMaskRule>();
    for (Logr_Data_Mask_Rule__mdt ruleRecord : rawRules) {
      if (ruleRecord.Is_Active__c && String.isNotBlank(ruleRecord.Regex__c)) {
        try {
          Pattern compiledPattern = Pattern.compile(ruleRecord.Regex__c);
          String replacementText = String.isNotBlank(ruleRecord.Replacement__c)
            ? ruleRecord.Replacement__c
            : '[REDACTED]';
          compiledList.add(
            new CompiledMaskRule(compiledPattern, replacementText)
          );
        } catch (Exception invalidRegexError) {
          continue;
        }
      }
    }
    if (testRulesOverride == null) {
      cachedMaskRules = compiledList;
    }
    return compiledList;
  }

  public static String buildGovernorLimitsSnapshot(Long elapsedMs) {
    Integer heapKb = Limits.getHeapSize() / 1024;
    Integer maxHeapKb = Limits.getLimitHeapSize() / 1024;
    String snapshot =
      'Time: ' +
      Math.max(0L, elapsedMs) +
      'ms | CPU: ' +
      Limits.getCpuTime() +
      '/' +
      Limits.getLimitCpuTime() +
      'ms | SOQL: ' +
      Limits.getQueries() +
      '/' +
      Limits.getLimitQueries() +
      ' | DML: ' +
      Limits.getDmlStatements() +
      '/' +
      Limits.getLimitDmlStatements() +
      ' | Heap: ' +
      heapKb +
      '/' +
      maxHeapKb +
      'KB';
    return safeTruncate(snapshot, MAX_TEXT_255);
  }

  public static List<Database.SaveResult> persistEntries(
    List<Logr_Entry__c> builtEntries,
    Logr.SaveMode effectiveMode
  ) {
    if (
      builtEntries == null ||
      builtEntries.isEmpty() ||
      Limits.getDmlStatements() >= Limits.getLimitDmlStatements() ||
      Limits.getDmlRows() + builtEntries.size() > Limits.getLimitDmlRows()
    ) {
      return new List<Database.SaveResult>();
    }
    if (effectiveMode == Logr.SaveMode.DIRECT) {
      return Database.insert(builtEntries, false, AccessLevel.SYSTEM_MODE);
    }
    List<Logr_Event__e> eventsToPublish = new List<Logr_Event__e>();
    for (Logr_Entry__c sourceEntry : builtEntries) {
      eventsToPublish.add(
        new Logr_Event__e(
          Subject__c = sourceEntry.Subject__c,
          Level__c = sourceEntry.Level__c,
          Source__c = sourceEntry.Source__c,
          Tags__c = sourceEntry.Tags__c,
          Records__c = sourceEntry.Records__c,
          Body__c = sourceEntry.Body__c,
          Is_Exception__c = (sourceEntry.Is_Exception__c == true),
          Stack_Trace__c = sourceEntry.Stack_Trace__c,
          Governor_Limits__c = sourceEntry.Governor_Limits__c,
          User__c = sourceEntry.User__c
        )
      );
    }
    return EventBus.publish(eventsToPublish);
  }
}
