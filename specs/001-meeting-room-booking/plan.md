# Plan — 001 Reserva de salas de reunião

> Status: Aprovado (2026-11-26) — com ajustes do usuário (REQ-023 a REQ-025) e REQ-026 (revisão de código)
> Spec: [spec.md](spec.md) (Aprovada em 2026-11-26)

## Constitution Check

| #   | Princípio             | Atende? | Observação                                                                                                                                                                                                    |
| --- | --------------------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | `with sharing`        | ✅      | Todas as classes `with sharing`; base `TriggerHandler` é `inherited sharing` (utilitária).                                                                                                                    |
| 2   | Trigger Handler       | ✅      | `RoomBookingTrigger` sem lógica → `RoomBookingTriggerHandler` → `RoomBookingService` → selectors. Bypass estático na base.                                                                                    |
| 3   | Sem SOQL/DML em loop  | ✅      | 2 SOQL por execução do trigger, fora de loops; nenhuma DML (só alterações em `Trigger.new` no before).                                                                                                        |
| 4   | CRUD/FLS              | ✅      | Toda SOQL `WITH USER_MODE`. Sem DML na solução. Ver "Segurança" sobre a checagem de conflito.                                                                                                                 |
| 5   | Testes                | ✅      | `@TestSetup`, `Assert` com mensagem, bulk 200, `System.runAs` com usuários de cada persona.                                                                                                                   |
| 6   | Uma regra, um dono    | ✅      | Reserva: todas as regras no Apex (nenhuma validation rule/Flow no objeto). Sala: só validation rules (nenhum trigger).                                                                                        |
| 7   | Reusar antes de criar | ✅      | Não há framework de trigger nem objetos do tema. `TestDataFactory` existe na org para outro app → **não** reaproveitada nem sobrescrita; reaproveito o padrão dela (usuário Minimum Access + Permission Set). |
| 8   | Sem valores mágicos   | ✅      | Limites em Custom Metadata; mensagens em Custom Labels; nenhum Id fixo. Exceção: mensagens das 2 validation rules da sala ficam na própria regra (VR não lê Custom Label).                                    |
| 9   | Permission Set        | ✅      | 2 Permission Sets novos (colaborador e administrador).                                                                                                                                                        |
| 10  | Rastreabilidade       | ✅      | Tabela de testes abaixo cobre todos os ACs vigentes (36 — AC-016, AC-030 e AC-009c substituídos; AC-038/039 novos).                                                                                           |

## Decisão de automação

- **Sala (`Meeting_Room__c`): validation rules.** REQ-002 e REQ-017 são
  checagens simples no próprio registro — declarativo resolve, sem código.
- **Reserva (`Room_Booking__c`): Apex trigger (before insert/update + after undelete).** Conflito
  de horário exige consultar outras reservas e comparar reservas do mesmo lote
  (REQ-025), com 200 registros — fora do alcance de Flow/validation rule.
  Descartados: _Flow record-triggered_ (não compara registros do mesmo lote de
  forma confiável e é pior com 200); _validation rules para REQ-004/006/009_
  (rodam **depois** do before trigger; dividiriam as regras da reserva entre
  duas ferramentas e a checagem de conflito rodaria sobre dados inválidos).
- **Telas:** padrão do Salesforce (abas + layouts), conforme "Fora de escopo".

## Modelo de dados

### `Meeting_Room__c` (label "Sala de reunião") — OWD **Public Read Only**

| Campo (API name)  | Tipo        | Obrigatório  | Observação                                                                                                         |
| ----------------- | ----------- | ------------ | ------------------------------------------------------------------------------------------------------------------ |
| `Name`            | Text(80)    | Sim          | Label "Nome da sala"                                                                                               |
| `Capacity__c`     | Number(4,0) | Não no campo | Vazio/≤0 barrado pela VR (REQ-002) — se fosse obrigatório no campo, apareceria a mensagem padrão em vez da da spec |
| `Is_Active__c`    | Checkbox    | —            | Default `true` (AC-001)                                                                                            |
| `Opening_Time__c` | Time        | Sim          | Label "Hora de abertura"                                                                                           |
| `Closing_Time__c` | Time        | Não no campo | Vazio/≤ abertura barrado pela VR (REQ-017), mesmo motivo de `Capacity__c`                                          |

