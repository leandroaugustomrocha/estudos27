/**
 * Spec 002: who sees and changes customers and their CPF/CNPJ (REQ-009, 010, 011, 022).
 * DML and queries run in USER_MODE so CRUD, FLS and sharing apply as in the UI.
 */
@IsTest
private class CustomerSecurityTest {
  @TestSetup
  static void setup() {
    CustomerTestDataFactory.createPersonaUsers();
    System.runAs(CustomerTestDataFactory.getUser(
      CustomerTestDataFactory.USER_A
    )) {
      insert CustomerTestDataFactory.buildCustomer(
        'Cliente de A',
        CustomerTestDataFactory.CPF
      );
    }
  }

  private static Id customerOfA() {
    return [SELECT Id FROM Customer__c WITH SYSTEM_MODE LIMIT 1].Id;
  }

  private static User userNamed(String lastName) {
    return CustomerTestDataFactory.getUser(lastName);
  }

  // AC-008 / REQ-009
  @IsTest
  static void otherUserSeesCustomer_AC008() {
    List<Customer__c> visible;
    System.runAs(userNamed(CustomerTestDataFactory.USER_B)) {
      Test.startTest();
      visible = [SELECT Id, Name FROM Customer__c WITH USER_MODE];
      Test.stopTest();
    }
    Assert.areEqual(
      1,
      visible.size(),
      'User B sees the customer registered by A'
    );
  }

  // AC-009 / REQ-009
  @IsTest
  static void otherUserCannotEditOrDelete_AC009() {
    Id customerId = customerOfA();
    Database.SaveResult edit;
    Database.DeleteResult deletion;
    System.runAs(userNamed(CustomerTestDataFactory.USER_B)) {
      Test.startTest();
      edit = Database.update(
        new Customer__c(Id = customerId, Name = 'Alterado'),
        false,
        AccessLevel.USER_MODE
      );
      deletion = Database.delete(customerId, false, AccessLevel.USER_MODE);
      Test.stopTest();
    }
    Assert.isFalse(
      edit.isSuccess(),
      'User B must not edit a customer registered by A'
    );
    Assert.isFalse(
      deletion.isSuccess(),
      'User B must not delete a customer registered by A'
    );
  }

  // AC-010 / REQ-010
  @IsTest
  static void adminEditsAndDeletesAny_AC010() {
    Id customerId = customerOfA();
    Database.SaveResult edit;
    Database.DeleteResult deletion;
    System.runAs(userNamed(CustomerTestDataFactory.ADMIN)) {
      Test.startTest();
      edit = Database.update(
        new Customer__c(Id = customerId, Name = 'Ajustado'),
        false,
        AccessLevel.USER_MODE
      );
      deletion = Database.delete(customerId, false, AccessLevel.USER_MODE);
      Test.stopTest();
    }
    Assert.isTrue(
      edit.isSuccess(),
      'Admin edits any customer: ' + edit.getErrors()
    );
    Assert.isTrue(
      deletion.isSuccess(),
      'Admin deletes any customer: ' + deletion.getErrors()
    );
  }

  // AC-011 / REQ-011
  @IsTest
  static void userWithoutAccessDenied_AC011() {
    Boolean denied = false;
    System.runAs(userNamed(CustomerTestDataFactory.NO_ACCESS)) {
      Test.startTest();
      try {
        denied = !Database.insert(
            CustomerTestDataFactory.buildCustomer(
              'Sem acesso',
              CustomerTestDataFactory.validCpf(5)
            ),
            false,
            AccessLevel.USER_MODE
          )
          .isSuccess();
      } catch (SecurityException e) {
        denied = true;
      }
      Test.stopTest();
    }
    Assert.isTrue(
      denied,
      'A user without the permission sets must not create customers'
    );
  }

