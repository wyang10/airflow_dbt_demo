{% macro pricing_discounted_amount(price, discount) %}
  ({{ price }} * (1 - {{ discount }}))
{% endmacro %}