/*
    MART - the fact table.   GRAIN: ONE ROW PER ORDER.

    Say the grain out loud before writing a fact table. Almost every modelling
    mistake is a grain mistake.

    Materialized as a table (set in dbt_project.yml) because dashboards hit it
    over and over, so you pay the build cost once instead of on every query.
*/

with orders as (

    select * from {{ ref('stg_orders') }}

),

payments as (

    -- Aggregate payments to the SAME grain we are joining to (one row per
    -- order). Joining raw payments would fan out to one row per PAYMENT and
    -- silently double-count every order with two payments.
    select
        order_id,
        sum(amount)                                       as total_paid,
        sum(case when is_refund then amount else 0 end)   as total_refunded,
        count(*)                                          as payment_count,
        max(paid_at)                                      as last_paid_at
    from {{ ref('stg_payments') }}
    group by order_id

)

select
    o.order_id,
    o.customer_id,
    o.order_date,
    o.order_status,
    o.is_reversed,

    -- LEFT join: an unpaid order is still an order. An INNER join here would
    -- silently drop every unpaid order and nobody would notice for months.
    coalesce(p.total_paid, 0)      as total_paid,
    coalesce(p.total_refunded, 0)  as total_refunded,
    coalesce(p.payment_count, 0)   as payment_count,
    p.last_paid_at,
    p.order_id is null             as is_unpaid,

    current_timestamp()            as dbt_updated_at

from orders o
left join payments p on o.order_id = p.order_id
