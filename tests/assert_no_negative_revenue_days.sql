/*
    A SINGULAR TEST.

    dbt has two kinds of test:
      GENERIC   the ones declared in .yml (unique, not_null, relationships,
                accepted_values). Reusable, attached to a column.
      SINGULAR  a .sql file like this one. Just a query.

    The rule that trips people up: you write the query that finds BAD rows.
    Rows returned = test FAILS. No rows = pass.

    This checks a business rule no generic test can express: a day should never
    have negative net revenue, because that means refunds exceeded sales and a
    human should look at it.
*/

select
    order_date,
    revenue,
    refunds
from {{ ref('fct_daily_orders') }}
where revenue < 0
