-- Relatório de entrada de leads: consulta única (só leitura)
-- Supabase nearsmart, ref pbvjsixlqnuzcnqahbxu
--
-- Antes de rodar, troque os dois marcadores pelas datas do período, em BRT, no formato AAAA-MM-DD:
--   __INICIO__  primeiro dia incluído (ex.: 2026-10-12)
--   __FIM__     último dia incluído   (ex.: 2026-10-27)
-- O período vai de 00:00 do primeiro dia até 23:59:59 do último, no fuso de São Paulo.
--
-- Devolve um JSON com estas chaves:
--   rastreamento      última data com clique de anúncio e com UTM em cada tabela, em todo o histórico
--   totais            linhas, testes (por regra) e reais por tabela, mais a cobertura da jornada
--   testes_suspeitos  linhas de teste com cara de sondagem externa (para a seção de limitações)
--   pessoas           uma linha por pessoa real do período (juntada por e-mail): formulário e agendamento
--                     (em todo o histórico) e a jornada de navegação (primeiro toque mais antigo, último
--                     toque do lead mais recente, visitas)
--   reais             só as linhas reais, compactas, da mais recente para a mais antiga
--
-- Teste = regra de texto (e-mail, nome, página) OU marca no raw_payload (is_test, integration_test ou
-- smoke_test = true, ou as chaves teste/sonda preenchidas). As duas se somam: há testes feitos sem
-- ?integration_test=true que só a regra de texto pega.
--
-- Primeiro e último toque: as colunas utm_*, gclid etc. e o raw_payload.attribution guardam o PRIMEIRO
-- toque. O último toque (o clique que levou ao lead) está em raw_payload.journey.last (jornada v2, desde
-- 29/10/2026; nas landings a cobertura é parcial).
--
-- As linhas de teste não vêm de propósito, e as reais vêm compactas (sem o payload inteiro, campos nulos
-- omitidos): num período com bateria de testes a saída estoura o limite da ferramenta.

