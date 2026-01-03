{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key='shipment_event_key',
    cluster_by=['event_date', 'order_key'],
    tags=['gold', 'fact']
) }}

with
{% if is_incremental() %}
cutoff as (
  select
    dateadd(day, -7, coalesce(max(event_date), to_date('1900-01-01'))) as cutoff_date
  from {{ this }}
),
refresh_order_items as (
  select distinct
    order_key,
    line_number
  from {{ this }}
  where
    event_date >= (select cutoff_date from cutoff)
    or days_since_prior_event < 0
),
{% endif %}
base as (
  select
    b.*
  from {{ ref('int_shipment_events') }} as b
  {% if is_incremental() %}
  where exists (
    select 1
    from refresh_order_items r
    where r.order_key = b.order_key and r.line_number = b.line_number
  )
  {% endif %}
),
status_policy as (
  select * from {{ ref('dim_status_policy') }}
),
sla_policy as (
  select * from {{ ref('dim_sla_policy') }}
),
events as (
  select
    to_varchar(order_key) || '-' || to_varchar(line_number) || '-COMMIT' as shipment_event_key,
    order_key,
    line_number,
    part_key,
    supplier_key,
    customer_key,
    market_segment,
    {{ dbt_utils.generate_surrogate_key(['customer_key']) }} as customer_sk,
    {{ dbt_utils.generate_surrogate_key(['part_key']) }} as part_sk,
    {{ dbt_utils.generate_surrogate_key(['supplier_key']) }} as supplier_sk,
    'COMMIT' as event_type,
    commit_date as event_date,
    null::int as days_since_prior_event
  from base

  union all

  select
    to_varchar(order_key) || '-' || to_varchar(line_number) || '-SHIP' as shipment_event_key,
    order_key,
    line_number,
    part_key,
    supplier_key,
    customer_key,
    market_segment,
    {{ dbt_utils.generate_surrogate_key(['customer_key']) }} as customer_sk,
    {{ dbt_utils.generate_surrogate_key(['part_key']) }} as part_sk,
    {{ dbt_utils.generate_surrogate_key(['supplier_key']) }} as supplier_sk,
    'SHIP' as event_type,
    ship_date as event_date,
    ship_minus_commit_days as days_since_prior_event
  from base

  union all

  select
    to_varchar(order_key) || '-' || to_varchar(line_number) || '-RECEIPT' as shipment_event_key,
    order_key,
    line_number,
    part_key,
    supplier_key,
    customer_key,
    market_segment,
    {{ dbt_utils.generate_surrogate_key(['customer_key']) }} as customer_sk,
    {{ dbt_utils.generate_surrogate_key(['part_key']) }} as part_sk,
    {{ dbt_utils.generate_surrogate_key(['supplier_key']) }} as supplier_sk,
    'RECEIPT' as event_type,
    receipt_date as event_date,
    receipt_minus_ship_days as days_since_prior_event
  from base
),
enriched as (
  select
    e.*,
    p.event_order,
    p.sla_target_days as status_sla_target_days,
    s.sla_target_days as segment_sla_target_days,
    case
      when p.sla_target_days is null then null
      when e.days_since_prior_event is null then null
      else e.days_since_prior_event > p.sla_target_days
    end as is_late_against_status_policy
  from events e
  left join status_policy p on p.event_type = e.event_type
  left join sla_policy s on s.market_segment = e.market_segment
)
select * from enriched
