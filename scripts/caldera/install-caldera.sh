#!/usr/bin/env bash
# install-caldera.sh — CALDERA 5.3.0 installation on caldera-vm (10.0.0.20)
#
# Run as root (or with sudo) on caldera-vm after it is booted and SSH-reachable.
# Pre-conditions:
#   - Ubuntu 22.04 LTS, caldera-vm at 10.0.0.20
#   - Internet access from caldera-vm (to pull github.com/mitre/caldera and PyPI)
#   - local.yml has had api_key_red/api_key_blue rotated from PLACEHOLDER values
#
# What this script does:
#   1. Create 'caldera' system user
#   2. Clone CALDERA 5.3.0 from github.com/mitre/caldera (MITRE — approved source)
#   3. Install Python dependencies
#   4. Copy local.yml config (sets routable beacon URL + changed API keys)
#   5. First-run build (--build compiles the VueJS UI — required once before systemd start)
#   6. Install and enable caldera.service systemd unit
#   7. Verify UI health at http://10.0.0.20:8888/api/v2/health (gate)
#   8. Document actual listening ports (resolves Research A1: 8853 vs 7010)
#
# PORT NOTE (Research A1):
#   local.yml sets app.contact.tcp: 0.0.0.0:8853 explicitly.
#   CALDERA 5.x default is 7010 — the grep at the end documents which ports
#   actually bind after startup. If 8853 is not present, inspect conf/default.yml
#   and ensure local.yml override was copied correctly.
#
# SECURITY (T-1-04):
#   This script does NOT contain API keys. The operator must have already rotated
#   the PLACEHOLDER values in local.yml before running this script.

set -euo pipefail

CALDERA_INSTALL_DIR="/opt/caldera"
CALDERA_BRANCH="5.3.0"
CALDERA_REPO="https://github.com/mitre/caldera.git"
CALDERA_VM_IP="10.0.0.20"
CALDERA_UI_PORT="8888"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { echo "[install-caldera] $*"; }
die() { echo "[install-caldera] ERROR: $*" >&2; exit 1; }

# ── 0. Preflight: ensure local.yml keys are rotated ────────────────────────────
LOCAL_YML="${SCRIPT_DIR}/local.yml"
if [[ ! -f "$LOCAL_YML" ]]; then
    die "local.yml not found at ${LOCAL_YML}. Ensure scripts/caldera/local.yml is present."
fi
if grep -q 'CHANGE_ME' "$LOCAL_YML"; then
    die "local.yml still contains PLACEHOLDER values (CHANGE_ME_*). Rotate api_key_red, api_key_blue, and passwords before running this script. (T-1-04)"
fi
log "local.yml key check passed — no PLACEHOLDER values found."

# ── 1. Create caldera system user ──────────────────────────────────────────────
if ! id caldera &>/dev/null; then
    log "Creating system user 'caldera'..."
    useradd --system --no-create-home --shell /usr/sbin/nologin caldera
else
    log "User 'caldera' already exists — skipping."
fi

# ── 2. Install system dependencies ─────────────────────────────────────────────
log "Installing system dependencies..."
apt-get update -qq
apt-get install -y --no-install-recommends \
    git \
    python3-pip \
    python3-dev \
    build-essential \
    libssl-dev \
    libffi-dev \
    curl

# ── 3. Clone CALDERA 5.3.0 ─────────────────────────────────────────────────────
if [[ -d "${CALDERA_INSTALL_DIR}/.git" ]]; then
    log "CALDERA already cloned at ${CALDERA_INSTALL_DIR} — skipping clone."
else
    log "Cloning CALDERA ${CALDERA_BRANCH} from ${CALDERA_REPO}..."
    git clone "${CALDERA_REPO}" --recursive --branch "${CALDERA_BRANCH}" \
        "${CALDERA_INSTALL_DIR}"
fi
# Confirm tag
ACTUAL_TAG=$(git -C "${CALDERA_INSTALL_DIR}" describe --tags --exact-match 2>/dev/null || \
             git -C "${CALDERA_INSTALL_DIR}" rev-parse --short HEAD)
log "Cloned commit/tag: ${ACTUAL_TAG}"

# ── 4. Install Python requirements ─────────────────────────────────────────────
log "Installing Python requirements..."
pip3 install -r "${CALDERA_INSTALL_DIR}/requirements.txt"

# ── 5. Install local.yml config ────────────────────────────────────────────────
log "Installing local.yml into ${CALDERA_INSTALL_DIR}/conf/..."
mkdir -p "${CALDERA_INSTALL_DIR}/conf"
cp "${LOCAL_YML}" "${CALDERA_INSTALL_DIR}/conf/local.yml"
chown caldera:caldera "${CALDERA_INSTALL_DIR}/conf/local.yml"
chmod 640 "${CALDERA_INSTALL_DIR}/conf/local.yml"

