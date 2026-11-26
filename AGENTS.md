# AGENTS.md — Constituição do projeto estudos27

Fonte única de verdade para Claude Code, Kiro e Agentforce Vibes.
Este arquivo é carregado em TODA interação: manter curto. Processo detalhado
fica em `CLAUDE.md` (Claude Code) e `.kiro/steering/sdd-process.md` (Kiro).

- Org única: alias `estudos27` (Developer Edition). Nunca usar outra org.
- `sourceApiVersion`: 68.0.
- Responder em português do Brasil; código, comentários e nomes de API em inglês.
- Regras detalhadas de código: `agent_docs/` e `.claude/rules/`
  (`apex.md`, `lwc.md`, `flows.md`, `general.md`). Em conflito, perguntar.
- `agent_docs/security.md` é leitura obrigatória antes de qualquer trabalho com
  `@AuraEnabled`, SOQL, DML ou sharing.

## Constituição (princípios inegociáveis)

Todo plano técnico (`plan.md` no Claude Code, `design.md` no Kiro) começa com
um "Constitution Check" que confirma cada item ou justifica a exceção.
Alterar a Constituição exige pedido explícito do usuário.

### Apex

1. **`with sharing` por padrão.** `without sharing` só com justificativa em
   comentário na classe e no plano. Utilitárias sem contexto: `inherited sharing`.
2. **Trigger Handler, camadas sob demanda.** Um trigger por objeto
   (`<Object>Trigger`), sem lógica, delegando para `<Object>TriggerHandler`
   (com bypass). Criar `<Domain>Service` só quando houver lógica reutilizada
   ou que envolva mais de um objeto; criar `<Object>Selector` só quando a mesma
   query for usada em mais de um lugar. Caso contrário, a lógica fica no handler.
   Se o service/selector do objeto já existe, usar e estender o existente.
3. **Nunca SOQL ou DML dentro de loops.** Bulkificar com `Set<Id>`,
   `Map<Id, SObject>` e DML em lista.
4. **CRUD/FLS em toda query e DML.** `WITH USER_MODE` e `AccessLevel.USER_MODE`;
   senão `Security.stripInaccessible()`. Exceção exige justificativa no código e
   no plano.
5. **Todo Apex tem teste** (`<ClassName>Test`, `@IsTest`): dados em `@TestSetup`
   ou `TestDataFactory` (nunca `SeeAllData=true`); `Assert.*` sempre com
   mensagem; `Test.startTest()`/`stopTest()`; cenários positivo, negativo,
   bulk (200+) e `System.runAs` para o que a spec cobre.

### Plataforma

6. **Declarativo antes de código; uma regra tem um só dono.** Nunca Flow e
   trigger disputando a mesma regra no mesmo objeto.
7. **Reusar antes de criar.** Procurar objeto, campo, classe, LWC ou Flow
   existente antes de criar algo novo.
8. **Sem valores mágicos.** Sem IDs fixos; textos de usuário em Custom Labels;
   Record Types por `DeveloperName`; Custom Metadata só para o que a spec diz
   que precisa ser configurável.
9. **Acesso por Permission Set**, nunca Profile. Todo objeto/campo/classe novo
   entra num Permission Set na mesma entrega.
10. **Rastreabilidade.** REQ → AC → task → teste → commit. Nada sem REQ;
    nenhum REQ sem teste.

## Disciplina de escopo

- Implementar somente o que está na spec aprovada. Melhoria fora dela vira
  sugestão no final, não código.
- Não inventar regra de negócio: marcar `[DÚVIDA]` e perguntar uma por vez.
- Antes de usar objeto, campo, classe ou método, confirmar que existe em
  `force-app/` ou na org (somente leitura). Nunca inventar API names.
- Deploy sempre escopado aos componentes do plano, primeiro com `--dry-run`.
  Deploy real só com confirmação explícita. Nunca deletar metadata sem confirmação.
- Código que não cumpre a Constituição não está pronto, mesmo compilando.
