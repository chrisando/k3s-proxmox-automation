#!/usr/bin/env bash
# setup.sh — Interactive configuration wizard for k3s-ansible
#
# Run this from the repo root to generate all configuration files:
#   infra/terraform/terraform.tfvars
#   inventory/hosts.yml
#   inventory/group_vars/all.yml
#   inventory/group_vars/k3s_controller.yml
#   gitops/cilium/values.yaml
#   gitops/cilium/config/bgp-peering-policy.yaml
#   gitops/cilium/config/lb-ip-pool.yaml
#
# Prerequisites:
#   - bash 4+
#   - Run from the repo root: bash scripts/setup.sh

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────

BOLD='\033[1m'
DIM='\033[2m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────

info()    { echo -e "${CYAN}${BOLD}→${RESET} $*"; }
success() { echo -e "${GREEN}${BOLD}✓${RESET} $*"; }
warn()    { echo -e "${YELLOW}${BOLD}!${RESET} $*"; }
error()   { echo -e "${RED}${BOLD}✗${RESET} $*" >&2; }
header()  { echo -e "\n${BOLD}${CYAN}━━ $* ━━${RESET}"; }
blank()   { echo; }

# prompt VAR "Question" "default"
prompt() {
  local -n _ref=$1
  local question="$2"
  local default="${3:-}"
  local display_default=""
  [[ -n "$default" ]] && display_default=" ${DIM}[${default}]${RESET}"
  echo -ne "  ${question}${display_default}: "
  read -r _ref
  [[ -z "$_ref" ]] && _ref="$default"
}

# prompt_secret VAR "Question"
prompt_secret() {
  local -n _ref=$1
  local question="$2"
  echo -ne "  ${question}: "
  read -rs _ref
  echo
}

# prompt_yn VAR "Question" "y|n"
prompt_yn() {
  local -n _ref=$1
  local question="$2"
  local default="${3:-n}"
  local display_default="${DIM}[${default}]${RESET}"
  echo -ne "  ${question} (y/n) ${display_default}: "
  read -r _ref
  [[ -z "$_ref" ]] && _ref="$default"
  [[ "$_ref" =~ ^[Yy] ]] && _ref="y" || _ref="n"
}

