---
phase: 01-proxmox-foundation-siem-node
plan: 02
subsystem: infra
tags: [proxmox, qm-create, cloud-init, elastic-vm, caldera-vm, ubuntu-22.04, lvm-thin, vm-provisioning]

requires:
  - "01-01: vmbr0/vmbr1 bridges on Host 1 and Host 6 (network-setup.sh applied)"

provides:
  - "scripts/proxmox/create-elastic-vm.sh: qm create for elastic-vm — 14 GB/200 GB/10.0.0.10 (LOCKED D-12)"
  - "scripts/proxmox/create-caldera-vm.sh: qm create for caldera-vm — 6 GB/40 GB/10.0.0.20"
  - "scripts/proxmox/cloud-init-user-data.yaml: shared cloud-init template; sets vm.max_map_count=262144 and elasticsearch nofile 65535 (Pitfall 3 prerequisites)"

affects:
  - "01-03 (Elasticsearch + Fleet Server): elastic-vm at 10.0.0.10 is the hard precondition; Elasticsearch OS prereqs pre-applied via cloud-init"
  - "01-04 (CALDERA): caldera-vm at 10.0.0.20 must be stable before Plan 04 builds CALDERA agent binaries"
  - "All Phase 2+ plans: both control-plane VMs must be SSH-reachable before target VM provisioning begins"

tech-stack:
  added:
    - "qm create + qm importdisk + qm resize (Proxmox 8.x VM provisioning API)"
    - "Ubuntu 22.04 cloud image (jammy-server-cloudimg-amd64.img) via cloud-init"
    - "cloud-init write_files + runcmd for OS prerequisite injection"
  patterns:
    - "Shared cloud-init template pattern — single user-data file applied to both control-plane VMs; OS prereqs harmless on caldera-vm, mandatory on elastic-vm"
    - "7-step qm provisioning pattern: create → importdisk → attach scsi0 → resize → add cloudinit drive → configure cloud-init → set description"
    - "Parameterized scripts — VMID, LAN_GW, STORAGE, CLOUD_IMAGE, SSH_KEYFILE are operator inputs; no hardcoded credentials or host-specific values"
    - "Confirm prompt before destructive qm create — mirrors dry-run safety pattern from Plan 01"

key-files:
  created:
    - scripts/proxmox/cloud-init-user-data.yaml
    - scripts/proxmox/create-elastic-vm.sh
    - scripts/proxmox/create-caldera-vm.sh
  modified: []

key-decisions:
  - "cloud-init template shared between both VMs — Elasticsearch OS prereqs (vm.max_map_count, nofile) are harmless no-ops on caldera-vm and eliminate a Plan 03 failure mode"
  - "vm.max_map_count applied both transiently (sysctl -w) and persistently (/etc/sysctl.d/99-elasticsearch.conf) in runcmd — covers both the first boot and future reboots"
  - "DISK_VOLID constructed as ${STORAGE}:vm-${VMID}-disk-0 — matches Proxmox LVM-thin naming convention after qm importdisk"
  - "Static IP configured via ipconfig0 in qm cloud-init args, not hardcoded in user-data.yaml — keeps the template reusable for future VMs"

requirements-completed: [INFRA-02]

duration: 6min
completed: 2026-06-18
---

# Phase 1 Plan 02: elastic-vm + caldera-vm Provisioning Scripts Summary

**qm create scripts for the two persistent control-plane VMs (elastic-vm 14 GB/200 GB/10.0.0.10 and caldera-vm 6 GB/40 GB/10.0.0.20) with a shared cloud-init template that pre-applies Elasticsearch production mode OS prerequisites**

## Performance

- **Duration:** 6 min
- **Started:** 2026-06-18T06:43:20Z
- **Completed:** 2026-06-18T06:46:11Z
- **Tasks:** 2/3 complete (2 auto tasks committed; Task 3 is checkpoint:human-verify — paused awaiting operator)
- **Files created:** 3

## Accomplishments

- Created `cloud-init-user-data.yaml`: shared headless Ubuntu 22.04 cloud-init template. Installs `qemu-guest-agent` and `openssh-server`, disables password SSH auth. Applies Elasticsearch production mode OS prerequisites via `write_files` + `runcmd`: `vm.max_map_count=262144` in `/etc/sysctl.d/99-elasticsearch.conf` and `elasticsearch soft/hard nofile 65535` in `/etc/security/limits.d/99-elasticsearch.conf`. These are the exact settings from RESEARCH.md Pitfall 3 that prevent Elasticsearch bootstrap check failures in Plan 03.

- Created `create-elastic-vm.sh`: 7-step `qm create` script for elastic-vm on Host 1. Locked specs: 14336 MiB RAM, 4 cores, 200 GB LVM-thin disk, vmbr0 only (no vmbr1 NIC), ipconfig0=10.0.0.10/24, `--agent 1`. Imports Ubuntu 22.04 cloud image via `qm importdisk`, resizes to 200 GB, attaches cloud-init drive, configures static IP + SSH key + cicustom pointing to shared user-data. Header comment flags 10.0.0.10 as LOCKED by D-12 (Fleet Server TLS cert SAN). Parameterized: VMID, LAN_GW, STORAGE, CLOUD_IMAGE, SSH_KEYFILE are operator inputs.

