#!/usr/bin/env python3
"""
Seed the Unity Catalog volume with a sample CSV.

Only needed for the ONE ingestion model (models/ingestion/bronze_orders_stream.sql),
which reads files rather than tables. The other six models work with just
setup/01_bootstrap.sql.

A volume is UC storage for FILES. SQL can create the volume but cannot write
files into it, which is why this step is Python.

Usage:
    cp .env.example .env        # fill it in
    python setup/02_seed_volume.py

Reads DATABRICKS_HOST / DATABRICKS_TOKEN from .env or the environment.
"""
from __future__ import annotations

import io
import json
import os
import sys
import urllib.error
import urllib.request

CATALOG = os.environ.get("DBT_CATALOG", "workspace")
VOLUME = f"/Volumes/{CATALOG}/bronze/landing"


def load_dotenv(path: str = ".env") -> None:
    """Minimal .env reader so this has no dependencies."""
    if not os.path.exists(path):
        return
    for line in io.open(path, encoding="utf-8"):
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        os.environ.setdefault(k.strip(), v.strip())


def request(host: str, token: str, path: str, method: str = "GET", body: bytes | None = None,
            content_type: str = "application/json"):
    req = urllib.request.Request(
        host + path, data=body, method=method,
        headers={"Authorization": f"Bearer {token}", "Content-Type": content_type},
    )
    try:
        raw = urllib.request.urlopen(req, timeout=120).read()
        return json.loads(raw) if raw and content_type == "application/json" else {}
    except urllib.error.HTTPError as e:
        raise SystemExit(f"API error {e.code}: {e.read().decode()[:300]}")


# One row per line. Deliberately messy in the same ways as the tables:
# order 115 references a customer that does not exist.
SAMPLE_CSV = """order_id,customer_id,order_ts,order_status,currency_code,channel
101,1,2025-03-01 09:14:00,delivered,USD,online
102,1,2025-04-12 16:02:00,delivered,USD,mobile
103,2,2025-03-14 11:47:00,shipped,EUR,online
104,3,2025-03-22 08:31:00,delivered,BRL,online
105,3,2025-05-02 14:20:00,returned,BRL,mobile
106,4,2025-04-01 19:05:00,delivered,JPY,online
107,5,2025-04-09 07:58:00,placed,INR,mobile
108,5,2025-05-19 12:11:00,delivered,INR,online
109,6,2025-04-25 15:44:00,cancelled,EUR,online
110,7,2025-05-03 10:26:00,delivered,SEK,mobile
111,1,2025-05-27 17:39:00,shipped,USD,online
112,8,2025-05-30 09:02:00,placed,MAD,online
113,10,2025-06-04 13:15:00,delivered,BGN,mobile
114,3,2025-06-11 08:47:00,delivered,BRL,online
115,99,2025-06-15 20:03:00,delivered,USD,online
"""


def main() -> None:
    load_dotenv()
    host = os.environ.get("DATABRICKS_HOST", "").rstrip("/")
    token = os.environ.get("DATABRICKS_TOKEN", "")

    if not host or not token:
        sys.exit("Set DATABRICKS_HOST and DATABRICKS_TOKEN (see .env.example)")
    if not host.startswith("http"):
        host = "https://" + host

    print(f"workspace : {host}")
    print(f"volume    : {VOLUME}")

    # The volume must already exist - setup/01_bootstrap.sql creates it.
    request(host, token, f"/api/2.0/fs/directories{VOLUME}", "PUT")

    payload = SAMPLE_CSV.encode("utf-8")
    request(host, token, f"/api/2.0/fs/files{VOLUME}/orders_seed.csv?overwrite=true",
            "PUT", payload, "application/octet-stream")
    print(f"uploaded  : orders_seed.csv ({len(payload):,} bytes, "
          f"{SAMPLE_CSV.count(chr(10)) - 1} rows)")

    listing = request(host, token, f"/api/2.0/fs/directories{VOLUME}")
    print("\ncontents:")
    for entry in listing.get("contents", []):
        size = entry.get("file_size", 0)
        print(f"  {entry['name']:<28} {size:>9,} bytes")

    print("\nDone. Now run:  dbt build")


if __name__ == "__main__":
    main()
