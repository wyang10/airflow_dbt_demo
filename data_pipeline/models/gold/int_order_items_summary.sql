select
  order_date,
  count(*)                               as items_cnt,
  sum(net_item_sales_amount)             as gross_item_sales_amount,
  sum(item_discount_amount)              as item_discount_amount
from {{ ref('fct_order_items') }}
group by 1
