{{ config(materialized='streaming_table') }}

-- Auto Loader, expressed as a dbt model.
--
-- STREAM read_files(...) is the SQL form of Auto Loader: same incremental
-- file tracking, same schema evolution, no PySpark. dbt-databricks supports
-- materialized='streaming_table', so ingestion CAN live in dbt after all --
-- with the caveat that dbt only issues CREATE OR REFRESH; the incremental
-- bookkeeping is Databricks', not dbt's.

SELECT
    *,
    current_timestamp()   AS _ingest_ts,
    _metadata.file_path   AS _source_file
FROM STREAM read_files(
    '/Volumes/workspace/bronze/landing/',
    format         => 'csv',
    header         => true,
    pathGlobFilter => 'orders*.csv'
)
