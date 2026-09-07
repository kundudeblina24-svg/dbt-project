/*
    STAGING MODEL  -  payments, from Unity Catalog

    Shows a macro in use - see the select list below, and macros/cents_to_dollars.sql

    NOTE: Jinja is evaluated even inside SQL comments, so a comment that talks
    about a macro must not contain live double-brace syntax. That is a real and
    very confusing dbt gotcha.
*/

with source as (

    select * from {{ source('lakehouse', 'payments') }}

),

cleaned as (

    select
        cast(payment_id as string)                as payment_id,
        cast(order_id as string)                  as order_id,
        lower(trim(payment_method))               as payment_method,

        cast(amount_cents as bigint)              as amount_cents,
        {{ cents_to_dollars('amount_cents') }}    as amount,

        -- Refunds stay NEGATIVE on purpose, so summing payments nets them
        -- automatically and no downstream model has to subtract them.
        amount_cents < 0                          as is_refund,

        cast(paid_at as date)                     as paid_at,
        cast(_loaded_at as timestamp)             as loaded_at

    from source

)

select * from cleaned
