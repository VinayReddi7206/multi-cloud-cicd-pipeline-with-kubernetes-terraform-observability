# Security scope and exceptions

This repository demonstrates security controls; it does not establish regulatory compliance or certify a production environment.

## Implemented controls

- GitHub OIDC with separate planning, provisioning and application identities; exact environment trust subjects are configured during bootstrap.
- Read-only default workflow permissions, job-scoped OIDC permission, exact commit pins for third-party actions and top-level Terraform modules, and provider lock files.
- Private AKS/EKS API endpoints, managed identities, RBAC, no AKS local administrator account, private AWS worker subnets and enforced metadata tokens.
- ECR KMS encryption, rotation and immutable tags; no ACR admin/password login or anonymous pulls.
- Non-root containers, read-only root filesystems, no Linux capabilities, no Kubernetes service account token, resource limits, probes, restricted application namespaces, and application network policies. The sample API needs no outbound network access.
- Checkov gates the root Terraform resources. Trivy blocks HIGH/CRITICAL image findings, including unfixed vulnerabilities. A scanner outage also fails the gate.
- The runtime image updates Alpine packages and removes bundled npm/Yarn because this API has no third-party runtime dependencies. Local image scanning caught and resolved findings in OpenSSL and unused npm dependencies before publication.
- A saved Terraform plan is applied only after the configured environment gate; app releases deploy the tested image by digest.

Backend encryption, access controls, versioning and OIDC trust are bootstrap requirements. They cannot be verified by scanning these infrastructure roots. A saved plan can contain sensitive values even when its text output redacts them; restrict artifact access and keep its retention short.

## Explicit Checkov exceptions

Exceptions are inline on the affected Azure resources, never global blanket exclusions. They apply to the shared configuration, including the Production learning profile. Reassess them before hosting real workloads.

| Check | Exception and remaining work |
| --- | --- |
| CKV_AZURE_237 | Standard ACR is used. Dedicated Premium data endpoints are not enabled. |
| CKV_AZURE_166 | Pipeline scanning is enforced before push; registry quarantine/verification workflow is not implemented. These controls are not equivalent. |
| CKV_AZURE_167 | Premium registry retention is not enabled; untagged ACR cleanup is an operator task. Preserve images needed for rollback. |
| CKV_AZURE_233 | ACR zone redundancy is not configured. The single-region registry remains a regional dependency. |
| CKV_AZURE_165 | ACR geo-replication is not configured; the project deploys independent regional registries in two clouds. |
| CKV_AZURE_139 | ACR uses an authenticated public endpoint to support GitHub-hosted image publishing. For private registries, move publishing to private runners and add Premium/private endpoint networking. |
| CKV_AZURE_164 | Images deploy by digest but are not signed or admission-verified. Add OCI signing/attestations and signature enforcement before treating provenance as authenticated. |
| CKV_AZURE_226 | Managed OS disks support the selected VM family; ephemeral OS disks are not configured. |
| CKV_AZURE_170 | Dev and Staging use Free cluster management. The Terraform expression selects Standard for Production. |
| CKV_AZURE_232 | Application and system pods share the learning cluster's node pool. Separate and taint system pools for real production. |
| CKV_AZURE_117 | Azure platform-managed disk encryption and host encryption are used; a customer-managed disk encryption set is not provisioned. |

The default Checkov run covers resources declared in this repository, not downloaded external module internals. It pins module sources but does not prove those modules satisfy every Checkov policy. Before real production, scan the resolved Terraform plan and external modules, review their IAM policies and network rules, and close or explicitly approve findings against your organization's requirements.

## Production work still required

Separate monitoring installation from application deployment and reduce the application role to namespace-scoped access; the current release role is cluster administrator because it installs monitoring CRDs. Isolate environment credentials, cloud accounts/subscriptions and ephemeral runners. Add durable backup/restore testing, workload autoscaling, image signing and verification, TLS ingress, appropriate registry isolation and redundancy, and organization-specific policy enforcement.

The Production profile changes capacity, replica count, disruption budget, AKS management tier and AWS NAT availability. It is a deployment profile for the exercise, not a claim of production readiness. There is no stateful data replication or automated cross-cloud traffic failover.
