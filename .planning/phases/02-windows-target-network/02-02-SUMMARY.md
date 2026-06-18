---
phase: 02-windows-target-network
plan: "02"
subsystem: windows-provisioning
tags: [proxmox, vm-provisioning, unattend-iso, winrm, qm-create, genisoimage]
dependency_graph:
  requires:
    - 02-01-SUMMARY.md (autounattend XMLs in scripts/windows/autounattend/ + .planning/secrets/)
  provides:
    - scripts/proxmox/build-unattend-isos.sh — packages operator-filled XMLs into 5 bootable unattend ISOs
    - scripts/proxmox/provision-windows.sh — qm create commands for all 5 Windows VMs per locked D-NEW-09 specs
    - 5 Windows VMs running on Proxmox hosts 2/3/4 with WinRM responding on 10.0.0.11-15
  affects:
    - Phase 2 Plans 03-07 (all require WinRM on 10.0.0.11-15 for PowerShell remoting)
    - Phase 3 (Elastic Agent enrollment runs over this WinRM channel)
tech_stack:
  added:
    - "Proxmox qm CLI — VM creation with dual NIC, triple ISO mount, SATA disk, VirtIO drivers"
    - "genisoimage — Linux tool for building bootable ISO-9660 images from per-VM unattend XML"
    - "Windows Unattended Setup — autounattend.xml consumed at install time via second CD-ROM (ide2)"
  patterns:
    - "Per-host execution pattern: provision-windows.sh takes HOST_NUMBER arg (2/3/4); run once per Proxmox host via SSH"
    - "Triple ISO mount: ide0=Windows eval ISO, ide2=unattend ISO, ide3=virtio-win.iso; SATA disk (no VirtIO driver needed at install)"
    - "ISO filename contract: WS2019-eval.iso and Win10-eval.iso — operator renames downloaded ISO before running"
    - "D-10 exclusion guard: VMID range check blocks accidental operations on elastic-vm (10x range) or caldera-vm (20x range)"
    - "Unattend ISO detach protocol: qm set <VMID> --delete ide2 --delete ide3 --delete cdrom after OS install"
key_files:
  created:
    - scripts/proxmox/build-unattend-isos.sh
    - scripts/proxmox/provision-windows.sh
  modified: []
decisions:
  - "Scripts read operator-filled XMLs from .planning/secrets/ (not scripts/windows/autounattend/ templates with OPERATOR_SETS_PASSWORD placeholder) — build-unattend-isos.sh dies with a clear message if any XML is missing from secrets/"
  - "provision-windows.sh scoped per Proxmox host (arg: 2, 3, or 4) — mirrors how the operator actually works: SSH to each host and run once"
  - "STORAGE variable defaults to local-lvm and is overridable as second argument — supports operators with different Proxmox storage pool names"
  - "Prerequisite ISO check before qm create: script dies listing exact missing filenames and download URLs — prevents partial VM creation"
  - "Confirmation prompt before qm create matches Phase 1 pattern from create-elastic-vm.sh — operator reviews VM table before committing"
metrics:
  duration_minutes: 30
  tasks_completed: 3
  tasks_total: 3
  files_created: 2
  files_modified: 0
  completed_date: "2026-06-18"
---

# Phase 2 Plan 02: Proxmox Windows VM Provisioning Scripts Summary

**One-liner:** build-unattend-isos.sh (genisoimage wrapper for 5 per-VM unattend ISOs from .planning/secrets/) and provision-windows.sh (qm create for dc01/exchange01/sql01/ws01/ws02 with dual NIC and triple ISO mount), executed by operator on Proxmox hosts — all 5 Windows VMs running with WinRM responding on 10.0.0.11-15.

## What Was Built

### Task 1: build-unattend-isos.sh

`scripts/proxmox/build-unattend-isos.sh` (167 lines) — run once on the Proxmox host with access to `.planning/secrets/`.

Script flow:
1. Prerequisite check: `command -v genisoimage` — dies with `apt-get install -y genisoimage` hint if missing
2. SECRETS_DIR variable: defaults to `$(dirname "$0")/../../.planning/secrets`; overridable as first argument
3. For each of 5 VMs (dc01, exchange01, sql01, ws01, ws02):
   - File-existence check: verifies `${SECRETS_DIR}/<name>-autounattend.xml` exists; dies with message directing operator to fill in `.planning/secrets/` copies
   - Stages XML into `/tmp/unattend-<name>/autounattend.xml`
   - Calls `genisoimage -o /var/lib/vz/template/iso/unattend-<name>.iso -J -r /tmp/unattend-<name>/`
   - Cleans up temp dir
4. Prints summary of all 5 ISO paths produced

The script reads from `.planning/secrets/` (operator-filled passwords), never from `scripts/windows/autounattend/` templates (which contain `OPERATOR_SETS_PASSWORD` placeholder).

### Task 2: provision-windows.sh

`scripts/proxmox/provision-windows.sh` (328 lines) — run once per Proxmox host.

Usage: `bash provision-windows.sh <HOST_NUMBER> [STORAGE_POOL]`

