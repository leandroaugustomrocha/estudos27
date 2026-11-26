---
inclusion: fileMatch
fileMatchPattern: "force-app/**"
---

# Convenções Salesforce da squad

Siga os padrões JÁ EXISTENTES no repositório. Antes de criar algo, procure
um arquivo semelhante em force-app/ e copie a abordagem dele.

## Apex — geral

- API version: <62.0>. Classes: `with sharing` por padrão;
  `without sharing` só com justificativa escrita na história.
- Nomenclatura: <Objeto>TriggerHandler, <Objeto>Service, <Funcionalidade>Controller (LWC),
  <Classe>Test. Sem prefixos/sufixos inventados.
- Queries: SOQL inline na classe de serviço. NÃO usamos camada Selector.
- Sempre bulkificado: sem SOQL/DML dentro de loop.
- Sem hardcode de Ids, RecordTypeIds ou URLs. RecordType via
  Schema.SObjectType.<Obj>.getRecordTypeInfosByDeveloperName().
- Exceções: usar <NomeDaExceptionCustomExistente>; não criar novas classes de exceção.

## Triggers

- Um trigger por objeto, sem lógica: delega para o handler.
- Framework: <NomeDaClasseBaseDoHandler>. Exemplo existente:
  force-app/main/default/classes/<ExemploTriggerHandler>.cls
- Novo comportamento = novo método no handler existente do objeto.

## Testes

- Dados via <TestDataFactory> existente. Se faltar um método, adicione nela;
  não crie outra factory.
- @TestSetup quando os dados forem reutilizados.
- Um método de teste por critério de aceite, nomeado deve<Comportamento>_CA<n>.
- Assert.areEqual / Assert.isTrue com mensagem. Nada de System.assert sem mensagem.
- Cobertura mínima da classe: 85%. Testar cenário positivo, negativo e bulk (200 registros)
  APENAS para o que a história cobre.

## LWC

- Chamadas Apex: @wire para leitura com cache; imperativo para ações.
- Erros: usar o utilitário existente <c/errorUtils> + ShowToastEvent. Não criar outro.
- Labels: Custom Labels para textos visíveis. Sem texto hardcoded em pt-BR no HTML.
- Estilo: SLDS. Sem CSS customizado se houver classe SLDS equivalente.
- Sem bibliotecas externas / static resources novos.

## Flows

- Não converter Flow existente em Apex (nem o contrário) se a história não pedir.
