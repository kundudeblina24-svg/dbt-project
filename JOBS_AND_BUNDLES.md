# Databricks Jobs and Asset Bundles

How to schedule this dbt project. Everything below was deployed and run on a
real workspace — the errors shown are ones I actually hit.

---

# Part 1 — The three ways to create a job

| Way | Good for | Problem |
|---|---|---|
| **UI** (Workflows → Create job) | Learning, one-offs | Not version controlled. Nobody knows who changed what |
| **Jobs API** | Scripting, automation | You hand-roll JSON and manage state yourself |
| **Asset Bundles (DAB)** | **Production** | Slight learning curve |

A bundle is **infrastructure-as-code for Databricks**: jobs, pipelines and
config in YAML, version controlled, deployed with one command across
dev/staging/prod.

It's the mechanism that makes "all changes go through Git" *enforceable* rather
than just a policy someone wrote down.

---

# Part 2 — Setting up a job in the UI (learn the shape first)

Worth doing once so the YAML means something.

1. **Workflows** → **Create job**
2. **Task name**: `dbt_build`
3. **Type**: `dbt`
4. **Source**: Workspace, or Git provider
5. **dbt commands**: `dbt deps`, `dbt build`
6. **SQL warehouse**: pick yours ← *this is where the SQL actually runs*
7. **Compute**: Serverless
8. **Create task**

Add a second task and set **Depends on** to build a DAG.

Then **Schedule** → cron, **Notifications** → on failure.

**Now click "View JSON" (top right).** That JSON is what a bundle generates for
you. Seeing them side by side is what makes bundles click.

---

# Part 3 — Asset Bundles

## Install the CLI

The bundle CLI is a **Go binary**, not the old `pip install databricks-cli`:

```bash
winget install Databricks.DatabricksCLI
databricks --version        # want v0.2xx or v1.x
```

## Authenticate

```bash
export DATABRICKS_HOST=https://your-workspace.cloud.databricks.com
export DATABRICKS_TOKEN=dapi...
```

> The CLI wants the **full URL with scheme**. Note this is the opposite of
> dbt-databricks, which needs the **bare hostname**. Getting them backwards
> produces confusing errors in both directions.

## The four commands

```bash
databricks bundle validate -t dev     # check the config, no changes made
databricks bundle deploy   -t dev     # create/update the job
databricks bundle run dbt_daily -t dev
databricks bundle destroy  -t dev     # tear it down
```

## The file — see `databricks.yml`

```yaml
bundle:
  name: dbt_databricks_learning

sync:
  exclude: [.env, .git/, target/, logs/, dbt_packages/]

variables:
  warehouse_id: {default: ""}
  catalog:      {default: workspace}

targets:
  dev:  {mode: development, default: true}
  prod: {mode: production}

resources:
  jobs:
    dbt_daily:
      name: dbt daily build
      environments:
        - environment_key: default
          spec: {client: "3", dependencies: ["dbt-databricks>=1.8,<1.10"]}
      tasks:
        - task_key: dbt_snapshot
          environment_key: default
          dbt_task:
            project_directory: ""
            catalog: ${var.catalog}
            schema: gold
            warehouse_id: ${var.warehouse_id}
            commands: ["dbt deps", "dbt snapshot"]
        - task_key: dbt_build
          depends_on: [{task_key: dbt_snapshot}]
          ...
      schedule:
        quartz_cron_expression: "0 0 5 * * ?"
        timezone_id: "America/New_York"
        pause_status: PAUSED
```

## `mode: development` vs `mode: production`

| | development | production |
|---|---|---|
| Resource names | prefixed `[dev yourname]` | as written |
| Schedules | **paused automatically** | active |
| Concurrent runs | allowed | restricted |

That prefix is a safety feature — you cannot deploy dev over prod by mistake.

---

# Part 4 — The three problems I actually hit

## 1. Bundle sync uploads `.env` — it does NOT read `.gitignore` ⚠

