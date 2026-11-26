/**
 * Spec 002: Apex behind the customer form (REQ-003 to REQ-007, REQ-018, REQ-019).
 * Records used by update tests are created in @TestSetup: a callout cannot follow
 * uncommitted DML in the same transaction.
 */
@IsTest
private class CustomerControllerTest {
  @TestSetup
  static void setup() {
    CustomerTestDataFactory.createPersonaUsers();
    System.runAs(CustomerTestDataFactory.getUser(
      CustomerTestDataFactory.USER_A
    )) {
      Customer__c existing = CustomerTestDataFactory.buildCustomer(
        'Cliente Existente',
        CustomerTestDataFactory.CPF
      );
      existing.Address_Number__c = '1000';
      existing.Address_Complement__c = 'Sala 5';
      insert existing;
    }
  }

  private static User userA() {
    return CustomerTestDataFactory.getUser(CustomerTestDataFactory.USER_A);
  }

  private static Customer__c existingCustomer() {
    return [SELECT Id FROM Customer__c WITH SYSTEM_MODE LIMIT 1];
  }

  private static Customer__c reload(Id customerId) {
    return [
      SELECT
        Postal_Code__c,
        Street__c,
        District__c,
        City__c,
        State__c,
        Address_Number__c,
        Address_Complement__c
      FROM Customer__c
      WHERE Id = :customerId
      WITH SYSTEM_MODE
    ];
  }

  private static Customer__c formCustomer(String postalCode) {
    Customer__c customer = CustomerTestDataFactory.buildCustomer(
      'Cliente da Tela',
      CustomerTestDataFactory.validCpf(7)
    );
    customer.Postal_Code__c = postalCode;
    return customer;
  }

  // ---------- lookupCep ----------

  // AC-003 / REQ-003
  @IsTest
  static void lookupFillsAddress_AC003() {
    Test.setMock(HttpCalloutMock.class, new ViaCepCalloutMock());
    CustomerController.AddressResult result;
    System.runAs(userA()) {
      Test.startTest();
      result = CustomerController.lookupCep('01310-100');
      Test.stopTest();
    }
    Assert.areEqual('FOUND', result.status, 'Existing postal code is found');
    Assert.areEqual('Avenida Paulista', result.street, 'Street');
    Assert.areEqual('Bela Vista', result.district, 'District');
    Assert.areEqual('São Paulo', result.city, 'City');
    Assert.areEqual('SP', result.state, 'State');
  }

  // AC-005 / REQ-005
  @IsTest
  static void lookupRejectsWrongLengthWithoutCallout_AC005() {
    ViaCepCalloutMock mock = new ViaCepCalloutMock();
    Test.setMock(HttpCalloutMock.class, mock);
    String message;
    System.runAs(userA()) {
      Test.startTest();
      try {
        CustomerController.lookupCep('0131010');
      } catch (AuraHandledException e) {
        message = e.getMessage();
      }
      Test.stopTest();
    }
    Assert.areEqual(
      'Informe um CEP com 8 dígitos.',
      message,
      'Format message for a 7-digit postal code'
    );
    Assert.areEqual(0, mock.calls, 'The service must not be called');
  }

  // AC-006 / REQ-006
  @IsTest
  static void lookupReportsNotFound_AC006() {
    Test.setMock(HttpCalloutMock.class, new ViaCepCalloutMock());
    CustomerController.AddressResult result;
    System.runAs(userA()) {
      Test.startTest();
      result = CustomerController.lookupCep('99999-999');
      Test.stopTest();
    }
    Assert.areEqual(
      'NOT_FOUND',
      result.status,
      'Unknown postal code reported to the form'
    );
  }

  // AC-007 / REQ-007
  @IsTest
  static void lookupReportsUnavailable_AC007() {
    Test.setMock(
      HttpCalloutMock.class,
      new ViaCepCalloutMock(ViaCepCalloutMock.Behavior.SERVER_ERROR)
    );
    CustomerController.AddressResult result;
    System.runAs(userA()) {
      Test.startTest();
      result = CustomerController.lookupCep('01310-100');
      Test.stopTest();
    }
    Assert.areEqual(
      'UNAVAILABLE',
      result.status,
      'Service down reported to the form'
    );
  }

  // ---------- saveCustomer ----------

