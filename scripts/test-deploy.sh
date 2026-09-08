#!/usr/bin/env bash
set -Eeuo pipefail
# Exercise deployment failure handling with mocked CLIs; this does not simulate a cluster.
task_tmp="$(mktemp -d)"
trap 'rm -f -- "$MOCK_LOG"; rmdir -- "$task_tmp"' EXIT
export MOCK_LOG="$task_tmp/commands.log"
helm() {
  echo "helm $*" >> "$MOCK_LOG"
  if [[ "$1" == list ]]; then echo '[]'; fi
  if [[ "$1" == upgrade && "$SCENARIO" == upgrade-fail ]]; then return 1; fi
  return 0
}
jq() {
  cat >/dev/null
  if [[ "$*" == *revision* ]]; then
    if [[ "$SCENARIO" != first-smoke-fail ]]; then echo 3; fi
  else
    echo '{"kind":"Pod"}'
  fi
}
kubectl() {
  echo "kubectl $*" >> "$MOCK_LOG"
  case "$1" in
    create) echo '{"kind":"Namespace"}' ;;
    run) echo '{"kind":"Pod"}' ;;
    apply)
      payload="$(cat)"
      if [[ "$payload" == *Pod* && "$SCENARIO" == smoke-create-fail ]]; then return 1; fi
      ;;
    wait)
      if [[ "$SCENARIO" == smoke-fail || "$SCENARIO" == first-smoke-fail ]]; then return 1; fi
      ;;
  esac
  return 0
}
export -f helm jq kubectl
for SCENARIO in success smoke-fail first-smoke-fail smoke-create-fail upgrade-fail; do
  export SCENARIO
  : > "$MOCK_LOG"
  status=0
  bash scripts/deploy.sh dev aws example.test/app "sha256:$(printf 'a%.0s' {1..64})" "$(printf 'b%.0s' {1..40})" >/dev/null 2>&1 || status=$?
  if [[ "$SCENARIO" == success ]]; then
    [[ "$status" == 0 ]]
    ! grep -Eq 'helm (rollback|uninstall)' "$MOCK_LOG"
  else
    [[ "$status" != 0 ]]
    case "$SCENARIO" in
      first-smoke-fail) grep -q 'helm uninstall multicloud-app' "$MOCK_LOG" ;;
      upgrade-fail) ! grep -Eq 'helm (rollback|uninstall)' "$MOCK_LOG" ;;
      *) grep -q 'helm rollback multicloud-app 3' "$MOCK_LOG" ;;
    esac
  fi
  echo "PASS $SCENARIO"
done
