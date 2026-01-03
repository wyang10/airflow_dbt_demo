{{ config(materialized='table', tags=['gold', 'dim']) }}

with bounds as (
  select
    (select min(order_date)::date from {{ ref('stg_tpch_orders') }}) as start_date,
    (
      select
        max(coalesce(receipt_date, ship_date, commit_date))::date
      from {{ ref('stg_tpch_line_items') }}
    ) as end_date
),
spine as (
  select
    date_day
  from (
    select
      dateadd(day, seq4(), start_date) as date_day,
      end_date
    from bounds,
      table(generator(rowcount => 20000))
  )
  where date_day <= end_date
)
select
  date_day,
  year(date_day) as year,
  month(date_day) as month,
  day(date_day) as day,
  dayofweek(date_day) as day_of_week,
  date_trunc('month', date_day) as month_start
from spine
