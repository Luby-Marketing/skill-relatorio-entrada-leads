-- Relatório de entrada de leads: consulta única (só leitura)
-- Supabase nearsmart, ref pbvjsixlqnuzcnqahbxu
--
-- Antes de rodar, troque os dois marcadores pelas datas do período, em BRT, no formato AAAA-MM-DD:
--   __INICIO__  primeiro dia incluído (ex.: 2026-10-12)
--   __FIM__     último dia incluído   (ex.: 2026-10-27)
-- O período vai de 00:00 do primeiro dia até 23:59:59 do último, no fuso de São Paulo.
--
-- Devolve um JSON com cinco chaves:
--   rastreamento      última data com clique de anúncio e com UTM em cada tabela, em todo o histórico
--   totais            linhas, testes e reais por tabela
--   testes_suspeitos  linhas de teste com cara de sondagem externa (para a seção de limitações)
--   pessoas           uma linha por pessoa real do período (juntada por e-mail), com a jornada:
--                     se ela já preencheu formulário, se agendou, as datas de cada um (em todo o
--                     histórico, então um formulário de setembro aparece para quem agendou em outubro)
--                     e quantas linhas ela tem no período
--   reais             só as linhas reais, completas, da mais recente para a mais antiga
-- As linhas de teste não vêm completas de propósito: num período com bateria de testes elas passam de 250
-- e estouram o limite de saída da ferramenta.