with u as (
  select 'contact_tracks_br' tbl, 'BR' mercado, 'Formulário do site' tipo, created_at,
    trim(coalesce(name,'')||' '||coalesce(last_name,'')) nome, email,
    page_url pagina, referrer_url referrer, utm_source, utm_medium, utm_campaign,
    concat_ws(',', case when coalesce(gclid,gbraid,wbraid) is not null then 'google_ads' end,
                   case when fbclid is not null then 'meta' end,
                   case when msclkid is not null then 'microsoft' end) clique_pago,
    crm_sync::text crm_sync, null::text reuniao, left(message,300) msg, to_jsonb(t) j
  from contact_tracks_br t
  union all
  select 'contact_tracks_us','US','Formulário do site', created_at,
    trim(coalesce(first_name,'')||' '||coalesce(last_name,'')), email,
    coalesce(page_url,landing_page), referrer_url, utm_source, utm_medium, utm_campaign,
    concat_ws(',', case when coalesce(gclid,gbraid,wbraid) is not null then 'google_ads' end,
                   case when fbclid is not null then 'meta' end,
                   case when msclkid is not null then 'microsoft' end),
    crm_sync::text, null, left(message,300), to_jsonb(t)
  from contact_tracks_us t
  union all
  select 'contacts_landings','US','Landing', created_at,
    trim(coalesce(name,'')||' '||coalesce(last_name,'')), email,
    origin_url, null, utm_source, utm_medium, utm_campaign,
    concat_ws(',', case when coalesce(gclid,gbraid,wbraid) is not null then 'google_ads' end,
                   case when fbclid is not null then 'meta' end,
                   case when msclkid is not null then 'microsoft' end),
    crm_sync::text, null, left(message,300), to_jsonb(t)
  from contacts_landings t
  union all
  select 'contacts_landings_br','BR','Landing', created_at,
    trim(coalesce(name,'')||' '||coalesce(last_name,'')), email,
    origin_url, null, utm_source, utm_medium, utm_campaign,
    concat_ws(',', case when coalesce(gclid,gbraid,wbraid) is not null then 'google_ads' end,
                   case when fbclid is not null then 'meta' end,
                   case when msclkid is not null then 'microsoft' end),
    crm_sync::text, null, left(message,300), to_jsonb(t)
  from contacts_landings_br t
  union all
  select 'agendamento_luby', market, 'Agendamento', created_at,
    trim(coalesce(first_name,'')||' '||coalesce(last_name,'')), email,
    origin_url, landing_page, utm_source, utm_medium, utm_campaign,
    concat_ws(',', case when coalesce(gclid,gbraid,wbraid) is not null then 'google_ads' end,
                   case when fbclid is not null then 'meta' end,
                   case when msclkid is not null then 'microsoft' end),
    null, concat_ws(' · ', status, meeting_date::text||' '||meeting_time::text, timezone, 'host '||host),
    left(message,300), to_jsonb(t)
  from agendamento_luby t
),
p as (
  -- raw_payload (json ou jsonb, conforme a tabela) e a jornada v2, quando existe
  select u.*, rp,
    case when jsonb_typeof(rp->'journey') = 'object' then rp->'journey' end jr
  from u, lateral (select case when jsonb_typeof(u.j->'raw_payload') = 'object'
                               then u.j->'raw_payload' else '{}'::jsonb end rp) x
),
base as (
  select p.*, to_char(created_at at time zone 'America/Sao_Paulo','DD/MM HH24:MI') quando_brt,
    (email ilike '%@luby.co%' or email ilike '%example.com' or email ilike '%test%'
     or email ilike '%yopmail%' or email ilike 'recon%' or nome ilike '%test%' or nome like '{{%'
     or coalesce(pagina,'') ~* '(smoke_test|integration_test|test\.luby\.co|72\.61\.13\.41|estudio-teste|meet-with-karime)') teste_texto,
    (coalesce(rp->>'is_test','') = 'true' or coalesce(rp->>'integration_test','') = 'true'
     or coalesce(rp->>'smoke_test','') = 'true'
     or coalesce(rp->>'teste','') <> '' or coalesce(rp->>'sonda','') <> '') teste_payload,
    -- toque = fonte/mídia (campanha), ou o domínio do referrer, ou direct; + o clique pago do toque.
    -- Com jornada mas sem first/last (só visitas diretas), o toque é direct.
    coalesce((select concat_ws(' · ',
        coalesce(nullif(x->>'utm_source',''),
                 substring(x->>'referrer' from '^(?:https?://)?(?:www\.)?([^/:?#]+)'), 'direct')
          || coalesce('/'||nullif(x->>'utm_medium',''), '')
          || coalesce(' ('||left(nullif(x->>'utm_campaign',''),40)||')', ''),
        nullif(concat_ws(',', case when coalesce(x->>'gclid',x->>'gbraid',x->>'wbraid') is not null then 'gclid' end,
                              case when x->>'fbclid' is not null then 'fbclid' end,
                              case when x->>'msclkid' is not null then 'msclkid' end), ''))
     from (select jr->'first' x) s where jsonb_typeof(x) = 'object'),
      case when jr is not null then 'direct' end) primeiro_toque,
    coalesce((select concat_ws(' · ',
        coalesce(nullif(x->>'utm_source',''),
                 substring(x->>'referrer' from '^(?:https?://)?(?:www\.)?([^/:?#]+)'), 'direct')
          || coalesce('/'||nullif(x->>'utm_medium',''), '')
          || coalesce(' ('||left(nullif(x->>'utm_campaign',''),40)||')', ''),
        nullif(concat_ws(',', case when coalesce(x->>'gclid',x->>'gbraid',x->>'wbraid') is not null then 'gclid' end,
                              case when x->>'fbclid' is not null then 'fbclid' end,
                              case when x->>'msclkid' is not null then 'msclkid' end), ''))
     from (select jr->'last' x) s where jsonb_typeof(x) = 'object'),
      case when jr is not null then 'direct' end) ultimo_toque,
    nullif(concat_ws(',', case when coalesce(jr->'last'->>'gclid',jr->'last'->>'gbraid',jr->'last'->>'wbraid') is not null then 'google_ads' end,
                          case when jr->'last'->>'fbclid' is not null then 'meta' end,
                          case when jr->'last'->>'msclkid' is not null then 'microsoft' end), '') clique_pago_ultimo,
    coalesce(jr->'first'->>'ts', jr->>'created') primeiro_ts_jornada
  from p
),
f as (
  select * from base
  where created_at >= ('__INICIO__'::date)::timestamp at time zone 'America/Sao_Paulo'
    and created_at <  ('__FIM__'::date + 1)::timestamp at time zone 'America/Sao_Paulo'
),
fr as (
  -- linhas reais do período, já com os campos compactos de jornada, qualificação e produto
  select f.*,
    (jr->>'session_count')::int visitas,
    case when jsonb_typeof(jr->'pages') = 'array' then jsonb_array_length(jr->'pages') end paginas_vistas,
    case when primeiro_ts_jornada is not null
         then round((extract(epoch from created_at - primeiro_ts_jornada::timestamptz) / 86400)::numeric, 1) end dias_ate_lead,
    -- caminho das últimas visitas guardadas (sessions[] tem só as mais recentes): repetições viram ×N
    (select case when (jr->>'session_count')::int > max(n_total) then '(+'||((jr->>'session_count')::int - max(n_total))||') ' else '' end
            || string_agg(lbl || case when qt > 1 then ' ×'||qt else '' end, ' → ' order by o)
     from (select lbl, min(o) o, count(*) qt, max(n_total) n_total
           from (select o, lbl, o - row_number() over (partition by lbl order by o) g, count(*) over () n_total
                 from jsonb_array_elements(case when jsonb_typeof(jr->'sessions') = 'array' then jr->'sessions' else '[]' end)
                      with ordinality s(v, o),
                      lateral (select coalesce(nullif(v->>'source',''), 'direct') || coalesce('/'||nullif(v->>'medium',''), '') lbl) l) a
           group by lbl, g) b) caminho,
    nullif(concat_ws(' · ',
      'empresa: '||coalesce(nullif(j->>'company',''), nullif(j->>'company_name',''), nullif(rp->>'company',''),
                            nullif(rp->>'empresa',''), nullif(rp->>'company_name','')),
      'cargo: '||coalesce(nullif(j->>'role',''), nullif(j->>'job_title',''), nullif(rp->>'role',''),
                          nullif(rp->>'jobTitle',''), nullif(rp->>'title','')),
      'setor: '||nullif(concat_ws(' / ', nullif(rp->>'industry',''),
                                  coalesce(nullif(j->>'segment',''), nullif(rp->>'segment',''), nullif(rp->>'segmento','')),
                                  nullif(rp->>'area','')), ''),
      'país: '||nullif(rp->>'country','')), '') qualif,
    (select string_agg(v, ' · ' order by o)
     from (select v, min(o) o from unnest(array[rp->>'profile', j->>'profile', rp->>'site', rp->>'lp_slug',
                                               coalesce(rp->>'form_name', rp->>'form'), rp->>'template', rp->>'pageType'])
                                   with ordinality a(v, o)
           where coalesce(v,'') <> '' group by v) x) site_perfil,
    left(nullif(concat_ws(' · ',
      case when rp ? 'xray_move' or rp ? 'xray_score'
           then 'xray: '||coalesce(lower(nullif(rp->>'xray_move','')),'?')||coalesce(' · score '||nullif(rp->>'xray_score',''),'') end,
      case when coalesce(rp->>'yearlySavings','') ~ '^[0-9]+(\.[0-9]+)?$' and (rp->>'yearlySavings')::numeric > 0
           then 'economia R$ '||replace(to_char(round((rp->>'yearlySavings')::numeric),'FM999G999G999'),',','.')||'/ano' end,
      case when jsonb_typeof(rp->'calculator') = 'object' and rp->'calculator' <> '{}' then 'calculadora preenchida' end,
      case when jsonb_typeof(rp->'catalogAgents') = 'array' and jsonb_array_length(rp->'catalogAgents') > 0
           then 'agentes: '||(select string_agg(e, ', ') from (select jsonb_array_elements_text(rp->'catalogAgents') e limit 3) z) end,
      'processo: '||nullif(rp->>'process',''),
      'intenção: '||nullif(rp->>'intent',''),
      'tier: '||nullif(rp->>'tier',''),
      'ebook: '||nullif(rp->>'ebook',''),
      'material: '||left(nullif(rp->>'asset',''),60),
      case when jsonb_typeof(rp->'saasbusters'->'stack') = 'array'
           then 'saasbusters: '||jsonb_array_length(rp->'saasbusters'->'stack')||' ferramentas' end), ''), 160) produto,
    (select case when ua ~* '(ipad|tablet)' then 'tablet' when ua ~* '(mobi|android|iphone)' then 'celular' else 'desktop' end
     from (select coalesce(nullif(rp->>'userAgent',''), nullif(rp->>'user_agent',''), nullif(j->>'user_agent','')) ua) z
     where ua is not null) aparelho
  from f where not (teste_texto or teste_payload)
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
    string_agg(reuniao, ' | ' order by created_at) filter (where tipo = 'Agendamento') reunioes,
    -- primeiro toque mais antigo da pessoa (em todo o histórico com jornada)
    (array_agg(primeiro_toque order by primeiro_ts_jornada::timestamptz) filter (where primeiro_toque is not null))[1] primeiro_toque,
    min(primeiro_ts_jornada::timestamptz) primeiro_ts_jornada
  from base where not (teste_texto or teste_payload) and coalesce(trim(email),'') <> ''
  group by 1
),
pessoas as (
  select lower(trim(email)) em,
    (array_agg(nome order by created_at desc))[1] nome,
    count(*) linhas_no_periodo,
    string_agg(distinct tbl, ', ') tabelas_no_periodo,
    to_char(min(created_at) at time zone 'America/Sao_Paulo','DD/MM HH24:MI') primeiro_contato_no_periodo,
    min(created_at) primeiro_ts,
    max(created_at) ultimo_ts,
    (array_agg(ultimo_toque order by created_at desc) filter (where ultimo_toque is not null))[1] ultimo_toque,
    max(visitas) visitas
  from fr where coalesce(trim(email),'') <> ''
  group by 1
)
select json_build_object(
  'periodo', json_build_object('inicio','__INICIO__','fim','__FIM__'),
  -- Saúde do rastreamento, em todo o histórico (não só no período): a última vez que cada tabela
  -- recebeu um contato real com clique de anúncio (nas colunas, 1º toque, e no último toque da jornada)
  -- e com qualquer UTM. Uma data antiga aqui, numa tabela que deveria receber tráfego pago, indica
  -- campanha parada ou captura quebrada no formulário.
  'rastreamento', (select json_agg(r) from (
     select tbl,
       to_char(max(created_at) filter (where clique_pago <> '') at time zone 'America/Sao_Paulo','DD/MM/YYYY') ultimo_clique_pago,
       to_char(max(created_at) filter (where clique_pago_ultimo is not null) at time zone 'America/Sao_Paulo','DD/MM/YYYY') ultimo_clique_pago_jornada,
       to_char(max(created_at) filter (where utm_source is not null) at time zone 'America/Sao_Paulo','DD/MM/YYYY') ultima_utm
     from base where not (teste_texto or teste_payload) group by tbl) r),
  -- testes_texto e testes_payload se sobrepõem; testes_so_payload = os que só a marca no payload pegou
  'totais', (select json_agg(t) from (
     select tbl, count(*) total,
       count(*) filter (where teste_texto or teste_payload) testes,
       count(*) filter (where teste_texto) testes_texto,
       count(*) filter (where teste_payload) testes_payload,
       count(*) filter (where teste_payload and not teste_texto) testes_so_payload,
       count(*) filter (where not (teste_texto or teste_payload)) reais,
       count(*) filter (where not (teste_texto or teste_payload) and jr is not null) reais_com_jornada,
       count(*) filter (where not (teste_texto or teste_payload) and primeiro_toque is distinct from ultimo_toque
                          and jr is not null) reais_primeiro_dif_ultimo
     from f group by tbl order by tbl) t),
  'testes_suspeitos', (select json_agg(s) from (
     select tbl, quando_brt, nome, email, pagina, crm_sync from f
     where (teste_texto or teste_payload)
       and (nome like '{{%' or email ilike '%yopmail%' or email ilike 'recon%'
            or email ilike '%example.com' or email = 'test@test.com')) s),
  'pessoas', (select jsonb_agg(jsonb_strip_nulls(to_jsonb(x)) - 'ord' order by x.ord desc) from (
     select pe.primeiro_ts ord, pe.nome, pe.em email,
       case when h.n_formularios > 0 and h.n_agendamentos > 0 then 'Formulário + agendamento'
            when h.n_agendamentos > 0 then 'Só agendamento'
            else 'Só formulário' end formulario_agendamento,
       h.datas_formulario, h.datas_agendamento, h.reunioes,
       pe.linhas_no_periodo, pe.tabelas_no_periodo, pe.primeiro_contato_no_periodo,
       h.primeiro_toque, pe.ultimo_toque, pe.visitas,
       case when h.primeiro_ts_jornada is not null
            then round((extract(epoch from pe.ultimo_ts - h.primeiro_ts_jornada) / 86400)::numeric, 1) end dias_ate_ultimo_lead
     from pessoas pe join historico h on h.em = pe.em) x),
  -- pagina/referrer/utm/clique_pago são as colunas (1º toque); primeiro_toque/ultimo_toque vêm da jornada
  'reais', (select jsonb_agg(jsonb_strip_nulls(to_jsonb(r)) - 'ord' order by r.ord desc) from (
     select created_at ord, tbl, tipo, mercado, quando_brt, nome, email, pagina, referrer,
       nullif(concat_ws('/', utm_source, utm_medium, utm_campaign), '') utm,
       nullif(clique_pago, '') clique_pago, crm_sync, reuniao, msg,
       primeiro_toque, ultimo_toque, clique_pago_ultimo, visitas, dias_ate_lead, caminho, paginas_vistas,
       qualif, site_perfil, produto, aparelho
     from fr) r)
);
