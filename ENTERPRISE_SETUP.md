# The same project in a real enterprise — Volumes become S3

This project uses a **Unity Catalog Volume** because Free Edition cannot attach
your own cloud storage. In production that volume is an **S3 prefix**.

Almost nothing else changes — which is the point. Below is every file, side by
side, with realistic (fake) values you can copy.

> All credentials, ARNs and URLs here are **dummy**. Replace them.

---

## 1. The one thing that changes: where the files live

| | This project (Free Edition) | Enterprise (AWS) |
|---|---|---|
| Landing | `/Volumes/workspace/bronze/landing/` | `s3://acme-lakehouse-prod/landing/` |
| Catalog | `workspace` | `lakehouse_dev` / `lakehouse_prod` |
| Access | implicit | **Storage Credential → External Location → GRANT** |
| Auth | personal token | **service principal, OAuth** |

### The S3 layout you'd actually use

```
s3://acme-lakehouse-prod/
├── landing/                     raw, immutable, never rewritten
│   ├── erp/customers/dt=2026-09-07/part-0000.parquet
│   ├── orders/dt=2026-09-07/part-0000.csv
│   └── payments/dt=2026-09-07/part-0000.csv
├── bronze/                      Delta tables
├── silver/
├── gold/
└── _checkpoints/                Auto Loader state
```

**Partition landing by *ingest* date, not event date.** Ingest date is known at
write time and never needs restating when late data arrives.

---

## 2. The permission chain (this is the part people get wrong)

```
IAM role  →  Storage Credential  →  External Location  →  GRANT  →  user/group
```

Run once, by a platform admin:

```sql
-- 1. wrap the IAM role
CREATE STORAGE CREDENTIAL acme_lake_prod
  WITH IAM_ROLE 'arn:aws:iam::123456789012:role/acme-uc-access-prod'
  COMMENT 'Managed by Terraform';

-- 2. bind it to a path
CREATE EXTERNAL LOCATION acme_landing
  URL 's3://acme-lakehouse-prod/landing'
  WITH (STORAGE CREDENTIAL acme_lake_prod);

-- 3. grant access to people, not clusters
GRANT READ FILES  ON EXTERNAL LOCATION acme_landing TO `data_engineers`;
GRANT WRITE FILES ON EXTERNAL LOCATION acme_landing TO `ingestion_sp`;

-- 4. the catalog
CREATE CATALOG lakehouse_prod
  MANAGED LOCATION 's3://acme-lakehouse-prod/managed';
GRANT USE CATALOG ON CATALOG lakehouse_prod TO `analysts`;
```

### The IAM trust policy — the bit that wastes an afternoon

