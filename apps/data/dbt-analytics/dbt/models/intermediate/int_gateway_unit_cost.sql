{{ config(materialized='view') }}

-- Custo unitário ($/token) por modelo canônico, derivado SÓ do gateway (LiteLLM = ledger com
-- pricing real do provider). É a taxa usada pra REPRECIFICAR os tokens do projeto rag, casando
-- por model_canonical (resolve deepseek-v4-flash-paid [rag] vs openrouter/.../deepseek-v4-flash
-- [gateway] = mesmo canônico).
--
-- Taxa BLENDED (input+output juntos) — aproximação consciente. Refinar via cost_details (input
-- cost / output cost separados) se a precisão importar. toFloat64 mantém tudo em float pro mart.
-- Modelos free/local: cost=0 -> unit=0 -> custo atribuído 0 (correto).
select
    model_canonical,
    sum(total_cost)                                            as gateway_cost,
    sum(total_tokens)                                          as gateway_tokens,
    toFloat64(sum(total_cost)) / nullIf(sum(total_tokens), 0)  as unit_cost_per_token
from {{ ref('int_observations_model') }}
where project_role = 'gateway'
group by model_canonical
