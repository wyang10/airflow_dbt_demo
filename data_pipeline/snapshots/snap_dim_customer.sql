{% snapshot snap_dim_customer %}
{{
  config(
    target_database=target.database,
    target_schema=target.schema,
    unique_key='customer_key',
    strategy='check',
    check_cols=['customer_name', 'market_segment', 'address', 'phone']
  )
}}

select
  customer_key,
  customer_name,
  market_segment,
  address,
  phone,
  nation_key
from {{ ref('dim_customer') }}

{% endsnapshot %}
