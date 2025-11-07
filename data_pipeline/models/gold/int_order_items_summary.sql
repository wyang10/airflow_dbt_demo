select
  order_date,
  count(*)                               as items_cnt,
  sum(discounted_amount)                 as gross_item_sales_amount,
  sum(extended_price * discount)         as item_discount_amount
from {{ ref('int_order_items') }}
group by 1