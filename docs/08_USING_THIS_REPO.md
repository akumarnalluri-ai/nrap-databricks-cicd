# 08 – Using This Repository (guide for other people)

This repository deploys Databricks notebooks and jobs from GitHub to DEV and TEST with GitHub Actions and
Databricks Asset Bundles. This guide is for anyone who receives the link:
`https://github.com/akumarnalluri-ai/nrap-databricks-cicd`.

**Pick your path:**

| You want to… | Follow |
|---|---|
| Work **in this repository** with the owner (make changes, deploy, approve) | **Path A – Collaborator** |
| Run the whole thing **in your own GitHub account and your own Databricks workspace** | **Path B – Your own copy** |

> **Security notes.** No secrets are stored in the code. Workspace URLs and tokens live only in GitHub
> *environment secrets*, which are never copied to forks or clones and are never visible after saving –
> not even to collaborators. Pull requests from forks cannot use the secrets or the self-hosted runner.
> Never commit a token, a `.databrickscfg` file or an `.env` file containing credentials.

---

## What is in the repository (1-minute tour)

| Path | Contents |
|---|---|
| `databricks.yml` | Asset Bundle: variables and the `dev` / `test` / `prod` targets (catalog, schema, workspace folder) |
| `resources/nrap_demo_job.yml` | The Databricks job: 3 notebook tasks, parameters, version tags |
| `src/notebooks/` | `01_setup_schema_table`, `02_load_sample_data`, `03_validate_deployment` |
| `config/<env>.env` | Non-secret pipeline settings per environment |
| `.github/workflows/` | `deploy-databricks`, `rollback-databricks`, `_reusable-deploy`, `ci-validate`, `release` |
| `scripts/ci/` | Bash steps the workflows run |
| `scripts/runner/` | Self-hosted runner install scripts (Linux, Windows) and a health check |
| `docs/` | All documentation – `07_SETUP_WALKTHROUGH.md` explains every workflow step |

---

# Path A – Collaborator on this repository

The owner has already configured the Databricks workspace, the GitHub environments, the secrets and a runner.
You do **not** set up any secrets.

### A1. Get access (owner does this)
1. Owner: **Settings → Collaborators → Add people** → your GitHub username → role **Write**.
2. Owner (if you should approve TEST deployments): **Settings → Environments → test → Required reviewers** → add you.
   For real separation of duties the owner ticks **Prevent self-review**, so nobody approves their own deployment.
3. Accept the e-mail invitation.

### A2. Clone and make a change
```bash
git clone https://github.com/akumarnalluri-ai/nrap-databricks-cicd.git
cd nrap-databricks-cicd
git checkout -b feature/my-change
# edit notebooks / databricks.yml / resources ...
git add .
git commit -m "Describe the change"
git push -u origin feature/my-change
```
Open a **Pull request** into `main`. **CI - Validate** runs automatically (syntax checks + `bundle validate`).
After review and merge, a release manager tags it:
```bash
git checkout main && git pull
git tag -a v1.2.0 -m "Release v1.2.0"
git push origin v1.2.0          # Release workflow creates GitHub Release v1.2.0
```

### A3. Deploy, approve, roll back
- **Deploy:** **Actions → Deploy Databricks → Run workflow** → environment `dev` or `test`, version (`v1.2.0` or `latest`), reason.
- **Approve (TEST):** open the waiting run → **Review deployments** → tick `test` → **Approve and deploy**.
- **Roll back:** **Actions → Rollback Databricks** → environment, version `previous` (or a tag), reason.

### A4. The runner must be online
Deployments run on a self-hosted runner with label `databricks-deploy`. If a run says
*"Waiting for a runner"*, the runner machine is off. Either ask the owner to start it, or register your own
machine as an additional runner (owner generates the token – see **B5**). Several runners with the same
label are fine; GitHub uses whichever is free.

---

# Path B – Your own copy (your GitHub + your Databricks)

About 45 minutes. You need: a GitHub account, a Databricks workspace (Free Edition works), and a Windows
or Linux machine for the runner.

### B1. Copy the code into a new repository of your own
1. On GitHub create an **empty** repository (no README/.gitignore/license), e.g. `nrap-databricks-cicd`.
   Make it **Public** if you are on a free GitHub plan – required reviewers on environments need a public
   repository or a paid plan.
2. Copy the code including the release tags:
   ```bash
   git clone https://github.com/akumarnalluri-ai/nrap-databricks-cicd.git
   cd nrap-databricks-cicd
   git remote set-url origin https://github.com/<YOUR-USERNAME>/nrap-databricks-cicd.git
   git push -u origin main
   git push origin --tags
   ```
   *(Forking also works, but forks have Actions disabled until you enable them under the **Actions** tab, and
   environments/secrets are never copied – you still do B3.)*

### B2. Adjust the files for your setup
| File | Change | When |
|---|---|---|
| `.github/CODEOWNERS` | Replace `@akumarnalluri-ai` with your username or team | Always |
| `databricks.yml` → `targets.dev/test.variables.catalog` | Your catalog name (Free Edition: `workspace`) | If your catalog differs |
| `databricks.yml` → `schema` per target | Other schema names | Optional |
| `config/dev.env` → `REQUIRE_TAG_ON_MAIN` | `true` to allow only releases from `main` in DEV as well | Recommended for regulated projects |

