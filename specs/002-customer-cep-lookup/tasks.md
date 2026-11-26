# Tasks — 002 Cadastro de clientes com busca de CEP

> Spec: [spec.md](spec.md) · Plan: [plan.md](plan.md)
> Verificação padrão das tasks de código: deploy `--dry-run` escopado com
> `--test-level RunSpecifiedTests`; para o LWC, `npm run lint && npm test`.

## Fase 0 — Verificações do plan

- [x] T01 [REQ-003] External Credential "sem autenticação" + Named Credential `ViaCep`:
      dry-run; conferir o formato real das respostas do ViaCEP (encontrado, `erro`, 400)
      → 2026-11-26: protocolo `NoAuthentication` **não suportado** na org; External
      Credential `Custom` sem parâmetros + principal passou no dry-run. ViaCEP: encontrado =
      HTTP 200 com `logradouro/bairro/localidade/uf`; não encontrado = HTTP 200
      `{"erro": "true"}` (texto); CEP malformado = HTTP 400 (HTML)
- [x] T02 [REQ-003] LWC pode substituir os botões padrão New/Edit? (dry-run de um override)
      → 2026-11-26: **não** (`LightningWebComponent` não existe no enum; `LightningComponent`
      só aceita Aura). Decisão do usuário: aba + ação com o LWC, "Editar" padrão removido,
      "Novo" padrão segue o REQ-008. Spec: REQ-026, AC-029, AC-030
- [x] T03 [REQ-014, 015] Conferir o cálculo do CNPJ alfanumérico contra exemplo publicado
      → 2026-11-26: exemplo oficial da Receita `12.ABC.345/01DE-35` (valor = ASCII − 48,
      módulo 11, pesos 2–9 da direita para a esquerda) conferido por script; mesmo
      algoritmo valida CNPJ numérico; CPF `529.982.247-25` válido

## Fase A — Metadata e acesso

- [x] T04 [REQ-001, 002, 012–014, 018, 023, 024] `Customer__c` + campos, aba, layout e
      list view "Todos os clientes"
- [x] T05 [REQ-014–016, 022] `Customer_Document__c` (Private) + campos
- [x] ~~T06 [NFR] `Cep_Lookup_Setting__mdt` + registro `Default` (120 s / 20)~~ →
      removido em 2026-11-26 pela revisão do plan (princípio 8 do `AGENTS.md`); os
      arquivos nunca foram implantados
- [x] T07 [REQ-003] External Credential + Named Credential `ViaCep` (resultado da T01)
- [x] T08 Custom Labels das mensagens
- [x] T09 [REQ-009–011, 022] Permission Sets `Customer_User` e `Customer_Admin` (incluindo
      acesso ao principal `ViaCep-ViaCepPrincipal`)
- [x] T10 Dry-run da Fase A → 2026-11-26: sucesso (inclui acesso ao principal
      `ViaCep-ViaCepPrincipal` nos Permission Sets). Acesso à classe `CustomerController`
      fica para a T24, quando a classe existir
- [x] T10b Dry-run da Fase A sem o Custom Metadata → 2026-11-26: sucesso

## Fase B — Testes (devem falhar)

- [x] T11 `CustomerTestDataFactory` e `ViaCepCalloutMock`
- [x] T12 [AC-014, 015] `DocumentValidatorTest` (vetor oficial do CNPJ alfanumérico)
- [x] T13 [AC-001, 002, 012–017, 022, 023, 026, 031, 032] `CustomerServiceTest`
- [x] T14 [AC-008–011, 025] `CustomerSecurityTest`
- [x] T15 [AC-003, 005–007] `ViaCepCalloutTest` + `CustomerControllerTest`
- [x] T16 [AC-021, 027, 028, 030] `CustomerAddressLookupJobTest`
- [x] T17 [AC-003–007, 018–020, 029] Jest de `customerForm`
- [x] T18 Dry-run com testes → 2026-11-26: vermelho como esperado, 36 de 44 testes Apex
      falharam por asserção. Esqueletos (só assinaturas) de `DocumentValidator`,
      `ViaCepCallout`, `CustomerController` e `CustomerAddressLookupJob` criados para os
      testes compilarem. Passaram só os que dependem de compartilhamento/permissão já
      existentes na metadata. Jest (T17) fica junto com o LWC (T25)

