{% snapshot snap_dim_status_policy %}
{{
  config(
    target_database=target.database,
    target_schema=target.schema,
    unique_key='event_type',
    strategy='check',
    check_cols=['event_order', 'sla_target_days', 'policy_version']
  )
}}

select
  event_type,
  event_order,
  sla_target_days,
  policy_version
from {{ ref('dim_status_policy') }}

{% endsnapshot %}
