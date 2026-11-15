# 02 – Placeholders and Configuration Guide

Everything you may need to change, where it is, and what to put there.

> **Find what's left:** `bash scripts/find_placeholders.sh` lists every `__REPLACE_…__` marker with file and line.
> For the **Free Edition demo you only need section 1** (GitHub secrets + runner). All other defaults work as shipped.

---

## 1. Required for any deployment (not in files – set in GitHub)

| Name | Where | Type | Value | Example |
|---|---|---|---|---|
| `DATABRICKS_HOST` | Settings → Environments → `dev` / `test` | Secret (or variable) | Workspace URL, no trailing path | `https://dbc-a1b2c3d4-e5f6.cloud.databricks.com` |
| `DATABRICKS_TOKEN` | same | Secret | Personal access token **or** leave empty and use the two below | `dapi…` |
| `DATABRICKS_CLIENT_ID` | same | Secret | Service principal application (client) ID | `6b2c…` |
| `DATABRICKS_CLIENT_SECRET` | same | Secret | Service principal OAuth secret | `dose…` |
| `RUNNER_LABELS` | Settings → Secrets and variables → Actions → **Variables** (repository) | Variable, JSON array | Only if your runner labels differ from the default `["self-hosted","databricks-deploy"]` | `["self-hosted","linux","nrap-deploy"]` |
| `CI_RUNNER_LABELS` | same | Variable, JSON array | Only if GitHub-hosted runners are not allowed in your org (used by static checks and release) | `["self-hosted","databricks-deploy"]` |

Rules: set **either** `DATABRICKS_TOKEN` **or** the client ID + secret pair per environment, not both
(`check_auth.sh` stops the run if both are present). Use a different identity per environment in
real projects so DEV credentials can never touch TEST.

---

## 2. Placeholders inside files

| Placeholder | File | Required? | Replace with |
|---|---|---|---|
| `__REPLACE_DEV_WORKSPACE_URL__` | `databricks.yml` (commented `host:` under `targets.dev.workspace`) | Optional | DEV workspace URL. Uncomment to hard-pin the target to that workspace (recommended when DEV/TEST/PROD are separate workspaces – the CLI then refuses to deploy if `DATABRICKS_HOST` points elsewhere). |
| `__REPLACE_TEST_WORKSPACE_URL__` | `databricks.yml` `targets.test` | Optional | TEST workspace URL |
| `__REPLACE_PROD_WORKSPACE_URL__` | `databricks.yml` `targets.prod` | Optional (PROD) | PROD workspace URL |
| `__REPLACE_PROD_SP_APPLICATION_ID__` | `databricks.yml` `targets.prod.run_as` (commented) | Recommended for PROD | Application ID of the service principal the PROD job runs as |
| `__REPLACE_DEV/TEST/PROD_NOTIFICATION_EMAIL__` | `databricks.yml` comments next to `notification_email` | Optional | Put the address in `notification_email: "team@agency.gov"` for every target, then uncomment `email_notifications` in `resources/nrap_demo_job.yml`. |
| `__REPLACE_NODE_TYPE__` | `resources/nrap_demo_job.yml` (commented `job_clusters`) | Only for classic clusters | Node type, e.g. `Standard_DS3_v2` (Azure), `i3.xlarge` (AWS), `n2-standard-4` (GCP) |
| `__REPLACE_DEFAULT_CODE_OWNER__` | `.github/CODEOWNERS` | Recommended | GitHub user or team, e.g. `@my-org/data-engineering` |
| `__REPLACE_DEVOPS_CODE_OWNER__` | `.github/CODEOWNERS` | Recommended | GitHub user or team owning the pipeline, e.g. `@my-org/devops` |

---

## 3. Values with working defaults you will likely change for a real project

### 3.1 `databricks.yml`

| Setting | Default | Change to (enterprise example) | Notes |
|---|---|---|---|
| `bundle.name` | `nrap_cicd_demo` | `nrap_revenue_jobs` | Changes the workspace folder `…/.bundle/<name>/<target>`. Changing it after deployment creates a *new* deployment; delete the old one with `databricks bundle destroy` from the old version. |
| `targets.dev.variables.catalog` | `workspace` | `nrap_dev` | Free Edition only has the `workspace` catalog by default. |
| `targets.test.variables.catalog` | `workspace` | `nrap_test` | |
| `targets.*.variables.schema` | `nrap_demo_dev` / `nrap_demo_test` / `nrap_demo_prod` | `enr_nrap` | With separate catalogs per env the schema name can be identical in all envs. |
| `variables.create_catalog` | `"false"` | `"true"` only if the deploy identity may create catalogs | Usually catalogs are created by the platform team. |
| `targets.*.variables.expected_min_rows` | `"5"` | Your real minimum | Used by validation check `min_row_count`. |
| `targets.*.workspace.root_path` | `/Workspace/Shared/.bundle/${bundle.name}/${bundle.target}` | Keep, or a restricted folder like `/Workspace/NRAP/deployments/...` | The deploy identity needs write access there. |
| `targets.prod.run_as` | commented | `service_principal_name: <app-id>` | Jobs in PROD should not run as a person. |

