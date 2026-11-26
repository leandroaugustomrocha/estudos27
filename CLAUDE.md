@AGENTS.md

# CLAUDE.md — Spec-Driven Development (SDD) para Salesforce

Este projeto segue **Spec-Driven Development**: a especificação é a fonte da
verdade e o código é a implementação dela. Nenhuma linha de Apex, LWC, Flow ou
metadata é escrita antes de existir uma spec aprovada (salvo as exceções da
seção 2).

- Org única: alias `estudos27` (Developer Edition). **Nunca** usar outra org,
  mesmo que esteja autenticada no CLI.
- `sourceApiVersion`: 68.0 (ver `sfdx-project.json`).
- Responder em **português do Brasil**; código, comentários, nomes de API,
  classes, métodos e variáveis em **inglês**.
- Este arquivo define o **processo** e os **princípios**. O padrão de código
  detalhado está em `AGENTS.md`, `agent_docs/` e `.claude/rules/`
  (`apex.md`, `lwc.md`, `flows.md`, `general.md`). Em conflito, perguntar
  antes de seguir.

### Específico do Claude Code

- `AGENTS.md` (importado acima) é a fonte única de verdade compartilhada com o
  Agentforce Vibes. Regras de código compartilhadas vão lá, não aqui.
- Carregar contexto sob demanda: `agent_docs/business-rules.md` é sempre
  relevante; ler `agent_docs/security.md` em qualquer trabalho com
  `@AuraEnabled`, SOQL, DML ou sharing.
- Em pedidos de nível Padrão (seção 2), o Plan Mode pode ser usado para
  redigir a spec e o plan antes de escrever arquivos.
- Um hook `PreToolUse` em `.claude/settings.json` bloqueia `git commit` se o
  lint ou os testes de LWC falharem — corrigir os erros, nunca contornar o
  hook.

---

## 1. Constituição (princípios inegociáveis)

Valem em toda fase e em toda geração ou alteração de código. Todo `plan.md`
tem um "Constitution Check" que confirma cada item ou justifica a exceção.

### 1.1 Regras permanentes de Apex

1. **`with sharing` por padrão.** `without sharing` só quando estritamente
   necessário, com justificativa em comentário na classe **e** no `plan.md`.
   Classes utilitárias sem contexto próprio usam `inherited sharing`.
2. **Padrão Trigger Handler.** Um único trigger por objeto (`<Object>Trigger`),
   cobrindo todos os eventos e **sem lógica** — só delega para
   `<Object>TriggerHandler`, que encaminha para services (`<Domain>Service`) e
   selectors (`<Object>Selector`). O handler tem mecanismo de bypass.
3. **Nunca SOQL ou DML dentro de loops.** Bulkificar com `Set<Id>`,
   `Map<Id, SObject>` e DML em lista, fora de qualquer `for`/`while`.
4. **CRUD/FLS em toda query e DML.** `WITH USER_MODE` no SOQL e
   `AccessLevel.USER_MODE` no `Database.*`; quando não for possível,
   `Security.stripInaccessible()`. Exceção (ex.: `SYSTEM_MODE` em processo de
   sistema) exige justificativa no código e no `plan.md`.
5. **Todo Apex vem com classe de teste** (`<ClassName>Test`, `@IsTest`) que:
   - cria dados em `@TestSetup` (ou `TestDataFactory`), nunca `SeeAllData=true`;
   - usa asserts descritivos da classe `System.Assert` (`Assert.areEqual`,
     `Assert.isTrue`…) **sempre com mensagem**;
   - inclui teste de carga com **200+ registros**, além de positivo, negativo
     e `System.runAs` (usuário sem permissão);
   - envolve a chamada testada em `Test.startTest()` / `Test.stopTest()`.

### 1.2 Princípios de plataforma

6. **Declarativo antes de código, mas uma regra tem um só dono.** Preferir
   configuração/Flow quando resolve; nunca Flow e trigger disputando a mesma
   regra no mesmo objeto.
7. **Reusar antes de criar.** Nada de objeto, campo, classe, LWC ou Flow novo
   sem antes procurar algo existente que possa ser estendido.
