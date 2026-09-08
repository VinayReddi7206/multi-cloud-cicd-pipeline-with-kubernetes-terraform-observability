#!/usr/bin/env bash
set -Eeuo pipefail
cloud="${1:?Usage: install-monitoring.sh azure|aws [extra-values.yaml]}"
[[ "$cloud" =~ ^(azure|aws)$ ]]
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "monitoring/storage-class-$cloud.yaml"
extra=()
if [[ -n "${2:-}" ]]; then extra=(-f "$2"); fi
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --version 88.6.1 --namespace monitoring \
  -f monitoring/values.yaml "${extra[@]}" \
  --atomic --wait --timeout 15m
kubectl create configmap multicloud-dashboard -n monitoring \
  --from-file=multicloud.json=monitoring/dashboards/multicloud.json \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl label configmap multicloud-dashboard -n monitoring grafana_dashboard=1 --overwrite
