# Recruiter demonstration

This project has a working local Kubernetes deployment and cloud infrastructure definitions for AKS/EKS. The cloud configurations have passed static validation; a live cloud deployment has not been performed. Present that distinction clearly.

## Prepare

Start Docker Desktop with Linux containers. If the local cluster is already running, open access with:

```powershell
./scripts/local-access.ps1
```

For a fresh installation, run `./scripts/local-up.ps1` first. The [local guide](local-kubernetes.md) includes pause, resume and cleanup commands.

## Walkthrough

1. Open the [public repository](https://github.com/VinayReddi7206/multi-cloud-cicd-pipeline-with-kubernetes-terraform-observability). Explain the architecture: a stateless Node.js API, Terraform per cloud, one shared Helm chart, and GitHub Actions gates before deployment.
2. Open the latest successful [CI run](https://github.com/VinayReddi7206/multi-cloud-cicd-pipeline-with-kubernetes-terraform-observability/actions/workflows/ci.yaml). Show tests, Terraform validation for both clouds, Checkov, Docker build and Trivy. Explain that the scanned image is then loaded into a temporary kind cluster on the same runner.
3. Open [the application](http://127.0.0.1:18080/api/info). Point out `cloud: local`, its environment and version. This is the deployed Kubernetes Service reached through a loopback port forward.
4. Open [Grafana](http://127.0.0.1:13000) and the **Multi-Cloud Application** dashboard. Explain request rate, error ratio, p95 latency, application memory, container CPU and working memory. Send traffic with the command below, then wait for multiple scrapes.
5. Run the rollback check. The intentionally bad image upgrade must fail; Helm restores the working revision. Explain why CI still considers an unexpected deployment failure a failure even when recovery succeeds.
6. Run the self-healing/alert drill. Show the new pod replacing the deleted pod, then the outage progressing to a firing alert and clearing after replica restoration. Prometheus sends the alert to local Alertmanager; external notifications are not configured.

```powershell
1..100 | ForEach-Object { Invoke-RestMethod http://127.0.0.1:18080/api/info -TimeoutSec 5 | Out-Null }
./scripts/local-verify.ps1 -TestRollback
./scripts/local-drill.ps1
./scripts/local-access.ps1
```

Allow roughly ten minutes for the complete walkthrough, including the real alert timer. For a short interview, show the CI job summary and saved local reports instead of rerunning every drill.

## Discuss the limits

- The local Deployment has one replica and a rolling-update surge of one. Replacing the only pod can cause a brief interruption; the bad-upgrade test retains the old healthy replica while its replacement fails.
- Local PVCs use kind's local-path storage. They demonstrate volume provisioning but do not validate cloud CSI drivers, replication or disaster recovery.
- kind's default CNI does not enforce NetworkPolicy, so the local profile explicitly disables it. The cloud profiles retain their policies.
- The two cloud configurations represent independent deployments. Global failover, a shared database, private runner provisioning and live cloud identity setup remain outside the verified local demo.
- Checkov has documented exceptions; a passing scan is not a compliance certification. The image vulnerability gate covers HIGH/CRITICAL findings at scan time.

Use [the validation record](validation.md) as the source of truth for completed checks and [the security guide](security.md) for the scope of the controls.
