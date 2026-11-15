# NRAP Databricks CI/CD - GitHub Actions + Databricks Asset Bundles

Automated, version-controlled deployment of Databricks notebooks and jobs from GitHub to
**DEV** and **TEST** (PROD-ready), executed on a **self-hosted VM runner**, with an
**approval gate** for higher environments, **post-deployment validation**, **execution logs**,
**automatic rollback** on failure and a **manual rollback** to any previously approved version.

The demo payload is intentionally small: **1 schema, 1 table (`customer_orders`), 1 job** with three
notebook tasks (setup → load → validate). It runs as-is on **Databricks Free Edition**.

---

## How it works (one picture)

```
 Developer                     GitHub                                  Self-hosted VM runner              Databricks
 ─────────                     ──────                                  ─────────────────────              ──────────
 PR to main ───────────▶ CI - Validate (syntax + bundle validate)
 git tag v1.1.0 + push ─▶ Release workflow → GitHub Release v1.1.0
 Actions ▸ Deploy Databricks
   env=dev, version=v1.1.0 ─────────────────────────────────────▶ checkout v1.1.0
                                                                   bundle validate/deploy -t dev ───▶ job nrap_demo_job_dev
                                                                   bundle run (validation task) ────▶ customer_orders + audit
                                                                   verify (job tag, notebooks, run)
   env=test, version=v1.1.0 ─▶ ⏸ waits for reviewer approval ─▶ same steps with -t test ──────────▶ job nrap_demo_job_test
 On failure ─────────────────────────────────────────────────────▶ auto-redeploy the version that was live before
 Actions ▸ Rollback Databricks (version=previous | v1.0.0) ─────▶ redeploy that tag (approval again for TEST)
```

## Repository layout

```
Halvik/
├── databricks.yml                     # Asset Bundle: variables + dev/test/prod targets
├── resources/nrap_demo_job.yml        # The Databricks job (3 notebook tasks, parameters, tags)
├── src/notebooks/
│   ├── 01_setup_schema_table.py       # CREATE SCHEMA / TABLE customer_orders + deployment_audit
│   ├── 02_load_sample_data.py         # MERGE sample rows stamped with env + release version
│   └── 03_validate_deployment.py      # 7 data checks, writes audit rows, fails run on error
├── config/
│   ├── dev.env  test.env  prod.env    # Non-secret pipeline settings per environment
├── .github/
│   ├── workflows/
│   │   ├── deploy-databricks.yml      # MANUAL: pick environment + version → deploy
│   │   ├── rollback-databricks.yml    # MANUAL: redeploy "previous" or a chosen version
│   │   ├── _reusable-deploy.yml       # The actual deployment logic (used by both above)
│   │   ├── ci-validate.yml            # PR / main: static checks + bundle validate
│   │   └── release.yml                # Tag push v*.*.* → GitHub Release
│   └── CODEOWNERS                     # Required reviewers for pipeline/config changes
├── scripts/
│   ├── ci/                            # Bash steps called by the workflows (logging, deploy, verify …)
│   ├── runner/                        # Self-hosted runner install (Linux + Windows) and checks
│   └── find_placeholders.sh           # Lists every __REPLACE_…__ placeholder left
├── docs/                              # Full documentation (start with 00_IMPLEMENTATION_GUIDE.md)
├── CHANGELOG.md
├── .gitattributes                     # Forces LF endings (repo lives on Windows/OneDrive)
└── .gitignore
```

## Quick start (15 minutes with free accounts)

1. **Databricks Free Edition** – sign up, copy the workspace URL, create a personal access token.
2. **GitHub** – create a repo, push this folder to `main`.
3. **Environments** – in GitHub *Settings → Environments* create `dev` and `test`; add secrets
   `DATABRICKS_HOST` and `DATABRICKS_TOKEN` to each; add yourself as **Required reviewer** on `test`.
4. **Runner** – register a self-hosted runner with label `databricks-deploy`
   (`scripts/runner/setup-runner-linux.sh` or `setup-runner-windows.ps1`).
5. **Release** – `git tag v1.0.0 && git push origin v1.0.0`.
6. **Deploy** – *Actions → Deploy Databricks → Run workflow* → `dev`, `v1.0.0`. Then `test`, `v1.0.0` → approve.

Detailed steps: **[docs/06_DEMO_RUNBOOK.md](docs/06_DEMO_RUNBOOK.md)**.

## Documentation

| Doc | Read it when |
|---|---|
| [00_IMPLEMENTATION_GUIDE.md](docs/00_IMPLEMENTATION_GUIDE.md) | Start here – overview, requirement traceability, reading order |
| [01_ARCHITECTURE_AND_FILES.md](docs/01_ARCHITECTURE_AND_FILES.md) | You want to know what every file does and how they connect |
| [02_PLACEHOLDERS_GUIDE.md](docs/02_PLACEHOLDERS_GUIDE.md) | You need to change names, catalogs, schemas, workspaces, runners, secrets |
| [03_GITHUB_SETUP.md](docs/03_GITHUB_SETUP.md) | Setting up environments, secrets, approvals, branch/tag protection |
| [04_SELF_HOSTED_RUNNER_SETUP.md](docs/04_SELF_HOSTED_RUNNER_SETUP.md) | Building the VM runner |
| [05_DEPLOYMENT_VALIDATION_ROLLBACK.md](docs/05_DEPLOYMENT_VALIDATION_ROLLBACK.md) | Day-to-day operations, logs, failures, rollback |
| [06_DEMO_RUNBOOK.md](docs/06_DEMO_RUNBOOK.md) | Running the DEV → TEST demo end to end |
| [07_SETUP_WALKTHROUGH.md](docs/07_SETUP_WALKTHROUGH.md) | The exact setup we did step by step, how CI - Validate / Release / _reusable-deploy work inside, problems and fixes |
| [08_USING_THIS_REPO.md](docs/08_USING_THIS_REPO.md) | **Sharing the repo** – how collaborators use it, or how to set up your own copy with your own secrets |
| [09_RUNNER_START_STOP.md](docs/09_RUNNER_START_STOP.md) | Turning the laptop runner back on after closing PowerShell, desktop shortcut, what happens while it is off |
