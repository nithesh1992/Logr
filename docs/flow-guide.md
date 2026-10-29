# Flow Builder Guide

Logr exposes an Invocable Apex Action named **Save Logr Entry** (`Logr.saveFlowLogs`, under the `Logr` category in Flow Builder) so Record-Triggered, Screen, Scheduled, and Autolaunched Flows can write to the same `Logr_Entry__c` object as Apex and LWC.

## Adding Logr to a Flow

1. Open your Flow in **Flow Builder**.
2. Click **+** on either a normal execution path or a **Fault Path** and choose **Action**.
3. Filter by category **Logr** (or search for **Save Logr Entry**).
4. Configure the inputs below.

## Input Parameters

| Input Label        | API Name       | Required | Description                                                                                                                                     |
| :----------------- | :------------- | :------- | :---------------------------------------------------------------------------------------------------------------------------------------------- |
| **Subject**        | `subject`      | Yes      | Short summary of the log entry (for example, `Opportunity Stage Sync Failed`).                                                                  |
| **Message / Body** | `message`      | No       | Detailed log message or payload for `Body__c`.                                                                                                  |
| **Level**          | `level`        | No       | `ERROR`, `WARN`, `INFO`, `DEBUG`, or `FINE`. Defaults to `INFO` (or `ERROR` when **Fault Message** is populated).                               |
| **Source**         | `source`       | No       | Flow API name or step name (for example, `Opportunity_After_Save.Create_Invoice`). Defaults to `'Flow'`.                                        |
| **Tags**           | `tags`         | No       | Comma-separated tags (for example, `OMS, Checkout`).                                                                                            |
| **Record ID(s)**   | `recordId`     | No       | Single or comma-separated record or correlation IDs (`{!$Record.Id}`).                                                                          |
| **Fault Message**  | `faultMessage` | No       | Bind to `{!$Flow.FaultMessage}` when logging a fault path. Forces `ERROR` level, sets `Is_Exception__c = true`, and populates `Stack_Trace__c`. |
| **Save Mode**      | `saveMode`     | No       | `EVENT` (default) or `DIRECT`. Leave blank to use `Default_Save_Mode__c` from `Logr_Config__c`.                                                 |

## Output Parameters

| Output Label   | API Name    | Type      | Description                                                                                         |
| :------------- | :---------- | :-------- | :-------------------------------------------------------------------------------------------------- |
| **Is Success** | `isSuccess` | `Boolean` | Returns `true` when the invocable action completes so the Flow path continues without interruption. |

## Fault Path Recipe

When a DML element or external callout fails inside a Flow:

1. Select the failing element (such as **Create Records** or **Update Records**) and click **Add Fault Path**.
2. On the Fault connector, add the **Save Logr Entry** action:
   - **Subject**: `Invoice Creation Fault`
   - **Source**: `Order_Fulfillment_Flow.Create_Invoice`
   - **Record ID(s)**: `{!$Record.Id}`
   - **Fault Message**: `{!$Flow.FaultMessage}`
   - **Tags**: `Flow, Billing`
3. Keep **Save Mode** blank (or set to `EVENT`) so the log is published via `Logr_Event__e` (`PublishImmediately`) even if the Flow rolls back the transaction.

## Bulkification Across Interviews

Salesforce batches Invocable Action calls when a Record-Triggered Flow runs on up to 200 records at once. `Logr.saveFlowLogs` processes the entire `List<FlowLogRequest>` in a single bulkified call, consuming only 1 DML statement or 1 `EventBus.publish` call for the batch.
