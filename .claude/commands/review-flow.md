---
description: Audita arquivos .flow-meta.xml em busca de DML/SOQL em loops, falta de Fault Connectors e riscos de recursão.
---

Atue como um especialista em automação Salesforce. Analise o arquivo de metadado XML informado em `$ARGUMENTS` (se nenhum argumento for passado, busque arquivos `.flow-meta.xml` alterados no `git status` ou `git diff`).

Faça a leitura estrutural do XML e verifique os seguintes pontos:

### 1. Riscos de Governor Limits

- **SOQL/DML em Loops:** Verifique se existem elementos `<recordLookups>`, `<recordUpdates>`, `<recordCreates>` ou `<recordDeletes>` conectados dentro do caminho de iteração (`<nextValueConnector>`) de qualquer elemento `<loops>`.
- **Queries excessivas:** Verifique se múltiplos `Get Records` no mesmo objeto podem ser consolidados ou filtrados melhor.

### 2. Tratamento de Erros e Resiliência

- **Fault Connectors:** Verifique se todos os elementos de DML (`recordCreates`, `recordUpdates`, `recordDeletes`) e `actionCalls` possuem um `<faultConnector>` configurado para logar ou tratar falhas.
- **Null Checks:** Verifique se o Flow valida se um `Get Records` retornou nulo antes de acessar campos do registro em elementos de `Decision` ou `Assignment`.

### 3. Performance e Arquitetura (Record-Triggered Flows)

- Verifique o `<triggerType>` (`RecordBeforeSave` vs `RecordAfterSave`). Se o Flow apenas atualiza campos do próprio registro que disparou o gatilho e está como `AfterSave`, recomende mudar para `BeforeSave` (Fast Field Updates).
- Verifique se há condições de entrada (`<filters>` ou `<filterFormula>`) bem definidas para evitar execuções desnecessárias a cada edição do registro.
- Procure por IDs hardcoded em filtros ou atribuições.

---

### Formato de Saída Obrigatório:

1. **Resumo do Flow:** Tipo, objeto gatilho, momento de execução e objetivo em 3 linhas.
2. **Diagnóstico de Riscos:** Liste cada achado indicando o **Nome da API do Elemento** no Flow, a **Severidade** (Crítico / Atenção / Boas Práticas) e a **Solução recomendada**.
3. **Nota de Prontidão para Deploy:** Classifique como _Aprovado_, _Aprovado com ressalvas_ ou _Bloqueado_.
