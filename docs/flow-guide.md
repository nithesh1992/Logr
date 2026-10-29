# Flow Builder Guide

Logr exposes an Invocable Apex Action named **Save Logr Entry** (`Logr.saveFlowLogs`, under the `Logr` category in Flow Builder) so Record-Triggered, Screen, Scheduled, and Autolaunched Flows can write to the same `Logr_Entry__c` object as Apex and LWC.

## Adding Logr to a Flow

1. Open your Flow in **Flow Builder**.
2. Click **+** on either a normal execution path or a **Fault Path** and choose **Action**.
3. Filter by category **Logr** (or search for **Save Logr Entry**).
4. Configure the inputs below.

## Input Parameters

| Input Label                | API Name       | Required | Description                                                                                                                                                                    |
| :------------------------- | :------------- | :------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Subject**                | `subject`      | Yes      | Short headline for `Subject__c` (for example, `Opportunity Stage Sync Failed`).                                                                                                |
| **Message / Step Details** | `message`      | No       | Detailed message or variable snapshot for `Body__c`.                                                                                                                           |
| **Severity Level**         | `level`        | No       | `FINE`, `DEBUG`, `INFO`, `WARN`, or `ERROR`. Defaults to `INFO` (or `ERROR` when **Flow Fault Message** is populated).                                                         |
| **Flow / Element Source**  | `source`       | No       | Flow API name and element name (for example, `Opportunity_After_Save.Create_Invoice`). Defaults to `'Flow'`.                                                                   |
| **Tags (Comma-Separated)** | `tags`         | No       | Comma-separated tags such as `Billing, Flow, Opportunity`.                                                                                                                     |
| **Related Record ID(s)**   | `recordId`     | No       | Single Record ID (`{!$Record.Id}`) or comma-separated IDs.                                                                                                                     |
| **Flow Fault Message**     | `faultMessage` | No       | Bind to `{!$Flow.FaultMessage}` on a Fault Path. Automatically escalates severity to `ERROR`, sets `Is_Exception__c = true`, and stores the fault details in `Stack_Trace__c`. |
| **Save Mode Override**     | `saveMode`     | No       | `DIRECT` or `EVENT`. Leave blank to use the org default (`Logr_Config__c.Default_Save_Mode__c`).                                                                               |

## Output Parameters

| Output Label     | API Name     | Type      | Description                                                                                                                 |
| :--------------- | :----------- | :-------- | :-------------------------------------------------------------------------------------------------------------------------- |
| **Is Saved**     | `isSaved`    | `Boolean` | `true` if the log passed the user's `Logr_Config__c` threshold and was queued or inserted; `false` if filtered out.         |
| **Log Entry ID** | `logEntryId` | `Id`      | Populated with the `Logr_Entry__c.Id` when saved via `DIRECT` mode (`null` when published asynchronously via `EVENT` mode). |

## Fault Path Recipe

When a DML element or external callout fails inside a Flow:

1. Select the failing element (such as **Create Records** or **Update Records**) and click **Add Fault Path**.
2. On the Fault connector, add the **Save Logr Entry** action:
   - **Subject**: `Invoice Creation Fault`
   - **Flow / Element Source**: `Order_Fulfillment_Flow.Create_Invoice`
   - **Related Record ID(s)**: `{!$Record.Id}`
   - **Flow Fault Message**: `{!$Flow.FaultMessage}`
   - **Tags**: `Flow, Billing`
3. Keep **Save Mode Override** blank (or set to `EVENT`) so the log is published via `Logr_Event__e` (`PublishImmediately`) even if the Flow rolls back the transaction.

## Bulkification Across Interviews

Salesforce automatically batches Invocable Action calls when a Record-Triggered Flow runs on up to 200 records at once. `Logr.saveFlowLogs` processes the entire `List<FlowLogInput>` in a single bulkified `LogrUtil.saveFlowEntries` operation, consuming only 1 DML statement (or 1 `EventBus.publish` call) for the entire batch.
