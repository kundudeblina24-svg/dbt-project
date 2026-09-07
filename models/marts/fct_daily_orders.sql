/*
    INCREMENTAL MODEL - the one materialization worth understanding properly.

    The three you must be able to explain:
       view         stored as a query; runs every time someone selects from it
       table        fully rebuilt from scratch on every dbt run
       incremental  only NEW or CHANGED rows are processed each run

    Incremental exists because rebuilding a billion-row table every night is
    wasteful. It is also more complex, so only use it when the table is
    genuinely large.

    Read the is_incremental() block - that is the entire idea.
*/

{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key='order_date'
) }}

with orders as (

    select * from {{ ref('fct_orders') }}

    {% if is_incremental() %}

    -- This block runs ONLY on incremental runs: not the first build, and not
    -- when you pass --full-refresh.
    --
    -- `this` (in braces, below) means "this model as it already exists".
    --
    -- The lookback re-reads days already processed, because a late payment can
    -- change a day's totals after the fact. That is exactly why the strategy
    -- is `merge` and not `append`: merge REPLACES those days, append would
    -- duplicate them. This is the single most common dbt interview question.
    where order_date >= (
        select date_sub(max(order_date), {{ var('lookback_days') }}) from {{ this }}
    )

    {% endif %}

)

select
    order_date,
    count(*)                                      as order_count,
    sum(case when is_reversed then 1 else 0 end)  as reversed_count,
    sum(total_paid)                               as revenue,
    sum(total_refunded)                           as refunds
from orders
group by order_date
