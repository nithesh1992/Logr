# Apex Logging Guide

The `Logr` class uses a chainable Unit-of-Work builder. Instead of inserting a new database record on every `debug()` or `info()` call, you start a logger for an operation, record steps as your code runs, and call `save()` once in a `finally` block.

## Basic Pattern

```apex
public class OrderService {
  public void processOrder(Order ord, List<OrderItem> items) {
    Logr log = Logr.start('Process Customer Order').tag('OMS').recordId(ord.Id);

    log.add('Validated order header'); // alias for info()
    log.debug('Order items', items); // kept only if an ERROR follows

    try {
      HttpRequest req = SapClient.buildRequest(ord, items);
      HttpResponse res = new Http().send(req);
      log.callout('SAP Order Sync', req, res);

      Database.SaveResult[] results = Database.update(items, false);
      log.dmlResults('Update Order Items', results, items);
    } catch (Exception ex) {
      log.error('Order processing failed', ex);
    } finally {
      log.save(); // uses Default_Save_Mode__c
      // log.saveDirect();  // force DML
      // log.saveViaEvent();// force platform event
    }
  }
}
```

## One-Liners

Every method on `Logr` returns the `Logr` instance, so quick error or telemetry logs fit on a single line:

```apex
// Log a caught exception
Logr.start('Webhook Sync Failed').source('StripeWebhook').error(ex).save();

// Log an operational milestone
Logr.start('Nightly Pricing Sync').tag('Pricing').info('Synced 450 SKUs').save();
```

## Context Methods

Attach metadata at any point before calling `save()`:

