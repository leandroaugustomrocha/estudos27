# Plan — 002 Cadastro de clientes com busca de CEP

> Status: Aprovado (2026-11-26)
> Spec: [spec.md](spec.md) (Aprovada em 2026-11-26)

## Constitution Check

| #   | Princípio             | Atende?                | Observação / exceção                                                                                                                                                                                                                                                                                                                                               |
| --- | --------------------- | ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1   | `with sharing`        | ⚠️ exceção justificada | Tudo `with sharing`, **exceto** `CustomerDocumentDuplicateChecker` (`without sharing`): a checagem de duplicidade (REQ-016) precisa enxergar documentos que o usuário não pode ver (REQ-022). Classe mínima, devolve só quais chaves já existem, nunca dados.                                                                                                      |
| 2   | Trigger Handler       | ✅                     | `CustomerTrigger` → `CustomerTriggerHandler` (estende o `TriggerHandler` do 001) → services.                                                                                                                                                                                                                                                                       |
| 3   | Sem SOQL/DML em loop  | ✅                     | Trigger: ≤ 3 SOQL e ≤ 2 DML por execução. Callouts só fora do trigger (controller e Queueable), com cache por CEP.                                                                                                                                                                                                                                                 |
| 4   | CRUD/FLS              | ⚠️ exceção justificada | `USER_MODE` em toda SOQL/DML, **exceto** (a) a consulta do `CustomerDocumentDuplicateChecker` (`WITH SYSTEM_MODE`, mesma justificativa do item 1) e (b) a gravação de `Customer_Document__c` pelo `CustomerDocumentService` (`AccessLevel.SYSTEM_MODE`): usuários só leem o documento, para não poderem gravá-lo sem validação (decisão do usuário em 2026-11-26). |
| 5   | Testes                | ✅                     | `@TestSetup`, `Assert` com mensagem, carga de 200, `System.runAs` por persona, `HttpCalloutMock`; Jest para o LWC.                                                                                                                                                                                                                                                 |
| 6   | Uma regra, um dono    | ✅                     | Validações do cliente só no Apex (sem validation rules nem Flow em `Customer__c`).                                                                                                                                                                                                                                                                                 |
| 7   | Reusar antes de criar | ✅                     | Reusa `TriggerHandler` do 001. `ZipCodeName` não serve (API americana, chave fixa).                                                                                                                                                                                                                                                                                |
| 8   | Sem valores mágicos   | ✅                     | Endpoint na Named Credential; tempo máximo e tamanho de lote em Custom Metadata; mensagens em Custom Labels.                                                                                                                                                                                                                                                       |
| 9   | Permission Set        | ✅                     | `Customer_User` e `Customer_Admin`.                                                                                                                                                                                                                                                                                                                                |
| 10  | Rastreabilidade       | ✅                     | Tabela de testes cobre os 27 ACs vigentes.                                                                                                                                                                                                                                                                                                                         |

## Decisões principais

### D-1. Onde fica o CPF/CNPJ (REQ-022)

A permissão de campo do Salesforce vale para o campo inteiro, não por registro: não dá
para o dono ver o CPF e outro usuário não. Por isso o documento fica num **objeto
separado, `Customer_Document__c`, com compartilhamento Private**: só o dono do registro
(quem cadastrou) e quem tem View All (administrador) o enxergam — em telas, listas,
relatórios, busca global e exportação, porque todos respeitam o compartilhamento.

- **Entrada do documento:** campo de passagem `Customer__c.Document_Input__c`. O usuário
  (ou o arquivo de importação) preenche; o trigger valida, grava em
  `Customer_Document__c` e **limpa o campo antes de salvar** — o valor nunca fica no
  cliente. Isso permite exigir o documento já na criação (REQ-017), inclusive em
  importações, sem expor o dado.
- **Duplicidade (REQ-016, REQ-021):** chave normalizada (`Document_Key__c`, só
  dígitos/letras, maiúsculas) com **índice único** no objeto de documento, mais uma
  checagem prévia pelo `CustomerDocumentDuplicateChecker` para devolver a mensagem da spec
  sem revelar qual cliente usa o documento.
- **Vida do documento:** dono do documento acompanha o dono do cliente; excluir o
  cliente exclui o documento; restaurar o cliente da Lixeira restaura o documento.
- Descartados: Master-Detail (herdaria o Public Read Only do cliente) e Shield/criptografia
  (não resolve visibilidade por registro e não está na Developer Edition).

### D-2. Busca de CEP

