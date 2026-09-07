{#
    A macro is reusable SQL written in Jinja.

    Why bother for something this small? Because the conversion now has ONE
    definition. If finance changes how it rounds, you edit here instead of
    hunting through every model - and it cannot drift out of sync between them.

    Used as:   {{ cents_to_dollars('amount_cents') }}
#}

{% macro cents_to_dollars(column_name, decimal_places=2) %}
    round( {{ column_name }} / 100.0, {{ decimal_places }} )
{% endmacro %}
