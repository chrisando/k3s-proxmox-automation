#!/usr/bin/env bash
# seal-secrets.sh — Convert all plaintext Kubernetes Secrets to SealedSecrets.
#
# Prerequisites:
#   - kubeseal CLI installed (https://github.com/bitnami-labs/sealed-secrets#installation)
#   - sealed-secrets-controller running in kube-system (deployed by ArgoCD)
#   - KUBECONFIG pointing at the cluster
#
# Usage:
#   ./scripts/seal-secrets.sh              # seal everything
#   ./scripts/seal-secrets.sh --dry-run    # print what would be done, no changes
#
# After running, commit the changed files (original secret files are backed up to .bak).
# Delete .bak files once you've verified the cluster is healthy.

set -euo pipefail

KUBECONFIG="${KUBECONFIG:-$HOME/.kube/k3s.yaml}"
export KUBECONFIG

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

CERT_FILE="$(mktemp /tmp/sealed-secrets-cert.XXXXXX.pem)"
trap 'rm -f "$CERT_FILE"' EXIT

echo "==> Fetching sealed-secrets public certificate..."
kubeseal \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=kube-system \
  --fetch-cert > "$CERT_FILE"
echo "    Certificate written to $CERT_FILE"

# Files that are plain single-document secrets (or multi-Secret pure-secret files)
SIMPLE_SECRETS=(
  gitops/apps/keycloak/admin-secret.yaml
  gitops/apps/keycloak/postgres-secret.yaml
  gitops/apps/keycloak/grafana-sso-secret.yaml
  gitops/apps/keycloak-instance/gitea-readonly-secret.yaml
  gitops/apps/secrets/cloudflare-token-secret.yaml
  gitops/apps/secrets/dbcreds.yaml
)

cd "$(git rev-parse --show-toplevel)"

seal_file() {
  local src="$1"
  if [[ ! -f "$src" ]]; then
    echo "  SKIP  $src (not found)"
    return
  fi

  echo "  sealing $src"
  if $DRY_RUN; then
    return
  fi

  cp "$src" "${src}.bak"

  kubeseal \
    --format yaml \
    --cert "$CERT_FILE" \
    < "$src" > "${src}.sealed.tmp"

  # Replace the original with the SealedSecret
  mv "${src}.sealed.tmp" "$src"
}

echo ""
echo "==> Sealing single-document secret files..."
for f in "${SIMPLE_SECRETS[@]}"; do
  seal_file "$f"
done

echo ""
if $DRY_RUN; then
  echo "==> DRY RUN complete — no files were modified."
else
  echo "==> Done. Next steps:"
  echo "    1. Verify ArgoCD syncs cleanly with the new SealedSecrets."
  echo "    2. Check that applications start successfully."
  echo "    3. Delete the .bak backup files once you are confident."
  echo "    4. Commit the sealed files to git."
  echo ""
  echo "    Backup controller key (run once, store safely):"
  echo "      kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key \\"
  echo "        -o yaml > sealed-secrets-master-key.yaml"
  echo "    WARNING: keep sealed-secrets-master-key.yaml OUT of git."
fi
