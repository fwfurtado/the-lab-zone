{{ config(materialized='view') }}

-- traces é ReplacingMergeTree -> FINAL pra deduplicar; is_deleted=0 tira soft-deletes.
-- É o pai das observações (traces.id = observations.trace_id). Usado pelo mart_rag_interactions
-- pra montar a "forma" de cada interação RAG (nome do trace, sessão, data).
select
    id                  as trace_id,
    project_id,
    name                as trace_name,
    session_id,
    user_id,
    timestamp,
    toDate(timestamp)   as event_date
from {{ source('langfuse', 'traces') }} final
where is_deleted = 0
