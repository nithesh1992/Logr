import Logr from "c/logr";
import saveClientLog from "@salesforce/apex/Logr.saveClientLog";

jest.mock(
  "@salesforce/apex/Logr.saveClientLog",
  () => ({
    default: jest.fn()
  }),
  { virtual: true }
);

const lastCall = () =>
  saveClientLog.mock.calls[saveClientLog.mock.calls.length - 1][0];

const apexError = (overrides = {}) => ({
  body: {
    exceptionType: "System.DmlException",
    message: "Insert failed",
    stackTrace: "Class.OrderController.save: line 12, column 1",
    ...overrides
  }
});

describe("c/logr", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    saveClientLog.mockResolvedValue(true);
  });

  describe("chaining", () => {
    it("builds a full unit of work with one chain and saves it once", async () => {
      const saved = await Logr.start("Customer Checkout")
        .source("checkoutSummary")
        .tag("Checkout")
        .tags(["Stripe", "Checkout"])
        .recordId("801000000000001AAA")
        .recordIds(["801000000000002AAA"])
        .add("Cart validated")
        .debug("Cart payload", { items: 2 })
        .warn("Slow tax service")
        .save();

      expect(saved).toBe(true);
      expect(saveClientLog).toHaveBeenCalledTimes(1);

      const args = lastCall();
      expect(args.subject).toBe("Customer Checkout");
      expect(args.level).toBe("WARN");
      expect(args.source).toBe("checkoutSummary");
      expect(args.tags).toBe("Checkout, Stripe");
      expect(args.recordId).toBe("801000000000001AAA, 801000000000002AAA");
      expect(args.message).toContain("| INFO] Cart validated");
      expect(args.message).toContain(
        '| DEBUG] Cart payload:\n{\n  "items": 2\n}'
      );
      expect(args.message).toContain("\n----------\n");
      expect(args.stackTrace).toBeNull();
      expect(args.saveMode).toBeNull();
    });

    it("returns the same logger from every non-save method", () => {
      const log = Logr.start("Chain");
      const methods = [
        () => log.subject("x"),
        () => log.source("y"),
        () => log.tag("t"),
        () => log.tags("a, b"),
        () => log.recordId("1"),
        () => log.recordIds(["2"]),
        () => log.fine("f"),
        () => log.debug("d"),
        () => log.info("i"),
        () => log.add("a"),
        () => log.warn("w"),
        () => log.error("e")
      ];
      methods.forEach((call) => expect(call()).toBe(log));
    });

    it("uses sensible defaults when nothing is set", async () => {
      await Logr.start().save();

      const args = lastCall();
      expect(args.subject).toBe("Client Log");
      expect(args.source).toBe("LWC");
      expect(args.level).toBe("INFO");
      expect(args.message).toBe("Client Log");
      expect(args.tags).toBeNull();
      expect(args.recordId).toBeNull();
    });

    it("accepts comma-separated strings for tags and record IDs and ignores blanks", async () => {
      await Logr.start("Lists")
        .tags("LWC, Checkout, ,LWC")
        .recordIds("001A, 001B")
        .tag(null)
        .recordId("")
        .info("ok")
        .save();

      const args = lastCall();
      expect(args.tags).toBe("LWC, Checkout");
      expect(args.recordId).toBe("001A, 001B");
    });

    it("works with new Logr() just like Logr.start()", async () => {
      await new Logr("Constructed").info("hi").save();
      expect(lastCall().subject).toBe("Constructed");
    });
  });

  describe("error()", () => {
    it("takes a caught JavaScript Error on its own", async () => {
      await Logr.start("Checkout crashed")
        .source("checkoutSummary")
        .error(new TypeError("Cannot read properties of null"))
        .save();

      const args = lastCall();
      expect(args.level).toBe("ERROR");
      expect(args.message).toContain(
        "| ERROR] TypeError: Cannot read properties of null"
      );
      expect(args.stackTrace).toContain("TypeError");
    });

    it("takes a label and an Apex error response", async () => {
      await Logr.start("Save order").error("Save failed", apexError()).save();

      const args = lastCall();
      expect(args.message).toContain(
        "| ERROR] Save failed: System.DmlException: Insert failed"
      );
      expect(args.stackTrace).toBe(
        "System.DmlException: Insert failed\nClass.OrderController.save: line 12, column 1"
      );
    });

    it("handles Apex errors without a stack trace and list-shaped bodies", async () => {
      await Logr.start("No stack")
        .error(apexError({ stackTrace: "" }))
        .save();
      expect(lastCall().stackTrace).toBe("System.DmlException: Insert failed");

      await Logr.start("List body")
        .error({
          body: [
            { message: "Field A is required" },
            { message: "Field B is invalid" }
          ]
        })
        .save();
      expect(lastCall().message).toContain(
        "Field A is required; Field B is invalid"
      );
    });

    it("takes a plain message without setting a stack trace", async () => {
      await Logr.start("Validation").error("Quantity must be positive").save();

      const args = lastCall();
      expect(args.level).toBe("ERROR");
      expect(args.message).toContain("| ERROR] Quantity must be positive");
      expect(args.stackTrace).toBeNull();
    });
  });

  describe("saving", () => {
    it("supports saveDirect() and saveViaEvent()", async () => {
      await Logr.start("Direct").info("a").saveDirect();
      expect(lastCall().saveMode).toBe("DIRECT");

      await Logr.start("Event").info("b").saveViaEvent();
      expect(lastCall().saveMode).toBe("EVENT");
    });

    it("clears steps, level and stack after a successful save but keeps subject, source and tags", async () => {
      const log = Logr.start("Reusable")
        .source("orderView")
        .tag("OMS")
        .recordId("801A")
        .error(new Error("first"));
      await log.save();

      await log.info("second").save();
      const args = lastCall();
      expect(args.subject).toBe("Reusable");
      expect(args.source).toBe("orderView");
      expect(args.tags).toBe("OMS");
      expect(args.recordId).toBeNull();
      expect(args.level).toBe("INFO");
      expect(args.stackTrace).toBeNull();
      expect(args.message).not.toContain("first");
    });

    it("never throws and keeps the steps when Apex fails", async () => {
      saveClientLog.mockRejectedValueOnce(new Error("Network offline"));
      const log = Logr.start("Offline").error("Failed action", apexError());

      await expect(log.save()).resolves.toBe(false);

      await log.save();
      expect(lastCall().message).toContain("Failed action");
    });

    it("resolves false when Apex reports the log was not saved", async () => {
      saveClientLog.mockResolvedValueOnce(false);
      await expect(Logr.start("Disabled").info("x").save()).resolves.toBe(
        false
      );
    });
  });
});
