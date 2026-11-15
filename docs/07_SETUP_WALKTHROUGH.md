# 07 – Setup Walkthrough (what we did, step by step) and How the Workflows Work

This is the record of how this CI/CD setup was built and tested end to end with a **Databricks Free
Edition** workspace, a **public GitHub repository** and a **Windows laptop as the self-hosted runner**.
Part A is the setup, in the order it was done. Part B explains what happens inside each workflow.
Part C lists the problems we hit and how they were fixed.

| Item | Value used in this setup |
|---|---|
| Databricks workspace | `https://dbc-18519eb8-c00e.cloud.databricks.com` (Free Edition) |
| Unity Catalog catalog | `workspace` |
| GitHub repository | `https://github.com/akumarnalluri-ai/nrap-databricks-cicd` (public) |
| Local folder | `C:\Users\akuma\OneDrive\Desktop\Halvik` |
| Runner | Windows laptop, name `nrap-laptop`, label `databricks-deploy`, folder `C:\actions-runner` |
| Tools on runner | Git for Windows 2.53 (bash 5.2), jq 1.8.2, Databricks CLI v1.26.0 in `C:\tools` |

---

# Part A – Setup, step by step

## Phase 1 – Databricks

**Step 1 – Confirm the catalog name.** Databricks → **Catalog** in the left sidebar → the catalog list
shows `workspace` (plus `samples`, `system`). `databricks.yml` uses `catalog: workspace` for dev and test,
so nothing had to change. *If your catalog has another name, change `catalog:` under each target.*

**Step 2 – Create a personal access token (PAT).** Profile icon (top right) → **Settings** →
**Developer** → **Access tokens → Manage** → **Generate new token**, comment `github-cicd`, lifetime
90 days → copy the `dapi…` value into Notepad. It is shown only once and is never pasted into code or chat;
it goes only into GitHub environment secrets.

> One workspace is enough. DEV and TEST are separated inside it by bundle targets:
> schema `nrap_demo_dev` vs `nrap_demo_test`, job `nrap_demo_job_dev` vs `nrap_demo_job_test`,
> workspace folder `/Workspace/Shared/.bundle/nrap_cicd_demo/dev` vs `…/test`.

## Phase 2 – Local folder and GitHub repository

**Step 3 – Rename `_github` to `.github` and check Git.** The workflows were delivered in `_github`;
GitHub only reads `.github`.

```powershell
cd C:\Users\akuma\OneDrive\Desktop\Halvik
Rename-Item _github .github
Remove-Item .github\RENAME_THIS_FOLDER_TO_.github.txt
dir .github\workflows          # 5 workflow files
git --version                  # git version 2.53.0.windows.3
```

**Step 4 – Create an empty GitHub repository.** github.com → **+ → New repository** → name
`nrap-databricks-cicd`, **Public** (needed for environment approval rules on a free account), no README,
no .gitignore, no license → **Create repository** → copy the HTTPS URL.

*If GitHub shows "We detected unusual activity…": use a normal Chrome/Edge window (not an embedded
browser), close developer tools, turn off VPN, wait 10–15 minutes or switch network.*

**Step 5 – Push the code.**

```powershell
cd C:\Users\akuma\OneDrive\Desktop\Halvik
(Get-Content .github\CODEOWNERS) -replace '__REPLACE_DEFAULT_CODE_OWNER__','@akumarnalluri-ai' -replace '__REPLACE_DEVOPS_CODE_OWNER__','@akumarnalluri-ai' | Set-Content .github\CODEOWNERS
git init -b main
git config user.name "akumarnalluri-ai"
git config user.email "akumarnalluri-ai@users.noreply.github.com"
git add .
git commit -m "NRAP Databricks CI/CD - initial version"
git remote add origin https://github.com/akumarnalluri-ai/nrap-databricks-cicd.git
git push -u origin main
```

The first push opens a browser to authorize Git with GitHub. The push to `main` immediately triggered
**CI - Validate**: `static-checks` went green, `bundle-validate` waited/failed with
*"Waiting for a runner… Requested labels: self-hosted, databricks-deploy"* – expected, because no runner
existed yet.

## Phase 3 – GitHub environments, secrets and approval

