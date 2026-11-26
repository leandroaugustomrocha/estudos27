/**
 * Spec 002: CPF/CNPJ check digits and formatting (REQ-014, REQ-015).
 * Vectors are fixed and independent of the code under test: CPF 529.982.247-25,
 * Receita Federal's official alphanumeric example 12.ABC.345/01DE-35 and a numeric CNPJ,
 * all checked by script in task T03.
 */
@IsTest
private class DocumentValidatorTest {
  // AC-014 / REQ-014
  @IsTest
  static void cpfIsValidFormattedAndIndividual_AC014() {
    Test.startTest();
    String key = DocumentValidator.normalize('529.982.247-25');
    Boolean valid = DocumentValidator.isValid(key);
    String formatted = DocumentValidator.format(key);
    String personType = DocumentValidator.personType(key);
    Test.stopTest();
    Assert.areEqual('52998224725', key, 'Normalization keeps only the digits');
    Assert.isTrue(valid, 'CPF 529.982.247-25 is valid');
    Assert.areEqual('529.982.247-25', formatted, 'CPF format 000.000.000-00');
    Assert.areEqual(
      DocumentValidator.INDIVIDUAL,
      personType,
      'CPF means Individual (Física)'
    );
  }

  // AC-014 / REQ-014
  @IsTest
  static void alphanumericCnpjOfficialExample_AC014() {
    Test.startTest();
    String key = DocumentValidator.normalize('12.abc.345/01de-35');
    Boolean valid = DocumentValidator.isValid(key);
    String formatted = DocumentValidator.format(key);
    String personType = DocumentValidator.personType(key);
    Test.stopTest();
    Assert.areEqual(
      '12ABC34501DE35',
      key,
      'Normalization keeps letters, in uppercase'
    );
    Assert.isTrue(valid, 'Official example 12.ABC.345/01DE-35 is valid');
    Assert.areEqual(
      '12.ABC.345/01DE-35',
      formatted,
      'CNPJ format AA.AAA.AAA/AAAA-00'
    );
    Assert.areEqual(
      DocumentValidator.COMPANY,
      personType,
      'CNPJ means Company (Jurídica)'
    );
  }

  // AC-014 / REQ-014
  @IsTest
  static void numericCnpjIsValid_AC014() {
    Test.startTest();
    Boolean valid = DocumentValidator.isValid('11222333000181');
    String formatted = DocumentValidator.format('11222333000181');
    Test.stopTest();
    Assert.isTrue(valid, 'Numeric CNPJ 11.222.333/0001-81 is valid');
    Assert.areEqual('11.222.333/0001-81', formatted, 'Numeric CNPJ formatted');
  }

  // AC-015 / REQ-015
  @IsTest
  static void invalidDocumentsAreRejected_AC015() {
    Test.startTest();
    Boolean wrongCpfDigit = DocumentValidator.isValid('52998224726');
    Boolean repeatedCpf = DocumentValidator.isValid('11111111111');
    Boolean wrongCnpjDigit = DocumentValidator.isValid('12ABC34501DE36');
    Boolean repeatedCnpj = DocumentValidator.isValid('00000000000000');
    Boolean wrongLength = DocumentValidator.isValid('5299822472');
    Boolean letterInCheckDigits = DocumentValidator.isValid('12ABC34501DE3A');
    Boolean blank = DocumentValidator.isValid(null);
    Test.stopTest();
    Assert.isFalse(wrongCpfDigit, 'CPF with a wrong check digit is invalid');
    Assert.isFalse(repeatedCpf, 'CPF with all digits equal is invalid');
    Assert.isFalse(wrongCnpjDigit, 'CNPJ with a wrong check digit is invalid');
    Assert.isFalse(repeatedCnpj, 'CNPJ with all characters equal is invalid');
    Assert.isFalse(wrongLength, 'A 10-digit document is neither CPF nor CNPJ');
    Assert.isFalse(letterInCheckDigits, 'CNPJ check digits are always numeric');
    Assert.isFalse(blank, 'A blank document is invalid');
  }
}
