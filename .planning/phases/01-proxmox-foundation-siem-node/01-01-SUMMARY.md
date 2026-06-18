---
phase: 01-proxmox-foundation-siem-node
plan: 01
subsystem: infra
tags: [proxmox, vmbr0, vmbr1, vlan10, lvm-thin, network-isolation, bridge, cyber-range]

requires: []

provides:
  - "scripts/proxmox/verify-isolation.sh: Wave 0 gate — asserts vmbr1 has no bare physical NIC uplink (D-02 / T-1-01)"
  - "scripts/proxmox/verify-storage.sh: Wave 0 gate — asserts LVM-thin pool present per host (D-04)"
  - "scripts/proxmox/network-setup.sh: per-host /etc/network/interfaces generator for vmbr0+vmbr1 bridges"
  - "scripts/proxmox/SWITCH-VLAN10.md: vendor-neutral 802.1Q VLAN 10 trunk configuration steps with isolation guarantee"
  - "scripts/proxmox/README.md: Wave 1 operator runbook (verify-storage → network-setup --apply → verify-isolation order)"

affects:
  - "01-02 (elastic-vm + caldera-vm provisioning): requires vmbr0/vmbr1 bridges on Host 1 and Host 6"
  - "01-03 (Elasticsearch + Fleet Server): requires elastic-vm on vmbr0 at 10.0.0.10"
  - "all phase 2+ plans: all target VMs require vmbr1 isolation confirmed before provisioning"

tech-stack:
  added:
    - "Proxmox VE 8.x bridge networking (vmbr0/vmbr1 via /etc/network/interfaces)"
    - "802.1Q VLAN 10 on managed switch (vendor-neutral)"
    - "LVM-thin storage pool (Proxmox local-lvm)"
  patterns:
    - "Option A VLAN sub-interface (eno1.10) for vmbr1 — simpler than VLAN-aware bridge for single-VLAN lab"
    - "Wave 0 gate scripts — fail-fast before VM provisioning if network/storage prerequisites absent"
    - "Dry-run-first pattern — network-setup.sh previews config before --apply writes it"
    - "Inverted-ping assertion — ping success treated as isolation FAILURE for B-2/B-1 checks"

key-files:
  created:
    - scripts/proxmox/verify-isolation.sh
    - scripts/proxmox/verify-storage.sh
    - scripts/proxmox/network-setup.sh
    - scripts/proxmox/SWITCH-VLAN10.md
    - scripts/proxmox/README.md
  modified: []

key-decisions:
  - "vmbr1 uses bridge-ports eno1.10 (VLAN sub-interface), never bridge-ports eno1 (bare NIC) — enforces D-02 air-gap at hypervisor level"
  - "Option A VLAN sub-interface chosen over Option B VLAN-aware bridge — simpler for single-VLAN lab, avoids bridge-vlan-aware complexity"
  - "network-setup.sh defaults to dry-run preview; --apply flag required for destructive write — prevents accidental overwrite"
  - "verify-isolation.sh Mode B (--from-target-vm) uses inverted-ping logic: ping 8.8.8.8 success = isolation FAILED"
  - "Operator applies scripts on live hardware — checkpoint required after Task 2 before any VM provisioning"

patterns-established:
  - "Wave 0 gate pattern: run verify-storage.sh and verify-isolation.sh before any qm create; non-zero exit blocks provisioning"
  - "Isolation double-gate: hypervisor (vmbr1 no bare NIC) AND switch (VLAN 10 no inter-VLAN routing) — both required"
  - "grep -v '^#' before counting bridge-ports — prevents false positives from comment lines in brctl/interfaces output"

requirements-completed: [INFRA-01]

duration: 5min
completed: 2026-06-18
---

# Phase 1 Plan 01: Proxmox Networking Scripts Summary

**Bash scripts for per-host vmbr0/vmbr1 bridge setup and Wave 0 isolation + LVM-thin gates, with vendor-neutral 802.1Q VLAN 10 switch guide enforcing D-02 air-gap**

## Performance

- **Duration:** 5 min
- **Started:** 2026-06-18T06:12:37Z
- **Completed:** 2026-06-18T06:17:26Z
- **Tasks:** 3/3 complete (2 auto + 1 checkpoint:human-verify — approved by operator)
- **Files created:** 5

## Accomplishments

