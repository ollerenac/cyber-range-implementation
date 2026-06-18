#!/usr/bin/env bash
# generate-certs.sh — Generate lab CA + Fleet Server cert (SAN IP:10.0.0.10) + Kibana cert
#
# Implements RESEARCH.md Pattern 3 exactly.
# Source: https://www.elastic.co/guide/en/elasticsearch/reference/8.17/certutil.html
#
# Usage: sudo bash scripts/elastic/generate-certs.sh
# Requires: Elasticsearch 8.19.16 installed (provides elasticsearch-certutil binary)
#           Run as root or with sudo
#
# CRITICAL (T-1-03 / D-12): The Fleet Server cert MUST contain SAN IP:10.0.0.10.
# Without it, ALL Phase 3 Elastic Agent enrollments will fail with:
#   "x509: certificate is valid for fleet-server, not 10.0.0.10"
# This script self-verifies the SAN after generation and FAILS if absent.
#
# D-13: ca.crt is placed at /etc/elasticsearch/certs/ca.crt (chmod 644).
#       This is the Phase 3 trust anchor — distributed to all target VMs before
#       elastic-agent enroll. Document this path in runbooks and SUMMARY.
#
# D-11: Lab CA generated with elasticsearch-certutil ca (not openssl req).
#       certutil integrates with the ES keystore; PEM export is done via openssl pkcs12.
#
# Cert output paths:
#   /etc/elasticsearch/certs/elastic-stack-ca.p12  — lab CA (PKCS#12, passphrase "")
#   /etc/elasticsearch/certs/ca.crt                — lab CA PEM (D-13 distribution anchor)
#   /etc/elasticsearch/certs/fleet-server.p12      — Fleet Server cert (PKCS#12)
#   /etc/elasticsearch/certs/fleet-server.crt      — Fleet Server cert PEM
#   /etc/elasticsearch/certs/fleet-server.key      — Fleet Server key PEM (chmod 600)
#   /etc/elasticsearch/certs/kibana.p12            — Kibana cert (PKCS#12)
#   /etc/elasticsearch/certs/kibana.crt            — Kibana cert PEM
#   /etc/elasticsearch/certs/kibana.key            — Kibana key PEM (chmod 600)

set -euo pipefail
umask 077  # default all new files to 600 (owner read/write only)

CERTS_DIR="/etc/elasticsearch/certs"
CERTUTIL="/usr/share/elasticsearch/bin/elasticsearch-certutil"

echo "=== generate-certs.sh — Lab CA + Fleet/Kibana cert generation ==="
echo ""

# ─── Verify certutil exists ──────────────────────────────────────────────────
if [ ! -x "${CERTUTIL}" ]; then
  echo "FATAL: ${CERTUTIL} not found. Run install-stack.sh first." >&2
  exit 1
fi

# ─── Create certs directory (if not already created by install-stack.sh) ─────
mkdir -p "${CERTS_DIR}"
chmod 750 "${CERTS_DIR}"
chown root:elasticsearch "${CERTS_DIR}"

# ─── Step 1: Generate lab CA ─────────────────────────────────────────────────
echo "--- Step 1: Generate lab CA (elastic-stack-ca.p12) ---"

if [ -f "${CERTS_DIR}/elastic-stack-ca.p12" ]; then
  echo "WARNING: ${CERTS_DIR}/elastic-stack-ca.p12 already exists. Skipping CA generation."
  echo "         To regenerate, remove the existing file first."
  echo "         WARNING: Regenerating the CA invalidates ALL previously signed certs."
else
  "${CERTUTIL}" ca \
    --out "${CERTS_DIR}/elastic-stack-ca.p12" \
    --pass ""
  chmod 600 "${CERTS_DIR}/elastic-stack-ca.p12"
  chown root:root "${CERTS_DIR}/elastic-stack-ca.p12"
  echo "[OK] Lab CA generated: ${CERTS_DIR}/elastic-stack-ca.p12 (chmod 600)"
fi

# ─── Step 2: Export CA certificate as PEM (D-13 Phase 3 distribution anchor) ─
echo ""
echo "--- Step 2: Export CA as PEM (ca.crt) — D-13 Phase 3 trust anchor ---"

openssl pkcs12 \
  -in "${CERTS_DIR}/elastic-stack-ca.p12" \
  -out "${CERTS_DIR}/ca.crt" \
  -nokeys \
  -passin pass:""