| VM | VMID | Host | RAM | Disk | TARGET IP | MGMT IP |
|----|------|------|-----|------|-----------|---------|
| dc01 | 201 | 2 | 4096 MB | 60G | 10.10.10.10 | 10.0.0.11 |
| sql01 | 202 | 2 | 5120 MB | 80G | 10.10.10.30 | 10.0.0.13 |
| exchange01 | 301 | 3 | 10240 MB | 120G | 10.10.10.20 | 10.0.0.12 |
| ws01 | 401 | 4 | 4096 MB | 60G | 10.10.10.40 | 10.0.0.14 |
| ws02 | 402 | 4 | 4096 MB | 60G | 10.10.10.50 | 10.0.0.15 |

Every `qm create` call includes:
- `--machine pc --bios seabios --ostype win10 --scsihw virtio-scsi-single`
- `--sata0 ${STORAGE}:${DISK_GB},cache=writeback` (no VirtIO driver at install time)
- `--cdrom local:iso/<WS2019-eval.iso or Win10-eval.iso>` (ide0)
- `--ide2 local:iso/unattend-<name>.iso,media=cdrom` (per-VM unattend ISO)
- `--ide3 local:iso/virtio-win.iso,media=cdrom` (VirtIO drivers for post-install NetKVM)
- `--net0 virtio,bridge=vmbr1` (TARGET NIC, 10.10.10.0/24)
- `--net1 virtio,bridge=vmbr0` (MGMT NIC, 10.0.0.0/24)
- `--agent 1 --boot order=sata0 --onboot 0`

Script safety features:
- ISO existence check before any `qm create` — dies listing missing filenames and download URLs
- VMID range guard: warns if any VMID falls in 100-200 range (elastic-vm / caldera-vm zone)
- Confirmation prompt: shows VM table with specs before proceeding
- "Next steps" footer with qm start commands, install monitoring instructions, WinRM test commands, and ISO detach commands

### Task 3: Hardware Checkpoint — Operator Execution

Operator executed the following steps on physical Proxmox hardware:

1. Downloaded Windows Server 2019 Evaluation ISO and Windows 10 Enterprise Evaluation ISO from Microsoft Evaluation Center
2. Downloaded virtio-win.iso from Fedora People stable virtio downloads
3. Placed all ISOs in `/var/lib/vz/template/iso/` on respective Proxmox hosts
4. Filled in `.planning/secrets/PASSWORDS.md` with actual Administrator and domain user passwords
5. Copied 5 autounattend XMLs from `scripts/windows/autounattend/` to `.planning/secrets/`, substituting `OPERATOR_SETS_PASSWORD` with real passwords
6. Ran `bash build-unattend-isos.sh` — produced 5 unattend ISOs in Proxmox ISO storage
7. SSH'd to each Proxmox host (2, 3, 4) and ran `bash provision-windows.sh <HOST_NUMBER>` — created 5 VMs
8. Started VMs, waited ~15-20 min per VM for Windows Setup to complete and reboot

**Outcome:** All 5 Windows VMs booted, ran autounattend.xml unattended setup including 5-command WinRM bootstrap, and rebooted to desktop. WinRM confirmed responding:

| VM | MGMT IP | WinRM Status |
|----|---------|-------------|
| dc01 | 10.0.0.11 | Responding |
| exchange01 | 10.0.0.12 | Responding |
| sql01 | 10.0.0.13 | Responding |
| ws01 | 10.0.0.14 | Responding |
| ws02 | 10.0.0.15 | Responding |

VMs are running but not yet domain-joined — ready for Plan 03 (DC promotion).

## Deviations from Plan

None — plan executed exactly as written. Both scripts passed all automated verification checks (bash -n syntax, grep checks for vmbr0/vmbr1/ide2/virtio-win.iso/all 5 VMIDs). Operator confirmed full WinRM availability before checkpoint approval.

## Threat Surface Scan

All plan threat model mitigations applied:

| Threat | Mitigation Applied |
|--------|--------------------|
| T-02-04: provision-windows.sh accidentally touches elastic-vm/caldera-vm | VMID range guard included in provision-windows.sh — warns if VMID 100-200 range |
| T-02-05: unattend ISOs remaining mounted after OS install expose passwords | "Next steps" section in provision-windows.sh explicitly instructs `qm set <VMID> --delete ide2 --delete ide3 --delete cdrom` |
| T-02-06: Wrong ISO filename causes VM to boot without autounattend | Both scripts include existence checks before building ISOs or creating VMs |

No new threat surface introduced beyond the plan's threat model.

## Known Stubs

None. Both scripts are complete and functional. All 5 VMs are running with WinRM active.

## Self-Check

### Files Created

- [x] scripts/proxmox/build-unattend-isos.sh — FOUND (committed 24befb2)
- [x] scripts/proxmox/provision-windows.sh — FOUND (committed 0d85964)
- [x] .planning/phases/02-windows-target-network/02-02-SUMMARY.md — this file

### Commits

- [x] 24befb2 — feat(02-02): create build-unattend-isos.sh for packaging autounattend XMLs
- [x] 0d85964 — feat(02-02): create provision-windows.sh for all 5 Windows target VMs

## Self-Check: PASSED
