# 002 — Cadastro de clientes com busca de CEP

> Status: Implementada (2026-11-26) — deploy na estudos27 com 52/52 testes Apex
> Nível: Padrão

## Objetivo

Permitir cadastrar clientes com endereço brasileiro completo digitando só o CEP, o
número e o complemento: o sistema busca o restante do endereço num serviço público de
CEP. Sucesso = endereços padronizados, com menos erros de digitação, e o cadastro
continua possível mesmo quando o serviço de CEP falha.

## Contexto atual

Projeto novo. Verificado em 2026-11-26: não há objeto de cliente próprio, credencial de
serviço externo nem classe relacionada a CEP na org `estudos27`. Existe localmente uma
classe antiga, `ZipCodeName`, que consulta uma API americana de CEP com endpoint e chave
fixos no código e sem testes; ela **não** será reaproveitada (outro país, outro serviço,
fora do padrão do projeto).

## Personas e permissões

| Persona                       | Pode                                                                                                                             | Não pode                                                                                             |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| Usuário de clientes           | Ver todos os clientes; cadastrar clientes; editar e excluir os clientes que cadastrou; ver o CPF/CNPJ dos clientes que cadastrou | Editar ou excluir clientes cadastrados por outros; ver o CPF/CNPJ de clientes cadastrados por outros |
| Administrador de clientes     | Tudo o que o usuário pode; editar e excluir qualquer cliente; ver o CPF/CNPJ de todos                                            | —                                                                                                    |
| Usuário sem acesso ao recurso | —                                                                                                                                | Ver, cadastrar ou editar clientes                                                                    |

## Requisitos funcionais

### Cadastro

- REQ-001: O SISTEMA DEVE permitir cadastrar um cliente com nome (obrigatório), e-mail e
  telefone (opcionais), CPF/CNPJ (obrigatório) e endereço: CEP, logradouro, número,
  complemento, bairro, cidade e UF.
- REQ-023: O SISTEMA DEVE permitir salvar um cliente com o CEP em branco, em qualquer
  situação (tela ou importação); nesse caso nenhuma busca é feita e os demais campos de
  endereço podem ser digitados à mão. Um CEP **informado** que não existe é sempre barrado
  (REQ-006, REQ-008).
- REQ-012: SE o e-mail for informado num formato inválido, ENTÃO O SISTEMA DEVE rejeitar o
  cadastro com a mensagem "Informe um e-mail válido."
- REQ-013: SE o telefone for informado sem 10 ou 11 dígitos (DDD + número), ENTÃO O
  SISTEMA DEVE rejeitar o cadastro com a mensagem "Informe um telefone com DDD (10 ou 11
  dígitos)."; o telefone válido é guardado no formato `(00) 0000-0000` ou
  `(00) 00000-0000`.

### Documento (CPF/CNPJ)

- REQ-014: O SISTEMA DEVE aceitar CPF (11 dígitos) ou CNPJ (14 caracteres, incluindo o
  CNPJ alfanumérico em vigor desde julho de 2026), com ou sem pontuação, identificar o
  tipo de pessoa (Física para CPF, Jurídica para CNPJ) e guardar o documento formatado:
  `000.000.000-00` ou `AA.AAA.AAA/AAAA-00`.
- REQ-015: SE os dígitos verificadores do CPF/CNPJ não conferirem, ou o documento tiver
  todos os caracteres iguais, ENTÃO O SISTEMA DEVE rejeitar o cadastro com a mensagem
  "CPF/CNPJ inválido."
- REQ-016: SE já existir outro cliente com o mesmo CPF/CNPJ, ENTÃO O SISTEMA DEVE rejeitar
  o cadastro com a mensagem "Já existe um cliente com este CPF/CNPJ." A comparação ignora
  a pontuação.
- REQ-017: SE o CPF/CNPJ não for informado, ENTÃO O SISTEMA DEVE rejeitar o cadastro com a
  mensagem "Informe o CPF ou CNPJ do cliente."
- REQ-002: O SISTEMA DEVE aceitar o CEP com ou sem hífen e guardá-lo sempre no formato
  `00000-000`.

### Busca de CEP

- REQ-003: QUANDO o usuário completar os 8 dígitos do CEP no cadastro, O SISTEMA DEVE
  consultar o serviço de CEP automaticamente (sem botão) e substituir logradouro, bairro,
  cidade e UF pelos valores do CEP, mesmo que já estivessem preenchidos.
- REQ-004: O SISTEMA DEVE deixar número e complemento para o usuário preencher; eles nunca
  vêm da busca nem são apagados por ela.