Validation rules: `Capacity_Must_Be_Positive` (REQ-002) e
`Closing_After_Opening` (REQ-017), com os textos exatos da spec.

### `Room_Booking__c` (label "Reserva de sala") — OWD **Public Read Only**

| Campo (API name)     | Tipo                      | Obrigatório | Observação                                                                                                   |
| -------------------- | ------------------------- | ----------- | ------------------------------------------------------------------------------------------------------------ |
| `Name`               | Text(80)                  | Sim         | Label "Assunto" (REQ-003)                                                                                    |
| `OwnerId`            | padrão                    | —           | **É o organizador.** Preenchido pela plataforma com quem cria (REQ-003) e base do compartilhamento (REQ-014) |
| `Meeting_Room__c`    | Lookup(`Meeting_Room__c`) | Sim         | Delete constraint **Restrict**: sala com reservas não pode ser excluída (REQ-024)                            |
| `Start_Date_Time__c` | DateTime                  | Sim         | Label "Início"                                                                                               |
| `End_Date_Time__c`   | DateTime                  | Sim         | Label "Fim" (exclusivo, REQ-005)                                                                             |
| `Attendee_Count__c`  | Number(4,0)               | Sim         | Label "Participantes"                                                                                        |
| `Status__c`          | Picklist restrita         | Sim         | `Active` ("Ativa", default) / `Cancelled` ("Cancelada")                                                      |
| `Cancelled_At__c`    | DateTime                  | Não         | Preenchido/limpo só pelo trigger (REQ-011/021); somente leitura para todos via FLS                           |

Lookup (e não Master-Detail) porque Master-Detail herda o compartilhamento da
sala: quem pudesse editar a sala editaria todas as reservas, quebrando
REQ-014.

### `Booking_Setting__mdt` (Custom Metadata Type) — REQ-020

| Campo                     | Tipo        | Registro `Default` |
| ------------------------- | ----------- | ------------------ |
| `Min_Duration_Minutes__c` | Number(5,0) | 15                 |
| `Max_Duration_Minutes__c` | Number(5,0) | 240                |
| `Max_Advance_Days__c`     | Number(4,0) | 90                 |

Lido com `Booking_Setting__mdt.getInstance('Default')` (não consome SOQL).

## Segurança

- **Compartilhamento:** OWD Public Read Only nos dois objetos → todos com
  acesso veem tudo (REQ-014, AC-019); só o dono (organizador) edita a própria
  reserva (AC-018). Administrador recebe **Modify All** (AC-021).
- **Permission Set `Meeting_Room_User`** (colaborador):
  - `Meeting_Room__c`: Read. FLS: leitura em todos os campos.
  - `Room_Booking__c`: Read, Create, Edit, Delete — o compartilhamento limita edição e exclusão às reservas próprias (REQ-023).
    FLS: edição em `Meeting_Room__c`, `Start_Date_Time__c`,
    `End_Date_Time__c`, `Attendee_Count__c`, `Status__c`; leitura em
    `Cancelled_At__c`.
  - Abas visíveis.
- **Permission Set `Meeting_Room_Admin`** (administrador de salas):
  - `Meeting_Room__c`: CRUD + View All + Modify All (REQ-015).
  - `Room_Booking__c`: CRUD + View All + Modify All (AC-021, AC-033).
  - FLS igual ao colaborador + edição nos campos da sala; `Cancelled_At__c`
    só leitura.
  - Não concede edição do Custom Metadata: alterar os limites (REQ-020) é
    feito em Setup por quem tem "Customize Application".
- **Usuário sem Permission Set** não tem CRUD → negado (REQ-016, AC-022).
- **Apex:** classes `with sharing`; SOQL `WITH USER_MODE`. A checagem de
  conflito roda em user mode e depende de o usuário enxergar todas as
  reservas ativas — garantido pelo OWD Public Read Only. Ver Riscos.
