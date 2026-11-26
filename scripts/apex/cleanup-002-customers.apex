// Removes ONLY the customers created by seed-002-customers.apex (e-mail at
// seed002.example.com). CustomerTrigger deletes their CPF/CNPJ records too (REQ-027).
// Run:  sf apex run --file scripts/apex/cleanup-002-customers.apex --target-org estudos27

List<Customer__c> customers = [SELECT Id FROM Customer__c WHERE Email__c LIKE '%@seed002.example.com'];
delete customers;
System.debug(LoggingLevel.ERROR, 'CLEANUP_RESULT customers=' + customers.size());
