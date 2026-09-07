# Operations: GitHub, and running this on Databricks

The two questions that always follow "tell me about your dbt project".

---

## Part 1 - How the SQL is maintained in GitHub

### What is version controlled

Everything except secrets and build output:

```
COMMITTED                        NOT COMMITTED (.gitignore)
---------                        --------------------------
models/**.sql                    .env            <- the token
models/**.yml                    target/         <- compiled SQL
macros/, snapshots/, tests/      dbt_packages/
dbt_project.yml                  logs/
profiles.yml  (env_var only!)
.env.example
```

`profiles.yml` is committed **because it contains no secrets** - every value is
an `env_var()` reference. The actual token lives in `.env`, which is gitignored.
That is the pattern to describe: *the shape of the config is versioned, the
values are not.*

### The branching workflow

```
main            production. protected. no direct pushes
  |
  +-- feature/add-customer-segment
         |
         1. write the model + its tests + its description
         2. dbt build --select state:modified+   (locally, or in CI)
         3. open a Pull Request
         4. review: is the grain tested? does it have a description?
         5. merge -> CI deploys to prod
```

**What a reviewer actually checks** - worth saying out loud:
- Does the model have a `unique` test on its key? That is the grain assertion
- Is there a `description`? Undocumented models become nobody's models
- Does it use `ref()` everywhere, never a hardcoded table name?
- Is business logic in staging that should be in a mart?

### CI on a pull request

The important trick is **slim CI** - do not rebuild 250 models to test 3:

```bash
dbt build --select state:modified+ --defer --state ./prod-artifacts
```

- `state:modified+` - only changed models **and everything downstream**
- `--defer` - unchanged parents resolve to the **production** tables instead of
  being rebuilt
- Build into a schema named after the PR, and drop it afterwards

You compare against `manifest.json` from the last successful production run,
stored in S3 or as a CI artifact.

---

## Part 2 - How this gets triggered on Databricks

### Option A: Databricks Workflows with a dbt task (the normal answer)

Databricks has a **native dbt task type**. It clones your Git repo, runs the
dbt commands, and shows the results in the job UI.

Create it in the UI: **Workflows -> Create job -> Task type: dbt**, or declare
it as code (see `databricks_job.yml`):

```yaml
tasks:
  - task_key: dbt_build
    dbt_task:
      project_directory: ""
      commands:
        - "dbt deps"
        - "dbt snapshot"     # ALWAYS first - snapshots cannot be backfilled
        - "dbt build"
      warehouse_id: <your SQL warehouse id>
    # Git source means the job runs what is IN GITHUB, not a copy pasted
    # into the workspace. This is the bit that matters.
    git_source:
      git_url: https://github.com/<user>/<repo>
      git_provider: gitHub
      git_branch: main
```

**Why point the job at Git rather than at notebooks in the workspace?**
Because then production runs exactly what was reviewed and merged. Nobody can
edit prod logic by clicking around in the workspace. Say this - it is the
governance answer they want.

Schedule it with a cron in the job definition, or trigger on file arrival.

### Option B: Databricks Asset Bundles (deployment as code)

`databricks bundle deploy -t prod` ships job definitions from your repo, so
the *job itself* is version controlled too, not just the SQL. Jenkins or GitHub
Actions runs this on merge to main.

### Option C: An external orchestrator

Airflow / MWAA or AWS Step Functions calls the Databricks Jobs API. Use this
when the pipeline spans more than Databricks - a DMS task, a Lambda, an SNS
alert. If everything is inside Databricks, Workflows is simpler and you should
say so.

### How to choose

| Situation | Use |
|---|---|
| Everything lives in Databricks | **Workflows dbt task** |
| Job definitions should be version controlled | **Asset Bundles** |
| Pipeline spans other AWS services | **Step Functions / Airflow** |

### Run order that matters

```
1. dbt deps        install packages
2. dbt snapshot    FIRST - only captures what it sees; a missed run is lost
3. dbt build       models + tests interleaved, stops at first failure
4. alert on failure
```

### What to monitor

- **Job failure** -> email/Slack from the Workflow's notification settings
- **Test failures** -> `dbt build` fails the task, so this is covered
- **Source freshness** -> `dbt source freshness` catches an upstream that
  silently stopped delivering, which no downstream test can find
- **Cost** -> tag the SQL warehouse; query `system.billing.usage`