- REQ-018: O SISTEMA DEVE permitir ajustar logradouro e bairro depois da busca (CEPs gerais
  de cidade vêm sem rua e sem bairro), mas cidade e UF ficam travados no valor retornado
  pelo CEP (exceto quando o serviço está fora do ar, REQ-007).
- REQ-019: QUANDO o usuário alterar o CEP de um cliente, O SISTEMA DEVE refazer a busca e
  substituir logradouro, bairro, cidade e UF pelos do novo CEP.
- REQ-005: SE o CEP não tiver 8 dígitos, ENTÃO O SISTEMA DEVE mostrar "Informe um CEP com
  8 dígitos." sem consultar o serviço.
- REQ-006: SE o serviço informar que o CEP não existe, ENTÃO O SISTEMA DEVE mostrar "CEP
  não encontrado. Confira o número digitado." e impedir o salvamento enquanto o CEP não
  for corrigido.
- REQ-007: SE o serviço de CEP não responder ou responder com erro, ENTÃO O SISTEMA DEVE
  mostrar "Não foi possível consultar o CEP agora. Preencha o endereço manualmente ou
  tente de novo.", liberar todos os campos de endereço (inclusive cidade e UF) para
  preenchimento manual e permitir salvar o cliente com o endereço digitado.

### Permissões

- REQ-009: O SISTEMA DEVE permitir que todo usuário de clientes veja todos os clientes,
  mas SE ele tentar editar ou excluir um cliente que não cadastrou, ENTÃO O SISTEMA DEVE
  negar a operação.
- REQ-010: O SISTEMA DEVE permitir que o administrador de clientes edite e exclua
  qualquer cliente.
- REQ-011: SE um usuário sem acesso ao recurso tentar ver ou cadastrar clientes, ENTÃO O
  SISTEMA DEVE negar a operação.
- REQ-022: O SISTEMA DEVE mostrar o CPF/CNPJ de um cliente somente para quem o cadastrou e
  para o administrador de clientes; os demais usuários não veem o documento em nenhuma
  tela, lista, relatório, busca ou exportação (o restante do cliente continua visível
  para eles, REQ-009). A mensagem de duplicidade (REQ-016) não revela qual cliente já usa
  o documento.

### Acesso à tela de cadastro

- REQ-026: O SISTEMA DEVE oferecer a tela de cadastro com busca de CEP na hora pela aba
  "Novo cliente" e pela ação "Editar cliente" na página do cliente, e não deve oferecer o
  "Editar" padrão na página do cliente. O botão padrão "Novo" da lista de clientes
  continua existindo (limitação da plataforma) e segue o REQ-008.

### Carga em massa

- REQ-008: QUANDO clientes forem criados, ou tiverem o CEP alterado, fora da tela de
  cadastro (importação, integração ou o botão padrão "Novo" da lista de clientes, até 200
  por operação), O SISTEMA DEVE salvá-los na
  hora e, em segundo plano, buscar cada CEP e preencher **apenas** os campos de
  logradouro, bairro, cidade e UF que estiverem vazios. ~~SE essa busca falhar (CEP não
  encontrado ou serviço fora do ar), ENTÃO O SISTEMA DEVE manter o cliente como foi
  importado, sem erro nem marcação.~~ (substituído em 2026-11-26 por REQ-024 e REQ-025)
- REQ-024: SE a busca em segundo plano informar que o CEP não existe, ENTÃO O SISTEMA DEVE
  apagar o CEP do cliente (que fica em branco, o que é permitido pelo REQ-023), manter o
  restante do cliente como foi importado e registrar no cliente a observação "CEP
  <CEP> removido em <data>: CEP não encontrado."
- REQ-025: SE o serviço de CEP estiver fora do ar durante a busca em segundo plano, ENTÃO
  O SISTEMA DEVE manter o cliente como foi importado, sem erro nem observação.
- REQ-020: O SISTEMA DEVE aplicar as validações de CEP, e-mail, telefone e CPF/CNPJ
  (REQ-002, REQ-005, REQ-012 a REQ-017) também em importações, a cada registro, com a
  mensagem própria de cada erro, salvando os registros válidos.
- REQ-021: SE o mesmo CPF/CNPJ aparecer mais de uma vez no mesmo lote, ENTÃO O SISTEMA DEVE
  manter o primeiro e rejeitar os seguintes com a mensagem "Já existe um cliente com este
  CPF/CNPJ."

### Exclusão e restauração

- REQ-027: QUANDO um cliente for excluído, O SISTEMA DEVE excluir também o CPF/CNPJ dele,
  de modo que o documento possa ser usado num novo cadastro (REQ-016).
