import Logr, { createLogr, logError, logInfo } from "c/logr";
import saveClientLog from "@salesforce/apex/Logr.saveClientLog";

jest.mock(
  "@salesforce/apex/Logr.saveClientLog",
  () => ({
    default: jest.fn()
  }),
  { virtual: true }
);

describe("c/logr headless logging service", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it("persists fluent multi-step unit of work via default save()", async () => {
    saveClientLog.mockResolvedValue(true);

    const logger = Logr.start("Checkout Telemetry")
      .source("checkoutSummary")
      .tag("Checkout")
      .tags(["Stripe", "Checkout"])
      .recordId("801000000000001AAA")
      .recordIds(["801000000000002AAA"]);

    logger.add("Cart validated");
    logger.debug("Cart Payload", { items: 2 });
    logger.warn("Slow response from tax service");

    const saved = await logger.save();

    expect(saved).toBe(true);
    expect(saveClientLog).toHaveBeenCalledTimes(1);
    const callArgs = saveClientLog.mock.calls[0][0];
    expect(callArgs.subject).toBe("Checkout Telemetry");
    expect(callArgs.level).toBe("WARN");
    expect(callArgs.source).toBe("checkoutSummary");
    expect(callArgs.tags).toBe("Checkout, Stripe");
    expect(callArgs.recordId).toBe("801000000000001AAA, 801000000000002AAA");
    expect(callArgs.message).toContain("----------");
    expect(callArgs.saveMode).toBeNull();
  });

  it("supports saveDirect() and saveViaEvent() explicit save modes", async () => {
    saveClientLog.mockResolvedValue(true);

    const directLogger = createLogr("Direct Client Log")
      .source("orderView")
      .info("Saved directly");
    await directLogger.saveDirect();

    const eventLogger = createLogr("Event Client Log")
      .source("orderView")
      .fine("Saved via event");
    await eventLogger.saveViaEvent();

    expect(saveClientLog).toHaveBeenCalledTimes(2);
    expect(saveClientLog.mock.calls[0][0].saveMode).toBe("DIRECT");
    expect(saveClientLog.mock.calls[1][0].saveMode).toBe("EVENT");
  });

  it("captures Error stack traces and AuraHandledException details in logError() and logInfo()", async () => {
    saveClientLog.mockResolvedValue(true);

    const jsError = new TypeError("Cannot read properties of null");
    await logError({
      subject: "Payment Crash",
      error: jsError,
      source: "paymentForm",
      tags: ["Payment", "UI"],
      recordId: "a01000000000001AAA",
      saveMode: "DIRECT"
    });

    await logInfo({
      subject: "Payment Initiated",
      message: "User clicked submit",
      source: "paymentForm",
      tags: "Payment",
      recordId: "a01000000000001AAA"
    });

    expect(saveClientLog).toHaveBeenCalledTimes(2);
    const errorArgs = saveClientLog.mock.calls[0][0];
    expect(errorArgs.level).toBe("ERROR");
    expect(errorArgs.stackTrace).toContain("TypeError");
    expect(errorArgs.saveMode).toBe("DIRECT");

    const infoArgs = saveClientLog.mock.calls[1][0];
    expect(infoArgs.level).toBe("INFO");
    expect(infoArgs.subject).toBe("Payment Initiated");
  });

  it("swallows Apex errors gracefully so client UI never crashes", async () => {
    saveClientLog.mockRejectedValue(new Error("Network offline"));

    const logger = Logr.start("Offline Log").error("Failed action", {
      body: {
        exceptionType: "System.CalloutException",
        message: "Timed out",
        stackTrace: "Class.X"
      }
    });
    const result = await logger.save();

    expect(result).toBe(false);
  });
});