- **Mensagens** de conflito mostram só horários (nada de organizador ou
  assunto), atendendo o NFR de não expor dados.

## Componentes (inventário de metadata)

| Tipo               | Nome                                                                                                        | Ação  | Camada                                     | REQ                       |
| ------------------ | ----------------------------------------------------------------------------------------------------------- | ----- | ------------------------------------------ | ------------------------- |
| CustomObject       | `Meeting_Room__c` (+ 4 campos, 2 VRs)                                                                       | criar | dados                                      | 001, 002, 017             |
| CustomObject       | `Room_Booking__c` (+ 6 campos)                                                                              | criar | dados                                      | 003, 011, 024             |
| CustomObject (mdt) | `Booking_Setting__mdt` (+ 3 campos)                                                                         | criar | config                                     | 020                       |
| CustomMetadata     | `Booking_Setting.Default`                                                                                   | criar | config                                     | 009, 019, 020             |
| CustomLabels       | 9 labels `Room_Booking_*`                                                                                   | criar | config                                     | 004–009, 019, 025         |
| PermissionSet      | `Meeting_Room_User`                                                                                         | criar | acesso                                     | 014, 016, 023             |
| PermissionSet      | `Meeting_Room_Admin`                                                                                        | criar | acesso                                     | 015, 023                  |
| CustomTab          | `Meeting_Room__c`, `Room_Booking__c`                                                                        | criar | UI                                         | 001, 003                  |
| Layout             | `Meeting_Room__c-Meeting Room Layout`, `Room_Booking__c-Room Booking Layout`                                | criar | UI                                         | 001, 003                  |
| ListView           | `Meeting_Room__c.All` ("Todas as salas"), `Room_Booking__c.All` ("Todas as reservas") — visíveis para todos | criar | UI                                         | 001, 014 (AC-040, AC-041) |
| ApexClass          | `TriggerHandler`                                                                                            | criar | framework (base virtual + bypass)          | —                         |
| ApexTrigger        | `RoomBookingTrigger`                                                                                        | criar | trigger                                    | todos de reserva          |
| ApexClass          | `RoomBookingTriggerHandler`                                                                                 | criar | handler                                    | todos de reserva          |
| ApexClass          | `RoomBookingService`                                                                                        | criar | service                                    | 004–011, 019, 021, 025    |
| ApexClass          | `MeetingRoomSelector`                                                                                       | criar | selector                                   | 006–008                   |
| ApexClass          | `RoomBookingSelector`                                                                                       | criar | selector                                   | 005, 025                  |
| ApexClass          | `BookingSettings`                                                                                           | criar | config (lê o mdt, override `@TestVisible`) | 009, 019, 020             |
| ApexClass (test)   | `RoomBookingTestDataFactory`                                                                                | criar | teste                                      | —                         |
| ApexClass (test)   | `RoomBookingServiceTest`, `RoomBookingSecurityTest`, `MeetingRoomValidationTest`, `TriggerHandlerTest`      | criar | teste                                      | todos                     |

Labels: `Room_Booking_End_Before_Start`, `Room_Booking_Room_Conflict`,
`Room_Booking_Batch_Conflict`, `Room_Booking_Capacity_Exceeded`,
`Room_Booking_Outside_Hours`, `Room_Booking_Room_Inactive`,
`Room_Booking_Invalid_Duration`, `Room_Booking_Start_In_Past`,
`Room_Booking_Too_Far_Ahead` — placeholders `{0}`, `{1}` via `String.format`.

## Lógica do service (resumo)

`RoomBookingService.stampCancellation(...)` e `RoomBookingService.validate(...)`
(before insert/update); só `validate` no **after undelete** (REQ-026 — o
undelete não tem evento before e `Trigger.new` é somente leitura; o `addError`
desfaz a restauração):

1. **Carimbo de cancelamento:** `Active→Cancelled` grava `Cancelled_At__c = now`;
   `Cancelled→Active` limpa (REQ-011, REQ-021).
