---
description: Gera uma arquitetura completa de integração REST de saída (Service, Wrappers tipados, Exceção customizada, HttpCalloutMock e Test Class).
---

Atue como um Salesforce Integration Architect sênior. Implemente uma integração REST de saída completa com base nos requisitos, endpoint/Named Credential e payload informados em `$ARGUMENTS`.

### 1. Estrutura de Arquivos a Criar

Gere os arquivos em `force-app/main/default/classes/` (incluindo os respectivos `.cls-meta.xml` alinhados à `sourceApiVersion` do `sfdx-project.json`):

- `<Servico>IntegrationService.cls`: Classe principal de orquestração do callout.
- `<Servico>Wrappers.cls`: Classes internas tipadas (`RequestWrapper`, `ResponseWrapper`, `ErrorWrapper`) para `JSON.serialize` / `JSON.deserialize`.
- `<Servico>IntegrationException.cls`: Exceção customizada para falhas de negócio ou HTTP.
- `<Servico>CalloutMock.cls`: Implementação de `HttpCalloutMock` configurável para simular sucesso (200/201), erro de cliente (400/401/404) e erro de servidor (500).
- `<Servico>IntegrationServiceTest.cls`: Classe de teste completa.

### 2. Padrões Obrigatórios de Integração e Resiliência

- **Autenticação:** Utilize exclusivamente Named Credentials no formato `callout:<Nome_Named_Credential>/<rota>`. Nunca insira tokens, chaves de API ou URLs hardcoded.
- **Timeouts e Headers:** Configure `req.setTimeout(120000)` (ou valor adequado), `Content-Type: application/json` e `Accept: application/json`.
- **Tratamento de Status HTTP:**
  - `200` / `201`: Desserialize o corpo com segurança e retorne o objeto tipado.
  - `400` / `422`: Extraia a mensagem de erro da API externa e lance `<Servico>IntegrationException`.
  - `401` / `403`: Lance exceção clara indicando falha de autenticação/permissão na Named Credential.
  - `500+` ou timeout (`System.CalloutException`): Capture e lance exceção padronizada com contexto para retry/log.
- **Governança:** Garanta que o método não execute DML antes do callout na mesma transação (evitando `System.CalloutException: You have uncommitted work pending`).

### 3. Cobertura de Testes

- Na classe `<Servico>IntegrationServiceTest`, teste obrigatoriamente:
  1. Cenário de sucesso (HTTP 200/201) validando os campos desserializados com `System.Assert.areEqual`.
  2. Cenário de erro de validação (HTTP 400) validando o lançamento da `<Servico>IntegrationException`.
  3. Cenário de indisponibilidade (HTTP 500) validando o tratamento de falha.

### 4. Validação CLI

- Após gerar os arquivos, execute `sf project deploy start --source-dir force-app/main/default/classes --dry-run` (ou direcionado às classes criadas) e corrija qualquer falha de compilação antes de encerrar.
