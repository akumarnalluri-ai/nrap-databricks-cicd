# 03 – GitHub Setup (environments, secrets, approvals, protection)

One-time setup by a repository admin.

## 1. Push the code

```bash
cd C:\Users\akuma\OneDrive\Desktop\Halvik        # or wherever the folder is
git init -b main
git add .
git commit -m "NRAP Databricks CI/CD v1.0.0"
git remote add origin https://github.com/<org-or-user>/<repo>.git
git push -u origin main
```

`.gitattributes` makes Git store `.sh/.yml/.env/.py` with LF endings even though the folder is on Windows.
If you committed before `.gitattributes` existed, run `git add --renormalize . && git commit -m "normalize line endings"`.

## 2. Actions settings

*Settings → Actions → General*

- **Actions permissions:** allow `actions/*` and `databricks/*` (or "Allow all actions").
  Used actions: `actions/checkout@v4`, `actions/upload-artifact@v4`, `databricks/setup-cli@main`.
- **Workflow permissions:** "Read repository contents" is enough (the release workflow requests `contents: write` itself).
- **Fork pull request workflows:** "Require approval for all outside collaborators" – protects the self-hosted runner.

## 3. Environments (this is where approvals live)

*Settings → Environments → New environment*

| Environment | Required reviewers | Prevent self-review | Deployment branches and tags | Secrets |
|---|---|---|---|---|
| `dev` | none | – | **No restriction** (lets the PR `bundle validate` job run) – or `main` only if you skip PR validation | `DATABRICKS_HOST`, `DATABRICKS_TOKEN` (or SP pair) |
| `test` | 1–2 people/teams, e.g. QA lead + release manager | ✔ in real use, ✘ for a solo demo | **Selected branches: `main`** | TEST credentials |
| `prod` (later) | Change Advisory / release manager | ✔ | `main` | PROD credentials |

How it behaves: when a run targets `test`, the job shows **"Waiting for review"**. Reviewers get a
notification, open the run, click **Review deployments → Approve and deploy** (or Reject) and can leave a
comment. Secrets of `test` are only handed to the runner after approval. Every approval is recorded in the
run history and under *Environments → test → deployment history* – that is your audit evidence for DOT policy.

Optional: **Wait timer** (e.g. 15 min cooling-off) on `prod`.

> **Plan note:** environment protection rules (required reviewers) are available on public repositories on
> every plan, but on private repositories only on paid GitHub plans. For the free-account demo either make the
> demo repository public (no secrets are in the code) or use an organization with a paid plan. Check your
> plan's documentation if the "Required reviewers" checkbox is missing.

### Secrets per environment

*Environments → `dev` → Environment secrets → Add secret*

- `DATABRICKS_HOST` = `https://<your-workspace>.cloud.databricks.com` (Azure: `https://adb-<id>.<n>.azuredatabricks.net`)
- `DATABRICKS_TOKEN` = personal access token (Databricks: *User menu → Settings → Developer → Access tokens → Generate*)
  **or** `DATABRICKS_CLIENT_ID` + `DATABRICKS_CLIENT_SECRET` for a service principal (*Workspace settings → Identity and access → Service principals → Secrets*).

Repeat for `test`. In the free demo both can point to the same workspace; the bundle targets keep the
objects apart (`nrap_demo_dev` vs `nrap_demo_test`).

## 4. Repository variables (only if needed)

*Settings → Secrets and variables → Actions → Variables*

| Variable | When |
|---|---|
| `RUNNER_LABELS` | Your runner uses different labels. Value is a JSON array: `["self-hosted","linux","nrap-deploy"]` |
| `CI_RUNNER_LABELS` | GitHub-hosted runners are disabled in your org. Same JSON format. |

## 5. Protect `main` and release tags

*Settings → Rules → Rulesets* (or *Branches → Branch protection rules*)

- **Branch ruleset for `main`:** require a pull request, 1+ approval, "Require review from Code Owners",
  required status checks `static-checks` and `bundle-validate`, block force pushes.
- **Tag ruleset for `v*`:** restrict creation/update/deletion to release managers, block updates and deletions
  – a tag that was approved for TEST can then never silently change.

## 6. Who can run deployments

`workflow_dispatch` can only be started by users with **write** access. Combined with required reviewers on
`test`/`prod`, a developer can *request* a TEST deployment but cannot complete it without approval.
