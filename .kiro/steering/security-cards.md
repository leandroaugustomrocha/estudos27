---
inclusion: always
---

# Segurança — domínio de cartão de crédito

## Dados sensíveis (PCI DSS / LGPD)

- NUNCA armazenar, logar, exibir ou trafegar PAN completo, CVV, data de
  validade completa, senha ou trilha do cartão.
- Cartão é sempre referenciado por token ou pelos 4 últimos dígitos.
- CPF, renda e limite: nunca em System.debug, mensagens de erro, toast ou
  payload de log. Em exceções, mensagem genérica para o usuário.
- Não criar campos novos para dados sensíveis sem a história pedir
  (e indicar criptografia/Shield).

## Acesso a dados

- SOQL em contexto de usuário: WITH USER_MODE.
- DML em contexto de usuário: Database.insert(records, AccessLevel.USER_MODE)
  ou Security.stripInaccessible antes do DML.
- @AuraEnabled sempre em classe `with sharing`.
- Sem SOQL dinâmico com input do usuário concatenado; usar bind variables.

## Integrações

- Endpoints sempre via Named Credential existente (<NomeNamedCredential>).
  Nunca URL, token ou secret em código, Custom Label ou Custom Setting.
- Payloads de request/response não são logados inteiros.

## Proibido sem aprovação explícita na história

- without sharing, permissões novas em Profile/Permission Set,
  alteração de sharing rules, OWD ou Remote Site Settings.
