#!/usr/bin/env bash
# =============================================================================
# create-elastic-vm.sh — Provision elastic-vm on Host 1 (Proxmox)
#
# LOCKED SPECS (do NOT change without updating D-NEW-01, D-06, D-12):
#   IP:  10.0.0.10  *** LOCKED by D-12 — Fleet Server TLS cert SAN includes
#                   IP:10.0.0.10. Changing this IP after Plan 03 requires
#                   regenerating the CA and re-enrolling ALL Elastic Agents. ***
#   RAM: 14336 MiB  (14 GB — D-NEW-01; host: Host 1 dedicated to elastic-vm only)
#   Disk: 200 GB    (D-06 — sized for Elastic 8.19.16 stack: ES + Kibana + Fleet)
#   Cores: 4
#   Bridge: vmbr0   (MGMT only — no vmbr1 NIC; elastic-vm is NOT a target VM)
#
# ROLE: Persistent data sink — elastic-vm is NEVER snapshotted and NEVER
#       included in reset_range.sh (D-10). Elasticsearch + Kibana + Fleet
#       Server are installed here in Plan 03.
#
# USAGE:
#   bash create-elastic-vm.sh <VMID> <LAN_GW> <STORAGE> <CLOUD_IMAGE> <SSH_KEYFILE>
#
# ARGUMENTS:
#   VMID          Free VMID on Host 1 (operator-chosen; check `qm list`)
#   LAN_GW        LAN gateway for MGMT network (e.g. 10.0.0.1)
#   STORAGE       Proxmox LVM-thin storage name (typically: local-lvm)
#   CLOUD_IMAGE   Path to Ubuntu 22.04 cloud image on Host 1
#                 Download: https://cloud-images.ubuntu.com/jammy/current/
#                 File: jammy-server-cloudimg-amd64.img
#   SSH_KEYFILE   Path to operator SSH public key file (e.g. ~/.ssh/id_rsa.pub)
#
# EXAMPLE:
#   bash create-elastic-vm.sh 200 10.0.0.1 local-lvm \
#       /root/jammy-server-cloudimg-amd64.img /root/.ssh/id_rsa.pub
#
# PREREQUISITES:
#   - Host 1 has vmbr0 configured (Plan 01 complete)
#   - LVM-thin pool present on local-lvm (verify-storage.sh gate passed)
#   - Ubuntu 22.04 cloud image available at CLOUD_IMAGE path
#   - cloud-init-user-data.yaml uploaded to Proxmox snippets storage
#     (typically: /var/lib/vz/snippets/cloud-init-user-data.yaml)
#     Copy with: scp scripts/proxmox/cloud-init-user-data.yaml \
#                    root@host1:/var/lib/vz/snippets/
# =============================================================================

set -euo pipefail

