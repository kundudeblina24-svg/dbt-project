# Runbook — running and testing dbt on Databricks

Every step below was executed against a live Databricks workspace. The outputs
shown are real.

---

## Step 0 — Set up (once)

```bash
cp .env.example .env      # fill in host, http_path, token
```

Then before every session:

```bash
source env.sh
```

`env.sh` exists for one reason. **Git Bash on Windows rewrites environment
variables that look like Unix paths.** Setting
`DATABRICKS_HTTP_PATH=/sql/1.0/warehouses/abc` silently becomes
`C:/Program Files/Git/sql/1.0/warehouses/abc`, and dbt then hangs for 15+
minutes retrying a URL that does not exist.

The fix is `export MSYS2_ENV_CONV_EXCL="DATABRICKS_HTTP_PATH"`.

Do **not** use `MSYS_NO_PATHCONV=1` — that disables conversion globally and
breaks `DBT_PROFILES_DIR` instead.

---

## Step 1 — `dbt debug`

Always first. Catches config problems in seconds instead of failing halfway
through a build.

```bash
dbt debug --target dev
```

```
profiles.yml file [OK found and valid]
dbt_project.yml file [OK found and valid]
host: https://dbc-....cloud.databricks.com
http_path: /sql/1.0/warehouses/xxxxxxxxxxxxxxxx
catalog: workspace
Connection test: [OK connection ok]
All checks passed!
```

If this hangs, check `http_path` in the output — that is exactly how the
mangling bug shows itself.

---

## Step 2 — `dbt deps`

```bash
dbt deps
```

Installs packages from `packages.yml`. **This project has none**, so it
correctly reports `No packages were found in packages.yml`. You only need this
step when the project uses `dbt_utils`, `dbt_expectations` etc.

---

## Step 3 — `dbt compile` — the step that teaches you what dbt is

```bash
dbt compile --target dev
```

Compiles the SQL **without executing anything**. Then open the output:

```
target/compiled/dbt_databricks_learning/models/staging/stg_orders.sql
```

**What you wrote:**
```sql
select * from {{ source('lakehouse', 'orders') }}
```

**What dbt sent to Databricks:**
```sql
select * from `workspace`.`learn_raw`.`orders`
```

And `{{ ref('stg_orders') }}` became `` `workspace`.`staging`.`stg_orders` ``.

That is the whole idea. **dbt never touches data** — it resolves Jinja into
plain SQL and hands it to the warehouse. All the compute is Databricks.

> Read `target/compiled/` whenever a model behaves oddly. Nine times out of ten
> the answer is visible there.

---

## Step 4 — Run one model

```bash
dbt run --select stg_orders --target dev
```

```
1 of 1 OK created sql view model staging.stg_orders  [OK in 2.95s]
Done. PASS=1 WARN=0 ERROR=0
```

Selectors worth knowing:

```bash
dbt run --select stg_orders      # just this one
dbt run --select stg_orders+     # this model AND everything downstream
dbt run --select +fct_orders     # this model AND everything upstream
dbt run --select staging         # the whole folder
dbt run --select tag:daily       # everything with that tag
```

---

## Step 5 — Test it

```bash
dbt test --select stg_orders --target dev
```

```
PASS not_null_stg_orders_customer_id
PASS accepted_values_stg_orders_order_status__...
PASS not_null_stg_orders_order_id
WARN 1 relationships_stg_orders_customer_id__...
PASS unique_stg_orders_order_id
Done. PASS=4 WARN=1 ERROR=0
```

That `WARN 1` is deliberate — order 115 points at customer 99, who does not
exist. It is set to `severity: warn` so you can see a failing test without the
project going red.

### How to debug a failing test

dbt writes **every test as runnable SQL**. Find it:

```
target/compiled/.../relationships_stg_orders_customer_id__....sql
```

```sql
with child as (
    select customer_id as from_field
    from `workspace`.`staging`.`stg_orders`
    where customer_id is not null
),
parent as (
    select customer_id as to_field
    from `workspace`.`staging`.`stg_customers`
)
select from_field
from child
left join parent on child.from_field = parent.to_field
where parent.to_field is null
```

