# 01 – Architecture and File Reference

## 1. Where configuration lives (the four layers)

| Layer | File / location | Holds | Example |
|---|---|---|---|
| Databricks config | `databricks.yml` → `targets.<env>.variables` | Catalog, schema, env name, validation threshold, workspace folder | `schema: nrap_demo_test` |
| Pipeline config | `config/<env>.env` | How the workflow behaves for that env | `AUTO_ROLLBACK_ON_FAILURE=true` |
| Secrets | GitHub → Settings → Environments → `<env>` | Workspace URL + credentials | `DATABRICKS_TOKEN` |
| Runtime | Job parameters (`resources/nrap_demo_job.yml`) | Values pushed into notebooks at run time | `catalog`, `schema`, `release_version` |

Selecting `environment=test` in the workflow picks: GitHub environment `test` (its secrets + approval),
`config/test.env`, bundle target `test`, and therefore all `test` variables → job parameters → notebooks.

## 2. Deployment sequence

```
workflow_dispatch (environment, version)
  └─ deploy-databricks.yml ──calls──▶ _reusable-deploy.yml
        job "deploy"  (runs-on self-hosted, environment: <env>)
          0  ⏸ approval (only if the GitHub environment has required reviewers)
          1  checkout pipeline code (main, full history + tags)        → pipeline/
          2  load_env_config.sh   config/<env>.env → job env vars
          3  install Databricks CLI only if missing
          4  check_auth.sh        tools present, one auth method, login works
          5  resolve_version.sh   latest/previous/explicit → verified tag; record live version
          6  checkout the tag                                           → release/
          7  deploy_bundle.sh     bundle validate → bundle deploy → bundle summary
          8  run_job.sh           bundle run (waits) – job task 3 = data validation
          9  verify_deployment.sh job exists, tag = version, notebooks exist, last run SUCCESS
         10  (on failure) checkout previous tag → deploy → run → verify   (auto-rollback)
         11  write_summary.sh     run summary table (always)
         12  upload logs artifact (always, 90 days)
```

## 3. File-by-file reference

### Root

| File | What it does | Change it when |
|---|---|---|
| `databricks.yml` | Bundle definition. `bundle.name` (used in the workspace folder path), `include` of resource files, **variables** with defaults, and **targets** `dev`, `test`, `prod` that override variables and set `root_path` (where files are deployed: `/Workspace/Shared/.bundle/nrap_cicd_demo/<target>`). `databricks_cli_version` blocks old CLIs. | New environment, new catalog/schema, pinning a workspace host, adding `run_as` for PROD. |
| `README.md` | Overview and quick start. | – |
| `CHANGELOG.md` | Human-readable list of releases. | Every new tag. |
| `.gitattributes` | Forces LF line endings for `.sh/.yml/.env/.py` so files edited on Windows/OneDrive still run on a Linux runner. | Rarely. |
| `.gitignore` | Keeps local bundle state (`.databricks/`), credentials and logs out of Git. | Rarely. |

### `resources/nrap_demo_job.yml`

The Databricks job `nrap_demo_job_<target>`:

- `tags` – `environment`, `release_version` (read by the scripts for verification and rollback), `managed_by`, `project`.
- `parameters` – `catalog`, `schema`, `env_name`, `release_version`, `expected_min_rows`, `create_catalog`, `job_run_id` (`{{job.run_id}}` dynamic value). Job parameters are passed automatically to every notebook as widgets.
- `tasks` – `setup_schema_table` → `load_sample_data` → `validate_deployment`, each a `notebook_task` pointing at `../src/notebooks/*.py`.
- No cluster is declared → **serverless** compute. A commented `job_clusters` block shows the classic-cluster alternative.
- `email_notifications` is commented out until a real address is configured (the Jobs API rejects blank addresses).
- `max_concurrent_runs: 1`, `timeout_seconds: 3600`.

### `src/notebooks/` (Databricks "source" format `.py`)

| Notebook | Behaviour |
|---|---|
| `01_setup_schema_table.py` | Reads widgets, validates identifiers (`^[A-Za-z0-9_]+$`), optionally `CREATE CATALOG`, then `CREATE SCHEMA IF NOT EXISTS`, `CREATE TABLE IF NOT EXISTS customer_orders` (8 columns) and `deployment_audit`. Idempotent. |
| `02_load_sample_data.py` | Builds 5 sample orders, stamps `env_name`, `release_version`, `load_ts`, and Delta-`MERGE`s on `order_id`: update, insert, and delete rows not in this release (re-runnable; after a rollback the table matches the restored release). Edit the `sample_orders` list to show a new release. |
| `03_validate_deployment.py` | 7 checks: table exists, expected columns, min row count, no NULL keys, no duplicate keys, every row stamped with this release, every row stamped with this env. Appends one row per check to `deployment_audit`, prints a JSON summary and **raises** if any check fails (fails the job → fails the workflow → triggers auto-rollback). |

