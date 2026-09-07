#!/usr/bin/env bash
# Source this before running dbt:   source env.sh
#
# Reads everything from .env (which is gitignored). No secrets live in here.

# ---------------------------------------------------------------------------
# Git Bash on Windows rewrites env vars that look like Unix paths, so
# DATABRICKS_HTTP_PATH=/sql/1.0/... silently becomes
# C:/Program Files/Git/sql/1.0/... and dbt then hangs for 15+ minutes
# retrying a URL that does not exist.
#
# Do NOT use MSYS_NO_PATHCONV=1 - that disables conversion globally and
# breaks DBT_PROFILES_DIR instead.
# ---------------------------------------------------------------------------
export MSYS2_ENV_CONV_EXCL="DATABRICKS_HTTP_PATH"

if [ ! -f .env ]; then
  echo "ERROR: no .env found. Copy .env.example to .env and fill it in."
  return 1 2>/dev/null || exit 1
fi

set -a; . ./.env; set +a

# dbt-databricks needs the BARE hostname. The SQL connector tolerates a
# scheme, but the pipelines REST client (used by streaming_table and
# materialized_view models) concatenates it and builds
# https://https/dbc-.../api/... which fails DNS. Strip it.
export DATABRICKS_HOST="${DATABRICKS_HOST#https://}"
export DATABRICKS_HOST="${DATABRICKS_HOST#http://}"
export DATABRICKS_HOST="${DATABRICKS_HOST%/}"

export DBT_CATALOG="${DBT_CATALOG:-workspace}"
export DBT_SOURCE_CATALOG="${DBT_SOURCE_CATALOG:-$DBT_CATALOG}"
export DBT_PROFILES_DIR="$(pwd -W 2>/dev/null || pwd)"

for v in DATABRICKS_HOST DATABRICKS_HTTP_PATH DATABRICKS_TOKEN; do
  if [ -z "${!v}" ]; then echo "WARNING: $v is not set in .env"; fi
done

echo "host      : $DATABRICKS_HOST"
echo "http_path : $DATABRICKS_HTTP_PATH"
echo "catalog   : $DBT_CATALOG"
