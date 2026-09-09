$ErrorActionPreference = 'Stop'
$GithubProjectRoot = Split-Path $PSScriptRoot -Parent
$GithubStatePath = Join-Path $GithubProjectRoot '.validation/github'
New-Item -ItemType Directory -Path $GithubStatePath -Force | Out-Null
$GithubCli = (Get-Command gh -ErrorAction SilentlyContinue).Source
if (-not $GithubCli -and $env:ProgramFiles) {
    $candidate = Join-Path $env:ProgramFiles 'GitHub CLI/gh.exe'
    if (Test-Path -LiteralPath $candidate) { $GithubCli = $candidate }
}
if (-not $GithubCli) { throw 'Install GitHub CLI and sign in with gh auth login.' }

function Invoke-ProjectGithub {
    param([string]$Endpoint, [string]$Method = 'GET', [object]$Body)
    $arguments = @('api', $Endpoint, '--method', $Method, '-H', 'Accept: application/vnd.github+json')
    $bodyPath = $null
    try {
        if ($null -ne $Body) {
            $bodyPath = Join-Path $GithubStatePath ([Guid]::NewGuid().ToString() + '.json')
            $Body | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $bodyPath -Encoding utf8
            $arguments += @('--input', $bodyPath)
        }
        $response = & $GithubCli @arguments
        if ($LASTEXITCODE -ne 0) { throw "GitHub $Method $Endpoint failed. No later setup steps were run." }
        if ($response) { return ($response | ConvertFrom-Json) }
    } finally {
        if ($bodyPath -and (Test-Path -LiteralPath $bodyPath)) { Remove-Item -LiteralPath $bodyPath }
    }
}

function Get-ProjectGithubPages {
    param([string]$Endpoint, [string]$Collection)
    $items = @()
    $page = 1
    do {
        $separator = if ($Endpoint.Contains('?')) { '&' } else { '?' }
        $response = Invoke-ProjectGithub "${Endpoint}${separator}per_page=100&page=$page"
        $batch = @($response.$Collection)
        $items += $batch
        $page++
    } while ($batch.Count -eq 100)
    return $items
}

function Get-DeploymentEnvironmentStatus {
    param([string]$Repository, [string]$Name, [object]$Environment)
    if ($null -eq $Environment) { return @{ exists = $false; mainOnly = $false; reviewRequired = $false } }
    $mainOnly = $false
    if ($Environment.deployment_branch_policy.custom_branch_policies) {
        $policies = @(Get-ProjectGithubPages "repos/$Repository/environments/$Name/deployment-branch-policies" 'branch_policies')
        $mainOnly = $policies.Count -eq 1 -and $policies[0].name -eq 'main' -and $policies[0].type -eq 'branch'
    }
    $reviewRules = @($Environment.protection_rules | Where-Object { $_.type -eq 'required_reviewers' -and $_.reviewers.Count -gt 0 })
    return @{ exists = $true; mainOnly = $mainOnly; reviewRequired = $reviewRules.Count -gt 0 }
}
