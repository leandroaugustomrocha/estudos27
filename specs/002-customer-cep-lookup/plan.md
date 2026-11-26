# Plan — 002 Cadastro de clientes com busca de CEP

> Status: Aprovado (2026-11-26) — revisado pela Constituição nova do `AGENTS.md`
> Spec: [spec.md](spec.md) (Aprovada; REQ-027 e REQ-028 acrescentados em 2026-11-26)

## Mudanças desta revisão

| O que mudou                                                                                    | Motivo (Constituição do `AGENTS.md`)                                                                                               |
| ---------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `Cep_Lookup_Setting__mdt` e `CepLookupSettings` removidos; 120 s e lote de 20 viram constantes | Princípio 8: Custom Metadata só para o que a spec pede como configurável — a spec só pede o endereço do serviço (Named Credential) |
| `CustomerService` + `CustomerDocumentService` → um só `CustomerService`                        | Princípio 2: service só com reúso ou mais de um objeto; um service basta para os dois objetos                                      |
| `CustomerSelector` removido; consulta de clientes fica no job                                  | Princípio 2: selector só quando a mesma query é usada em mais de um lugar                                                          |
| `ViaCepClient` → `ViaCepCallout`                                                               | Padrão do `CLAUDE.md` (`*Callout`); mantido como classe própria porque é usado pela tela e pelo job                                |
| "Documento acompanha a troca de dono do cliente" removido                                      | Disciplina de escopo: não está na spec; REQ-022 fala em "quem cadastrou"                                                           |
| Exclusão e restauração do documento agora vêm da spec (REQ-027, REQ-028)                       | Disciplina de escopo: era suposição; virou requisito por decisão do usuário                                                        |

## Constitution Check

| #   | Princípio                            | Atende?                | Observação / exceção                                                                                                                                                                                                                                                                                                                  |
| --- | ------------------------------------ | ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | `with sharing`                       | ⚠️ exceção justificada | Tudo `with sharing`, exceto `CustomerDocumentDuplicateChecker` (`without sharing`): a checagem de duplicidade (REQ-016, 021, 028) precisa enxergar documentos que o usuário não pode ver (REQ-022). Classe mínima: recebe chaves e devolve só as que já existem.                                                                      |
| 2   | Trigger Handler, camadas sob demanda | ✅                     | `CustomerTrigger` → `CustomerTriggerHandler` (estende o `TriggerHandler` do 001, com bypass) → `CustomerService` (justificado: grava em `Customer__c` e `Customer_Document__c`). Sem selector: nenhuma query se repete.                                                                                                               |
| 3   | Sem SOQL/DML em loop                 | ✅                     | Trigger: ≤ 3 SOQL e ≤ 3 DML por execução. Callouts só no controller e no job, um por CEP distinto.                                                                                                                                                                                                                                    |
| 4   | CRUD/FLS                             | ⚠️ exceção justificada | `USER_MODE` em toda SOQL/DML, exceto (a) a consulta do verificador de duplicidade (`WITH SYSTEM_MODE`, mesmo motivo do item 1) e (b) a gravação, exclusão e restauração de `Customer_Document__c` pelo `CustomerService` (`SYSTEM_MODE`): usuários só leem o documento, para não poderem gravá-lo sem validação (decisão do usuário). |
| 5   | Testes                               | ✅                     | `@TestSetup`/`CustomerTestDataFactory`, `Assert` com mensagem, `startTest/stopTest`, positivo, negativo, bulk 200 e `System.runAs` nos ACs de permissão; `HttpCalloutMock`; Jest no LWC.                                                                                                                                              |
| 6   | Uma regra, um dono                   | ✅                     | Validações do cliente só no Apex; nenhuma validation rule ou Flow em `Customer__c`.                                                                                                                                                                                                                                                   |
| 7   | Reusar antes de criar                | ✅                     | Reusa `TriggerHandler` do 001. `ZipCodeName` não serve (API americana, chave fixa).                                                                                                                                                                                                                                                   |
| 8   | Sem valores mágicos                  | ✅                     | Textos em Custom Labels; endereço do serviço na Named Credential; nenhum Custom Metadata (a spec não pede outra configuração). Constantes nomeadas e comentadas: `TIMEOUT_MS = 120000` (NFR da spec) e `BATCH_SIZE = 20` (limite de 120 s de callout por transação).                                                                  |
| 9   | Permission Set                       | ✅                     | `Customer_User` e `Customer_Admin`.                                                                                                                                                                                                                                                                                                   |
| 10  | Rastreabilidade                      | ✅                     | Tabela de testes cobre os 31 ACs vigentes.                                                                                                                                                                                                                                                                                            |

