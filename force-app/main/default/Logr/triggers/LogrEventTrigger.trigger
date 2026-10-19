/**
 * @description Logicless Platform Event subscriber trigger for Logr_Event__e.
 * Delegates all processing to LogrEventHandler.
 */
trigger LogrEventTrigger on Logr_Event__e(after insert) {
  LogrEventHandler.handleAfterInsert(Trigger.new);
}
