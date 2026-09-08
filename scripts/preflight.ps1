$ErrorActionPreference = 'Stop'
$taskTools = 'git', 'node', 'terraform', 'docker', 'kubectl', 'helm', 'gh', 'az', 'aws'
$taskMissing = @()
foreach ($taskTool in $taskTools) {
    $taskCommand = Get-Command $taskTool -ErrorAction SilentlyContinue
    if ($taskCommand) { Write-Output "OK       $taskTool ($($taskCommand.Source))" }
    else { Write-Output "MISSING  $taskTool"; $taskMissing += $taskTool }
}
if (Get-Command docker -ErrorAction SilentlyContinue) {
    docker info --format '{{.ServerVersion}}'
    if ($LASTEXITCODE -ne 0) { Write-Output 'Docker engine is unavailable. Start Docker Desktop.'; $taskMissing += 'Docker engine' }
}
if ($taskMissing.Count -gt 0) { exit 1 }