### `config/`

`dev.env`, `test.env`, `prod.env` – `KEY=VALUE` files loaded by `scripts/ci/load_env_config.sh`:

| Key | Meaning |
|---|---|
| `BUNDLE_TARGET` | Target name in `databricks.yml` |
| `JOB_RESOURCE_KEY` | Job key under `resources.jobs` (used by `bundle run`) |
| `JOB_NAME` | Deployed job name (`nrap_demo_job_<target>`) – used to look the job up |
| `RUN_JOB_AFTER_DEPLOY` | Run the job (and its validation task) after deploying |
| `AUTO_ROLLBACK_ON_FAILURE` | Redeploy the previously live version if anything fails |
| `REQUIRE_TAG_ON_MAIN` | Reject tags whose commit is not on `MAIN_BRANCH` (on for TEST/PROD) |
| `MAIN_BRANCH` | Protected branch name |

### `.github/workflows/`

| Workflow | Trigger | Runner | Purpose |
|---|---|---|---|
| `deploy-databricks.yml` | Manual (`workflow_dispatch`) | – (caller) | Inputs: `environment`, `version`, `run_job`, `auto_rollback`, `reason`. One deployment per env at a time (`concurrency`). Calls the reusable workflow. |
| `rollback-databricks.yml` | Manual | – (caller) | Inputs: `environment`, `version` (`previous` or tag), `reason` (required). Same concurrency group, auto-rollback disabled. |
| `_reusable-deploy.yml` | `workflow_call` | self-hosted | All deployment logic (sequence in §2). Uses `environment:` → approval + env secrets. Uploads logs. |
| `ci-validate.yml` | PR to `main`, push to `main` | hosted for static checks, self-hosted for `bundle validate` | Notebook/shell syntax, CRLF guard, `bundle validate -t dev`. Fork PRs never reach the self-hosted runner. |
| `release.yml` | Push of tag `v*.*.*` | hosted | Creates a GitHub Release with generated notes (no-op if it already exists). |

`.github/CODEOWNERS` – owners who must review PRs to the pipeline and config (placeholders).

### `scripts/ci/` (called by workflows; can also be run locally)

| Script | Purpose |
|---|---|
| `common.sh` | Logging (`log/warn/die` → console + `pipeline.log` + GitHub annotations), `run_logged` (tee to per-step log, keep exit code), GitHub output helpers, Databricks lookups: `find_job_id`, `get_deployed_version`, `find_previous_good_version`. |
| `load_env_config.sh <env>` | Loads `config/<env>.env` (CRLF-tolerant), validates required keys. |
| `check_auth.sh` | Checks `databricks`, `jq`, `git`; exactly one auth method; logs in with `current-user me`. |
| `resolve_version.sh` | Resolves `latest` (highest `vX.Y.Z`), `previous` (last successful run's version before the live one) or an explicit tag; verifies the tag; enforces on-main rule; outputs `version`, `commit`, `previous_version`. |
| `deploy_bundle.sh <dir> <target> <version> [log]` | `bundle validate` → `bundle deploy --auto-approve` → `bundle summary`. `FORCE_LOCK=true` adds `--force-lock`. |
| `run_job.sh <dir> <target> <version> <job-key> [log]` | `bundle run` and wait; captures the run URL; fails if the run fails. |
| `verify_deployment.sh <version> <job-name> [expect-run]` | Job exists, `release_version` tag matches, notebooks exist, latest run SUCCESS with the same version. Saves the deployed job JSON to the logs. |
| `write_summary.sh` | Run summary table: result, versions, rollback outcome, job/run URLs, who, why, runner. |

### `scripts/runner/`

| Script | Purpose |
|---|---|
| `setup-runner-linux.sh` | Installs packages, creates `ghrunner` user, downloads & registers the runner with labels, installs as a systemd service, installs Databricks CLI, optional proxy. |
| `setup-runner-windows.ps1` | Same for Windows: Git for Windows (bash), jq, Databricks CLI via winget; runner as a Windows service. |
| `check-runner-prereqs.sh` | Health check on the VM: tools, outbound HTTPS, optional Databricks login. |

### `scripts/find_placeholders.sh`

Lists every `__REPLACE_…__` placeholder still present (active vs. commented/optional).

## 4. Objects created in Databricks per environment

| Object | DEV (default) | TEST (default) |
|---|---|---|
| Workspace folder | `/Workspace/Shared/.bundle/nrap_cicd_demo/dev` | `…/test` |
| Job | `nrap_demo_job_dev` | `nrap_demo_job_test` |
| Schema | `workspace.nrap_demo_dev` | `workspace.nrap_demo_test` |
| Table | `workspace.nrap_demo_dev.customer_orders` | `workspace.nrap_demo_test.customer_orders` |
| Audit table | `…nrap_demo_dev.deployment_audit` | `…nrap_demo_test.deployment_audit` |
