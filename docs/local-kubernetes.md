# Kubernetes demo without cloud provisioning

This mode runs the Node.js app, Prometheus, Grafana and Alertmanager inside a single-node kind cluster on your computer. It requires no AWS/Azure account or cloud resources. The AKS/EKS configurations remain available for a future cloud deployment.

## Start

Use Docker Desktop with Linux containers, kubectl, Helm 3 and PowerShell. The setup script supports Windows AMD64 and Linux AMD64; the GitHub runner uses PowerShell 7 and Helm 3.19.0. Allow several GB of memory and disk space for Kubernetes, monitoring, and downloaded images. The first run downloads more than a GB of images.

From the repository root:

```powershell
./scripts/local-up.ps1
./scripts/local-access.ps1
```

The script downloads kind 0.33.0 into the ignored `.tools` directory and verifies its official release checksum. Kubernetes 1.35.8 is pinned by image digest. A dedicated kubeconfig in `.validation/kubeconfig-local` keeps the default Kubernetes context separate. The scripts reject remote Docker sockets and Kubernetes API addresses.

`local-up.ps1` builds the image, loads it into kind, installs kube-prometheus-stack 88.6.1 with smaller local storage/memory settings, provisions the dashboard, and deploys the application with Helm. It verifies the application Service and Prometheus scrape target. Use `-SkipBuild` only when `multicloud-demo:local` already contains the app version you want to run. Use a unique `-ImageTag` when changing the app so Kubernetes performs an update.

| Service | Local address |
| --- | --- |
| Application | http://127.0.0.1:18080/api/info |
| Grafana | http://127.0.0.1:13000 |
| Prometheus | http://127.0.0.1:19090 |

Grafana's username is `admin`. `local-access.ps1` saves its generated password in `.validation/local-grafana-password.txt`; this is ignored by Git. Under **Dashboards**, find **Multi-Cloud Application**. These ports differ from the Docker Compose demo so either mode can be accessed without reusing its ports.

## Exercise the deployment

```powershell
1..100 | ForEach-Object { Invoke-RestMethod http://127.0.0.1:18080/api/info -TimeoutSec 5 | Out-Null }
./scripts/local-verify.ps1 -TestRollback
```

The rollback test deliberately requests a nonexistent image tag with image pulling disabled. Helm must fail the upgrade, automatically restore the previous revision, and pass the original Service/version check. The result is saved in `.validation/local-kubernetes-result.json`. The app has one replica with a surge of one, so the old healthy pod can continue serving while the broken replacement fails.

Request-rate and latency panels need multiple metric scrapes. Kubernetes CPU and memory panels are available in this mode because the full cluster monitoring stack is installed.

## CI

Pull requests and pushes to `main` build and scan the image, then deploy that same image into kind on a standard GitHub-hosted Ubuntu runner. CI checks Service access, Prometheus scraping, and an actual failed-upgrade rollback, then removes its temporary cluster. The validation result appears in the job summary.

Standard hosted runners are free for public repositories. Normal CI keeps the image on the same temporary runner, disables the Trivy cache, and uploads no artifacts. The manually dispatched cloud release still uses a one-day image artifact to pass the tested image to its registry jobs. See [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions).

## Stop and resume

Stop the browser access processes:

```powershell
./scripts/local-access.ps1 -Stop
```

To stop this cluster and release its CPU/memory while preserving its container data:

```powershell
docker stop multicloud-local-control-plane
```

Resume with `docker start multicloud-local-control-plane`, then run `local-up.ps1 -SkipBuild` and `local-access.ps1`. Port forwards may need restarting after a Grafana or application pod is replaced: run `local-access.ps1 -Stop`, then `local-access.ps1`.

To intentionally delete this demo cluster and its monitoring data:

```powershell
./scripts/local-access.ps1 -Stop
# Windows; Linux uses .tools/kind/kind instead.
./.tools/kind/kind.exe delete cluster --name multicloud-local --kubeconfig .validation/kubeconfig-local
```

## What this demonstrates

This mode demonstrates actual Kubernetes scheduling, Helm deployments, probes, metrics scraping, dashboards, persistent volume provisioning, and automatic rollback. kind uses its default local-path storage and CNI. NetworkPolicy is disabled in the local application profile because this CNI does not enforce it; cloud profiles retain their NetworkPolicies.

It does not verify AKS/EKS provisioning, ACR/ECR authentication, cloud workload identities, Azure Monitor, private deployment runners, or cross-cloud releases. External alert delivery remains optional and unconfigured.

References: [kind quick start](https://kind.sigs.k8s.io/docs/user/quick-start/), [kind 0.33.0 release and pinned node images](https://github.com/kubernetes-sigs/kind/releases/tag/v0.33.0).