2. **Seleção dos registros a validar:** inserts/restaurações com status
   `Active`; updates `Active` em que mudou sala, início, fim, participantes ou
   status (REQ-010, REQ-021). Editar só o assunto não valida nada (AC-026).
   Registros com início, fim, sala ou participantes vazios são ignorados: em
   cargas via API/Apex a plataforma só checa campo obrigatório **depois** do
   before trigger e devolve o erro certo só naquela linha (REQ-013).
3. **Regras por registro, em ordem, parando no 1º erro:** fim > início
   (004) → duração (009) → passado/antecedência (019) → sala ativa (008) →
   capacidade (006) → horário/dia útil/mesmo dia (007).
4. **Conflito com reservas salvas (005):** 1 SOQL das reservas `Active` das
   salas envolvidas na janela `[menor início, maior fim)`, excluindo os Ids do
   lote. Comparação em memória por sala: `a.start < b.end && b.start < a.end`.
5. **Conflito dentro do lote (025):** percorre o lote **na ordem recebida**;
   cada registro que passou nos passos 3–4 é comparado só com os registros
   anteriores da mesma sala já aceitos. Se conflita, recebe erro; se não, entra
   na lista de aceitos. O primeiro do lote tem preferência e um rejeitado não
   bloqueia os seguintes (AC-035 a AC-037).
6. **Fuso:** horário local via `DateTime.format(pattern, UserInfo.getTimeZone().getID())`
   — hora (`HH:mm:ss`) e data (`yyyy-MM-dd`); dia da semana calculado a partir
   de uma segunda-feira conhecida (1900-01-01), sem depender de formato.
7. Erros via `record.addError(label formatado)` — sem exceção, permitindo
   sucesso parcial (REQ-013). Limites do Custom Metadata lidos uma vez por
   execução.

Sucesso parcial em **updates**: uma alteração rejeitada deixa a versão salva
no lugar. Se ela estava `Active`, continua ocupando o horário antigo — por isso
a versão antiga (`Trigger.oldMap`) de todo update rejeitado volta a contar como
ocupada para os registros seguintes do lote. Assim a 1ª passada já dá o
resultado final e a reexecução da plataforma não muda as decisões (achado da
revisão de código; teste `bulkUpdateRejectedKeepsSavedSlot_REQ012`).

Concorrência ("primeiro a reservar" entre transações diferentes): o selector
de salas usa `FOR UPDATE`, então a segunda transação espera a primeira gravar
e, ao consultar, já enxerga a reserva dela (REQ-005).

## Orçamento de governor limits (200 reservas, cenário pior: mesma sala)

| Recurso         | Estimado                                                           | Limite síncrono |
| --------------- | ------------------------------------------------------------------ | --------------- |
| SOQL            | 2 (salas + reservas existentes)                                    | 100             |
| Linhas SOQL     | ≤ 200 salas + reservas na janela (milhares no máximo)              | 50.000          |
| DML             | 0                                                                  | 150             |
| CPU             | < 500 ms (≤ 19.900 comparações no pior caso + formatação de datas) | 10.000 ms       |
| Callouts / heap | 0 / < 1 MB                                                         | 100 / 6 MB      |

No sucesso parcial, a plataforma pode reexecutar o trigger até 2 vezes
(2 SOQL a cada vez) — ainda muito abaixo do limite.

## Assíncrono e integrações

Nenhum. Tudo síncrono no before trigger.

## Plano de testes (rastreável)

Usuários de teste: perfil "Minimum Access - Salesforce" + Permission Set
(colaborador A, colaborador B, administrador, usuário sem acesso), criados no
`@TestSetup` via `RoomBookingTestDataFactory`, com fuso `America/Sao_Paulo`
(e um `America/Los_Angeles` para AC-031). Datas de teste calculadas como "a
próxima segunda/quarta a partir de daqui a 2 dias", no fuso do usuário. Os
limites usam o registro `Default` ou o override `@TestVisible` de
`BookingSettings` (AC-027).

