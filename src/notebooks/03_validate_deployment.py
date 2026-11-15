# Databricks notebook source
# MAGIC %md
# MAGIC # 03 - Validate deployment
# MAGIC Post-deployment checks. Every check is written to `deployment_audit`.
# MAGIC If any check fails the notebook raises an exception, which fails the job run,
# MAGIC which fails the GitHub Actions workflow (and triggers auto-rollback if enabled).
# MAGIC
# MAGIC | # | Check | Passes when |
# MAGIC |---|-------|-------------|
# MAGIC | 1 | table_exists | `customer_orders` exists |
# MAGIC | 2 | schema_columns | all expected columns are present |
# MAGIC | 3 | min_row_count | row count >= `expected_min_rows` |
# MAGIC | 4 | no_null_keys | no NULL `order_id` |
# MAGIC | 5 | no_duplicate_keys | `order_id` is unique |
# MAGIC | 6 | release_version_stamped | every row carries the release being deployed |
# MAGIC | 7 | env_name_stamped | every row carries this environment's name |

# COMMAND ----------

import json
import re
from datetime import datetime, timezone

dbutils.widgets.text("catalog", "workspace")
dbutils.widgets.text("schema", "nrap_demo_dev")
dbutils.widgets.text("env_name", "DEV")
dbutils.widgets.text("release_version", "local-dev")
dbutils.widgets.text("expected_min_rows", "5")
dbutils.widgets.text("job_run_id", "manual")

catalog = dbutils.widgets.get("catalog").strip()
schema = dbutils.widgets.get("schema").strip()
env_name = dbutils.widgets.get("env_name").strip().upper()
release_version = dbutils.widgets.get("release_version").strip()
expected_min_rows = int(dbutils.widgets.get("expected_min_rows").strip() or "1")
job_run_id = dbutils.widgets.get("job_run_id").strip()

IDENT = re.compile(r"^[A-Za-z0-9_]+$")
for label, value in (("catalog", catalog), ("schema", schema)):
    if not IDENT.match(value):
        raise ValueError(f"Invalid {label} name: {value!r}")

table = f"{catalog}.{schema}.customer_orders"
audit_table = f"{catalog}.{schema}.deployment_audit"

EXPECTED_COLUMNS = {
    "order_id", "customer_name", "order_amount", "order_date",
    "order_status", "env_name", "release_version", "load_ts",
}

results = []  # (check_name, status, details)


def record(check_name, passed, details):
    status = "PASS" if passed else "FAIL"
    results.append((check_name, status, details))
    print(f"[{status}] {check_name}: {details}")

# COMMAND ----------

# 1. Table exists
exists = spark.catalog.tableExists(table)
record("table_exists", exists, table)

if exists:
    df = spark.table(table)

    # 2. Schema columns
    missing = sorted(EXPECTED_COLUMNS - set(df.columns))
    record("schema_columns", not missing,
           "all expected columns present" if not missing else f"missing: {missing}")

    # 3-7 in one pass over the table
    stats = df.selectExpr(
        "count(*)                                                        AS row_count",
        "count_if(order_id IS NULL)                                      AS null_keys",
        "count(*) - count(DISTINCT order_id)                             AS duplicate_keys",
        f"count_if(release_version IS DISTINCT FROM '{release_version}') AS wrong_version_rows",
        f"count_if(env_name IS DISTINCT FROM '{env_name}')               AS wrong_env_rows",
    ).first()

    record("min_row_count", stats.row_count >= expected_min_rows,
           f"rows={stats.row_count}, expected>={expected_min_rows}")
    record("no_null_keys", stats.null_keys == 0, f"null order_id rows={stats.null_keys}")
    record("no_duplicate_keys", stats.duplicate_keys == 0, f"duplicate order_id rows={stats.duplicate_keys}")
    record("release_version_stamped", stats.wrong_version_rows == 0,
           f"rows not stamped with {release_version}: {stats.wrong_version_rows}")
    record("env_name_stamped", stats.wrong_env_rows == 0,
           f"rows not stamped with {env_name}: {stats.wrong_env_rows}")

# COMMAND ----------

# Write every check to the audit table (kept even when validation fails).
checked_at = datetime.now(timezone.utc).replace(tzinfo=None)
audit_rows = [
    (env_name, release_version, job_run_id, name, status, details, checked_at)
    for name, status, details in results
]
spark.createDataFrame(
    audit_rows,
    "env_name STRING, release_version STRING, job_run_id STRING, check_name STRING, "
    "status STRING, details STRING, checked_at TIMESTAMP",
).write.mode("append").saveAsTable(audit_table)

# COMMAND ----------

failed = [r for r in results if r[1] == "FAIL"]
summary = {
    "env_name": env_name,
    "release_version": release_version,
    "job_run_id": job_run_id,
    "checks": len(results),
    "failed": len(failed),
    "status": "FAIL" if failed else "PASS",
}
print(json.dumps(summary, indent=2))

if failed:
    # Raising (not dbutils.notebook.exit) marks the task - and the run - as FAILED.
    raise AssertionError(f"Deployment validation failed: {[r[0] for r in failed]}")

dbutils.notebook.exit(json.dumps(summary))
