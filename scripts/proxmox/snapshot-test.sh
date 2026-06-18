#!/usr/bin/env bash
# snapshot-test.sh — verify qm snapshot/rollback/delsnapshot on a throwaway test VM
#
# Usage: bash snapshot-test.sh <VMID>
#
# Runs the full D-05 reset sequence on ONE throwaway VM to confirm the mechanism works
# before committing to Phase 3 production snapshots (ROADMAP Phase 1 gate requirement).
#
# IMPORTANT: Never run this on elastic-vm or caldera-vm (D-10).
#   elastic-vm VMID resolves to 10.0.0.10 — permanent data sink, never snapshotted.
#   caldera-vm VMID resolves to 10.0.0.20 — persistent C2 platform, never snapshotted.
#
# Syntax source: https://pve.proxmox.com/pve-docs/qm.1.html [VERIFIED — RESEARCH Pattern 9]
# No --quiesce flag: qm snapshot does not have this flag. QEMU Guest Agent freeze is
# automatic when enabled in VM options (qm set <VMID> --agent 1). This applies to
# Phase 3 Windows VMs; the throwaway test VM does not require guest agent.

set -euo pipefail

SNAP_NAME="test_snap"

# ── Argument check ──────────────────────────────────────────────────────────────
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <VMID>" >&2
    echo "Example: $0 999" >&2
    exit 1
fi

VMID="$1"

# ── Guard: refuse to operate on elastic-vm or caldera-vm (D-10) ────────────────
# These VMs are the persistent data sink and C2 platform — NEVER snapshotted.
EXCLUDED_DESCRIPTION=$(qm config "${VMID}" 2>/dev/null | grep -i 'description' || true)
VM_IP=$(qm config "${VMID}" 2>/dev/null | grep -E 'ipconfig|ip=' | head -1 || true)

if echo "${VM_IP}" | grep -qE '10\.0\.0\.10|10\.0\.0\.20'; then
    echo "ERROR: VMID ${VMID} appears to be elastic-vm (10.0.0.10) or caldera-vm (10.0.0.20)." >&2
    echo "       These VMs are NEVER snapshotted (D-10). Aborting." >&2
    exit 1
fi

echo "[snapshot-test] VMID: ${VMID}"
echo "[snapshot-test] Snapshot name: ${SNAP_NAME}"
echo "[snapshot-test] Checking VM exists..."
qm status "${VMID}"

# ── Step 1: Create snapshot ─────────────────────────────────────────────────────
echo ""
echo "[snapshot-test] Step 1: qm snapshot ${VMID} ${SNAP_NAME}"
qm snapshot "${VMID}" "${SNAP_NAME}" --description "snapshot-test.sh automated test snapshot"
echo "[snapshot-test] Snapshot created."

# ── Step 2: Rollback (timed) ────────────────────────────────────────────────────
echo ""
echo "[snapshot-test] Step 2: qm rollback ${VMID} ${SNAP_NAME} (timed)"
ROLLBACK_START=$(date +%s)
qm rollback "${VMID}" "${SNAP_NAME}"
ROLLBACK_END=$(date +%s)
ROLLBACK_DURATION=$(( ROLLBACK_END - ROLLBACK_START ))
echo "[snapshot-test] Rollback complete. Duration: ${ROLLBACK_DURATION}s"

# ── Step 3: Delete snapshot ─────────────────────────────────────────────────────
echo ""
echo "[snapshot-test] Step 3: qm delsnapshot ${VMID} ${SNAP_NAME}"
qm delsnapshot "${VMID}" "${SNAP_NAME}"
echo "[snapshot-test] Snapshot deleted."

# ── Result ──────────────────────────────────────────────────────────────────────
echo ""
echo "================================================="
echo " SNAPSHOT TEST PASSED for VMID ${VMID}"
echo " Rollback time: ${ROLLBACK_DURATION}s"
echo " D-05 mechanism (qm rollback <vmid> clean_state) confirmed working."
echo " Record rollback time in 01-04-SUMMARY.md."
echo "================================================="
