# Download latest frontend-assets artifact from GitHub Actions (no local npm/vite build).
param(
    [string]$Repo = "cutecat2331234/mcweb",
    [string]$Workflow = "ci.yml",
    [string]$ArtifactName = "frontend-assets",
    [string]$Branch = "main"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

$Token = $env:GITHUB_TOKEN
if (-not $Token) { $Token = $env:GH_TOKEN }
if (-not $Token) {
    Write-Error "Set GITHUB_TOKEN or GH_TOKEN to download artifacts from GitHub Actions."
}

$Headers = @{
    Authorization = "Bearer $Token"
    Accept        = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
}

Write-Host "==> Finding latest successful CI run on $Branch…"
$runsUrl = "https://api.github.com/repos/$Repo/actions/workflows/$Workflow/runs?branch=$Branch&status=success&per_page=5"
$runs = Invoke-RestMethod -Uri $runsUrl -Headers $Headers
$run = $runs.workflow_runs | Where-Object { $_.conclusion -eq "success" } | Select-Object -First 1
if (-not $run) {
    Write-Error "No successful workflow run found. Push to main and wait for CI to finish."
}

Write-Host "    Run $($run.id) ($($run.head_sha.Substring(0,12)))"

$artifactsUrl = "https://api.github.com/repos/$Repo/actions/runs/$($run.id)/artifacts?per_page=100"
$artifacts = Invoke-RestMethod -Uri $artifactsUrl -Headers $Headers
$artifact = $artifacts.artifacts | Where-Object { $_.name -eq $ArtifactName } | Select-Object -First 1
if (-not $artifact) {
    Write-Error "Artifact '$ArtifactName' not found on run $($run.id). Ensure CI build-frontend job completed."
}

$zipPath = Join-Path $env:TEMP "mcweb-$ArtifactName-$($artifact.id).zip"
Write-Host "==> Downloading $($artifact.name) ($([math]::Round($artifact.size_in_bytes / 1MB, 1)) MB)…"

Invoke-WebRequest -Uri $artifact.archive_download_url -Headers $Headers -OutFile $zipPath

$extractRoot = Join-Path $env:TEMP "mcweb-assets-$($artifact.id)"
if (Test-Path $extractRoot) { Remove-Item -Recurse -Force $extractRoot }
New-Item -ItemType Directory -Path $extractRoot | Out-Null
Expand-Archive -Path $zipPath -DestinationPath $extractRoot -Force

function Copy-Tree($src, $dest) {
    if (-not (Test-Path $src)) { return }
    if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
    $parent = Split-Path -Parent $dest
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Copy-Item -Path $src -Destination $dest -Recurse -Force
}

# Artifact paths are relative to repo root inside the zip.
Copy-Tree (Join-Path $extractRoot "public/vite") (Join-Path $Root "public/vite")
Copy-Tree (Join-Path $extractRoot "app/assets/builds") (Join-Path $Root "app/assets/builds")
Copy-Tree (Join-Path $extractRoot "public/template-starter") (Join-Path $Root "public/template-starter")

Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
Remove-Item $extractRoot -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "==> Assets synced from GitHub Actions."