8. **Sem valores mágicos.** Nada de IDs fixos; configuração em Custom Metadata,
   textos de usuário em Custom Labels, Record Types por `DeveloperName`.
9. **Acesso por Permission Set**, nunca por Profile. Todo objeto/campo/classe
   novo entra em um Permission Set na mesma entrega.
10. **Rastreabilidade ponta a ponta.** REQ → AC → task → teste → commit. Nada
    é implementado sem REQ; nenhum REQ fica sem teste.

Código que não cumpre a Constituição não está pronto, mesmo que compile e os
testes passem. Alterar a Constituição exige pedido explícito do usuário.

---

## 2. Tamanho do pedido → profundidade do processo

Classificar o pedido **antes** de começar e dizer a classificação ao usuário.

| Nível       | Exemplos                                 | Artefatos                                                | Portões      |
| ----------- | ---------------------------------------- | -------------------------------------------------------- | ------------ |
| **Trivial** | typo, label, help text, formatação, doc  | nenhum (dizer o motivo)                                  | —            |
| **Pequeno** | 1 campo + validação, ajuste em 1 método  | `spec.md` curta com seção "Plano" e "Tarefas" embutidas  | 1 aprovação  |
| **Padrão**  | feature, nova automação, integração, LWC | `spec.md` + `plan.md` + `tasks.md`                       | 2 aprovações |
| **Bug**     | comportamento divergente do esperado     | AC na spec existente ou `specs/<NNN>-fix-<slug>/spec.md` | 1 aprovação  |

Na dúvida entre dois níveis, usar o maior.

---

## 3. O fluxo

```
0. Contexto → 1. Specify → 1.5 Clarify → [aprovação da spec]
            → 2. Plan (+ Constitution Check) → [aprovação do plan]
            → 3. Tasks → 4. Implement (TDD) → 5. Verify → [confirmação de deploy]
```

| Fase         | Saída                                            | Portão                                     |
| ------------ | ------------------------------------------------ | ------------------------------------------ |
| 0. Contexto  | Leitura do que existe (nada é escrito)           | —                                          |
| 1. Specify   | `specs/<NNN>-<slug>/spec.md` (status `Rascunho`) | —                                          |
| 1.5 Clarify  | `[DÚVIDA]`s resolvidas, uma por vez              | **Parar: aprovar spec**                    |
| 2. Plan      | `plan.md` com Constitution Check                 | **Parar: aprovar plan**                    |
| 3. Tasks     | `tasks.md` ordenado e rastreável                 | Seguir, salvo dúvida                       |
| 4. Implement | Código + testes, task a task                     | —                                          |
| 5. Verify    | Checklist (seção 9) + `--dry-run`                | **Pedir confirmação antes de deploy real** |

Regras do fluxo:

- **Nunca pular fase** do nível escolhido. Pedido pequeno = spec curta, não
  ausência de spec.
- **Não inventar regra de negócio.** Marcar `[DÚVIDA]` e perguntar **uma por
  vez**, oferecendo opções com recomendação quando possível.
- **A spec muda antes do código.** Se a implementação revelar algo que
  contradiz a spec, parar, propor a alteração, esperar aprovação, então mudar
  o código.
- **Status no cabeçalho da spec:** `Rascunho` → `Aprovada` → `Em implementação`
  → `Implementada`. Atualizar a cada transição, com data.
- Pastas: `specs/001-...`, `002-...` sequencial, slug kebab-case em inglês
  (`003-account-cep-lookup`). Verificar o maior número existente antes de criar.

---

## 4. Fase 0 — Contexto (antes de escrever qualquer coisa)

1. Ler `AGENTS.md`, as regras de `.claude/rules/` relevantes,
   `agent_docs/business-rules.md` e `agent_docs/security.md`.
2. Procurar no projeto o que já existe sobre o tema: objetos, campos,
   validações, triggers, handlers, services, selectors, LWCs, Flows,
   Permission Sets, Custom Metadata, Custom Labels.
3. Ler specs anteriores em `specs/` que toquem os mesmos objetos.
4. Se precisar de informação da org (campos, record types, Flows ativos,
   automações no objeto), consultar a `estudos27` **somente leitura**
   (`sf` CLI / MCP / SOQL). Não confiar em defaults de documentação para
   valores da org.
