#!/usr/bin/env bash
# Creates each environment's namespace and gada-secrets if they do not exist yet.
# Safe to re-run: existing secrets are left alone.
set -euo pipefail

for env in stage preprod prod; do
  ns="gada-$env"
  kubectl get namespace "$ns" >/dev/null 2>&1 || kubectl create namespace "$ns"
  if kubectl -n "$ns" get secret gada-secrets >/dev/null 2>&1; then
    echo "$ns: gada-secrets already exists, leaving it alone"
    continue
  fi
  kubectl -n "$ns" create secret generic gada-secrets \
    --from-literal=mongo-root-password="$(openssl rand -hex 16)" \
    --from-literal=jwt-secret="$(openssl rand -hex 32)" \
    --from-literal=admin-password="$(openssl rand -hex 12)"
  echo "$ns: created gada-secrets"
done

kubectl get namespace monitoring >/dev/null 2>&1 || kubectl create namespace monitoring
if ! kubectl -n monitoring get secret grafana-admin >/dev/null 2>&1; then
  kubectl -n monitoring create secret generic grafana-admin \
    --from-literal=admin-user=admin \
    --from-literal=admin-password="$(openssl rand -base64 18 | tr -d '=+/')"
fi
