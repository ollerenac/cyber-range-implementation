---
phase: 03-full-telemetry-reset
plan: 01
subsystem: infra
tags: [kali, proxmox, qemu, qcow2, vmid-601, dual-nic, bloodhound-ce, mimikatz, ssh-fanout]

# Dependency graph
requires:
  - phase: 01-proxmox-foundation-siem-node
    provides: vmbr0/vmbr1 bridges on all hosts, Host 6 with caldera-vm already present
  - phase: 02-windows-target-network
    provides: phase2-domain-joined snapshot as starting state; confirmed WinRM on all Windows VMs

provides:
  - scripts/proxmox/create-kali-vm.sh — qm create + qm importdisk for Kali VMID 601 on Host 6
  - Human checkpoint with step-by-step console/SSH setup for Kali static IPs, credential change, BloodHound CE, Mimikatz staging, and elastic-vm → Proxmox host SSH key enrollment

affects:
  - 03-02 (Elastic Agent enrollment — Kali MGMT IP 10.0.0.16 must be reachable first)
  - 03-03 (Sysmon deployment — SSH fan-out key pairs must be in place)
  - 03-04 (reset_range.sh + clean_state snapshot — VMID 601 + passwordless SSH to host6 required)

# Tech tracking
tech-stack:
  added: [kali-linux-qcow2, bloodhound-ce-docker, mimikatz-pe]
  patterns: [qm-importdisk-no-cloudinit, dual-nic-vmbr1-vmbr0, ssh-fanout-ed25519]

key-files:
  created:
    - scripts/proxmox/create-kali-vm.sh
  modified: []

key-decisions:
  - "Kali qcow2 has no cloud-init — IPs configured manually via Proxmox console after first boot (Pitfall 3)"
  - "Dual-NIC convention: net0=vmbr1 (TARGET 10.10.10.200/24) net1=vmbr0 (MGMT 10.0.0.16/24) — matches all other target VMs"
  - "VMID guard warns operator if != 601 and requires confirmation before proceeding"
  - "SSH key setup for elastic-vm → host2/3/4/6 documented in next-steps output (required for reset_range.sh fan-out)"
  - "BloodHound CE and Mimikatz staging deferred to Task 2 human checkpoint (D-02 — inside-Kali steps)"

patterns-established:
  - "Pattern: qm importdisk for pre-built distro images (no cloud-init section) — omit all --ide2/--ciuser/--ipconfig0/--cicustom flags"
  - "Pattern: confirmation prompt + VMID guard before destructive qm commands"

requirements-completed: [INFRA-07]

# Metrics
duration: 8min
completed: 2026-06-19
---

# Phase 3 Plan 01: Kali VM Provisioning + SSH Infrastructure Summary

**Kali VMID 601 creation script (dual-NIC, 4 GB RAM, 80 GB disk, no cloud-init) with human checkpoint for console-based static IP config, credential hardening, BloodHound CE, Mimikatz staging, and elastic-vm SSH key enrollment to all four Proxmox hosts**

## Performance

- **Duration:** 8 min
- **Started:** 2026-06-19T02:22:48Z
- **Completed:** 2026-06-19T02:30:00Z
- **Tasks:** 1 of 2 completed (Task 2 is a human-action checkpoint — paused)
- **Files modified:** 1 created

## Accomplishments

- `scripts/proxmox/create-kali-vm.sh` written — follows `create-caldera-vm.sh` pattern, omits all cloud-init flags, includes VMID 601 guard and confirmation prompt
- Script covers: `qm create` with dual-NIC (net0=vmbr1/TARGET, net1=vmbr0/MGMT), `qm importdisk` for Kali qcow2, `scsi0` attach + resize to 80G
- Next-steps summary printed by script covers static IP config (nmcli + ifupdown options), SSH enable, credential change, and Proxmox host key enrollment — all required for Task 2

## Task Commits

1. **Task 1: Write create-kali-vm.sh** - `b3db554` (feat)
2. **Task 2: Run create-kali-vm.sh + configure Kali via console** - CHECKPOINT (human-action — paused)

**Plan metadata:** see final commit in this agent's wave

## Files Created/Modified

- `scripts/proxmox/create-kali-vm.sh` — `qm create` + `qm importdisk` for Kali VMID 601 on Host 6; no cloud-init; dual-NIC (vmbr1/TARGET + vmbr0/MGMT); includes next-steps console instructions

## Decisions Made

- Script intentionally omits all cloud-init flags (`--ide2`, `--ciuser`, `--sshkeys`, `--ipconfig0`, `--nameserver`, `--cicustom`) — Kali pre-built qcow2 is a full XFCE desktop image with NetworkManager, not a cloud image. Reference: 03-RESEARCH.md Pitfall 3 and Pattern 2.
- VMID guard warns and prompts if VMID != 601. This ensures the locked spec (D-01) is enforced without making the script fragile.
- SSH key file argument kept for API symmetry with `create-caldera-vm.sh` even though it is not applied (documented in script header and help text).
- BloodHound CE Docker Compose and Mimikatz staging are post-boot steps inside Kali — they require a running VM and are documented in Task 2 checkpoint, not in this script.

## Deviations from Plan

None — plan executed exactly as written for Task 1. Task 2 is a `checkpoint:human-action` by design.

## Issues Encountered

None.

## User Setup Required

**Task 2 requires manual console steps** — see checkpoint message for full instructions:
- Download Kali qcow2 from kali.org/get-kali → QEMU, copy to Host 6
- Run `create-kali-vm.sh 601` on Host 6, then `qm start 601`
- Open Proxmox console for VM 601, log in as kali/kali, configure static IPs
- Change credentials, enable SSH, set up SSH key from elastic-vm
- Set up passwordless SSH from elastic-vm to root@host2/host3/host4/host6
- Install BloodHound CE via docker-compose and stage Mimikatz PE at /opt/mimikatz/

## Known Stubs

None — `create-kali-vm.sh` is a complete, self-contained script. No placeholder values or TODO blocks.

## Threat Flags

No new network endpoints, auth paths, or schema changes introduced beyond what is in the plan's threat model (T-03-01 through T-03-SC).

## Self-Check

- [x] `scripts/proxmox/create-kali-vm.sh` exists and is executable
- [x] Commit `b3db554` exists: Task 1 feat commit
- [x] SUMMARY.md created at `.planning/phases/03-full-telemetry-reset/03-01-SUMMARY.md`

## Self-Check: PASSED

## Next Phase Readiness

After human completes Task 2 checkpoint (type "kali-ready"):
- Kali VM reachable at 10.0.0.16 from elastic-vm via SSH
- elastic-vm has passwordless SSH to root@host2, root@host3, root@host4, root@host6
- BloodHound CE running on Kali; Mimikatz staged at /opt/mimikatz/x64/
- Ready to proceed to Plan 03-02 (Elastic Agent enrollment on all Windows VMs and Kali)

---
*Phase: 03-full-telemetry-reset*
*Completed: 2026-06-19*
