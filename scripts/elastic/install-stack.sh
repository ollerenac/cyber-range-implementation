#!/usr/bin/env bash
# install-stack.sh — Install and configure Elasticsearch + Kibana + Elastic Agent on elastic-vm
#
# Version pin: ALL three packages install at EXACTLY 8.19.16
#   NOTE: 8.17.x is EOL as of August 5, 2025. 8.18.x is EOL as of October 21, 2025.
#   8.19.16 is the correct current pin per STATE.md "all Elastic components pinned to same 8.x patch".
#   Source: RESEARCH.md §State of the Art (confirmed live 2026-06-17 from elastic.co apt repo).
#
# Usage: sudo bash scripts/elastic/install-stack.sh
#
# Requires:
#   - Ubuntu 22.04 LTS on elastic-vm (10.0.0.10)
#   - vm.max_map_count=262144 pre-applied by Plan 02 cloud-init (asserted below)
#   - Run as root or with sudo
#
# After install, capture the elastic superuser password from:
#   journalctl -u elasticsearch | grep -A3 "Security autoconfiguration"
# Then export: export ES_PASSWORD="<captured-password>"
#
# ES_PASSWORD env var is required for the ILM policy curl at the end of this script.
# NEVER hardcode it here — T-1-leak mitigation (RESEARCH §Security Domain).

set -euo pipefail

ELASTIC_VERSION="8.19.16"
ES_CERTS_DIR="/etc/elasticsearch/certs"
KIBANA_CERTS_DIR="/etc/kibana/certs"

echo "=== Elastic Stack Installer — version ${ELASTIC_VERSION} ==="
echo "Target host: elastic-vm (10.0.0.10)"
echo ""

# ─── GATE: vm.max_map_count assertion (Plan 02 cloud-init prerequisite) ───────
# Elasticsearch in production mode (network.host != loopback) enforces this.
# If cloud-init did not apply it, ES will fail to start (RESEARCH Pitfall 3).
MAPCOUNT=$(sysctl -n vm.max_map_count)
if [ "${MAPCOUNT}" -lt 262144 ]; then
  echo "FATAL: vm.max_map_count is ${MAPCOUNT}, expected >= 262144." >&2
  echo "This should have been set by Plan 02 cloud-init (sysctl.d/99-elasticsearch.conf)." >&2
  echo "Fix: sudo sysctl -w vm.max_map_count=262144 && echo 'vm.max_map_count=262144' | sudo tee /etc/sysctl.d/99-elasticsearch.conf && sudo sysctl -p /etc/sysctl.d/99-elasticsearch.conf" >&2
  exit 1
fi
echo "[OK] vm.max_map_count=${MAPCOUNT}"

# ─── Step 1: Add Elastic 8.x apt repository ────────────────────────────────
echo ""
echo "=== Step 1: Add Elastic 8.x apt repository ==="

# Install prerequisites
apt-get install -y apt-transport-https gnupg

# Import GPG key
# Source: https://www.elastic.co/guide/en/elasticsearch/reference/8.19/deb.html
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | \
  gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg

# Add 8.x repo
echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] \
  https://artifacts.elastic.co/packages/8.x/apt stable main" | \
  tee /etc/apt/sources.list.d/elastic-8.x.list

apt-get update

# ─── Step 2: Install pinned versions ─────────────────────────────────────────
echo ""
echo "=== Step 2: Install elasticsearch=${ELASTIC_VERSION} kibana=${ELASTIC_VERSION} elastic-agent=${ELASTIC_VERSION} ==="
echo "    (NEVER install 8.17.x or 8.18.x — both EOL; versions must be identical across all components)"

apt-get install -y \
  "elasticsearch=${ELASTIC_VERSION}" \
  "kibana=${ELASTIC_VERSION}" \
  "elastic-agent=${ELASTIC_VERSION}"

# Pin versions to prevent unintended upgrades
apt-mark hold elasticsearch kibana elastic-agent

# ─── Step 3: Deploy Elasticsearch config ─────────────────────────────────────
echo ""
echo "=== Step 3: Deploy Elasticsearch configuration ==="

# Create certs directory (used by generate-certs.sh later)
mkdir -p "${ES_CERTS_DIR}"
chmod 750 "${ES_CERTS_DIR}"
chown root:elasticsearch "${ES_CERTS_DIR}"

