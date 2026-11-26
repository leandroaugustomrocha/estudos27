# 001 — Reserva de salas de reunião

> Status: Implementada (2026-11-26) — deploy na estudos27 com 54/54 testes
> Nível: Padrão

## Objetivo

Permitir que os usuários da org reservem salas de reunião sem conflitos de
horário, respeitando a capacidade e o horário de funcionamento de cada sala.
Sucesso = nenhuma sala fica com duas reservas ativas sobrepostas, mesmo quando
as reservas são criadas em massa.

## Contexto atual

Projeto novo, sem dados nem automações existentes. Verificado em 2026-11-26:
nenhum objeto com "Room", "Booking" ou "Reserv" no nome, nem no `force-app`
nem na org `estudos27`.

## Personas e permissões

| Persona                       | Pode                                                                                                                                  | Não pode                                                                                 |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| Colaborador                   | Ver todas as salas ativas e todas as reservas; criar reservas; editar, cancelar e excluir as reservas das quais é organizador         | Cadastrar ou alterar salas; editar, cancelar ou excluir reservas de outros organizadores |
| Administrador de salas        | Tudo o que o colaborador pode; cadastrar, alterar, inativar e excluir salas sem reservas; editar, cancelar e excluir qualquer reserva | Excluir sala que tenha reservas                                                          |
| Usuário sem acesso ao recurso | —                                                                                                                                     | Ver ou criar salas e reservas                                                            |

## Requisitos funcionais

### Salas

- REQ-001: O SISTEMA DEVE permitir cadastrar uma sala com nome, capacidade
  máxima de pessoas, indicação de ativa/inativa e horário de funcionamento
  próprio (hora de abertura e hora de fechamento), válido de segunda a sexta.
- REQ-017: SE a hora de fechamento da sala for vazia ou menor ou igual à hora
  de abertura, ENTÃO O SISTEMA DEVE rejeitar o cadastro com a mensagem "O
  horário de fechamento deve ser posterior ao de abertura."
- REQ-002: SE a capacidade informada for vazia, zero ou negativa, ENTÃO O
  SISTEMA DEVE rejeitar o cadastro com a mensagem "A capacidade da sala deve
  ser maior que zero."

### Reservas

- REQ-003: O SISTEMA DEVE permitir criar uma reserva informando sala, data/hora
  de início, data/hora de fim, número de participantes e assunto. O
  organizador é o usuário que cria a reserva.
- REQ-004: SE a data/hora de fim for menor ou igual à de início, ENTÃO O
  SISTEMA DEVE rejeitar a reserva com a mensagem "O fim da reserva deve ser
  posterior ao início."
- REQ-005: SE já existir uma reserva ativa na mesma sala cujo intervalo se
  sobreponha ao da nova reserva, ENTÃO O SISTEMA DEVE rejeitar a nova reserva
  com a mensagem "Esta sala já está reservada das <início> às <fim>."
  Dois intervalos se sobrepõem quando um começa antes do outro terminar; o
  horário de fim é exclusivo, então reservas encostadas (uma termina às
  11:00, a outra começa às 11:00) não conflitam.
- REQ-006: SE o número de participantes for maior que a capacidade da sala,
  ENTÃO O SISTEMA DEVE rejeitar a reserva com a mensagem "A sala comporta no
  máximo <capacidade> pessoas."
- REQ-007: SE a reserva começar antes da abertura ou terminar depois do
  fechamento da sala, cair em sábado ou domingo, ou não começar e terminar no
  mesmo dia, ENTÃO O SISTEMA DEVE rejeitar a reserva com a mensagem "Esta sala
  funciona de segunda a sexta, das <abertura> às <fechamento>."
- REQ-008: SE a sala estiver inativa, ENTÃO O SISTEMA DEVE rejeitar novas
  reservas com a mensagem "Esta sala não está disponível para reservas."
