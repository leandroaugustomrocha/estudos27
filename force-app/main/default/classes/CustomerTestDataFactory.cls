/**
 * Test data for spec 002 (customers with postal code lookup).
 * Personas are Minimum Access users whose only access comes from the spec permission sets.
 */
@IsTest
public class CustomerTestDataFactory {
  public static final String USER_A = 'CustomerUserA';
  public static final String USER_B = 'CustomerUserB';
  public static final String ADMIN = 'CustomerAdmin';
  public static final String NO_ACCESS = 'CustomerNoAccess';

  /** Valid CPF used across the tests (well-known test number). */
  public static final String CPF = '52998224725';
  public static final String CPF_FORMATTED = '529.982.247-25';
  /** Official alphanumeric CNPJ example published by Receita Federal. */
  public static final String CNPJ_ALPHANUMERIC = '12ABC34501DE35';

  private static final String MINIMUM_ACCESS_PROFILE = 'Minimum Access - Salesforce';

  /** Setup DML: call first, then create data inside System.runAs. */
  public static void createPersonaUsers() {
    Id profileId = [
      SELECT Id
      FROM Profile
      WHERE Name = :MINIMUM_ACCESS_PROFILE
      LIMIT 1
    ]
    .Id;
    Map<String, User> users = new Map<String, User>{
      USER_A => buildUser(USER_A, profileId),
      USER_B => buildUser(USER_B, profileId),
      ADMIN => buildUser(ADMIN, profileId),
      NO_ACCESS => buildUser(NO_ACCESS, profileId)
    };
    insert users.values();

    Map<String, Id> permissionSetIds = new Map<String, Id>();
    for (PermissionSet permissionSet : [
      SELECT Id, Name
      FROM PermissionSet
      WHERE Name IN ('Customer_User', 'Customer_Admin')
    ]) {
      permissionSetIds.put(permissionSet.Name, permissionSet.Id);
    }
    insert new List<PermissionSetAssignment>{
      new PermissionSetAssignment(
        AssigneeId = users.get(USER_A).Id,
        PermissionSetId = permissionSetIds.get('Customer_User')
      ),
      new PermissionSetAssignment(
        AssigneeId = users.get(USER_B).Id,
        PermissionSetId = permissionSetIds.get('Customer_User')
      ),
      new PermissionSetAssignment(
        AssigneeId = users.get(ADMIN).Id,
        PermissionSetId = permissionSetIds.get('Customer_Admin')
      )
    };
  }

  public static User getUser(String lastName) {
    return [SELECT Id FROM User WHERE LastName = :lastName LIMIT 1];
  }

  /** Customer without postal code (no background lookup is scheduled). */
  public static Customer__c buildCustomer(String name, String document) {
    return new Customer__c(
      Name = name,
      Document_Input__c = document,
      Address_Number__c = '100',
      Address_Complement__c = 'Sala 1'
    );
  }

  /** The customer's document, read in SYSTEM_MODE (test-side check only). */
  public static Customer_Document__c documentOf(Id customerId) {
    List<Customer_Document__c> documents = [
      SELECT Id, Document_Number__c, Document_Key__c, OwnerId
      FROM Customer_Document__c
      WHERE Customer__c = :customerId
      WITH SYSTEM_MODE
    ];
    return documents.isEmpty() ? null : documents[0];
  }

  /** Valid CPF built from a seed, for bulk tests (check digits: modulus 11). */
  public static String validCpf(Integer seed) {
    String base = String.valueOf(100000000 + seed).right(9);
    Integer first = cpfCheckDigit(base, 10);
    Integer second = cpfCheckDigit(base + first, 11);
    return base + first + second;
  }

  private static Integer cpfCheckDigit(String digits, Integer firstWeight) {
    Integer total = 0;
    for (Integer i = 0; i < digits.length(); i++) {
      total += Integer.valueOf(digits.substring(i, i + 1)) * (firstWeight - i);
    }
    Integer remainder = Math.mod(total, 11);
    return remainder < 2 ? 0 : 11 - remainder;
  }

  private static User buildUser(String lastName, Id profileId) {
    String uniqueKey = String.valueOf(Crypto.getRandomInteger())
      .replace('-', '');
    return new User(
      LastName = lastName,
      Alias = lastName.right(8),
      Email = lastName.toLowerCase() + '@example.com',
      Username = lastName.toLowerCase() + '.' + uniqueKey + '@example.com',
      ProfileId = profileId,
      TimeZoneSidKey = 'America/Sao_Paulo',
      LocaleSidKey = 'pt_BR',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
  }
}
