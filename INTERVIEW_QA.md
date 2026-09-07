# Interview questions, with answers

Three parts: **Unity Catalog**, **dbt**, and **hands-on SQL** you can run right
now against the `samples` catalog that exists in every Databricks workspace.

Every SQL query below was executed against a live Free Edition workspace. The
outputs shown are real.

---

# Part 1 - Unity Catalog

### Q: Explain the Unity Catalog namespace.

Three levels: **`catalog.schema.table`**.

```
metastore                one per region, shared across workspaces in the account
  └── catalog            level 1 - usually per environment (dev/prod) or domain
        └── schema       level 2 - a group of tables. Where most grants sit
              └── table  level 3 - the data itself
```

So `workspace.gold.fct_orders` = catalog `workspace`, schema `gold`, table
`fct_orders`.

The old Hive metastore had only two levels (`schema.table`) and was scoped to a
single workspace. Unity Catalog adds the catalog level and moves governance up
to the **account**, so one grant covers every workspace in the region.

### Q: What objects live in a schema?

| Object | What it is |
|---|---|
| **Table** | Managed or External (see below) |
| **View** | A saved query, no storage |
| **Materialized view** | A view whose results are stored and refreshed |
| **Volume** | Governed storage for *files* - CSVs, PDFs, images |
| **Function** | A registered UDF |
| **Model** | A registered MLflow model |

### Q: Managed vs External table?

- **Managed** - Unity Catalog owns the data files and their lifecycle.
  `DROP TABLE` deletes the data.
- **External** - you point at a path you control via an External Location.
  `DROP TABLE` removes only the metadata; the files stay.

Use managed unless something outside Databricks must read the same files.

### Q: How does Databricks reach S3 under Unity Catalog?

A **Storage Credential** wraps an IAM role; an **External Location** binds that
credential to an S3 path; grants are then issued on the location.

The older way was an instance profile attached to a cluster, which gave every
job on that cluster the same access. UC makes access **per principal instead of
per cluster**, and you get lineage for free.

### Q: What is in the `samples` and `system` catalogs?

Every workspace has them:

- **`samples`** - read-only demo data. `samples.tpch` (8 classic tables),
  `samples.nyctaxi.trips`, `samples.bakehouse`, `samples.tpcds_sf1`.
  Ideal for practising SQL. Used throughout Part 3 below.
- **`system`** - operational metadata about your own account:
  `system.billing.usage` (cost), `system.query.history`,
  `system.access.audit`, `system.access.table_lineage`,
  `system.compute.warehouse_events`.

Knowing `system.billing.usage` exists is a genuinely good signal - it is how
you answer "how would you find what is driving cost?"

---

# Part 2 - dbt

### Q: What does dbt actually do?

Two things: it wraps your `SELECT` in `CREATE TABLE AS` / `CREATE VIEW AS` and
sends it to Databricks, and it works out the **order** to run things in from
your `ref()` calls. All compute happens in Databricks. dbt is a SQL compiler
and a scheduler-of-SQL - it never moves data itself.

### Q: `source()` vs `ref()`?

`source()` = a table someone else created, declared in YAML.
`ref()` = a table dbt created.

`ref()` is what builds the dependency graph. Hardcode a table name and dbt
cannot know the build order.

### Q: The three materializations, and when do you use each?

| | What happens | Use for |
|---|---|---|
| **view** | Stored as a query | Staging - cheap, always fresh |
| **table** | Rebuilt from scratch each run | Marts - queried repeatedly |
| **incremental** | Only new/changed rows | Genuinely large tables |

### Q: Why `merge` and not `append` on an incremental model?

**The most-asked dbt question.** Because of the lookback window.

`fct_daily_orders` re-reads the last 7 days on every run, since a late payment
can change a day's totals after the fact. With `append` those 7 days would be
inserted *again* - duplicates. With `merge` plus a `unique_key` they are
*replaced* - correct.

The lookback is *why* the strategy must be merge. That link is the answer.

### Q: What happens on the very first run of an incremental model?

The `is_incremental()` block is skipped and the whole table is built. It is
also skipped on `--full-refresh`. So `is_incremental()` is true only when the
table already exists **and** you did not ask for a full refresh.

### Q: How do you test that a model has the right grain?

A `unique` test on the primary key. That test **is** the grain assertion - it
is not decoration. If the grain is a combination, use
`dbt_utils.unique_combination_of_columns` or build a surrogate key and test
that.

### Q: Generic vs singular tests?

**Generic** are declared in YAML and reusable: `unique`, `not_null`,
`relationships`, `accepted_values`.

**Singular** is a `.sql` file - just a query. The inversion trips people up:
**you write the query that finds BAD rows. Rows returned = FAIL.**

Use singular for business rules no generic test can express - see
`tests/assert_no_negative_revenue_days.sql`.

