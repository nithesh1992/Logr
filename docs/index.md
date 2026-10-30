---
layout: home

hero:
  name: "Logr"
  text: "One unit of work, one log record."
  tagline: "A small logging and telemetry framework for Salesforce. Capture steps, callouts, DML outcomes, and exceptions across Apex, LWC, and Flow in one readable record."
  actions:
    - theme: brand
      text: Get Started
      link: /getting-started
    - theme: alt
      text: Apex Guide
      link: /apex-guide
    - theme: alt
      text: LWC Guide
      link: /lwc-guide
    - theme: alt
      text: View on GitHub
      link: https://github.com/nithesh1992/Logr

features:
  - title: One Record Per Transaction
    details: Buffer every step in memory and write a single chronological story instead of scattered child rows.
  - title: Same Chain in Apex & LWC
    details: Use the same fluent builder on the server and in the browser, plus a single invocable action in Flow.
  - title: Flush Debug on Error
    details: Run quietly at Info level in production and keep verbose Debug steps only when a transaction fails.
  - title: Survives Rollbacks
    details: Publish logs through Platform Events so failure traces still land when a transaction rolls back.
  - title: Callout & DML Summaries
    details: Record HTTP requests, status codes, and partial DML outcomes with a single method call.
  - title: Small Enough to Own
    details: Four Apex classes and one trigger, with regex PII masking, five reports, and a nightly cleanup job built in.
---

## What a Logr Entry Record Looks Like

You read the story of one failure top to bottom, in one place. No joining child rows, no digging through 24-hour debug logs.

**Individual fields on `Logr_Entry__c`:**

```text
Subject__c:         Order Fulfillment
Level__c:           ERROR (highest step)
Source__c:          OrderService.fulfillOrder (QUEUEABLE)
Governor_Limits__c: Time: 506ms | CPU: 48/10000ms | SOQL: 3/100 | DML: 1/150 | Heap: 124/6000KB
```

**Execution trace inside `Body__c`:**

```text
[14:22:01.104 | +0ms   | INFO ] Validated order header
----------
[14:22:01.189 | +85ms  | DEBUG] Order lines: [ { "Id": "802g7000000xyz1AAA", "Quantity": 2 } ]
----------
[14:22:01.610 | +506ms | ERROR] SAP Order API
POST https://api.sap.example.com/v1/orders
Request Body: {"orderId":"EXT-ORD-9941","email":"[REDACTED-EMAIL]"}
Status: 503 Service Unavailable
```

## One API Across the Stack

Write the same fluent chain in Apex and Lightning Web Components.

::: code-group

```apex [Apex]
public void processOrder(Order ord, List<OrderItem> items) {
    Logr log = Logr.start('Process Customer Order').tag('OMS').recordId(ord.Id);
    log.add('Validated order header');
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
        log.save();
    }
}
```

```javascript [LWC]
import Logr from "c/logr";

async handlePayment() {
    const log = Logr.start("Customer Checkout")
        .source("checkoutSummary")
        .tag("Stripe")
        .recordId(this.recordId);

    log.info("Initializing payment intent");
    try {
        log.debug("Gateway response", await authorizeCard());
    } catch (error) {
        log.error("Payment failed", error);
    } finally {
        log.save();
    }
}

// One-liner:
Logr.start("Checkout UI Crash").source("checkoutSummary").error(error).save();
```

```bash [Install v1.1.0]
# Install the Unlocked Package
sf package install --package 04tg7000000ZCRJAA4 --target-org <alias> --apex-compile package --wait 10

# Assign Admin permissions
sf org assign permset --name Logr_Admin --target-org <alias>
```

:::

## How It Compares

Logr stands on good work by others. [Nebula Logger](https://github.com/jongpie/NebulaLogger) and [RFLIB](https://github.com/j-fischer/rflib) are mature platforms with features Logr will not match (live stream, archival, notifications, plugins). [Bolt Logger](https://github.com/batra-kapil/Bolt-Logger) showed that a logger can be small. Logr aims at the space between: a general-purpose logger you can read in an afternoon.

|                                          | **Logr**                                         | Bolt Logger                          | Nebula Logger                | RFLIB                              |
| :--------------------------------------- | :----------------------------------------------- | :----------------------------------- | :--------------------------- | :--------------------------------- |
| **Built for**                            | Traces, callouts, DML and errors                 | Error logging                        | Full logging platform        | Logging plus a wider library suite |
| **Size (core)**                          | 4 objects, 4 classes                             | 4 objects, 2 classes                 | 15 objects, 42 classes       | 13 objects, 79 classes             |
| **A transaction becomes**                | **One readable record**                          | One record per error                 | Parent log + child entries   | Log rows                           |
| **Keeps debug steps when an error hits** | **Yes**                                          | No                                   | Not documented               | Yes                                |
| **Built-in callout and DML summaries**   | **Yes**                                          | No                                   | Yes                          | Not checked                        |
| **Live view, archival, alerts**          | No                                               | No                                   | Yes                          | Yes                                |
| **Log purging**                          | Yes (batch, retention days, empties recycle bin) | Yes (nightly batch)                  | Yes (retention date + batch) | Yes (cleanup jobs)                 |
| **Data masking**                         | **Yes** (regex rules in metadata, on by default) | Yes (regex rules, first 2,000 chars) | Yes (rules in metadata)      | Yes                                |

- **Choose Logr** when you want a small, general-purpose logger with a clear trace per transaction.
- **Choose Bolt Logger** when you only need lightweight error logging. It is smaller than Logr and does that one job well.
- **Choose Nebula or RFLIB** when you need a live stream, archival, alerts, or a large ecosystem.

## Why the Name "Logr"?

The name comes from an internal logging utility I built during my time at Sonos. This open-source framework is a ground-up rewrite and much more capable, but it carries forward the core unit-of-work idea from that original tool: a transaction should produce one readable story. Keeping the name is a small nod to where that idea started.
