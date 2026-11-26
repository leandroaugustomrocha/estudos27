/**
 * Customer rules (spec 002). Called by CustomerTriggerHandler.
 *
 * Validates and formats contact data, postal code and CPF/CNPJ (REQ-002, 005, 012-017,
 * 020, 021, 023), keeps the document in the Private Customer_Document__c record (REQ-022),
 * deletes and restores it with the customer (REQ-027, REQ-028) and starts the background
 * postal code lookup for customers saved outside the form (REQ-008).
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
  private static final String DUPLICATE_VALUE = 'DUPLICATE_VALUE';

  /**
   * Validated document keys of the last before-save run, read by the after trigger of
   * the same run. Updates are keyed by record Id; inserts (no Id yet) by Trigger.new
   * position, which is only used when the after trigger sees the same number of rows.
   */
  private static Map<Id, String> pendingKeysById = new Map<Id, String>();
  private static List<String> pendingKeysByPosition = new List<String>();

  /** Key of the document read by the last readDocument call (null when none). */
  private String lastDocumentKey;

  // ---------- before insert / before update ----------

  public void beforeSave(
    List<Customer__c> customers,
    Map<Id, Customer__c> oldMap
  ) {
    Boolean isInsert = oldMap == null;
    pendingKeysById = new Map<Id, String>();
    pendingKeysByPosition = new List<String>();
    Set<String> batchKeys = new Set<String>();

    for (Customer__c customer : customers) {
      String error = normalizePostalCode(customer);
      if (error == null) {
        error = validateEmail(customer);
      }
      if (error == null) {
        error = normalizePhone(customer);
      }
      String documentError = readDocument(customer, isInsert);
      if (error == null) {
        error = documentError;
      }
      String key = null;
      // REQ-021: only a row that will be saved can claim a document in the batch.
      if (error == null && lastDocumentKey != null) {
        if (batchKeys.contains(lastDocumentKey)) {
          error = System.Label.Customer_Duplicate_Document;
        } else {
          batchKeys.add(lastDocumentKey);
          key = lastDocumentKey;
        }
      }
      if (error != null) {
        customer.addError(error);
      }
      pendingKeysByPosition.add(key);
      if (!isInsert && key != null) {
        pendingKeysById.put(customer.Id, key);
      }
    }

    rejectDocumentsUsedByOtherCustomers(customers);
  }

  // ---------- after insert / after update ----------

  public void afterSave(
    List<Customer__c> customers,
    Map<Id, Customer__c> oldMap
  ) {
    saveDocuments(pendingKeysFor(customers, oldMap == null), customers);
    startBackgroundLookup(customers, oldMap);
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

  /**
   * REQ-028: restore the document too, unless another customer took it meanwhile or an
   * earlier customer of the same restore already uses it (the first one wins).
   */
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
    Set<String> restoredKeys = new Set<String>();
    for (Customer_Document__c document : deletedDocuments) {
      String key = document.Document_Key__c.toUpperCase();
      Id owner = usedBy.get(key);
      Boolean takenByAnother = owner != null && owner != document.Customer__c;
      if (takenByAnother || restoredKeys.contains(key)) {
        customersById.get(document.Customer__c)
          .addError(System.Label.Customer_Duplicate_Document);
      } else {
        restoredKeys.add(key);
        toRestore.add(document);
      }
    }
    if (toRestore.isEmpty()) {
      return;
    }
    List<Database.UndeleteResult> results = Database.undelete(
      toRestore,
      false,
      AccessLevel.SYSTEM_MODE
    );
    for (Integer i = 0; i < results.size(); i++) {
      if (!results[i].isSuccess()) {
        customersById.get(toRestore[i].Customer__c)
          .addError(messageFor(results[i].getErrors()));
      }
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
    for (String key : pendingKeysByPosition) {
      if (key != null) {
        keys.add(key);
      }
    }
    Map<String, Id> usedBy = CustomerDocumentDuplicateChecker.customersByKey(
      keys
    );
    for (Integer i = 0; i < customers.size(); i++) {
      String key = pendingKeysByPosition[i];
      if (
        key != null &&
        usedBy.containsKey(key) &&
        usedBy.get(key) != customers[i].Id
      ) {
        customers[i].addError(System.Label.Customer_Duplicate_Document);
        pendingKeysByPosition[i] = null;
        pendingKeysById.remove(customers[i].Id);
      }
    }
  }

  // ---------- documents and background lookup ----------

  /**
   * Customer Id -> validated key for the rows of this after trigger. When a row failed in
   * the before trigger it is missing here and positions no longer match; that attempt is
   * always rolled back by the platform, so nothing is written (the retry writes it).
   */
  private Map<Id, String> pendingKeysFor(
    List<Customer__c> customers,
    Boolean isInsert
  ) {
    Map<Id, String> keyByCustomer = new Map<Id, String>();
    if (!isInsert) {
      for (Customer__c customer : customers) {
        if (pendingKeysById.containsKey(customer.Id)) {
          keyByCustomer.put(customer.Id, pendingKeysById.get(customer.Id));
        }
      }
      return keyByCustomer;
    }
    if (customers.size() != pendingKeysByPosition.size()) {
      return keyByCustomer;
    }
    for (Integer i = 0; i < customers.size(); i++) {
      if (pendingKeysByPosition[i] != null) {
        keyByCustomer.put(customers[i].Id, pendingKeysByPosition[i]);
      }
    }
    return keyByCustomer;
  }

  private void saveDocuments(
    Map<Id, String> keyByCustomer,
    List<Customer__c> customers
  ) {
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
    for (Id customerId : keyByCustomer.keySet()) {
      Customer_Document__c document = documentByCustomer.containsKey(customerId)
        ? documentByCustomer.get(customerId)
        : new Customer_Document__c(Customer__c = customerId);
      document.Document_Key__c = keyByCustomer.get(customerId);
      document.Document_Number__c = DocumentValidator.format(
        keyByCustomer.get(customerId)
      );
      documents.add(document);
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
        Customer__c customer = customersById.get(documents[i].Customer__c);
        if (customer != null) {
          customer.addError(messageFor(results[i].getErrors()));
        }
      }
    }
  }

  /** Spec message for a duplicate; a safe generic message for anything else. */
  private static String messageFor(List<Database.Error> errors) {
    for (Database.Error error : errors) {
      if (String.valueOf(error.getStatusCode()) == DUPLICATE_VALUE) {
        return System.Label.Customer_Duplicate_Document;
      }
    }
    System.debug(
      LoggingLevel.ERROR,
      'Customer document could not be saved: ' + errors
    );
    return System.Label.Customer_Document_Save_Failed;
  }

  /** REQ-008: customers created, or with a new postal code, outside the form. */
  private void startBackgroundLookup(
    List<Customer__c> customers,
    Map<Id, Customer__c> oldMap
  ) {
    if (skipBackgroundLookup) {
      return;
    }
    Set<Id> toLookUp = new Set<Id>();
    for (Customer__c customer : customers) {
      Customer__c old = oldMap == null ? null : oldMap.get(customer.Id);
      Boolean postalCodeIsNew =
        old == null ||
        old.Postal_Code__c != customer.Postal_Code__c;
      if (String.isNotBlank(customer.Postal_Code__c) && postalCodeIsNew) {
        toLookUp.add(customer.Id);
      }
    }
    if (toLookUp.isEmpty()) {
      return;
    }
    // A batch cannot be started from inside another batch's execute().
    if (System.isBatch()) {
      System.debug(
        LoggingLevel.WARN,
        'Background address lookup skipped (saved from inside a batch) for customers: ' +
        toLookUp
      );
      return;
    }
    CustomerAddressLookupBatch.run(toLookUp);
  }

  private static String digitsOf(String value) {
    return value == null ? '' : value.replaceAll('[^0-9]', '');
  }
}
