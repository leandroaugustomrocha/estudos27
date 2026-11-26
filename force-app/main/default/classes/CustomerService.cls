/**
 * Customer rules (spec 002). Called by CustomerTriggerHandler.
 *
 * Validates and formats contact data, postal code and CPF/CNPJ (REQ-002, 005, 012-017,
 * 020, 021, 023), keeps the document in the Private Customer_Document__c record (REQ-022),
 * deletes and restores it with the customer (REQ-027, REQ-028) and schedules the
 * background postal code lookup for customers saved outside the form (REQ-008).
 *
 * Customer_Document__c is written in SYSTEM_MODE on purpose (plan 002, Constitution Check
 * item 4, user decision): users only read it, so it can never be written without going
 * through these validations.
 */
public with sharing class CustomerService {
  /** Set by CustomerController: the form already looked up the postal code (REQ-003). */
  public static Boolean skipBackgroundLookup = false;

  private static final Pattern EMAIL_PATTERN = Pattern.compile(
    '^[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)*\\.[A-Za-z]{2,}$'
  );

  /**
   * Validated document keys of the last before-insert/update run, in Trigger.new order,
   * read by the after trigger of the same run (null = no document change for that row).
   */
  private static List<String> pendingDocumentKeys = new List<String>();

  /** Key of the document read by the last readDocument call (null when none). */
  private String lastDocumentKey;

  // ---------- before insert / before update ----------

  public void beforeSave(
    List<Customer__c> customers,
    Map<Id, Customer__c> oldMap
  ) {
    Boolean isInsert = oldMap == null;
    pendingDocumentKeys = new List<String>();
    Set<String> batchKeys = new Set<String>();

    for (Customer__c customer : customers) {
      String error = normalizePostalCode(customer);
      if (error == null) {
        error = validateEmail(customer);
      }
      if (error == null) {
        error = normalizePhone(customer);
      }
      String key = null;
      String documentError = readDocument(customer, isInsert);
      if (documentError == null && lastDocumentKey != null) {
        key = lastDocumentKey;
        if (batchKeys.contains(key)) {
          documentError = System.Label.Customer_Duplicate_Document;
          key = null;
        } else {
          batchKeys.add(key);
        }
      }
      if (error == null) {
        error = documentError;
      }
      if (error != null) {
        customer.addError(error);
        key = null;
      }
      pendingDocumentKeys.add(key);
    }

    rejectDocumentsUsedByOtherCustomers(customers);
  }

  // ---------- after insert / after update ----------

  public void afterSave(
    List<Customer__c> customers,
    Map<Id, Customer__c> oldMap
  ) {
    saveDocuments(customers);
    scheduleBackgroundLookup(customers, oldMap);
  }

  // ---------- before delete / after undelete ----------

  /** REQ-027: the document goes away with the customer, so it can be used again. */
  public void deleteDocuments(List<Customer__c> customers) {
    Set<Id> customerIds = new Map<Id, Customer__c>(customers).keySet();
    List<Customer_Document__c> documents = [
      SELECT Id
      FROM Customer_Document__c
      WHERE Customer__c IN :customerIds
      WITH SYSTEM_MODE
    ];
    if (!documents.isEmpty()) {
      Database.delete(documents, true, AccessLevel.SYSTEM_MODE);
    }
  }

  /** REQ-028: restore the document too, unless another customer took it meanwhile. */
  public void restoreDocuments(List<Customer__c> customers) {
    Map<Id, Customer__c> customersById = new Map<Id, Customer__c>(customers);
    List<Customer_Document__c> deletedDocuments = [
      SELECT Id, Customer__c, Document_Key__c
      FROM Customer_Document__c
      WHERE Customer__c IN :customersById.keySet() AND IsDeleted = TRUE
      WITH SYSTEM_MODE
      ALL ROWS
    ];
    Set<String> keys = new Set<String>();
    for (Customer_Document__c document : deletedDocuments) {
      keys.add(document.Document_Key__c.toUpperCase());
    }
    Map<String, Id> usedBy = CustomerDocumentDuplicateChecker.customersByKey(
      keys
    );

    List<Customer_Document__c> toRestore = new List<Customer_Document__c>();
    for (Customer_Document__c document : deletedDocuments) {
      Id owner = usedBy.get(document.Document_Key__c.toUpperCase());
      if (owner != null && owner != document.Customer__c) {
        customersById.get(document.Customer__c)
          .addError(System.Label.Customer_Duplicate_Document);
      } else {
        toRestore.add(document);
      }
    }
    if (!toRestore.isEmpty()) {
      Database.undelete(toRestore, true, AccessLevel.SYSTEM_MODE);
    }
  }

  // ---------- validations ----------

  /** REQ-002, REQ-005, REQ-023: blank is allowed; otherwise 8 digits stored as 00000-000. */
  private String normalizePostalCode(Customer__c customer) {
    if (String.isBlank(customer.Postal_Code__c)) {
      customer.Postal_Code__c = null;
      return null;
    }
    // Hyphen, dots and spaces are accepted as separators; anything else is invalid.
    String digits = customer.Postal_Code__c.replaceAll('[\\s.-]', '');
    if (!digits.isNumeric() || digits.length() != 8) {
      return System.Label.Customer_Invalid_Postal_Code;
    }
    customer.Postal_Code__c = digits.left(5) + '-' + digits.right(3);
    return null;
  }

  /** REQ-012 */
  private String validateEmail(Customer__c customer) {
    if (String.isBlank(customer.Email__c)) {
      return null;
    }
    customer.Email__c = customer.Email__c.trim();
    return EMAIL_PATTERN.matcher(customer.Email__c).matches()
      ? null
      : System.Label.Customer_Invalid_Email;
  }

  /** REQ-013: 10 or 11 digits with area code, stored as (00) 0000-0000 / (00) 00000-0000. */
  private String normalizePhone(Customer__c customer) {
    if (String.isBlank(customer.Phone__c)) {
      return null;
    }
    String digits = digitsOf(customer.Phone__c);
    if (digits.length() != 10 && digits.length() != 11) {
      return System.Label.Customer_Invalid_Phone;
    }
    customer.Phone__c =
      '(' +
      digits.left(2) +
      ') ' +
      digits.substring(2, digits.length() - 4) +
      '-' +
      digits.right(4);
    return null;
  }

  /**
   * REQ-014, REQ-015, REQ-017: reads the pass-through field, always clears it (the
   * document must never be stored on the customer) and sets the person type.
   */
  private String readDocument(Customer__c customer, Boolean isInsert) {
    lastDocumentKey = null;
    String input = customer.Document_Input__c;
    customer.Document_Input__c = null;
    if (String.isBlank(input)) {
      return isInsert ? System.Label.Customer_Document_Required : null;
    }
    String key = DocumentValidator.normalize(input);
    if (!DocumentValidator.isValid(key)) {
      return System.Label.Customer_Invalid_Document;
    }
    customer.Person_Type__c = DocumentValidator.personType(key);
    lastDocumentKey = key;
    return null;
  }

  /** REQ-016: a key already used by another customer (visible to this user or not). */
  private void rejectDocumentsUsedByOtherCustomers(
    List<Customer__c> customers
  ) {
    Set<String> keys = new Set<String>();
    for (String key : pendingDocumentKeys) {
      if (key != null) {
        keys.add(key);
      }
    }
    Map<String, Id> usedBy = CustomerDocumentDuplicateChecker.customersByKey(
      keys
    );
    for (Integer i = 0; i < customers.size(); i++) {
      String key = pendingDocumentKeys[i];
      if (
        key != null &&
        usedBy.containsKey(key) &&
        usedBy.get(key) != customers[i].Id
      ) {
        customers[i].addError(System.Label.Customer_Duplicate_Document);
        pendingDocumentKeys[i] = null;
      }
    }
  }

  // ---------- documents and background lookup ----------

  private void saveDocuments(List<Customer__c> customers) {
    Map<Id, String> keyByCustomer = new Map<Id, String>();
    for (
      Integer i = 0; i < customers.size() && i < pendingDocumentKeys.size(); i++
    ) {
      if (pendingDocumentKeys[i] != null) {
        keyByCustomer.put(customers[i].Id, pendingDocumentKeys[i]);
      }
    }
    if (keyByCustomer.isEmpty()) {
      return;
    }
    Map<Id, Customer_Document__c> documentByCustomer = new Map<Id, Customer_Document__c>();
    for (Customer_Document__c existing : [
      SELECT Id, Customer__c
      FROM Customer_Document__c
      WHERE Customer__c IN :keyByCustomer.keySet()
      WITH SYSTEM_MODE
    ]) {
      documentByCustomer.put(existing.Customer__c, existing);
    }
    List<Customer_Document__c> documents = new List<Customer_Document__c>();
    List<Id> customerOrder = new List<Id>();
    for (Id customerId : keyByCustomer.keySet()) {
      Customer_Document__c document = documentByCustomer.containsKey(customerId)
        ? documentByCustomer.get(customerId)
        : new Customer_Document__c(Customer__c = customerId);
      document.Document_Key__c = keyByCustomer.get(customerId);
      document.Document_Number__c = DocumentValidator.format(
        keyByCustomer.get(customerId)
      );
      documents.add(document);
      customerOrder.add(customerId);
    }
    // Unique index on Document_Key__c is the last line of defense (two saves at the same time).
    List<Database.UpsertResult> results = Database.upsert(
      documents,
      false,
      AccessLevel.SYSTEM_MODE
    );
    Map<Id, Customer__c> customersById = new Map<Id, Customer__c>(customers);
    for (Integer i = 0; i < results.size(); i++) {
      if (!results[i].isSuccess()) {
        customersById.get(customerOrder[i])
          .addError(System.Label.Customer_Duplicate_Document);
      }
    }
  }

  /** REQ-008: customers created, or with a new postal code, outside the form. */
  private void scheduleBackgroundLookup(
    List<Customer__c> customers,
    Map<Id, Customer__c> oldMap
  ) {
    if (skipBackgroundLookup) {
      return;
    }
    List<Id> toLookUp = new List<Id>();
    for (Customer__c customer : customers) {
      Customer__c old = oldMap == null ? null : oldMap.get(customer.Id);
      Boolean postalCodeIsNew =
        old == null ||
        old.Postal_Code__c != customer.Postal_Code__c;
      if (String.isNotBlank(customer.Postal_Code__c) && postalCodeIsNew) {
        toLookUp.add(customer.Id);
      }
    }
    if (
      !toLookUp.isEmpty() &&
      Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()
    ) {
      System.enqueueJob(new CustomerAddressLookupJob(toLookUp));
    }
  }

  private static String digitsOf(String value) {
    return value == null ? '' : value.replaceAll('[^0-9]', '');
  }
}
