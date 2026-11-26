---
description: Valida metadados locais, verifica pendências no Git e executa um dry-run de deploy e testes via Salesforce CLI antes de abrir um PR.
---

Atue como um engenheiro de DevOps / Release Manager Salesforce. Execute uma verificação completa de pré-deploy no projeto atual (ou nos arquivos específicos passados em `$ARGUMENTS`).

Siga esta sequência de etapas no terminal:

### 1. Auditoria Rápida de Repositório

- Execute `git status` para listar arquivos modificados, adicionados ou não rastreados em `force-app/`.
- Verifique se algum arquivo `.cls`, `.trigger`, `.js` (LWC) ou `.flow-meta.xml` está sem seu respectivo arquivo `-meta.xml` acompanhando no diretório.
- Verifique rapidamente se não há credenciais, tokens ou IDs hardcoded óbvios nos arquivos alterados.

### 2. Validação de Deploy (Dry-Run)

- Identifique a org padrão configurada (`sf org display`).
- Caso existam classes de teste relacionadas aos arquivos modificados, monte e execute o comando de validação:
  ```bash
  sf project deploy start --dry-run --source-dir force-app --test-level RunLocalTests --wait 10
  ```
  _(Nota: Se `$ARGUMENTS` especificar caminhos ou testes específicos, ajuste `--source-dir` e use `--test-level RunSpecifiedTests --tests ...` para agilizar)._

### 3. Diagnóstico e Correção

- Se o comando retornar erros de compilação, dependências faltantes ou falhas em testes unitários:
  1. Liste claramente cada erro (Componente, Linha e Mensagem).
  2. Explique a causa raiz.
  3. Pergunte se deseja que eu corrija os problemas apontados e rode a validação novamente.
- Se a validação passar 100%, exiba um resumo pronto para ser colado na descrição do Pull Request (arquivos validados, cobertura de testes e status do check).
