#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/config.env"

echo "==> Destroying Inkus cluster..."

# try terraform destroy first if state exists
cd "$REPO_ROOT/terraform"
if [ -d .terraform ] && [ -f terraform.tfstate ]; then
    terraform destroy -auto-approve -input=false
else
    echo "  -> No terraform state found, skipping terraform destroy"
fi
cd "$REPO_ROOT"

# brute-force cleanup of any orphaned incus resources matching our cluster name
if command -v incus &>/dev/null; then
    echo "  -> Cleaning up incus resources for '$CLUSTER_NAME'..."
    # delete instances
    for inst in $(incus list --format csv -c n 2>/dev/null | grep "^${CLUSTER_NAME}-" || true); do
        echo "     deleting instance $inst"
        incus delete "$inst" --force 2>/dev/null || true
    done
    # delete profile
    incus profile delete "$CLUSTER_NAME" 2>/dev/null || true
    # delete network
    incus network delete "$CLUSTER_NAME" 2>/dev/null || true
    # delete storage pool
    incus storage delete "$CLUSTER_NAME" 2>/dev/null || true
fi

rm -f "$REPO_ROOT/kubeconfig"
rm -f "$REPO_ROOT/ansible/inventory.ini"
rm -f "$REPO_ROOT/terraform/terraform.auto.tfvars"

echo "==> Cluster destroyed."
