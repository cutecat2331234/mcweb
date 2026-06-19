# Start McWeb on localhost:3000 using GitHub-built frontend assets (no local vite/npm build).
param(
    [switch]$SyncAssets
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

$env:PORT = if ($env:PORT) { $env:PORT } else { "3000" }
$env:VITE_RUBY_AUTO_BUILD = "false"

if ($SyncAssets) {
    $env:MCWEB_SYNC_ASSETS = "1"
}

& "$Root\bin\local-serve" @args
