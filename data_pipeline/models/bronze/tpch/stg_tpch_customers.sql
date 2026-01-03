select
  c_custkey as customer_key,
  c_name as customer_name,
  c_mktsegment as market_segment,
  c_nationkey as nation_key,
  c_acctbal as account_balance,
  c_phone as phone,
  c_address as address,
  c_comment as comment
from {{ source('tpch', 'customer') }}