- Created `verify-isolation.sh` with two modes: Mode A (bridge state check — vmbr1 must have no bare physical NIC) and Mode B (--from-target-vm — inverted ping logic for internet/LAN/TARGET reach); enforces D-02 and T-1-01
- Created `verify-storage.sh` asserting `pvesm scan lvmthin pve` returns a pool and `storage.cfg` has an `lvmthin:` stanza; ZFS guard warns if ZFS found (D-04)
- Created `network-setup.sh` with dry-run default, `--apply` flag for destructive write, per-host vmbr0 IP parameter, generates `iface eno1.10 inet manual` + `bridge-ports eno1.10` for vmbr1 — never bare physical NIC
- Created `SWITCH-VLAN10.md` with Cisco IOS-style CLI and generic web-UI examples for VLAN 10 trunk configuration plus explicit L3 SVI removal to enforce VLAN 10 isolation from LAN
- Created `README.md` with Wave 1 operator runbook (verify-storage → network-setup --apply → ifreload → verify-isolation), host-to-NIC mapping per D-NEW-09, and VM MGMT IP reference

## Task Commits

1. **Task 1: Wave 0 isolation and storage verification scripts** — `2bd01b4` (feat)
2. **Task 2: Per-host bridge config helper, VLAN 10 switch docs, operator README** — `fcea933` (feat)

Task 3 (`checkpoint:human-verify`) — **APPROVED** by operator 2026-06-18.

## Files Created/Modified

- `scripts/proxmox/verify-isolation.sh` — Mode A: brctl state check; Mode B: inverted-ping isolation gate (88 lines)
- `scripts/proxmox/verify-storage.sh` — LVM-thin presence assertion; ZFS guard (73 lines)
- `scripts/proxmox/network-setup.sh` — vmbr0+vmbr1 config generator with dry-run/--apply; VLAN sub-interface enforced (162 lines)
- `scripts/proxmox/SWITCH-VLAN10.md` — vendor-neutral 802.1Q VLAN 10 trunk steps with inter-VLAN routing removal
- `scripts/proxmox/README.md` — Wave 1 operator runbook; host layout per D-NEW-09

## Decisions Made

- Option A (VLAN sub-interface `eno1.10`) chosen over Option B (VLAN-aware bridge) for vmbr1 — single-VLAN lab, simpler config, confirmed in RESEARCH.md Pattern 1
- `network-setup.sh` defaults to dry-run to prevent accidental overwrite; only writes to `/etc/network/interfaces` with explicit `--apply` flag — mirrors standard sysadmin safety practice
- `verify-isolation.sh --from-target-vm` treats `ping 8.8.8.8` SUCCESS as FAIL (inverted logic) to assert isolation rather than connectivity
- Physical NIC name defaults to `eno1` (common on Dell/HP servers) but is a parameter — operator must verify with `ip link show` before running

## Deviations from Plan

None — plan executed exactly as written. All five required files created per the `artifacts` spec in the plan frontmatter.

## Issues Encountered

None.

## Checkpoint Status

**PASSED** — Operator approved 2026-06-18. All 6 hosts have vmbr0+vmbr1 configured; isolation gate passed (test VM on vmbr1 confirmed unreachable to internet and LAN).

Wave 1 complete. Wave 2 (elastic-vm + caldera-vm provisioning) is unblocked.

## Threat Surface Scan

No new network endpoints or auth paths introduced. Scripts run locally on Proxmox hosts via SSH.
The `--apply` flag safety guard in `network-setup.sh` prevents silent destructive writes.
No secrets or credentials handled in any script.

No threat flags to report.

## Known Stubs

None. All five scripts/docs are functional and complete. The operator-specific variables (host IPs,
NIC names, LAN gateway, switch vendor) are parameterized inputs, not stubs — they must be supplied
at runtime by the operator on live hardware.

## Self-Check

Checking files exist and commits are present:

- [x] `scripts/proxmox/verify-isolation.sh` — commit `2bd01b4`
- [x] `scripts/proxmox/verify-storage.sh` — commit `2bd01b4`
- [x] `scripts/proxmox/network-setup.sh` — commit `fcea933`
- [x] `scripts/proxmox/SWITCH-VLAN10.md` — commit `fcea933`
- [x] `scripts/proxmox/README.md` — commit `fcea933`

## Self-Check: PASSED

All 5 required files created, 2 task commits exist, no unexpected deletions.

## Next Phase Readiness

- All 5 scripts/docs ready for operator execution on live hardware
- Checkpoint awaits hardware confirmation before proceeding to Plan 02 (elastic-vm + caldera-vm provisioning)
- Plan 02 requires: Host 1 vmbr0 at 10.0.0.1 (or operator-chosen IP), Host 6 vmbr0 at 10.0.0.6 — both need bridges applied first
- No blockers on the planning side

---
*Phase: 01-proxmox-foundation-siem-node*
*Completed: 2026-06-18*
