# Architecture, Data Model & Limitations

Logr stays small so you can read and understand the entire codebase in an afternoon.

## Package Structure

```text
force-app/main/default/Logr/
├── classes/                        Logr (API, Flow action, LWC endpoint) · LogrUtil (format, mask, persist)
│                                   LogrEventHandler · LogrPurgeBatch · 4 test classes
├── triggers/                       LogrEventTrigger
├── platformEventSubscriberConfigs/ LogrEventTriggerConfig (batch size 200, 2 parallel partitions)
├── lwc/logr/                       headless chainable logger + Jest tests
├── objects/                        Logr_Entry__c · Logr_Event__e · Logr_Config__c · Logr_Data_Mask_Rule__mdt
├── customMetadata/                 5 default mask rules
├── flexipages/ layouts/ tabs/      record page, layout, tab
├── dashboards/ reports/            1 dashboard, 5 reports
└── permissionsets/                 Logr_Admin · Logr_User
```

## Persistence Pipeline

1. **Buffer in Memory**: Apex (`Logr.start()`), Flow (`Save Logr Entry`), or LWC (`c/logr` calling `Logr.saveClientLog`) collects steps in memory with `+elapsedMs` timestamps.
2. **Filter, Truncate & Mask**:
   - **Level & Flush-on-Error**: If the unit of work reaches `ERROR` and `Flush_Debug_On_Error__c` is enabled, all buffered `FINE` and `DEBUG` steps are kept. Otherwise, steps below the user's configured `Level__c` are dropped.
   - **Middle Truncation (130k limit)**: `Body__c` holds up to 131,072 characters. If a log exceeds the safe limit, Logr keeps the **first 60,000** characters and the **last 65,000** characters, replacing the middle with `[TRUNCATED n CHARS]`. Preserving the tail ensures the final error step is never cut off.
   - **Regex Masking**: Active `Logr_Data_Mask_Rule__mdt` patterns scrub `Body__c` and `Stack_Trace__c`.
3. **Save Mode**:
   - **`EVENT` (default)**: Publishes `Logr_Event__e` with `PublishImmediately`, so the log is not rolled back when the surrounding transaction fails. `LogrEventTrigger` delegates to `LogrEventHandler` to insert `Logr_Entry__c`.
   - **`DIRECT`**: Inserts `Logr_Entry__c` immediately via `Database.insert(..., false, AccessLevel.SYSTEM_MODE)` and **is** rolled back if the transaction fails.

## High-Throughput Event Ingestion (`PlatformEventSubscriberConfig`)

Logr packages `LogrEventTriggerConfig.platformEventSubscriberConfig-meta.xml` to tune how the Salesforce event bus delivers events to `LogrEventTrigger`:

- **Native Batch Sizing (`batchSize = 200`)**: By default, Salesforce delivers up to 2,000 events in `Trigger.new`. If multiple logs contain large JSON bodies or deep stack traces, loading 2,000 records simultaneously can strain the 6 MB Apex heap limit before trigger logic even starts. Setting `batchSize = 200` ensures manageable transaction footprints at the delivery infrastructure layer.
- **Parallel Subscriptions (`numPartitions = 2`)**: Uses `partitionKey = EventUuid` to distribute event processing across two concurrent worker threads in parallel, doubling ingest throughput and preventing subscriber queue lag during bulk DML or integration surges.
- **Apex Checkpointing**: `LogrEventHandler` supplements this with `EventBus.TriggerContext.currentContext().setResumeCheckpoint(...)` to safeguard heap limits even if payloads vary widely within a batch.

## Execution Context & Governor Limits Snapshot

Each `Logr_Entry__c` stamps:

- **`Source__c`**: Automatically detects `Class.method (CONTEXT)` using the stack trace and `System.Request.getCurrent().getQuiddity()` (`SYNC`, `QUEUEABLE`, `BATCH`, `FUTURE`, trigger operation, `FLOW`, `AURA`, `REST`).
- **`Governor_Limits__c`**: Captures elapsed time and transaction limits at the moment `save()` runs (marking resources at 80% or higher with `*`):

