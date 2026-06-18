#!/usr/bin/env bash
# =============================================================================
# provision-windows.sh — Create Windows target VMs on Proxmox Hosts 2, 3, 4
#
# LOCKED SPECS (do NOT change without updating D-NEW-09 in Phase 1 CONTEXT.md):
#
#  VM          Host  VMID  RAM (MiB)  Disk   TARGET IP     MGMT IP
#  dc01        2     201   4096       60G    10.10.10.10   10.0.0.11
#  sql01       2     202   5120       80G    10.10.10.30   10.0.0.13
#  exchange01  3     301   10240      120G   10.10.10.20   10.0.0.12
#  ws01        4     401   4096       60G    10.10.10.40   10.0.0.14
#  ws02        4     402   4096       60G    10.10.10.50   10.0.0.15
#
# NIC CONVENTION (established Phase 1 CONTEXT.md):
#   net0 = vmbr1 (TARGET 10.10.10.0/24) — emulation traffic
#   net1 = vmbr0 (MGMT  10.0.0.0/24)   — WinRM + Elastic Agent enrollment
#
# ISO FILENAMES (rename downloaded ISOs to match before running this script):
#   WS2019-eval.iso   — Windows Server 2019 Evaluation (Build 17763, 64-bit)
#                       Download: https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2019
#   Win10-eval.iso    — Windows 10 Enterprise Evaluation (Build 19042, 64-bit)
#                       Download: https://www.microsoft.com/en-us/evalcenter/evaluate-windows-10-enterprise
#   virtio-win.iso    — VirtIO drivers (NetKVM, Balloon, QEMU Guest Agent)
#                       Download: https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso
#
# All ISOs must be in /var/lib/vz/template/iso/ on the target Proxmox host.
# Unattend ISOs (unattend-dc01.iso, etc.) must be built first via:
#   bash build-unattend-isos.sh
#
# D-10 GUARD:
#   elastic-vm (100-200 VMID range) and caldera-vm are NEVER modified here.
#   This script only CREATES VMs. A VMID range check (< 201) is included as
#   a safety net. Do NOT add VMIDs below 201 to this script.
#
# USAGE:
#   bash provision-windows.sh <HOST_NUMBER> [STORAGE]
#
# ARGUMENTS:
#   HOST_NUMBER   Proxmox host number: 2, 3, or 4
#                 2 → creates dc01 (VMID 201) + sql01 (VMID 202)
#                 3 → creates exchange01 (VMID 301)
#                 4 → creates ws01 (VMID 401) + ws02 (VMID 402)
#   STORAGE       (optional) Proxmox storage name. Default: local-lvm
#
# EXAMPLE:
#   # On Host 2:  ssh root@host2 && bash provision-windows.sh 2
#   # On Host 3:  ssh root@host3 && bash provision-windows.sh 3
#   # On Host 4:  ssh root@host4 && bash provision-windows.sh 4
#   # Custom storage:
#   bash provision-windows.sh 2 zfs-pool
#
# PREREQUISITES:
#   - Run build-unattend-isos.sh first to produce the 5 unattend ISOs
#   - All required ISOs present in /var/lib/vz/template/iso/ (checked below)
#   - vmbr0 (MGMT) and vmbr1 (TARGET) bridges configured on this host
#     (Phase 1 Plan 01 network-setup.sh complete on this host)
# =============================================================================

set -euo pipefail

# --- Helper functions --------------------------------------------------------
log()  { echo "[provision-windows] $*"; }
die()  { echo "[provision-windows] FATAL: $*" >&2; exit 1; }
warn() { echo "[provision-windows] WARNING: $*" >&2; }

