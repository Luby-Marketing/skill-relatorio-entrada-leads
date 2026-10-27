---
name: relatorio-entrada-leads
description: 'Relatório de ENTRADA DE LEADS da Luby (formulários do site, landings e reuniões agendadas) lido do Supabase nearsmart, com origem de cada lead, separação de testes, qualificação e lista completa, entregue como documento. Pergunta o período antes de rodar. USE SEMPRE que alguém quiser saber quantos leads entraram, de onde vieram ou quem preencheu formulário ou agendou, mesmo sem dizer "relatório": "quantos leads entraram essa semana?", "relatório de entrada de leads", "de onde estão vindo os leads do site?", "quem preencheu o formulário de contato?", "teve lead pelas landings?", "quem agendou reunião pelo site este mês?", "leads de outubro". Cobre as tabelas contact_tracks_br, contact_tracks_us, contacts_landings, contacts_landings_br e agendamento_luby. NÃO use para campanhas de outbound do motor ob_* (status-campanha-outbound), lista de ligação (lista-cold-call), resultados de Meta Ads ou Google Ads, nem para visitantes identificados pelo Apollo.'
---

# Relatório de entrada de leads

Lê quem entrou pelos canais de inbound da Luby num período, separa os testes dos contatos reais, descobre de onde cada um veio, qualifica e entrega um documento.

É só leitura. Não altere nada no banco, no HubSpot nem em lugar nenhum, mesmo que o relatório aponte algo para corrigir; nesses casos, recomende.

## Fonte

Supabase, projeto `nearsmart`, ref `pbvjsixlqnuzcnqahbxu`, pela ferramenta `execute_sql`.

| Tabela | Entrada | Mercado |
|---|---|---|
| `contact_tracks_br` | Formulário do site luby.com.br | BR |
| `contact_tracks_us` | Formulário do site luby.co | US |
| `contacts_landings_br` | Landings BR e Finfy | BR |
| `contacts_landings` | Landings US | US |
| `agendamento_luby` | Reunião marcada (agendamento.luby.com.br e schedule.luby.co) | coluna `market` |

## Passo 1: perguntar o período

O período muda a leitura inteira, então confirme antes de consultar qualquer coisa.

- Se a pessoa já disse o período ("últimos 7 dias", "outubro", "de 01/10 a 15/10"), use o que ela disse e não pergunte.
- Se não disse, pergunte com `AskUserQuestion` (uma pergunta, cabeçalho "Período"), com as opções **Últimos 7 dias**, **Últimos 15 dias**, **Últimos 30 dias** e **Mês passado**. A pessoa pode digitar outro intervalo no campo livre.
- Sem ninguém para responder (execução agendada), use os últimos 7 dias e diga isso na primeira linha do documento.

Traduza a resposta em duas datas, em BRT, no formato AAAA-MM-DD. Pegue a data de hoje com a ferramenta de hora atual; não confie na sua noção de data.

- "Últimos N dias": início = hoje menos N dias; fim = hoje.
- "Mês passado": primeiro e último dia do mês anterior.
- Um mês pelo nome: primeiro e último dia daquele mês (se for o mês atual, o fim é hoje).
- Intervalo digitado: as duas datas como vieram. Se estiver ambíguo (ex.: "semana passada" sem dizer se começa no domingo ou na segunda), escolha a leitura mais comum e diga qual foi.

## Passo 2: rodar a consulta

Leia `references/consulta.sql`, troque `__INICIO__` e `__FIM__` pelas datas e rode o texto inteiro numa única chamada de `execute_sql`. O período cobre os dias inteiros, de 00:00 do início até 23:59:59 do fim, no fuso de São Paulo.

A consulta devolve só os totais por tabela, as linhas de teste que parecem sondagem externa e as linhas reais completas. Ela é feita assim porque, em semanas de bateria de testes nas landings, só os testes passam de 250 linhas e estouram o limite de saída. Se mesmo assim a saída vier truncada (período longo, muito lead), rode de novo trocando o select final por um que devolva menos colunas, ou divida o período em duas consultas. Não pagine o resultado na conversa.

