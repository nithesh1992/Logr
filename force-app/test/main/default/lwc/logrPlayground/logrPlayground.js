import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import Logr from "c/logr";

const LEVEL_OPTIONS = [
  { label: "FINE", value: "FINE" },
  { label: "DEBUG", value: "DEBUG" },
  { label: "INFO", value: "INFO" },
  { label: "WARN", value: "WARN" },
  { label: "ERROR", value: "ERROR" }
];

const SAVE_MODE_OPTIONS = [
  { label: "Org Default (Logr_Config__c)", value: "DEFAULT" },
  { label: "Direct DML (saveDirect)", value: "DIRECT" },
  { label: "Platform Event (saveViaEvent)", value: "EVENT" }
];

export default class LogrPlayground extends NavigationMixin(LightningElement) {
  _recordId;

  @api
  get recordId() {
    return this._recordId;
  }
  set recordId(value) {
    this._recordId = value;
    if (value && !this.recordIds) {
      this.recordIds = value;
    }
  }

  subject = "Checkout Payment Action";
  source = "logrPlayground";
  level = "INFO";
  saveMode = "DEFAULT";
  tags = "LWC, Playground";
  recordIds = "";
  message = "Customer clicked Authorize Card";
  payload = '{\n  "amount": 149.99,\n  "currency": "USD"\n}';

  isBusy = false;
  history = [];
  nextId = 1;

  get levelOptions() {
    return LEVEL_OPTIONS;
  }

  get saveModeOptions() {
    return SAVE_MODE_OPTIONS;
  }

  get hasHistory() {
    return this.history.length > 0;
  }

  get historyCount() {
    return this.history.length;
  }

  get codePreview() {
    const methodMap = {
      FINE: "fine",
      DEBUG: "debug",
      INFO: "info",
      WARN: "warn",
      ERROR: "error"
    };
    const stepMethod = methodMap[this.level] || "info";
    const saveCall =
      this.saveMode === "DIRECT"
        ? "saveDirect()"
        : this.saveMode === "EVENT"
          ? "saveViaEvent()"
          : "save()";

    const lines = [
      `Logr.start(${JSON.stringify(this.subject || "Client Log")})`
    ];
    if (this.source) {
      lines.push(`  .source(${JSON.stringify(this.source)})`);
    }
    if (this.tags) {
      lines.push(`  .tags(${JSON.stringify(this.tags)})`);
    }
    if (this.recordIds) {
      lines.push(`  .recordIds(${JSON.stringify(this.recordIds)})`);
    }
    if (this.payload && this.level !== "ERROR") {
      lines.push(
        `  .${stepMethod}(${JSON.stringify(this.message)}, ${this.payload})`
      );
    } else if (this.payload && this.level === "ERROR") {
      lines.push(
        `  .error(${JSON.stringify(this.message)}, new Error(${JSON.stringify(this.payload)}))`
      );
    } else {
      lines.push(`  .${stepMethod}(${JSON.stringify(this.message)})`);
    }
    lines.push(`  .${saveCall};`);
    return lines.join("\n");
  }

  handleInputChange(event) {
    const { name, value } = event.target;
    this[name] = value;
  }