# --- Argument validation -----------------------------------------------------
if [[ $# -lt 1 ]]; then
  echo "ERROR: Missing HOST_NUMBER argument." >&2
  echo "Usage: $0 <HOST_NUMBER> [STORAGE]" >&2
  echo "" >&2
  echo "  HOST_NUMBER   2  →  dc01 (201) + sql01 (202)" >&2
  echo "                3  →  exchange01 (301)" >&2
  echo "                4  →  ws01 (401) + ws02 (402)" >&2
  echo "  STORAGE       Proxmox storage name (default: local-lvm)" >&2
  exit 1
fi

HOST_NUMBER="$1"
STORAGE="${2:-local-lvm}"

if [[ "$HOST_NUMBER" != "2" && "$HOST_NUMBER" != "3" && "$HOST_NUMBER" != "4" ]]; then
  die "HOST_NUMBER must be 2, 3, or 4. Got: '${HOST_NUMBER}'"
fi

ISO_DIR="/var/lib/vz/template/iso"

# --- D-10 safety check: refuse VMIDs in the elastic-vm / caldera-vm range ---
check_vmid_safe() {
  local vmid="$1"
  local name="$2"
  if [[ "$vmid" -lt 201 ]]; then
    die "VMID ${vmid} (${name}) is in the elastic-vm/caldera-vm range (< 201). (D-10)
  Never use VMIDs below 201 for Windows target VMs. Check D-NEW-09 in Phase 1 CONTEXT.md."
  fi
}

# --- ISO existence check function -------------------------------------------
require_iso() {
  local iso_name="$1"
  local download_url="$2"
  if [[ ! -f "${ISO_DIR}/${iso_name}" ]]; then
    echo "  MISSING: ${ISO_DIR}/${iso_name}" >&2
    echo "    Download: ${download_url}" >&2
    return 1
  fi
  return 0
}

# --- create_win_vm() — core VM creation function ----------------------------
# Args: VMID NAME MEM DISK_GB WIN_ISO UNATTEND_ISO
create_win_vm() {
  local VMID="$1"
  local NAME="$2"
  local MEM="$3"
  local DISK_GB="$4"
  local WIN_ISO="$5"
  local UNATTEND_ISO="$6"

  # D-10 guard: refuse VMIDs in elastic-vm / caldera-vm range
  check_vmid_safe "${VMID}" "${NAME}"

  log "[Creating] ${NAME} (VMID ${VMID}, ${MEM} MiB RAM, ${DISK_GB}G disk)"

  qm create "${VMID}" \
    --name "${NAME}" \
    --memory "${MEM}" \
    --cores 2 \
    --machine pc \
    --bios seabios \
    --ostype win10 \
    --scsihw virtio-scsi-single \
    --sata0 "${STORAGE}:${DISK_GB},cache=writeback" \
    --cdrom "local:iso/${WIN_ISO}" \
    --ide2 "local:iso/${UNATTEND_ISO},media=cdrom" \
    --ide3 "local:iso/virtio-win.iso,media=cdrom" \
    --net0 "virtio,bridge=vmbr1" \
    --net1 "virtio,bridge=vmbr0" \
    --agent 1 \
    --boot "order=sata0" \
    --onboot 0

  log "${NAME} (VMID ${VMID}) created."
}

# --- Determine VMs for this host and check required ISOs --------------------
MISSING_ISOS=0

case "${HOST_NUMBER}" in
  2)
    # --- ISO pre-flight for Host 2 ---
    log "Checking required ISOs for Host 2 (dc01, sql01)..."
    require_iso "WS2019-eval.iso" \
      "https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2019" \
      || MISSING_ISOS=$((MISSING_ISOS + 1))
    require_iso "unattend-dc01.iso" \
      "Run: bash build-unattend-isos.sh (on the host with .planning/secrets/)" \
      || MISSING_ISOS=$((MISSING_ISOS + 1))
    require_iso "unattend-sql01.iso" \
      "Run: bash build-unattend-isos.sh (on the host with .planning/secrets/)" \
      || MISSING_ISOS=$((MISSING_ISOS + 1))
    require_iso "virtio-win.iso" \
      "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso" \
      || MISSING_ISOS=$((MISSING_ISOS + 1))
    ;;
  3)
    # --- ISO pre-flight for Host 3 ---
    log "Checking required ISOs for Host 3 (exchange01)..."
    require_iso "WS2019-eval.iso" \
      "https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2019" \
      || MISSING_ISOS=$((MISSING_ISOS + 1))
    require_iso "unattend-exchange01.iso" \
      "Run: bash build-unattend-isos.sh (on the host with .planning/secrets/)" \
      || MISSING_ISOS=$((MISSING_ISOS + 1))
    require_iso "virtio-win.iso" \
      "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso" \
      || MISSING_ISOS=$((MISSING_ISOS + 1))
    ;;
  4)
    # --- ISO pre-flight for Host 4 ---
    log "Checking required ISOs for Host 4 (ws01, ws02)..."
    require_iso "Win10-eval.iso" \
      "https://www.microsoft.com/en-us/evalcenter/evaluate-windows-10-enterprise" \
      || MISSING_ISOS=$((MISSING_ISOS + 1))
    require_iso "unattend-ws01.iso" \
      "Run: bash build-unattend-isos.sh (on the host with .planning/secrets/)" \
      || MISSING_ISOS=$((MISSING_ISOS + 1))
    require_iso "unattend-ws02.iso" \
      "Run: bash build-unattend-isos.sh (on the host with .planning/secrets/)" \
      || MISSING_ISOS=$((MISSING_ISOS + 1))
    require_iso "virtio-win.iso" \
      "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso" \
      || MISSING_ISOS=$((MISSING_ISOS + 1))
    ;;
