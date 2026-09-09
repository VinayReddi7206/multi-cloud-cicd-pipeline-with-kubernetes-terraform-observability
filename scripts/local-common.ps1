$ErrorActionPreference = 'Stop'
$LocalRoot = Split-Path $PSScriptRoot -Parent
$LocalState = Join-Path $LocalRoot '.validation'
$LocalKubeconfig = Join-Path $LocalState 'kubeconfig-local'
$LocalCluster = 'multicloud-local'
$LocalContext = 'kind-multicloud-local'
$LocalKubeArgs = @('--kubeconfig', $LocalKubeconfig, '--context', $LocalContext)
$LocalWindows = $env:OS -eq 'Windows_NT'

function Invoke-Checked {
    param([string]$Executable, [string[]]$Arguments)
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Executable failed with exit code $LASTEXITCODE." }
}

function Get-LocalHelm {
    $bundled = Join-Path $LocalRoot '.tools/helm/windows-amd64/helm.exe'
    if ($LocalWindows -and (Test-Path -LiteralPath $bundled)) { return $bundled }
    return (Get-Command helm -ErrorAction Stop).Source
}

function Get-LocalKind {
    $directory = Join-Path $LocalRoot '.tools/kind'
    New-Item -ItemType Directory -Force $directory | Out-Null
    if ($LocalWindows) {
        $binary = Join-Path $directory 'kind.exe'
        $asset = 'kind-windows-amd64'
        $expected = '4b22adaa135368c5a465d56bbd8e520cbea87272a06ca00b6078e7b81515c9fc'
    } else {
        $binary = Join-Path $directory 'kind'
        $asset = 'kind-linux-amd64'
        $expected = 'aee6151561422756b764a4ae28e7f44cda5af5a9eead3cc9985112b1de8d8e0d'
    }
    if (-not (Test-Path -LiteralPath $binary)) {
        Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/kubernetes-sigs/kind/releases/download/v0.33.0/$asset" -OutFile $binary
    }
    if ((Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) {
        throw 'kind did not match the official v0.33.0 release checksum.'
    }
    if (-not $LocalWindows) { Invoke-Checked chmod @('+x', $binary) }
    return $binary
}

function Assert-LocalDocker {
    if ($env:DOCKER_HOST -and $env:DOCKER_HOST -notmatch '^(npipe|unix)://') {
        throw 'Use a local Docker socket for this demo; remote Docker hosts are not supported.'
    }
    $endpoint = Invoke-Checked docker @('context', 'inspect', '--format', '{{.Endpoints.docker.Host}}')
    if ($endpoint -notmatch '^(npipe|unix)://') { throw 'The selected Docker context is not local.' }
    $os = Invoke-Checked docker @('info', '--format', '{{.OSType}}')
    if ($os -ne 'linux') { throw 'Start Docker Desktop with Linux containers.' }
}

function Assert-LocalCluster {
    if (-not (Test-Path -LiteralPath $LocalKubeconfig)) { throw 'Run scripts/local-up.ps1 first.' }
    $server = Invoke-Checked kubectl ($LocalKubeArgs + @('config', 'view', '--minify', '-o', 'jsonpath={.clusters[0].cluster.server}'))
    if (([uri]$server).Host -notin @('127.0.0.1', 'localhost', '[::1]')) {
        throw 'Refusing to use a Kubernetes API outside this laptop.'
    }
}
