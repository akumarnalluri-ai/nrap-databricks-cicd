# 09 – Starting and Stopping the Windows Laptop Runner

The self-hosted runner `nrap-laptop` (label `databricks-deploy`) is registered once and stays registered.
Its configuration lives in `C:\actions-runner`. Closing PowerShell only **stops** it – you never need to
re-register; just start it again.

## 1. Start the runner (manual)

1. Open **PowerShell**.
2. Run:
   ```powershell
   cd C:\actions-runner
   $env:Path = "C:\Program Files\Git\bin;C:\tools;" + $env:Path
   .\run.cmd
   ```
3. Wait for **"√ Connected to GitHub"** and **"Listening for Jobs"**. Keep the window open.
4. Check **GitHub → repo → Settings → Actions → Runners**: `nrap-laptop` shows **Idle**.

**Why the `$env:Path` line matters**

| Path entry | Needed for |
|---|---|
| `C:\Program Files\Git\bin` (first) | `shell: bash` must use Git Bash, not `C:\Windows\System32\bash.exe` (the WSL launcher) |
| `C:\tools` | `databricks.exe` and `jq.exe` used by every deployment step |

Without it, jobs fail with errors such as `'databricks' is not installed on this runner` or bash errors.

## 2. Start the runner with a double-click (one-time setup)

The repository includes `scripts/runner/start-runner-windows.cmd`, which sets the PATH and starts the
runner. Copy it next to the runner and create a desktop shortcut – run once in PowerShell from the repo folder:

```powershell
cd C:\Users\akuma\OneDrive\Desktop\Halvik
Copy-Item scripts\runner\start-runner-windows.cmd C:\actions-runner\start-runner.cmd -Force
$desktop = [Environment]::GetFolderPath('Desktop')
$s = (New-Object -ComObject WScript.Shell).CreateShortcut("$desktop\Start GitHub Runner.lnk")
$s.TargetPath = "C:\actions-runner\start-runner.cmd"
$s.WorkingDirectory = "C:\actions-runner"
$s.Save()
```

From then on: double-click **Start GitHub Runner** on the desktop.

## 3. Stop the runner

- Press **Ctrl + C** in the runner window, or close the window.
- GitHub shows the runner as **Offline**.
- Avoid stopping it while a job is running – the job fails and a deploy lock may remain in Databricks
  (see docs/05 §8, `FORCE_LOCK`).

## 4. What happens while it is off

- Deploy, rollback and `bundle-validate` jobs show **"Waiting for a runner to pick up this job"**.
- They start automatically as soon as the runner comes back online.
- A job that waits too long (GitHub's queue limit is about 24 hours) is cancelled – just run the workflow again.
- `static-checks` and `Release` are unaffected (they use GitHub-hosted runners).

## 5. Common problems

| Symptom | Fix |
|---|---|
| Runner shows **Offline** after starting | Check internet/VPN; look at the last lines in the runner window; restart `run.cmd` |
| `'databricks' is not installed on this runner` | The PATH line was skipped – stop and start again with step 1 |
| `Runner registration has been deleted` / auth errors | The runner was removed in GitHub. Delete `C:\actions-runner\.runner` and `.credentials`, get a new token (**Settings → Actions → Runners → New self-hosted runner**) and run `config.cmd` again |
| Laptop went to sleep mid-job | Re-run the workflow; keep the laptop awake during deployments |
| Runner version is old | It updates itself automatically when GitHub releases a new version – let it restart |

## 6. Service mode vs. manual mode

The laptop runner runs **manually** (registered with "run as service = N") because a Windows service runs
under a different account that does not see your user PATH (`C:\tools`). For an always-on runner use a
dedicated VM: Linux with `scripts/runner/setup-runner-linux.sh` (installs a systemd service) or Windows
with `scripts/runner/setup-runner-windows.ps1` (adds the tools to the machine PATH) – see docs/04.
