# 06 – Demo Runbook: deploy a selected version to DEV and TEST

Goal: show, with free accounts, (1) deploying a chosen release to DEV, (2) promoting the same release to TEST
behind an approval, (3) a new release, and (4) a rollback. About 30–40 minutes the first time.

## Part A – One-time setup

### A1. Databricks Free Edition
1. Sign up at databricks.com (Free Edition). Open the workspace and copy the URL from the browser,
   e.g. `https://dbc-1234abcd-5678.cloud.databricks.com`.
2. *User menu (top right) → Settings → Developer → Access tokens → Generate new token* → name `github-cicd`,
   copy the `dapi…` value.

### A2. GitHub repository
1. Create a repository (public is simplest for the free demo – see the plan note in docs/03 §3).
2. Push this folder to `main` (docs/03 §1).

### A3. GitHub environments
1. *Settings → Environments → New environment* `dev` → add secrets `DATABRICKS_HOST`, `DATABRICKS_TOKEN`.
2. New environment `test` → same two secrets → tick **Required reviewers**, add yourself
   (leave **Prevent self-review** unticked for a solo demo) → *Deployment branches: Selected → `main`*.

### A4. Self-hosted runner
Follow docs/04 on your laptop or a VM with label `databricks-deploy`. Confirm it shows **Idle**.

### A5. First release
```bash
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0
```
*Actions → Release* runs and creates release **v1.0.0**.

## Part B – Deploy v1.0.0 to DEV

1. *Actions → Deploy Databricks → Run workflow* → branch `main`, environment **dev**, version **v1.0.0**,
   reason `Demo – initial DEV deployment` → **Run workflow**.
2. Watch the steps: load config → auth → resolve version → checkout tag → deploy → run job → verify.
3. Evidence to capture:
   - Run summary table (✅, deployed version v1.0.0).
   - Artifact `databricks-dev-v1.0.0-run…` → open `deploy.log`, `run.log`.
   - Databricks *Jobs & Pipelines* → `nrap_demo_job_dev` → tags `release_version: v1.0.0`; run graph with 3 green tasks.
   - *Catalog → workspace → nrap_demo_dev → customer_orders* → 5 rows, `release_version = v1.0.0`.
   - SQL editor: `SELECT * FROM workspace.nrap_demo_dev.deployment_audit ORDER BY checked_at DESC;` → 7 PASS rows.

## Part C – Promote v1.0.0 to TEST with approval

1. *Run workflow* → environment **test**, version **v1.0.0**.
2. The run shows **Waiting for review** – capture this screenshot (the approval gate).
3. *Review deployments* → tick `test` → comment "Approved for TEST" → **Approve and deploy**.
4. Evidence: summary ✅; job `nrap_demo_job_test`; schema `nrap_demo_test`; `env_name = TEST` in the data;
   *Settings → Environments → test* shows the deployment with approver.
   This proves environment-specific configuration: same tag, different catalog/schema/job/parameters.

## Part D – Ship v1.1.0

1. In `src/notebooks/02_load_sample_data.py` add a row:
   `(1006, "Panhandle Haulers", 735.40, "2026-01-10", "NEW"),`
2. In `databricks.yml` set `expected_min_rows: "6"` for `dev` and `test`.
3. Commit to `main` (via PR to show CI - Validate), then `git tag -a v1.1.0 -m "Release v1.1.0" && git push origin v1.1.0`.
4. Deploy **v1.1.0** (or **latest**) to **dev**, then to **test** (approve).
5. Evidence: 6 rows stamped `v1.1.0`; job tag `v1.1.0`.

## Part E – Rollback

1. *Actions → Rollback Databricks* → environment **test**, version **previous**, reason `Demo rollback`.
2. Approve. The log shows `'previous' resolved to v1.0.0`.
3. Evidence: job tag back to `v1.0.0`; table back to 5 rows stamped `v1.0.0` (order 1006 removed); audit rows for v1.0.0.

## Part F (optional) – Failed release with automatic rollback

1. Tag a broken release: set `expected_min_rows: "100"` for `dev` in `databricks.yml`, commit, tag `v1.2.0`, push.
2. Deploy **v1.2.0** to **dev** (`auto_rollback` ticked).
3. Validation task fails (`min_row_count` FAIL) → workflow redeploys the version that was live before.
4. Evidence: run ❌ with summary "Auto-rollback: ✅ rolled back to v1.1.0"; `deployment_audit` shows the FAIL row
   for v1.2.0 followed by PASS rows for v1.1.0; job tag `v1.1.0`.
5. Clean up: revert the change on `main` and delete the tag if you like (`git push --delete origin v1.2.0`).

## Clean up the demo

```bash
# from a checkout of the latest tag, with DATABRICKS_HOST/TOKEN set locally
databricks bundle destroy -t dev  --auto-approve
databricks bundle destroy -t test --auto-approve
```
Then drop the schemas in Databricks: `DROP SCHEMA workspace.nrap_demo_dev CASCADE;` (and `_test`).

## Presenting it (suggested 10-minute flow)

1. Repo tour: `databricks.yml` targets → `resources/` job → notebooks → `config/` → workflows (2 min).
2. Live: deploy `latest` to DEV (3 min, runs ~2–4 min on serverless).
3. Live: deploy same tag to TEST, show approval, approve (3 min).
4. Show rollback run from earlier + audit table + log artifact (2 min).
