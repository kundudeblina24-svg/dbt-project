# dbt on Databricks - the concepts

Everything here maps to a file in this project. Open the file as you read.

---

## 1. Unity Catalog: the three-level namespace

Before dbt, understand where data lives. Unity Catalog uses **three levels**:

```
catalog . schema . table
   |         |        |
   |         |        +-- the actual table or view
   |         +----------- a folder of tables (older docs call this a "database")
   +--------------------- the top level: usually one per environment or domain
```

So `workspace.gold.fct_orders` means catalog `workspace`, schema `gold`,
table `fct_orders`.

Above all of it sits the **metastore** - one per region, shared by the
workspaces in your account. That is what makes UC different from the old Hive
metastore: governance is defined once at account level, not per workspace.

| Object | What it is |
|---|---|
| **Metastore** | Top container, one per region. Holds all catalogs |
| **Catalog** | Level 1. Typically per environment (`dev`, `prod`) or domain |
| **Schema** | Level 2. A group of tables. Where you set most grants |
| **Table** | Level 3. Managed (UC owns the files) or External (you own them) |
| **View** | A saved query. No storage |
| **Volume** | Governed storage for *files* rather than tables (CSV, PDF, images) |
| **Function** | A registered UDF |

**Managed vs External table** - a very common question:
- **Managed**: UC controls the data files. `DROP TABLE` deletes the data.
- **External**: you point at a path you control. `DROP TABLE` removes only the
  metadata; the files remain.

In this project the target schemas are `staging`, `gold` and `snapshots`,
inside whichever catalog `DBT_CATALOG` names.

---

## 2. What dbt actually does

dbt does **not** move data. It does exactly two things:

1. Takes your `SELECT` statement and wraps it in `CREATE TABLE AS` / `CREATE
   VIEW AS`, then sends it to Databricks.
2. Works out the **order** to run everything in, from your `ref()` calls.

That is it. All the compute happens in Databricks. dbt is a SQL compiler and
a scheduler-of-SQL. Say that in an interview and you sound like you get it.

---

## 3. sources vs refs

- `{{ source('lakehouse', 'orders') }}` - a table **someone else** created.
  Declared in `models/staging/_sources.yml`.
- `{{ ref('stg_orders') }}` - a table **dbt** created.

Why never hardcode a table name? Because `ref()` is what builds the dependency
graph. Hardcode it and dbt has no idea `fct_orders` needs `stg_orders` first,
and your build runs in the wrong order.

**The rule that keeps projects clean:** exactly one model may read a given
source table, and it lives in staging. When the source changes, one model
breaks and you know where to look.

---

## 4. The three materializations

Set in `dbt_project.yml`, or per model with a `config()` block.

| Materialization | What happens | Use when |
|---|---|---|
| **view** | Stored as a query. Runs on every select | Staging. Cheap, always fresh |
| **table** | Dropped and fully rebuilt each run | Marts. Queried often |
| **incremental** | Only new/changed rows processed | The table is genuinely large |

**The most-asked follow-up: why `merge` and not `append`?**

Look at `models/marts/fct_daily_orders.sql`. It re-reads the last 7 days on
every run, because a late payment can change a day's totals after the fact.

- With `append`, those 7 days get inserted **again** - duplicates.
- With `merge` plus a `unique_key`, they get **replaced** - correct.

The lookback window is *why* the strategy has to be merge. That connection is
the answer they are listening for.

---

## 5. Tests

Two kinds:

**Generic** - declared in YAML, reusable:
- `unique` - no duplicates. On the primary key, this **is** your grain assertion
- `not_null`
- `relationships` - referential integrity to another model
- `accepted_values` - the value is in a known list

**Singular** - a `.sql` file, e.g. `tests/assert_no_negative_revenue_days.sql`.

The inversion catches everyone: **you write the query that finds BAD rows.**
Rows returned = FAIL. No rows = pass.

**Severity.** `severity: warn` reports without failing the build. Use error for
things the pipeline controls; warn for things it merely observes. A missing
customer email is a data-entry problem, not a broken pipeline - failing a 3am
build on it just trains people to ignore alerts.

---

## 6. Snapshots (SCD Type 2)

`snapshots/snap_customers.sql`.

Source systems usually show only the **current** state. If a customer moves
country, the old value is gone, and every report about last quarter is quietly
wrong. A snapshot records a new row each time a tracked column changes.

**The operational point that gets asked:** a snapshot only captures what it
sees **when it runs**. Miss three days and that history is gone permanently -
you cannot backfill it. So snapshots run **first**, on their own schedule, and
their failure should page someone.

Two strategies: `timestamp` (cheaper, needs a reliable `updated_at`) and
`check` (compares column values; use when `updated_at` is untrustworthy).

---

## 7. Macros

`macros/cents_to_dollars.sql` - reusable SQL written in Jinja.

Why bother for something small? The conversion now has **one** definition. It
cannot drift out of sync between models.

`macros/generate_schema_name.sql` overrides a dbt default that surprises
everyone: dbt normally concatenates `<target_schema>_<custom_schema>`, so you
get `gold_gold`. The override makes it use your schema name as written.

**A real gotcha:** Jinja is evaluated **even inside SQL comments**. A `--` or
`/* */` comment containing live `{{ }}` braces will be parsed and can break the
build. See the note in `models/staging/stg_payments.sql`.

---

## 8. The commands

| Command | What it does |
|---|---|
| `dbt debug` | Tests the connection. Always run this first |
| `dbt run` | Builds models only |
| `dbt test` | Runs tests only |
| **`dbt build`** | **Models + tests together, in DAG order** |
| `dbt snapshot` | Runs snapshots |
| `dbt docs generate && dbt docs serve` | The lineage graph in a browser |

**Why `build` rather than `run` then `test`:** `build` tests each model before
building its children, so a bad model stops there. With `run` then `test`, bad
data has already propagated through fifty tables before any test runs.

Useful selectors:
```bash
dbt build --select stg_orders+     # this model and everything downstream
dbt build --select +fct_orders     # this model and everything upstream
dbt build --select state:modified+ # only what changed (needs --state)
dbt run --full-refresh             # rebuild incrementals from scratch
```
