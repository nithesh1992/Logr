/**
 * @description Core fluent logging and telemetry API for Salesforce (Apex, Flow, and LWC).
 * Provides a clean, lightweight facade while delegating formatting, masking, and persistence to LogrUtil.
 */
@SuppressWarnings(
  'PMD.AvoidGlobalModifier,PMD.ApexDoc,PMD.ExcessivePublicCount,PMD.CyclomaticComplexity,PMD.CognitiveComplexity,PMD.ExcessiveParameterList,PMD.StdCyclomaticComplexity'
)
global with sharing class Logr {
  global enum Level {
    ERROR,
    WARN,
    INFO,
    DEBUG,
    FINE
  }

  global enum SaveMode {
    EVENT,
    DIRECT
  }

  public static List<Logr> activeTransactionLoggers = new List<Logr>();

  @TestVisible
  public static Logr_Config__c testConfigOverride;

  @TestVisible
  public static List<Logr_Data_Mask_Rule__mdt> testMaskRulesOverride;

  public String subjectText;
  public String sourceName;
  public Level highestLevel;
  public Boolean hasExplicitLevel;
  public Boolean isExceptionFlag;
  public String exceptionStackTrace;
  public Long startTimestampMs;
  public List<String> tagList;
  public List<String> recordIdList;
  public List<LogStep> steps;
  public Boolean hasUnsavedSteps;

  public class LogStep {
    public Level stepLevel;
    public String formattedLine;

    public LogStep(Level stepLevel, String formattedLine) {
      this.stepLevel = stepLevel;
      this.formattedLine = formattedLine;
    }
  }

  global Logr() {
    this(null);
  }

  global Logr(String initialSubject) {
    this.subjectText = initialSubject;
    this.sourceName = LogrUtil.detectCallerAndContext();
    this.highestLevel = Level.INFO;
    this.hasExplicitLevel = false;
    this.isExceptionFlag = false;
    this.exceptionStackTrace = null;
    this.startTimestampMs = System.currentTimeMillis();
    this.tagList = new List<String>();
    this.recordIdList = new List<String>();
    this.steps = new List<LogStep>();
    this.hasUnsavedSteps = false;
    activeTransactionLoggers.add(this);
  }

  global static Logr start() {
    return new Logr(null);
  }

  global static Logr start(String initialSubject) {
    return new Logr(initialSubject);
  }

  global Logr subject(String newSubject) {
    this.subjectText = newSubject;
    return this;
  }

  global Logr source(String customSource) {
    if (String.isNotBlank(customSource)) {
      this.sourceName = customSource.trim();
    }
    return this;
  }

  global Logr tag(String tagValue) {
    if (String.isNotBlank(tagValue)) {
      String trimmedTag = tagValue.trim();
      if (!this.tagList.contains(trimmedTag)) {
        this.tagList.add(trimmedTag);
      }
    }
    return this;
  }

  global Logr tags(Iterable<String> tagValues) {
    if (tagValues != null) {
      Iterator<String> tagIterator = tagValues.iterator();
      while (tagIterator.hasNext()) {
        this.tag(tagIterator.next());
      }
    }
    return this;
  }

  global Logr recordId(Id singleRecordId) {
    return (singleRecordId != null)
      ? this.recordId(String.valueOf(singleRecordId))
      : this;
  }

  global Logr recordId(String correlationOrRecordId) {
    if (String.isNotBlank(correlationOrRecordId)) {
      String cleanedId = correlationOrRecordId.trim();
      if (!this.recordIdList.contains(cleanedId)) {
        this.recordIdList.add(cleanedId);
        this.hasUnsavedSteps = true;
      }
    }
    return this;
  }

  global Logr recordIds(Set<Id> recordIdSet) {
    if (recordIdSet != null) {
      for (Id currentId : recordIdSet) {
        this.recordId(currentId);
      }
    }
    return this;
  }

  global Logr recordIds(Iterable<String> stringIdCollection) {
    if (stringIdCollection != null) {
      Iterator<String> stringIterator = stringIdCollection.iterator();
      while (stringIterator.hasNext()) {
        this.recordId(stringIterator.next());
      }
    }
    return this;
  }

  global Logr recordIds(List<SObject> sobjectRecords) {
    if (sobjectRecords != null) {
      for (SObject currentRecord : sobjectRecords) {
        if (currentRecord?.Id != null) {
          this.recordId(currentRecord.Id);
        }
      }
    }
    return this;
  }

  global Logr add(Object messageOrPayload) {
    return LogrUtil.appendStep(this, Level.INFO, null, messageOrPayload);
  }

  global Logr add(String stepLabel, Object payload) {
    return LogrUtil.appendStep(this, Level.INFO, stepLabel, payload);
  }

  global Logr fine(Object messageOrPayload) {
    return LogrUtil.appendStep(this, Level.FINE, null, messageOrPayload);
  }

  global Logr fine(String stepLabel, Object payload) {
    return LogrUtil.appendStep(this, Level.FINE, stepLabel, payload);
  }

  global Logr debug(Object messageOrPayload) {
    return LogrUtil.appendStep(this, Level.DEBUG, null, messageOrPayload);
  }

  global Logr debug(String stepLabel, Object payload) {
    return LogrUtil.appendStep(this, Level.DEBUG, stepLabel, payload);
  }

  global Logr info(Object messageOrPayload) {
    return LogrUtil.appendStep(this, Level.INFO, null, messageOrPayload);
  }

  global Logr info(String stepLabel, Object payload) {
    return LogrUtil.appendStep(this, Level.INFO, stepLabel, payload);
  }

  global Logr warn(Object messageOrPayload) {
    return LogrUtil.appendStep(this, Level.WARN, null, messageOrPayload);
  }

  global Logr warn(String stepLabel, Object payload) {
    return LogrUtil.appendStep(this, Level.WARN, stepLabel, payload);
  }

  global Logr error(Object messageOrException) {
    return (messageOrException instanceof Exception)
      ? LogrUtil.appendException(
          this,
          ((Exception) messageOrException).getMessage(),
          (Exception) messageOrException
        )
      : LogrUtil.appendErrorPayload(this, null, messageOrException);
  }

  global Logr error(String errorMessage, Exception caughtException) {
    return LogrUtil.appendException(this, errorMessage, caughtException);
  }

  global Logr error(String stepLabel, Object payload) {
    return (payload instanceof Exception)
      ? LogrUtil.appendException(this, stepLabel, (Exception) payload)
      : LogrUtil.appendErrorPayload(this, stepLabel, payload);
  }

  global Logr callout(
    String calloutLabel,
    HttpRequest httpRequest,
    HttpResponse httpResponse
  ) {
    return LogrUtil.appendCallout(
      this,
      calloutLabel,
      httpRequest,
      httpResponse
    );
  }

  global Logr dmlResults(
    String operationLabel,
    List<Database.SaveResult> saveResults,
    List<SObject> sourceRecords
  ) {
    return LogrUtil.appendDmlResults(
      this,
      operationLabel,
      saveResults,
      sourceRecords
    );
  }

  global Database.SaveResult save() {
    return this.save(
      LogrUtil.resolveConfig(testConfigOverride).defaultSaveMode
    );
  }

  global Database.SaveResult saveDirect() {
    return this.save(SaveMode.DIRECT);
  }

  global Database.SaveResult saveViaEvent() {
    return this.save(SaveMode.EVENT);
  }

  global Database.SaveResult save(SaveMode explicitSaveMode) {
    List<Database.SaveResult> results = LogrUtil.saveMany(
      new List<Logr>{ this },
      explicitSaveMode
    );
    return results.isEmpty() ? null : results[0];
  }

  global static List<Database.SaveResult> saveAll() {
    return saveAll(LogrUtil.resolveConfig(testConfigOverride).defaultSaveMode);
  }

  global static List<Database.SaveResult> saveAll(SaveMode explicitSaveMode) {
    return LogrUtil.saveAllPending(activeTransactionLoggers, explicitSaveMode);
  }

  public static Integer getRetentionDays() {
    return LogrUtil.resolveConfig(testConfigOverride).retentionDays;
  }

  @InvocableMethod(
    label='Save Logr Entry'
    description='Records a structured log entry from Flow using Logr (Platform Event or Direct DML).'
    category='Logr'
  )
  global static List<FlowLogResult> saveFlowLogs(
    List<FlowLogRequest> flowRequests
  ) {
    return LogrUtil.saveFlowLogs(flowRequests);
  }

  @AuraEnabled
  global static Boolean saveClientLog(
    String subject,
    String message,
    String level,
    String source,
    String tags,
    String recordId,
    String stackTrace,
    String saveMode
  ) {
    return LogrUtil.saveClientLog(
      subject,
      message,
      level,
      source,
      tags,
      recordId,
      stackTrace,
      saveMode
    );
  }

  public void resetAfterSave() {
    this.steps.clear();
    this.recordIdList.clear();
    this.exceptionStackTrace = null;
    this.isExceptionFlag = false;
    this.highestLevel = Level.INFO;
    this.hasExplicitLevel = false;
    this.hasUnsavedSteps = false;
    this.startTimestampMs = System.currentTimeMillis();
  }

  global class FlowLogRequest {
    @InvocableVariable(
      label='Subject'
      description='Short summary of the log entry'
      required=true
    )
    global String subject;

    @InvocableVariable(
      label='Message / Body'
      description='Detailed log message or payload'
    )
    global String message;

    @InvocableVariable(
      label='Level'
      description='ERROR, WARN, INFO, DEBUG, or FINE (default INFO)'
    )
    global String level;

    @InvocableVariable(label='Source' description='Flow API name or step name')
    global String source;

    @InvocableVariable(
      label='Tags'
      description='Comma-separated tags (e.g., OMS, Checkout)'
    )
    global String tags;

    @InvocableVariable(
      label='Record ID(s)'
      description='Single or comma-separated record/correlation IDs'
    )
    global String recordId;

    @InvocableVariable(
      label='Fault Message'
      description='Flow $Flow.FaultMessage when logging a fault path'
    )
    global String faultMessage;

    @InvocableVariable(
      label='Save Mode'
      description='EVENT (default) or DIRECT'
    )
    global String saveMode;
  }

  global class FlowLogResult {
    @InvocableVariable(
      label='Is Success'
      description='True if the log request was processed'
    )
    global Boolean isSuccess;
  }
}
