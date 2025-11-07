
with src as (
  select * from {{ source('tpch', 'lineitem') }}
)
select
  l_orderkey   as order_key,
  l_partkey    as part_key,
  l_linenumber as line_number,
  l_extendedprice as extended_price,
  l_discount   as discount
from src