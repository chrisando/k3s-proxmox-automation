#!/usr/bin/env bash
# create-template.sh — Proxmox Debian 13 cloud-init template helper
#
# Run this script ON the Proxmox host (or via SSH) before running terraform apply.
# It downloads the Debian 13 genericcloud image, creates a VM, attaches a cloud-init
# drive, and converts it to a template.
#
# Environment variables (all optional, defaults shown):
#   TEMPLATE_VM_ID   VM ID for the template            (default: 9000)
#   TEMPLATE_NAME    VM name for the template           (default: debian-13-cloudimg)
#   STORAGE_POOL     Proxmox storage pool for the disk  (default: local-lvm)
#   PROXMOX_NODE     Proxmox node name                  (default: pve)
#   DEBIAN_IMAGE_URL URL to Debian 13 genericcloud img  (default: official URL)
#   IMAGE_CACHE_DIR  Local dir to cache downloaded image (default: /var/tmp)

set -euo pipefail

TEMPLATE_VM_ID="${TEMPLATE_VM_ID:-9000}"
TEMPLATE_NAME="${TEMPLATE_NAME:-debian-13-cloudimg}"
STORAGE_POOL="${STORAGE_POOL:-fast}"
PROXMOX_NODE="${PROXMOX_NODE:-pve1}"
IMAGE_CACHE_DIR="${IMAGE_CACHE_DIR:-/var/tmp}"

# Debian 13 "Trixie" genericcloud image — update URL when stable releases arrive
DEBIAN_IMAGE_URL="${DEBIAN_IMAGE_URL:-https://cloud.debian.org/images/cloud/trixie/daily/latest/debian-13-genericcloud-amd64-daily.qcow2}"
IMAGE_FILE="${IMAGE_CACHE_DIR}/$(basename "${DEBIAN_IMAGE_URL}")"

# ── Prerequisites ──────────────────────────────────────────────────────────────

for cmd in qm wget virt-customize; do
  if ! command -v "${cmd}" &>/dev/null; then
    echo "ERROR: '${cmd}' is not installed or not in PATH." >&2
    [[ "${cmd}" == "virt-customize" ]] && echo "  Install with: apt-get install libguestfs-tools" >&2
    exit 1
  fi
done

# ── Check for existing template ────────────────────────────────────────────────

if qm status "${TEMPLATE_VM_ID}" &>/dev/null; then
  echo "WARNING: VM ${TEMPLATE_VM_ID} already exists."
  read -r -p "Destroy it and recreate? [y/N] " answer
  if [[ "${answer,,}" == "y" ]]; then
    qm destroy "${TEMPLATE_VM_ID}" --purge
  else
    echo "Aborted."
    exit 0
  fi
fi

# ── Download image ─────────────────────────────────────────────────────────────

if [[ ! -f "${IMAGE_FILE}" ]]; then
  echo "Downloading Debian 13 cloud image..."
  wget -q --show-progress -O "${IMAGE_FILE}" "${DEBIAN_IMAGE_URL}"
else
  echo "Using cached image: ${IMAGE_FILE}"
fi

# ── Inject qemu-guest-agent into image ────────────────────────────────────────

echo "Installing qemu-guest-agent into image (requires libguestfs-tools)..."
virt-customize \
  -a "${IMAGE_FILE}" \
  --install qemu-guest-agent \
  --run-command 'systemctl enable qemu-guest-agent' \
  --truncate /etc/machine-id

# ── Create VM ─────────────────────────────────────────────────────────────────

echo "Creating VM ${TEMPLATE_VM_ID} (${TEMPLATE_NAME})..."
qm create "${TEMPLATE_VM_ID}" \
  --name "${TEMPLATE_NAME}" \
  #--node "${PROXMOX_NODE}"
  --memory 2048 \
  --cores 2 \
  --cpu host \
  --net0 virtio,bridge=vmbr0 \
  --ostype l26 \
  --agent enabled=1,fstrim_cloned_disks=1 \
  --serial0 socket \
  --vga serial0

# ── Import disk ───────────────────────────────────────────────────────────────

echo "Importing disk to ${STORAGE_POOL}..."
qm importdisk "${TEMPLATE_VM_ID}" "${IMAGE_FILE}" "${STORAGE_POOL}"
qm set "${TEMPLATE_VM_ID}" \
  --virtio0 "${STORAGE_POOL}:vm-${TEMPLATE_VM_ID}-disk-0,discard=on,iothread=1" \
  --boot order=virtio0 \
  --scsihw virtio-scsi-single

# ── Add cloud-init drive ──────────────────────────────────────────────────────

echo "Adding cloud-init drive..."
qm set "${TEMPLATE_VM_ID}" --ide2 "${STORAGE_POOL}:cloudinit"
qm set "${TEMPLATE_VM_ID}" --citype nocloud

# ── Convert to template ───────────────────────────────────────────────────────

echo "Converting to template..."
qm template "${TEMPLATE_VM_ID}"

echo ""
echo "Done! Template ${TEMPLATE_VM_ID} (${TEMPLATE_NAME}) is ready."
echo "Set template_vm_id = ${TEMPLATE_VM_ID} in your terraform.tfvars."
