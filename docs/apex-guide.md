# Apex Logging Guide

The `Logr` class uses a chainable Unit-of-Work builder. Instead of inserting a new database record on every `debug()` or `info()` call, you start a logger for an operation, record steps as your code runs, and call `save()` once in a `finally` block.

## Basic Pattern

```apex
public class OrderService {
  public static void placeOrder(Order__c ord) {
    Logr log = Logr.start('Order Placement')
      .source('OrderService.placeOrder')
      .tag('Checkout')
      .record(ord);

    try {
      log.info('Validating order lines');
      log.debug('Order payload', ord);

      InventoryService.reserve(ord);
      log.info('Inventory reserved');
    } catch (Exception ex) {
      log.error('Order placement failed', ex);
      throw ex;
    } finally {
      log.save();
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

| Method                            | Description                                                                                                         |
| :-------------------------------- | :------------------------------------------------------------------------------------------------------------------ |
| `Logr.start(String subject)`      | Creates a new logger with the given subject (truncated safely to 255 characters).                                   |
| `.subject(String text)`           | Updates the subject on an existing logger.                                                                          |
| `.source(String sourceName)`      | Sets `Source__c` explicitly. If omitted, Logr automatically infers `ClassName.methodName` from the Apex call stack. |
| `.tag(String tag)`                | Adds a single tag to `Tags__c` (ignores blanks and duplicates).                                                     |
| `.tags(List<String> tags)`        | Adds multiple tags to `Tags__c`.                                                                                    |
| `.recordId(Id recordId)`          | Associates a single Salesforce Record ID with `Records__c`.                                                         |
| `.recordIds(Set<Id> / List<Id>)`  | Associates multiple Record IDs with `Records__c`.                                                                   |
| `.record(SObject record)`         | Extracts `record.Id` (if non-null) and adds it to `Records__c`.                                                     |
| `.records(List<SObject> records)` | Extracts all non-null IDs from a list of SObjects.                                                                  |

## Step Methods & Severity Escalation

Each step method appends a timestamped entry (`[HH:mm:ss.SSS | LEVEL]`) to the internal buffer and automatically escalates the parent `Logr_Entry__c.Level__c` to the highest severity recorded so far:

`FINE` < `DEBUG` < `INFO` < `WARN` < `ERROR`

| Method                     | Overloads                                                                                                    | Behavior                                                                                                                                                        |
| :------------------------- | :----------------------------------------------------------------------------------------------------------- | :-------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `.fine(...)`               | `(String message)`<br>`(String label, Object payload)`                                                       | Verbose step-by-step tracing. Payload objects are serialized with `JSON.serializePretty()`.                                                                     |
| `.debug(...)`              | `(String message)`<br>`(String label, Object payload)`                                                       | Variable inspection and intermediate payloads.                                                                                                                  |
| `.info(...)` / `.add(...)` | `(String message)`<br>`(String label, Object payload)`                                                       | High-level operational milestones. `.add()` is a shorthand alias for `.info()`.                                                                                 |
| `.warn(...)`               | `(String message)`<br>`(String label, Object payload)`                                                       | Recoverable issues, retries, or SLA warnings.                                                                                                                   |
| `.error(...)`              | `(Exception ex)`<br>`(String message)`<br>`(String label, Exception ex)`<br>`(String label, Object payload)` | Marks `Is_Exception__c = true` when an `Exception` is passed and captures the full exception type, message, cause chain, and stack trace into `Stack_Trace__c`. |

## Save Modes

| Method            | Description                                                                                                                                   |
| :---------------- | :-------------------------------------------------------------------------------------------------------------------------------------------- |
| `.save()`         | Uses `Default_Save_Mode__c` from `Logr_Config__c` (`EVENT` by default).                                                                       |
| `.saveDirect()`   | Forces synchronous DML (`Database.insert(..., AccessLevel.SYSTEM_MODE)`). Rollback-bound to the current transaction.                          |
| `.saveViaEvent()` | Forces publishing a `Logr_Event__e` Platform Event (`PublishImmediately`). Survives `Database.rollback()` and unhandled exceptions afterward. |
| `Logr.saveAll()`  | Bulk-saves all active `Logr` instances created during the current transaction in a single DML or `EventBus.publish()` call.                   |

## Stateful Batch & Queueable Pattern

`Logr` is safe to store as an instance variable in `Database.Stateful` batch jobs:

- Payloads passed to `.debug(label, obj)` or `.info(label, obj)` are converted to strings immediately, so live SObjects or unserializable references are never held on the heap across batch chunks.
- Calling `log.save()` at the end of `execute()` clears the step buffer, Record IDs, stack trace, and severity while keeping your `subject`, `source`, and `tags` ready for the next batch chunk.

```apex
public class AccountSyncBatch implements Database.Batchable<SObject>, Database.Stateful {
  private final Logr log = Logr.start('Account ERP Sync')
    .source('AccountSyncBatch')
    .tag('ERP');

  public Database.QueryLocator start(Database.BatchableContext bc) {
    return Database.getQueryLocator([SELECT Id, Name FROM Account]);
  }

  public void execute(Database.BatchableContext bc, List<Account> scope) {
    log.records(scope)
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