  async handleScenarioClick(event) {
    const scenario = event.currentTarget.dataset.scenario;
    this.isBusy = true;
    try {
      if (scenario === "telemetry") {
        const saved = await Logr.start("Order Checkout Telemetry")
          .source("logrPlayground")
          .tags(["Checkout", "LWC", "Telemetry"])
          .recordIds(this.recordIds)
          .info("Validated shopping cart", { items: 3, subtotal: 149.99 })
          .debug("Applied promo code", { code: "SPRING26", discount: 15.0 })
          .info("Payment intent authorized", { gateway: "Stripe" })
          .save();
        this.recordActivity(
          "Order Checkout Telemetry",
          "INFO",
          "DEFAULT",
          saved
        );
      } else if (scenario === "warn") {
        const saved = await Logr.start("Inventory Check Latency")
          .source("logrPlayground")
          .tags(["Inventory", "SLA"])
          .recordIds(this.recordIds)
          .info("Requesting warehouse availability")
          .warn("Warehouse API exceeded SLA threshold", {
            endpoint: "/v1/inventory/check",
            elapsedMs: 2480,
            thresholdMs: 1000
          })
          .save();
        this.recordActivity(
          "Inventory Check Latency",
          "WARN",
          "DEFAULT",
          saved
        );
      } else if (scenario === "jserror") {
        let caughtError;
        try {
          const emptyCart = null;
          // Intentionally trigger a real TypeError with a browser stack trace
          emptyCart.items.map((item) => item.id);
        } catch (err) {
          caughtError = err;
        }
        const saved = await Logr.start("Checkout UI Crash")
          .source("logrPlayground")
          .tags(["Checkout", "UI", "Crash"])
          .recordIds(this.recordIds)
          .info("Rendering cart summary")
          .error("Unhandled component render error", caughtError)
          .save();
        this.recordActivity("Checkout UI Crash", "ERROR", "DEFAULT", saved);
      } else if (scenario === "apexerror") {
        const simulatedApexError = {
          body: {
            exceptionType: "System.DmlException",
            message:
              "Insert failed. First exception on row 0; first error: FIELD_CUSTOM_VALIDATION_EXCEPTION, Order discount exceeds approval limit: [Discount_Percent__c]",
            stackTrace:
              "Class.OrderCheckoutService.createOrder: line 84, column 1\nClass.OrderCheckoutController.submitOrder: line 29, column 1"
          }
        };
        const saved = await Logr.start("Order Submit Apex Failure")
          .source("logrPlayground")
          .tags(["Checkout", "Apex", "DML"])
          .recordIds(this.recordIds)
          .info("Submitting order payload to Apex controller")
          .error("Order submission failed", simulatedApexError)
          .save();
        this.recordActivity(
          "Order Submit Apex Failure",
          "ERROR",
          "DEFAULT",
          saved
        );
      } else if (scenario === "piimask") {
        const saved = await Logr.start("PII Masking Verification")
          .source("logrPlayground")
          .tags(["Security", "PII", "Masking"])
          .recordIds(this.recordIds)
          .info("Customer verification payload", {
            email: "jane.doe@example.com",
            ssn: "123-45-6789",
            card: "4532-1111-2222-3333",
            phone: "(415) 555-0199",
            clientIp: "192.168.1.42"
          })
          .save();
        this.recordActivity(
          "PII Masking Verification",
          "INFO",
          "DEFAULT",
          saved
        );
      }
    } finally {
      this.isBusy = false;
    }
  }

  async handleSendCustom() {
    this.isBusy = true;
    try {
      const log = Logr.start(this.subject)
        .source(this.source)
        .tags(this.tags)
        .recordIds(this.recordIds);

      let parsedPayload = this.payload;
      if (this.payload && this.payload.trim()) {
        try {
          parsedPayload = JSON.parse(this.payload);
        } catch {
          parsedPayload = this.payload;
        }
      } else {
        parsedPayload = undefined;
      }

      if (this.level === "FINE") {
        log.fine(this.message, parsedPayload);
      } else if (this.level === "DEBUG") {
        log.debug(this.message, parsedPayload);
      } else if (this.level === "WARN") {
        log.warn(this.message, parsedPayload);
      } else if (this.level === "ERROR") {
        if (parsedPayload !== undefined) {
          const err = new Error(
            typeof parsedPayload === "string"
              ? parsedPayload
              : JSON.stringify(parsedPayload)
          );
          log.error(this.message, err);
        } else {
          log.error(this.message);
        }
      } else {
        log.info(this.message, parsedPayload);
      }

      let saved;
      if (this.saveMode === "DIRECT") {
        saved = await log.saveDirect();
      } else if (this.saveMode === "EVENT") {
        saved = await log.saveViaEvent();
      } else {
        saved = await log.save();
      }

      this.recordActivity(this.subject, this.level, this.saveMode, saved);
    } finally {
      this.isBusy = false;
    }
  }

  recordActivity(subject, level, mode, saved) {
    const time = new Date().toLocaleTimeString();
    const entry = {
      id: this.nextId++,
      subject,
      level,
      mode,
      time,
      statusLabel: saved ? "Saved" : "Filtered / Off",
      badgeClass: saved ? "badge-saved" : "badge-skipped"
    };
    this.history = [entry, ...this.history];

    this.dispatchEvent(
      new ShowToastEvent({
        title: saved ? `Log Saved (${level})` : `Log Filtered (${level})`,
        message: saved
          ? `"${subject}" was persisted to Logr_Entry__c.`
          : `"${subject}" was skipped by Logr_Config__c threshold or enabled settings.`,
        variant: saved ? "success" : "warning"
      })
    );
  }

  handleClearHistory() {
    this.history = [];
  }

  handleOpenLogEntries() {
    this[NavigationMixin.Navigate]({
      type: "standard__objectPage",
      attributes: {
        objectApiName: "Logr_Entry__c",
        actionName: "list"
      },
      state: {
        filterName: "All_Logs"
      }
    });
  }
}
