{{ config(materialized='view') }}

-- Enriquece com model_dim (canônico/provider/is_local/tier/kind) e project_dim (nome/role).
-- LEFT JOINs: não-mapeados caem em 'unknown' (e aparecem no mart_unmapped_models / fica óbvio
-- se um project_id novo surgir). project_role é o eixo de custo: só 'gateway' tem custo real.
select
    o.*,
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