Depois, leia as linhas reais uma a uma. O filtro de teste é por padrão de texto: pode deixar passar um teste novo (outro e-mail de QA, outro domínio de homologação) ou pegar alguém real cujo nome contenha "test". Corrija na sua contagem e diga no relatório o que ajustou à mão.

## Passo 3: classificar a origem de cada contato real

Aplique na ordem e pare na primeira que bater. A ordem importa: o clique de anúncio é a prova mais forte, e o referrer do próprio site é a mais fraca.

1. `clique_pago` preenchido → **Mídia paga** (Google Ads, Meta ou Microsoft, conforme o valor). Exceção: `fbclid` com `utm_content=link_in_bio` ou referrer instagram.com é **Instagram orgânico** (o link da bio também gera `fbclid`), não anúncio da Meta.
2. `utm_source` preenchida → a fonte da UTM (Clutch, GoodFirms, chatgpt.com etc.). Se `utm_medium` for cpc, paid ou ppc, é mídia paga.
3. Parâmetros na query string de `pagina` (`utm_*`, `gclid`, `fbclid`, `msclkid`) → trate como no item 1 ou 2.
4. `referrer` externo: google ou bing = **Google orgânico** (ou Bing); chatgpt.com, perplexity.ai, gemini.google.com, claude.ai = **IA generativa** (cite qual); clutch, goodfirms, techreviewer = **Diretório**; linkedin = **LinkedIn**; instagram = **Instagram orgânico**; outro domínio = **Referral** (cite o domínio).
5. Agendamento com `pagina` no formato `agendamento.luby.com.br/<host>` ou `schedule.luby.co/<host>` → **Link direto do host**. Com `?landing_page=` → **Site** (anote de qual página veio).
6. `pagina` em finfy.luby.com.br → **Landing Finfy**; em landing.luby.com.br ou landing.luby.co → **Landing** (use o slug da URL).
7. `referrer` do próprio site (luby.com.br, luby.co) ou vazio → **Site, navegação interna**.

Nas tabelas de landing e no agendamento, `pagina` é a coluna `origin_url`; nos formulários do site, é `page_url`. No agendamento, `referrer` traz a `landing_page`.

## Passo 4: qualificar cada contato real

Leia a mensagem e o domínio do e-mail. Os formulários do site não gravam empresa nem cargo, então deduza a empresa pelo domínio e pela mensagem e deixe claro que é dedução. E-mail pessoal (Gmail, Hotmail) não desqualifica sozinho; pese a mensagem.

- **Oportunidade**: empresa com necessidade de software, RFP, concorrência ou projeto. Inclua ideias em estágio inicial, sinalizando o estágio.
- **A qualificar**: mensagem vaga demais para decidir.
- **Parceria**: empresa propondo parceria ou revenda.
- **Fora do perfil**: currículo, pessoa física pedindo crédito ou conta (comum nas páginas da Finfy).

Qualifique a **pessoa**, não a linha. A chave `pessoas` da consulta junta as linhas reais pelo e-mail; uma pessoa com várias linhas (formulário e agendamento, ou dois envios) recebe uma categoria só, decidida pela mensagem mais informativa entre as dela. Envio repetido não é motivo para "Fora do perfil": quem manda duas vezes é a mesma pessoa, contada uma vez.

## Passo 4b: jornada de cada pessoa

A coluna `jornada` de `pessoas` diz se a pessoa **só preencheu formulário**, **só agendou** ou fez **formulário + agendamento**. Ela olha o histórico inteiro, não só o período: quem agendou em agosto e voltou pelo formulário em setembro aparece como "Formulário + agendamento", com as duas datas em `datas_formulario` e `datas_agendamento`.

