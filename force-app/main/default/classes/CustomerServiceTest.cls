/**
 * Spec 002: customer rules enforced by CustomerTrigger -> CustomerService.
 * DML runs as a persona with AccessLevel.USER_MODE, as in the UI or an import.
 */
@IsTest
private class CustomerServiceTest {
  @TestSetup
  static void setup() {
    CustomerTestDataFactory.createPersonaUsers();
  }

  private static User userA() {
    return CustomerTestDataFactory.getUser(CustomerTestDataFactory.USER_A);
  }

  private static User userB() {
    return CustomerTestDataFactory.getUser(CustomerTestDataFactory.USER_B);
  }

  private static Database.SaveResult insertAs(
    User runAsUser,
    Customer__c customer
  ) {
    Database.SaveResult result;
    System.runAs(runAsUser) {
      result = Database.insert(customer, false, AccessLevel.USER_MODE);
    }
    return result;
  }

  private static String firstError(Database.SaveResult result) {
    return result.getErrors().isEmpty()
      ? null
      : result.getErrors()[0].getMessage();
  }

  private static void assertRejected(
    Database.SaveResult result,
    String expected,
    String context
  ) {
    Assert.isFalse(result.isSuccess(), context + ' should be rejected');
    Assert.areEqual(
      expected,
      firstError(result),
      context + ': unexpected message'
    );
  }

  private static Customer__c reload(Id customerId) {
    return [
      SELECT
        Id,
        Document_Input__c,
        Person_Type__c,
        Postal_Code__c,
        Phone__c,
        Email__c
      FROM Customer__c
      WHERE Id = :customerId
      WITH SYSTEM_MODE
    ];
  }

  private static Integer countSaved(List<Database.SaveResult> results) {
    Integer saved = 0;
    for (Database.SaveResult result : results) {
      if (result.isSuccess()) {
        saved++;
      }
    }
    return saved;
  }

  // ---------- REQ-001 / REQ-014 / REQ-017 / REQ-022 ----------

  // AC-001 / REQ-001, REQ-014, REQ-022
  @IsTest
  static void customerSavedAndDocumentMovedToPrivateRecord_AC001() {
    User owner = userA();
    Test.startTest();
    Database.SaveResult result = insertAs(
      owner,
      CustomerTestDataFactory.buildCustomer('Maria Silva', '529.982.247-25')
    );
    Test.stopTest();
    Assert.isTrue(
      result.isSuccess(),
      'Customer should be saved: ' + firstError(result)
    );
    Customer__c saved = reload(result.getId());
    Assert.isNull(
      saved.Document_Input__c,
      'The document must never stay on the customer record'
    );
    Assert.areEqual(
      DocumentValidator.INDIVIDUAL,
      saved.Person_Type__c,
      'CPF sets person type Individual'
    );
    Customer_Document__c document = CustomerTestDataFactory.documentOf(
      result.getId()
    );
    Assert.isNotNull(
      document,
      'The document must be stored in Customer_Document__c'
    );
    Assert.areEqual(
      CustomerTestDataFactory.CPF_FORMATTED,
      document.Document_Number__c,
      'Stored formatted'
    );
    Assert.areEqual(
      CustomerTestDataFactory.CPF,
      document.Document_Key__c,
      'Key holds only digits'
    );
    Assert.areEqual(
      owner.Id,
      document.OwnerId,
      'Whoever registered the customer owns the document'
    );
  }

  // AC-014 / REQ-014
  @IsTest
  static void cnpjSetsCompanyType_AC014() {
    Test.startTest();
    Database.SaveResult result = insertAs(
      userA(),
      CustomerTestDataFactory.buildCustomer('Empresa X', '12.abc.345/01de-35')
    );
    Test.stopTest();
    Assert.isTrue(
      result.isSuccess(),
      'Alphanumeric CNPJ should be accepted: ' + firstError(result)
    );
    Assert.areEqual(
      DocumentValidator.COMPANY,
      reload(result.getId()).Person_Type__c,
      'CNPJ sets Company'
    );
    Assert.areEqual(
      '12.ABC.345/01DE-35',
      CustomerTestDataFactory.documentOf(result.getId()).Document_Number__c,
      'CNPJ stored formatted, in uppercase'
    );
  }

