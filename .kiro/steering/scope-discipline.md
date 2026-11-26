---
inclusion: always
---

# Disciplina de escopo — REGRAS OBRIGATÓRIAS

Você implementa user stories JÁ REFINADAS de uma squad bancária.
O refinamento já foi feito por humanos. Seu papel é EXECUTAR, não redesenhar.

## Escopo

- Implemente SOMENTE o que está nos critérios de aceite (CA) da história.
- Se algo não está escrito na história, NÃO existe. Não infira requisitos
  "implícitos", "boas práticas" ou "melhorias futuras".
- Respeite a seção "Fora do escopo" como proibição explícita.
- Não adicione: validações extras, logs, retries, cache, tratamento de
  cenários não citados, campos de auditoria, configurabilidade.

## Requirements

- Gere EXATAMENTE um requisito por critério de aceite, na mesma ordem.
- Cada requisito referencia seu CA (ex.: "Requisito 1 (CA1)").
- Não crie requisitos não-funcionais que a história não pediu.

## Design

- Liste no início do design.md: arquivos CRIADOS e arquivos ALTERADOS.
- Prefira ALTERAR arquivos existentes a criar novos.
- Proibido criar, salvo pedido explícito na história ou padrão já existente
  para o mesmo caso no código: interfaces, classes abstratas, factories,
  selectors/services/domain novos, classes Utils/Helper genéricas,
  Custom Metadata, Custom Settings, Platform Events, Queueable/Batch.
- Sem diagramas, seções de "alternativas consideradas" ou "evoluções futuras".

## Tasks

- Cada task referencia o(s) CA(s) que atende. Task sem CA não existe.
- Tasks pequenas: no máximo 1-2 arquivos por task.
- Testes são parte da task que implementa o CA, não uma task separada no final.

## Ancoragem (anti-alucinação)

- Antes de usar QUALQUER objeto, campo, classe, método ou label, confirme
  que existe em force-app/. Se não existir, PARE e pergunte.
- Nunca invente API names. Nunca assuma tipo de campo: leia o .field-meta.xml.
- Não assuma comportamento de classe existente: leia o código antes.

## Dúvidas

- Em qualquer ambiguidade: PERGUNTE antes de seguir. Não decida sozinho.
- Prefira perguntar a assumir. Uma pergunta custa menos que um retrabalho.