## Decisões

### D-1. Onde fica o CPF/CNPJ (REQ-022)

A permissão de campo vale para o campo inteiro, não por registro. Por isso o documento
fica em **`Customer_Document__c`, com compartilhamento Private**: só o dono do registro
(quem cadastrou) e quem tem View All (administrador) o veem — em telas, listas,
relatórios, busca global e exportação. Descartados: Master-Detail (herdaria o Public
Read Only do cliente) e criptografia (não resolve visibilidade por registro).

- **Entrada:** campo de passagem `Customer__c.Document_Input__c`. O trigger valida, guarda
  o valor em memória, **limpa o campo** no before e grava o documento no after. Permite
  exigir o documento na criação (REQ-017), inclusive em importações e no "Novo" padrão.
- **Duplicidade (REQ-016, 021, 028):** chave normalizada `Document_Key__c` com índice
  único, mais checagem prévia pelo `CustomerDocumentDuplicateChecker` para devolver a
  mensagem da spec sem revelar qual cliente usa o documento.
- **Exclusão (REQ-027):** before delete do cliente exclui o documento (`SYSTEM_MODE`).
- **Restauração (REQ-028):** after undelete do cliente busca o documento na Lixeira
  (`ALL ROWS`), confere duplicidade e restaura; se houver duplicidade, `addError` no
  cliente desfaz a restauração.

### D-2. Busca de CEP

- **Serviço:** ViaCEP (`https://viacep.com.br/ws/{cep}/json/`). Endereço na **Named
  Credential `ViaCep`** com **External Credential `Custom` sem parâmetros** e principal
  `ViaCepPrincipal` (T01: `NoAuthentication` não é suportado na org). Os Permission Sets
  dão acesso ao principal.
- **`ViaCepCallout.lookup(cep)`** devolve `FOUND` / `NOT_FOUND` / `UNAVAILABLE`. Formatos
  conferidos na T01: encontrado = HTTP 200 com `logradouro`, `bairro`, `localidade`, `uf`;
  não encontrado = HTTP 200 com `{"erro": "true"}` (aceitar também booleano); qualquer
  outro status, exceção ou tempo esgotado = `UNAVAILABLE`. `complemento` da resposta é
  ignorado (REQ-004).
- **Tempo máximo:** `TIMEOUT_MS = 120000` (NFR; máximo da plataforma por callout).

### D-3. Tela de cadastro (REQ-003 a 007, 018, 019, 026)

- **LWC `customerForm`** (criar e editar): busca automática ao completar 8 dígitos via
  `CustomerController.lookupCep` (`@AuraEnabled`, **sem cache**: o resultado de um serviço externo muda, e o "tente de novo" do REQ-007 precisa consultar de verdade); substitui logradouro,
  bairro, cidade e UF; trava cidade e UF, exceto com o serviço fora do ar; mostra
  "buscando"; erros em toast e nos campos. Mostra o CPF/CNPJ só se
  `CustomerController.getDocument` o devolver (consulta em `USER_MODE`: só dono e admin).
- **Salvar:** `CustomerController.saveCustomer` refaz a busca **antes** do DML: `NOT_FOUND`
  → erro e não salva (REQ-006); `FOUND` → cidade e UF do servidor prevalecem (REQ-018);
  `UNAVAILABLE` → aceita o endereço digitado (REQ-007). Liga um sinal estático para o
  trigger não agendar a busca em segundo plano.
