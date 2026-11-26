/**
 * Apex for the customerForm LWC (spec 002, REQ-003 to REQ-007, REQ-018, REQ-019, REQ-022).
 */
public with sharing class CustomerController {
  /** Address returned to the LWC; status is the ViaCepCallout.Status name. */
  public class AddressResult {
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String street;
    @AuraEnabled
    public String district;
    @AuraEnabled
    public String city;
    @AuraEnabled
    public String state;
  }

  /** REQ-003, REQ-005: checks the format first, so a malformed CEP never reaches the service. */
  // Not cacheable: a service answer (e.g. UNAVAILABLE) must not be served again on retry (REQ-007).
  @AuraEnabled
  public static AddressResult lookupCep(String postalCode) {
    String digits = digitsOf(postalCode);
    if (digits.length() != 8) {
      throw userError(System.Label.Customer_Invalid_Postal_Code);
    }
    ViaCepCallout.Result result = ViaCepCallout.lookup(digits);
    AddressResult address = new AddressResult();
    address.status = result.status.name();
    address.street = result.street;
    address.district = result.district;
    address.city = result.city;
    address.state = result.state;
    return address;
  }

  /**
   * Saves from the form. The postal code is looked up again on the server before the DML
   * (a callout cannot follow DML): unknown CEP blocks the save (REQ-006); found CEP decides
   * city and UF (REQ-018); service down keeps the typed address (REQ-007).
   */
  @AuraEnabled
  public static Id saveCustomer(Customer__c customer) {
    if (customer == null) {
      throw userError(System.Label.Customer_Invalid_Data);
    }
    String digits = digitsOf(customer.Postal_Code__c);
    if (digits.length() == 8) {
      ViaCepCallout.Result result = ViaCepCallout.lookup(digits);
      if (result.status == ViaCepCallout.Status.NOT_FOUND) {
        throw userError(System.Label.Customer_Postal_Code_Not_Found);
      }
      if (result.status == ViaCepCallout.Status.FOUND) {
        customer.City__c = result.city;
        customer.State__c = result.state;
        if (String.isBlank(customer.Street__c)) {
          customer.Street__c = result.street;
        }
        if (String.isBlank(customer.District__c)) {
          customer.District__c = result.district;
        }
      }
    }
    CustomerService.skipBackgroundLookup = true;
    try {
      Database.upsert(customer, true, AccessLevel.USER_MODE);
    } catch (DmlException e) {
      throw userError(e.getDmlMessage(0));
    } finally {
      CustomerService.skipBackgroundLookup = false;
    }
    return customer.Id;
  }

  /** REQ-022: USER_MODE returns the document only to whoever registered it and to admins. */
  @AuraEnabled(cacheable=true)
  public static String getDocument(Id customerId) {
    List<Customer_Document__c> documents = [
      SELECT Document_Number__c
      FROM Customer_Document__c
      WHERE Customer__c = :customerId
      WITH USER_MODE
      LIMIT 1
    ];
    return documents.isEmpty() ? null : documents[0].Document_Number__c;
  }

  private static String digitsOf(String value) {
    return value == null ? '' : value.replaceAll('[^0-9]', '');
  }

  /** AuraHandledException hides its message in tests and logs unless setMessage is called. */
  private static AuraHandledException userError(String message) {
    AuraHandledException error = new AuraHandledException(message);
    error.setMessage(message);
    return error;
  }
}