## Fase C — Implementação

- [x] T19 `DocumentValidator`
- [x] T20 `ViaCepCallout` (constante `TIMEOUT_MS = 120000`)
- [x] T21 `CustomerService` (validações, documento em `SYSTEM_MODE`, exclusão e
      restauração) + `CustomerDocumentDuplicateChecker` (without sharing)
- [x] T22 `CustomerTriggerHandler` + `CustomerTrigger`
- [x] T23 `CustomerAddressLookupJob` (constante `BATCH_SIZE = 20`)
- [x] T24 `CustomerController` + acesso à classe nos Permission Sets
- [x] T25 [REQ-026] LWC `customerForm` + aba "Novo cliente" + ação "Editar cliente";
      remover o "Editar" padrão das ações da página
- [x] T26 Dry-run com testes + lint + Jest → verde, cobertura ≥ 90%. Apex em 2026-11-26:
      46/46, cobertura 93,2%–100%. Durante a T21 o admin não conseguia mexer no documento
      de clientes de outros (`SYSTEM_MODE` respeita o compartilhamento de classe `with
sharing`); decisão do usuário: Modify All no documento para o admin, com campos só
      leitura (plan atualizado, 2 testes novos). LWC: Jest 10/10 (vermelho antes do
      componente), lint limpo; dry-run do pacote completo (Apex, trigger, LWC, aba, ação,
      layout, Permission Sets): sucesso, 46/46

## Fase D — Qualidade e entrega

- [x] T27 Revisão (`apex-reviewer`, `lwc-reviewer`) e correções → 2026-11-26:
  - **Bloqueador (Apex):** Queueable encadeado para no limite de 5 da Developer Edition
    (200 clientes = 10 execuções). Decisão do usuário: **Batch Apex**
    (`CustomerAddressLookupBatch`, blocos de 20, sem encadeamento, adiados relançados
    no `finish()` até 3 tentativas). Plan D-4 revisado
  - **Apex, importantes:** CPF "tomado" por linha com outro erro no lote; chaves de
    documento desalinhadas em nova tentativa de sucesso parcial (agora por Id nos updates
    e conferência de tamanho nos inserts); restauração em lote com o mesmo CPF (o primeiro
    vence, sem erro de plataforma); busca cortada pelo tempo tratada como "fora do ar"
    (agora é adiada); `lookupCep` sem cache (plan Segurança revisado)
  - **Apex, sugestões aplicadas:** logs quando a busca é pulada e quando a gravação do
    Batch falha; falha de gravação do documento que não é duplicidade com mensagem
    genérica; mensagem genérica para cliente nulo no controller. Não aplicada: o
    verificador de duplicidade continua devolvendo o Id do cliente (todos já veem todos
    os clientes, REQ-009)
  - **LWC, importantes:** corrida entre buscas (resposta antiga descartada); nova
    tentativa após "fora do ar"/"não encontrado"; CPF/CNPJ atualizado depois de editar
    (`refreshApex`)
  - **LWC, sugestões aplicadas:** falha da chamada tratada como "fora do ar"; Cancelar
    descarta busca em andamento; registro carregado uma vez; título próprio para erro de
    carga; erro do CEP no próprio campo (SLDS) e para leitores de tela; e-mail e telefone
    com o tipo certo
  - Testes novos: 3 Apex no service, 3 no Batch, 15 Jest. Resultado: Apex 52/52
    (cobertura 93,2%–100%), Jest 26/26, lint limpo, dry-run do pacote completo: sucesso
- [x] T28 Verificação final (CLAUDE.md seção 9) e atualização de spec/plan/tasks
- [x] T29 Deploy real (confirmado pelo usuário) → 2026-11-26: sucesso, 52/52 testes
      Apex na org, cobertura 93,2%–100%; conferido na org: `CustomerTrigger` ativo,
      LWC `customerForm` e Named Credential `ViaCep` presentes. Busca real no ViaCEP pela
      org (pedido do usuário, com `Customer_Admin` atribuído a ele): `CustomerController.lookupCep`
      via Apex anônimo → 01310-100 FOUND (Avenida Paulista, Bela Vista, São Paulo/SP, 113 ms),
      20040-020 FOUND (Praça Pio X, Centro, Rio de Janeiro/RJ, 29 ms), 99999-999 NOT_FOUND
      (40 ms)
