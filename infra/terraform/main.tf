# ── Locals ────────────────────────────────────────────────────────────────────

locals {
  # Bare IPs extracted from CIDR notation — used by outputs.tf
  controller_ipv4 = split("/", var.controller.ipv4_cidr)[0]
  controller_ipv6 = split("/", var.controller.ipv6_cidr)[0]
  worker_ipv4s    = [for w in var.workers : split("/", w.ipv4_cidr)[0]]
  worker_ipv6s    = [for w in var.workers : split("/", w.ipv6_cidr)[0]]

  workers_map = { for w in var.workers : w.name => w }
}

# ── Controller VM ─────────────────────────────────────────────────────────────
# 1 disk: virtio0 — OS + container images

resource "proxmox_virtual_environment_vm" "controller" {
  name      = var.controller.name
  vm_id     = var.controller.vm_id
  node_name = var.proxmox_node
  on_boot   = true

  clone {
    vm_id   = var.template_vm_id
    full    = true
    retries = 3
  }

  agent {
    enabled = true
  }

  cpu {
    cores = var.controller.cpu_cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.controller.memory_mb
  }

  disk {
    interface    = "virtio0"
    datastore_id = var.storage_pool
    size         = var.controller.disk_gb
    discard      = "on"
    iothread     = true
  }

  network_device {
    bridge  = var.network_bridge
    vlan_id = var.network_vlan
  }

  initialization {
    datastore_id = var.storage_pool
    ip_config {
      ipv4 {
        address = var.controller.ipv4_cidr
        gateway = var.ipv4_gateway
      }
      ipv6 {
        address = var.controller.ipv6_cidr
        gateway = var.ipv6_gateway
      }
    }
    user_account {
      username = var.ssh_user
      keys     = [trimspace(var.ssh_public_key)]
    }
    dns {
      servers = var.dns_servers
      domain  = var.dns_domain
    }
  }
}

# ── Worker VMs ────────────────────────────────────────────────────────────────
# 3 disks per worker:
#   virtio0 — OS + container images     (disk_gb)
#   virtio1 — DirectPV raw disk         (data_disk_gb,     left unformatted by Ansible)
#   virtio2 — Longhorn data disk        (longhorn_disk_gb, formatted XFS + mounted by Ansible)

resource "proxmox_virtual_environment_vm" "workers" {
  for_each = local.workers_map

  name      = each.value.name
  vm_id     = each.value.vm_id
  node_name = var.proxmox_node
  on_boot   = true

  clone {
    vm_id   = var.template_vm_id
    full    = true
    retries = 3
  }

  agent {
    enabled = true
  }

  cpu {
    cores = each.value.cpu_cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = each.value.memory_mb
  }

  disk {
    interface    = "virtio0"
    datastore_id = var.storage_pool
    size         = each.value.disk_gb
    discard      = "on"
    iothread     = true
  }

  disk {
    interface    = "virtio1"
    datastore_id = var.storage_pool
    size         = each.value.data_disk_gb
    discard      = "on"
    iothread     = true
  }

  disk {
    interface    = "virtio2"
    datastore_id = var.storage_pool
    size         = each.value.longhorn_disk_gb
    discard      = "on"
    iothread     = true
  }

  network_device {
    bridge  = var.network_bridge
    vlan_id = var.network_vlan
  }

  initialization {
    datastore_id = var.storage_pool
    ip_config {
      ipv4 {
        address = each.value.ipv4_cidr
        gateway = var.ipv4_gateway
      }
      ipv6 {
        address = each.value.ipv6_cidr
        gateway = var.ipv6_gateway
      }
    }
    user_account {
      username = var.ssh_user
      keys     = [trimspace(var.ssh_public_key)]
    }
    dns {
      servers = var.dns_servers
      domain  = var.dns_domain
    }
  }
}
