# 04 – Self-Hosted Runner Setup (VM)

All jobs that talk to Databricks run on a designated VM registered as a GitHub Actions self-hosted runner
with the label **`databricks-deploy`**.

## 1. VM requirements

| Item | Minimum |
|---|---|
| OS | Ubuntu 20.04+/RHEL 8+ (recommended) or Windows Server 2019+ |
| Size | 2 vCPU, 4 GB RAM, 20 GB disk |
| Outbound HTTPS 443 | `github.com`, `api.github.com`, `*.actions.githubusercontent.com`, `objects.githubusercontent.com`, `raw.githubusercontent.com` (CLI install), your Databricks workspace URL(s) |
| Inbound | none (the runner polls GitHub) |
| Software (installed by the scripts) | git, jq, curl, python3, Databricks CLI ≥ 0.218, GitHub runner; Windows also Git for Windows (bash) |

For the free demo your own laptop or any cloud VM works.

## 2. Get a registration token

GitHub → repository (or organization) → *Settings → Actions → Runners → New self-hosted runner*.
Pick the OS; copy the value after `--token` (valid **1 hour**). For many repositories register the runner at
**organization** level and assign it to a runner group allowed for this repo.

## 3a. Linux install

```bash
# copy scripts/runner/setup-runner-linux.sh to the VM, then:
sudo GITHUB_URL="https://github.com/<org>/<repo>" \
     RUNNER_TOKEN="<token>" \
     RUNNER_NAME="nrap-deploy-vm-01" \
     RUNNER_LABELS="databricks-deploy" \
     bash setup-runner-linux.sh
```

Optional: `HTTPS_PROXY=http://proxy.agency.gov:8080 NO_PROXY=169.254.169.254` (written to the runner's `.env`),
`RUNNER_VERSION=2.321.0` to pin, `RUNNER_USER`, `RUNNER_DIR`, `RUNNER_GROUP`.

What it does: installs packages → creates user `ghrunner` → downloads the latest runner → registers it with
your labels → installs and starts it as a systemd service → installs Databricks CLI → prints versions.

Service control: `cd /opt/actions-runner && sudo ./svc.sh status|stop|start`.
Logs: `/opt/actions-runner/_diag/`.

## 3b. Windows install

Elevated PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\runner\setup-runner-windows.ps1 `
   -GitHubUrl "https://github.com/<org>/<repo>" `
   -RunnerToken "<token>" `
   -RunnerName "nrap-deploy-win-01" `
   -RunnerLabels "databricks-deploy"
```

Installs Git for Windows, jq and Databricks CLI with winget, registers the runner as a Windows service and
adds `C:\Program Files\Git\bin` to the machine PATH so `shell: bash` works.

## 4. Verify

1. GitHub → *Settings → Actions → Runners*: runner is **Idle** with labels `self-hosted`, `databricks-deploy`.
2. On the VM, as the runner user:
   ```bash
   DATABRICKS_HOST=https://<workspace> DATABRICKS_TOKEN=<token> bash scripts/runner/check-runner-prereqs.sh
   ```
   All lines should be `[OK]`. (Run without the variables to skip the Databricks login test.)
3. *Actions → CI - Validate → Run workflow*: the `bundle-validate` job should be picked up by your runner.

## 5. Custom labels

If you register with other labels (e.g. `nrap-deploy`), set repository variable
`RUNNER_LABELS` = `["self-hosted","nrap-deploy"]`. No workflow edits needed.

## 6. Hardening (production VM)

- Dedicated, non-admin service account; VM used only for deployments.
- Do not store Databricks credentials on the VM – they come from GitHub environment secrets per run.
- Separate runners (or runner groups) per environment if policy requires network isolation of PROD.
- Keep the runner auto-updating (default) or patch monthly; pin the Databricks CLI version and update deliberately.
- Restrict the runner group to this repository; never allow fork PRs to run on it (already guarded in `ci-validate.yml`).
- Consider ephemeral runners (`--ephemeral`) re-created per job for the highest isolation.

## 7. Troubleshooting

| Symptom | Fix |
|---|---|
| Job stuck "Waiting for a runner" | Runner offline, or labels don't match → check *Runners* page and `RUNNER_LABELS`. |
| `'databricks' is not installed` | CLI not on the service user's PATH. Re-run the CLI install or restart the service after install. |
| `$'\r': command not found` | CRLF line endings – see docs/03 §1 (`git add --renormalize .`). |
| TLS / proxy errors | Set `HTTPS_PROXY` in the runner `.env` and restart the service; add the agency CA to the OS trust store. |
| `bash: not found` on Windows | Git for Windows missing or not on the service PATH; restart the service. |
