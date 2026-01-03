{{ config(materialized='table', tags=['gold', 'dim']) }}

with src as (
  select * from {{ ref('stg_tpch_customers') }}
)
select
  {{ dbt_utils.generate_surrogate_key(['customer_key']) }} as customer_sk,
  customer_key,
  customer_name,
  market_segment,
  nation_key,
  account_balance,
  phone,
  address
from src

