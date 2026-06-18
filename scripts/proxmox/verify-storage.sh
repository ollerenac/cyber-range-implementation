#!/usr/bin/env bash
# verify-storage.sh — Wave 0 gate: assert LVM-thin pool is present on a Proxmox host
#
# Usage:
#   bash verify-storage.sh [HOST]   # check LVM-thin on HOST (default: localhost)
#
# Exit codes:
#   0  = LVM-thin pool confirmed  (safe to create VMs with thin-provisioned disks)
#   1  = LVM-thin pool absent     (STOP — create the pool before VM provisioning)
#
# Implements D-04 (LVM-thin present, no ZFS) from 01-CONTEXT.md.
# Must pass before any qm create command is run in Wave 2.
#
# What it checks:
#   1. pvesm scan lvmthin pve  → returns at least one pool name
#   2. /etc/pve/storage.cfg    → contains an 'lvmthin:' stanza (Proxmox knows about it)

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
pass() { echo -e "${GREEN}[PASS]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; FAILURES=$((FAILURES + 1)); }

FAILURES=0

TARGET_HOST="${1:-localhost}"
echo "=== verify-storage.sh host=${TARGET_HOST} ==="
echo "    Assertions: LVM-thin pool present (D-04)"
echo ""

# Helper: run a command locally or via SSH
run_on_host() {
    if [[ "$TARGET_HOST" == "localhost" ]]; then
        eval "$1" 2>&1 || true
    else
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
            "root@${TARGET_HOST}" "$1" 2>&1 || true
    fi
}

# Assertion 1: pvesm scan lvmthin pve returns at least one pool
# 'pvesm scan lvmthin pve' lists thin pools in the 'pve' volume group.
# Expected output example:
#   pve/data
PVESM_OUT=$(run_on_host 'pvesm scan lvmthin pve')

if [[ -z "$PVESM_OUT" ]]; then
    fail "S-1 pvesm scan lvmthin pve: no output — no LVM-thin pools found in VG 'pve'"
    echo "     To create a thin pool:"
    echo "       lvcreate -L 100G -T pve/data"
    echo "     Then add to Proxmox storage config (Datacenter → Storage → Add → LVM-Thin)"
else
    POOL_COUNT=$(echo "$PVESM_OUT" | grep -vc '^$' || echo "0")
    pass "S-1 pvesm scan lvmthin pve: found ${POOL_COUNT} pool(s): $(echo "$PVESM_OUT" | tr '\n' ' ')"
fi

# Assertion 2: /etc/pve/storage.cfg contains an lvmthin: stanza
STORAGE_CFG=$(run_on_host 'cat /etc/pve/storage.cfg 2>/dev/null || echo ""')

if echo "$STORAGE_CFG" | grep -q 'lvmthin:'; then
    # Show the stanza for confirmation
    STANZA=$(echo "$STORAGE_CFG" | grep -A5 'lvmthin:' | head -10)
    pass "S-2 storage.cfg contains lvmthin: stanza:"
    echo "$STANZA" | sed 's/^/       /'
else
    fail "S-2 /etc/pve/storage.cfg has no lvmthin: stanza — Proxmox has not registered the LVM-thin backend"
    echo "     Add via: Datacenter → Storage → Add → LVM-Thin"
    echo "       ID: local-lvm, VG: pve, Thin Pool: data, Content: Disk image,Container"
fi

# ── ZFS guard: flag if ZFS is being used (D-04 forbids ZFS — RAM overhead) ────
ZFS_STOR=$(echo "$STORAGE_CFG" | grep -c 'zfspool:' || echo "0")
if [[ "$ZFS_STOR" -gt 0 ]]; then
    echo ""
    echo -e "${RED}[WARN]${NC} ZFS storage found in storage.cfg — D-04 requires LVM-thin only."
    echo "       ZFS uses 1–2 GB RAM per host; use LVM-thin on 16 GB machines to avoid memory pressure."
fi

# ── summary ───────────────────────────────────────────────────────────────────
echo ""
if [[ $FAILURES -eq 0 ]]; then
    echo -e "${GREEN}=== RESULT: STORAGE GATE PASSED — LVM-thin confirmed ===${NC}"
    exit 0
else
    echo -e "${RED}=== RESULT: ${FAILURES} ASSERTION(S) FAILED — do NOT create VMs yet ===${NC}"
    exit 1
fi
