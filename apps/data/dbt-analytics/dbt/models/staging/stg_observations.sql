{{ config(materialized='view') }}

-- observations é ReplacingMergeTree -> FINAL pra deduplicar; is_deleted=0 tira soft-deletes.
-- latency via toUnixTimestamp64Milli (start/end são DateTime64(3)) — exato e sem depender
-- de suporte a unidade 'millisecond' no dateDiff.
select
    id,
    project_id,
    type,
    level,
    provided_model_name,
    start_time,
    end_time,
    toDate(start_time)                                                      as event_date,
    toUnixTimestamp64Milli(end_time) - toUnixTimestamp64Milli(start_time)   as latency_ms,
    ifNull(total_cost, 0)                                                   as total_cost,
    usage_details['input']                                                  as input_tokens,
    usage_details['output']                                                 as output_tokens,
    usage_details['total']                                                  as total_tokens
from {{ source('langfuse', 'observations') }} final
where is_deleted = 0
