{{ config(materialized='view') }}

-- Auditoria: provided_model_name que NÃO está no model_dim. Cada linha aqui = um modelo
-- a adicionar no seed (2 formas: alias + cru). Se estiver vazio, o seed está completo.
select
    provided_model_name,
    count()           as n_observations,
    min(start_time)   as first_seen,
    max(start_time)   as last_seen
from {{ ref('stg_observations') }}
where provided_model_name not in (select model_raw from {{ ref('model_dim') }})
group by provided_model_name
order by n_observations desc
