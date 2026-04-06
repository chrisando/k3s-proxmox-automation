#!/usr/bin/env bash
# post-deploy.sh — Orchestrate all post-Ansible deployment steps in order.
#
# Run ONCE after `ansible-playbook site.yml` completes successfully.
# The script is divided into phases that match the ArgoCD sync waves.
# You can resume from a specific phase with:  ./scripts/post-deploy.sh --from=<phase>
#
# Phases:
#   1-argocd     Wait for ArgoCD to become healthy
#   2-secrets    Seal and push all plaintext secrets
#   3-wave0      Wait for wave 0 apps (infra, databases, operators)
#   4-directpv   Initialise DirectPV drives
#   5-wave1      Wait for wave 1 apps (keycloak, etc.)
#   6-keycloak   Bootstrap Keycloak realm, clients, groups
#   7-oidc       Seal and apply OIDC client secrets
#   8-verify     Final health check
#
# Usage:
#   ./scripts/post-deploy.sh                 # run all phases
#   ./scripts/post-deploy.sh --from=4-directpv  # resume from a phase

set -euo pipefail

KUBECONFIG="${KUBECONFIG:-$HOME/.kube/k3s.yaml}"
export KUBECONFIG

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FROM_PHASE="${1:-}"
[[ "$FROM_PHASE" == --from=* ]] && FROM_PHASE="${FROM_PHASE#--from=}" || FROM_PHASE=""

PHASES=(1-argocd 2-secrets 3-wave0 4-directpv 5-wave1 6-keycloak 7-oidc 8-verify)
SKIP=false
[[ -n "$FROM_PHASE" ]] && SKIP=true

# ─── helpers ────────────────────────────────────────────────────────────────

log()   { echo ""; echo "━━━ $* ━━━"; }
ok()    { echo "  ✓ $*"; }
info()  { echo "  · $*"; }
pause() {
  echo ""
  read -r -p "  Press Enter to continue, or Ctrl-C to abort... " _
}

should_run() {
  local phase="$1"
  if $SKIP; then
    [[ "$phase" == "$FROM_PHASE" ]] && SKIP=false
    $SKIP && return 1
  fi
  return 0
}

wait_deploy() {
  local ns="$1" deploy="$2" timeout="${3:-300}"
  info "Waiting for $ns/$deploy..."
  kubectl rollout status deployment/"$deploy" -n "$ns" --timeout="${timeout}s"
}

wait_app_healthy() {
  local app="$1"
  info "Waiting for ArgoCD app '$app' to be Healthy+Synced..."
  for i in $(seq 1 60); do
    STATUS=$(kubectl get application "$app" -n argocd \
      -o jsonpath='{.status.health.status}/{.status.sync.status}' 2>/dev/null || echo "NotFound/Unknown")
    if [[ "$STATUS" == "Healthy/Synced" ]]; then
      ok "$app: Healthy/Synced"
      return 0
    fi
    sleep 10
  done
  echo "  WARNING: $app did not reach Healthy/Synced within 10m (status: $STATUS)"
}

wait_all_apps_healthy() {
  local apps=("$@")
  for app in "${apps[@]}"; do
    wait_app_healthy "$app"
  done
}

# ─── phase 1: ArgoCD ─────────────────────────────────────────────────────────

if should_run "1-argocd"; then
  log "Phase 1 — Wait for ArgoCD"
  wait_deploy argocd argocd-server 300
  ok "ArgoCD server is ready"
  info "ArgoCD admin password: $(cat ~/.argocd-admin-password 2>/dev/null || echo '(see ~/.argocd-admin-password)')"
fi

# ─── phase 2: seal secrets ───────────────────────────────────────────────────

if should_run "2-secrets"; then
  log "Phase 2 — Seal plaintext secrets"
  info "Waiting for sealed-secrets-controller..."
  kubectl rollout status deployment/sealed-secrets-controller -n kube-system --timeout=300s

  info "Running seal-secrets.sh..."
  "$SCRIPT_DIR/seal-secrets.sh"

  ok "Secrets sealed"
  echo ""
  info "IMPORTANT: Back up the sealed-secrets master key NOW (store outside git):"
  echo "    kubectl get secret -n kube-system \\"
  echo "      -l sealedsecrets.bitnami.com/sealed-secrets-key \\"
  echo "      -o yaml > ~/sealed-secrets-master-key.yaml"
  pause
