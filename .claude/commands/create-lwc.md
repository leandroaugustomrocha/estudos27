---
description: Gera um bundle LWC completo (HTML, JS, CSS, XML, Controller Apex, classe de teste Apex e teste unitário Jest) seguindo boas práticas Salesforce.
---

Atue como um Salesforce Full-Stack Architect sênior. Crie um Lightning Web Component completo com base nos requisitos informados em `$ARGUMENTS` (se algum detalhe estiver faltando, pergunte antes ou adote padrões seguros e informe ao final).

### 1. Estrutura de Arquivos a Criar

Gere todos os arquivos na estrutura padrão SFDX (`force-app/main/default/`):

- `lwc/<nomeComponente>/<nomeComponente>.html`
- `lwc/<nomeComponente>/<nomeComponente>.js`
- `lwc/<nomeComponente>/<nomeComponente>.css` (se necessário estilização SLDS limpa)
- `lwc/<nomeComponente>/<nomeComponente>.js-meta.xml`
- `lwc/<nomeComponente>/__tests__/<nomeComponente>.test.js`
- `classes/<NomeComponente>Controller.cls` e `.cls-meta.xml`
- `classes/<NomeComponente>ControllerTest.cls` e `.cls-meta.xml`

### 2. Padrões Obrigatórios (Backend Apex)

- Use `public with sharing class` no Controller.
- Métodos de leitura devem usar `@AuraEnabled(cacheable=true)` e aplicar `WITH USER_MODE` nas queries SOQL.
- Métodos imperativos (DML) devem usar `Security.stripInaccessible()` ou DML `as user` e capturar exceções lançando `new AuraHandledException(e.getMessage())`.
- Crie a classe de teste com `@TestSetup`, cenários positivos/negativos e `System.Assert`.

### 3. Padrões Obrigatórios (Frontend LWC)

- Utilize Lightning Base Components (`lightning-card`, `lightning-datatable`, `lightning-record-edit-form`, etc.) e SLDS.
- Gerencie estado de carregamento com `lightning-spinner` (`isLoading = true/false` sempre resetado no bloco `finally`).
- Exiba feedbacks visuais padronizados com `ShowToastEvent` (`lightning/platformShowToastEvent`).
- Configure o `.js-meta.xml` com `isExposed` = `true`, API Version atual do projeto (`sfdx-project.json`) e os `targets` adequados (`lightning__RecordPage`, `lightning__AppPage`, `lightning__HomePage`).

### 4. Testes e Validação

- Crie testes unitários Jest cobrindo renderização inicial, retorno de dados mockados e disparo de toast em caso de erro.
- Ao finalizar, execute no terminal:
  1. `npm run test:unit` (se o script Jest existir no `package.json`)
  2. `sf project deploy start --source-dir force-app/main/default/lwc/<nomeComponente> --source-dir force-app/main/default/classes/<NomeComponente>Controller* --dry-run`
- Corrija imediatamente qualquer erro de lint, compilação ou teste antes de concluir.
