#!/usr/bin/env bash
set -Eeuo pipefail
# Usage: deploy.sh <dev|staging|production> <azure|aws> <repository> <sha256:digest> <commit>
environment="${1:?environment required}"
cloud="${2:?cloud required}"
repository="${3:?image repository required}"
digest="${4:?image digest required}"
commit="${5:?commit required}"
[[ "$environment" =~ ^(dev|staging|production)$ ]]
[[ "$cloud" =~ ^(azure|aws)$ ]]
[[ "$digest" =~ ^sha256:[a-f0-9]{64}$ ]]
[[ "$commit" =~ ^[a-f0-9]{40}$ ]]
namespace="app-$environment"
release="multicloud-app"
kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null
kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace "$namespace" pod-security.kubernetes.io/enforce=restricted --overwrite
# Atomic handles readiness failures; keep the previous revision for the HTTP smoke test.
previous="$(helm list --namespace "$namespace" --filter "^$release$" -o json | jq -r '.[0].revision // empty')"
helm upgrade --install "$release" helm/multicloud-app \
  --namespace "$namespace" \
  -f "helm/environments/$environment.yaml" \
  --set-string "cloud=$cloud" \
  --set-string "image.repository=$repository" \
  --set-string "image.digest=$digest" \
  --set-string "image.tag=$commit" \
  --set serviceMonitor.enabled=true \
  --atomic --wait --timeout 10m --history-max 10
# Test the Service from a pod; all runners do not have routes to ClusterIP addresses.
smoke="smoke-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}"
cleanup() { kubectl delete pod "$smoke" -n "$namespace" --ignore-not-found --wait=false >/dev/null || true; }
trap cleanup EXIT
rollback_on_error() {
  status=$?
  trap - ERR
  set +e
  kubectl logs "$smoke" -n "$namespace"
  if [[ -n "$previous" ]]; then
    helm rollback "$release" "$previous" -n "$namespace" --wait --timeout 10m
  else
    helm uninstall "$release" -n "$namespace" --wait --timeout 5m
  fi
  exit "$status"
}
trap rollback_on_error ERR
kubectl run "$smoke" -n "$namespace" --restart=Never --image="$repository@$digest" \
  --dry-run=client -o json --command -- node -e \
  "fetch('http://$release/api/info').then(async r=>{if(!r.ok)throw Error('HTTP '+r.status);const b=await r.json();if(b.version!=='$commit'||b.cloud!=='$cloud')throw Error('Unexpected release');console.log(b)}).catch(e=>{console.error(e);process.exit(1)})" \
  | jq '.spec.automountServiceAccountToken=false | .spec.securityContext={runAsNonRoot:true,runAsUser:1000,seccompProfile:{type:"RuntimeDefault"}} | .spec.containers[0].securityContext={allowPrivilegeEscalation:false,readOnlyRootFilesystem:true,capabilities:{drop:["ALL"]}} | .spec.containers[0].resources={requests:{cpu:"50m",memory:"32Mi"},limits:{cpu:"250m",memory:"128Mi"}}' \
  | kubectl apply -f -
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded "pod/$smoke" -n "$namespace" --timeout=120s
kubectl logs "$smoke" -n "$namespace"
trap - ERR
