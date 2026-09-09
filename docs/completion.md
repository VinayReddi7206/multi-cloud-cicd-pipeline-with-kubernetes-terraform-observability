# Completion criteria

Target requested on 2026-09-09: **2026-09-10 end of day, India Standard Time**.

The original deliverable includes live deployments in Azure AKS and AWS EKS. It is not complete until those deployments and their CI/CD integrations have been verified. The owner has confirmed a strict zero cloud budget and no trial/promotional credits. Cloud provisioning therefore remains blocked; finishing the local demo or the configuration files does not satisfy the live-cloud requirement.

## Acceptance record

| Requirement | Implemented | Verified | Remaining evidence |
| --- | --- | --- | --- |
| Node.js application and Docker image | Yes | Native/container tests and image scan | None for the sample app |
| GitHub CI and security gates | Yes | Successful hosted runs | Rerun after changes |
| Terraform per cloud and environment | Yes | Formatting, provider validation, Checkov | Actual account plans and applies |
| Helm deployment and probes | Yes | Local kind deployment | AKS/EKS deployment |
| Rollback and recovery | Yes | Mocked script cases and real local cluster drills | Repeat in both cloud clusters |
| Prometheus/Grafana and persistent storage | Yes | Local scraping, dashboard, PVCs and alert lifecycle | Cloud CSI, cloud scraping and retention checks |
| GitHub deployment environments | Automated setup applied | 12 environments checked; main-only restrictions and 6 target review gates; Dev setup repeated successfully | Cloud identity and resource variables |
| Cloud state and OIDC identities | Bootstrap instructions | Not verified | State backends, scoped planning/apply/deployment identities and actual token exchange |
| Private deployment runners | Required labels/network documented | No project runners registered | Ephemeral runners in each private cloud network |
| ACR/ECR publishing | Workflow implemented | Not run | Same tested image pushed to both registries and deployed by digest |
| Azure Monitor | Terraform configured | Not run | Container Insights ingestion |
| Slack/Teams delivery | Optional Slack configuration supplied | Local Alertmanager only | Optional webhook and explicit delivery test |

## Remaining sequence for a live release

1. Establish usable cloud credits or an approved budget. Verify account eligibility, expiry, supported services, regional quotas and cleanup costs.
2. Authenticate AWS and Azure, provision the state backends, create the OIDC identities, and populate Dev environment variables.
3. Review an account-backed Terraform plan for each cloud, then provision Dev AKS/EKS and registries. Staging/Production profiles remain available; six live clusters are not needed for an initial two-cloud proof.
4. Register ephemeral runners with private network/DNS access to their corresponding clusters.
5. Enable cloud workflows, run the release, and verify registry digests, Service responses, monitoring, alerts and rollback in both clouds.
6. Record the cloud evidence in validation.md and exercise cleanup. Preserve required evidence and state before removing demo resources.

All live steps remain blocked under the current zero-budget/no-credit constraint. The repository can be presented as a tested local Kubernetes CI/CD project with cloud infrastructure configurations; it must not be presented as a completed live multi-cloud deployment.
