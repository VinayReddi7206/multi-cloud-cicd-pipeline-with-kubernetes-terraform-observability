[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')][string]$Repository,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9-]+$')][string]$Reviewer,
    [ValidateSet('dev', 'staging', 'production')][string[]]$Environments = @('dev', 'staging', 'production')
)
. "$PSScriptRoot/github-common.ps1"
$repo = Invoke-ProjectGithub "repos/$Repository"
if (-not $repo.permissions.admin) { throw 'Repository administrator access is required to configure deployment environments.' }
$reviewerAccount = Invoke-ProjectGithub "users/$Reviewer"
$existing = @(Get-ProjectGithubPages "repos/$Repository/environments" 'environments')
$variables = @(Get-ProjectGithubPages "repos/$Repository/actions/variables" 'variables')
$cloudSwitch = @($variables | Where-Object { $_.name -eq 'CLOUD_DEPLOYMENTS_ENABLED' })
if ($cloudSwitch.Count -eq 0) {
    Invoke-ProjectGithub "repos/$Repository/actions/variables" -Method POST -Body @{ name = 'CLOUD_DEPLOYMENTS_ENABLED'; value = 'false' } | Out-Null
} elseif ($cloudSwitch[0].value -ne 'false') {
    throw 'Cloud deployments are enabled. This no-spend bootstrap requires CLOUD_DEPLOYMENTS_ENABLED=false.'
}

foreach ($cloud in @('aws', 'azure')) {
    foreach ($environment in ($Environments | Select-Object -Unique)) {
        foreach ($suffix in @('-plan', '')) {
            $name = "$cloud-$environment$suffix"
            $found = @($existing | Where-Object { $_.name -eq $name })
            if ($found.Count -eq 0) {
                $reviewers = @()
                if ($suffix -eq '') { $reviewers = @(@{ type = 'User'; id = $reviewerAccount.id }) }
                Invoke-ProjectGithub "repos/$Repository/environments/$name" -Method PUT -Body @{
                    wait_timer = 0
                    prevent_self_review = $false
                    reviewers = $reviewers
                    deployment_branch_policy = @{ protected_branches = $false; custom_branch_policies = $true }
                } | Out-Null
                Invoke-ProjectGithub "repos/$Repository/environments/$name/deployment-branch-policies" -Method POST -Body @{ name = 'main'; type = 'branch' } | Out-Null
            }
            $current = Invoke-ProjectGithub "repos/$Repository/environments/$name"
            $status = Get-DeploymentEnvironmentStatus -Repository $Repository -Name $name -Environment $current
            if (-not $status.mainOnly -or ($suffix -eq '' -and -not $status.reviewRequired)) {
                throw "$name has different protection rules. Existing rules were preserved; review them before continuing."
            }
            Write-Host "READY: $name permits only main$(if ($suffix -eq '') { ' and requires deployment review' })."
        }
    }
}
Write-Host 'GitHub environments are configured. Cloud deployment remains disabled; no AWS/Azure resources or credentials were created.'