- **Serviço:** ViaCEP (`https://viacep.com.br/ws/{cep}/json/`), público e gratuito.
  Endpoint configurável pela **Named Credential `ViaCep`** (SecuredEndpoint) com a
  **External Credential `ViaCep` de protocolo `Custom`, sem parâmetros**, e um principal
  nomeado `ViaCepPrincipal`. Resultado da T01: o protocolo `NoAuthentication` não é
  suportado na org; o `Custom` passou no dry-run. Os Permission Sets dão acesso ao
  principal (`ViaCep-ViaCepPrincipal`), senão o callout é negado.
- **Cliente HTTP:** `ViaCepClient.lookup(cep)` devolve um resultado com situação
  `FOUND` / `NOT_FOUND` / `UNAVAILABLE`. Formatos conferidos na T01: encontrado = HTTP 200
  com `logradouro`, `bairro`, `localidade`, `uf`; `NOT_FOUND` = HTTP 200 com
  `{"erro": "true"}` (texto; aceitar também booleano); HTTP 400 = CEP malformado (não deve
  acontecer, o formato é validado antes); qualquer outro erro, exceção ou tempo esgotado =
  `UNAVAILABLE`. O campo `complemento` da resposta é ignorado (REQ-004).
- **Tempo máximo:** 120 s por busca (máximo permitido pela plataforma para um callout),
  em `Cep_Lookup_Setting__mdt.Timeout_Seconds__c`.

### D-3. Tela de cadastro (LWC) × outros caminhos

- **LWC `customerForm`** (criar e editar): busca automática ao completar 8 dígitos via
  `CustomerController.lookupCep` (`@AuraEnabled(cacheable=true)`), substitui logradouro,
  bairro, cidade e UF, trava cidade e UF (exceto com serviço fora do ar), mostra "buscando"
  (até 120 s), mensagens de erro em toast e campos.
- **Salvar:** `CustomerController.saveCustomer` (imperativo). Refaz a busca no servidor
  **antes** do DML (callout antes de DML é permitido): `NOT_FOUND` → erro e não salva
  (REQ-006); `FOUND` → cidade e UF do servidor prevalecem (REQ-018); `UNAVAILABLE` →
  aceita o endereço digitado (REQ-007). Marca a transação para o trigger **não** agendar
  a busca em segundo plano.
- **Onde o LWC aparece (REQ-026):** aba "Novo cliente" (LWC com target `lightning__Tab`)
  e ação "Editar cliente" (quick action `lightning__RecordAction`) na página do registro;
  o "Editar" padrão sai das ações da página (layout). Resultado da T02: a metadata não
  aceita LWC como substituto de New/Edit (só Aura, proibido pelas regras do projeto). O
  "Novo" padrão da lista continua e segue o REQ-008 (decisão do usuário).

### D-4. Busca em segundo plano (REQ-008, REQ-024, REQ-025)

- Trigger (after insert/update) agenda **um** Queueable `CustomerAddressLookupJob` com os
  Ids dos clientes criados ou com CEP alterado fora da tela, com CEP preenchido.
- O job processa até `Batch_Size__c` clientes (padrão 20) e encadeia o restante. Agrupa
  por CEP (um callout por CEP distinto). Limite da plataforma: 120 s de callout somados
  por transação — o tempo de cada busca é o menor entre 120 s e o que ainda resta; o que
  não couber é reenfileirado.
- Relê cada cliente; se o CEP mudou desde o agendamento, ignora. `FOUND` → preenche só
  logradouro/bairro/cidade/UF vazios. `NOT_FOUND` → apaga o CEP e grava a observação.
  `UNAVAILABLE` → não altera nada.
- DML em `USER_MODE` como o usuário que importou (dono dos registros). A atualização do
  job não reagenda busca (só muda CEP para vazio ou campos de endereço).

### D-5. Validações no trigger (REQ-002, 005, 012–017, 020, 021, 023)

`CustomerService` em before insert/update, por registro, com mensagens em Custom Labels;
sucesso parcial preservado (`addError`). Normaliza e formata CEP, telefone e documento;
define o tipo de pessoa. CPF: módulo 11. CNPJ: cálculo oficial com caracteres
alfanuméricos (valor = código ASCII − 48; dígitos verificadores numéricos). Documento
repetido no mesmo lote: o primeiro vence (como no 001).

## Modelo de dados

### `Customer__c` ("Cliente") — OWD **Public Read Only**