| AC             | Classe de teste           | Método                                                                                                | Tipo                            |
| -------------- | ------------------------- | ----------------------------------------------------------------------------------------------------- | ------------------------------- |
| AC-001         | MeetingRoomValidationTest | adminCreatesActiveRoom_AC001                                                                          | positivo, runAs                 |
| AC-002         | MeetingRoomValidationTest | zeroCapacityRejected_AC002                                                                            | negativo                        |
| AC-023         | MeetingRoomValidationTest | closingBeforeOpeningRejected_AC023                                                                    | negativo                        |
| AC-020         | MeetingRoomValidationTest | collaboratorCannotEditRoom_AC020                                                                      | negativo, runAs                 |
| AC-003         | RoomBookingServiceTest    | collaboratorBooksFreeSlot_AC003                                                                       | positivo, runAs                 |
| AC-004         | RoomBookingServiceTest    | endBeforeStartRejected_AC004                                                                          | negativo                        |
| AC-005         | RoomBookingServiceTest    | overlappingBookingRejected_AC005                                                                      | negativo                        |
| AC-006         | RoomBookingServiceTest    | sameSlotOtherRoomAllowed_AC006                                                                        | positivo                        |
| AC-007         | RoomBookingServiceTest    | adjacentBookingAllowed_AC007                                                                          | positivo                        |
| AC-007b        | RoomBookingServiceTest    | containedBookingRejected_AC007b                                                                       | negativo                        |
| AC-008         | RoomBookingServiceTest    | overCapacityRejected_AC008                                                                            | negativo                        |
| AC-009         | RoomBookingServiceTest    | afterClosingRejected_AC009                                                                            | negativo                        |
| AC-009b        | RoomBookingServiceTest    | weekendRejected_AC009b                                                                                | negativo                        |
| AC-009d        | RoomBookingServiceTest    | exactOpeningHoursAllowed_AC009d                                                                       | positivo                        |
| AC-031         | RoomBookingServiceTest    | openingHoursUseBookerTimeZone_AC031                                                                   | positivo + negativo, runAs      |
| AC-010         | RoomBookingServiceTest    | inactiveRoomRejected_AC010                                                                            | negativo                        |
| AC-011         | RoomBookingServiceTest    | durationLimitsEnforced_AC011                                                                          | negativo + limites              |
| AC-024         | RoomBookingServiceTest    | pastStartRejected_AC024                                                                               | negativo                        |
| AC-025         | RoomBookingServiceTest    | tooFarAheadRejected_AC025                                                                             | negativo                        |
| AC-026         | RoomBookingServiceTest    | subjectEditOnStartedBookingAllowed_AC026                                                              | positivo                        |
| AC-027         | RoomBookingServiceTest    | configurableMaxDuration_AC027                                                                         | positivo                        |
| AC-012         | RoomBookingServiceTest    | extendWithoutSelfConflict_AC012                                                                       | positivo                        |
| AC-013         | RoomBookingServiceTest    | extendIntoNextBookingRejected_AC013                                                                   | negativo                        |
| AC-014         | RoomBookingServiceTest    | cancelStampsAndFreesSlot_AC014                                                                        | positivo                        |
| AC-028         | RoomBookingServiceTest    | reactivateWhenFree_AC028                                                                              | positivo                        |
| AC-029         | RoomBookingServiceTest    | reactivateIntoConflictRejected_AC029                                                                  | negativo                        |
| AC-015         | RoomBookingServiceTest    | bulkInsert200Valid_AC015                                                                              | bulk                            |
| AC-035         | RoomBookingServiceTest    | bulkFirstInBatchWins_AC035                                                                            | bulk, negativo, sucesso parcial |
| AC-036         | RoomBookingServiceTest    | bulkRejectedDoesNotBlockNext_AC036                                                                    | bulk, sucesso parcial           |
| AC-037         | RoomBookingServiceTest    | bulkInvalidDoesNotBlockNext_AC037                                                                     | bulk, sucesso parcial           |
| AC-016b        | RoomBookingServiceTest    | bulkAdjacentAllowed_AC016b                                                                            | bulk, positivo                  |
| AC-017         | RoomBookingServiceTest    | bulkPartialSuccess_AC017                                                                              | bulk, sucesso parcial           |
| AC-018         | RoomBookingSecurityTest   | otherCollaboratorCannotEdit_AC018                                                                     | negativo, runAs                 |
| AC-019         | RoomBookingSecurityTest   | collaboratorSeesOthersBookings_AC019                                                                  | positivo, runAs                 |
| AC-040, AC-041 | — (não testável em Apex)  | Verificação na org: `SELECT DeveloperName FROM ListView WHERE SobjectType IN (...)` + abertura da aba | configuração                    |
| AC-021         | RoomBookingSecurityTest   | adminEditsAnyBooking_AC021                                                                            | positivo, runAs                 |
| AC-022         | RoomBookingSecurityTest   | userWithoutAccessDenied_AC022                                                                         | negativo, runAs                 |
| AC-032         | RoomBookingSecurityTest   | organizerDeletesOwnOnly_AC032                                                                         | positivo + negativo, runAs      |
| AC-033         | RoomBookingSecurityTest   | adminDeletesAnyBooking_AC033                                                                          | positivo, runAs                 |
| AC-034         | MeetingRoomValidationTest | roomWithBookingsCannotBeDeleted_AC034                                                                 | positivo + negativo, runAs      |
| AC-038         | RoomBookingServiceTest    | restoreIntoTakenSlotRejected_AC038                                                                    | negativo, runAs                 |
| AC-039         | RoomBookingServiceTest    | restoreCancelledBookingAllowed_AC039                                                                  | positivo, runAs                 |
| REQ-013        | RoomBookingServiceTest    | blankRequiredFieldDoesNotBreakBatch_REQ013                                                            | bulk, negativo                  |
| REQ-012        | RoomBookingServiceTest    | bulkUpdateRejectedKeepsSavedSlot_REQ012                                                               | bulk update, sucesso parcial    |
| REQ-012        | RoomBookingServiceTest    | bulkUpdateBlankFieldKeepsSavedSlot_REQ012                                                             | bulk update, campo vazio        |
| REQ-012        | RoomBookingServiceTest    | bulkUpdateSwapSlots_REQ012                                                                            | bulk update, positivo           |
| REQ-010        | RoomBookingServiceTest    | roomOrAttendeeChangeRevalidates_REQ010                                                                | negativo                        |
| REQ-021        | RoomBookingServiceTest    | reactivatePastBookingRejected_REQ021                                                                  | negativo                        |
| REQ-003        | RoomBookingServiceTest    | insertWithoutStatusDefaultsToActive_REQ003                                                            | positivo                        |
| REQ-025        | RoomBookingServiceTest    | bulkSameSlotWorstCase_REQ025                                                                          | bulk 200, pior caso             |
| REQ-020        | BookingSettingsTest       | readsDefaultRecord, missingRecordThrowsClearError                                                     | positivo + negativo             |
| —              | TriggerHandlerTest        | 4 métodos (roteamento, defaults, bypass, fora de trigger)                                             | cobertura do framework          |

