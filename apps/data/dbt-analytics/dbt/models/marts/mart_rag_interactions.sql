{{ config(materialized='table', engine='MergeTree', order_by='(event_date, trace_id)') }}

-- Forma de cada interação RAG (projeto `rag`), por trace:
--   n_retrievals  = observações kind='embedding' (buscas vetoriais do LightRAG)
--   n_generations = observações kind='completion' (geração/extração do LightRAG)
--   wall_ms       = latência ponta-a-ponta do trace (último end - primeiro start)
-- SEM custo aqui — só volume/forma. Custo de RAG está PARKEADO: o repricing via
-- gateway morreu com a inversão (projeto gateway apagado) e o lightRAG ainda não
-- captura custo efetivo (fica pra quando ele entrar no plano do collector).
--
-- IMPORTANTE: event_date/trace_id saem do int (o, lado esquerdo). Do trace (t, lado direito) só
-- puxo trace_name/session_id (nomes ÚNICOS). Não dá pra selecionar t.event_date/t.project_id —
-- o ClickHouse perde colunas de mesmo nome do lado direito do JOIN. As condições de ON com nomes
-- iguais (qualificadas) são ok.
select
    o.event_date,
    o.trace_id,
    t.trace_name,
    t.session_id,
    countIf(o.kind = 'embedding')   as n_retrievals,
    countIf(o.kind = 'completion')  as n_generations,
    count()                         as n_observations,
    sum(o.input_tokens)             as input_tokens,
    sum(o.output_tokens)            as output_tokens,
    sum(o.total_tokens)             as total_tokens,
    toUnixTimestamp64Milli(max(o.end_time)) - toUnixTimestamp64Milli(min(o.start_time)) as wall_ms
from {{ ref('int_observations_model') }} o
inner join {{ ref('stg_traces') }} t
    on o.trace_id = t.trace_id
   and o.project_id = t.project_id
where o.project_role = 'rag'
group by
    o.event_date, o.trace_id, t.trace_name, t.session_id