### Q: When would you set a test to `severity: warn`?

Error on what the pipeline **controls**; warn on what it merely **observes**.

A missing customer email is a data-entry problem, not a broken pipeline -
failing a 3am build on it just trains people to ignore alerts. A duplicate
primary key is a real defect and should error.

### Q: What is a snapshot, and what is the catch?

It builds SCD Type 2 history from a source that only shows current state.

**The catch, and the follow-up they are waiting for:** a snapshot only captures
what it sees **when it runs**. Miss three days and that history is gone
permanently - it cannot be backfilled. So snapshots run first, on their own
schedule, and their failure pages someone.

### Q: `dbt run` vs `dbt build`?

`run` builds models. `test` runs tests. **`build` interleaves them in DAG
order** - it builds a model, tests it, and only then builds its children.

That matters: with `run` then `test`, a broken model has already propagated
bad data through fifty downstream tables before any test executes. `build`
stops at the first failure.

### Q: How do you keep CI fast on a large project?

Slim CI:

```bash
dbt build --select state:modified+ --defer --state ./prod-artifacts
```

`state:modified+` selects only changed models **and everything downstream**;
`--defer` resolves unchanged parents to the **production** tables instead of
rebuilding them. Three models build instead of two hundred and fifty.

---

# Part 3 - Hands-on SQL

Run these in a Databricks SQL editor. They use `samples.tpch`, which exists in
every workspace. **All outputs below are real.**

---

## 1. Top-N per group

*"For each region, give me the top 3 customers by account balance."*

```sql
SELECT r_name AS region, c_name AS customer, ROUND(c_acctbal,2) AS balance, rnk
FROM (
  SELECT r.r_name, c.c_name, c.c_acctbal,
         DENSE_RANK() OVER (PARTITION BY r.r_name ORDER BY c.c_acctbal DESC) AS rnk
  FROM samples.tpch.customer c
  JOIN samples.tpch.nation n ON c.c_nationkey = n.n_nationkey
  JOIN samples.tpch.region r ON n.n_regionkey = r.r_regionkey
)
WHERE rnk <= 3
ORDER BY region, rnk
```

```
region   customer            balance  rnk
AFRICA   Customer#000061453  9999.99  1
AFRICA   Customer#000069321  9999.96  2
AFRICA   Customer#000348586  9999.96  2
AFRICA   Customer#000171663  9999.90  3
AMERICA  Customer#000508503  9999.99  1
```

**Know the three ranking functions in one line each:**
`ROW_NUMBER` gives 1,2,3,4 (ties broken arbitrarily). `RANK` gives 1,2,2,4.
`DENSE_RANK` gives 1,2,2,3.

For "top 3" you usually want `DENSE_RANK` - note above that two customers tie
at rank 2 and **both** appear. With `ROW_NUMBER` one would be dropped at random.

**Why the subquery?** You cannot filter on a window function in `WHERE` -
windows are evaluated after `WHERE`. Hence the subquery, or `QUALIFY`.

---

## 2. Deduplicate to the latest row per key

*"One row per customer - their most recent order."*

The single most important pattern in data engineering: CDC feeds deliver the
same key many times.

```sql
SELECT o_custkey, o_orderkey, o_orderdate, o_totalprice
FROM samples.tpch.orders
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY o_custkey
  ORDER BY o_orderdate DESC, o_orderkey DESC) = 1
ORDER BY o_custkey
LIMIT 5
```

```
o_custkey  o_orderkey  o_orderdate  o_totalprice
1          22659203    1997-07-29   298763.11
2          17315366    1998-06-18   111745.59
4          16066180    1998-06-12   98219.75
```

**Points to make unprompted:**
- `QUALIFY` filters on a window without a subquery. Databricks, Snowflake and
  Teradata have it; Postgres does not, so know the subquery form too.
- Use `ROW_NUMBER`, not `RANK` - ties in `RANK` give back the duplicates you
  were removing.
- **Always add a tie-breaker** (`o_orderkey` here). Two CDC rows can share a
  timestamp, and without one the winner is arbitrary and changes between runs.

---

## 3. Running total

```sql
SELECT month, revenue,
       SUM(revenue) OVER (ORDER BY month
         ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total
FROM (
  SELECT DATE_TRUNC('MONTH', o_orderdate) AS month, ROUND(SUM(o_totalprice),0) AS revenue
  FROM samples.tpch.orders WHERE YEAR(o_orderdate) = 1995 GROUP BY 1
)
ORDER BY month
```

```
month       revenue      running_total
1995-01-01  14690432880  14690432880
1995-02-01  13152845366  27843278246
1995-03-01  14574503670  42417781916
```

The frame clause is the point. `ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT
ROW` = cumulative. `ROWS BETWEEN 6 PRECEDING AND CURRENT ROW` = rolling 7.