- REQ-028: QUANDO um cliente for restaurado da Lixeira, O SISTEMA DEVE restaurar o CPF/CNPJ
  dele junto; SE, nesse meio-tempo, outro cliente tiver sido cadastrado com o mesmo
  documento, ENTÃO O SISTEMA DEVE negar a restauração com a mensagem "Já existe um cliente
  com este CPF/CNPJ."

## Critérios de aceite (Given/When/Then)

- AC-001 (REQ-001): Dado um usuário com permissão de cadastro, quando cria um cliente com
  nome e endereço completos, então o cliente é salvo.
- AC-012 (REQ-012): Dado o e-mail `maria@exemplo`, quando o cliente é salvo, então recebe
  "Informe um e-mail válido."
- AC-013 (REQ-013): Dado o telefone `11987654321`, quando o cliente é salvo, então ele fica
  como `(11) 98765-4321`; dado `98765-4321` (sem DDD), então recebe "Informe um telefone
  com DDD (10 ou 11 dígitos)."
- AC-014 (REQ-014): Dado o CPF `52998224725`, quando o cliente é salvo, então o documento
  fica `529.982.247-25` e o tipo de pessoa é Física; dado um CNPJ válido sem pontuação
  (numérico ou alfanumérico), então fica no formato `AA.AAA.AAA/AAAA-00` e o tipo é
  Jurídica.
- AC-015 (REQ-015): Dado o CPF `529.982.247-26` (dígito errado) ou `111.111.111-11`, quando
  o cliente é salvo, então recebe "CPF/CNPJ inválido."
- AC-016 (REQ-016): Dado um cliente já cadastrado com o CPF `529.982.247-25`, quando outro
  cliente é salvo com `52998224725`, então recebe "Já existe um cliente com este
  CPF/CNPJ."
- AC-017 (REQ-017): Dado um cliente sem CPF/CNPJ, quando é salvo, então recebe "Informe o
  CPF ou CNPJ do cliente."
- AC-002 (REQ-002): Dado o CEP digitado como `01310100`, quando o cliente é salvo, então o
  CEP fica gravado como `01310-100`.
- AC-003 (REQ-003): Dado o CEP `01310-100`, quando a busca é feita, então logradouro
  "Avenida Paulista", bairro "Bela Vista", cidade "São Paulo" e UF "SP" são preenchidos.
- AC-004 (REQ-004): Dado um endereço preenchido pela busca, quando o usuário informa número
  e complemento, então eles são mantidos como digitados.
- AC-018 (REQ-003): Dado um cadastro em que o usuário digitou logradouro "Rua X" e cidade
  "Campinas", quando completa o CEP `01310-100`, então a busca acontece sem clique e os
  campos passam a "Avenida Paulista" e "São Paulo".
- AC-019 (REQ-018): Dado um endereço preenchido pela busca, quando o usuário ajusta o
  logradouro, então o ajuste é mantido; cidade e UF não podem ser editados.
- AC-020 (REQ-019): Dado um cliente com CEP `01310-100`, número "1000" e complemento
  "Sala 5", quando o usuário troca o CEP para `20040-020`, então logradouro, bairro, cidade
  e UF passam aos do novo CEP (Rio de Janeiro/RJ) e número e complemento continuam.
- AC-005 (REQ-005): Dado o CEP `0131010`, quando o usuário pede a busca, então vê "Informe
  um CEP com 8 dígitos." e o serviço não é consultado.
- AC-006 (REQ-006): Dado o CEP `99999-999`, quando a busca é feita, então vê "CEP não
  encontrado. Confira o número digitado." e não consegue salvar o cliente até corrigir o
  CEP.
- AC-007 (REQ-007): Dado o serviço de CEP fora do ar, quando a busca é feita, então vê a
  mensagem de indisponibilidade, cidade e UF ficam editáveis e o cliente pode ser salvo
  com o endereço digitado à mão.
- AC-029 (REQ-026): Dado um usuário de clientes, quando abre a aba "Novo cliente" ou a
  ação "Editar cliente" na página de um cliente, então usa a tela com busca de CEP na
  hora; a página do cliente não oferece o "Editar" padrão.
- AC-030 (REQ-008): Dado um cliente criado pelo botão padrão "Novo" da lista com CEP
  `01310-100` e endereço vazio, quando é salvo, então fica salvo na hora e o endereço é
  completado em segundo plano.
- AC-021 (REQ-008): Dado um arquivo com um cliente de CEP `01310-100`, cidade "São Paulo"
  preenchida e logradouro, bairro e UF vazios, quando é importado, então o cliente é salvo
  na hora e, depois do processamento em segundo plano, logradouro "Avenida Paulista",
  bairro "Bela Vista" e UF "SP" estão preenchidos e a cidade digitada foi mantida.
