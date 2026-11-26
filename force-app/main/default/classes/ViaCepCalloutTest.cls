/**
 * Spec 002: ViaCEP lookup outcomes (REQ-003, REQ-006, REQ-007).
 */
@IsTest
private class ViaCepCalloutTest {
  // AC-003 / REQ-003
  @IsTest
  static void foundPostalCodeReturnsAddress_AC003() {
    ViaCepCalloutMock mock = new ViaCepCalloutMock();
    Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    ViaCepCallout.Result result = ViaCepCallout.lookup('01310100');
    Test.stopTest();
    Assert.areEqual(
      ViaCepCallout.Status.FOUND,
      result.status,
      'Existing postal code is FOUND'
    );
    Assert.areEqual(
      'Avenida Paulista',
      result.street,
      'Street from "logradouro"'
    );
    Assert.areEqual('Bela Vista', result.district, 'District from "bairro"');
    Assert.areEqual('São Paulo', result.city, 'City from "localidade"');
    Assert.areEqual('SP', result.state, 'State from "uf"');
    Assert.areEqual(
      'callout:ViaCep/ws/01310100/json/',
      mock.endpoints[0],
      'Lookup goes through the ViaCep named credential'
    );
  }

  // AC-006 / REQ-006 — ViaCEP answers {"erro": "true"} (text) and older APIs {"erro": true}
  @IsTest
  static void unknownPostalCodeIsNotFound_AC006() {
    Test.setMock(HttpCalloutMock.class, new ViaCepCalloutMock());
    Test.startTest();
    ViaCepCallout.Result asText = ViaCepCallout.lookup('99999999');
    ViaCepCallout.Result asBoolean = ViaCepCallout.lookup('88888888');
    Test.stopTest();
    Assert.areEqual(
      ViaCepCallout.Status.NOT_FOUND,
      asText.status,
      '{"erro": "true"} means NOT_FOUND'
    );
    Assert.areEqual(
      ViaCepCallout.Status.NOT_FOUND,
      asBoolean.status,
      '{"erro": true} means NOT_FOUND'
    );
  }

  // AC-007 / REQ-007
  @IsTest
  static void serverErrorIsUnavailable_AC007() {
    Test.setMock(
      HttpCalloutMock.class,
      new ViaCepCalloutMock(ViaCepCalloutMock.Behavior.SERVER_ERROR)
    );
    Test.startTest();
    ViaCepCallout.Result result = ViaCepCallout.lookup('01310100');
    Test.stopTest();
    Assert.areEqual(
      ViaCepCallout.Status.UNAVAILABLE,
      result.status,
      'HTTP 500 means UNAVAILABLE'
    );
  }

  // AC-007 / REQ-007 — timeout or network failure
  @IsTest
  static void calloutExceptionIsUnavailable_AC007() {
    Test.setMock(
      HttpCalloutMock.class,
      new ViaCepCalloutMock(ViaCepCalloutMock.Behavior.CALLOUT_EXCEPTION)
    );
    Test.startTest();
    ViaCepCallout.Result result = ViaCepCallout.lookup('01310100');
    Test.stopTest();
    Assert.areEqual(
      ViaCepCallout.Status.UNAVAILABLE,
      result.status,
      'A callout exception means UNAVAILABLE'
    );
  }
}
