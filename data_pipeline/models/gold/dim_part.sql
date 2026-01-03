{{ config(materialized='table', tags=['gold', 'dim']) }}

with src as (
  select * from {{ ref('stg_tpch_parts') }}
)
select
  {{ dbt_utils.generate_surrogate_key(['part_key']) }} as part_sk,
  part_key,
  part_name,
  manufacturer,
  brand,
  part_type,
  part_size,
  container,
  retail_price
from src

