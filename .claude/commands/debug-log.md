---
description: Analisa arquivos .log de execução do Apex para identificar gargalos de governor limits, queries lentas, recursões e exceções.
---

Atue como um especialista em performance e troubleshooting Salesforce. Leia e analise o arquivo de log informado em `$ARGUMENTS` (caso nenhum arquivo seja informado, procure pelo arquivo `.log` mais recente na raiz do projeto ou na pasta `.sfdx/tools/debug/logs/`).

Faça uma varredura técnica detalhada no log buscando:

### 1. Exceções e Erros Fatais

- Localize eventos `EXCEPTION_THROWN`, `FATAL_ERROR` ou `VALIDATION_FAIL`.
- Extraia o tipo da exceção, a mensagem exata e o stack trace completo (classe, método e linha onde ocorreu a falha).

### 2. Consumo de Governor Limits (`LIMIT_USAGE_FOR_NS`)

- Analise os blocos finais de resumo de limites no log.
- Destaque qualquer métrica que ultrapassou **70% do limite** (especialmente `Number of SOQL queries`, `Number of DML statements`, `Maximum CPU time` e `Maximum heap size`).

### 3. Gargalos de Performance e Recursão

- Conte quantas vezes os mesmos métodos, triggers ou queries (`SOQL_EXECUTE_BEGIN`) são repetidos consecutivamente para detectar loops de recursão entre Triggers e Flows.
- Identifique queries SOQL que retornaram grande volume de linhas (`SOQL_EXECUTE_END`) ou demoraram mais tempo entre início e fim.

---

### Formato de Saída Obrigatório:

1. **Causa Raiz (Resumo Executivo):** O que quebrou ou deixou a transação lenta em até 3 frases.
2. **Raio-X de Limites:** Tabela mostrando os principais recursos consumidos vs. limite máximo da plataforma.
3. **Linha do Tempo do Problema:** Os eventos exatos (com timestamp/linha do log) que levaram ao erro ou gargalo.
4. **Plano de Correção:** O que alterar no código Apex ou no Flow para resolver o problema definitivamente.
