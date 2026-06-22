# Install portable Node + Claude Code for a Windows fleet host. No admin needed:
# node is a zip under %USERPROFILE%\nodejs, added to the USER PATH; claude-code is
# an npm global. Idempotent — safe to re-run. Adapted from the rcp fabric installer.
param(
    [string] $NodeVersion = 'v24.16.0',
    [string] $Arch        = 'win-x64'
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$nodeRoot = Join-Path $env:USERPROFILE 'nodejs'
$nodeDir  = Join-Path $nodeRoot ('node-{0}-{1}' -f $NodeVersion, $Arch)
$nodeExe  = Join-Path $nodeDir 'node.exe'
$npmCmd   = Join-Path $nodeDir 'npm.cmd'

if (-not (Test-Path $nodeExe)) {
    $url = "https://nodejs.org/dist/$NodeVersion/node-$NodeVersion-$Arch.zip"
    $zip = Join-Path $env:USERPROFILE 'node-portable.zip'
    Write-Host "downloading $url"
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $zip -TimeoutSec 600
    if (Test-Path $nodeRoot) { Remove-Item $nodeRoot -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $nodeRoot | Out-Null
    Expand-Archive -Path $zip -DestinationPath $nodeRoot -Force
    Remove-Item $zip -Force
}
Write-Host ('node: ' + (& $nodeExe --version))

# Global npm bin dirs for a zip node: the node dir itself and %APPDATA%\npm.
$npmGlobal = Join-Path $env:APPDATA 'npm'
$paths = @($nodeDir, $npmGlobal)

$cur = [Environment]::GetEnvironmentVariable('Path', 'User')
if ([string]::IsNullOrEmpty($cur)) { $cur = '' }
$changed = $false
foreach ($p in $paths) {
    if (($cur -split ';') -notcontains $p) { $cur = ($cur.TrimEnd(';') + ';' + $p).TrimStart(';'); $changed = $true }
}
if ($changed) { [Environment]::SetEnvironmentVariable('Path', $cur, 'User'); Write-Host 'user PATH updated' }

Write-Host 'installing @anthropic-ai/claude-code (global)...'
# npm's first invocation on a freshly-extracted zip node is flaky (cache/self-init
# can fail with a bare "npm error code 1"); retry a few times before giving up.
$claudeCmd = $null
for ($i = 1; $i -le 4; $i++) {
    & $npmCmd install -g @anthropic-ai/claude-code 2>&1 | Select-Object -Last 4
    $claudeCmd = @((Join-Path $nodeDir 'claude.cmd'), (Join-Path $npmGlobal 'claude.cmd')) |
                 Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($claudeCmd) { break }
    Write-Host ("npm install attempt {0} did not yield claude.cmd; retrying..." -f $i)
    Start-Sleep -Seconds 5
}
if ($claudeCmd) {
    Write-Host ('claude installed at: ' + $claudeCmd)
    Write-Host ('claude: ' + (& $claudeCmd --version))
} else {
    throw 'claude.cmd not found after npm install'
}
