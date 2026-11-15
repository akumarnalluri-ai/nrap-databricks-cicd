# Changelog

Each entry corresponds to a Git tag that can be selected in the **Deploy Databricks** workflow.

## v1.1.0 (demo change - create when you run the demo)
- Add a sixth sample order (order_id 1006) in `src/notebooks/02_load_sample_data.py`
- Raise `expected_min_rows` to 6 for dev and test in `databricks.yml`

## v1.0.0
- Initial release: schema `nrap_demo_<env>`, table `customer_orders`, audit table `deployment_audit`
- Job `nrap_demo_job_<env>` with setup, load and validation tasks
