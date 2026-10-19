/**
 * Anonymous Apex script to seed realistic bulk Logr telemetry and error data
 * for testing the Logr Dashboard and Reports.
 *
 * Run via CLI:
 * sf apex run --file scripts/apex/GenerateBulkLogrData.apex
 */

// Enable DEBUG/FINE levels temporarily in memory via org-default Logr_Config__c if none exists
Logr_Config__c orgConfig = Logr_Config__c.getOrgDefaults();
if (orgConfig.Id == null) {
    orgConfig.SetupOwnerId = UserInfo.getOrganizationId();
}
orgConfig.Enabled__c = true;
orgConfig.Level__c = 'FINE';
orgConfig.Default_Save_Mode__c = 'EVENT';
orgConfig.Flush_Debug_On_Error__c = true;
orgConfig.Mask_Data__c = true;
orgConfig.Retention_Days__c = 30;
upsert orgConfig;

List<String> sources = new List<String>{
    'OrderService.ship (QUEUEABLE)',
    'StripePaymentGateway.charge (SYNC)',
    'AccountTrigger (AFTER_UPDATE)',
    'checkoutSummary (LWC)',
    'Order_Fulfillment_Flow (FLOW)',
    'InventorySyncBatch.execute (BATCH)',
    'SapErpWebhook.handlePost (REST)'
};

List<String> tagOptions = new List<String>{
    'OMS',
    'Stripe',
    'Checkout',
    'Inventory',
    'SAP-ERP',
    'Billing',
    'AccountSync'
};

List<String> simulatedUsers = new List<String>{
    UserInfo.getUserName(),
    'integration.bot@logr-demo.org',
    'checkout.guest@logr-demo.org',
    'fulfillment.ops@logr-demo.org'
};

// 1. Create 25 rich multi-step logs through the fluent Logr API (including PII masking & callout helpers)
for (Integer i = 1; i <= 25; i++) {
    String selectedSource = sources[Math.mod(i, sources.size())];
    String primaryTag = tagOptions[Math.mod(i, tagOptions.size())];
    String secondaryTag = tagOptions[Math.mod(i + 2, tagOptions.size())];
    String fakeRecordId = '801000000000' + String.valueOf(100 + i) + 'AAA';

    Logr logger = Logr.start('Order Transaction #' + (1000 + i))
        .source(selectedSource)
        .tag(primaryTag)
        .tag(secondaryTag)
        .recordId(fakeRecordId);

    logger.fine('Initialized execution context for correlation ' + fakeRecordId);
    logger.debug(
        'Customer payload (PII Masking Test)',
        'Email: customer' + i + '@example.com | Phone: (415) 555-0199 | Card: 4532 0151 1283 0366 | SSN: 123-45-6789'
    );
    logger.add('Validated line items and pricing rules');

    Integer modVal = Math.mod(i, 5);
    if (modVal == 0) {
        // Simulate 503 Callout Failure + Exception
        HttpRequest req = new HttpRequest();
        req.setMethod('POST');
        req.setEndpoint('https://api.sap-erp.example.com/v2/orders/' + (1000 + i));
        req.setBody('{"orderNumber":' + (1000 + i) + ',"email":"customer' + i + '@example.com"}');

        HttpResponse res = new HttpResponse();
        res.setStatusCode(503);
        res.setStatus('Service Unavailable');
        res.setBody('{"error":"Upstream ERP gateway timeout"}');

        logger.callout('SAP Order Creation Callout', req, res);
        try {
            Integer divideByZero = 1 / 0;
        } catch (Exception ex) {
            logger.error('Failed to complete order fulfillment #' + (1000 + i), ex);
        }
    } else if (modVal == 1) {
        logger.warn('Inventory threshold low for SKU-992' + i + '; fallback warehouse selected');
    } else if (modVal == 2) {
        logger.info('Order #' + (1000 + i) + ' synced and confirmed');
    } else if (modVal == 3) {
        // Keep highest level at DEBUG
        logger.subject('Diagnostic Trace #' + (1000 + i));
    }
}

// Persist half via Platform Event and half via Direct DML
List<Database.SaveResult> fluentResults = Logr.saveAll(Logr.SaveMode.DIRECT);
System.debug('Persisted ' + fluentResults.size() + ' fluent Logr units of work via DIRECT mode.');

// 2. Also publish 15 Platform Events (Logr.SaveMode.EVENT) to exercise LogrEventTrigger -> LogrEventHandler
for (Integer j = 1; j <= 15; j++) {
    String selectedSource = sources[Math.mod(j * 2, sources.size())];
    String primaryTag = tagOptions[Math.mod(j * 3, tagOptions.size())];
    Logr eventLogger = Logr.start('Async Event Operation #' + (2000 + j))
        .source(selectedSource)
        .tag(primaryTag)
        .recordId('001000000000' + String.valueOf(200 + j) + 'AAA');

    eventLogger.info('Step 1: Queued inbound webhook event');
    if (Math.mod(j, 3) == 0) {
        eventLogger.error(
            'Webhook signature verification failed for IP 192.168.10.' + j,
            new CalloutException('HTTP 401 Unauthorized from Stripe webhook verifier')
        );
    } else if (Math.mod(j, 3) == 1) {
        eventLogger.warn('Retry attempt #2 scheduled due to lock contention');
    } else {
        eventLogger.info('Webhook processed in 42ms');
    }
}
List<Database.SaveResult> eventResults = Logr.saveAll(Logr.SaveMode.EVENT);
System.debug('Published ' + eventResults.size() + ' Logr_Event__e Platform Events.');

// 3. Seed 20 multi-user entries so the "Logs by User" and "Logs by Level" dashboard charts show multiple users & all 5 levels
List<Logr_Entry__c> multiUserEntries = new List<Logr_Entry__c>();
List<String> allLevels = new List<String>{ 'ERROR', 'WARN', 'INFO', 'DEBUG', 'FINE' };
for (Integer k = 1; k <= 20; k++) {
    String levelName = allLevels[Math.mod(k, allLevels.size())];
    String src = sources[Math.mod(k, sources.size())];
    String usr = simulatedUsers[Math.mod(k, simulatedUsers.size())];
    Boolean isErr = (levelName == 'ERROR');

    multiUserEntries.add(
        new Logr_Entry__c(
            Subject__c = 'Simulated ' + levelName + ' Telemetry #' + (3000 + k),
            Level__c = levelName,
            Source__c = src,
            Tags__c = tagOptions[Math.mod(k, tagOptions.size())],
            Records__c = 'a0B000000000' + String.valueOf(300 + k) + 'AAA',
            Body__c = '[12:00:00.000 | +0ms | INFO] Started operation\n----------\n[12:00:00.125 | +125ms | ' +
                levelName +
                '] Completed step for ' +
                usr,
            Is_Exception__c = isErr,
            Stack_Trace__c = isErr ? 'System.DmlException: FIELD_CUSTOM_VALIDATION_EXCEPTION\nClass.' + src.substringBefore(' ') + ': line 42, column 1' : null,
            Governor_Limits__c = 'Time: 125ms | CPU: 34/10000ms | SOQL: 2/100 | DML: 1/150 | Heap: 88/6000KB',
            User__c = usr
        )
    );
}
insert multiUserEntries;
System.debug('Inserted ' + multiUserEntries.size() + ' multi-user Logr_Entry__c records.');
