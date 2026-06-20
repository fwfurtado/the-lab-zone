{{ config(materialized='view') }}

-- Enriquece com model_dim (canônico/provider/is_local/tier/kind) e project_dim (nome/role).
-- Colunas EXPLÍCITAS (sem o.*): o ClickHouse, com `o.*` + JOIN onde o lado direito (project_dim)
-- tem uma coluna de mesmo nome (project_id), REMOVE essa coluna da expansão do `*` pra evitar
-- ambiguidade — o view perdia o project_id. Listar explícito (o.project_id) resolve.
select
    o.id,
    o.trace_id,
    o.project_id,
    o.type,
    o.level,
    o.provided_model_name,
    o.start_time,
    o.end_time,
    o.event_date,
    o.latency_ms,
    o.total_cost,
    o.input_tokens,
    o.output_tokens,
    o.total_tokens,
    coalesce(m.model_canonical, o.provided_model_name) as model_canonical,
    coalesce(m.provider, 'unknown')                    as provider,
    coalesce(m.is_local, toUInt8(0))                   as is_local,
    coalesce(m.tier, 'unknown')                        as tier,
    coalesce(m.kind, 'unknown')                        as kind,
    coalesce(p.project_name, o.project_id)             as project_name,
    coalesce(p.project_role, 'unknown')                as project_role
from {{ ref('stg_observations') }} o
left join {{ ref('model_dim') }} m
    on o.provided_model_name = m.model_raw
left join {{ ref('project_dim') }} p
    on o.project_id = p.project_id