Bundle sync pushes your whole project directory to the workspace. `.gitignore`
means nothing to it. Without an explicit exclude, your **token goes into the
workspace**.

```yaml
sync:
  exclude:
    - .env
    - .git/
    - target/
    - logs/
    - dbt_packages/
```

**Always set this.** Check what landed:

```bash
databricks workspace list /Workspace/Users/<you>/.bundle/<bundle>/dev/files
```

## 2. `--target prod` fails on a dbt task

```
Runtime Error
  The profile 'dbt_databricks_learning' does not have a target named 'prod'.
```

**Why:** when you set `warehouse_id`, **Databricks generates its own
`profiles.yml`** and passes `--profiles-dir`, which overrides the one in your
repo. That generated profile has its own target name — yours doesn't exist
there.

**Fix:** drop `--target` and let Databricks use its default.

```yaml
commands: ["dbt deps", "dbt build"]     # not "dbt build --target prod"
```

This is also *good*: it means no token has to be stored for dbt. Databricks
authenticates the warehouse connection itself.

## 3. `dbt source freshness` failed — correctly

```
Command 'dbt source freshness' returned non-zero exit status 1
```

The data was days old against a 24-hour `error_after`. **The check was working.**
For static demo data I widened it; in a real pipeline you'd leave it tight,
because a freshness breach means the upstream job stopped — the one failure no
downstream test can detect. If the data never arrives, every test on it passes.

---

# Part 5 — Task order that matters

```
dbt_snapshot  →  dbt_build  →  source_freshness
```

**Snapshots run first, alone.** A snapshot only captures what it sees *when it
runs*. Miss a run and that history is gone permanently — it cannot be
backfilled, because the source only holds current state. Its failure should
page someone.

**`dbt build`, not `dbt run` then `dbt test`.** Build interleaves them in
dependency order — it builds a model, tests it, and only then builds its
children. With run-then-test, a broken model has already pushed bad data
through every downstream table before any test fires.

---

# Part 6 — Running from Git instead of synced files

By default a bundle uploads your local files. Fine for dev. In production you
usually want the job to run **what is in Git**:

```yaml
git_source:
  git_url: https://github.com/kundudeblina24-svg/dbt-project
  git_provider: gitHub
  git_branch: main
```

(and drop `project_directory: ""`)

**Why this matters, and it's the governance answer:** production then runs
exactly what was reviewed and merged. Nobody can change prod logic by clicking
around the workspace. A private repo needs a Git credential registered first —
**Settings → Linked accounts → Git integration**.

---

# Part 7 — CI/CD

```yaml
# .github/workflows/deploy.yml
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: databricks/setup-cli@main
      - run: databricks bundle deploy -t prod
        env:
          DATABRICKS_HOST:  ${{ secrets.DATABRICKS_HOST }}
          DATABRICKS_TOKEN: ${{ secrets.DATABRICKS_SP_TOKEN }}
```

Authenticate as a **service principal**, not a person — a personal access token
dies with its owner, and an outage on someone's last day is a bad way to learn
that.

---

# Interview questions

1. **What is a Databricks Asset Bundle?** — Infrastructure-as-code for
   Databricks. Jobs, pipelines and config in version-controlled YAML, deployed
   with one command across environments. It's what makes "everything goes
   through Git" enforceable instead of aspirational.

2. **Bundle or the UI?** — UI to learn the shape and for one-offs. Bundles for
   anything that matters, because a UI-created job has no history, no review
   and no way to promote it between environments.

3. **How do you stop dev deploying over prod?** — Separate targets. `mode:
   development` prefixes resources and pauses schedules; `mode: production`
   doesn't. Plus separate workspaces or catalogs.

4. **Where does dbt actually run in a Databricks job?** — Two different
   computes. The dbt CLI runs on small serverless compute — it just parses the
   DAG and issues SQL. The **SQL Warehouse** does the real work. So sizing the
   job compute barely changes runtime; sizing the warehouse does.

5. **Git source or synced files?** — Git for production, so the job runs what
   was reviewed and merged rather than whatever someone last uploaded.
