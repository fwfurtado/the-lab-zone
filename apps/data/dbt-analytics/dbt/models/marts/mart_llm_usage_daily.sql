{{ config(materialized='table', engine='MergeTree', order_by='(event_date, project_id, model_canonical, tier)') }}

-- Gate Q1 (custo): custo + tokens + contagem por dia × projeto × modelo × tier, com o eixo
-- is_local (local vs cloud). n_errors fica pronto (level='ERROR') mesmo que hoje seja 0.
select
    event_date,
    project_id,
    model_canonical,
    provider,
    is_local,
    tier,
    type,
    count()                          as n_observations,
    countIf(level = 'ERROR')         as n_errors,
    sum(input_tokens)                as input_tokens,
    sum(output_tokens)               as output_tokens,
    sum(total_tokens)                as total_tokens,
    sum(total_cost)                  as total_cost
from {{ ref('int_observations_model') }}
group by
    event_date, project_id, model_canonical, provider, is_local, tier, type
