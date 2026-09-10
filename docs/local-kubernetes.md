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

Grafana's initial username is `admin`. `local-access.ps1` reads the managed username and saves it in `.validation/local-grafana-username.txt`, with the password in `.validation/local-grafana-password.txt`; both are ignored by Git. Under **Dashboards**, find **Multi-Cloud Application**. These ports differ from the Docker Compose demo so either mode can be accessed without reusing its ports.

Check actual Grafana authentication and its Prometheus connection with `./scripts/local-grafana.ps1`. This also checks the six-panel dashboard, without requiring a port forward. CI runs the same check and records its report in the job summary.

If the saved password is rejected, Grafana's persistent database may no longer match the Kubernetes Secret. For this local demo, `./scripts/local-grafana.ps1 -ResetAdminPassword` restores the database's admin password to the existing Secret and verifies login. It passes credentials through standard input, never command arguments or printed output. This is an explicit recovery operation; the normal check and CI never reset passwords automatically. Run `local-access.ps1` afterward to refresh the saved password file. Do not use the recovery switch if you intend to preserve a manually changed admin password.

If the original admin account (ID 1) was renamed through Grafana, add `-AdminLogin YOUR_CURRENT_LOGIN` during recovery. The script verifies that login before synchronizing the username in the Kubernetes Secret. Monitoring setup preserves this managed username on subsequent Helm upgrades. Renaming the user in Grafana alone does not update Kubernetes configuration.

## Exercise the deployment

```powershell
1..100 | ForEach-Object { Invoke-RestMethod http://127.0.0.1:18080/api/info -TimeoutSec 5 | Out-Null }
./scripts/local-verify.ps1 -TestRollback
```

The rollback test deliberately requests a nonexistent image tag with image pulling disabled. Helm must fail the upgrade, automatically restore the previous revision, and pass the original Service/version check. The result is saved in `.validation/local-kubernetes-result.json`. The app has one replica with a surge of one, so the old healthy pod can continue serving while the broken replacement fails.

Request-rate and latency panels need multiple metric scrapes. Kubernetes CPU and memory panels are available in this mode because the full cluster monitoring stack is installed.

Verification waits up to five minutes for the initial application scrape, independently of pod readiness. A scrape timeout prints the application target health, monitoring pod status, ServiceMonitor and endpoint discovery information. The result file is replaced at the start of each verification and records failures, so an earlier successful report cannot mask a later failed check.

## Prove self-healing and alert recovery

```powershell
./scripts/local-drill.ps1
./scripts/local-access.ps1
```

The drill briefly interrupts this local demo. It deletes one application pod and verifies that the Deployment creates a new ready pod with a different UID and serves the same application version. It then scales the application to zero, waits for the existing `ApplicationUnavailable` rule to fire, and verifies Alertmanager receives it. The original replica count is restored in a `finally` block, including when an outage assertion fails. The final checks require a working Service, healthy scraping, and cleared alerts in both Prometheus and Alertmanager.

Allow about four to six minutes: the rule retains its normal two-minute pending period. The drill rejects nonlocal API addresses and any loaded Alertmanager configuration containing external notification integrations. It sends no Slack/Teams messages. Results and timestamps are written to `.validation/local-drill-result.json`; credentials are excluded.

Run `local-access.ps1` afterward to reconnect to the current pods. Each run restarts only the project's recorded port-forward processes; an old forward can remain listening until a request reveals that its pod is gone. If the terminal or computer is forcibly terminated during the outage, run `local-up.ps1 -SkipBuild` to restore the deployment, then restart local access.

## CI

Pull requests and pushes to `main` build and scan the image, then deploy that same image into kind on a standard GitHub-hosted Ubuntu runner. CI checks Service access, Prometheus scraping, an actual failed-upgrade rollback, pod replacement, and outage alert firing/recovery, then removes its temporary cluster. Both validation reports appear in the job summary.

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