- **Onde aparece (REQ-026):** aba "Novo cliente" (`lightning__Tab`) e quick action "Editar
  cliente" (`lightning__RecordAction`); o "Editar" padrão sai das ações da página. O
  "Novo" padrão da lista segue o REQ-008 (T02: LWC não substitui New/Edit).

### D-4. Busca em segundo plano (REQ-008, 024, 025)

> Revisado em 2026-11-26 (revisão de código, decisão do usuário): o Queueable encadeado
> foi trocado por **Batch Apex**. Na Developer Edition só se encadeiam 5 Queueables;
> com lotes de 20, uma importação de 200 clientes parava na 5ª execução.

- After insert/update dispara **um** Batch `CustomerAddressLookupBatch`
  (`Database.Batchable`, `Database.AllowsCallouts`, `Database.Stateful`) com os Ids dos
  clientes criados, ou com CEP alterado, fora da tela e com CEP preenchido. A plataforma
  divide em blocos de `BATCH_SIZE = 20`, e cada bloco tem seu próprio limite de 120 s de
  callout — não há encadeamento.
- Em cada bloco: um callout por CEP distinto; o tempo de cada um é o menor entre 120 s e
  o que resta do bloco. Se o tempo acabar, ou se a busca for cortada pelo tempo restante
  (timeout menor que 120 s), o cliente é **adiado**, e não tratado como "fora do ar". No
  `finish()`, os adiados ganham um novo Batch (até 3 tentativas no total).
- A consulta usa o CEP atual do cliente (`USER_MODE`). Se o CEP mudar, a própria mudança
  dispara outra busca. `FOUND` → preenche só logradouro/bairro/cidade/UF vazios;
  `NOT_FOUND` → apaga o CEP e grava a observação (Custom Label); `UNAVAILABLE` → nada muda.
- DML em `USER_MODE` como quem importou; falhas de gravação vão para o log. A atualização
  não dispara nova busca. Se a gravação já acontece dentro de um Batch (de onde não se
  inicia outro), a busca é pulada com registro no log.

### D-5. Validações (REQ-002, 005, 012–017, 020, 021, 023)

No `CustomerService`, before insert/update, por registro, com Custom Labels e
`addError` (sucesso parcial preservado). Normaliza e formata CEP, telefone e documento;
define o tipo de pessoa. O cálculo do CPF/CNPJ fica em `DocumentValidator`: função pura,
sem acesso a dados, testada isoladamente com os vetores conferidos na T03 (não é service
nem selector). Documento repetido no lote: o primeiro vence.

## Modelo de dados

### `Customer__c` ("Cliente") — OWD Public Read Only

| Campo                                        | Tipo                       | Observação                                                          |
| -------------------------------------------- | -------------------------- | ------------------------------------------------------------------- |
| `Name`                                       | Text(80), obrigatório      | Nome                                                                |
| `Email__c`                                   | Text(80)                   | Texto para a mensagem da spec (REQ-012)                             |
| `Phone__c`                                   | Text(20)                   | `(00) 0000-0000` / `(00) 00000-0000`                                |
| `Person_Type__c`                             | Picklist restrita          | `Individual`/`Company` ("Física"/"Jurídica"); só o trigger preenche |
| `Document_Input__c`                          | Text(18)                   | Campo de passagem; sempre vazio depois de salvar                    |
| `Postal_Code__c`                             | Text(9)                    | `00000-000`; pode ficar vazio (REQ-023)                             |
| `Street__c`, `District__c`, `City__c`        | Text(255/100/100)          | Preenchidos pela busca                                              |
| `Address_Number__c`, `Address_Complement__c` | Text(20/100)               | Sempre do usuário                                                   |
| `State__c`                                   | Picklist restrita (27 UFs) | UF                                                                  |
| `Address_Note__c`                            | Text(255)                  | Observação do REQ-024                                               |

### `Customer_Document__c` ("Documento do cliente") — OWD Private