# --- Argument validation -----------------------------------------------------
if [[ $# -lt 5 ]]; then
  echo "ERROR: Missing required arguments." >&2
  echo "Usage: $0 <VMID> <LAN_GW> <STORAGE> <CLOUD_IMAGE> <SSH_KEYFILE>" >&2
  echo "" >&2
  echo "  VMID        Free VMID on Host 1 (e.g. 200)" >&2
  echo "  LAN_GW      LAN gateway for MGMT (e.g. 10.0.0.1)" >&2
  echo "  STORAGE     LVM-thin storage name (e.g. local-lvm)" >&2
  echo "  CLOUD_IMAGE Path to Ubuntu 22.04 jammy cloud image" >&2
  echo "  SSH_KEYFILE Path to operator SSH public key file" >&2
  exit 1
fi

VMID="$1"
LAN_GW="$2"
STORAGE="$3"
CLOUD_IMAGE="$4"
SSH_KEYFILE="$5"

# --- Locked configuration (D-NEW-01, D-06, D-12, D-NEW-08) ------------------
VM_NAME="elastic-vm"
VM_MEMORY=14336          # 14 GB RAM (D-NEW-01 — Host 1 dedicated to elastic-vm)
VM_CORES=4
VM_DISK_SIZE="200G"      # D-06 — sized for ES 8.19.16 + Kibana + Fleet + corpus
VM_MGMT_IP="10.0.0.10"  # LOCKED D-12 — Fleet Server cert SAN bakes this IP
VM_CIDR="24"
VM_BRIDGE="vmbr0"        # MGMT bridge only — no vmbr1 NIC (D-02 / T-1-02pre)
SNIPPETS_DIR="/var/lib/vz/snippets"
CLOUD_INIT_FILE="cloud-init-user-data.yaml"
CI_USER="operator"

# --- Validate inputs ---------------------------------------------------------
if [[ -z "$VMID" ]] || ! [[ "$VMID" =~ ^[0-9]+$ ]]; then
  echo "ERROR: VMID must be a positive integer, got: '$VMID'" >&2
  exit 1
fi

if [[ -z "$LAN_GW" ]]; then
  echo "ERROR: LAN_GW cannot be empty (e.g. 10.0.0.1)" >&2
  exit 1
fi

if [[ ! -f "$CLOUD_IMAGE" ]]; then
  echo "ERROR: Cloud image not found at '$CLOUD_IMAGE'" >&2
  echo "  Download from: https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img" >&2
  exit 1
fi

if [[ ! -f "$SSH_KEYFILE" ]]; then
  echo "ERROR: SSH public key file not found at '$SSH_KEYFILE'" >&2
  exit 1
fi

if [[ ! -f "${SNIPPETS_DIR}/${CLOUD_INIT_FILE}" ]]; then
  echo "ERROR: cloud-init user-data not found at '${SNIPPETS_DIR}/${CLOUD_INIT_FILE}'" >&2
  echo "  Upload with: scp scripts/proxmox/cloud-init-user-data.yaml root@<host1>:${SNIPPETS_DIR}/" >&2
  exit 1
fi

# --- Confirm before proceeding -----------------------------------------------
echo "============================================================"
echo " Creating elastic-vm on Host 1"
echo "============================================================"
echo "  VMID       : $VMID"
echo "  Name       : $VM_NAME"
echo "  Memory     : ${VM_MEMORY} MiB (14 GB)"
echo "  Cores      : $VM_CORES"
echo "  Disk       : $VM_DISK_SIZE on $STORAGE (LVM-thin)"
echo "  MGMT IP    : ${VM_MGMT_IP}/${VM_CIDR} gw ${LAN_GW}  *** LOCKED D-12 ***"
echo "  Bridge     : $VM_BRIDGE (MGMT only)"
echo "  Agent      : enabled (QEMU guest agent)"
echo "  Cloud image: $CLOUD_IMAGE"
echo "  SSH key    : $SSH_KEYFILE"
echo "------------------------------------------------------------"
read -r -p "Proceed? [y/N] " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Aborted."
  exit 0
fi

# --- Create VM ---------------------------------------------------------------
echo "[1/7] Creating VM $VMID ($VM_NAME)..."
qm create "$VMID" \
  --name "$VM_NAME" \
  --memory "$VM_MEMORY" \
  --cores "$VM_CORES" \
  --cpu cputype=host \
  --net0 "virtio,bridge=${VM_BRIDGE}" \
  --ostype l26 \
  --agent 1 \
  --onboot 1 \
  --scsihw virtio-scsi-pci

# --- Import cloud image as boot disk -----------------------------------------
echo "[2/7] Importing cloud image as VM disk..."
qm importdisk "$VMID" "$CLOUD_IMAGE" "$STORAGE"

# --- Attach imported disk as scsi0 (boot disk) -------------------------------
echo "[3/7] Attaching disk as scsi0 (boot disk)..."
DISK_VOLID="${STORAGE}:vm-${VMID}-disk-0"
qm set "$VMID" \
  --scsi0 "${DISK_VOLID},discard=on,ssd=1" \
  --boot "order=scsi0" \
  --bootdisk scsi0

# --- Resize disk to 200 GB ---------------------------------------------------
echo "[4/7] Resizing disk to $VM_DISK_SIZE..."
qm resize "$VMID" scsi0 "$VM_DISK_SIZE"

# --- Add cloud-init drive ----------------------------------------------------
echo "[5/7] Adding cloud-init drive..."
qm set "$VMID" \
  --ide2 "${STORAGE}:cloudinit"

# --- Configure cloud-init (user, key, networking, custom user-data) ----------
echo "[6/7] Configuring cloud-init..."
qm set "$VMID" \
  --ciuser "$CI_USER" \
  --sshkeys "$SSH_KEYFILE" \
  --ipconfig0 "ip=${VM_MGMT_IP}/${VM_CIDR},gw=${LAN_GW}" \
  --nameserver "8.8.8.8" \
  --cicustom "user=local:snippets/${CLOUD_INIT_FILE}"

# --- Final VM settings -------------------------------------------------------
echo "[7/7] Applying final settings..."
qm set "$VMID" \
  --description "elastic-vm: Elasticsearch 8.19.16 + Kibana + Fleet Server.
MGMT IP: ${VM_MGMT_IP} (LOCKED D-12 — Fleet cert SAN).
Host: Host 1 (dedicated — no co-tenants per D-NEW-01).
NEVER snapshotted / NEVER in reset_range.sh (D-10).
RAM: ${VM_MEMORY} MiB (14 GB). Disk: ${VM_DISK_SIZE} on ${STORAGE}.
Plans: provisioned in 01-02, services installed in 01-03."

# --- Summary -----------------------------------------------------------------
echo ""
echo "============================================================"
echo " elastic-vm created successfully"
echo "============================================================"
echo "  VMID          : $VMID"
echo "  MGMT IP       : ${VM_MGMT_IP}/24  *** LOCKED D-12 ***"
echo "  RAM           : ${VM_MEMORY} MiB (14 GB)"
echo "  Disk          : ${VM_DISK_SIZE} on ${STORAGE}"
echo "  Bridge        : ${VM_BRIDGE} (MGMT only)"
echo ""
echo "Next steps:"
echo "  1. Start VM:       qm start $VMID"
echo "  2. Monitor boot:   qm monitor $VMID  (or Proxmox console)"
echo "  3. Wait ~60s for cloud-init, then SSH:"
echo "     ssh ${CI_USER}@${VM_MGMT_IP}"
echo "  4. Verify prereqs: sysctl vm.max_map_count  (must be 262144)"
echo "  5. Check config:   qm config $VMID"
echo "     Expect: memory: ${VM_MEMORY}, net0: bridge=${VM_BRIDGE}, agent: 1"
echo ""
echo "REMINDER: Do NOT change ${VM_MGMT_IP} — it is LOCKED by D-12."
echo "  Changing it requires regenerating the Fleet Server TLS cert"
echo "  and re-enrolling all Elastic Agents."
