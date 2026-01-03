with src as (
  select * from {{ source('tpch', 'lineitem') }}
)
select
  l_orderkey   as order_key,
  l_partkey    as part_key,
  l_suppkey    as supplier_key,
  l_linenumber as line_number,
  l_extendedprice as extended_price,
  l_discount   as discount,
  l_shipdate   as ship_date,
  l_commitdate as commit_date,
  l_receiptdate as receipt_date,
  l_returnflag as return_flag,
  l_linestatus as line_status
from src