esac

if [[ "${MISSING_ISOS}" -gt 0 ]]; then
  echo "" >&2
  die "${MISSING_ISOS} required ISO(s) are missing from ${ISO_DIR}/.
  Download and place them there before running this script.
  See PREREQUISITES in the script header for download URLs and filename conventions."
fi

log "All required ISOs present."
echo ""

# --- Confirmation prompt: show all VMs to be created with their specs --------
echo "============================================================"
echo " provision-windows.sh — Host ${HOST_NUMBER} VM creation"
echo "============================================================"
echo "  STORAGE    : ${STORAGE}"
echo "  ISO DIR    : ${ISO_DIR}"
echo ""

case "${HOST_NUMBER}" in
  2)
    echo "  VMs to CREATE on Host 2:"
    echo "    VMID 201  dc01        4096 MiB  60G   WS2019-eval.iso  unattend-dc01.iso"
    echo "    VMID 202  sql01       5120 MiB  80G   WS2019-eval.iso  unattend-sql01.iso"
    echo ""
    echo "  TARGET NIC (net0): vmbr1  (dc01: 10.10.10.10 | sql01: 10.10.10.30)"
    echo "  MGMT NIC   (net1): vmbr0  (dc01: 10.0.0.11   | sql01: 10.0.0.13)"
    ;;
  3)
    echo "  VMs to CREATE on Host 3:"
    echo "    VMID 301  exchange01  10240 MiB  120G  WS2019-eval.iso  unattend-exchange01.iso"
    echo ""
    echo "  TARGET NIC (net0): vmbr1  (exchange01: 10.10.10.20)"
    echo "  MGMT NIC   (net1): vmbr0  (exchange01: 10.0.0.12)"
    ;;
  4)
    echo "  VMs to CREATE on Host 4:"
    echo "    VMID 401  ws01        4096 MiB  60G   Win10-eval.iso   unattend-ws01.iso"
    echo "    VMID 402  ws02        4096 MiB  60G   Win10-eval.iso   unattend-ws02.iso"
    echo ""
    echo "  TARGET NIC (net0): vmbr1  (ws01: 10.10.10.40 | ws02: 10.10.10.50)"
    echo "  MGMT NIC   (net1): vmbr0  (ws01: 10.0.0.14   | ws02: 10.0.0.15)"
    ;;
esac

echo "------------------------------------------------------------"
read -r -p "Proceed? [y/N] " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Aborted."
  exit 0
fi
echo ""

