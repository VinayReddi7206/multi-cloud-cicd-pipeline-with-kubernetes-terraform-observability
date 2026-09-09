# Validation record

Checks recorded on 2026-09-08 and 2026-09-09. Cloud deployment has not been performed. The local Kubernetes demo uses no cloud resources.

| Check | Result |
| --- | --- |
| Node.js API tests | 4 passed on Node.js 24.19.0 |
| Workstation prerequisites | All 9 tools detected using the refreshed Windows PATH; Node.js 24.19.0, GitHub CLI 2.100.0, AWS CLI 2.36.40, and Docker engine 29.7.2 verified |
| Deployment script failure-handling tests | 5 scenarios passed using mocked Helm/kubectl/jq: success, smoke failure, first-release smoke failure, smoke-pod creation failure, Helm upgrade failure |
| Terraform formatting | Passed |
| AWS Terraform provider validation | Passed, using locked AWS provider 6.63.0 |
| Azure Terraform provider validation | Passed, using locked AzureRM provider 4.81.0 |
| Checkov 3.3.16 | 44 passed, 0 failed, 11 explicitly skipped, 0 parsing errors |
| Helm application lint | Passed for Local, Dev, Staging, and Production |
| Application chart rendering | Production resources parsed; replica count and readiness endpoint verified |
| Monitoring chart rendering | Pinned kube-prometheus-stack 88.6.1 rendered 107 resources; scrape selector, persistent storage and application alerts verified |
| GitHub Actions validation | actionlint 1.7.12 passed; custom runner labels declared |
| YAML and dashboard parsing | 19 configuration YAML files and Grafana dashboard JSON parsed |
| Docker Compose configuration | Passed with the monitoring profile |
| Docker image build and runtime | Passed; application runs as a non-root user with a read-only filesystem; all 4 API tests also passed inside the patched image on Node.js 24.20.0 |
| Local monitoring | Application health/readiness passed; Prometheus target is up and request metrics were collected; Grafana 13.2.1 authenticated successfully, loaded all 6 dashboard panels, and connected to Prometheus |
| Trivy application image scan | Trivy 0.73.0 reported 0 HIGH/CRITICAL findings after updating Alpine packages and removing unused npm/Yarn; the initial image had 6 HIGH findings |
| GitHub publication | Published to the [public portfolio repository](https://github.com/VinayReddi7206/multi-cloud-cicd-pipeline-with-kubernetes-terraform-observability) on main; local credentials and generated files excluded; Trivy source secret scan passed before publication |
| GitHub-hosted CI | [Run 34254299244 passed](https://github.com/VinayReddi7206/multi-cloud-cicd-pipeline-with-kubernetes-terraform-observability/actions/runs/34254299244) for commit `96ec975`: application and deployment-script tests, Helm checks, AWS/Azure Terraform validation, Checkov, Docker build, Trivy and tested-image artifact upload |
| Terraform platform locking | HashiCorp-signed provider packages verified for Windows AMD64 and Linux AMD64; both platform hashes committed so Linux CI can initialize with a read-only lock file |
| Local Kubernetes deployment, 2026-09-09 | kind 0.33.0 with pinned Kubernetes 1.35.8; Node.js Service responds with cloud=local; dedicated kubeconfig leaves the user's default context separate |
| Local Kubernetes monitoring | kube-prometheus-stack 88.6.1 deployed; three persistent volumes bound; application scrape target is up; Grafana authenticates, loads the dashboard and connects to Prometheus; CPU, memory, request rate, latency and zero-error queries return data |
| Actual Helm rollback | A deliberately nonexistent image tag failed the upgrade; Helm --atomic restored the working image and the original application Service/version check passed |
| Local demo automation | PowerShell syntax and actionlint passed; CI now runs the local deployment and rollback after the image scan. See the [current CI runs](https://github.com/VinayReddi7206/multi-cloud-cicd-pipeline-with-kubernetes-terraform-observability/actions/workflows/ci.yaml) for hosted results |

Normal CI now runs the scanned image in kind on the same standard runner, writes evidence to the job summary, and uploads no artifacts. The two temporary image artifacts from the earlier runs were removed. The manually dispatched cloud release still uses a short-lived image artifact.

The initial hosted run exposed missing Linux package hashes in lock files generated on Windows. Adding the publisher-verified platform hashes fixed validation without changing provider versions or disabling checksum verification.

## Not yet verified

- Cloud account authentication, quotas, supported regional VM/Kubernetes configurations, identity bootstrap and Terraform state access.
- Terraform plan/apply against actual accounts.
- Private deployment runners and GitHub OIDC authentication to the clouds.
- Live AKS/EKS deployment, registry authentication and image pull, metrics scraping, PVC provisioning, live rollback, Azure Monitor ingestion and Slack alert delivery.

Static configuration checks and mocked rollback tests do not establish that the cloud deployment works. Follow the setup guide, complete a Dev deployment in each cloud, and record live results here.

The Checkov exceptions and external-module coverage limits are listed in [security.md](security.md). The Production profile still requires the production work documented there. The Trivy result covers the application image at scan time, not the Prometheus/Grafana images or future rebuilds.

## Reproduce local checks

```powershell
Push-Location app
node --test --experimental-test-coverage
Pop-Location
terraform fmt -check -recursive infra
terraform -chdir=infra/aws init -backend=false -input=false
terraform -chdir=infra/aws validate
terraform -chdir=infra/azure init -backend=false -input=false
terraform -chdir=infra/azure validate
helm lint helm/multicloud-app -f helm/environments/dev.yaml
helm lint helm/multicloud-app -f helm/environments/staging.yaml
helm lint helm/multicloud-app -f helm/environments/production.yaml
checkov --config-file .checkov.yaml
```

Run `bash scripts/test-deploy.sh` using Bash with its Unix utilities on PATH (Git Bash or Linux). The scripts use Helm 3. Actionlint was run with its optional ShellCheck and Pyflakes integrations disabled; Bash syntax and the rollback scenarios were checked separately.

Temporary validation tools, downloaded providers, rendered output and scan reports are ignored by Git. Provider lock files and project sources are retained.
