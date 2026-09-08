# Dot-source this before running dbt:   . .\env.ps1
#
# PowerShell equivalent of env.sh. Reads everything from .env (which is
# gitignored). No secrets live in here.
#
# The Git Bash MSYS2_ENV_CONV_EXCL workaround in env.sh is NOT needed here -
# PowerShell does not rewrite env vars that look like Unix paths, so
# DATABRICKS_HTTP_PATH=/sql/1.0/... survives intact.

if (-not (Test-Path .env)) {
  Write-Host "ERROR: no .env found. Copy .env.example to .env and fill it in."
  return
}

Get-Content .env | ForEach-Object {
  $line = $_.Trim()
  if ($line -eq '' -or $line.StartsWith('#')) { return }
  $i = $line.IndexOf('=')
  if ($i -lt 1) { return }
  $name  = $line.Substring(0, $i).Trim()
  $value = $line.Substring($i + 1).Trim()
  if ($value.Length -ge 2 -and
      (($value.StartsWith('"') -and $value.EndsWith('"')) -or
       ($value.StartsWith("'") -and $value.EndsWith("'")))) {
    $value = $value.Substring(1, $value.Length - 2)
  }
  Set-Item -Path "env:$name" -Value $value
}

# dbt-databricks needs the BARE hostname. The SQL connector tolerates a
# scheme, but the pipelines REST client (used by streaming_table and
# materialized_view models) concatenates it and builds
# https://https/dbc-.../api/... which fails DNS. Strip it.
$h = $env:DATABRICKS_HOST
$h = $h -replace '^https://', ''
$h = $h -replace '^http://', ''
$env:DATABRICKS_HOST = $h.TrimEnd('/')

if ([string]::IsNullOrEmpty($env:DBT_CATALOG))        { $env:DBT_CATALOG = 'workspace' }
if ([string]::IsNullOrEmpty($env:DBT_SOURCE_CATALOG)) { $env:DBT_SOURCE_CATALOG = $env:DBT_CATALOG }
$env:DBT_PROFILES_DIR = (Get-Location).Path

foreach ($v in 'DATABRICKS_HOST', 'DATABRICKS_HTTP_PATH', 'DATABRICKS_TOKEN') {
  if ([string]::IsNullOrEmpty([System.Environment]::GetEnvironmentVariable($v))) {
    Write-Host "WARNING: $v is not set in .env"
  }
}

Write-Host "host      : $env:DATABRICKS_HOST"
Write-Host "http_path : $env:DATABRICKS_HTTP_PATH"
Write-Host "catalog   : $env:DBT_CATALOG"
