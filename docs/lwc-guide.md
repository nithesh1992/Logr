# Lightning Web Components Guide

The `c/logr` module brings the exact same chainable `Logr.start(...)` API from Apex to Lightning Web Components. Every configuration and step method returns the logger instance, and `.save()` resolves to `Promise<boolean>` without ever throwing.

## Multi-Step Component Logging

Import `Logr` from `'c/logr'`, chain your context and steps, and call `log.save()` in your `finally` block:

```javascript
import { LightningElement, api } from "lwc";
import Logr from "c/logr";
import submitOrder from "@salesforce/apex/OrderController.submitOrder";

export default class CheckoutSummary extends LightningElement {
  @api recordId;

  async handleCheckout() {
    const log = Logr.start("Customer Checkout")
      .source("checkoutSummary")
      .tag("Checkout")
      .recordId(this.recordId);

    log.info("Submitting order to Apex controller");
    try {
      const result = await submitOrder({ orderId: this.recordId });
      log.debug("Order response", result);
    } catch (error) {
      // Accepts a JavaScript Error or an @AuraEnabled Apex error response
      log.error("Order submission failed", error);
    } finally {
      await log.save();
    }
  }
}
```

## One-Liners

Because every method chains cleanly, quick client error or telemetry logs take a single line with no positional arguments to remember:

```javascript
// Log a caught error
Logr.start("Checkout UI Crash").source("checkoutSummary").error(error).save();

// Log a user interaction with Direct DML
Logr.start("Quote Exported")
  .source("quoteHeader")
  .tag("PDF")
  .info("Export clicked")
  .saveDirect();
```

## Chainable API Reference

### Entry Point

```javascript
import Logr from "c/logr";

const log = Logr.start("Subject line");
// or: const log = new Logr('Subject line');
```

### Context Methods

| Method            | Accepted Input               | Description                                                          |
| :---------------- | :--------------------------- | :------------------------------------------------------------------- |
| `.subject(text)`  | `string`                     | Sets or updates `Subject__c`. Defaults to `'Client Log'` if omitted. |
| `.source(name)`   | `string`                     | Sets `Source__c`. Defaults to `'LWC'` if omitted.                    |
| `.tag(value)`     | `string`                     | Adds a single tag (deduplicated).                                    |
| `.tags(values)`   | `string[]` or `'Tag1, Tag2'` | Adds an array of tags or a comma-separated string.                   |
| `.recordId(id)`   | `string`                     | Adds a single Salesforce Record ID.                                  |
| `.recordIds(ids)` | `string[]` or `'001A, 001B'` | Adds an array of Record IDs or a comma-separated string.             |

### Step Methods

| Method                      | Signature                                    | Description                                                               |
| :-------------------------- | :------------------------------------------- | :------------------------------------------------------------------------ |
| `.fine(message, payload?)`  | `(string, any?)`                             | Appends a `FINE` step. Objects are pretty-printed as JSON.                |
| `.debug(message, payload?)` | `(string, any?)`                             | Appends a `DEBUG` step.                                                   |
| `.info(message, payload?)`  | `(string, any?)`                             | Appends an `INFO` step.                                                   |
| `.add(message, payload?)`   | `(string, any?)`                             | Shorthand alias for `.info()`.                                            |
| `.warn(message, payload?)`  | `(string, any?)`                             | Appends a `WARN` step and escalates severity to `WARN`.                   |
| `.error(...)`               | `(error)`<br>`(message)`<br>`(label, error)` | Escalates severity to `ERROR` and extracts the stack trace automatically. |

### Flexible `.error()` Handling

`log.error()` automatically inspects what you pass and formats both `Body__c` and `Stack_Trace__c`:

- **JavaScript `Error` (`TypeError`, `ReferenceError`, etc.)**: Extracts `error.name`, `error.message`, and the browser `error.stack`.
- **Apex `@AuraEnabled` Error (`{ body: { exceptionType, message, stackTrace } }`)**: Extracts the server exception type, message, and Apex stack trace.
- **UI API / Validation Error List (`{ body: [{ message }] }`)**: Joins all error messages cleanly.
- **Plain string (`.error('Invalid quantity')`)**: Logs an `ERROR` step without setting an exception stack trace.

### Save Methods

| Method             | Return Value       | Description                                                                                             |
| :----------------- | :----------------- | :------------------------------------------------------------------------------------------------------ |
| `.save(saveMode?)` | `Promise<boolean>` | Persists the log using the org's `Default_Save_Mode__c` (or an explicit `'DIRECT'` / `'EVENT'` string). |
| `.saveDirect()`    | `Promise<boolean>` | Forces synchronous DML (`DIRECT`).                                                                      |
| `.saveViaEvent()`  | `Promise<boolean>` | Forces publishing a `Logr_Event__e` Platform Event (`EVENT`).                                           |

::: info Reusable Logger Instances
After `.save()` resolves `true`, the logger clears its recorded steps, Record IDs, stack trace, and severity while keeping `subject`, `source`, and `tags` intact. If the network call fails, `.save()` resolves `false` without throwing and preserves the buffered steps.
:::

## Testing End-to-End with the Logr Playground Tab

This repository includes an unpackaged LWC test harness in `force-app/test/` (`c-logr-playground` surfaced on the **Logr Playground** tab) so you can fire real client-to-server logs in your org without cluttering the Unlocked Package:

```bash
sf project deploy start --source-dir force-app/test --target-org <org-alias>
sf org assign permset --name Logr_Playground_Access --target-org <org-alias>
```

Open the App Launcher, select **Logr Playground**, and use either the 5 one-click preset scenarios (Telemetry, Slow API Warning, Caught JS `TypeError`, Simulated Apex Error, and PII Regex Masking) or the interactive Custom Chain Builder.
