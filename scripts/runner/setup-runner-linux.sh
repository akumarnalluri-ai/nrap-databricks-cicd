#!/usr/bin/env bash
# =============================================================================
# setup-runner-linux.sh - install a GitHub Actions self-hosted runner on a
# Linux VM (Ubuntu 20.04+/RHEL 8+) as a service, plus the deployment tools
# (Databricks CLI, jq, git, python3).
#
# Usage (run as root / with sudo on the VM):
#   sudo GITHUB_URL="https://github.com/<org>/<repo>" \
#        RUNNER_TOKEN="<registration token>" \
#        RUNNER_NAME="nrap-deploy-vm-01" \
#        RUNNER_LABELS="databricks-deploy,linux" \
#        bash setup-runner-linux.sh
#
# RUNNER_TOKEN: GitHub -> repo (or org) Settings -> Actions -> Runners ->
#               New self-hosted runner -> copy the token after "--token".
#               It expires after 1 hour.
#
# Optional env:
#   RUNNER_USER   (default: ghrunner)        service account that runs jobs
#   RUNNER_DIR    (default: /opt/actions-runner)
#   RUNNER_VERSION(default: latest)          e.g. 2.321.0
#   RUNNER_GROUP  (default: Default)         org runner group
#   HTTPS_PROXY / NO_PROXY                   corporate proxy, written to runner .env
# =============================================================================
set -Eeuo pipefail

GITHUB_URL="${GITHUB_URL:?Set GITHUB_URL, e.g. https://github.com/my-org/my-repo}"
RUNNER_TOKEN="${RUNNER_TOKEN:?Set RUNNER_TOKEN (registration token from GitHub)}"
RUNNER_NAME="${RUNNER_NAME:-$(hostname)-databricks}"
RUNNER_LABELS="${RUNNER_LABELS:-databricks-deploy}"
RUNNER_USER="${RUNNER_USER:-ghrunner}"
RUNNER_DIR="${RUNNER_DIR:-/opt/actions-runner}"
RUNNER_VERSION="${RUNNER_VERSION:-latest}"
RUNNER_GROUP="${RUNNER_GROUP:-Default}"

log() { printf '\n==> %s\n' "$*"; }
[[ $EUID -eq 0 ]] || { echo "Run this script with sudo/root"; exit 1; }

log "1/7 Installing OS packages (curl, jq, git, tar, unzip, python3)"
if command -v apt-get >/dev/null; then
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y curl jq git tar unzip python3 ca-certificates
elif command -v dnf >/dev/null; then
  dnf install -y curl jq git tar unzip python3 ca-certificates
elif command -v yum >/dev/null; then
  yum install -y curl jq git tar unzip python3 ca-certificates
else
  echo "Unsupported package manager - install curl jq git tar unzip python3 manually"; exit 1
fi

log "2/7 Creating service account '${RUNNER_USER}'"
id "$RUNNER_USER" >/dev/null 2>&1 || useradd --create-home --shell /bin/bash "$RUNNER_USER"

log "3/7 Downloading GitHub Actions runner (${RUNNER_VERSION})"
case "$(uname -m)" in
  x86_64)  arch=x64 ;;
  aarch64) arch=arm64 ;;
  *) echo "Unsupported CPU architecture $(uname -m)"; exit 1 ;;
esac
if [[ "$RUNNER_VERSION" == "latest" ]]; then
  RUNNER_VERSION="$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest | jq -r .tag_name | sed 's/^v//')"
fi
mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"
curl -fsSL -o runner.tar.gz \
  "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${arch}-${RUNNER_VERSION}.tar.gz"
tar xzf runner.tar.gz && rm -f runner.tar.gz
./bin/installdependencies.sh
chown -R "$RUNNER_USER":"$RUNNER_USER" "$RUNNER_DIR"

if [[ -n "${HTTPS_PROXY:-}" ]]; then
  log "Writing proxy settings to ${RUNNER_DIR}/.env"
  { echo "https_proxy=${HTTPS_PROXY}"; echo "HTTPS_PROXY=${HTTPS_PROXY}"; echo "no_proxy=${NO_PROXY:-}"; echo "NO_PROXY=${NO_PROXY:-}"; } >> "$RUNNER_DIR/.env"
fi

log "4/7 Registering runner '${RUNNER_NAME}' with labels '${RUNNER_LABELS}'"
sudo -u "$RUNNER_USER" ./config.sh --unattended \
  --url "$GITHUB_URL" \
  --token "$RUNNER_TOKEN" \
  --name "$RUNNER_NAME" \
  --labels "$RUNNER_LABELS" \
  --runnergroup "$RUNNER_GROUP" \
  --work _work \
  --replace

log "5/7 Installing and starting the runner service"
./svc.sh install "$RUNNER_USER"
./svc.sh start

log "6/7 Installing Databricks CLI"
if ! command -v databricks >/dev/null; then
  curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/main/install.sh | sh
fi

log "7/7 Verifying tools"
databricks --version
jq --version
git --version
python3 --version
./svc.sh status || true

cat <<EOF

Runner installed. Next:
  - GitHub -> Settings -> Actions -> Runners: '${RUNNER_NAME}' should show "Idle".
  - Labels on this runner: self-hosted, Linux, X64/ARM64, ${RUNNER_LABELS}
  - If you used labels other than "databricks-deploy", set the repository
    variable RUNNER_LABELS, e.g. ["self-hosted","${RUNNER_LABELS%%,*}"]
  - Firewall: allow outbound HTTPS (443) to github.com, *.githubusercontent.com,
    *.actions.githubusercontent.com and your Databricks workspace URL.
EOF
