Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repositoryRoot = Split-Path $PSScriptRoot -Parent
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
$originalUserPath = [Environment]::GetEnvironmentVariable("PATH", "User")
$originalReleasesUrl = $env:NZOVU_RELEASES_URL
$originalApiUrl = $env:NZOVU_API_URL
$originalInstallDir = $env:NZOVU_INSTALL_DIR
$server = $null
$version = "0.0.1"
$tag = "v$version"
$commit = "0123456789abcdef0123456789abcdef01234567"
$buildDate = "2026-08-17T12:34:56Z"
$binaryName = "nzovu-$tag-windows-amd64.exe"
$stagingDir = Join-Path $testRoot "staging"
$releaseRoot = Join-Path $testRoot "releases"
$releaseDir = Join-Path $releaseRoot "download/$tag"
$installDir = Join-Path $testRoot "install"
$binaryPath = Join-Path $stagingDir $binaryName
$metadataPath = "$binaryPath.release"
$archivePath = Join-Path $releaseDir "nzovu-$tag-windows-amd64.zip"
$installer = Join-Path $PSScriptRoot "install.ps1"
$pwsh = (Get-Process -Id $PID).Path

function New-TestArchive {
    Compress-Archive -Path $binaryPath, $metadataPath -DestinationPath $archivePath -Force
    Write-TestChecksum
}

function Write-TestChecksum {
    $hash = (Get-FileHash $archivePath -Algorithm SHA256).Hash.ToLower()
    "$hash  $([IO.Path]::GetFileName($archivePath))" | Set-Content "$archivePath.sha256" -Encoding ascii
}

function Invoke-TestInstall([string]$RequestedVersion, [string]$ExpectedError = "") {
    $output = (& $pwsh -NoProfile -File $runner $installer $RequestedVersion 2>&1 | Out-String)
    $result = $LASTEXITCODE
    if ($ExpectedError) {
        if ($result -eq 0 -or -not $output.Contains($ExpectedError)) {
            throw "Expected installer failure '$ExpectedError', exit ${result}: $output"
        }
        if ((Get-FileHash (Join-Path $installDir "nzovu.exe")).Hash -ne (Get-FileHash $binaryPath).Hash) {
            throw "Failed installation modified the installed binary."
        }
    } elseif ($result -ne 0) {
        throw "Installer failed (${result}): $output"
    }
}

try {
    New-Item -ItemType Directory -Force -Path $stagingDir, $releaseDir | Out-Null
    Push-Location $repositoryRoot
    try {
        & go build -trimpath "-ldflags=-X github.com/adrien19/nzovu/pkg/version.Version=$version -X github.com/adrien19/nzovu/pkg/version.GitCommit=$commit -X github.com/adrien19/nzovu/pkg/version.BuildDate=$buildDate" -o $binaryPath .
        if ($LASTEXITCODE -ne 0) { throw "Failed to build installer fixture." }
    } finally { Pop-Location }
    "version=$tag`ncommit=$commit`nbuild_date=$buildDate" | Set-Content $metadataPath -Encoding ascii
    New-TestArchive
    @{ tag_name = $tag } | ConvertTo-Json | Set-Content (Join-Path $releaseRoot "latest.json")

    $runner = Join-Path $testRoot "run-installer.ps1"
    @'
param([string]$Installer, [string]$RequestedVersion)
$ErrorActionPreference = "Stop"
if (-not $IsWindows) {
    # A host-native fixture exercises Windows asset names on Unix; ZIP extraction loses execute permissions.
    function Expand-Archive {
        param($Path, $DestinationPath, [switch]$Force)
        Microsoft.PowerShell.Archive\Expand-Archive @PSBoundParameters
        Get-ChildItem $DestinationPath -Filter *.exe | ForEach-Object {
            & chmod +x $_.FullName
            if ($LASTEXITCODE -ne 0) { throw "Failed to make fixture executable." }
        }
    }
}
& $Installer -Version $RequestedVersion
exit $LASTEXITCODE
'@ | Set-Content $runner

    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = $listener.LocalEndpoint.Port
    $listener.Stop()
    $python = if ($IsWindows) { "python" } else { "python3" }
    $server = Start-Process $python -ArgumentList "-m", "http.server", "$port", "--bind", "127.0.0.1", "--directory", "`"$releaseRoot`"" -PassThru -RedirectStandardOutput (Join-Path $testRoot "server.log") -RedirectStandardError (Join-Path $testRoot "server-error.log")
    $env:NZOVU_RELEASES_URL = "http://127.0.0.1:$port"
    $env:NZOVU_API_URL = "$env:NZOVU_RELEASES_URL/latest.json"
    $env:NZOVU_INSTALL_DIR = $installDir
    for ($attempt = 0; $attempt -lt 50; $attempt++) {
        try {
            Invoke-WebRequest $env:NZOVU_API_URL -TimeoutSec 1 | Out-Null
            break
        } catch {
            if ($attempt -eq 49) { throw }
            Start-Sleep -Milliseconds 100
        }
    }

    Invoke-TestInstall $version
    $output = (& (Join-Path $installDir "nzovu.exe") --version | Out-String)
    if ($LASTEXITCODE -ne 0 -or -not $output.Contains("Nzovu v$version") -or -not $output.Contains("Git Commit: $commit") -or -not $output.Contains("Built:      $buildDate")) {
        throw "Installed binary metadata differs: $output"
    }
    if (Test-Path (Join-Path $installDir "chronoqueue.exe")) { throw "Legacy binary name installed." }
    Invoke-TestInstall ""
    Invoke-TestInstall $tag

    "version=v0.0.2`ncommit=$commit`nbuild_date=$buildDate" | Set-Content $metadataPath -Encoding ascii
    New-TestArchive
    Invoke-TestInstall $version "does not match requested version"
    "version=$tag`ncommit=abcdefabcdefabcdefabcdefabcdefabcdefabcd`nbuild_date=$buildDate" | Set-Content $metadataPath -Encoding ascii
    New-TestArchive
    Invoke-TestInstall $version "commit does not match"
    "version=$tag`ncommit=$commit`nbuild_date=$buildDate" | Set-Content $metadataPath -Encoding ascii
    New-TestArchive
    ("0" * 64) | Set-Content "$archivePath.sha256" -Encoding ascii
    Invoke-TestInstall $version "Checksum mismatch"
    Compress-Archive -Path $metadataPath -DestinationPath $archivePath -Force
    Write-TestChecksum
    Invoke-TestInstall $version "Binary '$binaryName' not found"
    Invoke-TestInstall "not-semver" "Invalid version"
    Invoke-TestInstall "0.0.1-01" "Invalid version"
    Write-Host "PowerShell installer fixtures passed."
} finally {
    if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force }
    [Environment]::SetEnvironmentVariable("PATH", $originalUserPath, "User")
    $env:NZOVU_RELEASES_URL = $originalReleasesUrl
    $env:NZOVU_API_URL = $originalApiUrl
    $env:NZOVU_INSTALL_DIR = $originalInstallDir
    if (Test-Path $testRoot) { Remove-Item -Recurse -Force $testRoot }
}