  // AC-015 / REQ-015
  @IsTest
  static void invalidDocumentRejected_AC015() {
    Test.startTest();
    Database.SaveResult wrongDigit = insertAs(
      userA(),
      CustomerTestDataFactory.buildCustomer('Maria', '529.982.247-26')
    );
    Database.SaveResult repeated = insertAs(
      userA(),
      CustomerTestDataFactory.buildCustomer('João', '111.111.111-11')
    );
    Test.stopTest();
    assertRejected(
      wrongDigit,
      'CPF/CNPJ inválido.',
      'CPF with a wrong check digit'
    );
    assertRejected(repeated, 'CPF/CNPJ inválido.', 'CPF with all digits equal');
  }

  // AC-016 / REQ-016 — user B cannot see A's document but must still be blocked
  @IsTest
  static void duplicateDocumentFromAnotherUserRejected_AC016() {
    insertAs(
      userA(),
      CustomerTestDataFactory.buildCustomer(
        'Maria',
        CustomerTestDataFactory.CPF_FORMATTED
      )
    );
    Test.startTest();
    Database.SaveResult result = insertAs(
      userB(),
      CustomerTestDataFactory.buildCustomer(
        'Outra Maria',
        CustomerTestDataFactory.CPF
      )
    );
    Test.stopTest();
    assertRejected(
      result,
      'Já existe um cliente com este CPF/CNPJ.',
      'Same CPF registered by another user'
    );
  }

  // AC-017 / REQ-017
  @IsTest
  static void missingDocumentRejected_AC017() {
    Test.startTest();
    Database.SaveResult result = insertAs(
      userA(),
      CustomerTestDataFactory.buildCustomer('Sem documento', null)
    );
    Test.stopTest();
    assertRejected(
      result,
      'Informe o CPF ou CNPJ do cliente.',
      'Customer without CPF/CNPJ'
    );
  }

