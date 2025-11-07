{{ config(materialized='table', tags=['silver']) }}

-- 示例：把 bronze 的原始表做一次业务清洗/维度补齐
with o as (
  select * from {{ ref('stg_tpch_orders') }}        -- bronze
),
l as (
  select * from {{ ref('stg_tpch_line_items') }}    -- bronze
)
select
  o.order_key                  as order_id,
  o.order_date::date           as order_date,
  o.customer_key               as customer_id,
  sum(l.extended_price)        as gross_item_sales_amount,
  sum(l.discount)              as total_discount
from o
join l on l.order_key = o.order_key
group by 1,2,3
