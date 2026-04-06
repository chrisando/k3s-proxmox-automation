#!/usr/bin/env bash
# setup-keycloak.sh — Bootstrap the Keycloak homelab realm with all required clients and groups.
#
# Run AFTER ArgoCD wave 1 has deployed Keycloak and it is healthy.
# This script is idempotent — safe to re-run.
#
# Prerequisites:
#   - kubectl configured and pointing at the cluster
#   - curl, jq installed
#   - Keycloak reachable at https://sso.apps.wagner.org.za
#
# Usage:
#   ./scripts/setup-keycloak.sh
#
# Outputs:
#   ~/.keycloak-client-secrets.env  — all OIDC client secrets (NEVER commit this file)
#
# After this script, run:
#   ./scripts/patch-oidc-secrets.sh   — seals and applies the client secrets to the cluster

set -euo pipefail

KUBECONFIG="${KUBECONFIG:-$HOME/.kube/k3s.yaml}"
export KUBECONFIG

KC_URL="https://sso.apps.wagner.org.za"
REALM="homelab"
SECRETS_FILE="$HOME/.keycloak-client-secrets.env"

# ─── helpers ────────────────────────────────────────────────────────────────

log()  { echo "==> $*"; }
ok()   { echo "    ✓ $*"; }
info() { echo "    · $*"; }

kc_get_token() {
  local pass
  pass=$(kubectl get secret -n keycloak keycloak-admin-secret \
    -o jsonpath='{.data.admin-password}' | base64 -d)

  curl -sf -X POST "$KC_URL/realms/master/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "client_id=admin-cli" \
    -d "username=admin" \
    -d "password=${pass}" \
    -d "grant_type=password" | jq -r '.access_token'
}

kc() {
  # kc <method> <path> [body]
  local method="$1" path="$2" body="${3:-}"
  local args=(-sf -X "$method" "$KC_URL/admin/realms/$path"
               -H "Authorization: Bearer $TOKEN"
               -H "Content-Type: application/json")
  [[ -n "$body" ]] && args+=(-d "$body")
  curl "${args[@]}"
}

kc_root() {
  local method="$1" path="$2" body="${3:-}"
  local args=(-sf -X "$method" "$KC_URL/admin/$path"
               -H "Authorization: Bearer $TOKEN"
               -H "Content-Type: application/json")
  [[ -n "$body" ]] && args+=(-d "$body")
  curl "${args[@]}"
}

client_id_by_name() {
  # Returns the Keycloak internal UUID for a client by clientId
  kc GET "${REALM}/clients?clientId=$1" | jq -r '.[0].id // empty'
}

# ─── 1. token ────────────────────────────────────────────────────────────────

log "Fetching Keycloak admin token..."
TOKEN=$(kc_get_token)
ok "Token acquired"

# ─── 2. realm ────────────────────────────────────────────────────────────────

log "Ensuring realm '$REALM' exists..."
if kc_root GET "realms/$REALM" 2>/dev/null | jq -e '.realm' &>/dev/null; then
  ok "Realm '$REALM' already exists"
else
  kc_root POST "realms" "$(jq -n \
    --arg r "$REALM" \
    '{realm: $r, enabled: true, displayName: "Homelab", sslRequired: "external",
      registrationAllowed: false, loginWithEmailAllowed: true,
      duplicateEmailsAllowed: false, resetPasswordAllowed: true,
      editUsernameAllowed: false, bruteForceProtected: true}')"
  ok "Realm '$REALM' created"
fi

# ─── 3. group ────────────────────────────────────────────────────────────────

log "Ensuring group 'admins' exists..."
if kc GET "${REALM}/groups" | jq -e '.[] | select(.name=="admins")' &>/dev/null; then
  ok "Group 'admins' already exists"
else
  kc POST "${REALM}/groups" '{"name":"admins"}'
  ok "Group 'admins' created"
fi

# ─── 4. clients ──────────────────────────────────────────────────────────────

create_client() {
  local name="$1" body="$2"
  if [[ -n "$(client_id_by_name "$name")" ]]; then
    ok "Client '$name' already exists — skipping"
  else
    kc POST "${REALM}/clients" "$body" >/dev/null
    ok "Client '$name' created"
  fi
}

log "Creating clients..."

create_client "argocd" "$(jq -n '{
  clientId: "argocd",
  enabled: true,
  protocol: "openid-connect",
  publicClient: false,
  standardFlowEnabled: true,
  directAccessGrantsEnabled: false,
  serviceAccountsEnabled: false,
  redirectUris: ["https://argocd.apps.wagner.org.za/auth/callback"],
  webOrigins: ["https://argocd.apps.wagner.org.za"],
  protocolMappers: [{
    name: "groups",
    protocol: "openid-connect",
    protocolMapper: "oidc-group-membership-mapper",
    consentRequired: false,
    config: {
      "full.path": "false",
      "id.token.claim": "true",
      "access.token.claim": "true",
      "claim.name": "groups",
      "userinfo.token.claim": "true"
    }
  }]
}')"

create_client "grafana" "$(jq -n '{
  clientId: "grafana",
  enabled: true,
  protocol: "openid-connect",
  publicClient: false,
  standardFlowEnabled: true,
  directAccessGrantsEnabled: false,
  redirectUris: ["https://grafana.apps.wagner.org.za/login/generic_oauth"],
  webOrigins: ["https://grafana.apps.wagner.org.za"],
  protocolMappers: [{
    name: "groups",
    protocol: "openid-connect",
    protocolMapper: "oidc-group-membership-mapper",
    consentRequired: false,
    config: {
      "full.path": "false",
      "id.token.claim": "true",
      "access.token.claim": "true",
      "claim.name": "groups",
      "userinfo.token.claim": "true"
    }
  }]
}')"

# ─── 5. collect client secrets ───────────────────────────────────────────────

log "Collecting client secrets..."

get_secret() {
  local cid
  cid=$(client_id_by_name "$1")
  kc GET "${REALM}/clients/${cid}/client-secret" | jq -r '.value'
}

ARGOCD_SECRET=$(get_secret "argocd")
GRAFANA_SECRET=$(get_secret "grafana")

cat > "$SECRETS_FILE" <<EOF
# Keycloak client secrets — generated $(date -u +%Y-%m-%dT%H:%M:%SZ)
# NEVER commit this file. Keep it in a password manager.
ARGOCD_OIDC_SECRET="${ARGOCD_SECRET}"
GRAFANA_OIDC_SECRET="${GRAFANA_SECRET}"
EOF
chmod 600 "$SECRETS_FILE"

ok "Secrets written to $SECRETS_FILE"

echo ""
log "Done. Summary:"
info "Realm:   $REALM"
info "Group:   admins"
info "Clients: argocd, grafana"
echo ""
echo "Next step: run   ./scripts/patch-oidc-secrets.sh"
