#!/usr/bin/env bash
# Rebuilds everything on a fresh k3s cluster: Argo CD, Secrets, then the three Applications.
# Usage: KUBECONFIG=~/.kube/k3s-config bash scripts/bootstrap.sh <server public ip>
set -euo pipefail

IP="${1:?usage: bootstrap.sh <server public ip>}"
here="$(cd "$(dirname "$0")/.." && pwd)"
ARGO_URL=https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl get namespace argocd >/dev/null 2>&1 || kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts -f "$ARGO_URL"
kubectl -n argocd rollout status deployment/argocd-server --timeout=300s
kubectl -n argocd rollout status deployment/argocd-repo-server --timeout=300s
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=300s

bash "$here/scripts/create-secrets.sh"

for env in stage preprod prod; do
  sed "s/__IP__/$IP/" "$here/apps/$env.yaml" | kubectl apply -f -
done

echo "Argo CD admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
echo
