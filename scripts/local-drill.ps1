[CmdletBinding()]
param()
. "$PSScriptRoot/local-common.ps1"
Assert-LocalCluster

function Get-DrillJson {
    param([string]$Url)
    $payload = Invoke-Checked kubectl ($LocalKubeArgs + @('exec', '-n', 'monitoring', 'deployment/monitoring-grafana', '-c', 'grafana', '--', 'wget', '-T', '10', '-qO-', $Url))
    return ($payload | ConvertFrom-Json)
}

function Wait-DrillCondition {
    param([scriptblock]$Check, [string]$Description, [int]$TimeoutSeconds = 180)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        if (& $Check) { return }
        Start-Sleep -Seconds 5
    } while ((Get-Date) -lt $deadline)
    throw "Timed out waiting for $Description."
}

$prometheusUrl = 'http://monitoring-kube-prometheus-prometheus.monitoring:9090'
$alertmanagerUrl = 'http://monitoring-kube-prometheus-alertmanager.monitoring:9093'
$applicationUrl = 'http://multicloud-app.app-local/api/info'
$upQuery = [Uri]::EscapeDataString('up{job="multicloud-app",namespace="app-local"}')
$resultPath = Join-Path $LocalState 'local-drill-result.json'
$result = [ordered]@{
    startedAt = (Get-Date).ToUniversalTime().ToString('o')
    cluster = $LocalCluster
    selfHealing = 'not run'
    alertFired = 'not run'
    alertmanagerReceived = 'not run'
    alertResolved = 'not run'
    recovery = 'not needed'
    success = $false
}
$restoreReplicas = $false
try {
    # Check the actually loaded receiver configuration, without printing credentials.
    $alertmanagerStatus = Get-DrillJson "$alertmanagerUrl/api/v2/status"
    $receiverConfig = $alertmanagerStatus.config.original
    if (-not $receiverConfig -or $receiverConfig -match '(?m)^\s*[a-zA-Z0-9_]+_configs\s*:') {
        throw 'This local drill requires Alertmanager with no external notification integrations.'
    }
    $rules = Get-DrillJson "$prometheusUrl/api/v1/rules?type=alert"
    $appRule = @($rules.data.groups | ForEach-Object { $_.rules } | Where-Object { $_.name -eq 'ApplicationUnavailable' })
    if ($appRule.Count -ne 1 -or $appRule[0].health -ne 'ok') { throw 'The ApplicationUnavailable rule must be loaded and healthy.' }
    $original = (Invoke-Checked kubectl ($LocalKubeArgs + @('get', 'deployment', 'multicloud-app', '-n', 'app-local', '-o', 'json'))) | ConvertFrom-Json
    $originalReplicas = [int]$original.spec.replicas
    if ($originalReplicas -lt 1 -or $original.status.availableReplicas -ne $originalReplicas) { throw 'Start with a fully available local application.' }
    $baseline = Get-DrillJson $applicationUrl
    if ($baseline.cloud -ne 'local') { throw 'The drill only targets the local application.' }
    $result.originalReplicas = $originalReplicas
    $result.version = $baseline.version
    Wait-DrillCondition -Description 'a healthy baseline scrape and inactive outage alert' -Check {
        $scrapes = Get-DrillJson "$prometheusUrl/api/v1/query?query=$upQuery"
        $alerts = Get-DrillJson "$prometheusUrl/api/v1/alerts"
        (@($scrapes.data.result | Where-Object { $_.value[1] -eq '1' }).Count -gt 0) -and
        (@($alerts.data.alerts | Where-Object { $_.labels.alertname -eq 'ApplicationUnavailable' }).Count -eq 0)
    }

    $pods = (Invoke-Checked kubectl ($LocalKubeArgs + @('get', 'pods', '-n', 'app-local', '-l', 'app.kubernetes.io/instance=multicloud-app,app.kubernetes.io/name=multicloud-app', '-o', 'json'))) | ConvertFrom-Json
    $deletedPod = @($pods.items | Where-Object { -not $_.metadata.deletionTimestamp })[0]
    $oldUids = @($pods.items | ForEach-Object { $_.metadata.uid })
    $result.deletedPod = $deletedPod.metadata.name
    Write-Host 'Deleting one local application pod; Kubernetes must create a healthy replacement.'
    Invoke-Checked kubectl ($LocalKubeArgs + @('delete', 'pod', $deletedPod.metadata.name, '-n', 'app-local', '--wait=true', '--timeout=60s'))
    Wait-DrillCondition -Description 'a new ready application pod' -Check {
        $current = (Invoke-Checked kubectl ($LocalKubeArgs + @('get', 'pods', '-n', 'app-local', '-l', 'app.kubernetes.io/instance=multicloud-app,app.kubernetes.io/name=multicloud-app', '-o', 'json'))) | ConvertFrom-Json
        $replacement = @($current.items | Where-Object {
            $_.metadata.uid -notin $oldUids -and -not $_.metadata.deletionTimestamp -and
            @($_.status.conditions | Where-Object { $_.type -eq 'Ready' -and $_.status -eq 'True' }).Count -gt 0
        })
        if ($replacement.Count -gt 0) { $result.replacementPod = $replacement[0].metadata.name; return $true }
        return $false
    }
    $replaced = Get-DrillJson $applicationUrl
    if ($replaced.version -ne $baseline.version -or $replaced.cloud -ne 'local') { throw 'The replacement pod serves an unexpected application.' }
    $result.selfHealing = 'passed'
    Write-Host 'PASS: Kubernetes replaced the deleted pod and the Service serves the same version.'

    Write-Host 'Temporarily scaling the local app to zero. Waiting for the existing two-minute outage alert.'
    # Restore the original count even if polling or an assertion fails after this point.
    $restoreReplicas = $true
    $result.outageStartedAt = (Get-Date).ToUniversalTime().ToString('o')
    Invoke-Checked kubectl ($LocalKubeArgs + @('scale', 'deployment/multicloud-app', '-n', 'app-local', '--replicas=0', "--current-replicas=$originalReplicas"))
    Wait-DrillCondition -Description 'ApplicationUnavailable to fire' -TimeoutSeconds 360 -Check {
        $alerts = Get-DrillJson "$prometheusUrl/api/v1/alerts"
        @($alerts.data.alerts | Where-Object { $_.labels.alertname -eq 'ApplicationUnavailable' -and $_.state -eq 'firing' }).Count -gt 0
    }
    $result.alertFired = 'passed'
    $result.firedAt = (Get-Date).ToUniversalTime().ToString('o')
    Write-Host 'PASS: Prometheus reports ApplicationUnavailable as firing.'
    Wait-DrillCondition -Description 'Alertmanager to receive the outage alert' -Check {
        $alerts = @(Get-DrillJson "$alertmanagerUrl/api/v2/alerts")
        @($alerts | Where-Object { $_.labels.alertname -eq 'ApplicationUnavailable' }).Count -gt 0
    }
    $result.alertmanagerReceived = 'passed'
    Write-Host 'PASS: Alertmanager received the alert; external receivers are unconfigured.'
} finally {
    try {
        if ($restoreReplicas) {
            $result.recovery = 'in progress'
            Write-Host "Restoring the original application replica count: $originalReplicas."
            Invoke-Checked kubectl ($LocalKubeArgs + @('scale', 'deployment/multicloud-app', '-n', 'app-local', "--replicas=$originalReplicas"))
            Invoke-Checked kubectl ($LocalKubeArgs + @('rollout', 'status', 'deployment/multicloud-app', '-n', 'app-local', '--timeout=180s'))
            $recovered = Get-DrillJson $applicationUrl
            if ($recovered.version -ne $baseline.version -or $recovered.cloud -ne 'local') { throw 'Application recovery returned an unexpected version.' }
            $result.recovery = 'passed'
        }
    } finally {
        $result | ConvertTo-Json | Set-Content -LiteralPath $resultPath -Encoding utf8
    }
}

Wait-DrillCondition -Description 'healthy scraping and cleared Prometheus/Alertmanager alerts' -Check {
    $scrapes = Get-DrillJson "$prometheusUrl/api/v1/query?query=$upQuery"
    $prometheusAlerts = Get-DrillJson "$prometheusUrl/api/v1/alerts"
    $receivedAlerts = @(Get-DrillJson "$alertmanagerUrl/api/v2/alerts")
    (@($scrapes.data.result | Where-Object { $_.value[1] -eq '1' }).Count -gt 0) -and
    (@($prometheusAlerts.data.alerts | Where-Object { $_.labels.alertname -eq 'ApplicationUnavailable' }).Count -eq 0) -and
    (@($receivedAlerts | Where-Object { $_.labels.alertname -eq 'ApplicationUnavailable' }).Count -eq 0)
}
$result.alertResolved = 'passed'
$result.resolvedAt = (Get-Date).ToUniversalTime().ToString('o')
$result.success = $true
$result | ConvertTo-Json | Set-Content -LiteralPath $resultPath -Encoding utf8
Write-Host 'PASS: the application recovered, scraping is healthy, and the outage alert cleared.'
