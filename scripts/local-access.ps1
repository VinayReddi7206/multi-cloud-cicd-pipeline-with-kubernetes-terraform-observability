[CmdletBinding()]
param([switch]$Stop)
. "$PSScriptRoot/local-common.ps1"
$recordPath = Join-Path $LocalState 'local-port-forwards.json'
$records = @()
if (Test-Path -LiteralPath $recordPath) { $records = @(Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json) }
$active = @()
foreach ($record in $records) {
    $process = Get-Process -Id $record.processId -ErrorAction SilentlyContinue
    if ($process -and $process.ProcessName -eq 'kubectl' -and $process.StartTime.ToUniversalTime().Ticks.ToString() -eq $record.startTicks) {
        if ($Stop) { Stop-Process -Id $process.Id -ErrorAction Stop }
        else { $active += $record }
    }
}
if ($Stop) {
    '[]' | Set-Content -LiteralPath $recordPath -Encoding utf8
    Write-Host 'Stopped the project port forwards. Kubernetes continues running locally.'
    return
}
Assert-LocalCluster
$kubectl = (Get-Command kubectl -ErrorAction Stop).Source
$services = @(
    @{ name = 'app'; namespace = 'app-local'; service = 'multicloud-app'; port = 18080; remote = 80 },
    @{ name = 'grafana'; namespace = 'monitoring'; service = 'monitoring-grafana'; port = 13000; remote = 80 },
    @{ name = 'prometheus'; namespace = 'monitoring'; service = 'monitoring-kube-prometheus-prometheus'; port = 19090; remote = 9090 }
)
foreach ($service in $services) {
    if (-not @($active | Where-Object { $_.name -eq $service.name }).Count) {
        $start = @{
            FilePath = $kubectl
            ArgumentList = @('--kubeconfig', ('"' + $LocalKubeconfig + '"'), '--context', $LocalContext, 'port-forward', '-n', $service.namespace, "service/$($service.service)", "$($service.port):$($service.remote)", '--address=127.0.0.1')
            RedirectStandardOutput = Join-Path $LocalState "$($service.name)-port-forward.log"
            RedirectStandardError = Join-Path $LocalState "$($service.name)-port-forward-error.log"
            PassThru = $true
        }
        if ($LocalWindows) { $start.WindowStyle = 'Hidden' }
        $process = Start-Process @start
        $active += [pscustomobject]@{ name = $service.name; processId = $process.Id; startTicks = $process.StartTime.ToUniversalTime().Ticks.ToString() }
        ConvertTo-Json -InputObject @($active) | Set-Content -LiteralPath $recordPath -Encoding utf8
    }
}
foreach ($service in $services) {
    $ready = $false
    for ($attempt = 0; $attempt -lt 15; $attempt++) {
        $client = New-Object System.Net.Sockets.TcpClient
        try { $client.Connect('127.0.0.1', $service.port); $ready = $true; break }
        catch { Start-Sleep -Seconds 1 }
        finally { $client.Dispose() }
    }
    if (-not $ready) { throw "The $($service.name) port forward failed; inspect .validation/$($service.name)-port-forward-error.log." }
    Write-Host "$($service.name): http://127.0.0.1:$($service.port)"
}
$encodedPassword = Invoke-Checked kubectl ($LocalKubeArgs + @('get', 'secret', 'monitoring-grafana', '-n', 'monitoring', '-o', 'jsonpath={.data.admin-password}'))
$passwordPath = Join-Path $LocalState 'local-grafana-password.txt'
[System.IO.File]::WriteAllText($passwordPath, [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encodedPassword)))
Write-Host 'Grafana username: admin. Password saved in the Git-ignored .validation/local-grafana-password.txt file.'
