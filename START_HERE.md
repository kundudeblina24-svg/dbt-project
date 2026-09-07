# Start here — how to read this folder, and how to test it yourself

Two parts: **read in this order**, then **do the eight exercises**. About two
hours total. Don't skip the exercises — reading dbt teaches you very little.

---

# PART 1 — Reading order

Open the files in this order. Each one builds on the last.

### 1. `dbt_project.yml` — the rules of the project
The config that governs everything. Look for:
- `profile:` — which connection to use
- `models:` → `staging: +materialized: view` and `marts: +materialized: table`

**That's a default.** Every staging model becomes a view and every mart a table,
without any model saying so. A model can override it with its own `config()`.

### 2. `profiles.yml` — the connection
How dbt reaches Databricks. Notice **every value is `env_var(...)`** — no
secrets. That's why this file is safe to commit. The real token lives in `.env`,
which is gitignored.

Look at `catalog:` and `schema:` — that's the Unity Catalog target.

### 3. `models/staging/_sources.yml` — where data comes FROM
The most important file for understanding the project. Two sources declared:
- **`erp_postgres`** — an external Postgres database, read through Lakehouse
  Federation
- **`lakehouse`** — a table already inside Unity Catalog

A *source* is a table dbt did **not** build. You declare it once here, then use
`{{ source('lakehouse', 'orders') }}` instead of typing a table name.

### 4. `models/staging/stg_orders.sql` — the simplest model
Read the comments. A staging model only renames, casts and tidies. **No joins,
no aggregation, no business logic.** If staging stays boring, then when a source
changes exactly one model breaks and you know where to look.

### 5. `models/staging/_staging.yml` — the tests
Tests live in YAML next to the models. `unique`, `not_null`, `relationships`,
`accepted_values`.

Find `severity: warn`. Two tests are set to warn on purpose so you can see a
failing test without the project going red.

### 6. `models/marts/fct_orders.sql` — a real fact table
Grain: **one row per order.** Look for two things:
- payments are aggregated to order level **before** the join — otherwise an
  order with 3 payments becomes 3 rows and every SUM triples
- it's a `LEFT` join, because an unpaid order is still an order

### 7. `models/marts/fct_daily_orders.sql` — the incremental one
**The most important file in the folder.** Find the `{% if is_incremental() %}`
block. That SQL only runs on incremental runs — not the first build, not on
`--full-refresh`.

The 7-day lookback is *why* the strategy is `merge` and not `append`.

### 8. `snapshots/snap_customers.sql` — history
How dbt records Type 2 history. Read the comment about a snapshot only
capturing what it sees **when it runs**.

### 9. `macros/` — reusable SQL
- `cents_to_dollars.sql` — one definition of the conversion
- `generate_schema_name.sql` — overrides a dbt default that would otherwise
  name your schema `gold_gold`

### 10. `tests/assert_no_negative_revenue_days.sql` — a singular test
Just a query. **You write the query that finds BAD rows.** Rows returned =
FAIL. That inversion catches everyone.

### Reference, not reading
`LEARNING_GUIDE.md` (concepts) · `INTERVIEW_QA.md` (Q&A + SQL) ·
`OPERATIONS.md` (GitHub + scheduling) · `RUNBOOK.md` (worked example)

---

# PART 2 — Eight exercises

```bash
cd "d:/Databrics notes/dbt-databricks-learning"
cp .env.example .env        # fill in host, http_path, token
source env.sh
```

---

## Exercise 1 — Connect (5 min)

```bash
dbt debug --target dev
```

**Expect:** `All checks passed!`

**Look at:** the `http_path` line in the output. If it shows anything starting
`C:/Program Files/Git/...`, Git Bash mangled it — `source env.sh` fixes that.

**Check yourself:** Which file did dbt read the connection from, and where did
the token come from?

---

## Exercise 2 — See the project before running it (10 min)

```bash
dbt ls --resource-type model
dbt ls --resource-type test | head -20
dbt ls --select stg_orders+
```

**Look at:** the last one lists `stg_orders` **and everything downstream of it**.
That's the `+` selector, and it's how CI decides what to rebuild.

**Check yourself:** How many models are there? Which models depend on
`stg_orders`?

---

## Exercise 3 — Compile, don't run (15 min) ⭐

```bash
dbt compile --target dev
```

Nothing executed. Now open:

```
target/compiled/dbt_databricks_learning/models/staging/stg_orders.sql
```

Compare with `models/staging/stg_orders.sql`.

**You'll see** `{{ source('lakehouse', 'orders') }}` became
`` `workspace`.`learn_raw`.`orders` ``.

