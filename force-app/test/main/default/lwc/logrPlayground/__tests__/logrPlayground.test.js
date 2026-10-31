import { createElement } from "lwc";
import LogrPlayground from "c/logrPlayground";
import saveClientLog from "@salesforce/apex/Logr.saveClientLog";
import publishBulkEvents from "@salesforce/apex/LogrPlaygroundController.publishBulkEvents";

jest.mock(
  "@salesforce/apex/Logr.saveClientLog",
  () => ({
    default: jest.fn()
  }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/LogrPlaygroundController.publishBulkEvents",
  () => ({
    default: jest.fn()
  }),
  { virtual: true }
);

const flushPromises = async () => {
  await Promise.resolve();
  await Promise.resolve();
};

describe("c-logr-playground", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("renders preset scenario buttons and runs the telemetry scenario through c/logr", async () => {
    saveClientLog.mockResolvedValue(true);

    const element = createElement("c-logr-playground", {
      is: LogrPlayground
    });
    document.body.appendChild(element);

    const telemetryBtn = element.shadowRoot.querySelector(
      '[data-scenario="telemetry"]'
    );
    expect(telemetryBtn).not.toBeNull();
    telemetryBtn.click();

    await flushPromises();

    expect(saveClientLog).toHaveBeenCalledTimes(1);
    expect(saveClientLog.mock.calls[0][0].subject).toBe(
      "Order Checkout Telemetry"
    );
    expect(saveClientLog.mock.calls[0][0].level).toBe("INFO");
  });

  it("runs caught JS TypeError and custom chain builder scenarios", async () => {
    saveClientLog.mockResolvedValue(true);

    const element = createElement("c-logr-playground", {
      is: LogrPlayground
    });
    element.recordId = "001000000000001AAA";
    document.body.appendChild(element);

    const jsErrorBtn = element.shadowRoot.querySelector(
      '[data-scenario="jserror"]'
    );
    jsErrorBtn.click();
    await flushPromises();

    expect(saveClientLog).toHaveBeenCalledTimes(1);
    expect(saveClientLog.mock.calls[0][0].level).toBe("ERROR");
    expect(saveClientLog.mock.calls[0][0].stackTrace).toContain("TypeError");

    const sendCustomBtn = Array.from(
      element.shadowRoot.querySelectorAll("lightning-button")
    ).find((btn) => btn.label === "Send Custom Log");
    sendCustomBtn.click();
    await flushPromises();

    expect(saveClientLog).toHaveBeenCalledTimes(2);
    expect(saveClientLog.mock.calls[1][0].subject).toBe(
      "Checkout Payment Action"
    );
  });

  it("triggers bulk burst scenario and records activity", async () => {
    publishBulkEvents.mockResolvedValue(250);

    const element = createElement("c-logr-playground", {
      is: LogrPlayground
    });
    document.body.appendChild(element);

    const bulkBtn = element.shadowRoot.querySelector(
      '[data-scenario="bulkburst"]'
    );
    expect(bulkBtn).not.toBeNull();
    bulkBtn.click();

    await flushPromises();

    expect(publishBulkEvents).toHaveBeenCalledWith({ count: 250 });
    const activityItems = element.shadowRoot.querySelectorAll("li.slds-item");
    expect(activityItems.length).toBe(1);
    expect(activityItems[0].textContent).toContain("Bulk Burst (250 Events)");
  });
});
