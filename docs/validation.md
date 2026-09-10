# Validation record

Checks recorded on 2026-09-08 through 2026-09-10. Cloud deployment has not been performed. The local Kubernetes demo uses no cloud resources.

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
| Docker Compose monitoring, 2026-09-08 | Application health/readiness passed; Prometheus target is up and request metrics were collected; Grafana 13.2.1 authenticated successfully, loaded all 6 dashboard panels, and connected to Prometheus |
| Trivy application image scan | Trivy 0.73.0 reported 0 HIGH/CRITICAL findings after updating Alpine packages and removing unused npm/Yarn; the initial image had 6 HIGH findings |
| GitHub publication | Published to the [public portfolio repository](https://github.com/VinayReddi7206/multi-cloud-cicd-pipeline-with-kubernetes-terraform-observability) on main; local credentials and generated files excluded; Trivy source secret scan passed before publication |
| GitHub-hosted CI | [Run 34254299244 passed](https://github.com/VinayReddi7206/multi-cloud-cicd-pipeline-with-kubernetes-terraform-observability/actions/runs/34254299244) for commit `96ec975`: application and deployment-script tests, Helm checks, AWS/Azure Terraform validation, Checkov, Docker build, Trivy and tested-image artifact upload |
| Terraform platform locking | HashiCorp-signed provider packages verified for Windows AMD64 and Linux AMD64; both platform hashes committed so Linux CI can initialize with a read-only lock file |
| Local Kubernetes deployment, 2026-09-09 | kind 0.33.0 with pinned Kubernetes 1.35.8; Node.js Service responds with cloud=local; dedicated kubeconfig leaves the user's default context separate |
| Local Kubernetes monitoring | kube-prometheus-stack 88.6.1 deployed; three persistent volumes bound; application scrape target is up; Grafana 13.2.0 authenticates, loads the dashboard and connects to Prometheus; CPU, memory, request rate, latency and zero-error queries return data |
| Actual Helm rollback | A deliberately nonexistent image tag failed the upgrade; Helm --atomic restored the working image and the original application Service/version check passed |
| Local demo automation | PowerShell syntax and actionlint passed; [run 34350649504 passed](https://github.com/VinayReddi7206/multi-cloud-cicd-pipeline-with-kubernetes-terraform-observability/actions/runs/34350649504) for `e818b98`, including local Kubernetes deployment, Prometheus scraping and actual automatic rollback after the image scan |
| Grafana browser check | Sign-in, dashboard search, and opening the six-panel application dashboard passed. Browser use exposed an OOM restart with the initial 384Mi limit; the local limit was increased to 768Mi, then navigation was repeated with zero restarts on the replacement pod |
| Pod self-healing, 2026-09-09 | Deleting the local application pod produced a new ready pod with a different UID; the Service continued to return the original application version after recovery |
| Outage alert lifecycle, 2026-09-09 | Application scaled to zero at 17:46:12 UTC; the existing two-minute ApplicationUnavailable rule was observed firing at 17:49:09 UTC and was received by local Alertmanager. Original replica count restored; the Service, healthy scraping, and alert clearance passed by 17:49:39 UTC. No external notification receivers were configured |
| GitHub deployment bootstrap, 2026-09-09 | Created and read back all 12 AWS/Azure Plan and target environments. All restrict deployment to main; the 6 targets require a reviewer. Repeating Dev bootstrap preserved the existing rules and passed |
| Cloud readiness report, 2026-09-09 | Correctly reported Dev blocked: cloud deployment disabled, cloud variables missing, and no private runners registered. The report includes variable names and protection status without credential values |
| Cloud workflow access guard | Test dispatches [34388233090](https://github.com/VinayReddi7206/multi-cloud-cicd-pipeline-with-kubernetes-terraform-observability/actions/runs/34388233090) and [34388236606](https://github.com/VinayReddi7206/multi-cloud-cicd-pipeline-with-kubernetes-terraform-observability/actions/runs/34388236606) stopped at the disabled access check as intended. Terraform plan/apply and release quality/publish/deploy jobs were skipped |
| Hosted monitoring verification update | [Run 34389008955 passed](https://github.com/VinayReddi7206/multi-cloud-cicd-pipeline-with-kubernetes-terraform-observability/actions/runs/34389008955) for commit ccbe5fc, including cluster setup, scraping, rollback, pod replacement and alert recovery |
| Grafana credential recovery, 2026-09-10 | The administrator had been renamed in Grafana, while the access helper still assumed admin. Restored the managed password, verified the actual account name before synchronizing the Secret, and confirmed authenticated dashboard/data-source access. The normal check then passed without recovery. Repeated the local Helm upgrade and confirmed the managed username and working login were preserved |
| Local monitoring audit, 2026-09-10 | All 15 scrape targets healthy, all 6 dashboard queries returned data, and all 3 monitoring PVCs bound. Temporary pending missed-evaluation warnings cleared; only the expected Watchdog alert remained |

Normal CI now runs the scanned image in kind on the same standard runner, writes evidence to the job summary, and uploads no artifacts. The two temporary image artifacts from the earlier runs were removed. The manually dispatched cloud release still uses a short-lived image artifact.

The local recovery drill writes `.validation/local-drill-result.json` with individual results and timestamps. CI includes the same drill and adds this report to its job summary; consult the [latest CI runs](https://github.com/VinayReddi7206/multi-cloud-cicd-pipeline-with-kubernetes-terraform-observability/actions/workflows/ci.yaml) for hosted evidence. Follow the [demo walkthrough](demo.md) to reproduce the deployment and recovery checks.

The initial hosted run exposed missing Linux package hashes in lock files generated on Windows. Adding the publisher-verified platform hashes fixed validation without changing provider versions or disabling checksum verification.

Run 34388112386 passed its static/security gates and deployed the application, but its initial Prometheus scrape check timed out after 90 seconds. That run did not capture enough target details to establish the discovery failure's cause. Verification now allows a bounded five-minute discovery period, reports elapsed time and failure diagnostics, and replaces stale result files before checking. Consult subsequent hosted runs for the new behavior; the original timeout is retained here as part of the validation history.

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
