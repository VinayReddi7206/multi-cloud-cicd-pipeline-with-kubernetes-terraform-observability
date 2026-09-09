[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')][string]$Repository,
    [ValidateSet('dev', 'staging', 'production')][string]$Environment = 'dev'
)
. "$PSScriptRoot/github-common.ps1"
$environments = @(Get-ProjectGithubPages "repos/$Repository/environments" 'environments')
$runners = @(Get-ProjectGithubPages "repos/$Repository/actions/runners" 'runners')
$repositoryVariables = @(Get-ProjectGithubPages "repos/$Repository/actions/variables" 'variables')
$enabled = @($repositoryVariables | Where-Object { $_.name -eq 'CLOUD_DEPLOYMENTS_ENABLED' -and $_.value -ceq 'true' }).Count -eq 1
$checks = @()
foreach ($cloud in @('aws', 'azure')) {
    foreach ($suffix in @('-plan', '')) {
        $name = "$cloud-$Environment$suffix"
        $found = @($environments | Where-Object { $_.name -eq $name })
        $entry = if ($found.Count) { $found[0] } else { $null }
        $protection = Get-DeploymentEnvironmentStatus -Repository $Repository -Name $name -Environment $entry
        $variables = @()
        if ($protection.exists) { $variables = @(Get-ProjectGithubPages "repos/$Repository/environments/$name/variables" 'variables') }
        $required = @('TF_VARS_JSON')
        if ($cloud -eq 'aws') {
            $required += @('AWS_REGION', 'AWS_INFRA_ROLE_ARN', 'TF_STATE_BUCKET')
            if ($suffix -eq '') { $required += @('AWS_ROLE_ARN', 'IMAGE_REPOSITORY', 'CLUSTER_NAME') }
        } else {
            $required += @('AZURE_INFRA_CLIENT_ID', 'AZURE_TENANT_ID', 'AZURE_SUBSCRIPTION_ID', 'TF_STATE_RESOURCE_GROUP', 'TF_STATE_STORAGE_ACCOUNT', 'TF_STATE_CONTAINER')
            if ($suffix -eq '') { $required += @('AZURE_CLIENT_ID', 'IMAGE_REPOSITORY', 'CLUSTER_NAME', 'ACR_NAME', 'AZURE_RESOURCE_GROUP') }
        }
        $present = @($variables | Where-Object { -not [string]::IsNullOrWhiteSpace($_.value) } | ForEach-Object { $_.name })
        $missing = @($required | Where-Object { $_ -notin $present })
        $inputsMatchEnvironment = $false
        $inputVariable = @($variables | Where-Object { $_.name -eq 'TF_VARS_JSON' })
        if ($inputVariable.Count) {
            try { $inputsMatchEnvironment = ($inputVariable[0].value | ConvertFrom-Json).environment -ceq $Environment }
            catch { $inputsMatchEnvironment = $false }
        }
        $runnerAvailable = $true
        if ($suffix -eq '') {
            $runnerAvailable = @($runners | Where-Object {
                $labels = @($_.labels | ForEach-Object { $_.name.ToLowerInvariant() })
                $_.status -eq 'online' -and -not $_.busy -and
                'self-hosted' -in $labels -and 'linux' -in $labels -and $cloud -in $labels -and $Environment -in $labels
            }).Count -gt 0
        }
        $ready = $protection.exists -and $protection.mainOnly -and ($suffix -ne '' -or $protection.reviewRequired) -and
            $missing.Count -eq 0 -and $inputsMatchEnvironment -and $runnerAvailable
        $checks += [ordered]@{
            name = $name
            exists = $protection.exists
            mainOnly = $protection.mainOnly
            reviewRequired = $protection.reviewRequired
            missingVariables = $missing
            inputsMatchEnvironment = $inputsMatchEnvironment
            runnerAvailable = $runnerAvailable
            configurationReady = $ready
        }
        $label = if ($ready) { 'READY' } else { 'BLOCKED' }
        Write-Host "${label}: $name; missing variables: $($missing -join ', '); runner available: $runnerAvailable."
    }
}
$report = [ordered]@{
    checkedAt = (Get-Date).ToUniversalTime().ToString('o')
    repository = $Repository
    environment = $Environment
    cloudDeploymentsEnabled = $enabled
    configurationReady = $enabled -and @($checks | Where-Object { -not $_.configurationReady }).Count -eq 0
    checks = $checks
    scope = 'GitHub configuration only. Does not verify credits, cloud permissions, private networking, quotas, or a live deployment.'
}
$reportPath = Join-Path $GithubStatePath "cloud-readiness-$Environment.json"
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportPath -Encoding utf8
Write-Host "Cloud workflows enabled: $enabled. Report: .validation/github/cloud-readiness-$Environment.json"
if (-not $report.configurationReady) { exit 2 }
