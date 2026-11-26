// Seed data for spec 002 (customers with postal code lookup): 200 customers saved like an
// import, so the trigger validates them and CustomerAddressLookupBatch looks up the real
// ViaCEP service in the background (REQ-008).
// Run:   sf apex run --file scripts/apex/seed-002-customers.apex --target-org estudos27
// Undo:  scripts/apex/cleanup-002-customers.apex
//
// Mix (by design):
//   - 170 with a real postal code and empty address  -> the batch fills the address
//   -  10 with a real postal code and the city typed -> only the empty fields are filled
//   -  10 with postal code 99999-999 (does not exist) -> postal code removed + note (REQ-024)
//   -  10 without postal code                         -> saved as is (REQ-023)
// Documents: 160 CPFs and 40 CNPJs (20 alphanumeric), generated with valid check digits.
// Every seed customer uses an e-mail at seed002.example.com (reserved example domain),
// which is how the cleanup script finds them. The running user needs Customer_Admin.

final String EMAIL_DOMAIN = '@seed002.example.com';
Assert.areEqual(
  0,
  [SELECT COUNT() FROM Customer__c WHERE Email__c LIKE '%@seed002.example.com'],
  'Seed already loaded: run cleanup-002-customers.apex first.'
);

// Postal codes checked against ViaCEP before writing this script (all exist).
List<String> postalCodes = new List<String>{
  '01001-000', '01310-100', '04538-133', '20040-020', '22071-000', '30130-010', '50030-000',
  '60060-000', '69005-000', '70040-010', '74003-010', '80010-000', '88010-000', '90010-000',
  '13010-000', '57020-000', '64000-020', '66010-000', '59010-000', '58010-000', '49010-000',
  '65010-000', '78005-000', '79002-000', '76801-000'
};
List<String> firstNames = new List<String>{
  'Ana', 'Bruno', 'Carla', 'Daniel', 'Eduarda', 'Felipe', 'Gabriela', 'Henrique', 'Isabela', 'João',
  'Larissa', 'Marcos', 'Natália', 'Otávio', 'Patrícia', 'Rafael', 'Sofia', 'Thiago', 'Vanessa', 'Yuri'
};
List<String> lastNames = new List<String>{
  'Almeida', 'Barbosa', 'Cardoso', 'Duarte', 'Esteves', 'Ferreira', 'Gomes', 'Lima', 'Moreira', 'Nogueira',
  'Oliveira', 'Pereira', 'Queiroz', 'Ribeiro', 'Santos', 'Teixeira'
};
List<String> companyTypes = new List<String>{ 'Comércio', 'Serviços', 'Tecnologia', 'Logística', 'Alimentos' };

// ---------- document generators (same rules as DocumentValidator) ----------
String checkDigit(String characters, Integer maxWeight) {
  Integer total = 0;
  Integer weight = 2;
  for (Integer i = characters.length() - 1; i >= 0; i--) {
    total += (characters.charAt(i) - 48) * weight;
    weight = weight == maxWeight ? 2 : weight + 1;
  }
  Integer remainder = Math.mod(total, 11);
  return String.valueOf(remainder < 2 ? 0 : 11 - remainder);
}
String withCheckDigits(String base, Integer maxWeight) {
  String first = checkDigit(base, maxWeight);
  return base + first + checkDigit(base + first, maxWeight);
}
String cpf(Integer seed) {
  return withCheckDigits(String.valueOf(310000000 + seed * 7919).right(9), 11);
}
String numericCnpj(Integer seed) {
  return withCheckDigits(String.valueOf(40000000 + seed * 131).right(8) + '0001', 9);
}
String alphanumericCnpj(Integer seed) {
  String letters = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  String code = letters.substring(Math.mod(seed, 24), Math.mod(seed, 24) + 1) +
    letters.substring(Math.mod(seed * 7, 24), Math.mod(seed * 7, 24) + 1);
  return withCheckDigits('7' + code + String.valueOf(10000 + seed).right(5) + '0001', 9);
}

// ---------- customers ----------
List<Customer__c> customers = new List<Customer__c>();
for (Integer i = 0; i < 200; i++) {
  Boolean isCompany = i >= 160;
  String name;
  String document;
  if (isCompany) {
    name = lastNames[Math.mod(i, lastNames.size())] + ' ' + companyTypes[Math.mod(i, companyTypes.size())] + ' Ltda';
    document = i < 180 ? numericCnpj(i) : alphanumericCnpj(i);
  } else {
    name = firstNames[Math.mod(i, firstNames.size())] + ' ' + lastNames[Math.mod(i * 3, lastNames.size())];
    document = cpf(i);
  }
  Customer__c customer = new Customer__c(
    Name = name,
    Document_Input__c = document,
    Email__c = 'cliente' + i + EMAIL_DOMAIN,
    Phone__c = Math.mod(i, 3) == 0 ? '1190000' + String.valueOf(1000 + i).right(4) : null,
    Address_Number__c = String.valueOf(10 + Math.mod(i * 37, 1990)),
    Address_Complement__c = Math.mod(i, 4) == 0 ? 'Sala ' + (1 + Math.mod(i, 30)) : null
  );
  if (i < 170) {
    customer.Postal_Code__c = postalCodes[Math.mod(i, postalCodes.size())];
  } else if (i < 180) {
    customer.Postal_Code__c = postalCodes[Math.mod(i, postalCodes.size())];
    customer.City__c = 'Cidade informada no arquivo';
  } else if (i < 190) {
    customer.Postal_Code__c = '99999-999';
    customer.City__c = 'Campinas';
  }
  customers.add(customer);
}

List<Database.SaveResult> results = Database.insert(customers, false);
Integer saved = 0;
for (Integer i = 0; i < results.size(); i++) {
  if (results[i].isSuccess()) {
    saved++;
  } else {
    System.debug(LoggingLevel.ERROR, 'SEED_FAIL ' + customers[i].Name + ': ' + results[i].getErrors()[0].getMessage());
  }
}
System.debug(LoggingLevel.ERROR, 'SEED_RESULT customers_built=' + customers.size() + ' customers_saved=' + saved);
