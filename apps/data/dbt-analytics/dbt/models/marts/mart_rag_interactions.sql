{{ config(materialized='table', engine='MergeTree', order_by='(event_date, trace_id)') }}

-- Forma de cada interação RAG (projeto `rag`), por trace:
--   n_retrievals  = observações kind='embedding' (as buscas vetoriais do LightRAG)
--   n_generations = observações kind='completion' (geração/extração do LightRAG)
--   wall_ms       = latência ponta-a-ponta do trace (último end - primeiro start)
-- SEM custo aqui — custo mora no mart_rag_cost_daily (reprecificado). Aqui é volume/forma,
-- onde double-count não é problema (não somo custo). É a resposta de "quanto retrieval uma
-- query de RAG dispara e quão pesada ela é".
select
    t.event_date,
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
    t.event_date, o.trace_id, t.trace_name, t.session_id
