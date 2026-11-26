/**
 * HttpCalloutMock for the ViaCEP service (spec 002). Bodies copied from real responses
 * checked in task T01. Unknown postal codes answer like ViaCEP: {"erro": "true"}.
 */
@IsTest
public class ViaCepCalloutMock implements HttpCalloutMock {
  public enum Behavior {
    NORMAL,
    SERVER_ERROR,
    CALLOUT_EXCEPTION
  }

  public Behavior responseBehavior = Behavior.NORMAL;
  public Integer calls = 0;
  public List<String> endpoints = new List<String>();

  private static final Map<String, String> BODIES = new Map<String, String>{
    '01310100' => '{"cep": "01310-100", "logradouro": "Avenida Paulista", "complemento": "de 612 a 1510 - lado par", "bairro": "Bela Vista", "localidade": "São Paulo", "uf": "SP"}',
    '20040020' => '{"cep": "20040-020", "logradouro": "Praça Pio X", "complemento": "lado ímpar", "bairro": "Centro", "localidade": "Rio de Janeiro", "uf": "RJ"}',
    '88888888' => '{"erro": true}'
  };

  public ViaCepCalloutMock() {
    this(Behavior.NORMAL);
  }

  public ViaCepCalloutMock(Behavior responseBehavior) {
    this.responseBehavior = responseBehavior;
  }

  public HttpResponse respond(HttpRequest request) {
    calls++;
    endpoints.add(request.getEndpoint());
    if (responseBehavior == Behavior.CALLOUT_EXCEPTION) {
      throw new CalloutException('Read timed out');
    }
    HttpResponse response = new HttpResponse();
    response.setHeader('Content-Type', 'application/json');
    if (responseBehavior == Behavior.SERVER_ERROR) {
      response.setStatusCode(500);
      response.setBody('Internal Server Error');
      return response;
    }
    String postalCode = request.getEndpoint().substringBetween('/ws/', '/json');
    String body = BODIES.get(postalCode);
    response.setStatusCode(200);
    response.setBody(body == null ? '{"erro": "true"}' : body);
    return response;
  }
}