AC-009c foi substituído por AC-009d (`exactOpeningHoursAllowed_AC009d`) —
aprovado pelo usuário em 2026-11-26.

Comando: `sf apex run test --target-org estudos27 --class-names RoomBookingServiceTest --class-names RoomBookingSecurityTest --class-names MeetingRoomValidationTest --class-names TriggerHandlerTest --class-names BookingSettingsTest --code-coverage --result-format human --wait 10`.
Meta: ≥ 90% por classe nova.

**Testes e FLS:** quem roda os testes (admin da org) não tem FLS nos campos
novos — na API 68 a consulta falha com "No such column". Consultas de apoio
dos testes (que só conferem resultados) usam `WITH SYSTEM_MODE`; as operações
sob teste continuam em `USER_MODE` dentro de `System.runAs`. Datas de teste
são montadas no relógio de São Paulo (fuso das personas), independentemente
do fuso de quem roda os testes.

Desvio da regra "uma classe de teste por classe" (`apex.md`):
`RoomBookingTriggerHandler`, `MeetingRoomSelector` e `RoomBookingSelector` não
têm `<Classe>Test` próprio — são cobertos (100%) pelos testes de comportamento
via DML, que é como são usados.

## Deploy e rollback

- **Deploy escopado** (nunca `force-app` inteiro, que tem metadata fora de
  sincronia com a org — ex.: `TestDataFactory` existe só na org):
  `sf project deploy start --target-org estudos27 --dry-run` com um
  `--source-dir` para cada componente do inventário (lista exata no
  `tasks.md`). Uma única transação: a plataforma resolve a ordem
  objeto → campo → permission set → Apex.