  // AC-025 / REQ-022
  @IsTest
  static void documentVisibleOnlyToOwnerAndAdmin_AC025() {
    Id customerId = customerOfA();
    Integer documentsForB;
    String documentForB;
    String documentForA;
    String documentForAdmin;
    Test.startTest();
    System.runAs(userNamed(CustomerTestDataFactory.USER_B)) {
      documentsForB = [SELECT COUNT() FROM Customer_Document__c WITH USER_MODE];
      documentForB = CustomerController.getDocument(customerId);
    }
    System.runAs(userNamed(CustomerTestDataFactory.USER_A)) {
      documentForA = CustomerController.getDocument(customerId);
    }
    System.runAs(userNamed(CustomerTestDataFactory.ADMIN)) {
      documentForAdmin = CustomerController.getDocument(customerId);
    }
    Test.stopTest();
    Assert.areEqual(
      0,
      documentsForB,
      'User B must not see any document record of A'
    );
    Assert.isNull(
      documentForB,
      'User B must not get the CPF of a customer registered by A'
    );
    Assert.areEqual(
      CustomerTestDataFactory.CPF_FORMATTED,
      documentForA,
      'The owner sees the CPF'
    );
    Assert.areEqual(
      CustomerTestDataFactory.CPF_FORMATTED,
      documentForAdmin,
      'The admin sees the CPF'
    );
  }

  // REQ-022 — users can only read the document record, never write it directly
  @IsTest
  static void documentRecordIsReadOnly_REQ022() {
    Customer_Document__c document = CustomerTestDataFactory.documentOf(
      customerOfA()
    );
    Boolean denied = false;
    System.runAs(userNamed(CustomerTestDataFactory.USER_A)) {
      Test.startTest();
      try {
        denied = !Database.update(
            new Customer_Document__c(
              Id = document.Id,
              Document_Number__c = '000.000.000-00'
            ),
            false,
            AccessLevel.USER_MODE
          )
          .isSuccess();
      } catch (SecurityException e) {
        denied = true;
      }
      Test.stopTest();
    }
    Assert.isTrue(
      denied,
      'Even the owner cannot edit the document record without validation'
    );
  }

  // REQ-022 — admin has Modify All on the document object but read-only fields
  @IsTest
  static void adminCannotEditDocumentNumberDirectly_REQ022() {
    Customer_Document__c document = CustomerTestDataFactory.documentOf(
      customerOfA()
    );
    Boolean denied = false;
    System.runAs(userNamed(CustomerTestDataFactory.ADMIN)) {
      Test.startTest();
      try {
        denied = !Database.update(
            new Customer_Document__c(
              Id = document.Id,
              Document_Number__c = '000.000.000-00'
            ),
            false,
            AccessLevel.USER_MODE
          )
          .isSuccess();
      } catch (SecurityException e) {
        denied = true;
      }
      Test.stopTest();
    }
    Assert.isTrue(
      denied,
      'The admin cannot change the document number directly'
    );
    Assert.areEqual(
      CustomerTestDataFactory.CPF_FORMATTED,
      CustomerTestDataFactory.documentOf(customerOfA()).Document_Number__c,
      'Document number unchanged'
    );
  }

  // REQ-010, REQ-014 — admin replaces the CPF/CNPJ of another user's customer through the validated path
  @IsTest
  static void adminReplacesDocumentOfAnotherUser_REQ010() {
    Id customerId = customerOfA();
    Database.SaveResult result;
    System.runAs(userNamed(CustomerTestDataFactory.ADMIN)) {
      Test.startTest();
      result = Database.update(
        new Customer__c(
          Id = customerId,
          Document_Input__c = CustomerTestDataFactory.CNPJ_ALPHANUMERIC
        ),
        false,
        AccessLevel.USER_MODE
      );
      Test.stopTest();
    }
    Assert.isTrue(
      result.isSuccess(),
      'Admin replaces the document: ' + result.getErrors()
    );
    Assert.areEqual(
      '12.ABC.345/01DE-35',
      CustomerTestDataFactory.documentOf(customerId).Document_Number__c,
      'Document replaced through the trigger'
    );
  }
}
