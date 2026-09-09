[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$')]
    [string]$ExpectedVersion = 'local',
    [switch]$TestRollback
)
. "$PSScriptRoot/local-common.ps1"
Assert-LocalCluster
$helm = Get-LocalHelm
Push-Location $LocalRoot
try {
    Invoke-Checked kubectl ($LocalKubeArgs + @('rollout', 'status', 'deployment/multicloud-app', '-n', 'app-local', '--timeout=180s'))
    $smoke = "fetch('http://multicloud-app/api/info').then(async r=>{const b=await r.json();if(!r.ok||b.version!=='$ExpectedVersion'||b.cloud!=='local')throw Error(JSON.stringify(b));console.log(JSON.stringify(b))}).catch(e=>{console.error(e);process.exit(1)})"
    Invoke-Checked kubectl ($LocalKubeArgs + @('exec', '-n', 'app-local', 'deployment/multicloud-app', '--', 'node', '-e', $smoke))
    Invoke-Checked kubectl ($LocalKubeArgs + @('wait', '--for=condition=Ready', 'pods', '-n', 'monitoring', '-l', 'app.kubernetes.io/name=prometheus', '--timeout=180s'))
    $prometheusCheck = 'wget -qO- ''http://monitoring-kube-prometheus-prometheus.monitoring:9090/api/v1/query?query=up%7Bjob%3D%22multicloud-app%22%7D'''
    $metricsFound = $false
    for ($attempt = 0; $attempt -lt 18; $attempt++) {
        $payload = Invoke-Checked kubectl ($LocalKubeArgs + @('exec', '-n', 'monitoring', 'deployment/monitoring-grafana', '-c', 'grafana', '--', 'sh', '-c', $prometheusCheck))
        $query = $payload | ConvertFrom-Json
        if (@($query.data.result | Where-Object { $_.value[1] -eq '1' }).Count -gt 0) { $metricsFound = $true; break }
        Start-Sleep -Seconds 5
    }
    if (-not $metricsFound) { throw 'Prometheus did not discover a healthy application scrape target.' }
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
        Write-Host 'PASS: failed Helm upgrade automatically rolled back; original version serves traffic.'
    }
    [ordered]@{
        checkedAt = (Get-Date).ToUniversalTime().ToString('o')
        cluster = $LocalCluster
        version = $ExpectedVersion
        applicationService = 'passed'
        prometheusScraping = 'passed'
        atomicRollback = $(if ($TestRollback) { 'passed' } else { 'not run' })
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $LocalState 'local-kubernetes-result.json') -Encoding utf8
} finally { Pop-Location }