# ── 6. First-run build (compiles VueJS UI — required before systemd start) ─────
log "Running first-time build (python3 server.py --insecure --build)..."
log "This compiles the VueJS UI and may take several minutes on first run."
cd "${CALDERA_INSTALL_DIR}"
python3 server.py --insecure --build &
BUILD_PID=$!
log "Build PID: ${BUILD_PID} — waiting up to 120 seconds for UI build to complete..."
for i in $(seq 1 120); do
    sleep 1
    if curl -sf "http://${CALDERA_VM_IP}:${CALDERA_UI_PORT}/api/v2/health" &>/dev/null; then
        log "CALDERA UI is up after ${i}s. Stopping build process to hand off to systemd."
        kill "${BUILD_PID}" 2>/dev/null || true
        wait "${BUILD_PID}" 2>/dev/null || true
        break
    fi
    if ! kill -0 "${BUILD_PID}" 2>/dev/null; then
        # Process exited — check if it completed the build or crashed
        log "Build process exited. Checking if UI is reachable..."
        sleep 3
        if ! curl -sf "http://${CALDERA_VM_IP}:${CALDERA_UI_PORT}/api/v2/health" &>/dev/null; then
            die "Build process exited and UI is not reachable. Check /opt/caldera logs."
        fi
        break
    fi
    if [[ $((i % 20)) -eq 0 ]]; then
        log "  Still building... (${i}s elapsed)"
    fi
done
cd - >/dev/null

# ── 7. Set ownership ───────────────────────────────────────────────────────────
chown -R caldera:caldera "${CALDERA_INSTALL_DIR}"

# ── 8. Install systemd unit ────────────────────────────────────────────────────
log "Installing caldera.service systemd unit..."
cp "${SCRIPT_DIR}/caldera.service" /etc/systemd/system/caldera.service
chmod 644 /etc/systemd/system/caldera.service
systemctl daemon-reload
systemctl enable caldera.service
systemctl restart caldera.service

log "Waiting for CALDERA to start under systemd..."
for i in $(seq 1 60); do
    sleep 2
    if curl -sf "http://${CALDERA_VM_IP}:${CALDERA_UI_PORT}/api/v2/health" &>/dev/null; then
        log "CALDERA systemd service is up (${i}x2s elapsed)."
        break
    fi
    if [[ $i -eq 60 ]]; then
        die "CALDERA did not start within 120 seconds under systemd. Run: journalctl -u caldera -n 50"
    fi
done

# ── 9. Health check — verify version 5.3.0 (GATE) ─────────────────────────────
log "Verifying health endpoint..."
HEALTH_JSON=$(curl -s "http://${CALDERA_VM_IP}:${CALDERA_UI_PORT}/api/v2/health")
echo "[install-caldera] Health response: ${HEALTH_JSON}"
if ! echo "${HEALTH_JSON}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
version = data.get('version', '')
print(f'  Reported version: {version}')
if '5.3' not in version:
    print(f'  WARNING: expected 5.3.x, got: {version}')
    sys.exit(1)
print('  Version check PASSED')
"; then
    die "Health check failed or version mismatch. Expected 5.3.x. Full response: ${HEALTH_JSON}"
fi

# ── 10. Document actual listening ports (resolves Research A1: 8853 vs 7010) ───
log "Documenting actual listening ports (Research A1 resolution):"
log "  ss -tlnp | grep -E '8888|8853|7010|7011|7012'"
ss -tlnp | grep -E '8888|8853|7010|7011|7012' || log "  (no matching ports found — check CALDERA config)"
log ""
log "PORT AUDIT NOTE: The CONTEXT.md specifies port 8853 for TCP agent contact."
log "  - If 8853 appears above: conf/local.yml app.contact.tcp override is working."
log "  - If 7010 appears instead: CALDERA ignored local.yml override; check file was"
log "    copied to /opt/caldera/conf/local.yml before the first run."
log "  - Port 8888 must always appear (HTTP UI + HTTP agent beacon)."
log "  Record the actual ports in 01-04-SUMMARY.md under 'A1 Resolution'."

log ""
log "====================================================="
log " CALDERA 5.3.0 installation complete."
log " UI: http://${CALDERA_VM_IP}:${CALDERA_UI_PORT}"
log " Systemd: systemctl status caldera"
log " Logs:    journalctl -u caldera -f"
log "====================================================="
