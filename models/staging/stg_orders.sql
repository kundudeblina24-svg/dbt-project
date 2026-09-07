/*
    STAGING MODEL  -  reads a UNITY CATALOG table

    Compare the source() call below with stg_customers.sql. One reads an
    external Postgres database, the other reads a Delta table inside Unity
    Catalog, and the SQL is otherwise identical. That is federation doing its
    job - the model does not care where the data physically lives.
*/

with source as (

    select * from {{ source('lakehouse', 'orders') }}

),

cleaned as (

    select
        cast(order_id as string)          as order_id,
        cast(customer_id as string)       as customer_id,
        cast(order_date as date)          as order_date,
        lower(trim(order_status))         as order_status,

        -- Business meaning stated once, here.
        lower(trim(order_status)) in ('returned', 'cancelled') as is_reversed,

        cast(_loaded_at as timestamp)     as loaded_at

    from source

)

select * from cleaned
