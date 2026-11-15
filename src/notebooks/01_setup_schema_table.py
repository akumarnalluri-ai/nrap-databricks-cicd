# Databricks notebook source
# MAGIC %md
# MAGIC # 01 - Setup schema and table
# MAGIC Creates (idempotently) the Unity Catalog schema, the demo table `customer_orders`
# MAGIC and the `deployment_audit` table used by the validation step.
# MAGIC
# MAGIC All names come from job parameters, so the same notebook works in DEV, TEST and PROD.

# COMMAND ----------

import re

# Defaults are only used when the notebook is run by hand.
dbutils.widgets.text("catalog", "workspace")
dbutils.widgets.text("schema", "nrap_demo_dev")
dbutils.widgets.text("env_name", "DEV")
dbutils.widgets.text("release_version", "local-dev")
dbutils.widgets.text("create_catalog", "false")

catalog = dbutils.widgets.get("catalog").strip()
schema = dbutils.widgets.get("schema").strip()
env_name = dbutils.widgets.get("env_name").strip().upper()
release_version = dbutils.widgets.get("release_version").strip()
create_catalog = dbutils.widgets.get("create_catalog").strip().lower() == "true"

# Guard against bad identifiers (and SQL injection through parameters).
IDENT = re.compile(r"^[A-Za-z0-9_]+$")
for label, value in (("catalog", catalog), ("schema", schema)):
    if not IDENT.match(value):
        raise ValueError(f"Invalid {label} name: {value!r}")

print(f"Environment     : {env_name}")
print(f"Release version : {release_version}")
print(f"Target          : {catalog}.{schema}")

# COMMAND ----------

if create_catalog:
    spark.sql(f"CREATE CATALOG IF NOT EXISTS `{catalog}`")

spark.sql(
    f"CREATE SCHEMA IF NOT EXISTS `{catalog}`.`{schema}` "
    f"COMMENT 'NRAP CI/CD demo schema ({env_name})'"
)

# COMMAND ----------

# Demo table - the one business table deployed by this bundle.
spark.sql(f"""
CREATE TABLE IF NOT EXISTS `{catalog}`.`{schema}`.customer_orders (
    order_id        BIGINT        NOT NULL COMMENT 'Business key',
    customer_name   STRING                 COMMENT 'Customer display name',
    order_amount    DECIMAL(12,2)          COMMENT 'Order value in USD',
    order_date      DATE                   COMMENT 'Order date',
    order_status    STRING                 COMMENT 'NEW / SHIPPED / CANCELLED',
    env_name        STRING                 COMMENT 'Environment that loaded the row',
    release_version STRING                 COMMENT 'Release (Git tag) that loaded the row',
    load_ts         TIMESTAMP              COMMENT 'Load timestamp (UTC)'
)
USING DELTA
COMMENT 'NRAP CI/CD demo table'
""")

# Audit table - one row per validation check per job run.
spark.sql(f"""
CREATE TABLE IF NOT EXISTS `{catalog}`.`{schema}`.deployment_audit (
    env_name        STRING,
    release_version STRING,
    job_run_id      STRING,
    check_name      STRING,
    status          STRING,
    details         STRING,
    checked_at      TIMESTAMP
)
USING DELTA
COMMENT 'Deployment validation results written by 03_validate_deployment'
""")

# COMMAND ----------

dbutils.notebook.exit(f"OK: {catalog}.{schema} ready for {env_name} / {release_version}")
