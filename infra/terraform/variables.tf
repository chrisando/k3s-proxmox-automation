# ── Proxmox connection ────────────────────────────────────────────────────────

variable "proxmox_endpoint" {
  description = "URL of the Proxmox API endpoint, e.g. https://pve.example.com:8006"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token in the form USER@REALM!TOKENID=SECRET"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Skip TLS verification for the Proxmox API (self-signed certs)"
  type        = bool
  default     = false
}

variable "proxmox_ssh_username" {
  description = "SSH username on the Proxmox host used by the bpg provider for provisioning tasks"
  type        = string
  default     = "root"
}

variable "proxmox_node" {
  description = "Proxmox node name to deploy VMs on"
  type        = string
  default     = "pve"
}

# ── Template ──────────────────────────────────────────────────────────────────

variable "template_vm_id" {
  description = "VM ID of the Debian 13 cloud-init template on Proxmox"
  type        = number
  default     = 9000
}

# ── Network ───────────────────────────────────────────────────────────────────

variable "network_bridge" {
  description = "Proxmox Linux bridge to attach VM NICs to"
  type        = string
  default     = "vmbr0"
}

variable "network_vlan" {
  description = "VLAN tag for VM NICs (null = untagged)"
  type        = number
  default     = null
}

variable "dns_servers" {
  description = "List of DNS server IPs passed via cloud-init"
  type        = list(string)
  default     = ["1.1.1.1", "2606:4700:4700::1111"]
}

variable "dns_domain" {
  description = "Search domain passed via cloud-init"
  type        = string
  default     = "local"
}

variable "ipv4_gateway" {
  description = "Default IPv4 gateway for all VMs"
  type        = string
  default     = "192.168.1.1"
}

variable "ipv6_gateway" {
  description = "Default IPv6 gateway for all VMs"
  type        = string
  default     = "2001:db8::1"
}

# ── Storage ───────────────────────────────────────────────────────────────────

variable "storage_pool" {
  description = "Proxmox storage pool for VM disks"
  type        = string
  default     = "fast"
}

# ── SSH ───────────────────────────────────────────────────────────────────────

variable "ssh_public_key" {
  description = "SSH public key injected into VMs via cloud-init"
  type        = string
}

variable "ssh_user" {
  description = "Default user created by cloud-init"
  type        = string
  default     = "debian"
}

# ── Controller ────────────────────────────────────────────────────────────────

variable "controller" {
  description = "Configuration for the k3s controller node"
  type = object({
    name      = string
    vm_id     = number
    ipv4_cidr = string # e.g. "192.168.1.10/24"
    ipv6_cidr = string # e.g. "2001:db8::10/64"
    cpu_cores = number
    memory_mb = number
    disk_gb   = number
  })
  default = {
    name      = "k3s-controller-01"
    vm_id     = 200
    ipv4_cidr = "192.168.1.10/24"
    ipv6_cidr = "2001:db8::10/64"
    cpu_cores = 8
    memory_mb = 16384
    disk_gb   = 200
  }
}

# ── Workers ───────────────────────────────────────────────────────────────────

variable "workers" {
  description = "Configuration for k3s worker nodes"
  type = list(object({
    name             = string
    vm_id            = number
    ipv4_cidr        = string
    ipv6_cidr        = string
    cpu_cores        = number
    memory_mb        = number
    disk_gb          = number
    data_disk_gb     = number # DirectPV raw disk (virtio1 → /dev/vdb)
    longhorn_disk_gb = number # Longhorn data disk, formatted XFS (virtio2 → /dev/vdc)
  }))
  default = [
    {
      name             = "k3s-worker-01"
      vm_id            = 201
      ipv4_cidr        = "192.168.1.11/24"
      ipv6_cidr        = "2001:db8::11/64"
      cpu_cores        = 16
      memory_mb        = 32768
      disk_gb          = 200
      data_disk_gb     = 512
      longhorn_disk_gb = 512
    },
    {
      name             = "k3s-worker-02"
      vm_id            = 202
      ipv4_cidr        = "192.168.1.12/24"
      ipv6_cidr        = "2001:db8::12/64"
      cpu_cores        = 16
      memory_mb        = 32768
      disk_gb          = 200
      data_disk_gb     = 512
      longhorn_disk_gb = 512
    },
    {
      name             = "k3s-worker-03"
      vm_id            = 203
      ipv4_cidr        = "192.168.1.13/24"
      ipv6_cidr        = "2001:db8::13/64"
      cpu_cores        = 16
      memory_mb        = 32768
      disk_gb          = 200
      data_disk_gb     = 512
      longhorn_disk_gb = 512
    },
  ]
}