- ~~AC-024 (REQ-008)~~ (substituído em 2026-11-26 por AC-027 e AC-028)
- AC-027 (REQ-024): Dado um cliente importado com CEP `99999-999` e cidade "Campinas",
  quando o processamento em segundo plano termina, então o cliente continua salvo, com o
  CEP em branco, a cidade "Campinas" mantida e a observação "CEP 99999-999 removido em
  <data>: CEP não encontrado."
- AC-028 (REQ-025): Dado o serviço de CEP fora do ar, quando um cliente importado com CEP
  `01310-100` e endereço vazio é processado em segundo plano, então ele continua salvo
  com o CEP e o endereço como vieram, sem observação.
- AC-022 (REQ-020): Dado um lote de 200 clientes em que um tem e-mail inválido, quando é
  importado permitindo sucesso parcial, então os 199 válidos são salvos e o inválido
  recebe "Informe um e-mail válido."
- AC-023 (REQ-021): Dado um lote em que dois clientes têm o CPF `529.982.247-25`, quando é
  importado permitindo sucesso parcial, então o primeiro é salvo e o segundo recebe "Já
  existe um cliente com este CPF/CNPJ."
- AC-031 (REQ-027): Dado um cliente com CPF `529.982.247-25` que foi excluído, quando um
  novo cliente é cadastrado com esse CPF, então o cadastro é aceito.
- AC-032 (REQ-028): Dado um cliente excluído com CPF `529.982.247-25`, quando é restaurado
  da Lixeira, então volta com o CPF; dado que outro cliente foi cadastrado com esse CPF
  enquanto ele estava na Lixeira, então a restauração é negada com "Já existe um cliente
  com este CPF/CNPJ."
- AC-008 (REQ-009): Dado um cliente cadastrado pelo usuário A, quando o usuário B
  consulta os clientes, então vê o cliente de A.
- AC-009 (REQ-009): Dado um cliente cadastrado pelo usuário A, quando o usuário B tenta
  editá-lo ou excluí-lo, então a operação é negada.
- AC-010 (REQ-010): Dado um cliente cadastrado pelo usuário A, quando o administrador de
  clientes o edita e depois o exclui, então as duas operações são permitidas.
- AC-011 (REQ-011): Dado um usuário sem acesso ao recurso, quando tenta cadastrar um
  cliente, então a operação é negada.
- AC-025 (REQ-022): Dado um cliente cadastrado pelo usuário A com CPF `529.982.247-25`,
  quando o usuário B abre o cliente, lista os clientes ou busca por ele, então vê nome,
  contatos e endereço, mas não vê o CPF; quando A ou o administrador abrem o cliente,
  então veem o CPF.
- AC-026 (REQ-023): Dado um cadastro sem CEP, quando o cliente é salvo pela tela ou por
  importação, então é salvo sem busca de CEP.

## Requisitos não funcionais

- Desempenho: a busca deve responder em até 120 segundos; depois disso conta como
  indisponível (REQ-007). Enquanto a busca não termina, a tela mostra que está buscando.
- Segurança e privacidade: dados de clientes são pessoais (LGPD); só quem tem acesso ao
  recurso vê clientes (REQ-009 a REQ-011) e o CPF/CNPJ só é visível para quem cadastrou e
  para o administrador (REQ-022). Nenhum dado do cliente é enviado ao serviço de CEP além
  do próprio CEP.
- Serviço externo: público e gratuito, sem credencial; o endereço do serviço deve ser
  configurável sem mudança de código.
- Volume: até 200 clientes por operação; a busca em segundo plano de um lote de 200 pode
  levar alguns minutos.
- Mensagens ao usuário: em português, com os textos definidos nos REQs.

## Dados envolvidos (nível de negócio)

- **Cliente:** nome, e-mail, telefone, CPF/CNPJ, tipo de pessoa (Física/Jurídica), CEP,
  logradouro, número, complemento,
  bairro, cidade, UF, observação sobre o endereço (CEP removido pela busca em segundo plano).

## Fora de escopo

- Vários endereços por cliente (entrega, cobrança…).
- Busca inversa (descobrir o CEP a partir do endereço).
- Mapa, geolocalização ou cálculo de distância/frete.
- Serviços de CEP pagos ou que exijam credencial.
- Revalidar depois, automaticamente, endereços digitados à mão enquanto o serviço estava
  fora do ar.
- Uso de Account/Contact padrão do Salesforce.
- Consulta à Receita Federal (situação cadastral, razão social) — o documento só é
  validado pelo cálculo dos dígitos verificadores.

