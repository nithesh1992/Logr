# Configuration, Data Masking & Retention

Logr separates runtime configuration (Hierarchy Custom Settings) from deployable security rules (Custom Metadata Types) so admins can tune logging behavior in production without code deployments.

## Hierarchy Custom Settings (`Logr_Config__c`)

Because `Logr_Config__c` is a **Hierarchy Custom Setting**, Salesforce resolves settings in order from most specific to least specific:

1. **Running User** override (`SetupOwnerId = UserInfo.getUserId()`)
2. **Running User's Profile** override (`SetupOwnerId = UserInfo.getProfileId()`)
3. **Org-Wide Default**

If no `Logr_Config__c` record exists in the org yet, Logr falls back to in-memory defaults (`Enabled = true`, `Level = INFO`, `Default Save Mode = EVENT`, `Flush Debug On Error = true`, `Mask Data = true`, `Retention Days = 30`).

| Field                    | API Name                  | Default | Description                                                                                                                                                                  |
| :----------------------- | :------------------------ | :------ | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Enabled**              | `Enabled__c`              | `true`  | Master kill-switch for the target scope (Org, Profile, or User).                                                                                                             |
| **Level**                | `Level__c`                | `INFO`  | Minimum severity threshold (`FINE`, `DEBUG`, `INFO`, `WARN`, `ERROR`, or `OFF`) required to persist a `Logr_Entry__c`.                                                       |
| **Default Save Mode**    | `Default_Save_Mode__c`    | `EVENT` | `EVENT` publishes `Logr_Event__e` (`PublishImmediately`) to survive rollbacks; `DIRECT` performs synchronous DML.                                                            |
| **Flush Debug On Error** | `Flush_Debug_On_Error__c` | `true`  | Buffers `FINE` and `DEBUG` steps in memory even when `Level__c` is `INFO` or `WARN`. If an `ERROR` occurs in the same logger, all buffered steps are flushed into `Body__c`. |
| **Mask Data**            | `Mask_Data__c`            | `true`  | Scrubs `Subject__c`, `Body__c`, and `Stack_Trace__c` using active `Logr_Data_Mask_Rule__mdt` regex patterns before persistence.                                              |
| **Retention Days**       | `Retention_Days__c`       | `30`    | Number of days `LogrPurgeBatch` retains `Logr_Entry__c` records before deletion.                                                                                             |

## How Smart Debug Buffering Works

In most production orgs, logging every `DEBUG` step to the database on successful transactions wastes storage. With `Level__c = INFO` and `Flush_Debug_On_Error__c = true`:

- **Happy path (highest step is `INFO`)**: Only `INFO` and `WARN` steps are written to `Body__c`. `FINE` and `DEBUG` steps are discarded at `save()`.
- **Failure path (a step calls `.error(...)`)**: The logger keeps every `FINE` and `DEBUG` breadcrumb leading up to the crash and writes the complete timeline to `Body__c`.

## Declarative PII Data Masking (`Logr_Data_Mask_Rule__mdt`)

When `Mask_Data__c` is enabled, Logr runs active `Logr_Data_Mask_Rule__mdt` rules ordered by `Sort_Order__c` against `Subject__c`, `Body__c`, and `Stack_Trace__c` before DML or event publishing.

### Included Rules

| Rule DeveloperName | Sort Order | Target Pattern                             | Replacement        |
| :----------------- | :--------- | :----------------------------------------- | :----------------- |
| `US_SSN`           | `10`       | US Social Security Numbers (`XXX-XX-XXXX`) | `***-**-****`      |
| `Credit_Card`      | `20`       | 13 to 16 digit payment card numbers        | `[REDACTED-CC]`    |
| `Email_Address`    | `30`       | Standard email addresses                   | `[REDACTED-EMAIL]` |
| `US_Phone`         | `40`       | 10-digit US phone numbers                  | `[REDACTED-PHONE]` |
| `IPv4_Address`     | `50`       | IPv4 network addresses                     | `[REDACTED-IP]`    |

### Adding a Custom Masking Rule

1. Go to **Setup > Custom Metadata Types** and click **Manage Records** next to **Logr Data Mask Rule**.
2. Click **New** and enter:
   - **Label / Name**: For example, `Bearer Token`
   - **Is Active**: Checked
   - **Sort Order**: `15`
   - **Regex**: `(?i)Bearer\s+[A-Za-z0-9\-._~+/]+=*`
   - **Replacement**: `Bearer [REDACTED-TOKEN]`

::: warning Regex Safety
Logr wraps each regex evaluation in a `try/catch` block. If an admin enters a malformed regular expression in `Logr_Data_Mask_Rule__mdt`, Logr skips that rule rather than failing the transaction.
:::

## Automated Log Retention (`LogrPurgeBatch`)

`LogrPurgeBatch` implements both `Database.Batchable<SObject>` and `Schedulable`. It reads `Logr_Config__c.getOrgDefaults().Retention_Days__c` (default `30` days), deletes expired `Logr_Entry__c` records in system mode, and permanently empties them from the Recycle Bin (`Database.emptyRecycleBin`).

Schedule it nightly at 2:00 AM via Anonymous Apex:

```apex
System.schedule('Logr Nightly Purge', '0 0 2 * * ?', new LogrPurgeBatch());
```

Or run an immediate one-off cleanup with a custom retention window (for example, delete logs older than 7 days):

```apex
Database.executeBatch(new LogrPurgeBatch(7), 2000);
```

## Customizing the Event Subscriber Running User

By default, Logr's `LogrEventTrigger` executes under the standard **Automated Process** user (`autoproc`). In this mode:

- `Logr_Entry__c.CreatedById` is stamped as `Automated Process`.
- The actual executing user is preserved in `Logr_Entry__c.User__c`.

If your security policies require that system records be created by a named service account, or if you want to capture user-scoped debug traces on the event trigger, you can override the running user in your org:

1. Create or identify a dedicated integration/service user (e.g. `logr.service@yourcompany.com`) and assign the **Logr Admin** permission set.
2. In Salesforce Setup, go to **Platform Events > Logr Event > Subscriptions**, or deploy an updated `PlatformEventSubscriberConfig` with the target user:

```xml
<?xml version="1.0" encoding="UTF-8" ?>
<PlatformEventSubscriberConfig xmlns="http://soap.sforce.com/2006/04/metadata">
    <platformEventConsumer>LogrEventTrigger</platformEventConsumer>
    <batchSize>200</batchSize>
    <masterLabel>LogrEventTriggerConfig</masterLabel>
    <isProtected>false</isProtected>
    <numPartitions>2</numPartitions>
    <partitionKey>EventUuid</partitionKey>
    <user>logr.service@yourcompany.com</user>
</PlatformEventSubscriberConfig>
```