- REQ-009: SE a duração da reserva for menor que a duração mínima ou maior
  que a máxima, ENTÃO O SISTEMA DEVE rejeitá-la com a mensagem "A reserva
  deve durar entre <mínimo> e <máximo> minutos."
- REQ-019: SE o início da reserva estiver no passado, ENTÃO O SISTEMA DEVE
  rejeitá-la com a mensagem "Não é possível reservar um horário que já
  passou."; SE estiver além da antecedência máxima, ENTÃO com a mensagem "As
  reservas podem ser feitas com no máximo <N> dias de antecedência." A regra
  vale na criação e quando início ou fim forem alterados — editar só o
  assunto de uma reserva já iniciada continua permitido.
- REQ-020: O SISTEMA DEVE permitir que o administrador altere os limites
  (duração mínima, duração máxima e antecedência máxima) sem mudança de
  código. Valores iniciais: 15 minutos, 240 minutos e 90 dias.
- REQ-010: QUANDO uma reserva existente tiver sala, início, fim ou número de
  participantes alterados, O SISTEMA DEVE aplicar novamente as regras REQ-004
  a REQ-009 e REQ-019, ignorando a própria reserva na checagem de conflito.
- REQ-011: QUANDO uma reserva for cancelada (situação muda para "Cancelada"),
  O SISTEMA DEVE registrar a data/hora do cancelamento e liberar o horário
  para novas reservas; a reserva continua consultável.
- REQ-021: QUANDO uma reserva cancelada for reativada (situação volta para
  "Ativa"), O SISTEMA DEVE aplicar novamente todas as regras de reserva
  (REQ-004 a REQ-009 e REQ-019) e limpar a data/hora do cancelamento; SE
  alguma regra falhar, ENTÃO a reativação é rejeitada com a mensagem da regra.
- ~~REQ-022: SE um usuário que não é administrador de salas tentar excluir uma
  reserva, ENTÃO O SISTEMA DEVE negar a operação.~~ (substituído em
  2026-11-26 por REQ-023)
- REQ-023: O SISTEMA DEVE permitir que o organizador exclua as próprias
  reservas e que o administrador de salas exclua qualquer reserva; SE um
  colaborador tentar excluir uma reserva da qual não é organizador, ENTÃO O
  SISTEMA DEVE negar a operação.
- REQ-024: SE alguém tentar excluir uma sala que possui reservas (ativas ou
  canceladas), ENTÃO O SISTEMA DEVE negar a exclusão; a sala pode ser
  inativada (REQ-008).
- REQ-026: QUANDO uma reserva com situação "Ativa" for restaurada da Lixeira,
  O SISTEMA DEVE aplicar novamente todas as regras de reserva (REQ-004 a
  REQ-009, REQ-019 e REQ-025); SE alguma falhar, ENTÃO a restauração é negada
  com a mensagem da regra. Reservas "Canceladas" são restauradas sem checagem.

### Operações em massa

- REQ-012: QUANDO várias reservas forem criadas ou alteradas de uma vez (até
  200 por operação), O SISTEMA DEVE aplicar as regras REQ-004 a REQ-009 e
  REQ-019 a cada uma, inclusive detectando conflitos entre reservas do mesmo lote.
- ~~REQ-018: SE duas ou mais reservas do mesmo lote se sobrepuserem na mesma
  sala, ENTÃO O SISTEMA DEVE rejeitar todas elas com a mensagem "Esta
  reserva conflita com outra reserva do mesmo lote das <início> às <fim>.",
  independentemente da ordem em que aparecem no lote.~~ (substituído em
  2026-11-26 por REQ-025)
- REQ-025: SE duas ou mais reservas do mesmo lote se sobrepuserem na mesma
  sala, ENTÃO O SISTEMA DEVE manter a que aparece primeiro no lote (o
  primeiro a reservar tem preferência) e rejeitar as seguintes com a mensagem
  "Esta reserva conflita com outra reserva do mesmo lote das <início> às
  <fim>." Cada reserva é comparada apenas com as reservas anteriores do lote
  que foram aceitas; uma reserva rejeitada por qualquer regra não bloqueia as
  seguintes.
