{{ config(materialized='view') }}

-- Enriquece com model_dim (canônico/provider/is_local/tier/kind) e project_dim (nome/role).
--
-- Colisão de nome no JOIN: enquanto o lado direito tiver uma coluna `project_id` (a do
-- project_dim), o ClickHouse resolve o output como ambíguo e DROPA o project_id do view — mesmo
-- com `o.project_id` explícito no SELECT. Fix: renomear a coluna colidente do project_dim num
-- subselect (project_id -> pd_project_id). Aí o `o.project_id` é o único `project_id` em escopo
-- e sobrevive no view. model_dim não colide (model_raw/canonical/... são nomes únicos).
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
left join (
    select
        project_id as pd_project_id,
        project_name,
        project_role
    from {{ ref('project_dim') }}
) p
    on o.project_id = p.pd_project_id
