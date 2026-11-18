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

# Alertmanager's Slack webhook. The URL lives in a local file, never in Git:
#   ~/.config/gada/slack-webhook   (override with SLACK_WEBHOOK_FILE)
if ! kubectl -n monitoring get secret alertmanager-slack >/dev/null 2>&1; then
  webhook_file="${SLACK_WEBHOOK_FILE:-$HOME/.config/gada/slack-webhook}"
  if [ -s "$webhook_file" ]; then
    kubectl -n monitoring create secret generic alertmanager-slack \
      --from-literal=url="$(tr -d '\n' < "$webhook_file")"
    echo "monitoring: created alertmanager-slack"
  else
    echo "WARNING: no Slack webhook at $webhook_file; alerts will not be delivered" >&2
    # Alertmanager mounts this secret, so create an empty-valued one to let it start.
    kubectl -n monitoring create secret generic alertmanager-slack --from-literal=url="http://localhost/unconfigured"
  fi
fi

# Password for the synthetic monitor's customer account (same value in every environment).
if ! kubectl -n monitoring get secret synthetic-monitor >/dev/null 2>&1; then
  kubectl -n monitoring create secret generic synthetic-monitor \
    --from-literal=password="$(openssl rand -hex 16)"
  echo "monitoring: created synthetic-monitor"
fi
