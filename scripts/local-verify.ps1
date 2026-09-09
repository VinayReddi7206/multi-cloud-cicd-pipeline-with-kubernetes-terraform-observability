[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$')]
    [string]$ExpectedVersion = 'local',
    [switch]$TestRollback,
    [ValidateRange(30, 600)][int]$MetricsTimeoutSeconds = 300
)
. "$PSScriptRoot/local-common.ps1"
Assert-LocalCluster
$helm = Get-LocalHelm
$resultPath = Join-Path $LocalState 'local-kubernetes-result.json'
$result = [ordered]@{
    checkedAt = (Get-Date).ToUniversalTime().ToString('o')
    cluster = $LocalCluster
    version = $ExpectedVersion
    applicationService = 'not run'
    prometheusScraping = 'not run'
    atomicRollback = 'not run'
    success = $false
}
# Replace stale success evidence before any checks, including when a later check fails.
$result | ConvertTo-Json | Set-Content -LiteralPath $resultPath -Encoding utf8
Push-Location $LocalRoot
try {
    Invoke-Checked kubectl ($LocalKubeArgs + @('rollout', 'status', 'deployment/multicloud-app', '-n', 'app-local', '--timeout=180s'))
    $smoke = "fetch('http://multicloud-app/api/info').then(async r=>{const b=await r.json();if(!r.ok||b.version!=='$ExpectedVersion'||b.cloud!=='local')throw Error(JSON.stringify(b));console.log(JSON.stringify(b))}).catch(e=>{console.error(e);process.exit(1)})"
    Invoke-Checked kubectl ($LocalKubeArgs + @('exec', '-n', 'app-local', 'deployment/multicloud-app', '--', 'node', '-e', $smoke))
    $result.applicationService = 'passed'
    Invoke-Checked kubectl ($LocalKubeArgs + @('wait', '--for=condition=Ready', 'pods', '-n', 'monitoring', '-l', 'app.kubernetes.io/name=prometheus', '--timeout=180s'))
    $prometheusUrl = 'http://monitoring-kube-prometheus-prometheus.monitoring:9090'
    $upQuery = [Uri]::EscapeDataString('up{job="multicloud-app",namespace="app-local"}')
    $metricsFound = $false
    $discoveryStarted = Get-Date
    $discoveryDeadline = $discoveryStarted.AddSeconds($MetricsTimeoutSeconds)
    do {
        $payload = Invoke-Checked kubectl ($LocalKubeArgs + @('exec', '-n', 'monitoring', 'deployment/monitoring-grafana', '-c', 'grafana', '--', 'wget', '-T', '10', '-qO-', "$prometheusUrl/api/v1/query?query=$upQuery"))
        $query = $payload | ConvertFrom-Json
        if ($query.status -ne 'success') { throw 'Prometheus rejected the application scrape query.' }
        if (@($query.data.result | Where-Object { $_.value[1] -eq '1' }).Count -gt 0) { $metricsFound = $true; break }
        Start-Sleep -Seconds 5
    } while ((Get-Date) -lt $discoveryDeadline)
    $result.prometheusDiscoverySeconds = [math]::Round(((Get-Date) - $discoveryStarted).TotalSeconds, 1)
    if (-not $metricsFound) {
        $result.prometheusScraping = 'failed'
        try {
            $targets = (Invoke-Checked kubectl ($LocalKubeArgs + @('exec', '-n', 'monitoring', 'deployment/monitoring-grafana', '-c', 'grafana', '--', 'wget', '-T', '10', '-qO-', "$prometheusUrl/api/v1/targets?state=active"))) | ConvertFrom-Json
            $appTargets = @($targets.data.activeTargets | Where-Object { $_.labels.namespace -eq 'app-local' } | Select-Object scrapePool, health, lastError, lastScrape)
            Write-Host ('Application scrape diagnostics: ' + (ConvertTo-Json -InputObject $appTargets -Compress))
            Invoke-Checked kubectl ($LocalKubeArgs + @('get', 'pods', '-n', 'monitoring', '-o', 'wide'))
            Invoke-Checked kubectl ($LocalKubeArgs + @('get', 'servicemonitors', '-n', 'app-local'))
            Invoke-Checked kubectl ($LocalKubeArgs + @('get', 'endpointslices', '-n', 'app-local', '-l', 'kubernetes.io/service-name=multicloud-app'))
        } catch { Write-Warning "Could not finish scrape diagnostics: $($_.Exception.Message)" }
        throw "Prometheus did not discover a healthy application scrape target within $MetricsTimeoutSeconds seconds."
    }
    $result.prometheusScraping = 'passed'
    Write-Host 'PASS: application Service and Prometheus scraping.'
    if ($TestRollback) {
        $before = (Invoke-Checked kubectl ($LocalKubeArgs + @('get', 'deployment', 'multicloud-app', '-n', 'app-local', '-o', 'json'))) | ConvertFrom-Json
        # A nonexistent local tag must fail, then --atomic must restore the working image.
        $previousNativeErrorPreference = $PSNativeCommandUseErrorActionPreference
        try {
            $PSNativeCommandUseErrorActionPreference = $false
            & $helm upgrade multicloud-app helm/multicloud-app --namespace app-local --kubeconfig $LocalKubeconfig --kube-context $LocalContext --reuse-values --set-string image.tag=missing-rollback-test --atomic --wait --timeout 75s
            if ($LASTEXITCODE -eq 0) { throw 'Expected the deliberately broken upgrade to fail.' }
        } finally { $PSNativeCommandUseErrorActionPreference = $previousNativeErrorPreference }
        Invoke-Checked kubectl ($LocalKubeArgs + @('rollout', 'status', 'deployment/multicloud-app', '-n', 'app-local', '--timeout=180s'))
        $after = (Invoke-Checked kubectl ($LocalKubeArgs + @('get', 'deployment', 'multicloud-app', '-n', 'app-local', '-o', 'json'))) | ConvertFrom-Json
        if ($after.spec.template.spec.containers[0].image -ne $before.spec.template.spec.containers[0].image) { throw 'Rollback did not restore the original image.' }
        Invoke-Checked kubectl ($LocalKubeArgs + @('exec', '-n', 'app-local', 'deployment/multicloud-app', '--', 'node', '-e', $smoke))
        $result.atomicRollback = 'passed'
        Write-Host 'PASS: failed Helm upgrade automatically rolled back; original version serves traffic.'
    }
    $result.success = $true
} catch {
    $result.error = $_.Exception.Message
    throw
} finally {
    try { $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $resultPath -Encoding utf8 }
    finally { Pop-Location }
}
