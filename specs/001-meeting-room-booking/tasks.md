# Tasks — 001 Reserva de salas de reunião

> Spec: [spec.md](spec.md) · Plan: [plan.md](plan.md)
> Verificação padrão das tasks de código: deploy `--dry-run` escopado com
> `--test-level RunSpecifiedTests` (compila e roda os testes na org sem
> salvar nada).

## Fase A — Metadata e acesso

- [x] T01 [REQ-001, 002, 017] Criar `Meeting_Room__c` (OWD Public Read Only),
      campos `Capacity__c`, `Is_Active__c`, `Opening_Time__c`,
      `Closing_Time__c` e VRs `Capacity_Must_Be_Positive`,
      `Closing_After_Opening`
- [x] T02 [REQ-003, 011, 024] Criar `Room_Booking__c` (OWD Public Read Only),
      lookup Restrict para a sala, campos de início, fim, participantes,
      status e `Cancelled_At__c`
- [x] T03 [REQ-020] Criar `Booking_Setting__mdt` + registro `Default`
      (15 / 240 / 90)
- [x] T04 [REQ-004–009, 019, 025] Criar as 9 Custom Labels `Room_Booking_*`
- [x] T05 [REQ-014–016, 023] Criar Permission Sets `Meeting_Room_User` e
      `Meeting_Room_Admin`
- [x] T06 [REQ-001, 003] Criar abas e layouts dos dois objetos
- [x] T07 Dry-run da metadata (Fase A) → 2026-11-26: sucesso, 0 erros

## Fase B — Testes (devem falhar)

- [x] T14 (antecipada) Criar `TriggerHandler` — os testes precisam dela para
      compilar (bypass no AC-026)
- [x] T15 (antecipada) [REQ-009, 019, 020] Criar `BookingSettings` — idem
      (override no AC-027)
- [x] T08 Criar `RoomBookingTestDataFactory` (usuários por persona, salas,
      reservas, datas de dia útil no fuso do usuário)
- [x] T09 [AC-001, 002, 020, 023, 034] Escrever `MeetingRoomValidationTest`
- [x] T10 [AC-003 a AC-017, AC-024 a AC-029, AC-031, AC-035 a AC-037]
      Escrever `RoomBookingServiceTest`
- [x] T11 [AC-018, 019, 021, 022, 032, 033] Escrever `RoomBookingSecurityTest`
- [x] T12 Escrever `TriggerHandlerTest` + `BookingSettingsTest` (este último
      fora do plan: regra "uma classe de teste por classe" do `apex.md`)
- [x] T13 Dry-run com testes → 2026-11-26: vermelho como esperado. As regras
      de reserva falharam por asserção (AC-009, 009b, 010, 024, 025, 031). Dois
      defeitos dos próprios testes corrigidos: consultas de apoio sem FLS para
      o usuário que roda os testes (→ `WITH SYSTEM_MODE` só no lado do teste) e
      ordem do enum `TriggerOperation`

## Fase C — Implementação

- [x] T16 [REQ-005–008] Criar `MeetingRoomSelector` (com `FOR UPDATE`) e
      `RoomBookingSelector`
- [x] T17 [REQ-004–011, 019, 021, 025] Criar `RoomBookingService`
- [x] T18 Criar `RoomBookingTriggerHandler` e `RoomBookingTrigger`
- [x] T19 Dry-run com os testes → 2026-11-26: 45/45 passaram; cobertura
      `RoomBookingService` 98,7%, demais classes 100%

## Fase D — Qualidade e entrega

- [x] T20 Revisão com `apex-reviewer` e correções → 2026-11-26. Achados
      tratados:
  - NPE com campo obrigatório vazio em carga via API derrubava o lote →
    registros com campos obrigatórios vazios são ignorados pelo trigger
  - restaurar da Lixeira burlava as regras → **REQ-026** (decisão do usuário),
    `afterUndelete` no handler, AC-038/AC-039
  - update em massa com sucesso parcial mudava de resultado nas reexecuções →
    a versão salva de updates rejeitados continua ocupando o horário
  - datas de teste dependiam do fuso de quem roda os testes → fábrica monta
    datas no relógio de São Paulo
  - limites lidos uma vez por execução; AC-036 confere a mensagem
  - 7 testes novos para casos faltantes (lote de update, troca de horários,
    troca de sala/participantes, reativação no passado, Status default, pior
    caso de 200 no mesmo horário, campo vazio no lote)
  - inconsistência AC-009c × REQ-009 → AC-009d (aprovado pelo usuário)
- [x] T21 Verificação final (CLAUDE.md seção 9) e atualização de
      spec/plan/tasks → dry-run 54/54, cobertura ≥ 99,6%
- [x] T22 Deploy real (confirmado pelo usuário) → 2026-11-26: sucesso, 54/54
      testes na org, cobertura ≥ 99,6%; `Meeting_Room_Admin` atribuído ao
      usuário da org (pedido do usuário)

## Componentes do deploy escopado

```
force-app/main/default/objects/Meeting_Room__c
force-app/main/default/objects/Room_Booking__c
force-app/main/default/objects/Booking_Setting__mdt
force-app/main/default/customMetadata/Booking_Setting.Default.md-meta.xml
force-app/main/default/labels/CustomLabels.labels-meta.xml
force-app/main/default/permissionsets/Meeting_Room_User.permissionset-meta.xml
force-app/main/default/permissionsets/Meeting_Room_Admin.permissionset-meta.xml
force-app/main/default/tabs/Meeting_Room__c.tab-meta.xml
force-app/main/default/tabs/Room_Booking__c.tab-meta.xml
force-app/main/default/layouts/Meeting_Room__c-Meeting Room Layout.layout-meta.xml
force-app/main/default/layouts/Room_Booking__c-Room Booking Layout.layout-meta.xml
force-app/main/default/triggers/RoomBookingTrigger.trigger
force-app/main/default/classes/ TriggerHandler, BookingSettings, MeetingRoomSelector,
  RoomBookingSelector, RoomBookingService, RoomBookingTriggerHandler,
  RoomBookingTestDataFactory, MeetingRoomValidationTest, RoomBookingSecurityTest,
  RoomBookingServiceTest, TriggerHandlerTest, BookingSettingsTest (.cls + .cls-meta.xml)
```
