#!/usr/bin/env bash
# reset_range.sh — parallel qm rollback clean_state for all target VMs
#
# ============================================================================
# CRITICAL CONSTRAINT (D-10, STATE.md):
#   elastic-vm (10.0.0.10) and caldera-vm (10.0.0.20) are NEVER in this
#   script. They are the PERSISTENT DATA SINK and C2 PLATFORM for the entire
#   lab. Rolling them back would destroy the FullAPT-2025 telemetry corpus
#   and the CALDERA operation history. This is a HARD constraint.
#
#   The EXCLUDE guard below aborts at runtime if any VMID in RESET_VMS
#   resolves to elastic-vm or caldera-vm. This is a construction-time and
#   runtime double-check (T-1-data threat mitigation).
# ============================================================================
#
# Usage: bash reset_range.sh
#
# Phase status: SCAFFOLD — target VM VMIDs are placeholders.
#   Populate RESET_VMS in Phase 3 once dc01/exchange01/sql01/ws01/ws02/kali
#   are provisioned and their VMIDs are known (see TODO: RESET-02 below).
#
# What this script does when complete:
#   For each target VM in parallel:
#     1. qm stop <VMID>        — graceful shutdown
#     2. qm rollback <VMID> clean_state  — restore D-05 baseline snapshot
#     3. qm start <VMID>       — bring VM back up
#   All rollbacks run in parallel (&) with a final wait for all to complete.
#
# Snapshot syntax: https://pve.proxmox.com/pve-docs/qm.1.html [VERIFIED — RESEARCH Pattern 9]
# Use qm only for snapshot operations — never the libvirt CLI (STATE.md locked decision).

set -euo pipefail

SNAP_NAME="clean_state"

# ── EXCLUDED VMs (D-10) — NEVER modify this list ───────────────────────────────
# These VMIDs and IPs are hardcoded as the exclusion reference.
# Any VMID whose ipconfig0 resolves to these IPs will cause an immediate abort.
EXCLUDED_IPS=("10.0.0.10" "10.0.0.20")
EXCLUDED_NAMES=("elastic-vm" "caldera-vm")

# ── TARGET VM allowlist ────────────────────────────────────────────────────────
# TODO (RESET-02, Phase 3): Replace 0 placeholders with actual VMIDs once
# dc01, exchange01, sql01, ws01, ws02, and kali are provisioned in Phase 2/3.
# Example after Phase 3:
#   declare -A RESET_VMS=(
#     ["dc01"]=101
#     ["exchange01"]=102
#     ["sql01"]=103
#     ["ws01"]=104
#     ["ws02"]=105
#     ["kali"]=106
#   )
declare -A RESET_VMS=(
    ["dc01"]=0        # TODO RESET-02: replace with actual VMID (Host 2, 10.10.10.10)
    ["exchange01"]=0  # TODO RESET-02: replace with actual VMID (Host 3, 10.10.10.20)
    ["sql01"]=0       # TODO RESET-02: replace with actual VMID (Host 2, 10.10.10.30)
    ["ws01"]=0        # TODO RESET-02: replace with actual VMID (Host 4, 10.10.10.40)
    ["ws02"]=0        # TODO RESET-02: replace with actual VMID (Host 4, 10.10.10.50)
    ["kali"]=0        # TODO RESET-02: replace with actual VMID (Host 6, 10.10.10.200)
)

# ── Helper functions ────────────────────────────────────────────────────────────
log()  { echo "[reset_range] $*"; }
die()  { echo "[reset_range] FATAL: $*" >&2; exit 1; }
warn() { echo "[reset_range] WARNING: $*" >&2; }

# ── Guard: abort if any VMID in RESET_VMS resolves to an excluded VM ───────────
# Double-check: verify no placeholder VMIDs are 0 (would target wrong VM)
check_exclusions() {
    log "Running D-10 exclusion guard before any rollback..."
    for name in "${!RESET_VMS[@]}"; do
        vmid="${RESET_VMS[$name]}"

        # Reject placeholder VMIDs (must be populated before use)
        if [[ "$vmid" -eq 0 ]]; then
            warn "VMID for '${name}' is 0 (placeholder). Skipping — populate RESET_VMS in Phase 3."
            continue
        fi

        # Fetch ipconfig from qm to detect excluded VMs
        vm_ip=$(qm config "${vmid}" 2>/dev/null | grep -E '^ipconfig0' | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1 || true)

        for excl_ip in "${EXCLUDED_IPS[@]}"; do
            if [[ "$vm_ip" == "$excl_ip" ]]; then
                die "VMID ${vmid} (${name}) resolves to excluded IP ${excl_ip} (elastic-vm or caldera-vm). Aborting. (D-10)"
            fi
        done

        for excl_name in "${EXCLUDED_NAMES[@]}"; do
            vm_desc=$(qm config "${vmid}" 2>/dev/null | grep -i 'description' | tr '[:upper:]' '[:lower:]' || true)
            if echo "$vm_desc" | grep -qi "${excl_name}"; then
                die "VMID ${vmid} description matches excluded name '${excl_name}'. Aborting. (D-10)"
            fi
        done
    done
    log "D-10 exclusion guard passed — no excluded VMs in RESET_VMS."
}

# ── Reset a single VM (stop → rollback → start) ────────────────────────────────
reset_vm() {
    local name="$1"
    local vmid="$2"

    if [[ "$vmid" -eq 0 ]]; then
        log "  [${name}] SKIP — VMID is placeholder 0 (Phase 3 TODO: RESET-02)"
        return 0
    fi

    log "  [${name}] Stopping VMID ${vmid}..."
    qm stop "${vmid}" || warn "[${name}] qm stop returned non-zero (VM may already be stopped)"

    log "  [${name}] Rolling back to ${SNAP_NAME}..."
    qm rollback "${vmid}" "${SNAP_NAME}"

    log "  [${name}] Starting VMID ${vmid}..."
    qm start "${vmid}"

    log "  [${name}] Reset complete."
}

# ── Main ────────────────────────────────────────────────────────────────────────
log "========================================================"
log " reset_range.sh — Cyber Range full reset"
log " Snapshot: ${SNAP_NAME}"
log " Target VMs: ${!RESET_VMS[*]}"
log ""
log " elastic-vm (10.0.0.10) and caldera-vm (10.0.0.20) are"
log " EXCLUDED BY CONSTRUCTION from this script (D-10)."
log "========================================================"
echo ""

check_exclusions

log "Starting parallel rollback for all target VMs..."
PIDS=()
for name in "${!RESET_VMS[@]}"; do
    vmid="${RESET_VMS[$name]}"
    reset_vm "$name" "$vmid" &
    PIDS+=($!)
done

# Wait for all parallel resets to complete
FAILED=0
for pid in "${PIDS[@]}"; do
    if ! wait "$pid"; then
        warn "A background reset job (PID ${pid}) failed."
        FAILED=$(( FAILED + 1 ))
    fi
done

if [[ "$FAILED" -gt 0 ]]; then
    die "${FAILED} reset job(s) failed. Check output above. Run 'qm status <VMID>' to inspect VM states."
fi

log ""
log "========================================================"
log " All target VMs reset to '${SNAP_NAME}'."
log " elastic-vm and caldera-vm untouched (D-10)."
log "========================================================"
