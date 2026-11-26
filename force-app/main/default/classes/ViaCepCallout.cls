/**
 * ViaCEP postal code lookup through the ViaCep named credential (spec 002, REQ-003,
 * REQ-006, REQ-007, REQ-024, REQ-025). Used by the customer form and by the background
 * job. Response formats checked against the real service in task T01:
 * found = HTTP 200 with logradouro/bairro/localidade/uf; not found = HTTP 200 with
 * {"erro": "true"} (text; older versions used a boolean). Anything else is UNAVAILABLE.
 */
public with sharing class ViaCepCallout {
  /** Spec NFR: a lookup waits at most 120 s (also the platform maximum per callout). */
  public static final Integer TIMEOUT_MS = 120000;

  private static final String ENDPOINT = 'callout:ViaCep/ws/{0}/json/';
  private static final Integer HTTP_OK = 200;

  public enum Status {
    FOUND,
    NOT_FOUND,
    UNAVAILABLE
  }

  public class Result {
    public Status status;
    public String street;
    public String district;
    public String city;
    public String state;
  }

  /** postalCode: 8 digits, already validated by the caller. */
  public static Result lookup(String postalCode) {
    return lookup(postalCode, TIMEOUT_MS);
  }

  public static Result lookup(String postalCode, Integer timeoutMs) {
    Result result = new Result();
    result.status = Status.UNAVAILABLE;
    HttpRequest request = new HttpRequest();
    request.setEndpoint(
      String.format(ENDPOINT, new List<Object>{ postalCode })
    );
    request.setMethod('GET');
    request.setHeader('Accept', 'application/json');
    request.setTimeout(timeoutMs);
    try {
      HttpResponse response = new Http().send(request);
      if (response.getStatusCode() != HTTP_OK) {
        System.debug(
          LoggingLevel.WARN,
          'ViaCEP unavailable: HTTP ' + response.getStatusCode()
        );
        return result;
      }
      Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
        response.getBody()
      );
      if (
        body.containsKey('erro') && String.valueOf(body.get('erro')) == 'true'
      ) {
        result.status = Status.NOT_FOUND;
        return result;
      }
      result.status = Status.FOUND;
      result.street = textOrNull(body.get('logradouro'));
      result.district = textOrNull(body.get('bairro'));
      result.city = textOrNull(body.get('localidade'));
      result.state = textOrNull(body.get('uf'));
    } catch (CalloutException e) {
      // Timeout or network failure: the spec treats it as "service unavailable" (REQ-007, REQ-025).
      System.debug(LoggingLevel.WARN, 'ViaCEP unavailable: ' + e.getMessage());
    } catch (JSONException e) {
      System.debug(
        LoggingLevel.WARN,
        'ViaCEP returned an unreadable body: ' + e.getMessage()
      );
    } catch (TypeException e) {
      System.debug(
        LoggingLevel.WARN,
        'ViaCEP returned an unexpected body: ' + e.getMessage()
      );
    }
    return result;
  }

  /** CEPs that cover a whole city come with empty street and district: keep them blank. */
  private static String textOrNull(Object value) {
    String text = value == null ? null : String.valueOf(value);
    return String.isBlank(text) ? null : text;
  }
}
