{{ config(enabled=false) }}

-- Disabled duplicate of gold/fct_orders.sql to avoid name collision
with order_item_summary as (
  select * from {{ ref('int_order_items_summary') }}
)
select
  order_date,
  items_cnt,
  gross_item_sales_amount,
  item_discount_amount
from order_item_summary
