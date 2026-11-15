# 00 – Implementation Guide (start here)

## 1. Purpose

This repository implements an automated, version-controlled deployment process for Databricks
notebooks and jobs using **GitHub Actions** and **Databricks Asset Bundles (DABs)**. GitHub is the
single source of truth; a deployment is always "release tag X → environment Y", executed by a
designated self-hosted VM runner, approved where policy requires, validated after deployment, and
reversible.

## 2. Requirement traceability

| # | Requirement | Where it is implemented |
|---|---|---|
| 1 | GitHub as the deployment source | Notebooks in `src/notebooks/`, job in `resources/nrap_demo_job.yml`, bundle in `databricks.yml`. The workflow checks out the **tag** and deploys only from it. |
| 2 | Version-based deployment (tag/release) | `deploy-databricks.yml` input **version** (`v1.2.0` or `latest`); `scripts/ci/resolve_version.sh` verifies the tag exists (and, for TEST, that it is on `main`); `release.yml` publishes a GitHub Release for every `vX.Y.Z` tag. |
| 3 | DEV and TEST environment selection | Workflow input **environment** (`dev` / `test`); PROD template ready in `databricks.yml` and `config/prod.env`. |
| 4 | Environment-specific configuration | Catalog, schema, env name, thresholds, workspace path → `databricks.yml` **targets**; pipeline behaviour → `config/<env>.env`; credentials/workspace URL → **GitHub environment secrets**; runtime values → job **parameters** pushed into the notebooks. Selecting the environment applies all four automatically. |
| 5 | Self-hosted VM runner | All Databricks-touching jobs use `runs-on: [self-hosted, databricks-deploy]` (overridable with repo variable `RUNNER_LABELS`). Install scripts in `scripts/runner/`; guide in `docs/04`. |
| 6 | Approval for TEST/PROD | GitHub **Environments** `test` (and `prod`) with **Required reviewers**; the deploy job declares `environment: <env>`, so it pauses until approved and secrets are released only after approval. See `docs/03`. |
| 7 | Validation, logs, error handling, rollback | `bundle validate` before deploy; job task `03_validate_deployment` (7 data checks + audit table); `verify_deployment.sh` (job tag, notebooks, last run); logs uploaded as artifacts (90 days) + run summary; `::error::` annotations; automatic rollback to the previously live version; manual `rollback-databricks.yml` with `previous` or any tag. |

## 3. Deliverables in this folder

| Deliverable | Files |
|---|---|
| GitHub Actions workflow YAML | `.github/workflows/*.yml` (5 files) |
| Databricks deployment configuration (DABs) | `databricks.yml`, `resources/nrap_demo_job.yml` |
| Environment-specific configuration & parameters | `databricks.yml` targets, `config/*.env`, GitHub environment secrets (documented) |
| Self-hosted runner setup instructions | `docs/04_SELF_HOSTED_RUNNER_SETUP.md`, `scripts/runner/*` |
| Deployment, validation and rollback documentation | `docs/05_DEPLOYMENT_VALIDATION_ROLLBACK.md` |
| Demonstration DEV and TEST | `docs/06_DEMO_RUNBOOK.md` (scripted steps + evidence checklist) |
| Placeholder / file reference | `docs/01_ARCHITECTURE_AND_FILES.md`, `docs/02_PLACEHOLDERS_GUIDE.md` |

## 4. Reading order

1. `README.md` – one-page overview
2. `docs/01` – what each file does
3. `docs/02` – what you must change for your environment
4. `docs/03` + `docs/04` – one-time GitHub and runner setup
5. `docs/06` – run the demo
6. `docs/05` – keep for operations

## 5. Key design decisions

- **Deploy from tags, not branches.** The workflow itself runs from `main` (so the latest pipeline
  logic is always used), but the bundle content comes from the selected tag. A release is immutable;
  redeploying `v1.0.0` next month deploys exactly what was approved.
- **One reusable workflow.** Deploy and rollback call the same `_reusable-deploy.yml`, so a rollback
  goes through identical checks, validation, logging and approval.
- **Version is visible everywhere.** The deployed job is tagged `release_version=<tag>`, every data
  row is stamped with it, every validation result is written to `deployment_audit` with it, and the
  GitHub run summary records it. That is also how "previous good version" is found for rollback.
- **No secrets in the repo.** Workspace URL and credentials live only in GitHub environment secrets.
- **Free-tier friendly.** Serverless compute, the default `workspace` catalog and a personal access
  token make the demo work on Databricks Free Edition; enterprise options (separate catalogs and
  workspaces, service principals, classic clusters, PROD) are one-line changes documented in `docs/02`.

## 6. Tested before hand-over

- All YAML parses; `databricks.yml` and `resources/nrap_demo_job.yml` validate against the official
  bundle JSON schema from Databricks CLI v1.26.0.
- Workflows pass `actionlint`; all bash scripts pass `shellcheck` and `bash -n`; notebooks compile.
- The CI scripts were exercised end-to-end against a mocked Databricks CLI (tag resolution for
  `latest` / `previous` / explicit, tag-not-on-main and missing-tag rejections, deploy, run,
  verification pass and mismatch failure, summary output).
- **Not yet run against a live workspace** – that is the demo in `docs/06`.