**Step 6 – Environment `dev`.** Repo → **Settings → Environments** → `dev` (create if missing).
No required reviewers, deployment branches **No restriction**. Environment secrets:

| Secret | Value |
|---|---|
| `DATABRICKS_HOST` | `https://dbc-18519eb8-c00e.cloud.databricks.com` (no `?o=…`, no trailing `/`) |
| `DATABRICKS_TOKEN` | the `dapi…` token |

**Step 7 – Environment `test` (the approval gate).** **New environment** `test`:
- **Required reviewers** ✔ → add `akumarnalluri-ai`; **Prevent self-review** left unticked (single-person demo) → **Save protection rules**.
- **Deployment branches and tags** → **Selected branches and tags** → rule `main`.
- Same two secrets as `dev`.

## Phase 4 – Self-hosted runner on the Windows laptop

**Step 8a – Install tools.** `winget` was not available, so jq and the Databricks CLI were downloaded
from their GitHub releases into `C:\tools` and `C:\tools` was added to the user PATH:

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
New-Item -ItemType Directory -Force C:\tools | Out-Null
$jq = (Invoke-RestMethod https://api.github.com/repos/jqlang/jq/releases/latest).assets | Where-Object name -eq 'jq-windows-amd64.exe'
Invoke-WebRequest $jq.browser_download_url -OutFile C:\tools\jq.exe
$db = (Invoke-RestMethod https://api.github.com/repos/databricks/cli/releases/latest).assets | Where-Object name -like '*_windows_amd64.zip' | Select-Object -First 1
Invoke-WebRequest $db.browser_download_url -OutFile C:\tools\dbcli.zip
Expand-Archive C:\tools\dbcli.zip -DestinationPath C:\tools -Force
Remove-Item C:\tools\dbcli.zip
$userPath = [Environment]::GetEnvironmentVariable('Path','User')
if ($userPath -notlike '*C:\tools*') { [Environment]::SetEnvironmentVariable('Path', "$userPath;C:\tools", 'User') }
```

New PowerShell window → `jq --version` (1.8.2), `databricks --version` (v1.26.0),
`& "C:\Program Files\Git\bin\bash.exe" --version` (5.2.37).

Two Windows fixes were added to `scripts/ci/common.sh` and pushed (details in Part C):
strip carriage returns from `jq` output, and disable Git Bash path conversion.

**Step 8b – Register the runner.** Repo → **Settings → Actions → Runners → New self-hosted runner** →
**Windows / x64** → run GitHub's *Download* commands in `C:\actions-runner`, then its
`./config.cmd --url … --token …` line, answering:

| Prompt | Answer |
|---|---|
| Runner group | Enter (Default) |
| Runner name | `nrap-laptop` |
| Additional labels | `databricks-deploy` |
| Work folder | Enter (`_work`) |
| Run as service? | **N** (runs interactively under your account, so it sees `C:\tools` and Git Bash) |

Start it (keep this window open for the whole session):

```powershell
$env:Path = "C:\Program Files\Git\bin;C:\tools;" + $env:Path
.\run.cmd          # "Connected to GitHub" … "Listening for Jobs"
```

Git Bash is put **first** on PATH so `shell: bash` uses Git Bash and not `C:\Windows\System32\bash.exe`
(the WSL launcher). The Runners page showed `nrap-laptop` **Idle** with labels
`self-hosted, Windows, X64, databricks-deploy`.

## Phase 5 – Prove the pipeline

**Step 9 – Smoke test.** **Actions → CI - Validate → Run workflow** (main). Both jobs green:
`Authenticated as: <Databricks user>` and `Validation OK!` – runner, secrets, auth and bundle config all work.

**Step 10 – First release.**

```powershell
git pull
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0
```

The **Release** workflow ran (its run is named after the tagged commit's message) and created GitHub
Release **v1.0.0**.

**Step 11 – Deploy v1.0.0 to DEV.** **Actions → Deploy Databricks → Run workflow** → `main`, `dev`,
`v1.0.0`, run job ✔, auto-rollback ✔, reason. First attempt: deploy and job run succeeded but verification
failed with `Notebook missing: /Workspace/Shared/...` (Git Bash path conversion – Part C #3). After the fix
was pushed, the same deployment re-run passed. Evidence: job `nrap_demo_job_dev` tagged
`release_version: v1.0.0`, 3 green tasks, `workspace.nrap_demo_dev.customer_orders` with 5 rows.

**Step 12 – Promote v1.0.0 to TEST with approval.** Same workflow with `test`. The run paused with
*"Waiting for review: test needs approval"* → **Review deployments → test → Approve and deploy**.
Result: job `nrap_demo_job_test` (tags `environment: TEST`, `release_version: v1.0.0`), schema
`nrap_demo_test`, rows with `env_name = TEST` – same release, environment-specific configuration.

**Step 13 – Release v1.1.0.** Change: order 1006 added in `02_load_sample_data.py`; `expected_min_rows`
5 → 6 for dev and test in `databricks.yml`; CHANGELOG entry.

```powershell
git add .
git commit -m "v1.1.0: add order 1006, expect 6 rows"
git push
git tag -a v1.1.0 -m "Release v1.1.0"
git push origin v1.1.0
```

Deployed to DEV with version **`latest`** (log: `'latest' resolved to v1.1.0`, `auto-rollback target: v1.0.0`),
then to TEST with `v1.1.0` + approval → 6 rows stamped `v1.1.0`.

**Step 14 – Rollback TEST.** **Actions → Rollback Databricks** → `test`, version `previous`, reason →
approve. Log: `'previous' resolved to v1.0.0 (last successful version before v1.1.0)`. Result: job tag back
to `v1.0.0`, table back to 5 rows (order 1006 removed), `deployment_audit` shows PASS rows for
v1.0.0 → v1.1.0 → v1.0.0.

**Step 15 – Failed release with automatic rollback (optional).** A deliberately broken release
(`expected_min_rows: "100"`) is deployed to DEV; the validation task fails, the workflow redeploys the
previously live version and marks the run failed. See docs/08 §6 and the branch-policy note below.

> **Branch policy decision.** `config/dev.env` currently has `REQUIRE_TAG_ON_MAIN=false`, which lets DEV
> receive tags from unmerged branches. To keep `main` the single source of truth for every environment,
> set it to `true` (TEST/PROD already are). Then even a "bad release" demo goes through `main`
> (PR → tag → deploy → auto-rollback → revert PR → new tag).

---

# Part B – What happens inside each workflow

## B1. `ci-validate.yml` – "CI - Validate"

**Purpose:** catch mistakes before anything is released. It deploys nothing.

**Triggers:** pull request into `main`, push to `main`, or manual **Run workflow**.

### Job 1 – `static-checks` (GitHub-hosted `ubuntu-latest`; no Databricks access)

| Step | What it does | Fails when |
|---|---|---|
| Checkout | Clones the commit being tested | – |
| Python syntax check | `python3 -m py_compile src/notebooks/*.py` – compiles each notebook | A notebook has a syntax error |
| Shell syntax check | `bash -n` on every script in `scripts/ci` and `scripts/runner` – parses without running | A script has a syntax error |
| Line-ending guard | Searches `.sh .env .yml .py` for Windows CR characters | Any file has CRLF endings (they break bash on Linux) |

### Job 2 – `bundle-validate` (self-hosted runner, GitHub environment `dev`)

Runs only after `static-checks` passes **and** only for pushes, manual runs, or PRs from branches in this
same repository – a PR from someone's fork can never run code on your runner.

| Step | What it does |
|---|---|
| Checkout | Clones the commit |
| Check / install Databricks CLI | Uses the runner's CLI; installs it with `databricks/setup-cli` only if missing |
| Verify authentication (`check_auth.sh`) | Confirms `databricks`, `jq`, `git` exist; `DATABRICKS_HOST` is set; exactly one credential type is present; logs in with `databricks current-user me` |
| Bundle validate (dev) | `databricks bundle validate -t dev` – resolves variables, includes, paths and checks the job definition against the workspace |

Because the job uses `environment: dev`, it receives the `dev` secrets. That is also why the `dev`
environment must allow all branches (PR branches need those secrets for validation).

## B2. `release.yml` – "Release"

**Purpose:** turn a pushed version tag into a GitHub Release that people can see and select.

**Trigger:** push of a tag matching `v*.*.*` (e.g. `git push origin v1.1.0`).

| Step | What it does |
|---|---|
| Create GitHub Release | Calls the GitHub REST API `POST /repos/<repo>/releases` with `tag_name`, `name` = the tag and `generate_release_notes: true` (GitHub lists the commits/PRs since the previous release) |
| Response 201 | Release created; link written to the run summary |
| Response 422 | Release already exists (e.g. you created it in the GitHub UI) – logged as a notice, not an error |
| Anything else | Fails and prints the API response |

It needs `contents: write` permission (declared in the file) and runs on a GitHub-hosted runner.
The run is labelled with the tagged commit's message – that is why the v1.0.0 Release run was named
"Strip CRLF from jq output on Windows runners".

## B3. `_reusable-deploy.yml` – the deployment engine

**Purpose:** the single place where a Databricks deployment happens. It is never started directly –
`deploy-databricks.yml` (mode `deploy`) and `rollback-databricks.yml` (mode `rollback`) call it with
`uses: ./.github/workflows/_reusable-deploy.yml`, so deploys and rollbacks share identical checks.

### Inputs

| Input | Meaning |
|---|---|
| `environment` | `dev` / `test` (/ `prod`) – selects GitHub environment, `config/<env>.env` and bundle target |
| `version` | A tag (`v1.1.0`), `latest`, or `previous` |
| `mode` | `deploy` or `rollback` – label in logs and summary |
| `run_job` | Run the job after deploying (it contains the validation task) |
| `auto_rollback` | Restore the previously live version on failure |
| `reason` | Change ticket / reason, shown in the summary |

### Before any step runs

- **Concurrency** (in the caller): group `databricks-deploy-<env>` – only one deploy or rollback per
  environment at a time; a second one waits instead of cancelling the first.
- **Approval:** the job declares `environment: <env>`. If that GitHub environment has required reviewers
  (TEST), the job pauses until approved, and the environment's secrets are released to the runner only
  after approval. Rejecting ends the run with nothing touched.
- **Runner:** `runs-on` = repo variable `RUNNER_LABELS`, default `["self-hosted","databricks-deploy"]`.
- **Credentials:** `DATABRICKS_HOST`, `DATABRICKS_TOKEN` (or client ID/secret) are mapped from the
  environment's secrets into job environment variables, which the Databricks CLI reads automatically.

### Steps

| # | Step | What it does | On failure |
|---|---|---|---|
| 1 | Checkout pipeline code | Clones the **workflow branch (main)** into `pipeline/` with full history and all tags | – |
| 2 | Prepare log folder | Sets `LOG_DIR` (in the runner temp folder, unique per run) and `CI_SCRIPTS` | – |
| 3 | Load environment configuration | `load_env_config.sh <env>` reads `config/<env>.env` and exports `BUNDLE_TARGET`, `JOB_RESOURCE_KEY`, `JOB_NAME`, `RUN_JOB_AFTER_DEPLOY`, `AUTO_ROLLBACK_ON_FAILURE`, `REQUIRE_TAG_ON_MAIN`, `MAIN_BRANCH` | Missing file / bad line / missing key |
| 4–5 | Check / install Databricks CLI | Uses the runner's CLI, installs only if missing | – |
| 6 | Verify tools and authentication | `check_auth.sh` (same as CI); records `DEPLOY_IDENTITY` | No/duplicate credentials, login fails |
| 7 | Resolve and verify release version | `resolve_version.sh`: reads the version currently deployed (the job's `release_version` tag); turns `latest` into the highest `vX.Y.Z` tag, `previous` into the most recent version that ran **successfully** before the live one (from the job's run history), or uses the explicit tag; checks the tag exists; if `REQUIRE_TAG_ON_MAIN=true`, checks its commit is on `origin/main`. Outputs `version`, `commit`, `previous_version` (= the live version, used for auto-rollback) | Tag missing (lists the latest 15 tags), tag not on main |
| 8 | Checkout release | Clones **the selected tag** into `release/` – this is the code that gets deployed | – |
| 9 | Validate and deploy bundle | `deploy_bundle.sh`: `databricks bundle validate`, `databricks bundle deploy --auto-approve`, `databricks bundle summary`, all with `--var="release_version=<tag>"` so the job is tagged and parameterised with the version | Invalid bundle, permission or lock error |
| 10 | Run job | `run_job.sh`: `databricks bundle run <job>` and **waits**; tasks 1→2→3 run on serverless; task 3 performs 7 data checks and writes `deployment_audit`. Captures the run URL | Any task fails (e.g. validation) |
| 11 | Verify deployment in workspace | `verify_deployment.sh`: job exists; its `release_version` tag equals the version; every notebook referenced by the job exists; latest completed run is SUCCESS and ran this version. Outputs job URL | Any check fails |
| 12 | Checkout previous version (auto-rollback) | Runs **only if** something failed **after** deploy started, auto-rollback is enabled (input and config) and a different version was live before. Clones that tag into `rollback/` | – |
| 13 | Auto-rollback | Deploys the previous tag, runs the job, verifies it. The run stays **failed** so the bad release is visible | Rollback itself fails → summary says "manual action required" |
| 14 | Write deployment summary *(always)* | `write_summary.sh` builds the table on the run page: result, requested/deployed version, commit, previously live version, rollback outcome, job and run links, GitHub actor, Databricks identity, reason, runner | – |
| 15 | Upload execution logs *(always)* | Uploads `LOG_DIR` as artifact `databricks-<env>-<version>-run<id>-<attempt>` (90 days): `pipeline.log`, `deploy.log`, `run.log`, `deployed_job_<name>.json`, rollback logs | – |

### Where each kind of configuration comes from in one run

```
environment=test ─┬─ GitHub environment "test"   → approval + DATABRICKS_HOST/TOKEN
                  ├─ config/test.env             → BUNDLE_TARGET=test, JOB_NAME, REQUIRE_TAG_ON_MAIN=true …
                  └─ databricks.yml targets.test → catalog, schema nrap_demo_test, env TEST, root_path
                                                   └─ job parameters → notebook widgets at run time
version=v1.1.0 ───── release/ checkout           → the notebooks + job definition that get deployed
```

---

# Part C – Problems we hit and how they were fixed

| # | Symptom | Cause | Fix |
|---|---|---|---|
| 1 | GitHub "We detected unusual activity" page | GitHub bot protection (embedded browser, VPN, rapid clicks) | Normal browser window, no dev tools/VPN, wait or switch network |
| 2 | `winget` not recognised | App Installer not present on the laptop | Downloaded jq and Databricks CLI from GitHub releases into `C:\tools` (Step 8a) |
| 3 | `[FAIL] Notebook missing: /Workspace/Shared/...` although the notebooks existed | Git Bash (MSYS) rewrites arguments starting with `/` into Windows paths before calling `databricks.exe` | `common.sh`: `export MSYS_NO_PATHCONV=1` and `MSYS2_ARG_CONV_EXCL="*"` (no effect on Linux) |
| 4 | (prevented) corrupted job IDs/versions on Windows | Native `jq.exe` can emit CRLF line endings | `common.sh`: `jq() { command jq "$@" \| tr -d '\r'; }` |
| 5 | `git commit` said "nothing to commit" after a file was updated | OneDrive synced an older copy over the new file | Re-wrote the file, checked its size, committed immediately. Tip: keep repos outside OneDrive, or pause OneDrive sync while working |
| 6 | `bundle-validate` red right after the first push | No runner with label `databricks-deploy` yet | Expected; re-ran CI - Validate after registering the runner |
| 7 | Annotation "Node.js 20 is deprecated…" | GitHub notice for `actions/checkout@v4` / `upload-artifact@v4` | Informational only – GitHub already runs them on Node 24 |

## Daily start-up checklist (laptop runner)

Full details, desktop shortcut and troubleshooting: **docs/09_RUNNER_START_STOP.md**.

1. Open PowerShell → `cd C:\actions-runner`
2. `$env:Path = "C:\Program Files\Git\bin;C:\tools;" + $env:Path`
3. `.\run.cmd` → wait for **Listening for Jobs**, keep the window open
4. Check **Settings → Actions → Runners** shows `nrap-laptop` **Idle**
5. Renew the Databricks token before its 90-day expiry and update `DATABRICKS_TOKEN` in both environments
