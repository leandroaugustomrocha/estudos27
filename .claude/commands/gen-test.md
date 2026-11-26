---
description: Gera uma classe de teste Apex completa com @TestSetup, HttpCalloutMock (se aplicável), cenários positivos/negativos e testes em massa (200+ registros).
---

Atue como um desenvolvedor Salesforce sênior especialista em qualidade de software e testes automatizados. Analise a classe ou trigger Apex informada em `$ARGUMENTS` e crie (ou atualize) a sua respectiva classe de teste dentro de `force-app/main/default/classes/`.

Siga rigorosamente estas diretrizes de implementação:

### 1. Estrutura e Boas Práticas

- Utilize a anotação `@IsTest` na classe e nos métodos.
- Crie um método `@TestSetup` para preparar a massa de dados comum (Accounts, Contacts, Opportunities, etc.) evitando repetição entre os métodos de teste.
- Crie um usuário de teste com perfil específico (ex: `Standard User`) quando o código envolver regras de compartilhamento (`with sharing`) ou permissões FLS/CRUD.
- Nunca dependa de dados reais da org (`SeeAllData=true` é estritamente proibido).
- Utilize `Test.startTest()` e `Test.stopTest()` para isolar os governor limits da execução principal e forçar a finalização de processos assíncronos (`Queueable`, `Batch`, `@future`).

### 2. Cenários de Cobertura Obrigatórios

Garanta uma cobertura acima de 85% cobrindo obrigatoriamente:

- **Cenário Positivo (Caminho Feliz):** Execução padrão com dados válidos e validação dos resultados esperados.
- **Cenário Negativo / Exceções:** Passagem de parâmetros nulos, listas vazias ou dados inválidos que disparam `AuraHandledException` ou exceções customizadas.
- **Teste em Massa (Bulk Test):** Execução com **200 ou mais registros** simultâneos para comprovar que o código não estoura limites de SOQL ou DML.
- **Mocks de Integração:** Se a classe realizar callouts HTTP (`HttpRequest`), implemente uma classe interna ou separada implementando `HttpCalloutMock` para simular respostas de sucesso (200/201) e erro (400/500).

### 3. Asserções Modernas

- Utilize a classe `System.Assert` (`Assert.areEqual`, `Assert.isTrue`, `Assert.isNotNull`, `Assert.fail`) incluindo sempre uma mensagem descritiva clara do que está sendo validado.

### Ação Esperada:

1. Gere o arquivo `[NomeDaClasse]Test.cls` e o seu respectivo `[NomeDaClasse]Test.cls-meta.xml`.
2. Se o Salesforce CLI estiver disponível no ambiente, execute `sf apex run test --tests [NomeDaClasse]Test --result-format human` para validar a compilação e a passagem dos testes.
