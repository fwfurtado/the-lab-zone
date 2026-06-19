{{ config(materialized='view') }}

-- Enriquece com o model_dim. LEFT JOIN: não-mapeados caem em provider/tier 'unknown'
-- e is_local=0 (e aparecem no mart_unmapped_models pra serem adicionados ao seed).
select
    o.*,
    coalesce(m.model_canonical, o.provided_model_name) as model_canonical,
    coalesce(m.provider, 'unknown')                    as provider,
    coalesce(m.is_local, toUInt8(0))                   as is_local,
    coalesce(m.tier, 'unknown')                        as tier
from {{ ref('stg_observations') }} o
left join {{ ref('model_dim') }} m
    on o.provided_model_name = m.model_raw
