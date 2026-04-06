#!/usr/bin/env bash
# patch-oidc-secrets.sh — Seal and apply Keycloak OIDC client secrets to the cluster.
#
# Run AFTER setup-keycloak.sh has generated ~/.keycloak-client-secrets.env.
#
# What it does:
#   For each OIDC client secret, it re-seals the relevant SealedSecret and
#   applies it directly to the cluster via kubectl. The sealed YAML files in
#   gitops/ are also updated so that the repo reflects the live state.
#
# Prerequisites:
#   - kubeseal CLI installed
#   - sealed-secrets-controller running in kube-system
#   - ~/.keycloak-client-secrets.env present (from setup-keycloak.sh)
#   - kubectl configured

set -euo pipefail

KUBECONFIG="${KUBECONFIG:-$HOME/.kube/k3s.yaml}"
export KUBECONFIG

SECRETS_FILE="$HOME/.keycloak-client-secrets.env"
REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

if [[ ! -f "$SECRETS_FILE" ]]; then
  echo "ERROR: $SECRETS_FILE not found. Run setup-keycloak.sh first." >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$SECRETS_FILE"

log()  { echo "==> $*"; }
ok()   { echo "    ✓ $*"; }

CERT_FILE="$(mktemp /tmp/sealed-secrets-cert.XXXXXX.pem)"
trap 'rm -f "$CERT_FILE"' EXIT

log "Fetching sealed-secrets certificate..."
kubeseal \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=kube-system \
  --fetch-cert > "$CERT_FILE"

seal_and_apply() {
  local name="$1" namespace="$2" key="$3" value="$4" dest_file="$5"

  log "Sealing $name/$key in $namespace..."

  SEALED=$(kubectl create secret generic "$name" \
    --namespace="$namespace" \
    --from-literal="${key}=${value}" \
    --dry-run=client -o yaml \
    | kubeseal --format yaml --cert "$CERT_FILE" \
    | python3 -c "
import sys, yaml
docs = list(yaml.safe_load_all(sys.stdin))
s = docs[0]
print(s['spec']['encryptedData']['${key}'])
")

  # Merge encrypted key into the existing SealedSecret file
  python3 - "$dest_file" "$key" "$SEALED" <<'PYEOF'
import sys, yaml, re

path, key, value = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f:
    content = f.read()

docs = list(yaml.safe_load_all(content))
updated = False
for doc in docs:
    if (doc.get('kind') == 'SealedSecret'
            and doc.get('spec', {}).get('encryptedData', {}).get(key) is not None):
        doc['spec']['encryptedData'][key] = value
        updated = True

if not updated:
    print(f"WARNING: key '{key}' not found in {path}", file=sys.stderr)
    sys.exit(1)

with open(path, 'w') as f:
    yaml.dump_all(docs, f, default_flow_style=False, allow_unicode=True)
PYEOF

  ok "$name/$key sealed and written to $dest_file"
}

# ArgoCD OIDC secret (in argocd-app.yaml values, key: oidc.keycloak.clientSecret)
# This one is patched directly in the cluster secret rather than a separate SealedSecret
log "Patching argocd-secret with OIDC client secret..."
kubectl create secret generic argocd-secret \
  --namespace=argocd \
  --from-literal="oidc.keycloak.clientSecret=${ARGOCD_OIDC_SECRET}" \
  --dry-run=client -o yaml \
  | kubeseal --format yaml --cert "$CERT_FILE" \
  | kubectl apply -f -
ok "argocd-secret patched"

# Grafana
seal_and_apply \
  "grafana-oauth-secret" "monitoring" \
  "client-secret" "$GRAFANA_OIDC_SECRET" \
  "$REPO_ROOT/gitops/apps/keycloak/grafana-sso-secret.yaml"

log "Applying updated SealedSecrets to cluster..."
kubectl apply -f "$REPO_ROOT/gitops/apps/keycloak/grafana-sso-secret.yaml"
ok "SealedSecrets applied"

echo ""
log "Done. Commit the updated sealed secret files:"
echo "    git add gitops/apps/keycloak/"
echo "    git commit -m 'Update sealed OIDC client secrets'"