  // REQ-014 — the document can be replaced on update through the same input field
  @IsTest
  static void documentReplacedOnUpdate_REQ014() {
    User owner = userA();
    Database.SaveResult created = insertAs(
      owner,
      CustomerTestDataFactory.buildCustomer(
        'Maria',
        CustomerTestDataFactory.CPF
      )
    );
    Database.SaveResult updated;
    System.runAs(owner) {
      Test.startTest();
      updated = Database.update(
        new Customer__c(
          Id = created.getId(),
          Document_Input__c = CustomerTestDataFactory.CNPJ_ALPHANUMERIC
        ),
        false,
        AccessLevel.USER_MODE
      );
      Test.stopTest();
    }
    Assert.isTrue(
      updated.isSuccess(),
      'Owner can replace the document: ' + firstError(updated)
    );
    Assert.areEqual(
      DocumentValidator.COMPANY,
      reload(created.getId()).Person_Type__c,
      'Type follows the new document'
    );
    Assert.areEqual(
      '12.ABC.345/01DE-35',
      CustomerTestDataFactory.documentOf(created.getId()).Document_Number__c,
      'Document record holds the new number'
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM Customer_Document__c
        WHERE Customer__c = :created.getId()
        WITH SYSTEM_MODE
      ],
      'Still exactly one document per customer'
    );
  }

  // ---------- REQ-002 / REQ-005 / REQ-023 postal code ----------

  // AC-002 / REQ-002
  @IsTest
  static void postalCodeStoredWithHyphen_AC002() {
    Test.setMock(HttpCalloutMock.class, new ViaCepCalloutMock());
    Customer__c customer = CustomerTestDataFactory.buildCustomer(
      'Maria',
      CustomerTestDataFactory.CPF
    );
    customer.Postal_Code__c = '01310100';
    Test.startTest();
    Database.SaveResult result = insertAs(userA(), customer);
    Test.stopTest();
    Assert.isTrue(
      result.isSuccess(),
      'Customer should be saved: ' + firstError(result)
    );
    Assert.areEqual(
      '01310-100',
      reload(result.getId()).Postal_Code__c,
      'Postal code stored as 00000-000'
    );
  }

  // AC-005 / REQ-005
  @IsTest
  static void postalCodeWithoutEightDigitsRejected_AC005() {
    Customer__c customer = CustomerTestDataFactory.buildCustomer(
      'Maria',
      CustomerTestDataFactory.CPF
    );
    customer.Postal_Code__c = '0131010';
    Test.startTest();
    Database.SaveResult result = insertAs(userA(), customer);
    Test.stopTest();
    assertRejected(
      result,
      'Informe um CEP com 8 dígitos.',
      'Postal code with 7 digits'
    );
  }

  // AC-026 / REQ-023
  @IsTest
  static void blankPostalCodeSavedWithoutLookup_AC026() {
    Integer queuedJobs;
    Database.SaveResult result;
    System.runAs(userA()) {
      Test.startTest();
      result = Database.insert(
        CustomerTestDataFactory.buildCustomer(
          'Maria',
          CustomerTestDataFactory.CPF
        ),
        false,
        AccessLevel.USER_MODE
      );
      queuedJobs = Limits.getQueueableJobs();
      Test.stopTest();
    }
    Assert.isTrue(
      result.isSuccess(),
      'Customer without postal code should be saved: ' + firstError(result)
    );
    Assert.areEqual(
      0,
      queuedJobs,
      'No background lookup without a postal code'
    );
  }

  // ---------- REQ-012 / REQ-013 contact data ----------

  // AC-012 / REQ-012
  @IsTest
  static void invalidEmailRejected_AC012() {
    Customer__c invalid = CustomerTestDataFactory.buildCustomer(
      'Maria',
      CustomerTestDataFactory.CPF
    );
    invalid.Email__c = 'maria@exemplo';
    Customer__c valid = CustomerTestDataFactory.buildCustomer(
      'João',
      CustomerTestDataFactory.validCpf(1)
    );
    valid.Email__c = 'joao@exemplo.com.br';
    Test.startTest();
    Database.SaveResult invalidResult = insertAs(userA(), invalid);
    Database.SaveResult validResult = insertAs(userA(), valid);
    Test.stopTest();
    assertRejected(
      invalidResult,
      'Informe um e-mail válido.',
      'E-mail without domain suffix'
    );
    Assert.isTrue(
      validResult.isSuccess(),
      'Valid e-mail accepted: ' + firstError(validResult)
    );
  }

  // AC-013 / REQ-013
  @IsTest
  static void phoneFormattedOrRejected_AC013() {
    Customer__c mobile = CustomerTestDataFactory.buildCustomer(
      'Maria',
      CustomerTestDataFactory.CPF
    );
    mobile.Phone__c = '11987654321';
    Customer__c landline = CustomerTestDataFactory.buildCustomer(
      'João',
      CustomerTestDataFactory.validCpf(2)
    );
    landline.Phone__c = '(11) 3333-4444';
    Customer__c withoutAreaCode = CustomerTestDataFactory.buildCustomer(
      'Ana',
      CustomerTestDataFactory.validCpf(3)
    );
    withoutAreaCode.Phone__c = '98765-4321';
    Test.startTest();
    Database.SaveResult mobileResult = insertAs(userA(), mobile);
    Database.SaveResult landlineResult = insertAs(userA(), landline);
    Database.SaveResult invalidResult = insertAs(userA(), withoutAreaCode);
    Test.stopTest();
    Assert.areEqual(
      '(11) 98765-4321',
      reload(mobileResult.getId()).Phone__c,
      'Mobile phone formatted'
    );
    Assert.areEqual(
      '(11) 3333-4444',
      reload(landlineResult.getId()).Phone__c,
      'Landline phone formatted'
    );
    assertRejected(
      invalidResult,
      'Informe um telefone com DDD (10 ou 11 dígitos).',
      'Phone without area code'
    );
  }

  // ---------- REQ-020 / REQ-021 bulk ----------

  // AC-022 / REQ-020
  @IsTest
  static void bulkImportKeepsValidRows_AC022() {
    List<Customer__c> customers = new List<Customer__c>();
    for (Integer i = 0; i < 200; i++) {
      customers.add(
        CustomerTestDataFactory.buildCustomer(
          'Cliente ' + i,
          CustomerTestDataFactory.validCpf(i + 10)
        )
      );
    }
    customers[150].Email__c = 'sem-arroba';
    List<Database.SaveResult> results;
    Integer queries;
    System.runAs(userA()) {
      Test.startTest();
      results = Database.insert(customers, false, AccessLevel.USER_MODE);
      queries = Limits.getQueries();
      Test.stopTest();
    }
    Assert.areEqual(
      199,
      countSaved(results),
      'The 199 valid customers are saved'
    );
    assertRejected(
      results[150],
      'Informe um e-mail válido.',
      'Row with invalid e-mail'
    );
    Assert.areEqual(
      199,
      [SELECT COUNT() FROM Customer_Document__c WITH SYSTEM_MODE],
      'One document per saved customer'
    );
    Assert.isTrue(
      queries <= 6,
      'Constant query count for 200 rows, used: ' + queries
    );
  }

  // AC-023 / REQ-021
  @IsTest
  static void duplicateInBatchFirstWins_AC023() {
    List<Customer__c> batch = new List<Customer__c>{
      CustomerTestDataFactory.buildCustomer(
        'Primeira',
        CustomerTestDataFactory.CPF_FORMATTED
      ),
      CustomerTestDataFactory.buildCustomer(
        'Segunda',
        CustomerTestDataFactory.CPF
      )
    };
    List<Database.SaveResult> results;
    System.runAs(userA()) {
      Test.startTest();
      results = Database.insert(batch, false, AccessLevel.USER_MODE);
      Test.stopTest();
    }
    Assert.isTrue(
      results[0].isSuccess(),
      'First customer of the batch is saved: ' + firstError(results[0])
    );
    assertRejected(
      results[1],
      'Já existe um cliente com este CPF/CNPJ.',
      'Second customer with the same CPF'
    );
  }

  // ---------- REQ-027 / REQ-028 delete and restore ----------

  // AC-031 / REQ-027
  @IsTest
  static void deletingCustomerFreesDocument_AC031() {
    User owner = userA();
    Database.SaveResult created = insertAs(
      owner,
      CustomerTestDataFactory.buildCustomer(
        'Maria',
        CustomerTestDataFactory.CPF
      )
    );
    Database.SaveResult reused;
    Test.startTest();
    System.runAs(owner) {
      Database.delete(created.getId(), false, AccessLevel.USER_MODE);
    }
    reused = insertAs(
      userB(),
      CustomerTestDataFactory.buildCustomer(
        'Nova Maria',
        CustomerTestDataFactory.CPF
      )
    );
    Test.stopTest();
    Assert.isNull(
      CustomerTestDataFactory.documentOf(created.getId()),
      'Document deleted with the customer'
    );
    Assert.isTrue(
      reused.isSuccess(),
      'The CPF can be used again: ' + firstError(reused)
    );
  }

  // AC-032 / REQ-028
  @IsTest
  static void restoringCustomerRestoresDocument_AC032() {
    User owner = userA();
    Database.SaveResult created = insertAs(
      owner,
      CustomerTestDataFactory.buildCustomer(
        'Maria',
        CustomerTestDataFactory.CPF
      )
    );
    Database.UndeleteResult restored;
    System.runAs(owner) {
      Database.delete(created.getId(), false, AccessLevel.USER_MODE);
      Test.startTest();
      restored = Database.undelete(
        created.getId(),
        false,
        AccessLevel.USER_MODE
      );
      Test.stopTest();
    }
    Assert.isTrue(
      restored.isSuccess(),
      'Customer restored: ' + restored.getErrors()
    );
    Customer_Document__c document = CustomerTestDataFactory.documentOf(
      created.getId()
    );
    Assert.isNotNull(document, 'Document restored with the customer');
    Assert.areEqual(
      CustomerTestDataFactory.CPF_FORMATTED,
      document.Document_Number__c,
      'Same document number'
    );
  }

  // AC-032 / REQ-028
  @IsTest
  static void restoreBlockedWhenDocumentReused_AC032() {
    User owner = userA();
    Database.SaveResult created = insertAs(
      owner,
      CustomerTestDataFactory.buildCustomer(
        'Maria',
        CustomerTestDataFactory.CPF
      )
    );
    System.runAs(owner) {
      Database.delete(created.getId(), false, AccessLevel.USER_MODE);
    }
    insertAs(
      userB(),
      CustomerTestDataFactory.buildCustomer(
        'Nova Maria',
        CustomerTestDataFactory.CPF
      )
    );
    Database.UndeleteResult restored;
    System.runAs(owner) {
      Test.startTest();
      restored = Database.undelete(
        created.getId(),
        false,
        AccessLevel.USER_MODE
      );
      Test.stopTest();
    }
    Assert.isFalse(
      restored.isSuccess(),
      'Restore must be denied when the CPF was reused'
    );
    Assert.areEqual(
      'Já existe um cliente com este CPF/CNPJ.',
      restored.getErrors()[0].getMessage(),
      'Duplicate message on restore'
    );
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM Customer__c
        WHERE Id = :created.getId()
        WITH SYSTEM_MODE
      ],
      'Customer stays in the Recycle Bin'
    );
  }
}