chmod 644 "${CERTS_DIR}/ca.crt"
chown root:root "${CERTS_DIR}/ca.crt"
echo "[OK] CA cert exported: ${CERTS_DIR}/ca.crt (chmod 644)"
echo "     Phase 3 path: /etc/elasticsearch/certs/ca.crt"
echo "     Distribute to all target VMs before elastic-agent enroll (D-13)"

# ─── Step 3: Generate Fleet Server cert with SAN IP:10.0.0.10 ────────────────
echo ""
echo "--- Step 3: Generate Fleet Server cert (--ip 10.0.0.10 --dns fleet-server) ---"
echo "    D-12: SAN IP:10.0.0.10 is MANDATORY — without it, all Phase 3 enrollments fail (T-1-03)"

if [ -f "${CERTS_DIR}/fleet-server.p12" ]; then
  echo "WARNING: ${CERTS_DIR}/fleet-server.p12 already exists. Skipping."
  echo "         To regenerate, remove fleet-server.p12, fleet-server.crt, fleet-server.key first."
else
  "${CERTUTIL}" cert \
    --ca "${CERTS_DIR}/elastic-stack-ca.p12" \
    --ca-pass "" \
    --dns fleet-server \
    --ip 10.0.0.10 \
    --out "${CERTS_DIR}/fleet-server.p12" \
    --pass ""
  chmod 600 "${CERTS_DIR}/fleet-server.p12"
  chown root:root "${CERTS_DIR}/fleet-server.p12"
  echo "[OK] Fleet Server cert generated: ${CERTS_DIR}/fleet-server.p12 (chmod 600)"
fi

# ─── Step 4: Export Fleet Server cert + key as PEM (elastic-agent uses PEM) ──
echo ""
echo "--- Step 4: Export Fleet Server cert + key as PEM ---"

# Export certificate (no key)
openssl pkcs12 \
  -in "${CERTS_DIR}/fleet-server.p12" \
  -out "${CERTS_DIR}/fleet-server.crt" \
  -clcerts \
  -nokeys \
  -passin pass:""

# Export private key (no cert)
openssl pkcs12 \
  -in "${CERTS_DIR}/fleet-server.p12" \
  -out "${CERTS_DIR}/fleet-server.key" \
  -nocerts \
  -nodes \
  -passin pass:""

chmod 600 "${CERTS_DIR}/fleet-server.key"
chown root:root "${CERTS_DIR}/fleet-server.crt" "${CERTS_DIR}/fleet-server.key"
echo "[OK] Fleet Server PEM exported: fleet-server.crt + fleet-server.key (key chmod 600)"

# ─── Step 5: CRITICAL SAN self-verification (T-1-03 mitigation) ──────────────
echo ""
echo "--- Step 5: SAN self-verification (CRITICAL — T-1-03) ---"
echo "    Verifying that fleet-server.crt contains SAN IP:10.0.0.10..."

SAN_OUTPUT=$(openssl x509 -in "${CERTS_DIR}/fleet-server.crt" -noout -text | grep -A3 "Subject Alternative Name" || echo "NO_SAN")

echo "    SAN output:"
echo "${SAN_OUTPUT}" | sed 's/^/      /'

if echo "${SAN_OUTPUT}" | grep -q "IP Address:10.0.0.10"; then
  echo "[OK] SAN verified: IP Address:10.0.0.10 is present"
else
  echo "" >&2
  echo "FATAL: Fleet Server cert does NOT contain SAN IP:10.0.0.10" >&2
  echo "       This is T-1-03: all Phase 3 elastic-agent enrollments will fail with TLS error." >&2
  echo "       Actual SAN output:" >&2
  echo "${SAN_OUTPUT}" | sed 's/^/  /' >&2
  echo "" >&2
  echo "       Remediation: remove ${CERTS_DIR}/fleet-server.p12 and re-run this script." >&2
  exit 1
fi

# ─── Step 6: Generate Kibana cert (RESEARCH Q4 — separate cert, same CA) ─────
echo ""
echo "--- Step 6: Generate Kibana cert (--dns elastic-vm --ip 10.0.0.10) ---"
echo "    Separate Kibana cert keeps cert scope clean (RESEARCH Open Question Q4)"

