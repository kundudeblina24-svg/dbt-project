/*
    STAGING MODEL  -  reads the EXTERNAL Postgres database (via federation)

    A staging model's only job is to make raw data pleasant to work with:
    rename, cast, tidy. Nothing else.

    Allowed here:      renaming, casting, lower/trim, simple flags
    NOT allowed here:  joins, aggregation, business rules

    Why so strict? Because if staging stays boring, then when the source system
    changes, exactly one model breaks and you know exactly where to look.

    Rule: only ONE model may read a given source table, and it lives here.
*/

with source as (

    -- source() = a table someone else built. ref() = a table dbt built.
    -- This one resolves to the federated Postgres catalog.
    select * from {{ source('erp_postgres', 'customers') }}

),

cleaned as (

    select
        cast(customer_id as string)              as customer_id,

        trim(first_name)                          as first_name,
        trim(last_name)                           as last_name,
        concat_ws(' ', trim(first_name), trim(last_name)) as full_name,

        -- Same person signs up as "A@x.com" and " a@x.com ". Normalise once,
        -- here, so nothing downstream has to remember to.
        lower(trim(email))                        as email,

        upper(trim(country_code))                 as country_code,
        cast(signup_date as date)                 as signup_date,

        -- A named flag reads better downstream than repeating the condition.
        email is null or trim(email) = ''         as is_missing_email

    from source

)

select * from cleaned