- REQ-013: SE em uma operação em massa algumas reservas forem inválidas,
  ENTÃO O SISTEMA DEVE rejeitar cada reserva inválida com a sua própria
  mensagem de erro.

### Permissões

- REQ-014: O SISTEMA DEVE permitir que todo colaborador veja todas as
  reservas, mas SE um colaborador tentar editar ou cancelar uma reserva da
  qual não é organizador, ENTÃO O SISTEMA DEVE negar a operação.
- REQ-015: SE um usuário que não é administrador de salas tentar criar,
  alterar ou inativar uma sala, ENTÃO O SISTEMA DEVE negar a operação; o
  administrador de salas DEVE poder editar e cancelar qualquer reserva.
- REQ-016: SE um usuário sem acesso ao recurso de reservas tentar ver ou criar
  salas ou reservas, ENTÃO O SISTEMA DEVE negar a operação.

## Critérios de aceite (Given/When/Then)

- AC-001 (REQ-001): Dado um administrador de salas, quando cadastra "Sala
  Azul" com capacidade 8, então a sala é salva como ativa.
- AC-002 (REQ-002): Dado um cadastro de sala com capacidade 0, quando salva,
  então recebe "A capacidade da sala deve ser maior que zero."
- AC-003 (REQ-003): Dada a "Sala Azul" livre amanhã das 10h às 11h, quando um
  colaborador reserva esse horário para 5 pessoas, então a reserva é salva e
  ele é o organizador.
- AC-004 (REQ-004): Dada uma reserva com início 11h e fim 10h, quando salva,
  então recebe "O fim da reserva deve ser posterior ao início."
- AC-005 (REQ-005): Dada uma reserva ativa na "Sala Azul" das 10h às 11h,
  quando outro usuário tenta reservar das 10h30 às 11h30, então recebe "Esta
  sala já está reservada das 10:00 às 11:00."
- AC-006 (REQ-005): Dada uma reserva ativa na "Sala Azul" das 10h às 11h,
  quando alguém reserva a "Sala Verde" das 10h às 11h, então a reserva é salva
  (conflito só vale na mesma sala).
- AC-007 (REQ-005): Dada uma reserva ativa das 10h às 11h, quando alguém
  reserva a mesma sala das 11h às 12h, então a reserva é salva.
- AC-007b (REQ-005): Dada uma reserva ativa das 10h às 12h, quando alguém
  reserva a mesma sala das 10h30 às 11h (totalmente contida), então recebe
  "Esta sala já está reservada das 10:00 às 12:00."
- AC-008 (REQ-006): Dada a "Sala Azul" com capacidade 8, quando alguém reserva
  para 9 pessoas, então recebe "A sala comporta no máximo 8 pessoas."
- AC-009 (REQ-007): Dada uma sala que funciona das 08:00 às 18:00, quando
  alguém reserva das 17:30 às 18:30 de uma quarta-feira, então recebe "Esta
  sala funciona de segunda a sexta, das 08:00 às 18:00."
- AC-009b (REQ-007): Dada a mesma sala, quando alguém reserva das 10:00 às
  11:00 de um sábado, então recebe a mesma mensagem.
- ~~AC-009c (REQ-007): Dada a mesma sala, quando alguém reserva exatamente das
  08:00 às 18:00 de uma segunda-feira, então a reserva é salva (os limites são
  inclusivos).~~ (substituído em 2026-11-26 por AC-009d — 10 h contradiz a
  duração máxima de 4 h do REQ-009; aprovado pelo usuário em 2026-11-26)
- AC-009d (REQ-007): Dada a mesma sala, quando alguém reserva das 08:00 às
  09:00 e das 17:00 às 18:00 de uma segunda-feira, então as duas reservas são
  salvas (os limites de abertura e fechamento são inclusivos).