| Campo                | Tipo                         | Observação                   |
| -------------------- | ---------------------------- | ---------------------------- |
| `Customer__c`        | Lookup, SetNull              | Lookup para manter o Private |
| `Document_Number__c` | Text(18)                     | Formatado                    |
| `Document_Key__c`    | Text(14), único, External ID | Chave normalizada            |

## Segurança

- **Customer_User:** `Customer__c` CRED (o compartilhamento limita edição e exclusão aos
  próprios); FLS de edição nos campos do cliente, exceto `Person_Type__c` (leitura);
  `Customer_Document__c` só Read (`Document_Number__c`, `Customer__c`); classe
  `CustomerController`; principal `ViaCep-ViaCepPrincipal`.
- **Customer_Admin:** igual + View All/Modify All em `Customer__c` e **Modify All** em
  `Customer_Document__c` com permissão de campo **só leitura** (decisão do usuário em
  2026-11-26, na Fase C): o `SYSTEM_MODE` ignora permissões de objeto e campo, mas não o
  compartilhamento da classe `with sharing`; sem Modify All, o trigger não conseguia
  excluir, restaurar ou trocar o documento de clientes de outros quando o admin age. Com
  campo só leitura, o admin não altera o número direto, mas pode excluir um registro de
  documento direto (ver Riscos).
- Usuário sem Permission Set: negado (REQ-011).
- `@AuraEnabled`: valida o CEP (8 dígitos) antes do callout; `AuraHandledException` com
  texto seguro; `cacheable=true` só em `getDocument` (revisão de código: `lookupCep` sem cache).
- Nenhum dado além do CEP sai da org.

## Componentes (inventário)

| Tipo                                 | Nome                                                                                                                                                                                                    | Ação                                                   | REQ                                   |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------ | ------------------------------------- |
| CustomObject                         | `Customer__c` + 12 campos, aba, layout, list view                                                                                                                                                       | criar (feito na Fase A)                                | 001, 002, 009, 012–014, 018, 023, 024 |
| CustomObject                         | `Customer_Document__c` + 3 campos                                                                                                                                                                       | criar (feito)                                          | 014–016, 022                          |
| ExternalCredential + NamedCredential | `ViaCep`                                                                                                                                                                                                | criar (feito)                                          | 003                                   |
| CustomLabels                         | 9 labels `Customer_*` (+ as do LWC na T25)                                                                                                                                                              | criar (feito)                                          | mensagens                             |
| PermissionSet                        | `Customer_User`, `Customer_Admin`                                                                                                                                                                       | criar (feito; acesso à classe na T24)                  | 009–011, 022                          |
| CustomObject (mdt)                   | `Cep_Lookup_Setting__mdt` + registro `Default`                                                                                                                                                          | **remover dos arquivos locais** (nunca foi implantado) | —                                     |
| ApexTrigger                          | `CustomerTrigger`                                                                                                                                                                                       | criar                                                  | 008, 017, 020–022, 027, 028           |
| ApexClass                            | `CustomerTriggerHandler`, `CustomerService`, `DocumentValidator`, `CustomerDocumentDuplicateChecker` (without sharing), `ViaCepCallout`, `CustomerAddressLookupBatch`, `CustomerController`             | criar                                                  | todos                                 |
| ApexClass (teste)                    | `CustomerTestDataFactory`, `ViaCepCalloutMock`, `DocumentValidatorTest`, `CustomerServiceTest`, `ViaCepCalloutTest`, `CustomerAddressLookupBatchTest`, `CustomerControllerTest`, `CustomerSecurityTest` | criar                                                  | todos                                 |
| LWC                                  | `customerForm` (+ Jest), aba "Novo cliente", quick action "Editar cliente", layout sem "Editar" padrão                                                                                                  | criar/alterar                                          | 003–007, 018, 019, 026                |

## Orçamento de governor limits

