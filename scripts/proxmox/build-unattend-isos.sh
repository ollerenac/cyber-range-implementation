#!/usr/bin/env bash
# =============================================================================
# build-unattend-isos.sh — Package per-VM autounattend XMLs into bootable ISOs
#
# SOURCE DIR   : .planning/secrets/  (operator-filled XMLs with actual passwords)
#                NOT scripts/windows/autounattend/ (those are templates with
#                OPERATOR_SETS_PASSWORD token — NOT ready to use).
#
# OUTPUT DIR   : /var/lib/vz/template/iso/  (Proxmox ISO storage)
#
# ISOs PRODUCED:
#   unattend-dc01.iso        — for dc01  (VMID 201, Host 2)
#   unattend-exchange01.iso  — for exchange01 (VMID 301, Host 3)
#   unattend-sql01.iso       — for sql01 (VMID 202, Host 2)
#   unattend-ws01.iso        — for ws01  (VMID 401, Host 4)
#   unattend-ws02.iso        — for ws02  (VMID 402, Host 4)
#
# USAGE:
#   bash build-unattend-isos.sh [SECRETS_DIR]
#
# ARGUMENTS:
#   SECRETS_DIR   (optional) Path to directory containing *-autounattend.xml files.
#                 Default: <script_dir>/../../.planning/secrets
#
# EXAMPLE:
#   bash build-unattend-isos.sh
#   bash build-unattend-isos.sh /root/my-secrets
#
# PREREQUISITES:
#   - genisoimage installed:  apt-get install -y genisoimage
#   - Operator has COPIED the 5 autounattend XMLs from scripts/windows/autounattend/
#     into .planning/secrets/ and REPLACED the OPERATOR_SETS_PASSWORD token with
#     the actual Administrator password from .planning/secrets/PASSWORDS.md
#   - /var/lib/vz/template/iso/ exists (standard Proxmox ISO storage path)
#
# SECURITY NOTE:
#   The XMLs in .planning/secrets/ contain plaintext Administrator passwords.
#   .planning/ is gitignored. Never copy these files to a public location.
#   Detach the unattend ISOs from VMs immediately after OS install completes:
#     qm set <VMID> --delete ide2
# =============================================================================

set -euo pipefail

# --- Helper functions --------------------------------------------------------
log()  { echo "[build-unattend-isos] $*"; }
die()  { echo "[build-unattend-isos] FATAL: $*" >&2; exit 1; }
warn() { echo "[build-unattend-isos] WARNING: $*" >&2; }

# --- Prerequisite check: genisoimage -----------------------------------------
command -v genisoimage >/dev/null 2>&1 \
  || die "genisoimage not found. Install with: apt-get install -y genisoimage"

# --- Resolve SECRETS_DIR -----------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_DIR="${1:-${SCRIPT_DIR}/../../.planning/secrets}"

# Resolve to absolute path
SECRETS_DIR="$(cd "${SECRETS_DIR}" 2>/dev/null && pwd)" \
  || die "SECRETS_DIR does not exist: ${1:-${SCRIPT_DIR}/../../.planning/secrets}
  Create the directory and copy the operator-filled autounattend XMLs there first."

ISO_DIR="/var/lib/vz/template/iso"

log "SECRETS_DIR : ${SECRETS_DIR}"
log "ISO_DIR     : ${ISO_DIR}"
echo ""

# --- Validate ISO output directory -------------------------------------------
if [[ ! -d "${ISO_DIR}" ]]; then
  die "Proxmox ISO storage directory not found: ${ISO_DIR}
  This script must run on a Proxmox host. If the path differs, create a symlink."
fi

# --- VM list: NAME → XML filename (same stem convention) ---------------------
declare -A VM_XML
VM_XML[dc01]="dc01-autounattend.xml"
VM_XML[exchange01]="exchange01-autounattend.xml"
VM_XML[sql01]="sql01-autounattend.xml"
VM_XML[ws01]="ws01-autounattend.xml"
VM_XML[ws02]="ws02-autounattend.xml"

VM_ORDER=(dc01 exchange01 sql01 ws01 ws02)
TOTAL=${#VM_ORDER[@]}

# --- Pre-flight: verify all XML source files exist ---------------------------
log "Checking that all autounattend XML source files are present..."
MISSING=()
for VM_NAME in "${VM_ORDER[@]}"; do
  XML_FILE="${SECRETS_DIR}/${VM_XML[$VM_NAME]}"
  if [[ ! -f "${XML_FILE}" ]]; then
    MISSING+=("${XML_FILE}")
  fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "" >&2
  echo "[build-unattend-isos] FATAL: Missing autounattend XML files in ${SECRETS_DIR}:" >&2
  for f in "${MISSING[@]}"; do
    echo "  MISSING: $f" >&2
  done
  echo "" >&2
  echo "  Steps to fix:" >&2
  echo "    1. Copy template XMLs from scripts/windows/autounattend/ to .planning/secrets/" >&2
  echo "    2. In each copy, replace OPERATOR_SETS_PASSWORD with the actual password" >&2
  echo "       (see .planning/secrets/PASSWORDS.md for the chosen password)" >&2
  echo "    3. Re-run this script." >&2
  echo "" >&2
  exit 1
fi

log "All ${TOTAL} autounattend XML files found."
echo ""

# --- Build one ISO per VM ----------------------------------------------------
STEP=0
for VM_NAME in "${VM_ORDER[@]}"; do
  STEP=$((STEP + 1))
  XML_SRC="${SECRETS_DIR}/${VM_XML[$VM_NAME]}"
  STAGING_DIR="/tmp/unattend-${VM_NAME}"
  OUT_ISO="${ISO_DIR}/unattend-${VM_NAME}.iso"

  echo "[${STEP}/${TOTAL}] Building unattend-${VM_NAME}.iso..."

  # Clean up any leftover staging dir from a previous failed run
  rm -rf "${STAGING_DIR}"
  mkdir -p "${STAGING_DIR}"

  # Stage autounattend.xml — Windows Setup looks for this exact filename
  cp "${XML_SRC}" "${STAGING_DIR}/autounattend.xml"

  # Build the ISO
  genisoimage \
    -o "${OUT_ISO}" \
    -J \
    -r \
    "${STAGING_DIR}/" \
    2>/dev/null

  # Clean up staging dir immediately
  rm -rf "${STAGING_DIR}"

  log "Built: ${OUT_ISO}"
done

# --- Summary -----------------------------------------------------------------
echo ""
echo "============================================================"
echo " All ${TOTAL} unattend ISOs built successfully"
echo "============================================================"
for VM_NAME in "${VM_ORDER[@]}"; do
  ISO_PATH="${ISO_DIR}/unattend-${VM_NAME}.iso"
  ISO_SIZE=$(du -sh "${ISO_PATH}" 2>/dev/null | cut -f1 || echo "?")
  echo "  ${ISO_SIZE}  ${ISO_PATH}"
done
echo ""
echo "Next steps:"
echo "  1. Run provision-windows.sh on each Proxmox host to create the VMs."
echo "     Each VM's qm create call mounts its unattend ISO as --ide2."
echo "  2. Start VMs and wait for OS installation to complete (~15-20 min each)."
echo "  3. After OS install and first reboot, DETACH the unattend ISOs:"
echo "     qm set 201 --delete ide2   # dc01"
echo "     qm set 202 --delete ide2   # sql01"
echo "     qm set 301 --delete ide2   # exchange01"
echo "     qm set 401 --delete ide2   # ws01"
echo "     qm set 402 --delete ide2   # ws02"
echo "  (Leaving unattend ISOs mounted exposes plaintext passwords to all VMs on the host.)"
