import saveClientLog from "@salesforce/apex/Logr.saveClientLog";

const STEP_DIVIDER = "\n----------\n";

const LEVEL_RANK = {
  FINE: 1,
  DEBUG: 2,
  INFO: 3,
  WARN: 4,
  ERROR: 5
};

function serializePayload(payload) {
  if (payload === null || payload === undefined) {
    return "";
  }
  if (typeof payload === "string") {
    return payload;
  }
  if (payload instanceof Error) {
    return `${payload.name}: ${payload.message}`;
  }
  try {
    return JSON.stringify(payload, null, 2);
  } catch {
    return String(payload);
  }
}

function extractStackTrace(errorObj) {
  if (!errorObj) {
    return null;
  }
  if (errorObj instanceof Error && errorObj.stack) {
    return errorObj.stack;
  }
  if (typeof errorObj === "object") {
    if (errorObj.body && typeof errorObj.body.message === "string") {
      const stack = errorObj.body.stackTrace
        ? `\n${errorObj.body.stackTrace}`
        : "";
      return `${errorObj.body.exceptionType || "AuraHandledException"}: ${errorObj.body.message}${stack}`;
    }
    if (typeof errorObj.stack === "string") {
      return errorObj.stack;
    }
    if (typeof errorObj.message === "string") {
      return errorObj.message;
    }
  }
  return String(errorObj);
}

/**
 * Fluent client-side unit-of-work logger for Lightning Web Components.
 */
export default class Logr {
  constructor(initialSubject = "Client Log") {
    this._subject = initialSubject;
    this._source = "LWC";
    this._tags = [];
    this._recordIds = [];
    this._steps = [];
    this._highestLevel = "INFO";
    this._stackTrace = null;
    this._startMs = Date.now();
  }

  static start(initialSubject) {
    return new Logr(initialSubject);
  }

  subject(newSubject) {
    this._subject = newSubject;
    return this;
  }

  source(componentName) {
    if (componentName) {
      this._source = String(componentName).trim();
    }
    return this;
  }

  tag(tagValue) {
    if (tagValue) {
      const trimmed = String(tagValue).trim();
      if (trimmed && !this._tags.includes(trimmed)) {
        this._tags.push(trimmed);
      }
    }
    return this;
  }

  tags(tagArray) {
    if (Array.isArray(tagArray)) {
      tagArray.forEach((item) => this.tag(item));
    }
    return this;
  }

  recordId(idValue) {
    if (idValue) {
      const trimmed = String(idValue).trim();
      if (trimmed && !this._recordIds.includes(trimmed)) {
        this._recordIds.push(trimmed);
      }
    }
    return this;
  }

  recordIds(idArray) {
    if (Array.isArray(idArray)) {
      idArray.forEach((item) => this.recordId(item));
    }
    return this;
  }

  add(labelOrMessage, optionalPayload) {
    return this._appendStep("INFO", labelOrMessage, optionalPayload);
  }

  fine(labelOrMessage, optionalPayload) {
    return this._appendStep("FINE", labelOrMessage, optionalPayload);
  }

  debug(labelOrMessage, optionalPayload) {
    return this._appendStep("DEBUG", labelOrMessage, optionalPayload);
  }

  info(labelOrMessage, optionalPayload) {
    return this._appendStep("INFO", labelOrMessage, optionalPayload);
  }

  warn(labelOrMessage, optionalPayload) {
    return this._appendStep("WARN", labelOrMessage, optionalPayload);
  }

  error(messageOrError, optionalError) {
    const errorTarget =
      optionalError !== undefined ? optionalError : messageOrError;
    const label = optionalError !== undefined ? String(messageOrError) : null;
    const extractedStack = extractStackTrace(errorTarget);
    if (extractedStack) {
      this._stackTrace = extractedStack;
    }
    return this._appendStep(
      "ERROR",
      label || serializePayload(messageOrError),
      optionalError
    );
  }

  async save(saveMode = null) {
    const messageBody =
      this._steps.length > 0
        ? this._steps.join(STEP_DIVIDER)
        : this._subject || "Client Log";

    try {
      const result = await saveClientLog({
        subject: this._subject || "Client Log",
        message: messageBody,
        level: this._highestLevel,
        source: this._source,
        tags: this._tags.length > 0 ? this._tags.join(", ") : null,
        recordId:
          this._recordIds.length > 0 ? this._recordIds.join(", ") : null,
        stackTrace: this._stackTrace,
        saveMode
      });
      this._steps = [];
      return result;
    } catch {
      // Never allow logger network or server errors to break the calling UI component
      return false;
    }
  }

  async saveDirect() {
    return this.save("DIRECT");
  }

  async saveViaEvent() {
    return this.save("EVENT");
  }

  _appendStep(levelName, labelOrMessage, optionalPayload) {
    const normalizedLevel = LEVEL_RANK[levelName] ? levelName : "INFO";
    if (LEVEL_RANK[normalizedLevel] > LEVEL_RANK[this._highestLevel]) {
      this._highestLevel = normalizedLevel;
    }
    const elapsedMs = Math.max(0, Date.now() - this._startMs);
    const isoTime = new Date().toISOString().slice(11, 23);
    const prefix = `[${isoTime} | +${elapsedMs}ms | ${normalizedLevel}] `;

    let stepText;
    if (optionalPayload !== undefined) {
      const serialized = serializePayload(optionalPayload);
      const separator = serialized.includes("\n") ? ":\n" : ": ";
      stepText = `${prefix}${labelOrMessage}${separator}${serialized}`;
    } else {
      stepText = `${prefix}${serializePayload(labelOrMessage)}`;
    }
    this._steps.push(stepText);
    return this;
  }
}

export function createLogr(subject) {
  return new Logr(subject);
}

export async function logError({
  subject,
  error,
  source = "LWC",
  tags = null,
  recordId = null,
  saveMode = null
}) {
  const logger = new Logr(
    subject || (error && error.message) || "LWC Error"
  ).source(source);
  if (tags) {
    logger.tags(Array.isArray(tags) ? tags : String(tags).split(","));
  }
  if (recordId) {
    logger.recordId(recordId);
  }
  logger.error(subject || "Unhandled LWC Error", error);
  return logger.save(saveMode);
}

export async function logInfo({
  subject,
  message,
  source = "LWC",
  tags = null,
  recordId = null,
  saveMode = null
}) {
  const logger = new Logr(subject || "LWC Info").source(source);
  if (tags) {
    logger.tags(Array.isArray(tags) ? tags : String(tags).split(","));
  }
  if (recordId) {
    logger.recordId(recordId);
  }
  logger.info(message || subject);
  return logger.save(saveMode);
}
