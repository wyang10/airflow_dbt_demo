{% snapshot snap_dim_sla_policy %}
{{
  config(
    target_database=target.database,
    target_schema=target.schema,
    unique_key='market_segment',
    strategy='check',
    check_cols=['sla_target_days', 'policy_version']
  )
}}

select
  market_segment,
  sla_target_days,
  policy_version
from {{ ref('dim_sla_policy') }}

{% endsnapshot %}
