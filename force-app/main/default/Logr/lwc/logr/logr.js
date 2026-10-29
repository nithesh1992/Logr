/**
 * c/logr: chainable client-side logger for Lightning Web Components.
 *
 * It mirrors the Apex Logr API, so the same pattern works on both sides:
 *
 *   import Logr from 'c/logr';
 *
 *   const log = Logr.start('Customer Checkout')
 *     .source('checkoutSummary')
 *     .tag('Stripe')
 *     .recordId(this.recordId);
 *
 *   log.info('Submitting payment');
 *   try {
 *     await authorizeCard();
 *   } catch (error) {
 *     log.error('Payment failed', error);
 *   } finally {
 *     log.save();
 *   }
 *
 * One-liner:
 *
 *   Logr.start('Checkout crashed').source('checkoutSummary').error(error).save();
 *
 * Every method returns the logger so calls can be chained, except save(),
 * saveDirect() and saveViaEvent(). Those return a Promise<boolean> and never
 * throw, so logging can't break your component.
 */
import saveClientLog from "@salesforce/apex/Logr.saveClientLog";

const STEP_DIVIDER = "\n----------\n";
const DEFAULT_SUBJECT = "Client Log";
const DEFAULT_SOURCE = "LWC";
const LEVEL_RANK = { FINE: 1, DEBUG: 2, INFO: 3, WARN: 4, ERROR: 5 };

export default class Logr {
  constructor(subject) {
    this._subject = subject || DEFAULT_SUBJECT;
    this._source = DEFAULT_SOURCE;
    this._tags = [];
    this._recordIds = [];
    this._resetSteps();
  }

  /**
   * Starts a new logger. Same as `new Logr(subject)`.
   * @param {string} [subject] Short summary of this unit of work.
   */
  static start(subject) {
    return new Logr(subject);
  }

  // ---------------------------------------------------------------------------
  // Context
  // ---------------------------------------------------------------------------

  /** Sets or replaces the subject. */
  subject(text) {
    if (text) {
      this._subject = String(text);
    }
    return this;
  }

  /** Names the component or feature that logged this, e.g. 'checkoutSummary'. */
  source(name) {
    if (name) {
      this._source = String(name).trim();
    }
    return this;
  }

  /** Adds one tag. Duplicates and blanks are ignored. */
  tag(value) {
    addUnique(this._tags, value);
    return this;
  }

  /** Adds several tags, as an array or a comma-separated string. */
  tags(values) {
    toList(values).forEach((value) => this.tag(value));
    return this;
  }

  /** Adds one record or correlation ID. Duplicates and blanks are ignored. */
  recordId(id) {
    addUnique(this._recordIds, id);
    return this;
  }

  /** Adds several record IDs, as an array or a comma-separated string. */
  recordIds(ids) {
    toList(ids).forEach((id) => this.recordId(id));
    return this;
  }

  // ---------------------------------------------------------------------------
  // Steps. Each takes a message and an optional payload (object, array, etc.)
  // ---------------------------------------------------------------------------

  fine(message, payload) {
    return this._addStep("FINE", message, payload);
  }

  debug(message, payload) {
    return this._addStep("DEBUG", message, payload);
  }

  info(message, payload) {
    return this._addStep("INFO", message, payload);
  }

  /** Alias for info(), same as in Apex. */
  add(message, payload) {
    return this._addStep("INFO", message, payload);
  }

  warn(message, payload) {
    return this._addStep("WARN", message, payload);
  }

  /**
   * Logs an error step. Accepts any of:
   *   .error(error)             a caught error
   *   .error('Payment failed')  just a message
   *   .error('Payment failed', error)
   *
   * `error` can be a JavaScript Error, an Apex error from an imperative or
   * wired call ({ body: { message, stackTrace } }), or anything else.
   */
  error(messageOrError, error) {
    const hasLabel = error !== undefined;
    const caught = hasLabel ? error : messageOrError;

    if (isErrorLike(caught)) {
      this._stackTrace = stackOf(caught) || this._stackTrace;
    }

    const description = describeError(caught);
    const message = hasLabel
      ? [String(messageOrError), description].filter(Boolean).join(": ")
      : description;
    return this._addStep("ERROR", message);
  }

  // ---------------------------------------------------------------------------
  // Saving
  // ---------------------------------------------------------------------------

