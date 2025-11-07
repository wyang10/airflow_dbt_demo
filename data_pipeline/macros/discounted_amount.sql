{% macro discounted_amount(extended_price, discount) -%}
({{ extended_price }} * (1 - {{ discount }}))
{%- endmacro %}dbt run -s int_order_items_summary