  // AC-018 / REQ-018 — server re-checks the postal code; city and UF come from it
  @IsTest
  static void saveUsesCityAndStateFromPostalCode_AC018() {
    Test.setMock(HttpCalloutMock.class, new ViaCepCalloutMock());
    Customer__c customer = formCustomer('01310100');
    customer.Street__c = 'Avenida Paulista (bloco B)';
    customer.District__c = 'Bela Vista';
    customer.City__c = 'Campinas';
    customer.State__c = 'RJ';
    Id customerId;
    Integer queuedJobs;
    System.runAs(userA()) {
      Test.startTest();
      customerId = CustomerController.saveCustomer(customer);
      queuedJobs = Limits.getQueueableJobs();
      Test.stopTest();
    }
    Customer__c saved = reload(customerId);
    Assert.areEqual('01310-100', saved.Postal_Code__c, 'Postal code formatted');
    Assert.areEqual(
      'São Paulo',
      saved.City__c,
      'City always from the postal code'
    );
    Assert.areEqual('SP', saved.State__c, 'UF always from the postal code');
    Assert.areEqual(
      'Avenida Paulista (bloco B)',
      saved.Street__c,
      'Adjusted street is kept'
    );
    Assert.areEqual(
      0,
      queuedJobs,
      'The form already looked up the postal code: no background job'
    );
  }

  // AC-006 / REQ-006
  @IsTest
  static void saveBlockedForUnknownPostalCode_AC006() {
    Test.setMock(HttpCalloutMock.class, new ViaCepCalloutMock());
    String message;
    System.runAs(userA()) {
      Test.startTest();
      try {
        CustomerController.saveCustomer(formCustomer('99999-999'));
      } catch (AuraHandledException e) {
        message = e.getMessage();
      }
      Test.stopTest();
    }
    Assert.areEqual(
      'CEP não encontrado. Confira o número digitado.',
      message,
      'Save blocked'
    );
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM Customer__c
        WHERE Name = 'Cliente da Tela'
        WITH SYSTEM_MODE
      ],
      'Nothing saved'
    );
  }

  // AC-007 / REQ-007
  @IsTest
  static void saveAcceptsManualAddressWhenServiceDown_AC007() {
    Test.setMock(
      HttpCalloutMock.class,
      new ViaCepCalloutMock(ViaCepCalloutMock.Behavior.CALLOUT_EXCEPTION)
    );
    Customer__c customer = formCustomer('01310-100');
    customer.Street__c = 'Rua Digitada';
    customer.City__c = 'Campinas';
    customer.State__c = 'SP';
    Id customerId;
    System.runAs(userA()) {
      Test.startTest();
      customerId = CustomerController.saveCustomer(customer);
      Test.stopTest();
    }
    Customer__c saved = reload(customerId);
    Assert.areEqual(
      'Campinas',
      saved.City__c,
      'Typed city kept when the service is down'
    );
    Assert.areEqual(
      'Rua Digitada',
      saved.Street__c,
      'Typed street kept when the service is down'
    );
  }

  // AC-020 / REQ-019 — changing the postal code of an existing customer
  @IsTest
  static void changingPostalCodeKeepsNumberAndComplement_AC020() {
    Test.setMock(HttpCalloutMock.class, new ViaCepCalloutMock());
    Customer__c edited = new Customer__c(
      Id = existingCustomer().Id,
      Postal_Code__c = '20040-020',
      Street__c = 'Praça Pio X',
      District__c = 'Centro'
    );
    System.runAs(userA()) {
      Test.startTest();
      CustomerController.saveCustomer(edited);
      Test.stopTest();
    }
    Customer__c saved = reload(edited.Id);
    Assert.areEqual(
      'Rio de Janeiro',
      saved.City__c,
      'City of the new postal code'
    );
    Assert.areEqual('RJ', saved.State__c, 'UF of the new postal code');
    Assert.areEqual('1000', saved.Address_Number__c, 'Number untouched');
    Assert.areEqual(
      'Sala 5',
      saved.Address_Complement__c,
      'Complement untouched'
    );
  }

  // REQ-012 — trigger validations reach the form as a readable message
  @IsTest
  static void saveReturnsValidationMessage_REQ012() {
    Customer__c customer = formCustomer(null);
    customer.Email__c = 'maria@exemplo';
    String message;
    System.runAs(userA()) {
      Test.startTest();
      try {
        CustomerController.saveCustomer(customer);
      } catch (AuraHandledException e) {
        message = e.getMessage();
      }
      Test.stopTest();
    }
    Assert.areEqual(
      'Informe um e-mail válido.',
      message,
      'Validation message shown in the form'
    );
  }
}