with u as (
  select 'contact_tracks_br' tbl, 'BR' mercado, 'Formulário do site' tipo, created_at,
    trim(coalesce(name,'')||' '||coalesce(last_name,'')) nome, email,
    page_url pagina, referrer_url referrer, utm_source, utm_medium, utm_campaign,
    concat_ws(',', case when coalesce(gclid,gbraid,wbraid) is not null then 'google_ads' end,
                   case when fbclid is not null then 'meta' end,
                   case when msclkid is not null then 'microsoft' end) clique_pago,
    crm_sync::text crm_sync, null::text reuniao, left(message,300) msg
  from contact_tracks_br
  union all
  select 'contact_tracks_us','US','Formulário do site', created_at,
    trim(coalesce(first_name,'')||' '||coalesce(last_name,'')), email,
    coalesce(page_url,landing_page), referrer_url, utm_source, utm_medium, utm_campaign,
    concat_ws(',', case when coalesce(gclid,gbraid,wbraid) is not null then 'google_ads' end,
                   case when fbclid is not null then 'meta' end,
                   case when msclkid is not null then 'microsoft' end),
    crm_sync::text, null, left(message,300)
  from contact_tracks_us
  union all
  select 'contacts_landings','US','Landing', created_at,
    trim(coalesce(name,'')||' '||coalesce(last_name,'')), email,
    origin_url, null, utm_source, utm_medium, utm_campaign,
    concat_ws(',', case when coalesce(gclid,gbraid,wbraid) is not null then 'google_ads' end,
                   case when fbclid is not null then 'meta' end,
                   case when msclkid is not null then 'microsoft' end),
    crm_sync::text, null, left(message,300)
  from contacts_landings
  union all
  select 'contacts_landings_br','BR','Landing', created_at,
    trim(coalesce(name,'')||' '||coalesce(last_name,'')), email,
    origin_url, null, utm_source, utm_medium, utm_campaign,
    concat_ws(',', case when coalesce(gclid,gbraid,wbraid) is not null then 'google_ads' end,
                   case when fbclid is not null then 'meta' end,
                   case when msclkid is not null then 'microsoft' end),
    crm_sync::text, null, left(message,300)
  from contacts_landings_br
  union all
  select 'agendamento_luby', market, 'Agendamento', created_at,
    trim(coalesce(first_name,'')||' '||coalesce(last_name,'')), email,
    origin_url, landing_page, utm_source, utm_medium, utm_campaign,
    concat_ws(',', case when coalesce(gclid,gbraid,wbraid) is not null then 'google_ads' end,
                   case when fbclid is not null then 'meta' end,
                   case when msclkid is not null then 'microsoft' end),
    null, concat_ws(' · ', status, meeting_date::text||' '||meeting_time::text, timezone, 'host '||host),
    left(message,300)
  from agendamento_luby
),
base as (
  select *, to_char(created_at at time zone 'America/Sao_Paulo','DD/MM HH24:MI') quando_brt,
    (email ilike '%@luby.co%' or email ilike '%example.com' or email ilike '%test%'
     or email ilike '%yopmail%' or email ilike 'recon%' or nome ilike '%test%' or nome like '{{%'
     or coalesce(pagina,'') ~* '(smoke_test|integration_test|test\.luby\.co|72\.61\.13\.41|estudio-teste|meet-with-karime)') teste
  from u
),
f as (
  select * from base
  where created_at >= ('__INICIO__'::date)::timestamp at time zone 'America/Sao_Paulo'
    and created_at <  ('__FIM__'::date + 1)::timestamp at time zone 'America/Sao_Paulo'
),
historico as (
  -- Tudo o que cada e-mail real já fez, em qualquer data
  select lower(trim(email)) em,
    count(*) filter (where tipo <> 'Agendamento') n_formularios,
    count(*) filter (where tipo = 'Agendamento') n_agendamentos,
    string_agg(distinct to_char(created_at at time zone 'America/Sao_Paulo','DD/MM/YYYY'), ', ')
      filter (where tipo <> 'Agendamento') datas_formulario,
    string_agg(distinct to_char(created_at at time zone 'America/Sao_Paulo','DD/MM/YYYY'), ', ')
      filter (where tipo = 'Agendamento') datas_agendamento,
    string_agg(reuniao, ' | ' order by created_at) filter (where tipo = 'Agendamento') reunioes
  from base where not teste and coalesce(trim(email),'') <> ''
  group by 1
),
pessoas as (
  select lower(trim(f.email)) em,
    (array_agg(f.nome order by f.created_at desc))[1] nome,
    count(*) linhas_no_periodo,
    string_agg(distinct f.tbl, ', ') tabelas_no_periodo,
    to_char(min(f.created_at) at time zone 'America/Sao_Paulo','DD/MM HH24:MI') primeiro_contato_no_periodo,
    min(f.created_at) primeiro_ts
  from f where not teste and coalesce(trim(f.email),'') <> ''
  group by 1
)
select json_build_object(
  'periodo', json_build_object('inicio','__INICIO__','fim','__FIM__'),
  -- Saúde do rastreamento, em todo o histórico (não só no período): a última vez que cada tabela
  -- recebeu um contato real com clique de anúncio e com qualquer UTM. Uma data antiga aqui, numa
  -- tabela que deveria receber tráfego pago, indica campanha parada ou captura quebrada no formulário.
  'rastreamento', (select json_agg(r) from (
     select tbl,
       to_char(max(created_at) filter (where clique_pago <> '') at time zone 'America/Sao_Paulo','DD/MM/YYYY') ultimo_clique_pago,
       to_char(max(created_at) filter (where utm_source is not null) at time zone 'America/Sao_Paulo','DD/MM/YYYY') ultima_utm
     from base where not teste group by tbl) r),
  'totais', (select json_agg(t) from (
     select tbl, count(*) total, count(*) filter (where teste) testes, count(*) filter (where not teste) reais
     from f group by tbl) t),
  'testes_suspeitos', (select json_agg(s) from (
     select tbl, quando_brt, nome, email, pagina, crm_sync from f
     where teste and (nome like '{{%' or email ilike '%yopmail%' or email ilike 'recon%'
                      or email ilike '%example.com' or email = 'test@test.com')) s),
  'pessoas', (select json_agg(p) from (
     select pe.nome, pe.em email,
       case when h.n_formularios > 0 and h.n_agendamentos > 0 then 'Formulário + agendamento'
            when h.n_agendamentos > 0 then 'Só agendamento'
            else 'Só formulário' end jornada,
       h.datas_formulario, h.datas_agendamento, h.reunioes,
       pe.linhas_no_periodo, pe.tabelas_no_periodo, pe.primeiro_contato_no_periodo
     from pessoas pe join historico h on h.em = pe.em
     order by pe.primeiro_ts desc) p),
  'reais', (select json_agg(r order by created_at desc) from (
     select * from f where not teste) r)
);