5. Mapear **toda automação já existente no objeto** (triggers, Flows
   record-triggered, validation rules) — ela entra na spec como contexto e no
   plan como risco de ordem de execução.
6. Código legado sem spec que será alterado: escrever primeiro uma spec
   **as-is** (comportamento atual) e depois a **to-be**.

---

## 5. Fase 1 — `spec.md` (o QUÊ e o PORQUÊ; sem decidir tecnologia)

A spec descreve comportamento observável pelo usuário ou por outro sistema.
**Não** fala em classe, trigger, Flow ou LWC.

```markdown
# <NNN> — <Título>

> Status: Rascunho | Aprovada (AAAA-MM-DD) | Em implementação | Implementada (AAAA-MM-DD)
> Nível: Pequeno | Padrão | Bug

## Objetivo

Uma ou duas frases: que problema resolve, para quem, e como saberemos que
deu certo.

## Contexto atual

O que já existe no(s) objeto(s) (automações, campos, regras) e é relevante.

## Personas e permissões

| Persona | Pode | Não pode |
| ------- | ---- | -------- |

## Requisitos funcionais

- REQ-001: QUANDO <evento>, O SISTEMA DEVE <comportamento>.
- REQ-002: ENQUANTO <estado>, O SISTEMA DEVE <comportamento>.
- REQ-003: SE <condição de erro>, ENTÃO O SISTEMA DEVE <tratamento/mensagem>.

## Critérios de aceite (Given/When/Then)

- AC-001 (REQ-001): Dado <estado>, quando <ação>, então <resultado>.
- AC-002 (REQ-003): Dado <usuário sem permissão>, quando <ação>, então <erro>.

## Requisitos não funcionais

- Volume: até N registros por transação (mínimo 200) e volume total esperado.
- Segurança: quem enxerga/edita o quê (sharing, CRUD/FLS).
- Desempenho e limites esperados; comportamento se uma integração falhar.
- Mensagens ao usuário: texto exato (vira Custom Label).

## Dados envolvidos (nível de negócio)

Objetos e informações necessárias, sem API names definitivos.

## Fora de escopo

O que explicitamente NÃO será feito nesta entrega.

## Dúvidas em aberto

- [DÚVIDA] ...

## Histórico de mudanças

| Data | Mudança | Motivo |
| ---- | ------- | ------ |
```

Boas práticas da spec:

- Requisitos no formato **EARS** (QUANDO / ENQUANTO / SE…ENTÃO … O SISTEMA
  DEVE …): **numerados, atômicos e testáveis** — um comportamento por REQ.
- IDs são estáveis: nunca renumerar. REQ removido vira `~~REQ-004~~
(substituído em AAAA-MM-DD por REQ-007)`.
- Todo REQ tem ao menos um AC; todo AC aponta para um REQ.
- Cobrir sempre os **caminhos de erro**: sem permissão, campo vazio, dado
  inválido, registro duplicado, callout falhando, operação em massa (200),
  usuário sem acesso ao registro (sharing).
- "Fora de escopo" é obrigatório — é o que segura o escopo.
- Spec só é aprovada sem `[DÚVIDA]` aberta.

---

## 6. Fase 2 — `plan.md` (o COMO, específico de Salesforce)

Traduz a spec em decisões de plataforma. Cada decisão tem 1–2 linhas de
justificativa e as alternativas descartadas.

