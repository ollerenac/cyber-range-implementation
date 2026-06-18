#!/usr/bin/env bash
# health-check.sh — INFRA-02 Wave 0 gate: verify Elasticsearch cluster health GREEN + Kibana reachable
#
# Usage: bash scripts/elastic/health-check.sh
#
# Requires: ES_PASSWORD env var set (elastic superuser password — never hardcoded here, T-1-leak)
#   export ES_PASSWORD="<your-elastic-password>"
#
# Exit codes:
#   0  — all checks passed (ES green, Kibana reachable)
#   1  — one or more checks failed (printed to stderr with details)
#
# This script is the INFRA-02 Wave 0 gate referenced in VALIDATION.md.
# Run it before proceeding to any Phase 2 or Phase 3 work.

set -euo pipefail

ES_URL="https://10.0.0.10:9200"
KIBANA_URL="https://10.0.0.10:5601"
ES_CA="/etc/elasticsearch/certs/http_ca.crt"

FAIL=0

echo "=== Elastic Stack Health Check ==="
echo "ES:     ${ES_URL}"
echo "Kibana: ${KIBANA_URL}"
echo ""

# ─── Check: ES_PASSWORD set ──────────────────────────────────────────────────
if [ -z "${ES_PASSWORD:-}" ]; then
  echo "FATAL: ES_PASSWORD environment variable is not set." >&2
  echo "  Export it: export ES_PASSWORD='<elastic-superuser-password>'" >&2
  exit 1
fi

# ─── Determine CA cert flag ───────────────────────────────────────────────────
if [ -f "${ES_CA}" ]; then
  CA_FLAG="--cacert ${ES_CA}"
else
  echo "WARNING: ${ES_CA} not found — using -k (insecure TLS). This is acceptable before generate-certs.sh has run."
  CA_FLAG="-k"
fi

# ─── Check 1: Elasticsearch cluster health = green ───────────────────────────
echo "--- Check 1: Elasticsearch cluster health ---"

HEALTH_JSON=$(curl -sf ${CA_FLAG} \
  -u "elastic:${ES_PASSWORD}" \
  "${ES_URL}/_cluster/health?pretty" 2>&1) || {
  echo "FAIL: Could not reach Elasticsearch at ${ES_URL}" >&2
  echo "  Error: ${HEALTH_JSON}" >&2
  FAIL=1
}

if [ "${FAIL}" -eq 0 ]; then
  STATUS=$(echo "${HEALTH_JSON}" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d.get('status','unknown'))" 2>/dev/null || echo "parse_error")

  NUM_NODES=$(echo "${HEALTH_JSON}" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d.get('number_of_nodes',0))" 2>/dev/null || echo "0")

  echo "  Status:       ${STATUS}"
  echo "  Nodes:        ${NUM_NODES}"

  if [ "${STATUS}" != "green" ]; then
    echo "FAIL: Cluster health is '${STATUS}', expected 'green'" >&2
    echo "  Full response:" >&2
    echo "${HEALTH_JSON}" | python3 -m json.tool 2>/dev/null || echo "${HEALTH_JSON}" >&2
    FAIL=1
  else
    echo "[OK] Elasticsearch cluster health: GREEN (${NUM_NODES} node(s))"
  fi
fi

# ─── Check 2: Elasticsearch responds with valid JSON ─────────────────────────
echo ""
echo "--- Check 2: Elasticsearch root endpoint ---"

ROOT_RESPONSE=$(curl -sf ${CA_FLAG} \
  -u "elastic:${ES_PASSWORD}" \
  "${ES_URL}/" 2>&1) || {
  echo "FAIL: Elasticsearch root endpoint unreachable" >&2
  FAIL=1
}

if [ "${FAIL}" -eq 0 ]; then
  ES_VERSION=$(echo "${ROOT_RESPONSE}" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d.get('version',{}).get('number','unknown'))" 2>/dev/null || echo "unknown")
  echo "[OK] Elasticsearch version: ${ES_VERSION}"

  # Verify version is 8.19.16
  if [ "${ES_VERSION}" != "8.19.16" ]; then
    echo "WARNING: Elasticsearch version is ${ES_VERSION}, expected 8.19.16 (EOL check: 8.17.x and 8.18.x are EOL)"
  fi
fi

# ─── Check 3: Kibana HTTP 200 or 302 ─────────────────────────────────────────
echo ""
echo "--- Check 3: Kibana reachable at ${KIBANA_URL} ---"

KIBANA_HTTP_CODE=$(curl -sk \
  -o /dev/null \
  -w "%{http_code}" \
  --max-time 15 \
  "${KIBANA_URL}" 2>/dev/null || echo "000")

echo "  HTTP status: ${KIBANA_HTTP_CODE}"

if [ "${KIBANA_HTTP_CODE}" = "200" ] || [ "${KIBANA_HTTP_CODE}" = "302" ]; then
  echo "[OK] Kibana reachable (HTTP ${KIBANA_HTTP_CODE})"
else
  echo "FAIL: Kibana returned HTTP ${KIBANA_HTTP_CODE}, expected 200 or 302" >&2
  echo "  Check: systemctl status kibana" >&2
  echo "  Check: journalctl -u kibana -n 30 --no-pager" >&2
  FAIL=1
fi

# ─── Check 4: ILM policy exists ──────────────────────────────────────────────
echo ""
echo "--- Check 4: ILM policy 'lab-logs-30d' ---"

ILM_CODE=$(curl -sk ${CA_FLAG} \
  -u "elastic:${ES_PASSWORD}" \
  -o /dev/null \
  -w "%{http_code}" \
  "${ES_URL}/_ilm/policy/lab-logs-30d" 2>/dev/null || echo "000")

if [ "${ILM_CODE}" = "200" ]; then
  echo "[OK] ILM policy 'lab-logs-30d' exists"
else
  echo "WARNING: ILM policy 'lab-logs-30d' not found (HTTP ${ILM_CODE})" >&2
  echo "  Run: sudo bash scripts/elastic/install-stack.sh (with ES_PASSWORD set)" >&2
  # Not a hard FAIL — policy may not have been applied yet on fresh install
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "=== Health Check Summary ==="

if [ "${FAIL}" -eq 0 ]; then
  echo "RESULT: PASSED — Elasticsearch GREEN + Kibana reachable"
  echo "        INFRA-02 Wave 0 gate: OPEN"
  exit 0
else
  echo "RESULT: FAILED — see errors above" >&2
  echo "        INFRA-02 Wave 0 gate: BLOCKED" >&2
  exit 1
fi
