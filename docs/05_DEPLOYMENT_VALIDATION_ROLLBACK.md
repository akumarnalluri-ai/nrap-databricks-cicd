# 05 – Deployment, Validation and Rollback Runbook

## 1. Release process

1. Merge changes to `main` through a PR (CI - Validate must pass).
2. Update `CHANGELOG.md`, then tag the release from `main`:
   ```bash
   git checkout main && git pull
   git tag -a v1.1.0 -m "Release v1.1.0"
   git push origin v1.1.0
   ```
   (or *GitHub → Releases → Draft a new release → Choose a tag `v1.1.0` → target `main` → Publish*).
3. The **Release** workflow creates the GitHub Release automatically for `vX.Y.Z` tags.

Versioning: `vMAJOR.MINOR.PATCH`. `latest` always means the highest such tag (pre-release tags like
`v1.2.0-rc1` can still be deployed by typing them explicitly, but are never picked by `latest`).

## 2. Deploy a version

*Actions → **Deploy Databricks** → Run workflow* (branch: `main`)

| Input | Meaning |
|---|---|
| environment | `dev` or `test` |
| version | `v1.1.0` or `latest` |
| run_job | Run the job after deploy (recommended – it contains the data validation) |
| auto_rollback | Restore the previously live version if this one fails |
| reason | Change ticket / reason – recorded in the summary |

Promotion path: deploy to **dev** → check → deploy the **same tag** to **test** → reviewer approves.

## 3. Approval (TEST / PROD)

The run pauses with *"Waiting for review: test needs approval"*. A required reviewer opens the run →
**Review deployments** → tick `test` → comment → **Approve and deploy**. Rejecting ends the run with nothing
deployed. Pending approvals expire after 30 days.

## 4. What is validated

| Stage | Check | Fails the run when |
|---|---|---|
| Pre-deploy | `check_auth.sh` | Tool missing, no/duplicate credentials, login fails |
| Pre-deploy | `resolve_version.sh` | Tag doesn't exist; (TEST) tag not on `main` |
| Pre-deploy | `databricks bundle validate` | Invalid bundle config / unresolved variables / permissions |
| Deploy | `databricks bundle deploy` | Upload or job create/update fails, deploy lock held |
| Post-deploy (Databricks) | Job task `03_validate_deployment` – 7 data checks written to `deployment_audit` | Any check FAIL |
| Post-deploy (workspace) | `verify_deployment.sh` | Job missing, `release_version` tag ≠ deployed version, notebook missing, latest run not SUCCESS or ran a different version |

Query the audit trail in Databricks:

```sql
SELECT env_name, release_version, job_run_id, check_name, status, details, checked_at
FROM workspace.nrap_demo_test.deployment_audit
ORDER BY checked_at DESC;
```

## 5. Execution logs

Every run (success or failure) produces:

- **Run summary** (top of the run page): result, requested/deployed version, commit, version live before,
  rollback outcome, Databricks job link, job run link, GitHub actor, Databricks identity, reason, runner.
- **Artifact** `databricks-<env>-<version>-run<id>-<attempt>` (kept 90 days) containing
  `pipeline.log` (all steps, timestamped), `deploy.log` (validate/deploy/summary output), `run.log`
  (job run output), `deployed_job_<name>.json` (job definition after deploy), and `rollback*.log` if a rollback happened.
- **Annotations**: every `::error::` / `::warning::` appears on the run page.
- **Databricks**: job run history (task output, Spark logs) and the `deployment_audit` table.

## 6. Error handling and automatic rollback

If anything fails **after** the deploy step started (deploy, job run, verification) and
`auto_rollback=true` and `AUTO_ROLLBACK_ON_FAILURE=true` and a different version was live before:

1. The previous tag is checked out into `rollback/`.
2. It is deployed, the job is run, and the deployment is verified.
3. The run is still marked **failed** (so the bad release is visible); the summary says
   *"rolled back to vX"* or *"auto-rollback FAILED – manual action required"*.

No rollback happens for failures **before** deploy (bad tag, auth) because nothing changed.

## 7. Manual rollback / redeploy a previously approved version

*Actions → **Rollback Databricks** → Run workflow*

| Input | Example |
|---|---|
| environment | `test` |
| version | `previous` – the most recent version that ran **successfully** in that environment before the one live now (read from the job's successful run history), or an explicit tag e.g. `v1.0.0` |
| reason | `INC0045678 – v1.1.0 load issue` (required) |

Rollback goes through the same approval, validation, verification and logging. Alternatively use
*Deploy Databricks* with the old tag – the effect is identical.

Note on data: rollback restores **code and job definitions**. In this demo the job's MERGE makes the table
match the restored release's dataset (updates, inserts, and deletes rows that release doesn't contain), so data
follows the rollback too. For real pipelines, use Delta
`RESTORE TABLE … TO VERSION AS OF …` if data must be reverted.

## 8. Common failures

| Message | Cause / fix |
|---|---|
| `Tag 'vX' does not exist` | Typo or tag not pushed (`git push origin vX`). The log lists the 15 latest tags. |
| `is not on origin/main` | Tag created on a feature branch – re-tag from `main`. |
| `deploy lock acquired by …` | A previous run was cancelled mid-deploy. Re-run with `FORCE_LOCK=true` (add it to `config/<env>.env` temporarily) or wait for the lock to expire. |
| `Both a token and service principal credentials are set` | Remove one method from the GitHub environment secrets. |
| `PERMISSION_DENIED … CREATE SCHEMA` | Grant the deploy identity `USE CATALOG` + `CREATE SCHEMA` on the catalog, or pre-create the schema. |
| Validation `release_version_stamped` FAIL | Rows not reloaded by this release – check task 2 output in the job run. |
| `Could not find an earlier successfully-validated version` | No successful run with another version in the job's run history (runs are kept 60 days) – type the version explicitly. |

## 9. Enabling PROD

1. Fill `targets.prod` in `databricks.yml` (host, catalog, schema, `run_as`).
2. Review `config/prod.env`.
3. Uncomment `- prod` in `deploy-databricks.yml` and `rollback-databricks.yml`.
4. Create GitHub environment `prod`: required reviewers (prevent self-review), `main` only, PROD secrets.
