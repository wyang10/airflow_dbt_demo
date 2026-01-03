{% macro discounted_amount(extended_price, discount) -%}
({{ extended_price }} * (1 - {{ discount }}))
{%- endmacro %}