Now open the compiled `models/marts/fct_orders.sql` and find what `ref()`
turned into.

**This is the single most important exercise.** dbt never touches data — it
resolves Jinja into plain SQL and hands it to Databricks.

**Check yourself:** If a model gives a weird result, which folder do you open
first?

---

## Exercise 4 — Build staging, then query it (15 min)

```bash
dbt run --select staging --target dev
```

Now go to the **Databricks SQL editor**:

```sql
SHOW TABLES IN workspace.staging;
SELECT * FROM workspace.staging.stg_orders LIMIT 10;

SELECT table_name, table_type
FROM workspace.information_schema.tables
WHERE table_schema = 'staging';
```

**Check yourself:** Are they tables or views? Which line of `dbt_project.yml`
decided that?

---

## Exercise 5 — Run tests and find the bad row (20 min) ⭐

```bash
dbt test --select stg_orders --target dev
```

**Expect:** `PASS=4 WARN=1`

Now investigate the warning. Find its compiled SQL:

```bash
ls target/compiled/dbt_databricks_learning/models/staging/_staging.yml/
```

Open the `relationships_...` file, paste it into the Databricks SQL editor,
run it.

**You'll see the actual offending row.** One order points at a customer who
doesn't exist.

**Check yourself:** Why does this WARN instead of ERROR? Where is that set?

---

## Exercise 6 — Prove the incremental (20 min) ⭐

```bash
dbt run --select fct_daily_orders --target dev     # run it
dbt run --select fct_daily_orders --target dev     # run it AGAIN
```

Now in Databricks:

```sql
SELECT version, operation,
       operationMetrics['numTargetRowsUpdated'] AS updated,
       operationMetrics['numOutputRows']        AS output
FROM (DESCRIBE HISTORY workspace.gold.fct_daily_orders)
ORDER BY version;
```

**Expect:**
```
version  operation                          updated  output
0        CREATE OR REPLACE TABLE AS SELECT     -       15
1        MERGE                                 2        2
2        MERGE                                 2        2
```

Then force a full rebuild and watch it go back to `CREATE OR REPLACE`:

```bash
dbt run --select fct_daily_orders --full-refresh --target dev
```

**Check yourself:** Why does the second run write 2 rows instead of 15? What
would go wrong if the strategy were `append` instead of `merge`?

---

## Exercise 7 — Break it on purpose (15 min)

In `models/staging/_staging.yml`, find the `accepted_values` list for
`order_status` and delete `'delivered'`. Then:

```bash
dbt test --select stg_orders --target dev
```

**Expect:** `ERROR=1` and `Got 1 result, configured to fail if != 0`

Put `'delivered'` back and re-run. Back to `ERROR=0`.

**Check yourself:** What's the difference between WARN and ERROR, and which
would you use for a missing email address?

---

## Exercise 8 — The full build and the DAG (20 min)

```bash
dbt build --target dev
```

**Expect:** `PASS=31 WARN=2 ERROR=0 TOTAL=33`

Watch the **order** models build in — staging first, then marts. Nobody
specified that order; dbt worked it out from the `ref()` calls.

```bash
dbt docs generate --target dev
dbt docs serve
```

Click a model → **Lineage** tab. Sources through staging to marts.

**Check yourself:** Why use `dbt build` instead of `dbt run` then `dbt test`?

---

# The answers

<details>
<summary>Click after you've tried them</summary>

**1.** `profiles.yml`, which reads env vars set by `env.sh` from `.env`.

**2.** 6 models. `fct_orders` depends on `stg_orders`, and `dim_customers` and
`fct_daily_orders` depend on `fct_orders`.

**3.** `target/compiled/` — it shows exactly what dbt sent.

**4.** Views. `dbt_project.yml` → `staging: +materialized: view`.

**5.** Because `severity: warn` is set on that test in `_staging.yml`. A missing
parent row is a data problem, not a pipeline defect.

**6.** The `is_incremental()` block filters to the last 7 days, so only those
rows are processed. With `append` those 7 days would be inserted *again* every
run — duplicates. `merge` replaces them.

**7.** WARN reports and keeps going; ERROR fails the build. A missing email is
a data-entry problem, so warn. A duplicate primary key is a real defect, so
error.

**8.** `build` tests each model **before** building its children, so a bad model
stops there. With run-then-test, bad data has already spread through every
downstream table before any test runs.

</details>

---

# If you only do three

**Exercise 3** (compile — what dbt actually is), **Exercise 5** (debugging a
failing test), **Exercise 6** (proving the incremental). Those three cover most
of what gets asked.