if [ -f "${CERTS_DIR}/kibana.p12" ]; then
  echo "WARNING: ${CERTS_DIR}/kibana.p12 already exists. Skipping."
  echo "         To regenerate, remove kibana.p12, kibana.crt, kibana.key first."
else
  "${CERTUTIL}" cert \
    --ca "${CERTS_DIR}/elastic-stack-ca.p12" \
    --ca-pass "" \
    --dns elastic-vm \
    --ip 10.0.0.10 \
    --out "${CERTS_DIR}/kibana.p12" \
    --pass ""
  chmod 600 "${CERTS_DIR}/kibana.p12"
  chown root:root "${CERTS_DIR}/kibana.p12"
  echo "[OK] Kibana cert generated: ${CERTS_DIR}/kibana.p12 (chmod 600)"
fi

# Export Kibana cert + key as PEM (Kibana uses PEM in kibana.yml)
openssl pkcs12 \
  -in "${CERTS_DIR}/kibana.p12" \
  -out "${CERTS_DIR}/kibana.crt" \
  -clcerts \
  -nokeys \
  -passin pass:""

openssl pkcs12 \
  -in "${CERTS_DIR}/kibana.p12" \
  -out "${CERTS_DIR}/kibana.key" \
  -nocerts \
  -nodes \
  -passin pass:""

chmod 600 "${CERTS_DIR}/kibana.key"

# Kibana needs to read its key — grant kibana group read access
chown root:kibana "${CERTS_DIR}/kibana.key" "${CERTS_DIR}/kibana.crt" 2>/dev/null || \
  chown root:root "${CERTS_DIR}/kibana.key" "${CERTS_DIR}/kibana.crt"

echo "[OK] Kibana PEM exported: kibana.crt + kibana.key (key chmod 600)"

# Copy certs to Kibana certs directory
KIBANA_CERTS_DIR="/etc/kibana/certs"
mkdir -p "${KIBANA_CERTS_DIR}"
cp "${CERTS_DIR}/kibana.crt" "${KIBANA_CERTS_DIR}/kibana.crt"
cp "${CERTS_DIR}/kibana.key" "${KIBANA_CERTS_DIR}/kibana.key"
cp "${CERTS_DIR}/ca.crt" "${KIBANA_CERTS_DIR}/ca.crt"
chown root:kibana "${KIBANA_CERTS_DIR}/kibana.key" "${KIBANA_CERTS_DIR}/kibana.crt" "${KIBANA_CERTS_DIR}/ca.crt" 2>/dev/null || true
chmod 640 "${KIBANA_CERTS_DIR}/kibana.key"
chmod 644 "${KIBANA_CERTS_DIR}/kibana.crt" "${KIBANA_CERTS_DIR}/ca.crt"
echo "[OK] Kibana certs copied to ${KIBANA_CERTS_DIR}/"

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "=== generate-certs.sh complete ==="
echo ""
echo "Cert inventory:"
echo "  ${CERTS_DIR}/ca.crt             — Lab CA PEM (D-13; chmod 644; distribute to all target VMs)"
echo "  ${CERTS_DIR}/fleet-server.crt   — Fleet Server cert PEM (SAN IP:10.0.0.10 VERIFIED)"
echo "  ${CERTS_DIR}/fleet-server.key   — Fleet Server key PEM (chmod 600)"
echo "  ${CERTS_DIR}/kibana.crt         — Kibana cert PEM (SAN IP:10.0.0.10, DNS:elastic-vm)"
echo "  ${CERTS_DIR}/kibana.key         — Kibana key PEM (chmod 600)"
echo "  ${KIBANA_CERTS_DIR}/kibana.crt  — Kibana cert (copied for Kibana service)"
echo "  ${KIBANA_CERTS_DIR}/kibana.key  — Kibana key (copied for Kibana service)"
echo ""
echo "Next steps:"
echo "  1. Copy kibana.yml into place: sudo cp scripts/elastic/kibana.yml /etc/kibana/kibana.yml"
echo "  2. Add Kibana encryption keys to kibana.yml:"
echo "     sudo /usr/share/kibana/bin/kibana-encryption-keys generate"
echo "  3. Start Kibana: sudo systemctl enable --now kibana"
echo "  4. Run: sudo bash scripts/elastic/bootstrap-fleet.sh"
