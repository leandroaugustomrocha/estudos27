/**
 * CPF/CNPJ check digit validation and formatting (spec 002, REQ-014, REQ-015).
 * Pure functions, no data access. CNPJ accepts the alphanumeric format in force since
 * July 2026: character value = ASCII code - 48, modulus 11, weights 2-9 from right to left
 * (official example 12.ABC.345/01DE-35, checked in task T03). The same rule gives the
 * classic result for numeric CNPJs and, with weights up to 11, for CPFs.
 */
public with sharing class DocumentValidator {
  public static final String INDIVIDUAL = 'Individual';
  public static final String COMPANY = 'Company';

  private static final Integer CPF_LENGTH = 11;
  private static final Integer CNPJ_LENGTH = 14;
  private static final Integer CPF_MAX_WEIGHT = 11;
  private static final Integer CNPJ_MAX_WEIGHT = 9;
  private static final Integer ASCII_ZERO = 48;
  private static final Pattern CNPJ_PATTERN = Pattern.compile(
    '[0-9A-Z]{12}[0-9]{2}'
  );

  /** Digits and uppercase letters only ("529.982.247-25" -> "52998224725"). */
  public static String normalize(String raw) {
    if (String.isBlank(raw)) {
      return null;
    }
    return raw.toUpperCase().replaceAll('[^0-9A-Z]', '');
  }

  /** True for a CPF (11 digits) or CNPJ (14 characters) whose check digits match. */
  public static Boolean isValid(String key) {
    if (String.isBlank(key) || allCharactersEqual(key)) {
      return false;
    }
    if (key.length() == CPF_LENGTH) {
      return key.isNumeric() && hasValidCheckDigits(key, CPF_MAX_WEIGHT);
    }
    if (key.length() == CNPJ_LENGTH) {
      return CNPJ_PATTERN.matcher(key).matches() &&
        hasValidCheckDigits(key, CNPJ_MAX_WEIGHT);
    }
    return false;
  }

  /** "000.000.000-00" for CPF, "AA.AAA.AAA/AAAA-00" for CNPJ; other input is returned as is. */
  public static String format(String key) {
    if (key == null) {
      return null;
    }
    if (key.length() == CPF_LENGTH) {
      return key.substring(0, 3) +
        '.' +
        key.substring(3, 6) +
        '.' +
        key.substring(6, 9) +
        '-' +
        key.substring(9);
    }
    if (key.length() == CNPJ_LENGTH) {
      return key.substring(0, 2) +
        '.' +
        key.substring(2, 5) +
        '.' +
        key.substring(5, 8) +
        '/' +
        key.substring(8, 12) +
        '-' +
        key.substring(12);
    }
    return key;
  }

  /** INDIVIDUAL for CPF, COMPANY for CNPJ, null otherwise. */
  public static String personType(String key) {
    if (key == null) {
      return null;
    }
    if (key.length() == CPF_LENGTH) {
      return INDIVIDUAL;
    }
    return key.length() == CNPJ_LENGTH ? COMPANY : null;
  }

  private static Boolean hasValidCheckDigits(String key, Integer maxWeight) {
    String base = key.left(key.length() - 2);
    String first = checkDigit(base, maxWeight);
    String second = checkDigit(base + first, maxWeight);
    return key.right(2) == first + second;
  }

  /** Modulus 11 over (ASCII - 48) values, weights from 2 to maxWeight, right to left, cycling. */
  private static String checkDigit(String characters, Integer maxWeight) {
    Integer total = 0;
    Integer weight = 2;
    for (Integer i = characters.length() - 1; i >= 0; i--) {
      total += (characters.charAt(i) - ASCII_ZERO) * weight;
      weight = weight == maxWeight ? 2 : weight + 1;
    }
    Integer remainder = Math.mod(total, 11);
    return String.valueOf(remainder < 2 ? 0 : 11 - remainder);
  }

  private static Boolean allCharactersEqual(String key) {
    return key.replace(key.left(1), '').length() == 0;
  }
}
