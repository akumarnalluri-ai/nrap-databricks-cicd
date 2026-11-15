# Databricks notebook source
# MAGIC %md
# MAGIC # 02 - Load sample data
# MAGIC MERGEs a small, fixed set of sample orders into `customer_orders`.
# MAGIC Re-running is safe: existing order_ids are updated, new ones inserted, and rows
# MAGIC not in this release's dataset are deleted (so a rollback restores the old dataset).
# MAGIC Every row is stamped with the environment and the release version that loaded it,
# MAGIC which lets the validation step prove the deployed version actually ran.

# COMMAND ----------

import re

dbutils.widgets.text("catalog", "workspace")
dbutils.widgets.text("schema", "nrap_demo_dev")
dbutils.widgets.text("env_name", "DEV")
dbutils.widgets.text("release_version", "local-dev")

catalog = dbutils.widgets.get("catalog").strip()
schema = dbutils.widgets.get("schema").strip()
env_name = dbutils.widgets.get("env_name").strip().upper()
release_version = dbutils.widgets.get("release_version").strip()

IDENT = re.compile(r"^[A-Za-z0-9_]+$")
for label, value in (("catalog", catalog), ("schema", schema)):
    if not IDENT.match(value):
        raise ValueError(f"Invalid {label} name: {value!r}")

table = f"`{catalog}`.`{schema}`.customer_orders"

# COMMAND ----------

# Sample rows. Change or add rows here to demonstrate a new release (e.g. v1.1.0).
sample_orders = [
    (1001, "Acme Logistics",      1250.00, "2026-01-05", "NEW"),
    (1002, "Blue Ridge Freight",   980.50, "2026-01-06", "SHIPPED"),
    (1003, "Lone Star Transit",   4310.75, "2026-01-07", "SHIPPED"),
    (1004, "Metro Road Services",  220.00, "2026-01-08", "CANCELLED"),
    (1005, "Trinity Fleet Co",    1899.99, "2026-01-09", "NEW"),
]

from delta.tables import DeltaTable
from pyspark.sql import functions as F

source = (
    spark.createDataFrame(
        sample_orders,
        "order_id BIGINT, customer_name STRING, order_amount DOUBLE, order_date STRING, order_status STRING",
    )
    .withColumn("order_amount", F.col("order_amount").cast("decimal(12,2)"))
    .withColumn("order_date", F.to_date("order_date"))
    .withColumn("env_name", F.lit(env_name))
    .withColumn("release_version", F.lit(release_version))
    .withColumn("load_ts", F.current_timestamp())
)

(
    DeltaTable.forName(spark, f"{catalog}.{schema}.customer_orders")
    .alias("t")
    .merge(source.alias("s"), "t.order_id = s.order_id")
    .whenMatchedUpdateAll()
    .whenNotMatchedInsertAll()
    # Rows that are not part of this release's dataset are removed, so after a
    # rollback the table matches the restored version exactly.
    .whenNotMatchedBySourceDelete()
    .execute()
)

# COMMAND ----------

loaded = spark.table(table).count()
print(f"{table} now holds {loaded} rows (release {release_version}, env {env_name})")
dbutils.notebook.exit(f"OK: {loaded} rows")
