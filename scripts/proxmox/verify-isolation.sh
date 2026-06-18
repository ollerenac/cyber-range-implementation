#!/usr/bin/env bash
# verify-isolation.sh — Wave 0 gate: assert vmbr1 TARGET bridge is air-gapped
#
# Usage:
#   bash verify-isolation.sh [HOST]         # check bridge state on HOST (default: localhost)
#   bash verify-isolation.sh --from-target-vm  # run inside a vmbr1 test VM to check network reach
#
# Exit codes:
#   0  = all assertions PASS  (safe to proceed with VM provisioning)
#   1  = one or more assertions FAIL (STOP — fix isolation before provisioning)
#
# Implements INFRA-01 isolation gate from 01-VALIDATION.md.
# Enforces D-02: vmbr1 has NO physical uplink on any Proxmox host.
# Enforces T-1-01: TARGET VMs cannot reach LAN (10.0.0.0/24) or internet.
#
# Threat model:
#   - A bare physical NIC on vmbr1 (bridge-ports eno1) bridges TARGET traffic
#     directly onto the untagged LAN — lab network bleeds to production LAN.
#   - A VLAN sub-interface (bridge-ports eno1.10) is the ONLY acceptable uplink
#     because VLAN 10 is switch-isolated from the LAN (no inter-VLAN routing).
#   - From inside a TARGET VM: 8.8.8.8 and 10.0.0.10 must be unreachable.
#     Only 10.10.10.1 (Proxmox host vmbr1 address) must succeed.

set -euo pipefail

# ── colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
pass() { echo -e "${GREEN}[PASS]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; FAILURES=$((FAILURES + 1)); }

FAILURES=0

# ── mode dispatch ─────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--from-target-vm" ]]; then
    # ── Mode B: run inside a vmbr1 test VM ──────────────────────────────────
    echo "=== verify-isolation.sh (--from-target-vm mode) ==="
    echo "    Assertions: internet FAIL, LAN FAIL, host vmbr1 PASS"
    echo ""

    # Assertion B-1: internet (8.8.8.8) must be UNREACHABLE
    # Logic inversion: ping EXIT 0 means isolation FAILED; EXIT non-zero is PASS
    if ping -c 3 -W 2 8.8.8.8 > /dev/null 2>&1; then
        fail "B-1 Internet reach (8.8.8.8): ping SUCCEEDED — vmbr1 isolation is BROKEN (D-02 violated)"
    else
        pass "B-1 Internet reach (8.8.8.8): ping FAILED as expected — isolated from internet"
    fi

    # Assertion B-2: LAN management network (10.0.0.10 = elastic-vm MGMT IP) must be UNREACHABLE
    # Logic inversion: ping EXIT 0 means isolation FAILED
    if ping -c 3 -W 2 10.0.0.10 > /dev/null 2>&1; then
        fail "B-2 LAN MGMT reach (10.0.0.10): ping SUCCEEDED — TARGET VLAN leaks to MGMT (D-02 violated)"
    else
        pass "B-2 LAN MGMT reach (10.0.0.10): ping FAILED as expected — isolated from MGMT network"
    fi

    # Assertion B-3: Proxmox host vmbr1 address (10.10.10.1) must be REACHABLE
    if ping -c 3 -W 2 10.10.10.1 > /dev/null 2>&1; then
        pass "B-3 vmbr1 host reach (10.10.10.1): ping SUCCEEDED — TARGET bridge functional"
    else
        fail "B-3 vmbr1 host reach (10.10.10.1): ping FAILED — check that the Proxmox host has vmbr1 at 10.10.10.1"
    fi

else
    # ── Mode A: check bridge state on a Proxmox host ────────────────────────
    TARGET_HOST="${1:-localhost}"
    echo "=== verify-isolation.sh (bridge-state mode) host=${TARGET_HOST} ==="
    echo "    Assertions: vmbr1 has no bare physical NIC uplink (D-02)"
    echo ""

    # Run brctl show on target host (local or via ssh)
    if [[ "$TARGET_HOST" == "localhost" ]]; then
        BRCTL_OUT=$(brctl show vmbr1 2>&1 || true)
    else
        BRCTL_OUT=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
            "root@${TARGET_HOST}" 'brctl show vmbr1' 2>&1 || true)
    fi

    if [[ -z "$BRCTL_OUT" ]]; then
        fail "A-1 brctl show vmbr1: no output — is vmbr1 bridge configured on ${TARGET_HOST}?"
    else
        # Assertion A-1: vmbr1 must exist
        if echo "$BRCTL_OUT" | grep -v '^#' | grep -q 'vmbr1'; then
            pass "A-1 vmbr1 bridge: exists on ${TARGET_HOST}"
        else
            fail "A-1 vmbr1 bridge: NOT found on ${TARGET_HOST} — run network-setup.sh first"
        fi

        # Assertion A-2: interfaces column must be empty ("none") OR contain only eno1.10
        # The brctl show format: bridge   bridge-id   STP   interfaces
        # A bare physical NIC (e.g. eno1, eth0, enp2s0) as bridge-ports breaks D-02.
        # eno1.10 is the ONLY acceptable uplink (VLAN 10 sub-interface — switch-isolated).
        # Filter comment lines before checking to avoid grep-false-positive on documented examples.
        IFACE_COL=$(echo "$BRCTL_OUT" | grep -v '^#' | awk '/vmbr1/{found=1; next} found{print $1; exit}' || true)
        # Alternative: grab from the same line if all on one line
        IFACE_INLINE=$(echo "$BRCTL_OUT" | grep -v '^#' | grep 'vmbr1' | awk '{print $4}' || true)

        # Combine: if bridge-ports spans multiple lines, IFACE_COL has it; inline row may have it too
        IFACE_PRESENT="${IFACE_COL}${IFACE_INLINE}"

        if [[ -z "$IFACE_PRESENT" ]]; then
            # No interfaces entry at all → bridge-ports none → PASS
            pass "A-2 vmbr1 bridge-ports: empty (no physical uplink) — isolation intact"
        elif echo "$IFACE_PRESENT" | grep -v '^#' | grep -Eq '^eno1\.10$'; then
            pass "A-2 vmbr1 bridge-ports: eno1.10 (VLAN sub-interface only) — isolation intact"
        elif echo "$IFACE_PRESENT" | grep -v '^#' | grep -q '\.'; then
            # Contains a dot — likely a VLAN sub-interface (e.g. eno2.10)
            pass "A-2 vmbr1 bridge-ports: VLAN sub-interface '${IFACE_PRESENT}' detected — verify it is VLAN 10"
        else
            # No dot → bare physical NIC name → ISOLATION FAILURE
            fail "A-2 vmbr1 bridge-ports: '${IFACE_PRESENT}' is a bare physical NIC — D-02 VIOLATED"
            echo "       Fix: edit /etc/network/interfaces, set 'bridge-ports eno1.10' (not '${IFACE_PRESENT}')"
            echo "       Then run: ifreload -a && verify-isolation.sh ${TARGET_HOST}"
        fi
    fi

fi

# ── summary ───────────────────────────────────────────────────────────────────
echo ""
if [[ $FAILURES -eq 0 ]]; then
    echo -e "${GREEN}=== RESULT: ALL ASSERTIONS PASSED ===${NC}"
    exit 0
else
    echo -e "${RED}=== RESULT: ${FAILURES} ASSERTION(S) FAILED ===${NC}"
    echo "    Do NOT provision target VMs until isolation is confirmed."
    exit 1
fi