  /**
   * Sends the log to Salesforce. Uses the org's Default Save Mode unless you
   * pass 'EVENT' or 'DIRECT'. Resolves true on success, false otherwise.
   * After a successful save the steps are cleared, but the subject, source and
   * tags are kept so the same logger can be reused.
   */
  async save(saveMode = null) {
    try {
      const saved = await saveClientLog({
        subject: this._subject,
        message: this._steps.length
          ? this._steps.join(STEP_DIVIDER)
          : this._subject,
        level: this._level,
        source: this._source,
        tags: this._tags.length ? this._tags.join(", ") : null,
        recordId: this._recordIds.length ? this._recordIds.join(", ") : null,
        stackTrace: this._stackTrace,
        saveMode
      });
      if (saved) {
        this._recordIds = [];
        this._resetSteps();
      }
      return saved === true;
    } catch {
      // Logging must never break the calling component.
      return false;
    }
  }

  /** Saves with a direct DML insert into Logr_Entry__c. */
  saveDirect() {
    return this.save("DIRECT");
  }

  /** Saves by publishing a Logr_Event__e platform event. */
  saveViaEvent() {
    return this.save("EVENT");
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  _addStep(level, message, payload) {
    if (LEVEL_RANK[level] > LEVEL_RANK[this._level]) {
      this._level = level;
    }

    const elapsedMs = Math.max(0, Date.now() - this._startMs);
    const time = new Date().toISOString().slice(11, 23);
    let text = `[${time} | +${elapsedMs}ms | ${level}] ${toText(message)}`;

    if (payload !== undefined) {
      const payloadText = toText(payload);
      text += payloadText.includes("\n")
        ? `:\n${payloadText}`
        : `: ${payloadText}`;
    }

    this._steps.push(text);
    return this;
  }

  _resetSteps() {
    this._steps = [];
    this._level = "INFO";
    this._stackTrace = null;
    this._startMs = Date.now();
  }
}

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

function toText(value) {
  if (value === null || value === undefined) {
    return "";
  }
  if (typeof value === "string") {
    return value;
  }
  if (value instanceof Error) {
    return describeError(value);
  }
  try {
    return JSON.stringify(value, null, 2);
  } catch {
    return String(value);
  }
}

function toList(values) {
  if (Array.isArray(values)) {
    return values;
  }
  return typeof values === "string" ? values.split(",") : [];
}

function addUnique(list, value) {
  const trimmed =
    value === null || value === undefined ? "" : String(value).trim();
  if (trimmed && !list.includes(trimmed)) {
    list.push(trimmed);
  }
}

function isErrorLike(value) {
  return value !== null && typeof value === "object";
}

/** Turns an Error, an Apex error response or a string into one readable line. */
function describeError(error) {
  if (error === null || error === undefined) {
    return "";
  }
  if (typeof error === "string") {
    return error;
  }
  if (error instanceof Error) {
    return `${error.name}: ${error.message}`;
  }

  const body = error.body;
  if (Array.isArray(body)) {
    return body
      .map((item) => item && item.message)
      .filter(Boolean)
      .join("; ");
  }
  if (body && typeof body.message === "string") {
    return body.exceptionType
      ? `${body.exceptionType}: ${body.message}`
      : body.message;
  }
  if (typeof error.message === "string") {
    return error.message;
  }
  return toText(error);
}

/** Finds the most useful stack trace on an error, if it has one. */
function stackOf(error) {
  const body = error.body;
  if (body && !Array.isArray(body) && typeof body.message === "string") {
    return body.stackTrace
      ? `${describeError(error)}\n${body.stackTrace}`
      : describeError(error);
  }
  if (typeof error.stack === "string" && error.stack) {
    return error.stack;
  }
  return describeError(error) || null;
}

// -----------------------------------------------------------------------------
// Deprecated helpers from v1.1.0. They still work, so existing components don't
// break, but new code should use the chain: Logr.start(...)...save()
// -----------------------------------------------------------------------------

/** @deprecated Use `Logr.start(subject)`. */
export function createLogr(subject) {
  return Logr.start(subject);
}

/** @deprecated Use `Logr.start(subject).source(...).error(error).save()`. */
export function logError({
  subject,
  error,
  source,
  tags,
  recordId,
  saveMode = null
} = {}) {
  return Logr.start(subject || (error && error.message) || "LWC Error")
    .source(source)
    .tags(tags)
    .recordId(recordId)
    .error(subject || "Unhandled LWC Error", error)
    .save(saveMode);
}

/** @deprecated Use `Logr.start(subject).source(...).info(message).save()`. */
export function logInfo({
  subject,
  message,
  source,
  tags,
  recordId,
  saveMode = null
} = {}) {
  return Logr.start(subject || "LWC Info")
    .source(source)
    .tags(tags)
    .recordId(recordId)
    .info(message || subject)
    .save(saveMode);
}
