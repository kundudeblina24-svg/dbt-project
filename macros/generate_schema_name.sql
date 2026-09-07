{#
    WHY THIS MACRO EXISTS - a real dbt gotcha.

    By default dbt does NOT use your custom schema as-is. It concatenates:
        <target schema>_<custom schema>
    So target schema `gold` plus custom schema `staging` gives `gold_staging`,
    and `gold` plus `gold` gives the ridiculous `gold_gold`.

    That default exists so several developers can share one warehouse without
    overwriting each other. In a single-catalog project it is just noise.

    Overriding it like this gives clean names: staging, gold, snapshots.
#}

{% macro generate_schema_name(custom_schema_name, node) -%}

    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}

{%- endmacro %}
