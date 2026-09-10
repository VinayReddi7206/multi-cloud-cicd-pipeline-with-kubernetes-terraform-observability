[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$')]
    [string]$ImageTag = 'local',
    [string]$ImageArchive,
    [switch]$SkipBuild
)
. "$PSScriptRoot/local-common.ps1"
$previousProvider = $env:KIND_EXPERIMENTAL_PROVIDER
Push-Location $LocalRoot
try {
    Assert-LocalDocker
    $env:KIND_EXPERIMENTAL_PROVIDER = 'docker'
    New-Item -ItemType Directory -Force $LocalState | Out-Null
    $kind = Get-LocalKind
    $helm = Get-LocalHelm
    $helmVersion = Invoke-Checked $helm @('version', '--short')
    if ($helmVersion -notmatch '^v3\.') { throw 'The demo requires Helm 3; CI uses 3.19.0.' }
    $clusters = @(Invoke-Checked $kind @('get', 'clusters'))
    if ($LocalCluster -notin $clusters) {
        Invoke-Checked $kind @('create', 'cluster', '--name', $LocalCluster, '--config', 'local/kind.yaml', '--kubeconfig', $LocalKubeconfig, '--wait', '180s')
    } else {
        Invoke-Checked $kind @('export', 'kubeconfig', '--name', $LocalCluster, '--kubeconfig', $LocalKubeconfig)
    }
    Assert-LocalCluster
    $image = "multicloud-demo:$ImageTag"
    if ($ImageArchive) {
        $archive = (Resolve-Path -LiteralPath $ImageArchive).Path
        Invoke-Checked docker @('load', '--input', $archive)
    } elseif (-not $SkipBuild) {
        Invoke-Checked docker @('build', '--pull', '-t', $image, '.')
    }
    Invoke-Checked docker @('image', 'inspect', $image, '--format', '{{.Id}}')
    Invoke-Checked $kind @('load', 'docker-image', $image, '--name', $LocalCluster)

    $repoArgs = @('--repository-config', (Join-Path $LocalState 'local-helm-repositories.yaml'), '--repository-cache', (Join-Path $LocalState 'local-helm-cache'))
    Invoke-Checked $helm (@('repo', 'add', 'prometheus-community', 'https://prometheus-community.github.io/helm-charts', '--force-update') + $repoArgs)
    Invoke-Checked $helm (@('repo', 'update', 'prometheus-community') + $repoArgs)
    $grafanaArgs = @()
    $existingGrafana = Invoke-Checked kubectl ($LocalKubeArgs + @('get', 'secret', 'monitoring-grafana', '-n', 'monitoring', '--ignore-not-found', '-o', 'json'))
    if ($existingGrafana) {
        $adminUser = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($existingGrafana | ConvertFrom-Json).data.'admin-user'))
        $grafanaArgs = @('--set-literal', "grafana.adminUser=$adminUser")
    }
    Invoke-Checked $helm (@('upgrade', '--install', 'monitoring', 'prometheus-community/kube-prometheus-stack', '--version', '88.6.1', '--namespace', 'monitoring', '--create-namespace', '--kubeconfig', $LocalKubeconfig, '--kube-context', $LocalContext, '-f', 'monitoring/values.yaml', '-f', 'monitoring/local-kubernetes.values.yaml', '--atomic', '--wait', '--timeout', '15m') + $repoArgs + $grafanaArgs)

    $dashboard = Invoke-Checked kubectl ($LocalKubeArgs + @('create', 'configmap', 'multicloud-dashboard', '-n', 'monitoring', '--from-file=multicloud.json=monitoring/dashboards/multicloud.json', '--dry-run=client', '-o', 'json'))
    $dashboard | & kubectl @LocalKubeArgs apply -f -
    if ($LASTEXITCODE -ne 0) { throw 'Dashboard configuration failed.' }
    Invoke-Checked kubectl ($LocalKubeArgs + @('label', 'configmap', 'multicloud-dashboard', '-n', 'monitoring', 'grafana_dashboard=1', '--overwrite'))
    $namespace = Invoke-Checked kubectl ($LocalKubeArgs + @('create', 'namespace', 'app-local', '--dry-run=client', '-o', 'json'))
    $namespace | & kubectl @LocalKubeArgs apply -f -
    if ($LASTEXITCODE -ne 0) { throw 'Application namespace creation failed.' }
    Invoke-Checked kubectl ($LocalKubeArgs + @('label', 'namespace', 'app-local', 'pod-security.kubernetes.io/enforce=restricted', '--overwrite'))
    Invoke-Checked $helm @('upgrade', '--install', 'multicloud-app', 'helm/multicloud-app', '--namespace', 'app-local', '--kubeconfig', $LocalKubeconfig, '--kube-context', $LocalContext, '-f', 'helm/environments/local.yaml', '--set-string', "image.tag=$ImageTag", '--atomic', '--wait', '--timeout', '5m', '--history-max', '10')
    & "$PSScriptRoot/local-verify.ps1" -ExpectedVersion $ImageTag
    Write-Host 'Local Kubernetes is ready. Run scripts/local-access.ps1 to open local service ports.'
} finally {
    $env:KIND_EXPERIMENTAL_PROVIDER = $previousProvider
    Pop-Location
}