- AC-031 (REQ-007): Dada uma sala que funciona das 08:00 às 18:00, quando um
  usuário com fuso America/Sao_Paulo reserva das 08:00 às 09:00 (horário dele)
  de uma segunda-feira, então a reserva é salva; quando um usuário com fuso
  America/Los_Angeles reserva o mesmo instante (03:00 às 04:00 no horário
  dele), então recebe a mensagem de horário de funcionamento.
- AC-023 (REQ-017): Dado um cadastro de sala com abertura 18:00 e fechamento
  08:00, quando salva, então recebe "O horário de fechamento deve ser
  posterior ao de abertura."
- AC-010 (REQ-008): Dada uma sala inativa, quando alguém tenta reservá-la,
  então recebe "Esta sala não está disponível para reservas."
- AC-011 (REQ-009): Com os limites iniciais, quando alguém reserva 10
  minutos, então recebe "A reserva deve durar entre 15 e 240 minutos."; o
  mesmo para 5 horas; 15 minutos e 4 horas exatos são aceitos.
- AC-024 (REQ-019): Quando alguém cria uma reserva que começou há 1 hora,
  então recebe "Não é possível reservar um horário que já passou."
- AC-025 (REQ-019): Quando alguém reserva para daqui a 91 dias, então recebe
  "As reservas podem ser feitas com no máximo 90 dias de antecedência."
- AC-026 (REQ-019): Dada uma reserva que já começou, quando o organizador
  altera só o assunto, então a alteração é salva.
- AC-027 (REQ-020): Dada a duração máxima alterada para 480 minutos, quando
  alguém reserva 5 horas, então a reserva é salva.
- AC-012 (REQ-010): Dada uma reserva das 10h às 11h, quando o organizador muda
  o fim para 11h30, então a alteração é salva (não conflita consigo mesma).
- AC-013 (REQ-010): Dadas reservas A (10h–11h) e B (11h–12h) na mesma sala,
  quando o organizador de A muda o fim para 11h30, então a alteração é
  rejeitada por conflito com B.
- AC-014 (REQ-011): Dada uma reserva ativa das 10h às 11h, quando ela é
  cancelada, então a data/hora do cancelamento é registrada, outra reserva
  das 10h às 11h na mesma sala é aceita e a reserva cancelada continua
  consultável.
- AC-028 (REQ-021): Dada uma reserva cancelada das 10h às 11h e o horário
  ainda livre, quando o organizador a reativa, então ela volta a "Ativa" e a
  data/hora do cancelamento é limpa.
- AC-029 (REQ-021): Dada uma reserva cancelada das 10h às 11h e outra reserva
  ativa criada depois no mesmo horário, quando o organizador tenta reativar a
  primeira, então recebe "Esta sala já está reservada das 10:00 às 11:00."
- ~~AC-030 (REQ-022)~~ (substituído em 2026-11-26 por AC-032 e AC-033)
- AC-032 (REQ-023): Dada uma reserva do colaborador A, quando A a exclui,
  então a exclusão é permitida; quando o colaborador B tenta excluí-la, então
  a operação é negada.
- AC-033 (REQ-023): Dada uma reserva do colaborador A, quando o administrador
  de salas a exclui, então a exclusão é permitida.
- AC-034 (REQ-024): Dada uma sala com uma reserva cancelada, quando o
  administrador tenta excluir a sala, então a exclusão é negada; dada uma sala
  sem reservas, a exclusão é permitida.
- AC-038 (REQ-026): Dada uma reserva ativa de A das 10h às 11h que A excluiu,
  e uma reserva de B criada depois no mesmo horário e sala, quando A tenta
  restaurar a sua da Lixeira, então recebe "Esta sala já está reservada das
  10:00 às 11:00." e a reserva continua excluída.
