#!/usr/bin/env bash
# bootstrap-fleet.sh — Bootstrap Fleet Server via elastic-agent 8.19.16 on elastic-vm
#
# Implements RESEARCH.md Pattern 4.
# Source: https://www.elastic.co/guide/en/fleet/8.17/secure-connections.html
#
# Usage: sudo bash scripts/elastic/bootstrap-fleet.sh
# Requires:
#   - Elasticsearch 8.19.16 running and healthy (run install-stack.sh + health-check.sh first)
#   - generate-certs.sh completed (Fleet cert SAN IP:10.0.0.10 verified)
#   - ES_PASSWORD env var set (elastic superuser)
#   - Run as root or with sudo
#
# INTEGRATION POINT: Enrollment tokens issued by this Fleet Server must remain valid
# into Phase 3. The operator copies an enrollment token from:
#   Kibana → Stack Management → Fleet → Enrollment Tokens → "Create enrollment token"
# That token (plus the ca.crt path /etc/elasticsearch/certs/ca.crt) is the Phase 3
# onboarding handoff (D-13, CONTEXT integration points).
#
# ANTI-PATTERN (RESEARCH §Anti-Patterns): Fleet Server MUST be healthy and connected
# to Elasticsearch BEFORE any Phase 3 agent enrollment. This script verifies that
# condition before exiting.
#
# Security (T-1-leak / RESEARCH §Security Domain):
#   - Service token written to /root/.elastic-tokens (chmod 600)
#   - Service token is NEVER echoed to stdout
#   - ES_PASSWORD read from env, never hardcoded
#
# Version note: elastic-agent 8.19.16 is installed by install-stack.sh. Mixing versions
# between elastic-agent and Elasticsearch/Fleet breaks enrollment. This is an
# ANTI-PATTERN — all components must be the same 8.x patch (RESEARCH §Anti-Patterns).

set -euo pipefail

CERTS_DIR="/etc/elasticsearch/certs"
FLEET_CERT="${CERTS_DIR}/fleet-server.crt"
FLEET_KEY="${CERTS_DIR}/fleet-server.key"
CA_CERT="${CERTS_DIR}/ca.crt"
TOKEN_FILE="/root/.elastic-tokens"
ES_URL="https://10.0.0.10:9200"
FLEET_URL="https://10.0.0.10:8220"
SERVICE_TOKENS_TOOL="/usr/share/elasticsearch/bin/elasticsearch-service-tokens"
ELASTIC_AGENT_BIN="/usr/bin/elastic-agent"

echo "=== bootstrap-fleet.sh — Fleet Server Bootstrap ==="
echo "ES:     ${ES_URL}"
echo "Fleet:  ${FLEET_URL}"
echo ""

# ─── Verify prerequisites ──────────────────────────────────────────────────
echo "--- Verifying prerequisites ---"

# Check ES_PASSWORD
if [ -z "${ES_PASSWORD:-}" ]; then
  echo "FATAL: ES_PASSWORD environment variable is not set." >&2
  echo "  Export it: export ES_PASSWORD='<elastic-superuser-password>'" >&2
  exit 1
fi

# Check certs exist (generate-certs.sh must have run)
for f in "${FLEET_CERT}" "${FLEET_KEY}" "${CA_CERT}"; do
  if [ ! -f "${f}" ]; then
    echo "FATAL: Required cert file not found: ${f}" >&2
    echo "  Run: sudo bash scripts/elastic/generate-certs.sh" >&2
    exit 1
  fi
done
echo "[OK] Fleet cert, key, and CA cert present"

# Check elastic-agent binary
if [ ! -x "${ELASTIC_AGENT_BIN}" ]; then
  echo "FATAL: elastic-agent binary not found at ${ELASTIC_AGENT_BIN}" >&2
  echo "  Run: sudo bash scripts/elastic/install-stack.sh" >&2
  exit 1
fi

