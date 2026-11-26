/**
 * Finds which CPF/CNPJ keys are already used by a customer (spec 002, REQ-016, REQ-021,
 * REQ-028).
 *
 * `without sharing` + SYSTEM_MODE on purpose (plan 002, Constitution Check items 1 and 4):
 * documents are Private (REQ-022), so a user cannot see the documents of customers
 * registered by others, yet a duplicate must still be blocked. This class only answers
 * "which keys are taken and by which customer"; CustomerService turns that into the spec
 * message, which never reveals the other customer.
 */
public without sharing class CustomerDocumentDuplicateChecker {
  /** Normalized document key -> Id of the customer that already uses it. */
  public static Map<String, Id> customersByKey(Set<String> keys) {
    Map<String, Id> customersByKey = new Map<String, Id>();
    if (keys == null || keys.isEmpty()) {
      return customersByKey;
    }
    for (Customer_Document__c document : [
      SELECT Document_Key__c, Customer__c
      FROM Customer_Document__c
      WHERE Document_Key__c IN :keys
      WITH SYSTEM_MODE
    ]) {
      customersByKey.put(
        document.Document_Key__c.toUpperCase(),
        document.Customer__c
      );
    }
    return customersByKey;
  }
}
