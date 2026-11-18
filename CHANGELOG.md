# Changelog

## 1.2.0 (18/11/2026)

A skill passa a ler o `raw_payload` dos leads.

- **Origem pelo último toque.** Quando a linha tem a jornada de navegação (`raw_payload.journey`, gravada desde 29/10/2026), a origem do lead é o último toque (`journey.last`), com o clique pago do último toque em primeiro lugar. As colunas `utm_*`, `gclid` e o `raw_payload.attribution` guardam o primeiro toque; quando os dois diferem, o relatório diz "chegou por X, converteu por Y". Sem jornada, valem as regras antigas pelas colunas.
- **Teste por duas regras somadas.** Além do padrão de texto, conta como teste a marca no payload (`is_test`, `integration_test` ou `smoke_test` = true, ou as chaves `teste` e `sonda`). `totais` mostra quantos cada regra pegou e quantos só a marca no payload pegou.
- **Campos novos nas linhas reais**, compactos e sem o payload inteiro: `primeiro_toque`, `ultimo_toque`, `clique_pago_ultimo`, `visitas`, `dias_ate_lead`, `caminho` (ex.: "google/cpc → direct ×2 → chatgpt.com"), `paginas_vistas`, `qualif` (empresa, cargo, setor, país), `site_perfil` (profile, site, slug da LP, formulário), `produto` (X-Ray, calculadora, agentes, ebook etc.) e `aparelho`. Campos vazios são omitidos.
- **`pessoas`** ganha o primeiro toque mais antigo, o último toque do lead mais recente, as visitas e os dias até o último lead. A coluna `jornada` (formulário/agendamento) passa a se chamar `formulario_agendamento`, para não confundir com a jornada de navegação.
- **Cobertura**: `totais` traz `reais_com_jornada` e `reais_primeiro_dif_ultimo`; `rastreamento` traz `ultimo_clique_pago_jornada`.
- **Documento**: a lista completa ganha Primeiro toque, Último toque, Visitas e Caminho; o resumo ganha uma linha sobre quem visitou mais de uma vez; as limitações explicam a cobertura da jornada e a regra de teste combinada.
- Novo critério no eval `sem-periodo-informado`: o relatório informa a cobertura da jornada.

## 1.1.1 (27/10/2026)

- "Vendedor ou spam" volta para a lista de categorias do passo 4.

## 1.1.0 (27/10/2026)

- Consulta ganha a chave `pessoas`: linhas reais juntadas por e-mail, com formulário e agendamento (só formulário, só agendamento, formulário + agendamento) em todo o histórico.
- Lista completa com uma pessoa por linha; o resumo destaca quem fez formulário e agendamento.

## 1.0.0 (27/10/2026)

- Primeira versão: relatório de entrada de leads das cinco tabelas de inbound do Supabase nearsmart, com período perguntado antes, consulta única parametrizada e checagem do rastreamento.
