{{ config(materialized='table', engine='MergeTree', order_by='(event_date, model_canonical)') }}

-- Gate Q2 (latência): percentis por dia × modelo. Só linhas com end_time (request concluído)
-- e latency >= 0 (guarda contra clock skew / eventos sem fim).
select
    event_date,
    model_canonical,
    provider,
    is_local,
    tier,
    count()                          as n,
    quantile(0.50)(latency_ms)       as p50_ms,
    quantile(0.95)(latency_ms)       as p95_ms,
    quantile(0.99)(latency_ms)       as p99_ms,
    avg(latency_ms)                  as avg_ms,
    max(latency_ms)                  as max_ms
from {{ ref('int_observations_model') }}
where end_time is not null
  and latency_ms >= 0
group by
    event_date, model_canonical, provider, is_local, tier
