#!/usr/bin/env bash
# apply-vars.sh — Substitute {{ VAR_NAME }} tokens in gitops YAML files from cluster.env.
#
# Run this from the repo root BEFORE sealing secrets.
#
# Usage:
#   cp cluster.env.example cluster.env
#   $EDITOR cluster.env          # fill in real values
#   bash scripts/apply-vars.sh   # substitute tokens
#   bash scripts/seal-secrets.sh # encrypt secrets before committing
#
# The files listed below contain {{ VAR_NAME }} placeholders that are replaced
# in-place. Original files are backed up to <file>.bak (gitignored).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_ROOT}/cluster.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE not found." >&2
  echo "  Copy cluster.env.example to cluster.env and fill in your values." >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

# ── Helpers ───────────────────────────────────────────────────────────────────

ok()   { echo "  ✓ $*"; }
info() { echo "  · $*"; }

# sub VAR_NAME "file" [file ...]
# Replaces {{ VAR_NAME }} with the value of $VAR_NAME in each file.
sub() {
  local var="$1"; shift
  local val="${!var}"
  # Escape characters special to sed's replacement string
  local escaped_val
  escaped_val="$(printf '%s\n' "$val" | sed 's/[&/\\]/\\&/g; s/|/\\|/g')"
  for file in "$@"; do
    local abs="${REPO_ROOT}/${file}"
    if [[ ! -f "$abs" ]]; then
      info "SKIP  $file (not found)"
      continue
    fi
    cp "$abs" "${abs}.bak"
    sed -i.tmp "s|{{ ${var} }}|${escaped_val}|g" "$abs"
    rm -f "${abs}.tmp"
    ok "$file  [${var}]"
  done
}

# ── Substitutions ─────────────────────────────────────────────────────────────

echo ""
echo "==> Substituting tokens from cluster.env..."
echo ""

sub BLOB_STORAGE_ENDPOINT \
  gitops/apps/databases/postgres/objectStore.yaml

sub BLOB_ACCESS_KEY_ID \
  gitops/apps/secrets/dbcreds.yaml

sub BLOB_SECRET_ACCESS_KEY \
  gitops/apps/secrets/dbcreds.yaml

sub DB_SUPERUSER_PASSWORD \
  gitops/apps/secrets/dbcreds.yaml

sub DB_KEYCLOAK_PASSWORD \
  gitops/apps/databases/postgres/cluster.yaml \
  gitops/apps/keycloak/postgres-secret.yaml

sub CLOUDFLARE_TOKEN \
  gitops/apps/secrets/cloudflare-token-secret.yaml

sub KEYCLOAK_ADMIN_PASSWORD \
  gitops/apps/keycloak/admin-secret.yaml

sub GRAFANA_ADMIN_PASSWORD \
  gitops/apps/argo-suite/kube-prometheus-stack-app.yaml

sub GRAFANA_OIDC_CLIENT_SECRET \
  gitops/apps/keycloak/grafana-sso-secret.yaml \
  gitops/apps/argo-suite/kube-prometheus-stack-app.yaml

sub GITEA_READONLY_USERNAME \
  gitops/apps/keycloak-instance/gitea-readonly-secret.yaml

sub GITEA_READONLY_TOKEN \
  gitops/apps/keycloak-instance/gitea-readonly-secret.yaml

echo ""
echo "==> Done. All tokens substituted."
echo ""
echo "  Next:"
echo "    bash scripts/seal-secrets.sh   # encrypt secrets"
echo "    git diff                        # review changes"
echo ""
echo "  NOTE: .bak files contain your real values — do NOT commit them."
echo "        They are gitignored by *.bak."