- Created `create-caldera-vm.sh`: mirrors elastic-vm script structure with caldera-vm specs per D-NEW-09: 6144 MiB RAM, 2 cores, 40 GB LVM-thin disk, vmbr0 only, ipconfig0=10.0.0.20/24, `--agent 1`. Header notes D-10 (never snapshotted/never in reset_range.sh) and Phase 4 CALDERA agent URL dependency on stable 10.0.0.20.

## Task Commits

1. **Task 1: cloud-init template + elastic-vm create script** — `795fd39` (feat)
   Files: `scripts/proxmox/cloud-init-user-data.yaml`, `scripts/proxmox/create-elastic-vm.sh`

2. **Task 2: caldera-vm create script** — `d5985e3` (feat)
   Files: `scripts/proxmox/create-caldera-vm.sh`

Task 3 (`checkpoint:human-verify`) — **PENDING** operator execution on live hardware.

## Files Created/Modified

- `scripts/proxmox/cloud-init-user-data.yaml` — shared cloud-init template; 61 lines; sets Pitfall 3 prerequisites
- `scripts/proxmox/create-elastic-vm.sh` — elastic-vm qm create script; 201 lines; locked to 10.0.0.10/14336 MiB/200 GB
- `scripts/proxmox/create-caldera-vm.sh` — caldera-vm qm create script; 218 lines; locked to 10.0.0.20/6144 MiB/40 GB

## Decisions Made

- Shared cloud-init template for both VMs: the vm.max_map_count and nofile settings are no-ops on caldera-vm but eliminate a likely Plan 03 failure mode on elastic-vm. One template, two VMs.
- Applied vm.max_map_count both transiently (`sysctl -w`) and persistently (`sysctl.d`): the `runcmd` in cloud-init runs once at first boot; the sysctl.d file ensures the setting survives reboots.
- `DISK_VOLID` as `${STORAGE}:vm-${VMID}-disk-0` after `qm importdisk`: this is the standard Proxmox naming convention for LVM-thin volumes after disk import.

## Deviations from Plan

None — plan executed exactly as written. All three files created per the `artifacts` spec in the plan frontmatter.

## Issues Encountered

None.

## Checkpoint Status (Task 3)

**PENDING** — Task 3 is `type="checkpoint:human-verify"`. The operator must:

On Host 1:
1. Place Ubuntu 22.04 cloud image, then run `bash scripts/proxmox/create-elastic-vm.sh <VMID> <LAN_GW> <STORAGE> <CLOUD_IMAGE> <SSH_KEYFILE>`
2. `qm start <VMID>`; confirm `qm config <VMID>` shows memory 14336, 200G disk on local-lvm, net0 on vmbr0, agent=1
3. SSH to 10.0.0.10; run `sysctl vm.max_map_count` (must be 262144)

On Host 6:
4. Run `bash scripts/proxmox/create-caldera-vm.sh <VMID> <LAN_GW> <STORAGE> <CLOUD_IMAGE> <SSH_KEYFILE>`; `qm start <VMID>`
5. Confirm `qm config` shows memory 6144, 40G disk, net0 on vmbr0; SSH to 10.0.0.20 succeeds

Resume signal: type "approved" once both VMs boot, show correct specs, and are SSH-reachable.

## Threat Surface Scan

No new network endpoints introduced by the scripts themselves — they run locally on the Proxmox host via SSH. The VMs they create will have:
- SSH on port 22 (key-only, no password auth via cloud-init `ssh_pwauth: false`) — T-1-cfg mitigated
- No internet-exposed ports: both VMs are on vmbr0 (10.0.0.0/24) MGMT only, no vmbr1 NIC (T-1-02pre, T-1-04pre mitigated)
- Only Ubuntu-archive packages installed via cloud-init (T-1-SC accepted per threat model)

No credentials hardcoded in any script. SSH key is operator-supplied at runtime.

No threat flags to report.

## Known Stubs

None. Scripts are complete and functional. The operator-specific variables (VMID, LAN_GW, STORAGE, CLOUD_IMAGE, SSH_KEYFILE) are runtime parameters, not stubs — they must be supplied by the operator on live hardware.

## Self-Check

Checking files exist and commits are present:

- [x] `scripts/proxmox/cloud-init-user-data.yaml` — commit `795fd39`
- [x] `scripts/proxmox/create-elastic-vm.sh` — commit `795fd39`
- [x] `scripts/proxmox/create-caldera-vm.sh` — commit `d5985e3`

## Self-Check: PASSED

All 3 required files created, 2 task commits exist, no unexpected deletions.

## Next Phase Readiness

- All 3 scripts ready for operator execution on live hardware
- Task 3 checkpoint awaits hardware confirmation (both VMs booted + SSH-reachable)
- Plan 03 requires elastic-vm reachable at 10.0.0.10 with vm.max_map_count=262144
- Plan 04 requires caldera-vm reachable at 10.0.0.20

---
*Phase: 01-proxmox-foundation-siem-node*
*Completed: 2026-06-18*
