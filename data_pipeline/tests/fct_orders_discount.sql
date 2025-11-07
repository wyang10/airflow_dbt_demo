-- 只要存在负折扣额就报错
select *
from {{ ref('fct_orders') }}
where item_discount_amount < 0
   or gross_item_sales_amount < 0