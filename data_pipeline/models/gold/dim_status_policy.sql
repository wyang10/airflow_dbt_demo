{{ config(materialized='table', tags=['gold', 'dim', 'policy']) }}

select
  event_type,
  event_order,
  sla_target_days,
  '{{ env_var("STATUS_POLICY_VERSION", "v1") }}' as policy_version
from (
  select 'COMMIT' as event_type, 1 as event_order, null::int as sla_target_days
  union all
  select 'SHIP' as event_type, 2 as event_order, 3 as sla_target_days
  union all
  select 'RECEIPT' as event_type, 3 as event_order, 7 as sla_target_days
)