| Cenário               | SOQL                                                          | DML                                             | Callouts                            |
| --------------------- | ------------------------------------------------------------- | ----------------------------------------------- | ----------------------------------- |
| Trigger, 200 clientes | ≤ 3 (duplicidade; documentos existentes; Lixeira no undelete) | ≤ 3 (documentos; exclusão/restauração; enqueue) | 0                                   |
| `saveCustomer`        | ≤ 4                                                           | ≤ 2                                             | 1, antes do DML                     |
| Batch, bloco de 20    | 1                                                             | 1                                               | ≤ 20 (CEPs distintos), soma ≤ 120 s |

## Plano de testes (rastreável)

| AC                                  | Classe                                         | Tipo                                                                    |
| ----------------------------------- | ---------------------------------------------- | ----------------------------------------------------------------------- |
| AC-001, 002, 012–017, 022, 023, 026 | `CustomerServiceTest`                          | positivo, negativo, bulk 200 com sucesso parcial                        |
| AC-031, 032                         | `CustomerServiceTest`                          | exclusão libera o documento; restauração com e sem duplicidade          |
| AC-014, 015 (cálculo)               | `DocumentValidatorTest`                        | CPF e CNPJ numérico/alfanumérico (vetor oficial), inválidos             |
| AC-003, 005, 006, 007               | `ViaCepCalloutTest` + `CustomerControllerTest` | encontrado / `erro` / 500 / exceção                                     |
| AC-004, 018, 019, 020, 029          | Jest `customerForm` + `CustomerControllerTest` | busca automática, sobrescrita, travas, troca de CEP, tela por aba/ação  |
| AC-021, 027, 028, 030               | `CustomerAddressLookupBatchTest`               | só campos vazios; CEP apagado + observação; serviço fora; "Novo" padrão |
| AC-008–011, 025                     | `CustomerSecurityTest`                         | runAs: cliente e documento para dono × outro × admin × sem acesso       |

Meta: ≥ 90% por classe nova. `CustomerTriggerHandler` e `CustomerDocumentDuplicateChecker`
são cobertos pelos testes de comportamento (mesmo desvio documentado no 001).

## Deploy e rollback

Deploy escopado (lista no `tasks.md`), `--dry-run` com testes, deploy real só com
confirmação. Rollback: tudo é novo; remover com `destructiveChanges.xml` só com
confirmação, ou retirar os Permission Sets.

## Riscos

| Risco                                                                                           | Prob.   | Mitigação                                                                                                           |
| ----------------------------------------------------------------------------------------------- | ------- | ------------------------------------------------------------------------------------------------------------------- |
| External Credential sem autenticação                                                            | Ocorreu | Resolvido na T01 com `Custom` + principal                                                                           |
| "Novo" padrão sem busca na hora                                                                 | Ocorreu | REQ-026: segue o REQ-008 (decisão do usuário)                                                                       |
| Corrida na duplicidade (dois salvamentos simultâneos)                                           | Baixa   | Índice único barra; mensagem da plataforma pode citar o Id — residual aceito                                        |
| Admin exclui um registro de documento direto (API/Data Loader), deixando o cliente sem CPF/CNPJ | Baixa   | Aceito pelo usuário junto com o Modify All; o número em si não pode ser alterado direto (campo só leitura, testado) |
| Documento entre before e after insert depende da ordem do `Trigger.new`                         | Baixa   | Ordem garantida pela plataforma; teste de sucesso parcial cobre a reexecução                                        |
| Limite de 5 Queueables encadeados na Developer Edition                                          | Ocorreu | Achado da revisão de código; resolvido com Batch Apex (D-4)                                                         |
| Busca em segundo plano adiada várias vezes (serviço lento)                                      | Baixa   | Até 3 tentativas; depois o cliente fica como importado (REQ-025)                                                    |
| ViaCEP lento em importações grandes                                                             | Média   | Um callout por CEP distinto, lotes de 20, falha = `UNAVAILABLE`                                                     |
| `Document_Input__c` em logs de depuração                                                        | Baixa   | Logs só do admin; campo limpo antes de gravar                                                                       |
