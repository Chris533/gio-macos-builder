param(
    [string]$ProjectDir = (Get-Location).Path,
    [string]$Name = "",
    [string]$DisplayName = "",
    [string]$BundleId = "",
    [string]$Entry = "",
    [string]$Icon = "",
    [string]$Version = "",
    [string]$BuildNumber = "",
    [string]$Arch = "universal",
    [string]$MinMacos = "11.0",
    [string]$Ldflags = "",
    [string]$CgoLdflags = "",
    [string]$OutDir = "dist/macos",
    [string]$Image = "ghcr.io/chris533/gio-macos-builder:15.5"
)

$ErrorActionPreference = "Stop"
$ResolvedProject = (Resolve-Path $ProjectDir).Path
$RepoRoot = Split-Path -Parent $PSScriptRoot
$BuildCtxDir = if (Test-Path (Join-Path $RepoRoot "Dockerfile")) { $RepoRoot } else { Join-Path $RepoRoot "resources" }

function Convert-ToWslPath([string]$WinPath) {
    $full = [System.IO.Path]::GetFullPath($WinPath)
    if ($full -match '^([A-Za-z]):\\(.*)$') {
        $drive = $Matches[1].ToLowerInvariant()
        $rest = ($Matches[2] -replace '\\', '/')
        return "/mnt/$drive/$rest"
    }
    throw "Cannot convert path to WSL mount path: $WinPath"
}

$UseWslDocker = $false
if (Get-Command docker -ErrorAction SilentlyContinue) {
    & docker info *> $null
    if ($LASTEXITCODE -ne 0) { $UseWslDocker = $true }
} else {
    $UseWslDocker = $true
}

$BuilderArgs = @("--arch", $Arch, "--min-macos", $MinMacos, "--out", $OutDir)
if ($Name)        { $BuilderArgs += @("--name", $Name) }
if ($DisplayName) { $BuilderArgs += @("--display-name", $DisplayName) }
if ($BundleId)    { $BuilderArgs += @("--id", $BundleId) }
if ($Entry)       { $BuilderArgs += @("--entry", $Entry) }
if ($Icon)        { $BuilderArgs += @("--icon", $Icon) }
if ($Version)     { $BuilderArgs += @("--version", $Version) }
if ($BuildNumber) { $BuilderArgs += @("--build-number", $BuildNumber) }
if ($Ldflags)     { $BuilderArgs += @("--ldflags", $Ldflags) }
if ($CgoLdflags)  { $BuilderArgs += @("--cgo-ldflags", $CgoLdflags) }

if ($UseWslDocker) {
    $WslProject = Convert-ToWslPath $ResolvedProject
    $WslBuildCtx = Convert-ToWslPath $BuildCtxDir
    & wsl docker image inspect $Image *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Image $Image not cached locally; attempting pull or local build..." -ForegroundColor Cyan
        & wsl docker pull $Image
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Building $Image locally from $WslBuildCtx..." -ForegroundColor Cyan
            & wsl docker build -t $Image $WslBuildCtx
            if ($LASTEXITCODE -ne 0) { throw "Failed to build $Image" }
        }
    }
    & wsl docker run --rm -v "${WslProject}:/workspace" -v "gio-macos-cache:/cache" $Image @BuilderArgs
    if ($LASTEXITCODE -ne 0) { throw "macOS cross-build failed" }
} else {
    & docker image inspect $Image *> $null
    if ($LASTEXITCODE -ne 0) {
        & docker pull $Image
        if ($LASTEXITCODE -ne 0) {
            & docker build -t $Image $BuildCtxDir
            if ($LASTEXITCODE -ne 0) { throw "Failed to build $Image" }
        }
    }
    & docker run --rm -v "${ResolvedProject}:/workspace" -v "gio-macos-cache:/cache" $Image @BuilderArgs
    if ($LASTEXITCODE -ne 0) { throw "macOS cross-build failed" }
}