**The trap:** `ROWS` counts *rows*, not *days*. If a day has no orders it is
simply absent, and your "7-day window" silently becomes 9 days. Fix by joining
to a date spine first so every day exists as a row.

---

## 4. Month-over-month growth

```sql
SELECT month, revenue,
       LAG(revenue) OVER (ORDER BY month) AS prior_month,
       ROUND(100.0 * (revenue / NULLIF(LAG(revenue) OVER (ORDER BY month), 0) - 1), 2) AS mom_pct
FROM (
  SELECT DATE_TRUNC('MONTH', o_orderdate) AS month, ROUND(SUM(o_totalprice),0) AS revenue
  FROM samples.tpch.orders WHERE YEAR(o_orderdate)=1995 GROUP BY 1
)
ORDER BY month
```

```
month       revenue      prior_month  mom_pct
1995-01-01  14690432880  NULL         NULL
1995-02-01  13152845366  14690432880  -10.47
1995-03-01  14574503670  13152845366  10.81
```

`NULLIF(..., 0)` is what they are checking for - a zero-revenue month must not
blow up the query. The first row is correctly NULL: there is no prior month.

---

## 5. The `NOT IN` NULL trap

**Asked constantly, missed constantly.** Verified output:

```
NOT IN            (BROKEN)     returns 0 rows   <-- WRONG
NOT IN + IS NOT NULL guard     returns 2 rows
NOT EXISTS        (correct)    returns 2 rows
LEFT JOIN .. IS NULL (correct) returns 2 rows
```

Setup: customers 1,2,3,4. Orders reference 1, 2, and one NULL. Customers 3 and
4 never ordered, so the answer is 2.

```sql
-- BROKEN: returns nothing
SELECT * FROM customers c
WHERE c.cust_id NOT IN (SELECT cust_id FROM orders);

-- CORRECT
SELECT * FROM customers c
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.cust_id = c.cust_id);
```

**Why:** `x NOT IN (1, 2, NULL)` expands to `x<>1 AND x<>2 AND x<>NULL`.
`x<>NULL` is `UNKNOWN`, never `TRUE`, so the whole predicate can never be true
and you get zero rows. `NOT EXISTS` uses correlated semantics and is unaffected.

---

## 6. Percent of total

```sql
SELECT o_orderpriority AS priority, ROUND(revenue,0) AS revenue,
       ROUND(100.0 * revenue / SUM(revenue) OVER (), 2) AS pct_of_total
FROM (SELECT o_orderpriority, SUM(o_totalprice) AS revenue
      FROM samples.tpch.orders GROUP BY 1)
ORDER BY revenue DESC
```

```
priority         revenue       pct_of_total
1-URGENT         226905605646  20.02
4-NOT SPECIFIED  226828528845  20.01
2-HIGH           226785170189  20.01
```

`SUM(...) OVER ()` with an **empty** window = the grand total on every row.
That is how you get a percent-of-total without a self-join or a second pass.

---

## 7. Gaps and islands

*"Customers who ordered in 3 or more consecutive months."*

```sql
WITH m AS (
  SELECT DISTINCT o_custkey, YEAR(o_orderdate)*12 + MONTH(o_orderdate) AS mi
  FROM samples.tpch.orders
),
islands AS (
  SELECT o_custkey, mi,
         mi - ROW_NUMBER() OVER (PARTITION BY o_custkey ORDER BY mi) AS grp
  FROM m
)
SELECT o_custkey, COUNT(*) AS consecutive_months
FROM islands GROUP BY o_custkey, grp
HAVING COUNT(*) >= 3
ORDER BY consecutive_months DESC
```

```
o_custkey  consecutive_months
693811     10
199081     10
8599       9
```

**The trick:** for consecutive values, `value - ROW_NUMBER()` is **constant**.
Group by that constant and each group is one unbroken run.

Converting the date to a month index (`year*12 + month`) first is what makes
"consecutive" well-defined across a year boundary - December to January.

---

## 8. Anti-join

*"Parts that were never ordered."*

```sql
SELECT COUNT(*) AS parts_never_ordered
FROM samples.tpch.part p
LEFT JOIN samples.tpch.lineitem l ON p.p_partkey = l.l_partkey
WHERE l.l_partkey IS NULL
```

```
parts_never_ordered
0
```

`LEFT JOIN ... WHERE right IS NULL` is the portable anti-join - it works
everywhere, unlike `QUALIFY`. `NOT EXISTS` is usually clearer and the optimiser
treats them the same; `NOT IN` is the one to avoid, per scenario 5.

---

## If they ask you to write one live

Say the grain out loud first: *"one row per customer per month"*. Then build it
in CTEs, one step per CTE, and name each CTE after what it **is**. Talking
through the shape before writing beats silently producing a correct query -
they are assessing how you think, not your typing.
