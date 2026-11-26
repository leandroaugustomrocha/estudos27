/**
 * Spec 002: background postal code lookup for customers saved outside the form —
 * imports, integrations and the standard "New" button (REQ-008, REQ-024, REQ-025).
 * The job runs at Test.stopTest().
 */
@IsTest
private class CustomerAddressLookupJobTest {
  @TestSetup
  static void setup() {
    CustomerTestDataFactory.createPersonaUsers();
  }

  private static User userA() {
    return CustomerTestDataFactory.getUser(CustomerTestDataFactory.USER_A);
  }

  private static Customer__c imported(
    String name,
    Integer seed,
    String postalCode,
    String city
  ) {
    Customer__c customer = CustomerTestDataFactory.buildCustomer(
      name,
      CustomerTestDataFactory.validCpf(seed)
    );
    customer.Postal_Code__c = postalCode;
    customer.City__c = city;
    return customer;
  }

  private static Customer__c reload(Id customerId) {
    return [
      SELECT
        Postal_Code__c,
        Street__c,
        District__c,
        City__c,
        State__c,
        Address_Note__c
      FROM Customer__c
      WHERE Id = :customerId
      WITH SYSTEM_MODE
    ];
  }

  private static Id importAs(Customer__c customer) {
    Database.SaveResult result;
    System.runAs(userA()) {
      Test.startTest();
      result = Database.insert(customer, false, AccessLevel.USER_MODE);
      Test.stopTest();
    }
    Assert.isTrue(
      result.isSuccess(),
      'Imported customer saved right away: ' + result.getErrors()
    );
    return result.getId();
  }

  // AC-021, AC-030 / REQ-008 — import or standard "New": only empty fields are filled
  @IsTest
  static void fillsOnlyEmptyAddressFields_AC021() {
    Test.setMock(HttpCalloutMock.class, new ViaCepCalloutMock());
    Id customerId = importAs(
      imported('Importado', 1, '01310-100', 'São Paulo')
    );
    Customer__c saved = reload(customerId);
    Assert.areEqual('Avenida Paulista', saved.Street__c, 'Empty street filled');
    Assert.areEqual('Bela Vista', saved.District__c, 'Empty district filled');
    Assert.areEqual('SP', saved.State__c, 'Empty UF filled');
    Assert.areEqual('São Paulo', saved.City__c, 'City from the file kept');
    Assert.isNull(saved.Address_Note__c, 'No note when the postal code exists');
  }

  // REQ-008 — values that came in the file are never overwritten
  @IsTest
  static void keepsFieldsFromTheFile_REQ008() {
    Test.setMock(HttpCalloutMock.class, new ViaCepCalloutMock());
    Customer__c customer = imported(
      'Importado',
      2,
      '01310-100',
      'Cidade do Arquivo'
    );
    customer.Street__c = 'Rua do Arquivo';
    Id customerId = importAs(customer);
    Customer__c saved = reload(customerId);
    Assert.areEqual(
      'Rua do Arquivo',
      saved.Street__c,
      'Street from the file kept'
    );
    Assert.areEqual(
      'Cidade do Arquivo',
      saved.City__c,
      'City from the file kept'
    );
    Assert.areEqual(
      'Bela Vista',
      saved.District__c,
      'Only the empty district filled'
    );
  }

  // AC-027 / REQ-024
  @IsTest
  static void unknownPostalCodeIsRemovedWithNote_AC027() {
    Test.setMock(HttpCalloutMock.class, new ViaCepCalloutMock());
    Id customerId = importAs(imported('Importado', 3, '99999-999', 'Campinas'));
    Customer__c saved = reload(customerId);
    Assert.isNull(saved.Postal_Code__c, 'Unknown postal code removed');
    Assert.areEqual('Campinas', saved.City__c, 'Rest of the customer kept');
    Assert.isNotNull(saved.Address_Note__c, 'A note records the removal');
    Assert.isTrue(
      saved.Address_Note__c.startsWith('CEP 99999-999 removido em '),
      'Note names the removed postal code: ' + saved.Address_Note__c
    );
    Assert.isTrue(
      saved.Address_Note__c.endsWith(': CEP não encontrado.'),
      'Note gives the reason: ' + saved.Address_Note__c
    );
  }

  // AC-028 / REQ-025
  @IsTest
  static void serviceDownLeavesCustomerAsImported_AC028() {
    Test.setMock(
      HttpCalloutMock.class,
      new ViaCepCalloutMock(ViaCepCalloutMock.Behavior.CALLOUT_EXCEPTION)
    );
    Id customerId = importAs(imported('Importado', 4, '01310-100', null));
    Customer__c saved = reload(customerId);
    Assert.areEqual('01310-100', saved.Postal_Code__c, 'Postal code kept');
    Assert.isNull(saved.Street__c, 'Address stays as imported');
    Assert.isNull(saved.Address_Note__c, 'No note when the service is down');
  }

  // REQ-008 — one execution handles BATCH_SIZE customers, one callout per distinct postal code
  @IsTest
  static void processesOneBatchWithOneCalloutPerPostalCode_REQ008() {
    ViaCepCalloutMock mock = new ViaCepCalloutMock();
    Test.setMock(HttpCalloutMock.class, mock);
    List<Customer__c> customers = new List<Customer__c>();
    for (Integer i = 0; i < CustomerAddressLookupJob.BATCH_SIZE + 5; i++) {
      customers.add(
        imported(
          'Lote ' + i,
          100 + i,
          Math.mod(i, 2) == 0 ? '01310-100' : '20040-020',
          null
        )
      );
    }
    System.runAs(userA()) {
      Test.startTest();
      Database.insert(customers, false, AccessLevel.USER_MODE);
      Test.stopTest();
    }
    Integer filled = [
      SELECT COUNT()
      FROM Customer__c
      WHERE Street__c != NULL
      WITH SYSTEM_MODE
    ];
    Assert.areEqual(
      CustomerAddressLookupJob.BATCH_SIZE,
      filled,
      'One execution processes exactly one batch'
    );
    Assert.areEqual(
      2,
      mock.calls,
      'One callout per distinct postal code in the batch'
    );
  }
}
