# Architecture & Data Model

Logr is intentionally small so every file in the package has one clear responsibility.

## Package Inventory

| Layer                | Component                                                                      | Purpose                                                                                                                    |
| :------------------- | :----------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------- |
| **Apex API**         | `Logr.cls`                                                                     | Public chainable API for Apex, `@AuraEnabled` endpoint for LWC, and `@InvocableMethod` for Flow.                           |
| **Apex Engine**      | `LogrUtil.cls`                                                                 | Internal engine handling config evaluation, smart debug buffering, PII masking, governor limit snapshots, and persistence. |
| **Event Handler**    | `LogrEventHandler.cls` + `LogrEventTrigger.trigger`                            | Subscribes to `Logr_Event__e` (`after insert`) and inserts `Logr_Entry__c` records in `AccessLevel.SYSTEM_MODE`.           |
| **Retention**        | `LogrPurgeBatch.cls`                                                           | Scheduled batch job that deletes and hard-purges `Logr_Entry__c` records past `Retention_Days__c`.                         |
| **LWC**              | `c/logr` (`logr.js`)                                                           | Client-side chainable logger matching the Apex `Logr` API.                                                                 |
| **Storage & Config** | `Logr_Entry__c`, `Logr_Event__e`, `Logr_Config__c`, `Logr_Data_Mask_Rule__mdt` | Primary log object, rollback-safe platform event transport, hierarchy config, and regex PII rules.                         |
| **Analytics**        | 5 Reports + `Logr_Dashboard`                                                   | Pre-built Lightning dashboard and reports in `Logr_Reports` and `Logr_Dashboards`.                                         |

## Persistence Pipeline

1. **Capture**: Apex (`Logr.start()`), LWC (`c/logr`), or Flow (`Save Logr Entry`) collects steps, tags, record IDs, and stack traces.
2. **Filter & Enrich**: `LogrUtil` checks `Logr_Config__c` (`Enabled__c` and `Level__c`), resolves `Flush_Debug_On_Error__c`, captures a snapshot of current Governor Limits, and applies active `Logr_Data_Mask_Rule__mdt` regex patterns.
3. **Transport**:
   - **`EVENT` mode (default)**: Publishes `Logr_Event__e` via `EventBus.publish()`. Because `Logr_Event__e` is configured with `PublishImmediately`, the event is committed even if the originating transaction throws an unhandled exception or calls `Database.rollback(sp)`. `LogrEventTrigger` then writes the `Logr_Entry__c` record in an isolated transaction.
   - **`DIRECT` mode**: Inserts `Logr_Entry__c` synchronously via `Database.insert(entries, false, AccessLevel.SYSTEM_MODE)`.

## Governor Limit Snapshot Format

Every `Logr_Entry__c` captures key governor limits at the moment `save()` is called in `Governor_Limits__c`:

```text
SOQL: 12/100 (12%)
SOQL Rows: 450/50000 (0%)
DML: 2/150 (1%)
DML Rows: 15/10000 (0%)
CPU: 8420/10000ms (84%)*
Heap: 1240500/6000000B (20%)
```

Any resource that reaches **80% or more** of its transaction limit is automatically suffixed with an asterisk (`*`) so you can spot bottlenecks at a glance or filter for `Governor_Limits__c CONTAINS *` in list views and reports.

## Data Model (`Logr_Entry__c`)

| Field Label         | API Name             | Type                         | Description                                                                                                         |
| :------------------ | :------------------- | :--------------------------- | :------------------------------------------------------------------------------------------------------------------ |
| **Log Entry Name**  | `Name`               | Auto Number (`LOG-{000000}`) | Unique identifier.                                                                                                  |
| **Subject**         | `Subject__c`         | Text(255)                    | High-level summary of the operation or error.                                                                       |
| **Level**           | `Level__c`           | Picklist                     | Highest severity reached (`FINE`, `DEBUG`, `INFO`, `WARN`, `ERROR`).                                                |
| **Source**          | `Source__c`          | Text(255)                    | Originating Apex `Class.method`, LWC component, or Flow element.                                                    |
| **Body**            | `Body__c`            | Long Text Area(131072)       | Chronological step trace separated by `\n----------\n`. Truncated safely from the tail if over 131,072 characters.  |
| **Is Exception**    | `Is_Exception__c`    | Checkbox                     | `true` when an exception or fault occurred. Controls conditional visibility of `Stack_Trace__c` on the record page. |
| **Stack Trace**     | `Stack_Trace__c`     | Long Text Area(32768)        | Exception type, message, cause chain, and stack trace.                                                              |
| **Governor Limits** | `Governor_Limits__c` | Long Text Area(2048)         | Formatted governor limit snapshot with `*` markers at 80%+ usage.                                                   |
| **Tags**            | `Tags__c`            | Text(255)                    | Comma-separated tags for filtering and reporting.                                                                   |
| **Records**         | `Records__c`         | Text(255)                    | Comma-separated Salesforce Record IDs associated with the transaction.                                              |
| **User**            | `User__c`            | Lookup(`User`)               | Running user who generated the log entry.                                                                           |
