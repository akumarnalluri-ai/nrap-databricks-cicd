@echo off
REM ============================================================================
REM start-runner-windows.cmd - start the GitHub Actions runner on a Windows laptop
REM with Git Bash and C:\tools (databricks.exe, jq.exe) on the PATH.
REM Copy to C:\actions-runner\start-runner.cmd (see docs\09_RUNNER_START_STOP.md).
REM ============================================================================
set "PATH=C:\Program Files\Git\bin;C:\tools;%PATH%"
cd /d C:\actions-runner
call run.cmd
pause
