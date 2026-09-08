# dbt on Databricks - a small project to learn from

A deliberately tiny dbt project that runs **on Databricks only**, writes into
**Unity Catalog**, and is **SQL only** - no Python models, no PySpark.

Six models. Read them in order and you will have seen every dbt concept that
comes up in an interview.

## Read these in order

| File | What it covers |
|---|---|
| `LEARNING_GUIDE.md` | Every concept, explained plainly. **Start here.** |
| `INTERVIEW_QA.md` | Questions with answers, including hands-on SQL |
| `OPERATIONS.md` | GitHub workflow + how this gets scheduled on Databricks |

## What it builds

```
SOURCES                              MODELS                        TARGET
-------                              ------                        ------
external Postgres  --federation-->   stg_customers  \
(erp.customers)                                      \
                                     stg_orders  -----+--> fct_orders ---> Unity
Unity Catalog      --------------->  stg_payments /         dim_customers   Catalog
(learn_raw.orders,                                          fct_daily_orders
 learn_raw.payments)                 snap_customers (SCD2)
```

Two sources on purpose: **one external database, one Unity Catalog table.**
The models cannot tell the difference - that is the point of federation.

## Run it

```bash
cp .env.example .env          # fill in your workspace details
pip install dbt-core dbt-databricks

# Windows Git Bash ONLY - see the gotcha below
export MSYS2_ENV_CONV_EXCL="DATABRICKS_HTTP_PATH"

dbt debug          # check the connection first, always
dbt build          # runs models + tests together, in dependency order
dbt docs generate && dbt docs serve   # the lineage graph
```

### Windows Git Bash gotcha (cost us 35 minutes, worth knowing)

Git Bash rewrites environment variables that look like Unix paths. Setting
`DATABRICKS_HTTP_PATH=/sql/1.0/warehouses/abc` silently becomes
`C:/Program Files/Git/sql/1.0/warehouses/abc`, and dbt then hangs for 15+
minutes retrying a URL that does not exist.

The fix is one line: `export MSYS2_ENV_CONV_EXCL="DATABRICKS_HTTP_PATH"`.

Do **not** use `MSYS_NO_PATHCONV=1` - that disables conversion globally and
breaks `DBT_PROFILES_DIR` instead.

## Verified

```
dbt build --target dev
Done. PASS=31 WARN=2 ERROR=0 SKIP=0 TOTAL=33
```

The 2 warnings are deliberate - a missing email and an order pointing at a
customer who does not exist, so you can see what a failing test looks like
without the project going red.

---

## First-time setup

The project reads from tables and a volume it does **not** create. Bootstrap
them once:

```bash
# 1. create schemas, volume and source tables  (paste into a Databricks SQL editor)
setup/01_bootstrap.sql

# 2. seed the volume  (only needed for the streaming ingestion model)
cp .env.example .env        # fill in host, http_path, token
python setup/02_seed_volume.py

# 3. build
source env.sh
dbt debug
dbt build
```

Expect `PASS=32 WARN=2 ERROR=0`. The two warnings are deliberate — see
`START_HERE.md`.
