#!/usr/bin/env bash
set -Eeuo pipefail
cloud="${1:?cloud required}"
environment="${2:?environment required}"
[[ "$cloud" =~ ^(azure|aws)$ ]]
[[ "$environment" =~ ^(dev|staging|production)$ ]]
: "${TF_VARS_JSON:?Set the environment TF_VARS_JSON variable}"
printf '%s' "$TF_VARS_JSON" | jq -e --arg environment "$environment" '.environment == $environment' >/dev/null
printf '%s' "$TF_VARS_JSON" > "infra/$cloud/ci.auto.tfvars.json"
if [[ "$cloud" == aws ]]; then
  terraform -chdir=infra/aws init -input=false -lockfile=readonly \
    -backend-config="bucket=${TF_STATE_BUCKET:?}" \
    -backend-config="key=multicloud/aws/$environment/terraform.tfstate" \
    -backend-config="region=${AWS_REGION:?}" \
    -backend-config=encrypt=true -backend-config=use_lockfile=true
else
  terraform -chdir=infra/azure init -input=false -lockfile=readonly \
    -backend-config="resource_group_name=${TF_STATE_RESOURCE_GROUP:?}" \
    -backend-config="storage_account_name=${TF_STATE_STORAGE_ACCOUNT:?}" \
    -backend-config="container_name=${TF_STATE_CONTAINER:?}" \
    -backend-config="key=multicloud/azure/$environment/terraform.tfstate" \
    -backend-config=use_azuread_auth=true -backend-config=use_oidc=true
fi