fi

# ─── phase 3: wave 0 ─────────────────────────────────────────────────────────

if should_run "3-wave0"; then
  log "Phase 3 — Wait for wave 0 (infrastructure)"
  info "This may take 10-15 minutes for storage, databases, and operators to become ready."
  wait_all_apps_healthy \
    cert-manager envoy-gateway reflector \
    cnpg postgres \
    directpv longhorn \
    kube-prometheus-stack loki \
    keycloak-operator keycloak-config \
    sealed-secrets
  ok "Wave 0 complete"
fi

# ─── phase 4: DirectPV ───────────────────────────────────────────────────────

if should_run "4-directpv"; then
  log "Phase 4 — Initialise DirectPV drives"
  info "The directpv app is deployed but drives must be claimed before PVCs can bind."
  "$SCRIPT_DIR/init-directpv.sh"
  ok "DirectPV drives initialised"

  info "Waiting for postgres PVCs to bind (may take 2-3 min)..."
  for i in $(seq 1 36); do
    UNBOUND=$(kubectl get pvc -A --no-headers 2>/dev/null \
      | grep -v "Bound" | grep -v "NAME" | wc -l || echo 0)
    [[ "$UNBOUND" -eq 0 ]] && break
    sleep 5
  done
  ok "All PVCs bound"
fi

# ─── phase 5: wave 1 ─────────────────────────────────────────────────────────

if should_run "5-wave1"; then
  log "Phase 5 — Wait for wave 1 (keycloak, apps)"
  wait_all_apps_healthy keycloak k8s-monitoring networking
  ok "Wave 1 complete"
fi

# ─── phase 6: Keycloak setup ─────────────────────────────────────────────────

if should_run "6-keycloak"; then
  log "Phase 6 — Bootstrap Keycloak"
  info "Waiting for Keycloak to be reachable..."
  for i in $(seq 1 30); do
    curl -sf https://sso.apps.wagner.org.za/health/ready &>/dev/null && break
    sleep 10
  done
  ok "Keycloak is reachable"

  "$SCRIPT_DIR/setup-keycloak.sh"
  ok "Keycloak bootstrapped"
fi

# ─── phase 7: OIDC secrets ───────────────────────────────────────────────────

if should_run "7-oidc"; then
  log "Phase 7 — Seal and apply OIDC client secrets"
  "$SCRIPT_DIR/patch-oidc-secrets.sh"
  ok "OIDC secrets applied"

  info "Restarting apps that depend on OIDC secrets..."
  kubectl rollout restart deployment/argocd-server -n argocd
  kubectl rollout restart statefulset/kube-prometheus-stack-grafana -n monitoring 2>/dev/null || true
  kubectl rollout restart deployment/kube-prometheus-stack-grafana -n monitoring 2>/dev/null || true
  ok "Restarts triggered"
  pause
fi

# ─── phase 8: verify ─────────────────────────────────────────────────────────

if should_run "8-verify"; then
  log "Phase 9 — Final verification"

  echo ""
  echo "  ArgoCD application health:"
  kubectl get applications -n argocd \
    -o custom-columns='APP:.metadata.name,HEALTH:.status.health.status,SYNC:.status.sync.status' \
    --sort-by=.metadata.name

  echo ""
  echo "  PVC status:"
  kubectl get pvc -A --no-headers | awk '{printf "  %-40s %-10s %s/%s\n", $2, $3, $1, $2}'

  echo ""
  echo "  Node status:"
  kubectl get nodes -o wide

  echo ""
  log "Deployment complete!"
  echo ""
  echo "  Access points:"
  echo "    ArgoCD:      https://argocd.apps.wagner.org.za"
  echo "    Grafana:     https://grafana.apps.wagner.org.za"
  echo "    Keycloak:    https://sso.apps.wagner.org.za"
  echo "    Longhorn:    https://longhorn.apps.wagner.org.za"
fi
