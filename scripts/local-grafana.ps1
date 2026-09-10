[CmdletBinding()]
param([switch]$ResetAdminPassword, [string]$AdminLogin)
. "$PSScriptRoot/local-common.ps1"
Assert-LocalCluster
if ($AdminLogin -and -not $ResetAdminPassword) { throw '-AdminLogin is only used during explicit admin password recovery.' }
$reportPath = Join-Path $LocalState 'local-grafana-result.json'
$report = [ordered]@{
    checkedAt = (Get-Date).ToUniversalTime().ToString('o')
    cluster = $LocalCluster
    success = $false
    adminResetPerformed = $false
}
$report | ConvertTo-Json | Set-Content -LiteralPath $reportPath -Encoding utf8
try {
    $secret = (Invoke-Checked kubectl ($LocalKubeArgs + @('get', 'secret', 'monitoring-grafana', '-n', 'monitoring', '-o', 'json'))) | ConvertFrom-Json
    $username = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($secret.data.'admin-user'))
    $password = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($secret.data.'admin-password'))
    if ([string]::IsNullOrWhiteSpace($username) -or [string]::IsNullOrWhiteSpace($password)) { throw 'Expected a local chart-managed admin credential.' }
    if ($AdminLogin) { $username = $AdminLogin }
    if ($ResetAdminPassword) {
        # Grafana persists its password in the database; updating a Secret does not change it.
        # Send the existing managed password through stdin, never command arguments or logs.
        $resetOutput = $password | & kubectl @LocalKubeArgs exec -i -n monitoring deployment/monitoring-grafana -c grafana -- grafana cli --homepath /usr/share/grafana --config /etc/grafana/grafana.ini --configOverrides cfg:default.paths.data=/var/lib/grafana admin reset-admin-password --user-id 1 --password-from-stdin 2>&1
        if ($LASTEXITCODE -ne 0 -or -not ($resetOutput -match 'Admin password changed successfully')) { throw 'Grafana admin password recovery failed. CLI output was withheld to protect credentials.' }
        $report.adminResetPerformed = $true
        Write-Host 'Restored the local Grafana admin password to the existing Kubernetes Secret.'
    }
    $check = @'
async function main() {
  let text = '';
  for await (const chunk of process.stdin) text += chunk;
  let credentials;
  try { credentials = JSON.parse(text); } catch { throw Error('Invalid Grafana credential input'); }
  const { username, password } = credentials;
  if (typeof username !== 'string' || typeof password !== 'string') throw Error('Invalid Grafana credential input');
  const authorization = 'Basic ' + Buffer.from(`${username}:${password}`).toString('base64');
  async function get(path, allowMissing = false) {
    const response = await fetch(`http://monitoring-grafana.monitoring${path}`, {
      headers: { Authorization: authorization }, signal: AbortSignal.timeout(15000)
    });
    if (allowMissing && response.status === 404) return null;
    if (!response.ok) throw Error(`Grafana ${path} returned HTTP ${response.status}`);
    return response.json();
  }
  const user = await get('/api/user');
  if (user.login !== username || !user.isGrafanaAdmin) throw Error('Unexpected Grafana identity');
  let dashboard;
  for (let attempt = 0; attempt < 12; attempt++) {
    dashboard = await get('/api/dashboards/uid/multicloud-app', true);
    if (dashboard) break;
    await new Promise(resolve => setTimeout(resolve, 5000));
  }
  if (!dashboard || dashboard.dashboard.panels.length !== 6) throw Error('Expected the six-panel application dashboard');
  const sources = await get('/api/datasources');
  const source = sources.find(item => item.type === 'prometheus');
  if (!source) throw Error('The Prometheus data source is missing');
  const health = await get(`/api/datasources/uid/${encodeURIComponent(source.uid)}/health`);
  if (health.status !== 'OK') throw Error('Grafana cannot query Prometheus');
  console.log(JSON.stringify({ login: 'passed', dashboard: dashboard.dashboard.title, panels: 6, prometheusDataSource: 'passed' }));
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
'@
    $inputPayload = @{ username = $username; password = $password } | ConvertTo-Json -Compress
    $output = $inputPayload | & kubectl @LocalKubeArgs exec -i -n app-local deployment/multicloud-app -- node -e $check
    if ($LASTEXITCODE -ne 0) { throw 'Authenticated Grafana verification failed. For a known local credential mismatch, use -ResetAdminPassword to restore the chart-managed login.' }
    $report.grafana = $output | ConvertFrom-Json
    if ($AdminLogin) {
        # Align the managed username only after confirming this is the real admin login.
        $patchPath = Join-Path $LocalState 'grafana-admin-login-patch.json'
        try {
            @{ data = @{ 'admin-user' = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($username)) } } | ConvertTo-Json | Set-Content -LiteralPath $patchPath -Encoding utf8
            Invoke-Checked kubectl ($LocalKubeArgs + @('patch', 'secret', 'monitoring-grafana', '-n', 'monitoring', '--type=merge', '--patch-file', $patchPath)) | Out-Null
        } finally { if (Test-Path -LiteralPath $patchPath) { Remove-Item -LiteralPath $patchPath } }
    }
    $report.success = $true
    Write-Host 'PASS: Grafana admin login, six-panel dashboard, and Prometheus data source.'
} catch {
    $report.error = $_.Exception.Message
    throw
} finally {
    $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding utf8
}