# Deploy elasticsearch.yml (network.host 10.0.0.10, discovery.type single-node, security enabled)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "${SCRIPT_DIR}/elasticsearch.yml" /etc/elasticsearch/elasticsearch.yml
chown root:elasticsearch /etc/elasticsearch/elasticsearch.yml
chmod 660 /etc/elasticsearch/elasticsearch.yml

# Verify critical settings are present
grep -q "discovery.type: single-node" /etc/elasticsearch/elasticsearch.yml || {
  echo "FATAL: elasticsearch.yml is missing 'discovery.type: single-node'" >&2; exit 1
}
grep -q "network.host: 10.0.0.10" /etc/elasticsearch/elasticsearch.yml || {
  echo "FATAL: elasticsearch.yml is missing 'network.host: 10.0.0.10'" >&2; exit 1
}
# Security check: ensure xpack.security.enabled: false was NOT introduced (T-1-02)
if grep -q "xpack.security.enabled: false" /etc/elasticsearch/elasticsearch.yml; then
  echo "FATAL: elasticsearch.yml contains 'xpack.security.enabled: false' — this disables authentication (T-1-02). Remove it." >&2
  exit 1
fi
echo "[OK] elasticsearch.yml deployed and validated"

# ─── Step 4: Deploy JVM heap options ─────────────────────────────────────────
echo ""
echo "=== Step 4: Deploy JVM heap (8g/8g — D-08) ==="

cp "${SCRIPT_DIR}/jvm-heap.options" /etc/elasticsearch/jvm.options.d/heap.options
chown root:elasticsearch /etc/elasticsearch/jvm.options.d/heap.options
chmod 660 /etc/elasticsearch/jvm.options.d/heap.options

grep -q -- "-Xms8g" /etc/elasticsearch/jvm.options.d/heap.options || {
  echo "FATAL: heap.options is missing -Xms8g" >&2; exit 1
}
echo "[OK] JVM heap set to 8g/8g"

# ─── Step 5: Create Kibana certs directory ───────────────────────────────────
mkdir -p "${KIBANA_CERTS_DIR}"
chmod 750 "${KIBANA_CERTS_DIR}"
chown root:kibana "${KIBANA_CERTS_DIR}" 2>/dev/null || chown root:root "${KIBANA_CERTS_DIR}"

# ─── Step 6: Enable and start Elasticsearch ──────────────────────────────────
echo ""
echo "=== Step 6: Enable and start Elasticsearch ==="

systemctl daemon-reload
systemctl enable elasticsearch
systemctl start elasticsearch

echo ""
echo "=== IMPORTANT: Capture the elastic superuser password ==="
echo "    Elasticsearch generates the password once on first start."
echo "    Run the following command and save the output:"
echo ""
echo "      journalctl -u elasticsearch | grep -A5 'Security autoconfiguration'"
echo ""
echo "    Alternatively, reset the password at any time:"
echo "      /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic"
echo ""
echo "    Once you have the password, export it:"
echo "      export ES_PASSWORD='<your-password>'"
echo ""
echo "    Then re-run this script to apply the ILM policy (or run the curl commands manually)."
echo ""

# ─── Step 7: Wait for Elasticsearch to become healthy ────────────────────────
echo "=== Step 7: Wait for Elasticsearch health ==="
echo "    Waiting up to 90 seconds for cluster health..."

