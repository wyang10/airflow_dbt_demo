select
  s_suppkey as supplier_key,
  s_name as supplier_name,
  s_nationkey as nation_key,
  s_acctbal as account_balance,
  s_phone as phone,
  s_address as address,
  s_comment as comment
from {{ source('tpch', 'supplier') }}

