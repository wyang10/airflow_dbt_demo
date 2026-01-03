{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key='order_item_key',
    cluster_by=['order_date', 'order_key'],
    tags=['gold', 'fact']
) }}

with src as (
  select
    order_item_key,
    order_key,
    line_number,
    order_date::date as order_date,
    customer_key,
    part_key,
    supplier_key,
    {{ dbt_utils.generate_surrogate_key(['customer_key']) }} as customer_sk,
    {{ dbt_utils.generate_surrogate_key(['part_key']) }} as part_sk,
    {{ dbt_utils.generate_surrogate_key(['supplier_key']) }} as supplier_sk,
    extended_price,
    discount,
    discounted_amount as net_item_sales_amount,
    (extended_price * discount) as item_discount_amount
  from {{ ref('int_order_items') }}
)
select * from src
{% if is_incremental() %}
where order_date >= (select dateadd(day, -7, max(order_date)) from {{ this }})
{% endif %}

