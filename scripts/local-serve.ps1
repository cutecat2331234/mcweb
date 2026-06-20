# Start McWeb on localhost:3000 (local development).

param(

    [switch]$SyncAssets,

    [switch]$RebuildFrontend

)



$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

Set-Location $Root



$env:PORT = if ($env:PORT) { $env:PORT } else { "3000" }

$env:VITE_RUBY_AUTO_BUILD = "false"



if (-not (Test-Path "$Root\config\local.yml")) {
    Write-Host "==> config/local.yml not found — running bin/setup-local-config"
    ruby "$Root\bin\setup-local-config" 2>$null
    if (-not (Test-Path "$Root\config\local.yml")) {
        Write-Host "    Or open http://127.0.0.1:$($env:PORT)/setup to configure database and secrets."
    }
}



if ($SyncAssets) {

    $env:MCWEB_SYNC_ASSETS = "1"

}



if ($RebuildFrontend -or -not (Test-Path "$Root\public\vite-dev\.vite\manifest.json")) {

    Write-Host "==> Building frontend assets (vite-dev)..."

    bundle exec rails tailwindcss:build

    npx vite build --mode development

}



& "$Root\bin\local-serve" @args

