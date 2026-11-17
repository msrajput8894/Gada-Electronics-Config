#!/usr/bin/env bash
# Rebuilds everything on a fresh k3s cluster:
# Argo CD, Secrets, monitoring, then the three environments.
# Usage: KUBECONFIG=~/.kube/k3s-config bash scripts/bootstrap.sh <ip>
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

# Monitoring first: the app chart creates a PodMonitor, which needs these CRDs.
kubectl apply -f "$here/apps/monitoring.yaml"
kubectl apply -f "$here/apps/dashboards.yaml"
kubectl apply -f "$here/apps/alerts.yaml"
echo "Waiting for the monitoring CRDs..."
for i in $(seq 1 120); do
  kubectl get crd podmonitors.monitoring.coreos.com >/dev/null 2>&1 && break
  sleep 5
done
kubectl wait --for=condition=Established \
  crd/podmonitors.monitoring.coreos.com --timeout=60s

for env in stage preprod prod; do
  sed "s/__IP__/$IP/" "$here/apps/$env.yaml" | kubectl apply -f -
done

echo "Argo CD admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
echo
echo "Grafana admin password:"
kubectl -n monitoring get secret grafana-admin \
  -o jsonpath='{.data.admin-password}' | base64 -d
echo
