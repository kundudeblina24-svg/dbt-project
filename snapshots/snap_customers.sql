{#
    SNAPSHOT - how dbt records history (Slowly Changing Dimension Type 2)

    Source systems usually show only the CURRENT state. If a customer moves
    from Nigeria to Ghana, the old value is simply gone - and every report
    about last quarter is now quietly wrong.

    A snapshot fixes that: each time a tracked column changes, it closes the
    old row (dbt_valid_to) and opens a new one.

    THE THING TO REMEMBER, and the follow-up question that catches people:
    a snapshot only captures what it sees WHEN IT RUNS. If it does not run for
    three days, those three days of changes are lost permanently - you cannot
    backfill them. That is why snapshots run FIRST, on their own schedule, and
    why their failure should page somebody.

    Try it: run `dbt snapshot`, change a country in the source table, run
    `dbt snapshot` again, then select from the snapshot and look at the
    dbt_valid_from / dbt_valid_to columns.
#}

{% snapshot snap_customers %}

{{
    config(
      target_schema='snapshots',
      unique_key='customer_id',

      strategy='check',
      check_cols=['country_code', 'email']
    )
}}

select customer_id, full_name, email, country_code, signup_date
from {{ ref('stg_customers') }}

{% endsnapshot %}