# validate_ip "address"  → exit 1 if not a valid IPv4
validate_ipv4() {
  local ip="$1"
  if [[ ! "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    error "'$ip' does not look like a valid IPv4 address"; return 1
  fi
}

# validate_cidr "192.168.1.1/24"
validate_cidr4() {
  local cidr="$1"
  if [[ ! "$cidr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
    error "'$cidr' does not look like a valid IPv4 CIDR (e.g. 192.168.1.10/24)"; return 1
  fi
}

# strip prefix length from CIDR → bare IP
cidr_ip() { echo "${1%%/*}"; }

# ── Banner ────────────────────────────────────────────────────────────────────

clear
echo -e "${BOLD}"
cat <<'EOF'
  ██╗  ██╗██████╗ ███████╗      █████╗ ███╗   ██╗███████╗██╗██████╗ ██╗     ███████╗
  ██║ ██╔╝╚════██╗██╔════╝     ██╔══██╗████╗  ██║██╔════╝██║██╔══██╗██║     ██╔════╝
  █████╔╝  █████╔╝███████╗     ███████║██╔██╗ ██║███████╗██║██████╔╝██║     █████╗
  ██╔═██╗  ╚═══██╗╚════██║     ██╔══██║██║╚██╗██║╚════██║██║██╔══██╗██║     ██╔══╝
  ██║  ██╗██████╔╝███████║     ██║  ██║██║ ╚████║███████║██║██████╔╝███████╗███████╗
  ╚═╝  ╚═╝╚═════╝ ╚══════╝     ╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝╚═╝╚═════╝ ╚══════╝╚══════╝
EOF
echo -e "${RESET}"
echo -e "  ${DIM}k3s on Proxmox · Cilium CNI · ArgoCD GitOps · Dual-stack${RESET}"
echo -e "  ${DIM}Configuration wizard — generates all config files from your answers${RESET}"
blank

warn "Prerequisites:"
echo -e "  • Debian 13 cloud-init template on Proxmox (run ${BOLD}scripts/create-template.sh${RESET} first)"
echo -e "  • Proxmox API token with VM + Datastore + SDN permissions"
echo -e "  • BGP-capable upstream router"
echo -e "  • SSH key pair generated locally"
blank
echo -ne "  Press ${BOLD}Enter${RESET} to continue or ${BOLD}Ctrl-C${RESET} to abort..."
read -r

# ── Section 1: Proxmox ────────────────────────────────────────────────────────

header "Proxmox Connection"
prompt PROXMOX_ENDPOINT    "API endpoint (https://host:8006)" "https://pve.local:8006"
prompt PROXMOX_NODE        "Node name" "pve"
prompt_secret PROXMOX_API_TOKEN "API token (USER@REALM!TOKENID=SECRET)"
prompt PROXMOX_SSH_USER    "SSH username on Proxmox host" "root"
prompt_yn PROXMOX_INSECURE "Skip TLS certificate verification?" "n"

# ── Section 2: Template ───────────────────────────────────────────────────────

header "Cloud-Init Template"
echo -e "  ${DIM}Run scripts/create-template.sh on the Proxmox host to create this template.${RESET}"
prompt TEMPLATE_VM_ID "Debian 13 cloud-init template VM ID" "9000"

# ── Section 3: Network ────────────────────────────────────────────────────────

header "Network"
prompt NETWORK_BRIDGE "Proxmox bridge for VM NICs" "vmbr0"
prompt NETWORK_VLAN   "VLAN tag (leave blank for untagged)" ""
prompt IPV4_GATEWAY   "IPv4 default gateway" ""
prompt IPV6_GATEWAY   "IPv6 default gateway" ""
prompt DNS_SERVERS    "DNS servers (comma-separated)" "1.1.1.1,2606:4700:4700::1111"
prompt DNS_DOMAIN     "DNS search domain" "local"

# Convert comma-separated DNS to Terraform list syntax
dns_tf_list() {
  local input="$1"
  # "1.1.1.1,8.8.8.8" → ["1.1.1.1", "8.8.8.8"]
  local result='['
  IFS=',' read -ra parts <<< "$input"
  for i in "${!parts[@]}"; do
    local part; part=$(echo "${parts[$i]}" | xargs)
    [[ $i -gt 0 ]] && result+=', '
    result+="\"${part}\""
  done
  result+=']'
  echo "$result"
}

# ── Section 4: Storage ────────────────────────────────────────────────────────

header "Storage"
prompt STORAGE_POOL "Proxmox storage pool for VM disks" "local-lvm"

# ── Section 5: SSH ────────────────────────────────────────────────────────────

header "SSH Access"
prompt SSH_KEY_PATH "Path to your SSH public key file" "~/.ssh/id_rsa.pub"
SSH_KEY_PATH_EXPANDED="${SSH_KEY_PATH/#\~/$HOME}"
if [[ -f "$SSH_KEY_PATH_EXPANDED" ]]; then
  SSH_PUBLIC_KEY=$(cat "$SSH_KEY_PATH_EXPANDED")
  success "Loaded public key from $SSH_KEY_PATH"
else
  warn "File not found — paste your public key directly:"
  prompt SSH_PUBLIC_KEY "SSH public key" ""
fi
prompt SSH_USER        "Default VM user (created by cloud-init)" "debian"
prompt ANSIBLE_SSH_KEY "Path to SSH private key for Ansible" "~/.ssh/id_rsa"

# ── Section 6: Controller VM ──────────────────────────────────────────────────

header "Controller VM  (k3s server)"
prompt CTRL_VM_ID    "VM ID" "200"
prompt CTRL_IPV4     "IPv4 CIDR  (e.g. 192.168.1.10/24)" ""
prompt CTRL_IPV6     "IPv6 CIDR  (e.g. fd12:3456:789a::1/64)" ""
prompt CTRL_CORES    "CPU cores" "8"
prompt CTRL_MEMORY   "Memory MB" "16384"
prompt CTRL_DISK     "OS disk GB" "200"

CTRL_IP=$(cidr_ip "$CTRL_IPV4")
CTRL_IPV6_ADDR=$(cidr_ip "$CTRL_IPV6")

# ── Section 7: Worker VMs ─────────────────────────────────────────────────────

header "Worker VMs  (k3s agents — always 3)"
echo -e "  ${DIM}Each worker gets 3 disks: OS + DirectPV raw (/dev/vdb) + Longhorn XFS (/dev/vdc)${RESET}"
blank

declare -a W_VM_IDS W_IPV4S W_IPV6S W_CORES W_MEMORIES W_DISKS W_DATA_DISKS W_LH_DISKS
declare -a W_IPS W_IPV6_ADDRS

for i in 1 2 3; do
  echo -e "  ${BOLD}Worker $i${RESET}"
  prompt "W_VM_IDS[$i]"    "  VM ID" "$((200 + i))"
  prompt "W_IPV4S[$i]"     "  IPv4 CIDR" ""
  prompt "W_IPV6S[$i]"     "  IPv6 CIDR" ""
  prompt "W_CORES[$i]"     "  CPU cores" "16"
  prompt "W_MEMORIES[$i]"  "  Memory MB" "32768"
  prompt "W_DISKS[$i]"     "  OS disk GB" "200"
  prompt "W_DATA_DISKS[$i]" "  DirectPV disk GB (/dev/vdb)" "512"
  prompt "W_LH_DISKS[$i]"  "  Longhorn disk GB (/dev/vdc)" "512"
  W_IPS[$i]=$(cidr_ip "${W_IPV4S[$i]}")
  W_IPV6_ADDRS[$i]=$(cidr_ip "${W_IPV6S[$i]}")
  blank
done

# ── Section 8: Kubernetes Networking ─────────────────────────────────────────

header "Kubernetes Networking"
echo -e "  ${DIM}These CIDRs must not overlap with your LAN or each other.${RESET}"
blank
prompt POD_CIDR_V4  "Pod CIDR (IPv4)" "10.42.0.0/16"
prompt POD_CIDR_V6  "Pod CIDR (IPv6)" "fd00:42::/48"
prompt SVC_CIDR_V4  "Service CIDR (IPv4)" "10.43.0.0/16"
prompt SVC_CIDR_V6  "Service CIDR (IPv6)" "fd00:43::/112"

blank
echo -e "  ${DIM}BGP — Cilium will peer with your upstream router to advertise LB service IPs.${RESET}"
prompt BGP_ROUTER_ADDR "BGP router IP (upstream peer)" ""
prompt BGP_ROUTER_ASN  "BGP router ASN" "65000"
prompt BGP_CLUSTER_ASN "BGP cluster ASN" "65000"

blank
echo -e "  ${DIM}LB IP pool — IPs from this range are assigned to LoadBalancer services and advertised via BGP.${RESET}"
prompt LB_POOL_V4 "LB pool CIDR (IPv4)" ""
prompt LB_POOL_V6 "LB pool CIDR (IPv6)" ""

# ── Section 9: GitOps / ArgoCD ────────────────────────────────────────────────

header "GitOps / ArgoCD"
echo -e "  ${DIM}ArgoCD will sync from this repo to manage all cluster applications.${RESET}"
prompt GITOPS_REPO_URL      "Git repo URL" ""
prompt GITOPS_REPO_REVISION "Branch/tag to track" "HEAD"
prompt APPS_DOMAIN          "Wildcard apps domain (e.g. apps.example.com)" ""

prompt_yn GITOPS_PRIVATE "Is the repo private (needs credentials)?" "n"
if [[ "$GITOPS_PRIVATE" == "y" ]]; then
  prompt      GITOPS_REPO_USER  "Git username" ""
  prompt_secret GITOPS_REPO_TOKEN "Git token / password"
fi

# ── Section 10: Secrets / cluster.env ────────────────────────────────────────

header "Secrets  (written to cluster.env — never committed)"
echo -e "  ${DIM}These values are substituted into gitops YAML files by scripts/apply-vars.sh.${RESET}"
blank

prompt      BLOB_STORAGE_ENDPOINT "Blob storage endpoint (MinIO/S3 URL)" "http://192.168.1.10:9000"
prompt      BLOB_ACCESS_KEY_ID    "Blob access key ID" "minioadmin"
prompt_secret BLOB_SECRET_ACCESS_KEY "Blob secret access key"

blank
prompt_secret DB_SUPERUSER_PASSWORD  "Postgres superuser password (cw role)"
prompt_secret DB_KEYCLOAK_PASSWORD   "Postgres keycloak role password"

blank
prompt_secret CLOUDFLARE_TOKEN       "Cloudflare API token (DNS-01, Zones:Read + DNS:Edit)"

blank
prompt_secret KEYCLOAK_ADMIN_PASSWORD "Keycloak admin password"

blank
prompt_secret GRAFANA_ADMIN_PASSWORD     "Grafana admin password"
prompt_secret GRAFANA_OIDC_CLIENT_SECRET "Grafana OIDC client secret (set after Keycloak bootstrap)"

blank
prompt      GITEA_READONLY_USERNAME "Gitea read-only username (for Keycloak theme loader)" ""
prompt_secret GITEA_READONLY_TOKEN  "Gitea read-only token"

# ── Section 11: Versions ──────────────────────────────────────────────────────

header "Component Versions"
echo -e "  ${DIM}Press Enter to keep the defaults.${RESET}"
blank
prompt K3S_VERSION      "k3s version"            "v1.35.1+k3s1"
prompt HELM_VERSION     "Helm version"            "v3.17.1"
prompt CILIUM_VERSION   "Cilium Helm chart"       "1.19.1"
prompt ARGOCD_VERSION   "ArgoCD Helm chart"       "7.7.2"
prompt ARGOCD_NS        "ArgoCD namespace"        "argocd"

# ── TLS SANs (controller) ─────────────────────────────────────────────────────

TLS_API_DNS="api.${APPS_DOMAIN}"

# ── Summary ───────────────────────────────────────────────────────────────────

blank
echo -e "${BOLD}${CYAN}━━ Summary ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo
echo -e "  Proxmox        ${BOLD}${PROXMOX_ENDPOINT}${RESET}  (node: ${PROXMOX_NODE})"
echo -e "  Controller     ${BOLD}${CTRL_IP}${RESET}  /  ${CTRL_IPV6_ADDR}"
for i in 1 2 3; do
  echo -e "  Worker $i       ${BOLD}${W_IPS[$i]}${RESET}  /  ${W_IPV6_ADDRS[$i]}"
done
echo -e "  Pod CIDRs      ${POD_CIDR_V4}  /  ${POD_CIDR_V6}"
echo -e "  Service CIDRs  ${SVC_CIDR_V4}  /  ${SVC_CIDR_V6}"
echo -e "  BGP peer       ${BGP_ROUTER_ADDR}  ASN ${BGP_ROUTER_ASN}  →  cluster ASN ${BGP_CLUSTER_ASN}"
echo -e "  LB pools       ${LB_POOL_V4}  /  ${LB_POOL_V6}"
echo -e "  GitOps repo    ${GITOPS_REPO_URL}  @ ${GITOPS_REPO_REVISION}"
echo -e "  Apps domain    *.${APPS_DOMAIN}"
echo -e "  k3s            ${K3S_VERSION}   Cilium ${CILIUM_VERSION}   ArgoCD chart ${ARGOCD_VERSION}"
blank

prompt_yn CONFIRM "Generate configuration files?" "y"
[[ "$CONFIRM" != "y" ]] && { warn "Aborted — no files written."; exit 0; }

# ── Write files ───────────────────────────────────────────────────────────────

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Helper — back up a file before overwriting
backup_if_exists() {
  [[ -f "$1" ]] && cp "$1" "${1}.bak" && warn "Backed up existing $(basename "$1") to $(basename "$1").bak"
}

info "Writing configuration files..."

# ── infra/terraform/terraform.tfvars ─────────────────────────────────────────

backup_if_exists "${REPO_ROOT}/infra/terraform/terraform.tfvars"
DNS_TF="$(dns_tf_list "$DNS_SERVERS")"
VLAN_TF="${NETWORK_VLAN:-null}"
INSECURE_TF="$( [[ "$PROXMOX_INSECURE" == "y" ]] && echo "true" || echo "false")"

cat > "${REPO_ROOT}/infra/terraform/terraform.tfvars" <<EOF
# Generated by scripts/setup.sh — do not edit manually, re-run the wizard instead.

# ── Proxmox connection ────────────────────────────────────────────────────────
proxmox_endpoint     = "${PROXMOX_ENDPOINT}"
proxmox_api_token    = "${PROXMOX_API_TOKEN}"
proxmox_insecure     = ${INSECURE_TF}
proxmox_ssh_username = "${PROXMOX_SSH_USER}"
proxmox_node         = "${PROXMOX_NODE}"

# ── Template ──────────────────────────────────────────────────────────────────
template_vm_id = ${TEMPLATE_VM_ID}

# ── Network ───────────────────────────────────────────────────────────────────
network_bridge = "${NETWORK_BRIDGE}"
network_vlan   = ${VLAN_TF}
ipv4_gateway   = "${IPV4_GATEWAY}"
ipv6_gateway   = "${IPV6_GATEWAY}"
dns_servers    = ${DNS_TF}
dns_domain     = "${DNS_DOMAIN}"

# ── Storage ───────────────────────────────────────────────────────────────────
storage_pool = "${STORAGE_POOL}"

# ── SSH ───────────────────────────────────────────────────────────────────────
ssh_public_key = "${SSH_PUBLIC_KEY}"
ssh_user       = "${SSH_USER}"

# ── Controller ────────────────────────────────────────────────────────────────
controller = {
  name      = "k3s-controller-01"
  vm_id     = ${CTRL_VM_ID}
  ipv4_cidr = "${CTRL_IPV4}"
  ipv6_cidr = "${CTRL_IPV6}"
  cpu_cores = ${CTRL_CORES}
  memory_mb = ${CTRL_MEMORY}
  disk_gb   = ${CTRL_DISK}
}

# ── Workers ───────────────────────────────────────────────────────────────────
workers = [
  {
    name             = "k3s-worker-01"
    vm_id            = ${W_VM_IDS[1]}
    ipv4_cidr        = "${W_IPV4S[1]}"
    ipv6_cidr        = "${W_IPV6S[1]}"
    cpu_cores        = ${W_CORES[1]}
    memory_mb        = ${W_MEMORIES[1]}
    disk_gb          = ${W_DISKS[1]}
    data_disk_gb     = ${W_DATA_DISKS[1]}
    longhorn_disk_gb = ${W_LH_DISKS[1]}
  },
  {
    name             = "k3s-worker-02"
    vm_id            = ${W_VM_IDS[2]}
    ipv4_cidr        = "${W_IPV4S[2]}"
    ipv6_cidr        = "${W_IPV6S[2]}"
    cpu_cores        = ${W_CORES[2]}
    memory_mb        = ${W_MEMORIES[2]}
    disk_gb          = ${W_DISKS[2]}
    data_disk_gb     = ${W_DATA_DISKS[2]}
    longhorn_disk_gb = ${W_LH_DISKS[2]}
  },
  {
    name             = "k3s-worker-03"
    vm_id            = ${W_VM_IDS[3]}
    ipv4_cidr        = "${W_IPV4S[3]}"
    ipv6_cidr        = "${W_IPV6S[3]}"
    cpu_cores        = ${W_CORES[3]}
    memory_mb        = ${W_MEMORIES[3]}
    disk_gb          = ${W_DISKS[3]}
    data_disk_gb     = ${W_DATA_DISKS[3]}
    longhorn_disk_gb = ${W_LH_DISKS[3]}
  },
]
EOF
success "infra/terraform/terraform.tfvars"

# ── inventory/hosts.yml ───────────────────────────────────────────────────────

backup_if_exists "${REPO_ROOT}/inventory/hosts.yml"
cat > "${REPO_ROOT}/inventory/hosts.yml" <<EOF
---
# Generated by scripts/setup.sh

all:
  vars:
    ansible_user: ${SSH_USER}
    ansible_ssh_private_key_file: ${ANSIBLE_SSH_KEY}
    ansible_python_interpreter: /usr/bin/python3

  children:
    k3s_cluster:
      children:
        k3s_controller:
          hosts:
            k3s-controller-01:
              ansible_host: ${CTRL_IP}
              ipv6_address: "${CTRL_IPV6_ADDR}"

        k3s_workers:
          hosts:
            k3s-worker-01:
              ansible_host: ${W_IPS[1]}
              ipv6_address: "${W_IPV6_ADDRS[1]}"
            k3s-worker-02:
              ansible_host: ${W_IPS[2]}
              ipv6_address: "${W_IPV6_ADDRS[2]}"
            k3s-worker-03:
              ansible_host: ${W_IPS[3]}
              ipv6_address: "${W_IPV6_ADDRS[3]}"
EOF
success "inventory/hosts.yml"

# ── inventory/group_vars/all.yml ──────────────────────────────────────────────

backup_if_exists "${REPO_ROOT}/inventory/group_vars/all.yml"

GITOPS_CREDS_BLOCK=""
if [[ "$GITOPS_PRIVATE" == "y" ]]; then
  GITOPS_CREDS_BLOCK="gitops_repo_username: \"${GITOPS_REPO_USER}\"
gitops_repo_token: \"${GITOPS_REPO_TOKEN}\""
else
  GITOPS_CREDS_BLOCK="#gitops_repo_username: \"\"
#gitops_repo_token: \"\""
fi

cat > "${REPO_ROOT}/inventory/group_vars/all.yml" <<EOF
---
# Generated by scripts/setup.sh

# ── k3s version ───────────────────────────────────────────────────────────────
k3s_version: "${K3S_VERSION}"
k3s_api_port: 6443

# ── Cluster networking ────────────────────────────────────────────────────────
cluster_pod_cidr_v4: "${POD_CIDR_V4}"
cluster_pod_cidr_v6: "${POD_CIDR_V6}"
cluster_svc_cidr_v4: "${SVC_CIDR_V4}"
cluster_svc_cidr_v6: "${SVC_CIDR_V6}"

# ── BGP ───────────────────────────────────────────────────────────────────────
bgp_router_address: "${BGP_ROUTER_ADDR}"
bgp_router_asn: ${BGP_ROUTER_ASN}
bgp_cluster_asn: ${BGP_CLUSTER_ASN}

# ── Load-balancer IP pools (advertised via BGP) ───────────────────────────────
lb_ip_pool_v4: "${LB_POOL_V4}"
lb_ip_pool_v6: "${LB_POOL_V6}"

# ── Helm ──────────────────────────────────────────────────────────────────────
helm_version: "${HELM_VERSION}"

# ── Cilium ────────────────────────────────────────────────────────────────────
cilium_version: "${CILIUM_VERSION}"
cilium_namespace: "kube-system"

# ── ArgoCD / GitOps ───────────────────────────────────────────────────────────
argocd_chart_version: "${ARGOCD_VERSION}"
argocd_namespace: "${ARGOCD_NS}"

gitops_repo_url: "${GITOPS_REPO_URL}"
gitops_repo_revision: "${GITOPS_REPO_REVISION}"
${GITOPS_CREDS_BLOCK}

# ── Blob storage (MinIO / S3-compatible) ─────────────────────────────────────
blob_storage_endpoint: "${BLOB_STORAGE_ENDPOINT}"

# ── Cluster hosts (used to populate /etc/hosts on each node) ─────────────────
cluster_hosts:
  - name: k3s-controller-01
    ipv4: "${CTRL_IP}"
    ipv6: "${CTRL_IPV6_ADDR}"
  - name: k3s-worker-01
    ipv4: "${W_IPS[1]}"
    ipv6: "${W_IPV6_ADDRS[1]}"
  - name: k3s-worker-02
    ipv4: "${W_IPS[2]}"
    ipv6: "${W_IPV6_ADDRS[2]}"
  - name: k3s-worker-03
    ipv4: "${W_IPS[3]}"
    ipv6: "${W_IPV6_ADDRS[3]}"
EOF
success "inventory/group_vars/all.yml"

# ── cluster.env ───────────────────────────────────────────────────────────────

cat > "${REPO_ROOT}/cluster.env" <<EOF
# cluster.env — Site-specific secrets for the k3s-ansible deployment.
# Generated by scripts/setup.sh — update values here and re-run apply-vars.sh.
# This file is gitignored — never commit it.

# ── Git repository ────────────────────────────────────────────────────────────
GITOPS_REPO_URL="${GITOPS_REPO_URL}"
GITOPS_REPO_USERNAME="${GITOPS_REPO_USER:-}"
GITOPS_REPO_TOKEN="${GITOPS_REPO_TOKEN:-}"

# ── Blob storage (MinIO / S3-compatible external NAS) ─────────────────────────
BLOB_STORAGE_ENDPOINT="${BLOB_STORAGE_ENDPOINT}"
BLOB_ACCESS_KEY_ID="${BLOB_ACCESS_KEY_ID}"
BLOB_SECRET_ACCESS_KEY="${BLOB_SECRET_ACCESS_KEY}"

# ── Database passwords ────────────────────────────────────────────────────────
DB_SUPERUSER_PASSWORD="${DB_SUPERUSER_PASSWORD}"
DB_KEYCLOAK_PASSWORD="${DB_KEYCLOAK_PASSWORD}"

# ── Cloudflare ────────────────────────────────────────────────────────────────
CLOUDFLARE_TOKEN="${CLOUDFLARE_TOKEN}"

# ── Keycloak ──────────────────────────────────────────────────────────────────
KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD}"

# ── Grafana ───────────────────────────────────────────────────────────────────
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD}"
GRAFANA_OIDC_CLIENT_SECRET="${GRAFANA_OIDC_CLIENT_SECRET}"

# ── Gitea read-only token ─────────────────────────────────────────────────────
GITEA_READONLY_USERNAME="${GITEA_READONLY_USERNAME}"
GITEA_READONLY_TOKEN="${GITEA_READONLY_TOKEN}"
EOF
success "cluster.env"

# ── inventory/group_vars/k3s_controller.yml ───────────────────────────────────

backup_if_exists "${REPO_ROOT}/inventory/group_vars/k3s_controller.yml"
cat > "${REPO_ROOT}/inventory/group_vars/k3s_controller.yml" <<EOF
---
# Generated by scripts/setup.sh

k3s_api_port: 6443

k3s_tls_sans:
  - "${CTRL_IP}"
  - "${CTRL_IPV6_ADDR}"
  - "k3s-controller-01"
  - "${TLS_API_DNS}"

kubeconfig_local_path: "~/.kube/k3s.yaml"
EOF
success "inventory/group_vars/k3s_controller.yml"

# ── gitops/cilium/values.yaml ─────────────────────────────────────────────────

backup_if_exists "${REPO_ROOT}/gitops/cilium/values.yaml"
cat > "${REPO_ROOT}/gitops/cilium/values.yaml" <<EOF
# Cilium Helm values — managed via GitOps (ArgoCD).
# Edit here to change Cilium configuration; ArgoCD will reconcile the release.

kubeProxyReplacement: true
k8sServiceHost: "${CTRL_IP}"
k8sServicePort: 6443

ipv4:
  enabled: true
ipv6:
  enabled: true

ipam:
  mode: kubernetes

routingMode: native
autoDirectNodeRoutes: true
ipv4NativeRoutingCIDR: "${POD_CIDR_V4}"
ipv6NativeRoutingCIDR: "${POD_CIDR_V6}"

bgpControlPlane:
  enabled: true

hubble:
  enabled: true
  relay:
    enabled: true
  ui:
    enabled: true

bpf:
  masquerade: true

operator:
  replicas: 1
EOF
success "gitops/cilium/values.yaml"

# ── gitops/cilium/config/bgp-peering-policy.yaml ─────────────────────────────

backup_if_exists "${REPO_ROOT}/gitops/cilium/config/bgp-peering-policy.yaml"
cat > "${REPO_ROOT}/gitops/cilium/config/bgp-peering-policy.yaml" <<EOF
# CiliumBGPPeeringPolicy — peers all cluster nodes with the upstream router.
# Managed via GitOps; edit here to change BGP peering configuration.
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPPeeringPolicy
metadata:
  name: cluster-bgp-policy
spec:
  nodeSelector:
    matchLabels: {}
  virtualRouters:
    - localASN: ${BGP_CLUSTER_ASN}
      exportPodCIDR: true
      neighbors:
        - peerAddress: "${BGP_ROUTER_ADDR}/32"
          peerASN: ${BGP_ROUTER_ASN}
          eBGPMultihop: false
          connectRetryTimeSeconds: 120
          holdTimeSeconds: 90
          keepAliveTimeSeconds: 30
          gracefulRestart:
            enabled: true
            restartTimeSeconds: 120
          families:
            - afi: ipv4
              safi: unicast
            - afi: ipv6
              safi: unicast
EOF
success "gitops/cilium/config/bgp-peering-policy.yaml"

# ── gitops/cilium/config/lb-ip-pool.yaml ─────────────────────────────────────

backup_if_exists "${REPO_ROOT}/gitops/cilium/config/lb-ip-pool.yaml"
cat > "${REPO_ROOT}/gitops/cilium/config/lb-ip-pool.yaml" <<EOF
# CiliumLoadBalancerIPPool — IP ranges Cilium assigns to LoadBalancer services.
# Managed via GitOps; edit here to adjust the advertised LB address pools.
apiVersion: cilium.io/v2alpha1
kind: CiliumLoadBalancerIPPool
metadata:
  name: cluster-lb-pool
spec:
  blocks:
    - cidr: "${LB_POOL_V4}"
    - cidr: "${LB_POOL_V6}"
EOF
success "gitops/cilium/config/lb-ip-pool.yaml"

# ── Done ──────────────────────────────────────────────────────────────────────

blank
echo -e "${GREEN}${BOLD}All configuration files generated.${RESET}"
blank
echo -e "  ${BOLD}Next steps:${RESET}"
echo -e ""
echo -e "  ${BOLD}1.${RESET}  Commit the gitops changes (cilium values + config):"
echo -e "       ${DIM}git add gitops/cilium/ && git commit -m 'Configure cilium for cluster'${RESET}"
echo -e "       ${DIM}git push${RESET}"
echo
echo -e "  ${BOLD}2.${RESET}  Create the Debian 13 cloud-init template on Proxmox (if not done):"
echo -e "       ${DIM}ssh ${PROXMOX_SSH_USER}@<proxmox-host> 'bash -s' < scripts/create-template.sh${RESET}"
echo
echo -e "  ${BOLD}3.${RESET}  Provision VMs with Terraform:"
echo -e "       ${DIM}cd infra/terraform && terraform init && terraform apply${RESET}"
echo
echo -e "  ${BOLD}4.${RESET}  Run the Ansible site playbook:"
echo -e "       ${DIM}ansible-playbook -i inventory/hosts.yml site.yml${RESET}"
echo
echo -e "  ${BOLD}5.${RESET}  Access ArgoCD (once cluster is up):"
echo -e "       ${DIM}kubectl port-forward svc/argocd-server -n ${ARGOCD_NS} 8080:443${RESET}"
echo -e "       ${DIM}cat ~/.argocd-admin-password${RESET}"
blank
warn "terraform.tfvars contains your Proxmox API token — never commit it to git."
blank
