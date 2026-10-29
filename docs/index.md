---
layout: home

hero:
  name: "Logr"
  text: "Lean logging & telemetry for Salesforce."
  tagline: "One chainable API across Apex, Lightning Web Components, and Flow. Only 4 Apex classes and 1 trigger."
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
  - title: Identical Chain in Apex & LWC
    details: Build multi-step execution traces or one-liners with Logr.start(subject).source(...).tag(...).info(...).error(...).save(). No argument order to memorize.
  - title: Smart Debug Buffering
    details: Keep production orgs running at INFO level while buffering FINE and DEBUG steps in memory. If an ERROR occurs in the same transaction, Logr flushes the full trace automatically.
  - title: Rollback-Safe Platform Events
    details: Persist logs via Logr_Event__e (PublishImmediately) so diagnostic traces survive Database.rollback() and unhandled exceptions, or switch to direct DML when needed.
  - title: Declarative PII Data Masking
    details: Scrub SSNs, credit cards, email addresses, US phone numbers, and IPv4 addresses before DML using Custom Metadata regex rules.
  - title: Flow Invocable Action
    details: Drop the Save Logr Entry action onto any Flow normal path or Fault Path. Bulkified across multi-record interviews.
  - title: Zero Org Bloat
    details: 4 Apex classes, 1 trigger, 1 custom object, 1 platform event, and 1 LWC module. No Big Objects, no external packages, and an automated retention batch.
---

## One API Across the Stack

Switch between Apex, Lightning Web Components, and Flow without learning different conventions.

::: code-group

```apex [Apex]
Logr log = Logr.start('Order Checkout')
    .source('OrderService.placeOrder')
    .tag('Checkout')
    .recordId(orderRecord.Id);

try {
    log.info('Validating inventory');
    log.debug('Request payload', payloadMap);
    processOrder(orderRecord);
} catch (Exception ex) {
    log.error('Checkout failed', ex);
} finally {
    log.save();
}
```

```javascript [LWC]
import Logr from 'c/logr';

async handleCheckout() {
    const log = Logr.start('Customer Checkout')
        .source('checkoutSummary')
        .tag('Stripe')
        .recordId(this.recordId);

    try {
        log.info('Authorizing card');
        log.debug('Gateway response', await authorizeCard());
    } catch (error) {
        log.error('Payment failed', error);
    } finally {
        log.save();
    }
}
```

```bash [Install v1.1.0]
# Install the Unlocked Package into any org
sf package install --package 04tg7000000ZCRJAA4 --wait 10 --target-org <org-alias>

# Assign Admin or User permissions
sf org assign permset --name Logr_Admin --target-org <org-alias>
```

:::

## Why Logr Exists

Salesforce teams usually face a trade-off when picking a logging library:

- **Nebula Logger** and **RFLIB** are comprehensive enterprise frameworks, but they bring dozens of classes, objects, and Big Object archival pipelines into your org.
- **BoltLogger** stays very small, but focuses strictly on catching exceptions rather than multi-level telemetry (`FINE` through `ERROR`).

Logr sits in the middle: a compact, general-purpose logger that handles both exception tracking and multi-step operational telemetry in **4 Apex classes**.

| Capability                                    | Logr           | Nebula Logger | RFLIB | BoltLogger     |
| :-------------------------------------------- | :------------- | :------------ | :---- | :------------- |
| **Apex Classes**                              | **4**          | ~55+          | ~35+  | ~5             |
| **Multi-Level Telemetry (`FINE` to `ERROR`)** | Yes            | Yes           | Yes   | Error-focused  |
| **Apex + LWC + Flow Support**                 | Yes            | Yes           | Yes   | Yes            |
| **Flush `DEBUG` Steps on `ERROR`**            | Yes            | Yes           | Yes   | No             |
| **Regex PII Data Masking**                    | Yes (5 rules)  | Yes           | No    | No             |
| **Direct DML + Platform Event Modes**         | Yes            | Yes           | Yes   | Platform Event |
| **Reports & Dashboard Included**              | Yes (5 + 1)    | Yes           | No    | Yes            |
| **Big Object Archival**                       | No (by design) | Yes           | Yes   | No             |
