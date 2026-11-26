---
inclusion: always
---

# Processo SDD no Kiro — projeto estudos27

A Constituição e as regras de código estão em `AGENTS.md` (sempre carregado).
Este arquivo só traduz o processo SDD do projeto para o formato de spec do
Kiro. O mesmo processo, para o Claude Code, está em `CLAUDE.md`: os dois devem
continuar coerentes.

## 1. Classificar o pedido antes de começar

Dizer a classificação ao usuário. Na dúvida entre dois níveis, usar o maior.

| Nível   | Exemplos                                | Modo no Kiro                        | Artefatos                                           |
| ------- | --------------------------------------- | ----------------------------------- | --------------------------------------------------- |
| Trivial | typo, label, help text, doc             | Vibe                                | nenhum (dizer o motivo)                             |
| Pequeno | 1 campo + validação, ajuste em 1 método | Spec                                | requirements.md curto + design.md mínimo + tasks.md |
| Padrão  | feature, automação, integração, LWC     | Spec                                | requirements.md + design.md completo + tasks.md     |
| Bug     | comportamento divergente                | Spec (ou AC novo na spec existente) | requirements.md com o comportamento esperado        |

## 2. Mapeamento de artefatos

Specs ficam em `.kiro/specs/<NNN>-<slug>/` (NNN sequencial, slug kebab-case em
inglês; verificar o maior número existente antes de criar).

| Processo do projeto | Arquivo no Kiro | Conteúdo                                                                                                            |
| ------------------- | --------------- | ------------------------------------------------------------------------------------------------------------------- |
| spec.md (o QUÊ)     | requirements.md | Objetivo, contexto atual, personas, REQs EARS, ACs, NFRs, fora de escopo, dúvidas                                   |
| plan.md (o COMO)    | design.md       | Constitution Check no topo, decisão de automação, reuso, modelo de dados, inventário de componentes, testes, deploy |
| tasks.md            | tasks.md        | Tasks com [REQ]/[AC] e "como verificar"                                                                             |

## 3. requirements.md

- Status no topo: `Rascunho` → `Aprovada (data)` → `Em implementação` → `Implementada (data)`.
- REQ-001, REQ-002… em EARS (QUANDO / ENQUANTO / SE…ENTÃO … O SISTEMA DEVE),
  atômicos e testáveis. IDs estáveis: nunca renumerar; REQ removido é riscado.
- AC-001 (REQ-001): Given/When/Then. Todo REQ tem AC; todo AC aponta para REQ.
- Sem decisão técnica: não citar classe, trigger, Flow ou LWC.
- Caminhos de erro: avaliar, virar REQ só os que se aplicam; os demais vão para
  "Fora de escopo" ou viram `[DÚVIDA]`.
- "Fora de escopo" é obrigatório.
- `[DÚVIDA]`: perguntar uma por vez, com opções e recomendação. Só pedir
  aprovação sem nenhuma `[DÚVIDA]` aberta.

## 4. design.md

Começar com:

1. **Constitution Check** — tabela com os princípios 1–10 do `AGENTS.md`:
   atende / justificativa da exceção.
2. **Inventário de componentes** — tipo, nome, criar/alterar, REQ atendido.
   Componente sem REQ não entra.

Depois, conforme o nível:

- **Pequeno:** só os dois itens acima + plano de testes (AC → método).
- **Padrão:** também decisão de automação (Flow/Apex/LWC e por quê), reuso,
  modelo de dados, segurança (sharing, USER_MODE, Permission Set), automações
  existentes no objeto e ordem de execução, orçamento de governor limits para
  200 registros, plano de testes, deploy escopado e rollback, riscos.
  Seções de assíncrono/integração só se a spec pedir.

## 5. tasks.md

- Ordem: metadata e Permission Set → teste que falha → código → refatoração → revisão.
- Cada task cita [REQ-xxx]/[AC-xxx] e diz como verificar. Task sem REQ/AC não existe.
- Executar uma task por vez; marcar [x] ao concluir.

## 6. Antes de escrever a spec (contexto)

- Ler `agent_docs/business-rules.md` e specs anteriores em `.kiro/specs/` sobre os mesmos objetos.
- Procurar em `force-app/` o que já existe: objetos, campos, triggers, handlers,
  services, selectors, LWCs, Flows, Permission Sets, Labels, Custom Metadata.
- Mapear toda automação existente no objeto (triggers, Flows, validation rules).
- Dado da org só por consulta somente leitura na `estudos27`.
- Código legado sem spec: spec as-is primeiro, depois to-be.

## 7. Implementação

- Test-first por AC. Nome do teste com o AC: `cepLookupFillsAddress_AC001`.
- Implementar somente o que está no design. Melhoria fora dele vira sugestão no final.
- Se a implementação contradiz a spec: parar, propor a mudança, esperar aprovação.
- Testes: `sf apex run test --target-org estudos27 --class-names <Class>Test --code-coverage --result-format human --wait 10`
- Deploy: `sf project deploy start --source-dir <caminhos do design> --target-org estudos27 --dry-run`.
  Nunca `force-app` inteiro. Deploy real só com confirmação.

## 8. Verificação final (obrigatória antes de dizer "pronto")

- Matriz REQ | AC | Componente | Teste | Resultado.
- Cobertura por classe (mínimo 75%, meta 90% em código novo).
- Constitution Check continua válido; dry-run escopado sem erro.
- Status do requirements.md atualizado; design.md e tasks.md refletem o entregue.

E sempre três listas:

1. O que foi feito e conferido (com evidência: teste, comando, saída).
2. O que foi feito mas não foi conferido.
3. O que foi assumido sem o usuário ter dito.
