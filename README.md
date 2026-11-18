# Relatório de entrada de leads

Skill do time de Growth da Luby. Responde "quantos leads entraram, de onde vieram e quais valem a pena" para o período que você escolher, lendo as cinco tabelas de inbound do Supabase `nearsmart`:

| Tabela | Entrada |
|---|---|
| `contact_tracks_br` | Formulário do site luby.com.br |
| `contact_tracks_us` | Formulário do site luby.co |
| `contacts_landings_br` | Landings BR e Finfy |
| `contacts_landings` | Landings US |
| `agendamento_luby` | Reuniões marcadas pelo agendador |

## O que entrega

Um documento com seis seções: resumo, volume por tabela (com testes separados dos contatos reais), origem de cada lead, qualificação (oportunidade, a qualificar, parceria, fora do perfil, vendedor ou spam), lista completa e limitações dos dados.

O relatório conta **pessoas**, não linhas: quem preencheu o formulário e também agendou aparece uma vez, como "Formulário + agendamento" e com as duas datas, olhando o histórico inteiro. Esse é o sinal de interesse mais forte e vem destacado no resumo. As limitações incluem a última data em que cada tabela recebeu clique de anúncio e UTM, para pegar campanha parada ou captura quebrada.

Desde a versão 1.2.0, a skill lê o `raw_payload` dos leads:

- **Origem pelo último toque.** As colunas `utm_*` e `gclid` guardam o primeiro toque; o clique que levou ao lead está na jornada de navegação (`raw_payload.journey.last`, gravada desde 29/10/2026). Com jornada, a origem é o último toque, e o relatório mostra "chegou por X, converteu por Y" quando os dois diferem, com as visitas, os dias até o lead e o caminho (ex.: "google/cpc → direct ×2 → chatgpt.com"). Sem jornada, a origem sai das colunas, como antes.
- **Teste por duas regras.** Padrão de texto (e-mail, nome, página) ou marca no payload (`is_test` etc.). Muitos testes chegam com `is_test = false`, então as duas se somam.
- **Qualificação com o que o formulário gravou**: empresa, cargo, setor, site ou perfil (agents.luby.co e legacybusters.com se distinguem pelo `profile`), sinais de produto (X-Ray, calculadora, agentes, ebook) e aparelho.

A versão 1.3.0 traz mais do `raw_payload`, sempre em strings curtas:

- **Páginas vistas antes do lead** (cases, serviços, preço, blog, sobre, carreiras etc.) e a **página de entrada** da visita que converteu.
- **Campanha de cada visita** no caminho (ex.: "google/cpc (agents_br) → direct").
- **Valores da calculadora** (legado do legacybusters, potencial da Finfy, agents) em vez de só "calculadora preenchida".
- **Idioma e fuso do navegador**, com um aviso quando o fuso não combina com o mercado (UTC, fora da América, fora do Brasil num site BR). É só um sinal para conferir à mão: a regra de teste e os totais não mudam.

Histórico de versões em [CHANGELOG.md](CHANGELOG.md).

A skill é **só leitura**: não altera o banco, o HubSpot nem nada.

## Como usar

Peça em linguagem natural, por exemplo:

- "quantos leads entraram essa semana?"
- "relatório de entrada de leads de setembro"
- "quem preencheu formulário ou agendou reunião pelo site?"

Se você não disser o período, a skill pergunta (7, 15 ou 30 dias, mês passado ou um intervalo seu). O período conta dias inteiros no horário de Brasília.

## Requisitos

- Conector do **Supabase** com acesso ao projeto `nearsmart` (ref `pbvjsixlqnuzcnqahbxu`).
- **Claude Docs** para o documento. Sem ele, o relatório sai na própria resposta.

## Instalação

Pelo marketplace do Claude Code:

```
/plugin marketplace add Luby-Marketing/skill-relatorio-entrada-leads
/plugin install relatorio-entrada-leads@skill-relatorio-entrada-leads
```

Ou adicione este repositório ao marketplace da organização.

## Estrutura

```
.claude-plugin/
  plugin.json          manifesto do plugin
  marketplace.json     permite adicionar este repositório como marketplace
CHANGELOG.md           histórico de versões
skills/relatorio-entrada-leads/
  SKILL.md             instruções da skill
  references/consulta.sql   consulta única, parametrizada por data
  evals/               casos de teste (formato do `claude plugin eval`)
```

## Testes

Três casos em `skills/relatorio-entrada-leads/evals/`, rodados em 27/10/2026 com e sem a skill (versão 1.0.0). A versão 1.2.0 acrescentou um critério ao caso "Sem período informado" (cobertura da jornada), ainda não rodado:

| Caso | Com a skill | Sem a skill |
|---|---|---|
| Últimos 7 dias | 6 de 6 critérios | 1 de 6 (não incluiu os agendamentos e contou 10 contatos reais em vez de 14) |
| Mês de setembro | 5 de 5 | 3 de 5 (sem agendamentos; listou só os leads comerciais) |
| Sem período informado | 3 de 3 | 3 de 3 |
| **Total** | **14 de 14** | **7 de 14** |

Para rodar de novo com o Claude Code: `claude plugin eval skills/relatorio-entrada-leads --allow-tools Write,Edit,Bash`.
