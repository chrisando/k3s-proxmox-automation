#!/usr/bin/env bash
# init-directpv.sh — Discover and initialise DirectPV drives on all worker nodes.
#
# Run ONCE after ArgoCD has deployed the directpv app (wave 0) and the CSI
# controller/node pods are running. The /dev/vdb disk on each worker must be
# raw (unformatted) — Ansible leaves it that way intentionally.
#
# This script is NOT idempotent for already-initialised drives. Running it
# again on a live cluster will re-discover but not re-format already-claimed
# drives (DirectPV skips them).
#
# Prerequisites:
#   - kubectl directpv plugin installed:
#       kubectl krew install directpv
#   - kubectl configured
#
# Usage:
#   ./scripts/init-directpv.sh [--yes]   # --yes skips the confirmation prompt

set -euo pipefail

KUBECONFIG="${KUBECONFIG:-$HOME/.kube/k3s.yaml}"
export KUBECONFIG

AUTO_YES=false
[[ "${1:-}" == "--yes" ]] && AUTO_YES=true

DRIVES_FILE="$(mktemp /tmp/directpv-drives.XXXXXX.yaml)"
trap 'rm -f "$DRIVES_FILE"' EXIT

log()  { echo "==> $*"; }
ok()   { echo "    ✓ $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

# ─── wait for DirectPV controller ────────────────────────────────────────────

log "Waiting for DirectPV controller to be ready..."
kubectl rollout status deployment/controller -n directpv --timeout=300s
ok "DirectPV controller ready"

log "Waiting for DirectPV node pods to be ready on all workers..."
kubectl rollout status daemonset/node-server -n directpv --timeout=300s
ok "DirectPV node pods ready"

# ─── discover drives ─────────────────────────────────────────────────────────

log "Discovering drives (this may take 30s)..."
kubectl directpv discover --output-file "$DRIVES_FILE"

echo ""
echo "Discovered drives:"
echo "─────────────────────────────────────────────────────────────"
kubectl directpv discover --quiet 2>/dev/null || cat "$DRIVES_FILE"
echo "─────────────────────────────────────────────────────────────"
echo ""

DRIVE_COUNT=$(grep -c "^  - " "$DRIVES_FILE" 2>/dev/null || echo 0)
if [[ "$DRIVE_COUNT" -eq 0 ]]; then
  die "No drives found. Check that /dev/vdb is raw on all workers and node-server pods are healthy."
fi

info() { echo "    · $*"; }
info "Found $DRIVE_COUNT drive(s)"

# ─── confirm ─────────────────────────────────────────────────────────────────

if ! $AUTO_YES; then
  echo ""
  read -r -p "Initialise all discovered drives? This will claim them for DirectPV. [y/N] " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

# ─── initialise ──────────────────────────────────────────────────────────────

log "Initialising drives..."
kubectl directpv init "$DRIVES_FILE"
ok "Drives initialised"

# ─── verify ──────────────────────────────────────────────────────────────────

log "Verifying drive status (waiting up to 60s for Ready)..."
for i in $(seq 1 12); do
  READY=$(kubectl directpv list drives --no-headers 2>/dev/null \
    | grep -c "Ready" || true)
  if [[ "$READY" -ge "$DRIVE_COUNT" ]]; then
    ok "$READY drive(s) in Ready state"
    break
  fi
  sleep 5
done

echo ""
log "DirectPV drive summary:"
kubectl directpv list drives
echo ""
log "Done. The directpv-min-io StorageClass is ready for PVC requests."