- AC-039 (REQ-026): Dada uma reserva cancelada de A que A excluiu, e uma
  reserva de B no mesmo horário, quando A a restaura, então a restauração é
  permitida (continua cancelada).
- AC-015 (REQ-012): Dado um lote de 200 reservas válidas sem conflitos, quando
  é importado, então todas são salvas.
- ~~AC-016 (REQ-018)~~ (substituído em 2026-11-26 por AC-035)
- AC-035 (REQ-025): Dado um lote com duas reservas sobrepostas na mesma sala,
  nesta ordem: 10h–11h e 10h30–11h30, e nenhuma reserva prévia, quando é
  importado permitindo sucesso parcial, então a de 10h–11h é salva e a de
  10h30–11h30 recebe "Esta reserva conflita com outra reserva do mesmo lote
  das 10:00 às 11:00."
- AC-036 (REQ-025): Dado um lote, nesta ordem: A 10h–11h, B 10h30–11h30 e
  C 11h–12h na mesma sala, quando é importado permitindo sucesso parcial,
  então A e C são salvas e só B é rejeitada (B não bloqueia C).
- AC-037 (REQ-025): Dado um lote, nesta ordem: A com 20 participantes numa
  sala de 8 (inválida) e B no mesmo horário com 5 participantes, quando é
  importado permitindo sucesso parcial, então A é rejeitada por capacidade e
  B é salva.
- AC-016b (REQ-025): Dado um lote com 10h–11h e 11h–12h na mesma sala, quando
  é importado, então as duas são salvas (encostadas não conflitam).
- AC-017 (REQ-013): Dado um lote com 199 reservas válidas e 1 com fim antes do
  início, quando é importado permitindo sucesso parcial, então as 199 são
  salvas e a inválida recebe a mensagem do REQ-004.
- AC-018 (REQ-014): Dada uma reserva cujo organizador é o colaborador A,
  quando o colaborador B tenta editá-la ou cancelá-la, então a operação é
  negada.
- AC-019 (REQ-014): Dada uma reserva do colaborador A, quando o colaborador B
  consulta as reservas da sala, então vê a reserva de A.
- AC-020 (REQ-015): Dado um colaborador, quando tenta criar ou alterar uma
  sala, então a operação é negada.
- AC-021 (REQ-015): Dado um administrador de salas, quando edita ou cancela a
  reserva de qualquer colaborador, então a operação é salva.
- AC-022 (REQ-016): Dado um usuário sem acesso ao recurso, quando tenta criar
  uma reserva, então a operação é negada.

## Requisitos não funcionais

- Volume: até 200 reservas por operação; volume total esperado de dezenas de
  salas e alguns milhares de reservas por ano.
- Segurança: cada usuário só vê e altera o que REQ-014 a REQ-016 permitem;
  mensagens de erro não expõem dados de reservas que o usuário
  não pode ver.
- Fuso horário: o horário de funcionamento, o dia da semana e o "mesmo dia"
  (REQ-007) são avaliados no fuso horário do usuário que cria ou altera a
  reserva; os horários exibidos nas mensagens também. Consequência aceita:
  usuários em fusos diferentes enxergam a mesma janela de funcionamento em
  horários absolutos diferentes. Em operações em massa, vale o fuso de quem
  executa a operação.
- Mensagens ao usuário: em português, com os textos definidos nos REQs.

## Dados envolvidos (nível de negócio)

- **Sala:** nome, capacidade, ativa/inativa, hora de abertura, hora de
  fechamento.
- **Reserva:** sala, organizador, assunto, início, fim, número de
  participantes, situação (ativa/cancelada), data/hora do cancelamento.
- **Configuração:** duração mínima, duração máxima, antecedência máxima.

## Fora de escopo

- Tela customizada (calendário, grade de disponibilidade) — usar as telas
  padrão do Salesforce nesta entrega; pode virar uma spec futura.