## Dúvidas em aberto

- ~~[DÚVIDA D1]~~ Resolvida em 2026-11-26: todos veem, quem cadastrou edita e exclui,
  administrador gerencia todos (REQ-009 a REQ-011).
- ~~[DÚVIDA D2]~~ Resolvida em 2026-11-26: e-mail, telefone e CPF/CNPJ (REQ-001,
  REQ-012 a REQ-016).
- ~~[DÚVIDA D2b]~~ Resolvida em 2026-11-26: CPF/CNPJ obrigatório (REQ-001, REQ-017).
- ~~[DÚVIDA D3]~~ Resolvida em 2026-11-26: busca automática ao completar o CEP, substitui
  logradouro, bairro, cidade e UF; logradouro e bairro ajustáveis, cidade e UF travados
  (REQ-003, REQ-018, REQ-019).
- ~~[DÚVIDA D4]~~ Resolvida em 2026-11-26: serviço fora do ar libera o preenchimento manual;
  CEP não encontrado bloqueia o salvamento (REQ-006, REQ-007, REQ-018).
- ~~[DÚVIDA D5]~~ Resolvida em 2026-11-26: importações completam em segundo plano só os
  campos de endereço vazios; validações valem em massa; documento repetido no lote: o
  primeiro vence (REQ-008, REQ-020, REQ-021).
- ~~[DÚVIDA D5b]~~ Resolvida em 2026-11-26: falhas da busca em segundo plano são ignoradas;
  o cliente fica como foi importado (REQ-008, AC-024). Revista em 2026-11-26: CEP
  inexistente é apagado e registrado em observação; serviço fora do ar continua ignorado
  (REQ-024, REQ-025).

Nenhuma dúvida em aberto.

## Histórico de mudanças

| Data       | Mudança                                                                                                                                                                                                                                                               | Motivo                                                                               |
| ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| 2026-11-26 | Rascunho inicial                                                                                                                                                                                                                                                      | Início do projeto                                                                    |
| 2026-11-26 | Personas definidas; REQ-009 a REQ-011, AC-008 a AC-011                                                                                                                                                                                                                | Resposta à D1                                                                        |
| 2026-11-26 | Dados do cliente: e-mail, telefone, CPF/CNPJ (com CNPJ alfanumérico); REQ-012 a REQ-016, AC-012 a AC-016                                                                                                                                                              | Resposta à D2                                                                        |
| 2026-11-26 | CPF/CNPJ obrigatório; REQ-017, AC-017                                                                                                                                                                                                                                 | Resposta à D2b                                                                       |
| 2026-11-26 | Busca automática que sobrescreve; REQ-018, REQ-019, AC-018 a AC-020                                                                                                                                                                                                   | Resposta à D3                                                                        |
| 2026-11-26 | Falha da busca: manual só com serviço fora do ar; CEP inexistente bloqueia                                                                                                                                                                                            | Resposta à D4                                                                        |
| 2026-11-26 | Importação completa só campos vazios em segundo plano; REQ-008, REQ-020, REQ-021, AC-021 a AC-023                                                                                                                                                                     | Resposta à D5                                                                        |
| 2026-11-26 | Falhas da busca em segundo plano ignoradas; AC-024                                                                                                                                                                                                                    | Resposta à D5b                                                                       |
| 2026-11-26 | Busca até 120 s; CPF/CNPJ visível só ao dono e ao administrador (REQ-022, AC-025); CEP em branco sempre permitido (REQ-023, AC-026); CEP inexistente em importação é apagado e registrado (REQ-008 revisto, REQ-024, REQ-025, AC-024 substituído por AC-027 e AC-028) | Respostas do usuário à revisão da spec                                               |
| 2026-11-26 | Spec aprovada                                                                                                                                                                                                                                                         | Aprovação do usuário                                                                 |
| 2026-11-26 | REQ-026 (tela de cadastro por aba e ação; "Editar" padrão removido); REQ-008 inclui o botão padrão "Novo"; AC-029, AC-030                                                                                                                                             | Verificação T02 do plan: LWC não pode substituir New/Edit padrão; decisão do usuário |
| 2026-11-26 | REQ-027 (excluir cliente exclui o documento) e REQ-028 (restaurar cliente restaura o documento, salvo duplicidade); AC-031, AC-032                                                                                                                                    | Revisão do plan pela Constituição nova: regra não estava na spec; decisão do usuário |
| 2026-11-26 | Spec implementada (deploy na estudos27)                                                                                                                                                                                                                               | Deploy confirmado pelo usuário                                                       |
