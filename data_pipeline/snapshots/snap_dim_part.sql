{% snapshot snap_dim_part %}
{{
  config(
    target_database=target.database,
    target_schema=target.schema,
    unique_key='part_key',
    strategy='check',
    check_cols=['part_name', 'manufacturer', 'brand', 'part_type', 'part_size', 'container', 'retail_price']
  )
}}

select
  part_key,
  part_name,
  manufacturer,
  brand,
  part_type,
  part_size,
  container,
  retail_price
from {{ ref('dim_part') }}

{% endsnapshot %}