- Reservas recorrentes (toda segunda, etc.).
- Integração com Outlook/Google Calendar.
- Notificações por e-mail e convites para participantes.
- Check-in, liberação automática por ausência.
- Recursos da sala (projetor, TV) e filtro por recurso.
- Aprovação de reservas.
- Relatórios e dashboards.
- Feriados e horários diferentes por dia da semana.

## Dúvidas em aberto

- ~~[DÚVIDA D1]~~ Resolvida em 2026-11-26: todos veem, organizador edita/cancela
  as próprias, administrador de salas gerencia salas e qualquer reserva
  (REQ-014 a REQ-016).
- ~~[DÚVIDA D2]~~ Resolvida em 2026-11-26: horário por sala, só dias úteis
  (REQ-001, REQ-007, REQ-017).
- ~~[DÚVIDA D3]~~ Resolvida em 2026-11-26: reservas encostadas são permitidas;
  fim exclusivo (REQ-005, AC-007, AC-007b).
- ~~[DÚVIDA D4]~~ Resolvida em 2026-11-26: conflito no mesmo lote rejeita
  todas as envolvidas (REQ-018, AC-016, AC-016b). Revista em 2026-11-26:
  o primeiro do lote tem preferência (REQ-025).
- ~~[DÚVIDA D5]~~ Resolvida em 2026-11-26: 15 min a 4 h, sem passado, até 90
  dias, configuráveis (REQ-009, REQ-019, REQ-020).
- ~~[DÚVIDA D6]~~ Resolvida em 2026-11-26: cancelar muda a situação e pode
  ser revertido; excluir só o administrador (REQ-011, REQ-021, REQ-022).
  Revista em 2026-11-26: organizador exclui as próprias (REQ-023).
- ~~[DÚVIDA D7]~~ Resolvida em 2026-11-26: fuso do usuário que reserva
  (Requisitos não funcionais; AC-031).

Nenhuma dúvida em aberto.

## Histórico de mudanças

| Data       | Mudança                                                                                                                                                                                       | Motivo                                          |
| ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| 2026-11-26 | Rascunho inicial                                                                                                                                                                              | Início do projeto                               |
| 2026-11-26 | Personas definidas; REQ-014 a REQ-016 e AC-018 a AC-022                                                                                                                                       | Resposta à D1                                   |
| 2026-11-26 | Horário por sala em dias úteis; REQ-017, AC-009b/c e AC-023; feriados fora de escopo                                                                                                          | Resposta à D2                                   |
| 2026-11-26 | Fim exclusivo, encostadas permitidas; mensagem de conflito definida; AC-007b                                                                                                                  | Resposta à D3                                   |
| 2026-11-26 | REQ-018: conflito no mesmo lote rejeita todas; AC-016 e AC-016b                                                                                                                               | Resposta à D4                                   |
| 2026-11-26 | Limites configuráveis; REQ-019, REQ-020, AC-011, AC-024 a AC-027                                                                                                                              | Resposta à D5                                   |
| 2026-11-26 | Cancelamento reversível; REQ-021, REQ-022, AC-028 a AC-030                                                                                                                                    | Resposta à D6                                   |
| 2026-11-26 | Fuso do usuário que reserva; AC-031                                                                                                                                                           | Resposta à D7                                   |
| 2026-11-26 | Spec aprovada                                                                                                                                                                                 | Aprovação do usuário                            |
| 2026-11-26 | REQ-018→REQ-025 (primeiro do lote tem preferência); REQ-022→REQ-023 (organizador exclui as próprias); REQ-024 (sala com reservas não é excluída); AC-030/AC-016 substituídos; AC-032 a AC-037 | Pedido do usuário na aprovação do plan          |
| 2026-11-26 | REQ-026 (restaurar da Lixeira revalida as regras); AC-038, AC-039                                                                                                                             | Achado da revisão de código; decisão do usuário |
| 2026-11-26 | AC-009c → AC-009d (aprovado pelo usuário)                                                                                                                                                     | AC-009c contradizia a duração máxima do REQ-009 |
