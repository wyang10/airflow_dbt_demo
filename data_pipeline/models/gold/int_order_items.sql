with orders as (select * from {{ ref('stg_tpch_orders') }}),
     line_item as (select * from {{ ref('stg_tpch_line_items') }})

select
  line_item.order_key       as order_item_key,
  line_item.part_key,
  line_item.line_number,
  line_item.extended_price,
  line_item.discount       as discount,   -- ← 新增
  orders.order_key,
  orders.customer_key,
  orders.order_date,
  {{ discounted_amount("line_item.extended_price", "line_item.discount") }} as discounted_amount
from orders
join line_item
  on orders.order_key = line_item.order_key
order by orders.order_date