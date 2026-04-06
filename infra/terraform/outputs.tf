output "controller_ipv4" {
  description = "IPv4 address of the k3s controller"
  value       = local.controller_ipv4
}

output "controller_ipv6" {
  description = "IPv6 address of the k3s controller"
  value       = local.controller_ipv6
}

output "worker_ipv4s" {
  description = "IPv4 addresses of k3s workers"
  value       = local.worker_ipv4s
}

output "worker_ipv6s" {
  description = "IPv6 addresses of k3s workers"
  value       = local.worker_ipv6s
}

output "ansible_inventory" {
  description = "Rendered Ansible inventory block — copy into inventory/hosts.yml"
  value = <<-EOT
    all:
      children:
        k3s_cluster:
          children:
            k3s_controller:
              hosts:
                ${var.controller.name}:
                  ansible_host: ${local.controller_ipv4}
                  ipv6_address: ${local.controller_ipv6}
            k3s_workers:
              hosts:
    %{for i, w in var.workers~}
                ${w.name}:
                  ansible_host: ${local.worker_ipv4s[i]}
                  ipv6_address: ${local.worker_ipv6s[i]}
    %{endfor~}
  EOT
}