```markdown
# Plan — <NNN> <Título>

## Constitution Check

| Princípio          | Atende? | Observação / justificativa de exceção |
| ------------------ | ------- | ------------------------------------- |
| 1. with sharing    | ✅      |                                       |
| 2. Trigger Handler | ✅      |                                       |
| ... (1 a 10)       |         |                                       |

## Decisão de automação

Flow, Apex, LWC + LDS ou combinação — e por quê (tabela "Escolha da
ferramenta"). Alternativas descartadas.

## Reuso

O que existente será reaproveitado/estendido e o que será criado do zero.

## Modelo de dados

| Objeto | Campo (API name) | Tipo | Obrigatório | Observação |
| ------ | ---------------- | ---- | ----------- | ---------- |

## Segurança

- Sharing de cada classe e justificativa.
- CRUD/FLS: `WITH USER_MODE` / `AccessLevel.USER_MODE` / `stripInaccessible`.
- Permission Set a criar/alterar e o que concede (objeto, campos, classes, tabs).
- `@AuraEnabled`: validação de entrada; sem SOQL dinâmico sem bind.

## Componentes (inventário de metadata)

| Tipo | Nome | Ação (criar/alterar) | Camada | REQ |
| ---- | ---- | -------------------- | ------ | --- |

## Ordem de execução e automações existentes

Como a solução convive com triggers/Flows/validations já presentes no objeto;
risco de recursão e como é evitado.

## Orçamento de governor limits (200 registros)

| Recurso  | Estimado | Limite síncrono |
| -------- | -------- | --------------- |
| SOQL     |          | 100             |
| DML      |          | 150             |
| CPU      |          | 10.000 ms       |
| Callouts |          | 100             |

## Assíncrono e integrações

Queueable/Batch/Platform Event; Named Credential + External Credential;
retry, timeout, idempotência e log de erro.

## Plano de testes (rastreável)

| AC  | Classe de teste | Método | Tipo (positivo/negativo/bulk/runAs) |
| --- | --------------- | ------ | ----------------------------------- |

## Deploy e rollback

Lista exata dos componentes a implantar (deploy **escopado**, não `force-app`
inteiro), ordem, `--dry-run`, testes a rodar e como desfazer.

## Riscos

| Risco | Probabilidade | Mitigação |
| ----- | ------------- | --------- |
```

### Escolha da ferramenta

| Situação                                            | Preferência                                             |
| --------------------------------------------------- | ------------------------------------------------------- |
| Atualizar campos do próprio registro, regra simples | Before-save Record-Triggered Flow                       |
| Validação simples de dados                          | Validation Rule                                         |
| Lógica complexa, vários objetos, volume alto, reuso | Apex (trigger → handler → service → selector)           |
| Callout externo                                     | Apex `*Callout` + Named Credential + Queueable          |
| Tela de leitura/edição simples                      | LWC com Lightning Data Service, sem Apex                |
| Tela com regra ou consulta complexa                 | LWC + `@AuraEnabled` (`cacheable=true` só para leitura) |
| Processamento de grande volume                      | Batch Apex                                              |
| Desacoplar processos / auditoria                    | Platform Events / Change Data Capture                   |
| Parâmetros e regras configuráveis                   | Custom Metadata Type                                    |

### Pegadinhas da org `estudos27`

- Idioma padrão inglês (gender neutral): **nunca** usar `<gender>` em objetos
  customizados — o deploy falha. Labels em português são permitidos.
- Developer Edition: confirmar que o recurso (Agentforce, CDC, Data Cloud,
  Shield…) está disponível na org antes de planejar em cima dele.
- O diretório `force-app` contém metadata recuperada da org que não pertence a
  nenhuma spec; por isso o deploy é sempre escopado aos componentes do plan.

---

## 7. Fase 3 — `tasks.md` (passos pequenos e verificáveis)

```markdown
# Tasks — <NNN> <Título>

## Fase A — Metadata e acesso

- [ ] T01 [REQ-001] Criar campo X__c no objeto Y → verificar: dry-run do campo
- [ ] T02 [REQ-001] Conceder FLS de X__c no Permission Set Z

## Fase B — Testes (devem falhar)

- [ ] T03 [AC-001] Escrever teste `methodName_AC001` → verificar: falha esperada

## Fase C — Implementação

- [ ] T04 [AC-001] Implementar service até T03 passar → verificar: teste verde

## Fase D — Qualidade e entrega

- [ ] T0N Revisão (apex-reviewer / lwc-reviewer) e correções
- [ ] T0N Verificação final (seção 9)
```

- Cada task cabe em uma edição pequena, cita o REQ/AC e diz **como verificar**.
- Ordem: **metadata e permissões → teste que falha → código → refatoração →
  revisão**.