```text
Time: 506ms | CPU: 48/10000ms | SOQL: 3/100 | DML: 1/150 | Heap: 124/6000KB
```

## Data Model (`Logr_Entry__c`)

| Field Label         | API Name             | Type                         | Description                                                                                             |
| :------------------ | :------------------- | :--------------------------- | :------------------------------------------------------------------------------------------------------ |
| **Log Entry Name**  | `Name`               | Auto Number (`LOG-{000000}`) | Unique identifier.                                                                                      |
| **Subject**         | `Subject__c`         | Text(255)                    | Summary of the unit of work (auto-filled from the first step if not set).                               |
| **Level**           | `Level__c`           | Picklist                     | Highest severity reached (`FINE`, `DEBUG`, `INFO`, `WARN`, `ERROR`).                                    |
| **Source**          | `Source__c`          | Text(255)                    | Originating `Class.method (CONTEXT)`, LWC component, or Flow element.                                   |
| **Body**            | `Body__c`            | Long Text Area(131072)       | Chronological step trace separated by `\n----------\n`.                                                 |
| **Is Exception**    | `Is_Exception__c`    | Checkbox                     | `true` when an exception or fault occurred. Controls visibility of `Stack_Trace__c` on the record page. |
| **Stack Trace**     | `Stack_Trace__c`     | Long Text Area(32768)        | Exception type, message, cause chain, and stack trace.                                                  |
| **Governor Limits** | `Governor_Limits__c` | Long Text Area(2048)         | Elapsed time and governor limits snapshot.                                                              |
| **Tags**            | `Tags__c`            | Text(255)                    | Comma-separated tags for filtering and reporting.                                                       |
| **Records**         | `Records__c`         | Text(255)                    | Comma-separated Record IDs or correlation IDs.                                                          |
| **User**            | `User__c`            | Lookup(`User`)               | Running user who generated the log entry.                                                               |

## Known Limitations

Read these before putting Logr in a regulated or high-volume org:

### Data Loss

- **Failed inserts are silent.** `LogrEventHandler` inserts with `allOrNone=false` and does not inspect the results. A rejected log record disappears without a trace.
- **Silent drops near limits.** If DML statements or rows are near the limit, `persistEntries` returns without saving or reporting.
- **Flow always reports success.** `Save Logr Entry` returns `isSuccess = true` even when logging is disabled or the save fails.
- **`DIRECT` mode rolls back** with the surrounding transaction.
- **One stack trace per entry.** The last exception wins. Earlier exception messages stay in the body, but not their stack traces.

### Privacy

- **Masking fails open under CPU pressure.** Above 80% of the CPU limit, the rest of the text is saved **unmasked**.
- **Masking works in 2,000-character windows split on newlines.** One long line, such as minified JSON from a callout, is cut at fixed points, so an email or card number can straddle a cut and escape the regex.
- **Only `Body__c` and `Stack_Trace__c` are masked.** `Subject__c` is auto-filled from the first step if you do not set one, and it is not masked. Tags, Records, Source, and `User__c` are not masked either.
- **Callouts log raw bodies and the full endpoint.** Headers are not logged, but tokens in a query string are, unless a rule matches them.

### Cost & Security

- **Debug payloads cost CPU and heap even when discarded.** They are serialized when you call `.debug()` because they might be needed after an error.
- **Create one logger per unit of work, not one per record in a loop.** Each `Logr` parses a stack trace on creation and stays in a static list for the transaction.
- **`saveClientLog` trusts its caller.** Any user with `Logr_User` can write entries with any level, source, and subject, and can pick `DIRECT`. That matters for Experience Cloud users as there is no rate limit.
- **LWC level filtering is coarse.** The component sends all its steps as one block at the highest level, so flush-on-error does not apply to client logs.