Paste that into the Databricks SQL editor and you see the offending rows.
**This is the answer to "how do you investigate a test failure?"** — you do not
guess, you run the test's own SQL.

---

## Step 6 — `dbt build` — the one you actually use

```bash
dbt build --target dev
```

```
OK created sql view model staging.stg_customers
OK created sql view model staging.stg_orders
OK created sql view model staging.stg_payments
WARN 1 not_null_stg_customers_email
WARN 1 relationships_stg_orders_customer_id__...
OK created sql table model gold.fct_orders
OK snapshotted snapshots.snap_customers
OK created sql table model gold.dim_customers
OK created sql incremental model gold.fct_daily_orders
Done. PASS=31 WARN=2 ERROR=0 SKIP=0 TOTAL=33
```

**Why `build` and not `run` then `test`:** build interleaves them in dependency
order — it builds a model, tests it, and only then builds its children. With
run-then-test, a broken model has already pushed bad data through every
downstream table before any test fires.

---

## Step 7 — Prove the incremental actually merges

Run it a second time, then read the transaction log:

```sql
SELECT version, operation,
       operationMetrics['numTargetRowsUpdated'] AS updated,
       operationMetrics['numOutputRows']        AS output
FROM (DESCRIBE HISTORY workspace.gold.fct_daily_orders)
ORDER BY version;
```

```
version  operation                          updated  output
0        CREATE OR REPLACE TABLE AS SELECT     -       15     <- first build: whole table
1        MERGE                                 2        2     <- only the lookback window
2        MERGE                                 2        2
3        MERGE                                 2        2
```

**15 rows on the first build, 2 rows on every run after.** That is the entire
argument for incremental, with numbers you can quote.

And the compiled SQL on an incremental run shows the lookback:

```sql
where order_date >= (
    select date_sub(max(order_date), 7) from `workspace`.`gold`.`fct_daily_orders`
)
```

That is why the strategy must be `merge` and not `append` — those 7 days
already exist, so append would duplicate them.

---

## Step 8 — Break something on purpose

You need to know what a real failure looks like. In `_staging.yml`, remove
`'delivered'` from the `accepted_values` list, then:

```bash
dbt test --select stg_orders --target dev
```

```
FAIL 1 accepted_values_stg_orders_order_status__placed__shipped__returned__cancelled
Failure in test accepted_values_... (models\staging\_staging.yml)
  Got 1 result, configured to fail if != 0
Done. PASS=3 WARN=1 ERROR=1
```

Note the difference: **`WARN` reports, `ERROR` fails the build.** That is the
`severity` setting, and choosing between them is a real design decision — error
on what the pipeline controls, warn on what it merely observes.

Put `'delivered'` back and it returns to `ERROR=0`.

---

## Step 9 — The lineage graph

```bash
dbt docs generate --target dev
dbt docs serve
```

Opens in a browser. Click any model to see its lineage, columns, tests and
compiled SQL. **This is the single most convincing thing to show someone.**

---

## The commands, summarised

| Command | What it does |
|---|---|
| `dbt debug` | Test the connection. Always first |
| `dbt deps` | Install packages (only if `packages.yml` exists) |
| `dbt compile` | Generate SQL without running it |
| `dbt run` | Build models only |
| `dbt test` | Run tests only |
| **`dbt build`** | **Models + tests, in DAG order. Use this** |
| `dbt snapshot` | Run snapshots — **first**, on their own schedule |
| `dbt run --full-refresh` | Rebuild incrementals from scratch |
| `dbt docs generate && dbt docs serve` | The lineage graph |

## Where things land in Unity Catalog

```
workspace.learn_raw.*    the sources (not built by dbt)
workspace.staging.*      views      <- materialized: view
workspace.gold.*         tables     <- materialized: table / incremental
workspace.snapshots.*    snapshots
```

Ephemeral models appear **nowhere** — they are never built as objects, just
inlined as CTEs.
