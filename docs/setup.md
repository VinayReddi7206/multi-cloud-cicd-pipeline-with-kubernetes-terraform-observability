# Cloud setup

## 1. Workstation and GitHub

Run `./scripts/preflight.ps1` on Windows. Install missing tools from the official [Terraform](https://developer.hashicorp.com/terraform/install), [Docker](https://docs.docker.com/desktop/setup/install/windows-install/), [kubectl](https://kubernetes.io/docs/tasks/tools/), [Helm](https://helm.sh/docs/intro/install/), [GitHub CLI](https://cli.github.com/), [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli), and [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) documentation. Azure cluster access also uses [kubelogin](https://github.com/Azure/kubelogin).

Use Node.js 24, Terraform 1.14.8 (the CI version), Helm 3.19.0 (scripts use Helm 3 flags), and kubectl 1.35.x. Terraform lock files are committed; update providers deliberately. The application has no npm installation step.

Create a GitHub repository, add it as the origin, and push the reviewed files to a `main` branch. No remote repository or account is assumed. Require CI checks in branch protection, and restrict deployment environments to `main`.

## 2. Bootstrap state and identities

Do this once using an authenticated administrative session. Bootstrap resources must outlive the clusters.

**AWS state:** a dedicated S3 bucket with versioning, encryption, public access blocked, and HTTPS-only access. Give the plan and apply identities scoped access to the exact environment's state object and its `.tflock` object. S3 locking uses `use_lockfile=true`; no DynamoDB table is required. Match the bucket region to the backend configuration.

**Azure state:** a dedicated resource group, storage account with shared-key access disabled, HTTPS required, TLS 1.2+, blob versioning and soft deletion, and a private `tfstate` container. Grant each pipeline identity Storage Blob Data Contributor on its intended state scope. Azure Blob leases provide locking. If state endpoints are private, plan/apply jobs also need private runners; the supplied plan/apply workflow uses hosted Ubuntu runners.

Create separate planning, provisioning, and application deployment identities for each environment:

- The AWS planning role needs read/describe permissions for the infrastructure plus state locking. The provisioning role needs the relevant EKS, EC2/VPC, IAM, KMS, ECR, CloudWatch and tagging operations and scoped `iam:PassRole`. The application role needs ECR push operations and `eks:DescribeCluster`. Terraform grants its Kubernetes access through an EKS access entry.
- The Azure planning identity needs Reader on the project scope and state access. The provisioning identity needs Contributor for infrastructure plus permission to create the specific role assignments (a role-assignment permission with conditions is preferable to subscription-wide Owner). Register required Azure resource providers during bootstrap. The application identity receives registry push and AKS cluster access through Terraform.
- Use the application role ARN/object ID for `deployer_role_arn` / `deployer_object_id`. Set `provisioner_role_arn` to the AWS apply role: it becomes the explicit KMS administrator. Cluster-creator Kubernetes admin access is disabled, so the planning caller does not gain cluster-admin privileges from the saved plan.
- Since the release installs cluster-wide monitoring CRDs, the initial application role has cluster-admin Kubernetes access. See the security guide for splitting monitoring and app permissions before real production.

GitHub OIDC issuer: `https://token.actions.githubusercontent.com`. AWS audience: `sts.amazonaws.com`. Azure audience: `api://AzureADTokenExchange`.

Use exact environment subjects; for example:

```text
repo:OWNER/REPOSITORY:environment:aws-dev-plan
repo:OWNER/REPOSITORY:environment:aws-dev
repo:OWNER/REPOSITORY:environment:azure-dev-plan
repo:OWNER/REPOSITORY:environment:azure-dev
```

An environment-based token uses the environment subject, not a branch subject. Enforce the allowed branch in GitHub environment deployment rules. Never use a trust subject allowing arbitrary repositories.

Terraform uses `AWS_INFRA_ROLE_ARN` / `AZURE_INFRA_CLIENT_ID`; release uses `AWS_ROLE_ARN` / `AZURE_CLIENT_ID`. Set the former to planning identities in plan environments and provisioning identities in target environments.

References: [GitHub OIDC for AWS](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws), [GitHub OIDC for Azure](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-azure), [S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3), [Azure backend](https://developer.hashicorp.com/terraform/language/backend/azurerm).

## 3. GitHub environment variables

Create these pairs for each cloud and target environment:

```text
aws-dev-plan          aws-dev
azure-dev-plan        azure-dev
aws-staging-plan      aws-staging
azure-staging-plan    azure-staging
aws-production-plan   aws-production
azure-production-plan azure-production
```

On each target environment (the names without `-plan`), configure required reviewers and restrict deployments to `main`. GitHub plan/repository visibility can affect availability of protection rules; verify they are actually active before applying.

| Variable | Environments | Value |
| --- | --- | --- |
| `TF_VARS_JSON` | Plan and target | JSON equivalent of the selected `.tfvars.example`; same inputs in both |
| `AWS_REGION` | AWS plan and target | Example: `ap-south-1` |
| `AWS_ROLE_ARN` | AWS target | Application deployment role |
| `AWS_INFRA_ROLE_ARN` | AWS plan and target | Planning role in plan environment; provisioning role in target |
| `TF_STATE_BUCKET` | AWS plan and target | Existing state bucket |
| `AZURE_CLIENT_ID` | Azure target | Application service principal client ID |
| `AZURE_INFRA_CLIENT_ID` | Azure plan and target | Planning client in plan environment; provisioning client in target |
| `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` | Azure plan and target | Account identifiers |
| `TF_STATE_RESOURCE_GROUP`, `TF_STATE_STORAGE_ACCOUNT`, `TF_STATE_CONTAINER` | Azure plan and target | Existing state storage |
| `IMAGE_REPOSITORY` | Target | Terraform `registry_repository` output |
| `CLUSTER_NAME` | Target | Terraform `cluster_name` output |
| `ACR_NAME` | Azure target | Terraform `registry_name` output |
| `AZURE_RESOURCE_GROUP` | Azure target | Terraform `resource_group_name` output |

IDs and resource names are variables, not passwords. Store webhook URLs in Secrets, never in Terraform variables or repository files. `TF_VARS_JSON` must include an `environment` property matching the workflow input.

Example AWS Dev JSON (replace the account ID and choose a region-supported Kubernetes version):

```json
{
  "environment": "dev",
  "region": "ap-south-1",
  "kubernetes_version": "1.35",
  "node_count": 2,
  "vpc_cidr": "10.20.0.0/16",
  "deployer_role_arn": "arn:aws:iam::123456789012:role/multicloud-dev-deploy",
  "provisioner_role_arn": "arn:aws:iam::123456789012:role/multicloud-dev-provision"
}
```

Azure requires `subscription_id`, a globally unique `acr_name`, and the application service principal's **object ID**, not its client ID. Use the environment example as the complete input guide.

AKS nodes enable host encryption. Verify the VM SKU supports it and register the Azure `Microsoft.Compute/EncryptionAtHost` feature if your subscription requires registration before provisioning.

Verify versions in the target region using `az aks get-versions --location centralindia -o table` and `aws eks describe-cluster-versions --region ap-south-1`. Example version 1.35 is listed by both providers, but availability and quota must be checked at deployment time.

## 4. Provision Dev

Dispatch **Terraform plan and apply**, selecting one cloud, Dev, and `apply=false` for the first review. Inspect the plan for names, node counts, NAT gateways, log ingestion and storage costs.

When ready, dispatch with `apply=true`, inspect that run's plan artifact, then approve the apply job. The job applies the saved plan from the same run, without replanning. Repeat for the other cloud, then populate target environment variables from outputs.

Local alternative:

```powershell
Copy-Item infra/aws/environments/dev.tfvars.example infra/aws/environments/dev.tfvars
Copy-Item infra/aws/dev.backend.hcl.example infra/aws/dev.backend.hcl
# Edit both files and authenticate to AWS first.
terraform -chdir=infra/aws init -reconfigure -backend-config=dev.backend.hcl
terraform -chdir=infra/aws plan -var-file=environments/dev.tfvars -out=dev.tfplan
terraform -chdir=infra/aws show dev.tfplan
terraform -chdir=infra/aws apply dev.tfplan
```

Azure follows the same sequence in `infra/azure`, after `az login`. Never reuse a Dev backend key for Staging or Production. Use a separate checkout or `TF_DATA_DIR` per environment when managing environments locally; the workflow starts each job with fresh Terraform metadata and generates a distinct backend key.

## 5. Private deployment runners

Provision an ephemeral Linux runner in each cloud network, or a network peered to it with private DNS configured. The Terraform outputs expose the AWS VPC/private subnets and Azure VNet. Runner provisioning and GitHub registration are a bootstrap responsibility and are not created by these Terraform roots.

Runners need outbound HTTPS to GitHub, the cloud APIs, registries and Helm repositories; Kubernetes API access over private networking; Bash, Git, jq, Azure CLI for Azure, and AWS CLI v2 for AWS. Terraform allows TCP 443 to the EKS API from the project VPC CIDR. A peered runner network needs an additional reviewed security-group rule. Azure runners need the AKS private DNS zone resolvable from their network. Use the non-overlapping VNet CIDRs in the environment examples.

Register labels `self-hosted,linux,aws,dev` or `self-hosted,linux,azure,dev`. Match the environment label for Staging/Production. Do not run pull-request jobs on these privileged runners. An absent runner causes deployment to queue.

## 6. Release and observe

Dispatch **Release to both clouds** from `main`, selecting Dev. It rebuilds and scans the selected main commit once; both registries receive that same artifact. Releasing a later environment reruns the build and scan from the currently selected main commit. Record the commit before promotion; cross-run artifact promotion without rebuilding is not implemented.

Use the operations guide to verify both clouds, retrieve Grafana credentials locally, inspect metrics, and practice rollback. Optional Slack alerts require a webhook secret and explicit monitoring values. Add Staging and Production only after Dev deployment and cleanup have been exercised.