for i in $(seq 1 18); do
  STATUS=$(curl -sk -u "elastic:${ES_PASSWORD:-PLACEHOLDER}" \
    "https://10.0.0.10:9200/_cluster/health" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status','unknown'))" 2>/dev/null || echo "waiting")

  if [ "${STATUS}" = "green" ] || [ "${STATUS}" = "yellow" ]; then
    echo "[OK] Elasticsearch cluster health: ${STATUS}"
    break
  fi

  if [ "${i}" -eq 18 ]; then
    echo ""
    echo "WARNING: Elasticsearch did not reach healthy state within 90 seconds."
    echo "Check: journalctl -u elasticsearch -n 50 --no-pager"
    echo "Continuing — ILM policy step will fail if ES is not up. Re-run after ES is healthy."
  else
    echo "  Attempt ${i}/18 — status: ${STATUS} — retrying in 5s..."
    sleep 5
  fi
done

# ─── Step 8: Apply ILM policy ────────────────────────────────────────────────
echo ""
echo "=== Step 8: Apply 30-day ILM policy (lab-logs-30d) ==="

if [ -z "${ES_PASSWORD:-}" ]; then
  echo "SKIP: ES_PASSWORD not set. To apply the ILM policy manually, run:"
  echo "  export ES_PASSWORD='<elastic-superuser-password>'"
  echo "  curl -sk -u elastic:\$ES_PASSWORD -X PUT https://10.0.0.10:9200/_ilm/policy/lab-logs-30d \\"
  echo "    --cacert /etc/elasticsearch/certs/http_ca.crt \\"
  echo "    -H 'Content-Type: application/json' \\"
  echo "    -d @${SCRIPT_DIR}/ilm-policy.json"
  echo ""
  echo "  Then create the index template:"
  echo "  curl -sk -u elastic:\$ES_PASSWORD -X PUT https://10.0.0.10:9200/_index_template/lab-logs \\"
  echo "    --cacert /etc/elasticsearch/certs/http_ca.crt \\"
  echo "    -H 'Content-Type: application/json' \\"
  echo "    -d '{\"index_patterns\":[\"logs-*\"],\"template\":{\"settings\":{\"lifecycle\":{\"name\":\"lab-logs-30d\"}}}}'"
else
  # Determine CA cert path: ES auto-generates http_ca.crt on first start
  ES_CA="/etc/elasticsearch/certs/http_ca.crt"
  if [ ! -f "${ES_CA}" ]; then
    echo "WARNING: ${ES_CA} not found yet. ES may still be starting. Using -k (insecure) for now."
    ES_CA_FLAG="-k"
  else
    ES_CA_FLAG="--cacert ${ES_CA}"
  fi

  # PUT the ILM policy
  HTTP_CODE=$(curl -s -o /tmp/ilm_response.json -w "%{http_code}" \
    ${ES_CA_FLAG} \
    -u "elastic:${ES_PASSWORD}" \
    -X PUT "https://10.0.0.10:9200/_ilm/policy/lab-logs-30d" \
    -H "Content-Type: application/json" \
    -d "@${SCRIPT_DIR}/ilm-policy.json")

  if [ "${HTTP_CODE}" = "200" ]; then
    echo "[OK] ILM policy 'lab-logs-30d' applied (30-day hot→delete)"
  else
    echo "WARNING: ILM PUT returned HTTP ${HTTP_CODE}. Response:"
    cat /tmp/ilm_response.json
    echo ""
    echo "Re-run after Elasticsearch is healthy and ES_PASSWORD is correct."
  fi

  # Create index template associating logs-* with the ILM policy
  HTTP_CODE=$(curl -s -o /tmp/tpl_response.json -w "%{http_code}" \
    ${ES_CA_FLAG} \
    -u "elastic:${ES_PASSWORD}" \
    -X PUT "https://10.0.0.10:9200/_index_template/lab-logs" \
    -H "Content-Type: application/json" \
    -d '{"index_patterns":["logs-*"],"template":{"settings":{"lifecycle":{"name":"lab-logs-30d"}}}}')

  if [ "${HTTP_CODE}" = "200" ]; then
    echo "[OK] Index template 'lab-logs' applied (logs-* → lab-logs-30d ILM)"
  else
    echo "WARNING: Index template PUT returned HTTP ${HTTP_CODE}. Response:"
    cat /tmp/tpl_response.json
  fi
fi

echo ""
echo "=== install-stack.sh complete ==="
echo ""
echo "Next steps:"
echo "  1. Capture elastic password from journalctl (see Step 6 above)"
echo "  2. Run: sudo bash scripts/elastic/generate-certs.sh"
echo "  3. Copy kibana.yml into place: sudo cp scripts/elastic/kibana.yml /etc/kibana/kibana.yml"
echo "     Copy Kibana certs: sudo cp /etc/elasticsearch/certs/kibana.crt /etc/kibana/certs/"
echo "                        sudo cp /etc/elasticsearch/certs/kibana.key /etc/kibana/certs/"
echo "     Then: sudo chown root:kibana /etc/kibana/certs/kibana.key && sudo chmod 640 /etc/kibana/certs/kibana.key"
echo "  4. Generate Kibana encryption keys:"
echo "     sudo /usr/share/kibana/bin/kibana-encryption-keys generate"
echo "     (Add the xpack.*.encryptionKey lines to /etc/kibana/kibana.yml)"
echo "  5. Start Kibana: sudo systemctl enable --now kibana"
echo "  6. Run: sudo bash scripts/elastic/bootstrap-fleet.sh"
echo "  7. Run: bash scripts/elastic/health-check.sh"
