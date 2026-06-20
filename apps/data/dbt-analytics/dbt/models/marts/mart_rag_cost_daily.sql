{{ config(materialized='table', engine='MergeTree', order_by='(event_date, model_canonical, kind)') }}

-- RAG × CUSTO (Nível B): tokens do projeto `rag` REPRECIFICADOS pela taxa unitária do gateway.
--   rag     = fronteira semântica (quais chamadas são RAG), tokens reais por modelo.
--   gateway = pricing real ($/token), via int_gateway_unit_cost.
--   join por model_canonical (a normalização do seed cola os nomes diferentes do mesmo modelo).
--
-- Por que assim: não há elo cross-projeto (session_id/metadata não compartilhados), então não dá
-- pra atribuir custo por interação com precisão. Reprecificar evita double-count (custo NÃO é
-- somado entre projetos) e atribui custo SÓ ao que o rag marcou como RAG.
--
-- est_cost é ESTIMADO (taxa blended input+output). kind separa retrieval (embedding) de geração.
select
    r.event_date,
    r.model_canonical,
    r.kind,
    r.provider,
    r.is_local,
    r.tier,
    count()                                                                  as n_observations,
    sum(r.input_tokens)                                                      as input_tokens,
    sum(r.output_tokens)                                                     as output_tokens,
    sum(r.total_tokens)                                                      as total_tokens,
    round(sum(toFloat64(r.total_tokens) * coalesce(u.unit_cost_per_token, 0.0)), 6) as est_cost
from {{ ref('int_observations_model') }} r
left join {{ ref('int_gateway_unit_cost') }} u
    on r.model_canonical = u.model_canonical
where r.project_role = 'rag'
group by
    r.event_date, r.model_canonical, r.kind, r.provider, r.is_local, r.tier
