{{ config(materialized='table', tags=['gold', 'dim']) }}

with src as (
  select * from {{ ref('stg_tpch_suppliers') }}
)
select
  {{ dbt_utils.generate_surrogate_key(['supplier_key']) }} as supplier_sk,
  supplier_key,
  supplier_name,
  nation_key,
  account_balance,
  phone,
  address
from src