| Campo                   | Tipo                       | Obrigatório  | Observação                                                              |
| ----------------------- | -------------------------- | ------------ | ----------------------------------------------------------------------- |
| `Name`                  | Text(80)                   | Sim          | Nome                                                                    |
| `Email__c`              | Text(80)                   | Não          | Texto (não `Email`) para a mensagem da spec (REQ-012)                   |
| `Phone__c`              | Text(20)                   | Não          | Guardado `(00) 00000-0000`                                              |
| `Person_Type__c`        | Picklist restrita          | —            | `Individual` ("Física") / `Company` ("Jurídica"); só o trigger preenche |
| `Document_Input__c`     | Text(18)                   | Não no campo | Campo de passagem; sempre vazio depois de salvar (D-1)                  |
| `Postal_Code__c`        | Text(9)                    | Não          | `00000-000`                                                             |
| `Street__c`             | Text(255)                  | Não          | Logradouro                                                              |
| `Address_Number__c`     | Text(20)                   | Não          | Número                                                                  |
| `Address_Complement__c` | Text(100)                  | Não          | Complemento                                                             |
| `District__c`           | Text(100)                  | Não          | Bairro                                                                  |
| `City__c`               | Text(100)                  | Não          | Cidade                                                                  |
| `State__c`              | Picklist restrita (27 UFs) | Não          | UF                                                                      |
| `Address_Note__c`       | Text(255)                  | Não          | Observação do REQ-024                                                   |

### `Customer_Document__c` ("Documento do cliente") — OWD **Private**

| Campo                | Tipo                                            | Observação                                          |
| -------------------- | ----------------------------------------------- | --------------------------------------------------- |
| `Customer__c`        | Lookup(`Customer__c`), não obrigatório, SetNull | Lookup (não Master-Detail) para manter o Private    |
| `Document_Number__c` | Text(18)                                        | Formatado (`000.000.000-00` / `AA.AAA.AAA/AAAA-00`) |
| `Document_Key__c`    | Text(14), **Unique**, External ID               | Chave normalizada para duplicidade                  |

### `Cep_Lookup_Setting__mdt` — registro `Default`

`Timeout_Seconds__c` = 120, `Batch_Size__c` = 20.

## Segurança

- **Customer_User:** `Customer__c` Read/Create/Edit/Delete (compartilhamento limita edição
  às próprias); FLS de edição nos campos do cliente, exceto `Person_Type__c` (leitura);
  `Customer_Document__c` **somente Read**, com leitura só em `Document_Number__c` e
  `Customer__c` (o Private limita aos próprios); acesso à classe `CustomerController`;
  acesso ao principal `ViaCep-ViaCepPrincipal` da External Credential.
- **Customer_Admin:** igual + View All/Modify All em `Customer__c` e **View All** (só
  leitura) em `Customer_Document__c` (REQ-010, REQ-022).
- **Gravação do documento (decisão do usuário em 2026-11-26):** ninguém edita
  `Customer_Document__c` diretamente. Só o `CustomerDocumentService`, chamado pelo trigger
  depois de validar, cria, altera, exclui e restaura documentos, em
  `AccessLevel.SYSTEM_MODE`. Assim não há como gravar um documento sem passar pela
  validação e pela checagem de duplicidade.
- Usuário sem Permission Set: sem CRUD → negado (REQ-011).
- `@AuraEnabled`: valida entrada (CEP só dígitos, 8 caracteres) antes do callout; erros com
  `AuraHandledException` e texto seguro; `cacheable=true` só em `lookupCep`.
- Nenhum dado além do CEP sai da org (NFR).

## Componentes (inventário de metadata)

| Tipo                                 | Nome                                                                                                                                                                                                                                                         | Ação  | REQ                              |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----- | -------------------------------- |
| CustomObject                         | `Customer__c` + 12 campos                                                                                                                                                                                                                                    | criar | 001, 002, 012–014, 018, 023, 024 |
| CustomObject                         | `Customer_Document__c` + 3 campos                                                                                                                                                                                                                            | criar | 014–016, 022                     |
| CustomObject (mdt)                   | `Cep_Lookup_Setting__mdt` + registro `Default`                                                                                                                                                                                                               | criar | NFR desempenho                   |
| ExternalCredential + NamedCredential | `ViaCep`                                                                                                                                                                                                                                                     | criar | 003, NFR serviço                 |
| CustomLabels                         | ~12 labels `Customer_*`                                                                                                                                                                                                                                      | criar | mensagens                        |
| PermissionSet                        | `Customer_User`, `Customer_Admin`                                                                                                                                                                                                                            | criar | 009–011, 022                     |
| CustomTab, Layout, ListView          | `Customer__c` (+ "Todos os clientes")                                                                                                                                                                                                                        | criar | 001, 009                         |
| ApexTrigger                          | `CustomerTrigger`                                                                                                                                                                                                                                            | criar | 008, 020–022                     |
| ApexClass                            | `CustomerTriggerHandler`, `CustomerService`, `DocumentValidator`, `CustomerDocumentService`, `CustomerDocumentDuplicateChecker` (without sharing), `ViaCepClient`, `CepLookupSettings`, `CustomerAddressLookupJob`, `CustomerController`, `CustomerSelector` | criar | todos                            |
| ApexClass (teste)                    | `CustomerTestDataFactory`, `DocumentValidatorTest`, `CustomerServiceTest`, `CustomerDocumentServiceTest`, `ViaCepClientTest`, `CustomerAddressLookupJobTest`, `CustomerControllerTest`, `CustomerSecurityTest`, `ViaCepHttpMock`                             | criar | todos                            |
| LWC                                  | `customerForm` (+ Jest)                                                                                                                                                                                                                                      | criar | 003–007, 018, 019                |
| Aba / ação                           | aba "Novo cliente", ação "Editar cliente"                                                                                                                                                                                                                    | criar | 003                              |

