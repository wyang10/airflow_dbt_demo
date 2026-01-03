{{ config(materialized='table', tags=['silver']) }}

with orders as (
  select * from {{ ref('stg_tpch_orders') }}
),
line_items as (
  select * from {{ ref('stg_tpch_line_items') }}
),
customers as (
  select * from {{ ref('stg_tpch_customers') }}
),
joined as (
  select
    line_items.order_key,
    line_items.line_number,
    line_items.part_key,
    line_items.supplier_key,
    orders.customer_key,
    customers.market_segment,
    orders.order_date::date as order_date,
    line_items.commit_date::date as commit_date_raw,
    line_items.ship_date::date as ship_date_raw,
    line_items.receipt_date::date as receipt_date_raw
  from line_items
  join orders on orders.order_key = line_items.order_key
  left join customers on customers.customer_key = orders.customer_key
),
normalized_dates as (
  select
    *,
    least(commit_date_raw, ship_date_raw, receipt_date_raw) as commit_date,
    case
      when commit_date_raw between ship_date_raw and receipt_date_raw then commit_date_raw
      when commit_date_raw between receipt_date_raw and ship_date_raw then commit_date_raw
      when ship_date_raw between commit_date_raw and receipt_date_raw then ship_date_raw
      when ship_date_raw between receipt_date_raw and commit_date_raw then ship_date_raw
      else receipt_date_raw
    end as ship_date,
    greatest(commit_date_raw, ship_date_raw, receipt_date_raw) as receipt_date
  from joined
)

select
  order_key,
  line_number,
  part_key,
  supplier_key,
  customer_key,
  market_segment,
  order_date,
  commit_date,
  ship_date,
  receipt_date,
  commit_date_raw,
  ship_date_raw,
  receipt_date_raw,
  datediff('day', commit_date, ship_date) as ship_minus_commit_days,
  datediff('day', ship_date, receipt_date) as receipt_minus_ship_days,
  (ship_date > commit_date) as is_ship_late,
  (receipt_date > dateadd('day', 7, ship_date)) as is_receipt_late_default
from normalized_dates
