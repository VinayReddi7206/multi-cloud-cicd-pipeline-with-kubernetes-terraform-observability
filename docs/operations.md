# Operations

Run cluster commands from an authorized machine with private network and DNS access. Check `kubectl config current-context` before changing anything.

## Verify a deployment

```bash
kubectl get nodes
kubectl get pods -n app-dev -o wide
kubectl rollout status deployment/multicloud-app -n app-dev
kubectl get servicemonitor -n app-dev
helm history multicloud-app -n app-dev
kubectl port-forward -n app-dev service/multicloud-app 8080:80
```

Open `http://localhost:8080/api/info` and verify cloud, environment and commit. Services use ClusterIP; no public application load balancer or TLS ingress is provisioned. For public access, add a reviewed ingress controller, DNS and TLS configuration, then update allowed caller namespaces in the chart's network policy.

## Grafana and Prometheus

```bash
kubectl port-forward -n monitoring service/monitoring-grafana 3000:80
```

In a private terminal, obtain the generated Grafana password:

```bash
kubectl get secret monitoring-grafana -n monitoring -o jsonpath='{.data.admin-password}' | base64 --decode
```

Use login `admin`. Never paste the password into CI logs or a support issue. The Multicloud dashboard covers requests, server-error ratio, p95 latency, app memory and pod CPU/memory. The stack also includes Kubernetes dashboards.

Prometheus metrics use 5-minute rates; send requests and wait for at least two scrapes. An empty error panel can mean no 5xx series has been created yet. During a fresh install, the application-unavailable alert can fire until the app is deployed.

Azure Terraform enables Container Insights through the monitoring agent and a Log Analytics workspace. AWS control-plane and VPC flow logs go to CloudWatch. Prometheus application metrics are collected separately in each cluster; no shared cross-cloud metrics store is configured.

Monitoring PVCs use encrypted cloud-managed disks. Storage classes use `Delete`; deleting PVCs can delete their disks. Monitoring Helm upgrades do not guarantee CRD schema upgrades—follow the pinned chart's upgrade instructions before changing versions.

## Optional Slack alerts

Create an incoming Slack webhook yourself and put its URL in a local file outside source control. The following command reads the file without embedding the URL in command history:

```bash
kubectl create secret generic slack-webhook -n monitoring --from-file=url=/secure/path/slack-webhook-url
bash scripts/install-monitoring.sh aws monitoring/alertmanager-slack.values.yaml.example
```

Replace `aws` with `azure` for AKS. Apply this to each cluster that should send alerts. If you want alerts to persist across automated releases, add the same extra values file to the monitoring step in `release.yaml`; otherwise the next release uses default values. Test with a controlled alert in Dev, then verify resolution. Teams is not configured in this version.

## Rollback and failure drill

A readiness failure causes Helm's atomic upgrade to revert to the prior release. A failed fresh installation is uninstalled. An HTTP smoke-test failure also triggers rollback (or uninstall if there was no previous release). The workflow exits unsuccessfully even when rollback succeeds.

In Dev, record the current revision, then deliberately upgrade to a nonexistent image tag using `--atomic --wait --timeout 2m`. Confirm that the command fails and the last healthy revision serves traffic. Do not perform this experiment in Production.

For an explicit manual rollback:

```bash
helm history multicloud-app -n app-dev
# Replace REVISION with a reviewed, known-good revision from the history.
helm rollback multicloud-app REVISION -n app-dev --wait --timeout 10m
```

Keep tagged registry images needed by rollback. ECR tags are immutable and release tags include the commit/run/attempt. Kubernetes uses digests. Failed deployments in one cloud do not revert a successful deployment in the other; inspect the release manifest artifacts and decide which environment needs repair.

## Teardown

Back up anything needed from monitoring first. Stop releases, confirm the cloud/account/context, then remove application and monitoring releases and their PVCs only if their data is disposable. Remove bootstrap runners attached to the project networks before deleting those networks.

In the correct Terraform directory and using the original environment input file:

```bash
terraform plan -destroy -var-file=environments/dev.tfvars -out=destroy.tfplan
terraform show destroy.tfplan
terraform apply destroy.tfplan
```

ECR is intentionally configured with `force_delete=false`: destruction fails if tagged images remain. Remove only the intended environment's images after confirming they are no longer needed, then regenerate and review the destroy plan. Do not change `force_delete` merely to bypass this check.

State storage and OIDC identities are bootstrap resources and are not destroyed by these roots. Check cloud consoles for leftover disks, snapshots, NAT gateways, IPs, log workspaces, registries and runners. Stopping pods does not stop cluster and infrastructure charges.