It needs **two** statements. The second one is the self-reference, and leaving
it out is the most common cause of *"failed to access external location"*.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DatabricksAssume",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::414351767826:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": { "sts:ExternalId": "1234567890123456" }
      }
    },
    {
      "Sid": "SelfAssume",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::123456789012:role/acme-uc-access-prod"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

`sts:ExternalId` is your **Databricks account ID** — confused-deputy protection.
`414351767826` is Databricks' own AWS account; it is the same for everyone.

---

## 3. `_sources.yml` — before and after

**Now:**
```yaml
sources:
  - name: lakehouse
    database: workspace
    schema: learn_raw
    tables:
      - name: orders
```

**Enterprise:**
```yaml
sources:
  # Federated Postgres - queries pushed down, nothing copied
  - name: erp_postgres
    database: pg_erp              # the FOREIGN CATALOG
    schema: public
    tables:
      - name: customers

  # Delta tables landed from S3 by Auto Loader
  - name: lakehouse
    database: "{{ env_var('DBT_CATALOG') }}"   # lakehouse_dev / lakehouse_prod
    schema: bronze
    freshness:
      warn_after:  {count: 2, period: hour}
      error_after: {count: 6, period: hour}
    loaded_at_field: _ingest_ts
    tables:
      - name: orders
      - name: payments
```

The foreign catalog is created once:

```sql
CREATE CONNECTION erp_pg TYPE postgresql
  OPTIONS (host 'erp-db.acme.internal', port '5432',
           user secret('acme','pg_user'), password secret('acme','pg_password'));

CREATE FOREIGN CATALOG pg_erp USING CONNECTION erp_pg OPTIONS (database 'erp');
```

**Only `database:` changed in the model layer.** No SQL was touched.

---

## 4. `.env` — dummy values to copy

```bash
# ---- Databricks ----
DATABRICKS_HOST=https://dbc-a1b2c3d4-e5f6.cloud.databricks.com
DATABRICKS_HTTP_PATH=/sql/1.0/warehouses/a1b2c3d4e5f6a7b8
DATABRICKS_TOKEN=dapiXXXXXXXX-REPLACE-ME-XXXXXXXX
DATABRICKS_ACCOUNT_ID=1234567890123456
DBT_CATALOG=lakehouse_dev

# ---- production uses a service principal, not a PAT ----
DATABRICKS_CLIENT_ID=a1b2c3d4-e5f6-7890-abcd-ef1234567890
DATABRICKS_CLIENT_SECRET=doseXXXXXXXX-REPLACE-ME-XXXXXXXX

# ---- AWS ----
AWS_REGION=us-east-1
LAKE_BUCKET=acme-lakehouse-prod
UC_ROLE_ARN=arn:aws:iam::123456789012:role/acme-uc-access-prod
```

> **A personal access token dies with its owner.** Use a service principal in
> production — an outage on someone's last day is a bad way to learn that.

---

## 5. `profiles.yml` — real environments

```yaml
dbt_databricks_learning:
  target: dev
  outputs:

    dev:
      type: databricks
      host:      "{{ env_var('DATABRICKS_HOST') }}"
      http_path: "{{ env_var('DATABRICKS_HTTP_PATH') }}"
      token:     "{{ env_var('DATABRICKS_TOKEN') }}"
      catalog:   lakehouse_dev
      schema:    "dbt_{{ env_var('USER', 'dev') }}"   # personal sandbox
      threads: 4

    ci:
      type: databricks
      host:      "{{ env_var('DATABRICKS_HOST') }}"
      http_path: "{{ env_var('DATABRICKS_HTTP_PATH') }}"
      token:     "{{ env_var('DATABRICKS_TOKEN') }}"
      catalog:   lakehouse_dev
      schema:    "ci_pr_{{ env_var('PR_NUMBER', '0') }}"   # dropped after the run
      threads: 8

    prod:
      type: databricks
      host:          "{{ env_var('DATABRICKS_HOST') }}"
      http_path:     "{{ env_var('DATABRICKS_HTTP_PATH') }}"
      client_id:     "{{ env_var('DATABRICKS_CLIENT_ID') }}"      # service principal
      client_secret: "{{ env_var('DATABRICKS_CLIENT_SECRET') }}"
      catalog:       lakehouse_prod
      schema:        gold
      threads: 8
```

**Each developer gets their own schema in dev.** That's why dbt prefixes schemas
by default — so two people don't overwrite each other.

---

## 6. Ingestion — S3 instead of a Volume

```python
LANDING    = "s3://acme-lakehouse-prod/landing/orders/"
CHECKPOINT = "s3://acme-lakehouse-prod/_checkpoints/bronze_orders/"

df = (spark.readStream.format("cloudFiles")
        .option("cloudFiles.format", "csv")
        .option("cloudFiles.schemaLocation", CHECKPOINT + "schema/")
        .option("cloudFiles.schemaEvolutionMode", "addNewColumns")
        .option("rescuedDataColumn", "_rescued_data")
        # above ~1M files, stop listing the bucket and use notifications
        .option("cloudFiles.useNotifications", "true")
        .load(LANDING)
        .withColumn("_ingest_ts",   F.current_timestamp())
        .withColumn("_source_file", F.col("_metadata.file_path")))

(df.writeStream
   .option("checkpointLocation", CHECKPOINT + "data/")
   .trigger(availableNow=True)
   .toTable("lakehouse_prod.bronze.orders")).awaitTermination()
```

Only the **paths** changed. `useNotifications` is the addition that matters at
scale: it consumes S3 events via SNS/SQS instead of listing the bucket, which
gets slower every day.

---

## 7. Models — what changes

**Nothing.** That is the headline.

`stg_orders.sql`, `fct_orders.sql`, `fct_daily_orders.sql` are byte-for-byte
identical. They reference `source()` and `ref()`, and those resolve through the
config. Change the catalog in `profiles.yml` and the same models build against
production.

**Say this out loud in an interview** — it is the strongest argument for why
sources and refs exist at all.

---

## 8. The full picture

```
S3 landing  ──Auto Loader──>  bronze (Delta)  ──dbt──>  silver/gold  ──>  BI
 (raw files)                   lakehouse_prod            marts
      │                              │                     │
      └── External Location ─────────┴─────────────────────┘
                 │
          Storage Credential ── IAM role ── S3 bucket policy
```

---

## 9. What is honestly different, and what to say

| | Free Edition | Enterprise |
|---|---|---|
| Storage | UC Volume | S3 + External Location |
| Auth | personal token | service principal OAuth |
| Compute | serverless only | job clusters, policies, pools |
| Catalogs | one (`workspace`) | per environment |
| Deploy | manual | Asset Bundles from CI |
| Cost | free | tagged, monitored via `system.billing.usage` |

> "I built it on Free Edition, so storage is a Unity Catalog volume rather than
> S3. In production that's an external location backed by a storage credential
> wrapping an IAM role — but the models themselves don't change at all, because
> they go through `source()` and `ref()`. You swap the catalog in the profile
> and the same code builds against prod."

That answer is better than pretending it was S3. It shows you know the
difference, which is the actual question.