- Deploy real com `--test-level RunSpecifiedTests` e as 5 classes de teste,
  **só após sua confirmação**.
- **Rollback:** tudo é novo, então desfazer = remover os componentes com
  `destructiveChanges.xml` — **só com sua confirmação**. Alternativa sem
  deleção: desligar o trigger pelo bypass e remover as Permission Sets dos
  usuários.

## Riscos

| Risco                                                                                                                                                                                                   | Probabilidade           | Mitigação                                                                                                                                                                                                                                                             |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Duas pessoas reservam o mesmo horário ao mesmo tempo (transações concorrentes passam na checagem)                                                                                                       | Baixa (org de estudo)   | `SELECT … FOR UPDATE` nas salas envolvidas para serializar reservas por sala. Verificado: `FOR UPDATE` + `WITH USER_MODE` funciona com o colaborador (só leitura na sala) — todos os testes runAs passam. A concorrência real entre transações não é testável em Apex |
| OWD de reserva mudar para Private no futuro → checagem em user mode deixa de ver reservas de outros                                                                                                     | Baixa                   | Comentário no selector + AC-019 testado; mudança de OWD exige nova spec                                                                                                                                                                                               |
| Fuso não se comportar como esperado                                                                                                                                                                     | Baixa                   | Formato `u` eliminado (dia da semana por cálculo). AC-009b e AC-031 passam                                                                                                                                                                                            |
| Horário de verão (DST) desloca a janela em testes                                                                                                                                                       | Baixa                   | Datas de teste no relógio de São Paulo (sem horário de verão), montadas por `RoomBookingTestDataFactory.at`                                                                                                                                                           |
| Testes dependem de "agora" (passado, 90 dias)                                                                                                                                                           | Média                   | Datas sempre relativas a `System.now()` / próxima segunda a partir de +2 dias                                                                                                                                                                                         |
| Sucesso parcial reexecuta o trigger                                                                                                                                                                     | Certa                   | Sem DML nem estado estático; a versão salva de updates rejeitados continua ocupando o horário, então a 1ª passada já é definitiva. AC-017, AC-035 a AC-037 e `bulkUpdateRejectedKeepsSavedSlot_REQ012` testam                                                         |
| Sala com reservas não pode ser excluída (lookup Restrict)                                                                                                                                               | —                       | Confirmado pelo usuário e registrado como REQ-024                                                                                                                                                                                                                     |
| Sobrescrever metadata da org que não está no local                                                                                                                                                      | Média                   | Nomes verificados na org; deploy escopado                                                                                                                                                                                                                             |
| Automação em system mode (Flow/Apex de integração) grava reservas em nome de usuário sem o Permission Set → as consultas `USER_MODE` do trigger lançam `QueryException` e o lote falha com erro técnico | Baixa (não existe hoje) | Aceito (code review 2026-11-26). Se surgir, nova spec: isolar a checagem de conflito numa classe `without sharing` pequena com `WITH SYSTEM_MODE`, justificada                                                                                                        |
| `FOR UPDATE` trava as salas até o fim da transação → sob concorrência alta, `UNABLE_TO_LOCK_ROW` após 10 s                                                                                              | Baixa                   | Comportamento esperado: a segunda transação espera ou falha, nunca grava em conflito                                                                                                                                                                                  |
| Registro `Default` de `Booking_Setting__mdt` apagado → toda gravação de reserva falha com `BookingSettingsException`                                                                                    | Baixa                   | Erro de configuração com mensagem clara para o admin; `<protected>` não tem efeito fora de pacote gerenciado                                                                                                                                                          |