## Orçamento de governor limits

| Cenário                                  | SOQL                                     | DML                       | Callouts              | Observação                                       |
| ---------------------------------------- | ---------------------------------------- | ------------------------- | --------------------- | ------------------------------------------------ |
| Trigger, 200 clientes                    | ≤ 3 (duplicidade, documentos existentes) | ≤ 2 (documentos; enqueue) | 0                     | CPU: validação de documento é aritmética simples |
| `saveCustomer` (tela)                    | ≤ 4                                      | ≤ 2                       | 1                     | Callout antes do DML                             |
| `CustomerAddressLookupJob` (20 clientes) | 1                                        | 1                         | ≤ 20 (CEPs distintos) | Soma dos timeouts ≤ 120 s; o resto encadeia      |

## Plano de testes (rastreável)

| AC                             | Classe de teste                                | Tipo                                                                             |
| ------------------------------ | ---------------------------------------------- | -------------------------------------------------------------------------------- |
| AC-001, 002, 012–017, 023, 026 | `CustomerServiceTest`                          | positivo, negativo, bulk 200                                                     |
| AC-014, 015 (cálculo)          | `DocumentValidatorTest`                        | CPF e CNPJ numérico/alfanumérico, casos inválidos                                |
| AC-003, 005, 006, 007          | `ViaCepClientTest` + `CustomerControllerTest`  | mock encontrado / `erro` / 500 / exceção de timeout                              |
| AC-004, 018, 019, 020          | Jest `customerForm` + `CustomerControllerTest` | busca automática, sobrescrita, travas, troca de CEP                              |
| AC-021, 027, 028               | `CustomerAddressLookupJobTest`                 | só campos vazios; CEP apagado + observação; serviço fora                         |
| AC-022                         | `CustomerServiceTest`                          | bulk 200 com sucesso parcial                                                     |
| AC-008–011, 025                | `CustomerSecurityTest`                         | runAs: visibilidade do cliente e do documento, dono × outro × admin × sem acesso |

Meta: ≥ 90% por classe nova; Jest para todo comportamento do LWC.

## Deploy e rollback

Deploy escopado (lista exata no `tasks.md`), `--dry-run` com os testes antes, deploy real
só com confirmação. Rollback: tudo é novo; remover com `destructiveChanges.xml` só com
confirmação, ou retirar os Permission Sets.

## Riscos

| Risco                                                                                      | Prob.   | Mitigação                                                                                                                         |
| ------------------------------------------------------------------------------------------ | ------- | --------------------------------------------------------------------------------------------------------------------------------- |
| External Credential sem autenticação não suportada                                         | Ocorreu | Resolvido na T01: External Credential `Custom` sem parâmetros + principal                                                         |
| LWC não substitui New/Edit padrão → cliente salvo pelo "Novo" padrão não tem busca na hora | Ocorreu | Confirmado na T02; "Editar" padrão removido da página; "Novo" padrão segue o REQ-008 (REQ-026, decisão do usuário)                |
| Corrida na duplicidade: dois usuários salvam o mesmo documento ao mesmo tempo              | Baixa   | Índice único barra o segundo; a mensagem da plataforma nesse caso é genérica e pode citar o Id do registro — aceito como residual |
| Mapear documento entre before e after insert depende da ordem do `Trigger.new`             | Baixa   | Ordem é garantida pela plataforma; teste de sucesso parcial (199/1) cobre a reexecução                                            |
| ViaCEP lento/limitado em importações grandes                                               | Média   | Um callout por CEP distinto, lotes pequenos, falha = `UNAVAILABLE` (REQ-025)                                                      |
| Vetor oficial do CNPJ alfanumérico                                                         | Baixa   | T03 confere o algoritmo contra exemplos publicados antes de escrever o validador                                                  |
| `Document_Input__c` aparecer em logs de depuração                                          | Baixa   | Logs são só do admin; campo limpo antes de gravar                                                                                 |
