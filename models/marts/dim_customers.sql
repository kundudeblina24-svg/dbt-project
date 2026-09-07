/*
    MART - the dimension.   GRAIN: ONE ROW PER CUSTOMER.

    Customer attributes plus a few facts rolled up to customer level, which is
    what makes a dimension useful for filtering and grouping in BI.
*/

with customers as (

    select * from {{ ref('stg_customers') }}

),

order_summary as (

    select
        customer_id,
        count(*)                                          as lifetime_orders,
        sum(case when not is_reversed then 1 else 0 end)  as completed_orders,
        min(order_date)                                   as first_order_date,
        max(order_date)                                   as most_recent_order_date
    from {{ ref('stg_orders') }}
    group by customer_id

),

value_summary as (

    select
        o.customer_id,
        sum(f.total_paid) as lifetime_value
    from {{ ref('fct_orders') }} f
    join {{ ref('stg_orders') }} o on f.order_id = o.order_id
    where not f.is_reversed
    group by o.customer_id

)

select
    c.customer_id,
    c.full_name,
    c.email,
    c.country_code,
    c.signup_date,

    coalesce(o.lifetime_orders, 0)   as lifetime_orders,
    coalesce(o.completed_orders, 0)  as completed_orders,
    coalesce(v.lifetime_value, 0)    as lifetime_value,
    o.first_order_date,
    o.most_recent_order_date,

    -- A business definition, in version control, where everyone reads the same
    -- rule - instead of copy-pasted into five different dashboards.
    case
        when coalesce(o.completed_orders, 0) = 0 then 'never_ordered'
        when o.completed_orders = 1              then 'one_time'
        when o.completed_orders <= 3             then 'repeat'
        else 'loyal'
    end                              as customer_segment

from customers c
left join order_summary o on c.customer_id = o.customer_id
left join value_summary v on c.customer_id = v.customer_id