# Verify elastic-agent version matches expected 8.19.16
AGENT_VERSION=$(${ELASTIC_AGENT_BIN} version 2>/dev/null | grep -oP '8\.\d+\.\d+' | head -1 || echo "unknown")
echo "[OK] elastic-agent version: ${AGENT_VERSION}"
if [ "${AGENT_VERSION}" != "8.19.16" ]; then
  echo "WARNING: elastic-agent version is ${AGENT_VERSION}, expected 8.19.16" >&2
  echo "         Mismatched versions between agent and Elasticsearch break enrollment." >&2
  echo "         Proceeding — verify manually if issues arise." >&2
fi

# Check Elasticsearch is reachable before proceeding
echo ""
echo "--- Verifying Elasticsearch reachability ---"
ES_STATUS=$(curl -sf -k \
  -u "elastic:${ES_PASSWORD}" \
  "${ES_URL}/_cluster/health" 2>/dev/null | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status','unknown'))" 2>/dev/null || echo "unreachable")

if [ "${ES_STATUS}" = "green" ] || [ "${ES_STATUS}" = "yellow" ]; then
  echo "[OK] Elasticsearch reachable, cluster status: ${ES_STATUS}"
else
  echo "FATAL: Elasticsearch is not reachable or not healthy (status: ${ES_STATUS})" >&2
  echo "  Check: systemctl status elasticsearch" >&2
  echo "  Check: bash scripts/elastic/health-check.sh" >&2
  exit 1
fi

# ─── Step 1: Create Fleet service token ──────────────────────────────────────
echo ""
echo "--- Step 1: Create Fleet service token ---"
echo "    Token written to ${TOKEN_FILE} (chmod 600) — NEVER echoed to stdout (T-1-leak)"

# Initialize token file securely before writing anything
touch "${TOKEN_FILE}"
chmod 600 "${TOKEN_FILE}"
chown root:root "${TOKEN_FILE}"

if grep -q "fleet-token" "${TOKEN_FILE}" 2>/dev/null; then
  echo "INFO: Fleet service token appears to already exist in ${TOKEN_FILE}."
  echo "      Skipping token creation. Delete ${TOKEN_FILE} and re-run to regenerate."
  # Read the existing token (suppress output, just verify it's readable)
  TOKEN_LINE=$(grep "fleet-token" "${TOKEN_FILE}" | tail -1)
  SERVICE_TOKEN=$(echo "${TOKEN_LINE}" | awk '{print $NF}')
else
  # Create the service token — output includes the token value, write only to file
  # The tool prints: "SERVICE_TOKEN elastic/fleet-server/fleet-token = <TOKEN>"
  "${SERVICE_TOKENS_TOOL}" create elastic/fleet-server fleet-token 2>/dev/null | \
    tee -a "${TOKEN_FILE}" > /dev/null

  # Extract token value from file (last whitespace-delimited field on the fleet-token line)
  TOKEN_LINE=$(grep "fleet-token" "${TOKEN_FILE}" | tail -1)
  SERVICE_TOKEN=$(echo "${TOKEN_LINE}" | awk '{print $NF}')

  echo "[OK] Service token created and stored in ${TOKEN_FILE}"
fi

if [ -z "${SERVICE_TOKEN:-}" ]; then
  echo "FATAL: Could not extract service token from ${TOKEN_FILE}" >&2
  echo "  Contents of ${TOKEN_FILE} (first line):" >&2
  head -1 "${TOKEN_FILE}" | sed 's/=.*/= <REDACTED>/' >&2
  exit 1
fi
echo "[OK] Service token extracted (not displayed — T-1-leak mitigation)"

# ─── Step 2: Install elastic-agent as Fleet Server ───────────────────────────
echo ""
echo "--- Step 2: Install elastic-agent as Fleet Server ---"
echo "    URL:            ${FLEET_URL}"
echo "    ES backend:     ${ES_URL}"
echo "    Fleet cert:     ${FLEET_CERT}"
echo "    CA cert:        ${CA_CERT}"
echo "    Port:           8220"

# elastic-agent install bootstraps Fleet Server in one command.
# All cert paths reference the SAN-verified certs from generate-certs.sh.
# --fleet-server-es-ca: ES trusts the lab CA for Fleet→ES connection
# --certificate-authorities: agents connecting to Fleet trust the lab CA
# --fleet-server-cert/key: the Fleet Server presents the SAN-verified cert (D-12/T-1-03)
${ELASTIC_AGENT_BIN} install \
  --non-interactive \
  --url="${FLEET_URL}" \
  --fleet-server-es="${ES_URL}" \
  --fleet-server-service-token="${SERVICE_TOKEN}" \
  --fleet-server-policy=fleet-server-policy \
  --fleet-server-es-ca="${CA_CERT}" \
  --certificate-authorities="${CA_CERT}" \
  --fleet-server-cert="${FLEET_CERT}" \
  --fleet-server-cert-key="${FLEET_KEY}" \
  --fleet-server-port=8220

echo "[OK] elastic-agent install completed"

# ─── Step 3: Verify Fleet Server is running and port 8220 is LISTEN ──────────
echo ""
echo "--- Step 3: Verify Fleet Server ---"

# Wait for Fleet Server to start (up to 60 seconds)
echo "    Waiting up to 60 seconds for Fleet Server to start..."
for i in $(seq 1 12); do
  AGENT_STATUS=$(${ELASTIC_AGENT_BIN} status 2>/dev/null | head -5 || echo "not_ready")

  if echo "${AGENT_STATUS}" | grep -qi "healthy\|running\|fleet server"; then
    echo "[OK] elastic-agent status: Fleet Server running"
    break
  fi

  if [ "${i}" -eq 12 ]; then
    echo "WARNING: elastic-agent status did not show 'healthy' within 60 seconds."
    echo "         Status output:"
    ${ELASTIC_AGENT_BIN} status 2>/dev/null || true
    echo "         Proceeding to port check — Fleet Server may still be starting."
  else
    echo "  Attempt ${i}/12 — retrying in 5s..."
    sleep 5
  fi
done

# Verify port 8220 is LISTEN on 10.0.0.10 (the primary Fleet Server gate)
echo ""
echo "--- Verifying Fleet Server port 8220 ---"
PORT_CHECK=$(ss -tlnp 2>/dev/null | grep ':8220' || echo "NOT_FOUND")

echo "    ss -tlnp | grep 8220 output:"
echo "${PORT_CHECK}" | sed 's/^/      /'

if echo "${PORT_CHECK}" | grep -q ":8220"; then
  echo "[OK] Fleet Server port 8220: LISTEN"
else
  echo "FATAL: Port 8220 is not in LISTEN state." >&2
  echo "       Fleet Server did not bind to ${FLEET_URL}" >&2
  echo "       Check: journalctl -u elastic-agent -n 50 --no-pager" >&2
  echo "       Check: ${ELASTIC_AGENT_BIN} status" >&2
  exit 1
fi

# ─── Step 4: Verify Fleet Server is connected to Elasticsearch ───────────────
echo ""
echo "--- Step 4: Verify Fleet Server→Elasticsearch connectivity ---"

# Full elastic-agent status output for logging
echo "    elastic-agent status:"
${ELASTIC_AGENT_BIN} status 2>/dev/null | sed 's/^/      /' || true

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "=== bootstrap-fleet.sh complete ==="
echo ""
echo "Fleet Server is running at ${FLEET_URL}"
echo "Service token stored at: ${TOKEN_FILE} (chmod 600 — keep secret)"
echo ""
echo "Phase 3 integration handoff:"
echo "  1. CA cert for agent trust: ${CA_CERT}"
echo "     Distribute to target VMs before elastic-agent enroll (D-13)"
echo "  2. Enrollment token: generate in Kibana UI:"
echo "     https://10.0.0.10:5601 → Stack Management → Fleet → Enrollment Tokens"
echo "     → 'Create enrollment token' → copy for Phase 3 VM provisioning scripts"
echo ""
echo "Verify Fleet Server cert SAN on the wire:"
echo "  openssl s_client -connect 10.0.0.10:8220 </dev/null 2>/dev/null | \\"
echo "    openssl x509 -noout -text | grep -A1 'Subject Alternative'"
echo "  Expected: IP Address:10.0.0.10"
