---
description: Executa um code review técnico rigoroso em classes e triggers Apex focando em segurança, governor limits e boas práticas.
---

Atue como um Salesforce Technical Architect sênior. Faça um code review completo no arquivo ou diretório informado em `$ARGUMENTS` (se nenhum argumento for passado, analise os arquivos `.cls` e `.trigger` modificados no `git diff`).

Avalie o código seguindo rigorosamente estes critérios:

### 1. Governor Limits & Bulkification

- Verifique se há operações `SOQL`, `SOSL` ou `DML` dentro de loops (`for`, `while`).
- Confirme se o código suporta lotes de 200+ registros sem estourar limites de CPU time ou Heap size.
- Verifique a seletividade das queries SOQL (uso de filtros indexados e ausência de queries sem `WHERE` em objetos grandes).

### 2. Segurança (CRUD / FLS / Sharing)

- Confirme se a classe declara explicitamente `with sharing` ou `inherited sharing` (se usar `without sharing`, exija justificativa).
- Verifique se queries e DMLs aplicam `WITH USER_MODE`, `WITH SECURITY_ENFORCED` ou `Security.stripInaccessible()`.
- Procure por vulnerabilidades de SOQL Injection (concatenação de strings dinâmicas sem `String.escapeSingleQuotes` ou bind variables).

### 3. Arquitetura & Clean Code

- Triggers devem estar livres de lógica de negócio (delegando para uma classe Handler).
- Verifique ausência de IDs hardcoded (`005...`, `012...`, etc.) — sugira Custom Metadata, Custom Labels ou queries dinâmicas.
- Valide o tratamento de exceções (evite blocos `catch` vazios que engolem erros silenciosamente).

### 4. Qualidade dos Testes (se houver classe de teste associada)

- Verifique uso de `@TestSetup`, asserções reais (`System.Assert.areEqual`, `isTrue`, etc.) e cobertura de cenários negativos e em massa.

---

### Formato de Saída Obrigatório:

Apresente o resultado em uma tabela resumida por severidade (**Crítico**, **Alerta**, **Melhoria**) contendo:

1. **Arquivo e Linha**
2. **Categoria** (Segurança, Performance, Arquitetura)
3. **Problema encontrado**
4. **Trecho de código sugerido para correção**

Ao final, pergunte se devo aplicar as correções diretamente nos arquivos.