### 3.2 `resources/nrap_demo_job.yml`

| Setting | Default | Notes |
|---|---|---|
| job key `nrap_demo_job` | – | If renamed, update `JOB_RESOURCE_KEY` in **all** `config/*.env`. |
| `name: nrap_demo_job_${bundle.target}` | – | If renamed, update `JOB_NAME` in **all** `config/*.env` (scripts look the job up by name). |
| `tags.project` | `nrap` | Any value. Do **not** remove `release_version` – validation and rollback rely on it. |
| `timeout_seconds`, `max_concurrent_runs` | 3600, 1 | |
| compute | serverless | For classic clusters uncomment `job_clusters` and add `job_cluster_key: main_cluster` to each task. |
| `email_notifications` | commented | Uncomment after setting `notification_email` (see §2). |

### 3.3 `config/<env>.env`

| Key | dev | test | When to change |
|---|---|---|---|
| `BUNDLE_TARGET` | `dev` | `test` | Only if you rename targets |
| `JOB_RESOURCE_KEY` | `nrap_demo_job` | same | If job key renamed |
| `JOB_NAME` | `nrap_demo_job_dev` | `nrap_demo_job_test` | If job name pattern changed |
| `RUN_JOB_AFTER_DEPLOY` | `true` | `true` | Set `false` for jobs that must not run on deploy (then only workspace-level verification happens) |
| `AUTO_ROLLBACK_ON_FAILURE` | `true` | `true` | |
| `REQUIRE_TAG_ON_MAIN` | `false` | `true` | Keep `true` for TEST/PROD |
| `MAIN_BRANCH` | `main` | `main` | If your default branch is `master` / `develop` |

### 3.4 Workflows

| Setting | File | Change when |
|---|---|---|
| `options:` list (`dev`, `test`, `# - prod`) | `deploy-databricks.yml`, `rollback-databricks.yml` | Enabling PROD: uncomment `- prod` in both, create GitHub environment `prod` with reviewers + secrets. |
| Runner labels default `["self-hosted","databricks-deploy"]` | `_reusable-deploy.yml`, `ci-validate.yml` | Prefer setting repo variable `RUNNER_LABELS` instead of editing. |
| `retention-days: 90` | `_reusable-deploy.yml` | Log retention policy (max depends on org settings). |
| `timeout-minutes: 90` | `_reusable-deploy.yml` | Long-running jobs. |
| `databricks/setup-cli@main` | `_reusable-deploy.yml`, `ci-validate.yml` | Pin to a release tag for reproducibility; only used when the runner has no CLI. |

### 3.5 Notebooks

| What | Where | Notes |
|---|---|---|
| Table name `customer_orders` | all three notebooks | Rename consistently in 01, 02 (`DeltaTable.forName`) and 03. |
| Columns | 01 (`CREATE TABLE`), 02 (data), 03 (`EXPECTED_COLUMNS`) | Keep the three in sync. |
| Sample rows | 02 `sample_orders` | Change to demonstrate a new release. |
| Widget defaults | top of each notebook | Only used for manual runs in the UI. |

---

## 4. Adding a new environment (e.g. UAT) – checklist

1. `databricks.yml`: copy the `test` target as `uat`, set variables.
2. `config/uat.env`: copy `test.env`, set `BUNDLE_TARGET=uat`, `JOB_NAME=nrap_demo_job_uat`.
3. Workflows: add `- uat` to the `options` of deploy and rollback.
4. GitHub: create environment `uat` with secrets and reviewers.

## 5. Moving from Free Edition to the agency workspace – checklist

1. Separate catalogs per env → set `catalog` per target (§3.1).
2. Separate workspaces → uncomment `host:` per target (§2) and set `DATABRICKS_HOST` per GitHub environment.
3. Service principal per environment → replace `DATABRICKS_TOKEN` with `DATABRICKS_CLIENT_ID/SECRET`; grant it `USE CATALOG`, `USE SCHEMA`, `CREATE TABLE`, `MODIFY`, `SELECT` on the target schema and `CAN MANAGE` on the `root_path` folder.
4. PROD `run_as` service principal.
5. Classic clusters if serverless is not approved.
6. Pin `databricks/setup-cli` and the runner's CLI version.
7. Fill `CODEOWNERS`, enable branch protection and tag rules (docs/03).