# --- Create VMs for this host -----------------------------------------------
case "${HOST_NUMBER}" in
  2)
    echo "[1/2] Creating dc01..."
    create_win_vm 201 "dc01" 4096 60 "WS2019-eval.iso" "unattend-dc01.iso"

    echo "[2/2] Creating sql01..."
    create_win_vm 202 "sql01" 5120 80 "WS2019-eval.iso" "unattend-sql01.iso"
    ;;
  3)
    echo "[1/1] Creating exchange01..."
    create_win_vm 301 "exchange01" 10240 120 "WS2019-eval.iso" "unattend-exchange01.iso"
    ;;
  4)
    echo "[1/2] Creating ws01..."
    create_win_vm 401 "ws01" 4096 60 "Win10-eval.iso" "unattend-ws01.iso"

    echo "[2/2] Creating ws02..."
    create_win_vm 402 "ws02" 4096 60 "Win10-eval.iso" "unattend-ws02.iso"
    ;;
esac

# --- Summary and next steps --------------------------------------------------
echo ""
echo "============================================================"
echo " Host ${HOST_NUMBER} — Windows VMs created successfully"
echo "============================================================"

case "${HOST_NUMBER}" in
  2)
    echo "  VMID 201  dc01        ready"
    echo "  VMID 202  sql01       ready"
    echo ""
    echo "Next steps (Host 2):"
    echo "  1. Start VMs:"
    echo "       qm start 201 && qm start 202"
    echo "  2. Monitor OS install via Proxmox console (~15-20 min per VM):"
    echo "       qm monitor 201   (Ctrl-O to detach)"
    echo "       qm monitor 202"
    echo "  3. After VMs reboot post-install, test WinRM from MGMT subnet:"
    echo "       pwsh -c \"Test-WSMan -ComputerName 10.0.0.11\"   # dc01"
    echo "       pwsh -c \"Test-WSMan -ComputerName 10.0.0.13\"   # sql01"
    echo "  4. Detach install ISOs (SECURITY — removes plaintext password exposure):"
    echo "       qm set 201 --delete ide2 --delete ide3 --delete cdrom"
    echo "       qm set 202 --delete ide2 --delete ide3 --delete cdrom"
    ;;
  3)
    echo "  VMID 301  exchange01  ready"
    echo ""
    echo "Next steps (Host 3):"
    echo "  1. Start VM:"
    echo "       qm start 301"
    echo "  2. Monitor OS install via Proxmox console (~15-20 min):"
    echo "       qm monitor 301   (Ctrl-O to detach)"
    echo "  3. After VM reboots post-install, test WinRM from MGMT subnet:"
    echo "       pwsh -c \"Test-WSMan -ComputerName 10.0.0.12\"   # exchange01"
    echo "  4. Detach install ISOs (SECURITY — removes plaintext password exposure):"
    echo "       qm set 301 --delete ide2 --delete ide3 --delete cdrom"
    ;;
  4)
    echo "  VMID 401  ws01  ready"
    echo "  VMID 402  ws02  ready"
    echo ""
    echo "Next steps (Host 4):"
    echo "  1. Start VMs:"
    echo "       qm start 401 && qm start 402"
    echo "  2. Monitor OS install via Proxmox console (~15-20 min per VM):"
    echo "       qm monitor 401   (Ctrl-O to detach)"
    echo "       qm monitor 402"
    echo "  3. After VMs reboot post-install, test WinRM from MGMT subnet:"
    echo "       pwsh -c \"Test-WSMan -ComputerName 10.0.0.14\"   # ws01"
    echo "       pwsh -c \"Test-WSMan -ComputerName 10.0.0.15\"   # ws02"
    echo "  4. Detach install ISOs (SECURITY — removes plaintext password exposure):"
    echo "       qm set 401 --delete ide2 --delete ide3 --delete cdrom"
    echo "       qm set 402 --delete ide2 --delete ide3 --delete cdrom"
    ;;
esac

echo ""
echo "After ALL 5 VMs across Hosts 2, 3, 4 are running and WinRM is reachable,"
echo "proceed to Plan 03 (DC promotion and domain join via PowerShell over WinRM)."