- Marcar `[x]` ao concluir. O `tasks.md` é o registro de progresso; se a
  sessão cair, retomar pela primeira task aberta.

---

## 8. Fase 4 — Implementação

- **Test-first por AC:** escrever o teste, ver falhar pelo motivo certo,
  implementar o mínimo até passar, refatorar.
- Implementar **somente** o que está no plan. Melhoria fora do plan vira
  sugestão no final, não código.
- Cada teste referencia o requisito no nome e no comentário:
  `// AC-001 / REQ-001` e `cepLookupFillsAddress_AC001`.
- Rodar testes após cada task relevante:
  ```bash
  sf apex run test --target-org estudos27 --class-names <Class>Test --code-coverage --result-format human --wait 10
  npm run lint && npm test            # quando houver LWC/JS
  ```
- Ao terminar o código, acionar o agente `apex-reviewer` (Apex) e/ou
  `lwc-reviewer` (LWC) e tratar os achados antes da verificação.
- Deploy sempre escopado aos componentes do plan, primeiro em dry-run:
  ```bash
  sf project deploy start --source-dir <caminhos do plan> --target-org estudos27 --dry-run
  ```
  Deploy real **só após confirmação explícita** do usuário.
- Nunca deletar metadata nem usar `destructiveChanges.xml` sem confirmação.
- Commits (somente quando pedido) em Conventional Commits citando a spec:
  `docs(spec): 004 account cep lookup`, `feat(apex): 004 REQ-001 fill address`.

---

## 9. Fase 5 — Verificação (convergência spec ↔ código)

Antes de dizer que terminou, entregar o checklist preenchido:

- [ ] Constitution Check do plan continua válido para o código entregue.
- [ ] Matriz de rastreabilidade completa (abaixo): todo REQ tem implementação
      **e** teste que passa.
- [ ] Todos os testes passam; cobertura por classe informada (mínimo 75%,
      meta 90% para código novo).
- [ ] Testes cobrem positivo, negativo, bulk (200+) e `System.runAs`.
- [ ] Sem SOQL/DML em loop; sharing e USER_MODE aplicados.
- [ ] Permission Set atualizado para todo campo/objeto/classe novo.
- [ ] Achados do reviewer tratados ou justificados.
- [ ] Deploy `--dry-run` escopado sem erro.
- [ ] `spec.md` (status `Implementada`), `plan.md` e `tasks.md` refletem o que
      foi realmente entregue.

```markdown
| REQ     | AC     | Componente                 | Teste                                 | Resultado |
| ------- | ------ | -------------------------- | ------------------------------------- | --------- |
| REQ-001 | AC-001 | AccountService.fillAddress | AccountServiceTest.fillsAddress_AC001 | ✅        |
```

E três listas, sempre:

1. **O que foi feito e conferido** (com evidência: teste, comando, saída).
2. **O que foi feito mas não foi conferido.**
3. **O que foi assumido sem o usuário ter dito.**

---

## 10. Mudanças e bugs

- **Mudança de requisito:** atualizar `spec.md` (novo REQ ou REQ revisado;
  nunca apagar histórico — riscar e registrar em "Histórico de mudanças") →
  ajustar `plan.md` → novas tasks → código. Spec `Implementada` que muda volta
  para `Em implementação`.
- **Bug:** registrar o comportamento esperado como novo AC na spec da feature
  (ou criar `specs/<NNN>-fix-<slug>/spec.md` curta), reproduzir com teste que
  falha, corrigir, provar que passa.
- **Feature sem spec (legado):** spec **as-is** primeiro, depois **to-be**.

---

## 11. O que NÃO fazer

- Começar a codar porque "é rápido".
- Decidir regra de negócio sozinho em vez de marcar `[DÚVIDA]`.
- Colocar decisão técnica na spec ou requisito novo no plan.
- Deixar spec e código divergirem ao final da entrega.
- Criar classe, LWC ou Flow sem checar se já existe algo parecido.
- Fazer deploy de `force-app` inteiro ou deploy real sem confirmação.
- Rodar qualquer comando contra outra org que não seja `estudos27`.
- Declarar "pronto" sem evidência de teste.