"Formulário + agendamento" é o sinal mais forte de interesse do relatório: a pessoa escreveu e depois reservou horário (ou o contrário). Nunca esconda isso numa marcação de "duplicado". Traga em três lugares:
- no resumo, uma linha com quantas pessoas fizeram as duas coisas e quem são;
- na lista, na coluna Jornada, com as duas datas e a reunião no assunto;
- na qualificação, citando a jornada ao lado do nome.
- **Vendedor ou spam**: revista oferecendo "prêmio" ou matéria, venda de links ou serviços, mensagem sem contexto.

## Passo 5: entregar o documento

Crie um documento (Claude Docs; carregue a skill `docs` antes) chamado **"Entrada de leads: DD/MM a DD/MM/AAAA"**, em português, com horários em BRT. Seções, nesta ordem:

1. **Resumo**: primeira frase com o número que importa (pessoas reais e oportunidades no período). Depois, em tópicos curtos: total de linhas, testes, linhas reais e pessoas únicas, oportunidades e por onde vieram, reuniões marcadas, quantas pessoas fizeram formulário + agendamento (com os nomes), quantos vieram de mídia paga (diga "zero" se for zero) e qual tabela não teve lead real.
2. **Volume por tabela**: tabela com Tabela, Entrada, Mercado, Linhas, Testes e Reais, mais a linha de total. Abaixo, uma frase com a regra usada para identificar teste e os dias em que os testes se concentraram.
3. **Origem dos leads reais**: tabela com Origem, Como foi identificada, Pessoas, Oportunidades e O que chegou (cada pessoa conta uma vez, pela origem do primeiro contato no período). Inclua a linha de mídia paga mesmo com zero, porque a ausência é informação. Abaixo, a contagem por página de entrada.
4. **Qualificação**: tabela com Categoria, Pessoas e Quem (empresa e o motivo em poucas palavras).
5. **Lista completa**: uma **pessoa** por linha, na ordem de `pessoas` (primeiro contato no período, do mais recente ao mais antigo), com Data (BRT, primeiro contato no período), Nome, E-mail, Jornada, Página de entrada, Origem, Categoria e Assunto (resumo da mensagem). A origem é a do primeiro contato dela no período. Quando houver agendamento, ponha no assunto a data, a hora e o host da reunião; quando houver formulário e agendamento, cite as duas datas. Se a pessoa tem mais de uma linha no período, diga quantas no assunto. Depois, uma frase sobre o `crm_sync` dos contatos de formulário.
6. **Limitações dos dados**: o estado do rastreamento, a partir da chave `rastreamento` (última data com clique de anúncio e com UTM em cada tabela, em todo o histórico; se uma tabela que recebe tráfego pago está há semanas sem nenhum, diga a data e que isso indica campanha parada ou captura quebrada no formulário, e ponha esse alerta também no resumo); falta de primeiro toque (o `referrer` é só a página anterior, então "Site" pode esconder Google, LinkedIn ou e-mail); empresa e cargo vazios; as linhas de `testes_suspeitos` que parecem sondagem externa, com o `crm_sync` delas (se for `true`, recomende conferir se viraram contato no HubSpot); e o que não foi cruzado (HubSpot, agendamento × formulário).

Se o período não tiver nenhum contato real, entregue mesmo assim: o resumo diz isso, a tabela de volume mostra os testes e as seções 3 a 5 viram uma frase cada.

Antes de entregar, confira as contas: a soma por origem, a soma por categoria e o total da lista têm de bater com o número de pessoas únicas; a soma de `linhas_no_periodo` tem de bater com o total de linhas reais da tabela de volume.

Se o Claude Docs não estiver disponível, entregue o mesmo conteúdo na resposta, em markdown.

No chat, feche com uma ou duas linhas: o achado principal (quantos reais, quantas oportunidades, de onde vieram) e o que a pessoa pode fazer com o documento. Não repita o relatório na conversa.