Commit and push. Full list of every setting: **docs/02_PLACEHOLDERS_GUIDE.md**.

### B3. Databricks token and GitHub environments + secrets
1. **Databricks token:** profile icon → **Settings → Developer → Access tokens → Manage → Generate new token**
   (comment `github-cicd`, 90 days). Copy the `dapi…` value.
2. **GitHub → your repo → Settings → Environments:**

| Environment | Protection | Deployment branches | Secrets |
|---|---|---|---|
| `dev` | none | No restriction | `DATABRICKS_HOST`, `DATABRICKS_TOKEN` |
| `test` | **Required reviewers** = you or your approvers | Selected → `main` | `DATABRICKS_HOST`, `DATABRICKS_TOKEN` |

**Secret values:**

| Secret | Value | Example |
|---|---|---|
| `DATABRICKS_HOST` | Workspace URL only – no `?o=…`, no trailing `/` | `https://dbc-1234abcd-5678.cloud.databricks.com` |
| `DATABRICKS_TOKEN` | Personal access token | `dapi…` |

**Service principal instead of a token** (recommended for real projects): leave `DATABRICKS_TOKEN` out and add
`DATABRICKS_CLIENT_ID` + `DATABRICKS_CLIENT_SECRET` (Databricks → **Settings → Identity and access →
Service principals** → create → **Secrets → Generate**). Grant it `USE CATALOG`, `USE SCHEMA`,
`CREATE SCHEMA`/`CREATE TABLE`, `MODIFY`, `SELECT` on the catalog/schema and access to the
`/Workspace/Shared/.bundle` folder. Use **one method per environment** – the pipeline stops if both are set.

Separate workspaces per environment? Put each environment's own URL and credentials in its secrets, and
optionally uncomment `host:` under each target in `databricks.yml` to pin it.

### B4. Install the tools on the runner machine
- **Linux VM:** `sudo GITHUB_URL=… RUNNER_TOKEN=… RUNNER_LABELS=databricks-deploy bash scripts/runner/setup-runner-linux.sh`
  (installs everything and registers the runner as a service – see docs/04).
- **Windows:** needs Git for Windows (provides bash), jq and Databricks CLI. With winget, run
  `winget install --id Git.Git -e`, `winget install --id jqlang.jq -e` and
  `winget install --id Databricks.DatabricksCLI -e`. Without winget, use the download block in
  **docs/07 Step 8a**, which installs jq and the CLI into `C:\tools`.

### B5. Register the runner
GitHub → your repo → **Settings → Actions → Runners → New self-hosted runner** → pick OS → run the *Download*
and *Configure* commands GitHub shows (token valid 1 hour). Answer: runner name of your choice,
**additional labels: `databricks-deploy`**, run as service **N** on Windows (or Y on a Linux VM).
Start on Windows with:
```powershell
cd C:\actions-runner
$env:Path = "C:\Program Files\Git\bin;C:\tools;" + $env:Path
.\run.cmd
```
The Runners page should show it **Idle**. Different label? Set repository variable
`RUNNER_LABELS` = `["self-hosted","<your-label>"]` (**Settings → Secrets and variables → Actions → Variables**).

### B6. Test and deploy
1. **Actions → CI - Validate → Run workflow** → both jobs green (`Authenticated as …`, `Validation OK!`).
2. **Actions → Deploy Databricks** → `dev`, `latest` → green. Check Databricks: job `nrap_demo_job_dev`,
   table `<catalog>.nrap_demo_dev.customer_orders`.
3. Same with `test` → approve → job `nrap_demo_job_test`, schema `nrap_demo_test`.
4. **Actions → Rollback Databricks** → `test`, `previous` → approve → previous version restored.

The step-by-step demo with evidence to capture is in **docs/06_DEMO_RUNBOOK.md**.

---

## Everyday rules for everyone
1. All changes reach `main` through a pull request; CI - Validate must pass.
2. Only tags `vMAJOR.MINOR.PATCH` cut from `main` are releases. Never move or reuse a tag – make a new one.
3. Deploy the **same tag** to DEV first, then TEST.
4. Always fill in **reason** with a change/incident ticket – it is recorded in the run summary.
5. If a deployment fails, read the run summary and the attached log artifact first; auto-rollback has
   usually already restored the previous version.

## Quick troubleshooting
| Message | Fix |
|---|---|
| `Waiting for a runner … databricks-deploy` | Start the runner (`.\run.cmd`) or check `RUNNER_LABELS` |
| `No Databricks credentials found` | Secrets missing on that GitHub **environment** (not repository secrets) |
| `Authentication … failed` | Wrong host (remove `?o=…`) or expired token |
| `Tag 'vX' does not exist` | `git push origin vX` |
| `is not on origin/main` | Tag was created on a branch – tag a commit on `main` |
| Notebook missing / odd paths on Windows | Make sure `scripts/ci/common.sh` contains `MSYS_NO_PATHCONV=1` (included in this repo) |

More: docs/05_DEPLOYMENT_VALIDATION_ROLLBACK.md §8 and docs/07 Part C.
