Welcome to your new dbt project!

### Using the starter project

Try running the following commands:

- dbt deps
- dbt run
- dbt test


### Resources:

执行层级流程图

[External Source]
  snowflake_sample_data.tpch_sf1
  ├─ orders(o_orderkey, o_orderdate, …)
  └─ lineitem(l_orderkey, l_extendedprice, l_discount, …)
        │
        ▼  (dbt source 定义 + 基础数据测试：unique / not_null / relationships)
────────────────────────────────────────────────────────────────────
[Staging 视图层]                (materialized: view)
  stg_tpch_orders           = select * from source('tpch','orders')
  stg_tpch_line_items       = select * from source('tpch','lineitem')
        │
        ▼  (ref)
────────────────────────────────────────────────────────────────────
[Intermediate 中间明细层]      (materialized: table)
  int_order_items = 
    join(stg_tpch_orders, stg_tpch_line_items on order_key)
    + 计算字段：
      discounted_amount = discounted_amount(extended_price, discount)  ← macro
      (并保留 extended_price, discount, order_date 等明细列)
        │
        ▼  (ref)
────────────────────────────────────────────────────────────────────
[Summary 汇总层]               (materialized: table)
  int_order_items_summary =
    group by order_date
    - items_cnt
    - gross_item_sales_amount = sum(discounted_amount)
    - item_discount_amount    = sum(extended_price * discount)
        │
        ▼  (ref)
────────────────────────────────────────────────────────────────────
[Fact 事实层]                   (materialized: table)
  fct_orders =
    select order_date, items_cnt, gross_item_sales_amount, item_discount_amount
    from int_order_items_summary
        │
        ▼
────────────────────────────────────────────────────────────────────
[Data Tests]
  Source 级：orders.o_orderkey unique/not_null，
             lineitem.l_orderkey → orders.o_orderkey relationships
  Model 级：fct_orders.order_key（示例字段）unique/not_null、
           status_code accepted_values（示例）、
           两个自定义 SQL 测试（date_valid / discount）


--------

执行顺序（dbt runtime 拓扑排序）
stg_* (views) → int_order_items → int_order_items_summary → fct_orders → dbt test
