{{ config(materialized='table', tags=['gold', 'dim', 'policy']) }}

with segments as (
  select distinct market_segment
  from {{ ref('stg_tpch_customers') }}
  where market_segment is not null
)
select
  {{ dbt_utils.generate_surrogate_key(['market_segment']) }} as sla_policy_sk,
  market_segment,
  case market_segment
    when 'AUTOMOBILE' then 5
    when 'BUILDING' then 7
    when 'FURNITURE' then 10
    when 'HOUSEHOLD' then 7
    when 'MACHINERY' then 14
    else 7
  end as sla_target_days,
  '{{ env_var("SLA_POLICY_VERSION", "v1") }}' as policy_version
from segments