| Method                                     | Description                                                                                                                                                                                            |
| :----------------------------------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Logr.start(String subject)`               | Creates a new logger with the given subject (or `Logr.start()` to fill the subject from the first step).                                                                                               |
| `.subject(String text)`                    | Updates the subject on an existing logger.                                                                                                                                                             |
| `.source(String customSource)`             | Sets `Source__c` explicitly. If omitted, Logr stamps `Class.method (CONTEXT)` using the call stack and `Quiddity` (`SYNC`, `QUEUEABLE`, `BATCH`, `FUTURE`, trigger operation, `FLOW`, `AURA`, `REST`). |
| `.tag(String tagValue)`                    | Adds a single tag to `Tags__c` (ignores blanks and duplicates).                                                                                                                                        |
| `.tags(Iterable<String> tagValues)`        | Adds multiple tags to `Tags__c`.                                                                                                                                                                       |
| `.recordId(Id singleRecordId)`             | Associates a single Salesforce Record ID with `Records__c`.                                                                                                                                            |
| `.recordId(String correlationOrRecordId)`  | Associates a Record ID or external correlation ID with `Records__c`.                                                                                                                                   |
| `.recordIds(Set<Id> recordIdSet)`          | Associates a set of Record IDs with `Records__c`.                                                                                                                                                      |
| `.recordIds(Iterable<String> stringIds)`   | Associates a collection of string IDs with `Records__c`.                                                                                                                                               |
| `.recordIds(List<SObject> sobjectRecords)` | Extracts all non-null IDs from a list of SObjects and adds them to `Records__c`.                                                                                                                       |

## Step Methods & Severity Escalation

Each step method appends a timestamped entry (`[HH:mm:ss.SSS | +elapsedMs | LEVEL]`) to the internal buffer and escalates the parent `Logr_Entry__c.Level__c` to the highest severity recorded so far:

`FINE` < `DEBUG` < `INFO` < `WARN` < `ERROR`

| Method                     | Overloads                                                                                                      | Behavior                                                                                                                                                   |
| :------------------------- | :------------------------------------------------------------------------------------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `.fine(...)`               | `(Object messageOrPayload)`<br>`(String stepLabel, Object payload)`                                            | Verbose step-by-step tracing. Payload objects are serialized to JSON.                                                                                      |
| `.debug(...)`              | `(Object messageOrPayload)`<br>`(String stepLabel, Object payload)`                                            | Variable inspection and intermediate payloads.                                                                                                             |
| `.info(...)` / `.add(...)` | `(Object messageOrPayload)`<br>`(String stepLabel, Object payload)`                                            | Operational milestones. `.add()` is a shorthand alias for `.info()`.                                                                                       |
| `.warn(...)`               | `(Object messageOrPayload)`<br>`(String stepLabel, Object payload)`                                            | Recoverable issues, retries, or SLA warnings.                                                                                                              |
| `.error(...)`              | `(Object messageOrException)`<br>`(String errorMessage, Exception ex)`<br>`(String stepLabel, Object payload)` | Marks `Is_Exception__c = true` when an `Exception` is passed and captures the exception type, message, cause chain, and stack trace into `Stack_Trace__c`. |

## Built-In Callout & DML Helpers

| Method             | Signature                                                                           | Behavior                                                                                                                                                                                               |
| :----------------- | :---------------------------------------------------------------------------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `.callout(...)`    | `(String calloutLabel, HttpRequest req, HttpResponse res)`                          | Records the HTTP method, endpoint, status code, request body, and response body. Automatically escalates step severity to `WARN` on `4xx` responses and `ERROR` on `5xx` or `null` responses.          |
| `.dmlResults(...)` | `(String operationLabel, List<Database.SaveResult> results, List<SObject> records)` | Summarizes partial DML outcomes (`Database.insert/update(..., false)`), collects successful Record IDs into `Records__c`, and logs row-level error messages and escalates severity if any rows failed. |

## Save Modes

| Method                      | Description                                                                                                                                   |
| :-------------------------- | :-------------------------------------------------------------------------------------------------------------------------------------------- |
| `.save()`                   | Uses `Default_Save_Mode__c` from `Logr_Config__c` (`EVENT` by default).                                                                       |
| `.saveDirect()`             | Forces synchronous DML (`Database.insert(..., false, AccessLevel.SYSTEM_MODE)`). Rollback-bound to the current transaction.                   |
| `.saveViaEvent()`           | Forces publishing a `Logr_Event__e` Platform Event (`PublishImmediately`). Survives `Database.rollback()` and unhandled exceptions afterward. |
| `.save(Logr.SaveMode mode)` | Accepts `Logr.SaveMode.EVENT` or `Logr.SaveMode.DIRECT` explicitly.                                                                           |
| `Logr.saveAll()`            | Bulk-saves all active `Logr` instances created during the current transaction in a single DML or `EventBus.publish()` call.                   |

## Stateful Batch & Queueable Pattern

`Logr` is safe to store as an instance variable in `Database.Stateful` batch jobs:

- Payloads passed to `.debug(label, obj)` or `.info(label, obj)` are converted to strings immediately when added, so live SObjects are not held in the step list across batch chunks.
- Calling `log.save()` at the end of `execute()` clears the step buffer, Record IDs, stack trace, and severity while keeping your `subject`, `source`, and `tags` ready for the next chunk.

```apex
public class AccountSyncBatch implements Database.Batchable<SObject>, Database.Stateful {
  private final Logr log = Logr.start('Account ERP Sync')
    .source('AccountSyncBatch')
    .tag('ERP');

  public Database.QueryLocator start(Database.BatchableContext bc) {
    return Database.getQueryLocator([SELECT Id, Name FROM Account]);
  }

  public void execute(Database.BatchableContext bc, List<Account> scope) {
    log.recordIds(scope)
      .info(
        'Processing chunk',
        new Map<String, Object>{ 'size' => scope.size() }
      );
    try {
      ErpClient.push(scope);
    } catch (Exception ex) {
      log.error('Chunk failed', ex);
    } finally {
      log.save(); // Flushes this chunk and resets steps for the next execute()
    }
  }

  public void finish(Database.BatchableContext bc) {
    log.info('Batch completed').save();
  }
}
```
