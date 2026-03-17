param(
  [string]$AppVersion,
  [switch]$SkipBuild,
  [string]$SourceDir,
  [string]$OutputDir
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')

if (-not $AppVersion) {
  $versionLine = Select-String -Path (Join-Path $repoRoot 'pubspec.yaml') -Pattern '^version:\s*(.+)$' |
    Select-Object -First 1

  if (-not $versionLine) {
    throw 'Could not determine app version from pubspec.yaml.'
  }

  $AppVersion = (($versionLine.Matches[0].Groups[1].Value.Trim()) -split '\+')[0]
}

if (-not $SourceDir) {
  $SourceDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'
}

if (-not $OutputDir) {
  $OutputDir = Join-Path $repoRoot 'build\dist'
}

if (-not $SkipBuild) {
  $flutterArgs = @('build', 'windows', '--release')

  if (-not [string]::IsNullOrWhiteSpace($env:KICK_APTABASE_APP_KEY_RELEASE)) {
    $flutterArgs += "--dart-define=KICK_APTABASE_APP_KEY_RELEASE=$($env:KICK_APTABASE_APP_KEY_RELEASE)"
  }
  if (-not [string]::IsNullOrWhiteSpace($env:KICK_APTABASE_HOST_RELEASE)) {
    $flutterArgs += "--dart-define=KICK_APTABASE_HOST_RELEASE=$($env:KICK_APTABASE_HOST_RELEASE)"
  }
  if (-not [string]::IsNullOrWhiteSpace($env:SENTRY_DSN)) {
    $flutterArgs += "--dart-define=SENTRY_DSN=$($env:SENTRY_DSN)"
  }
  $flutterArgs += '--dart-define=SENTRY_ENVIRONMENT=production'
  if (-not [string]::IsNullOrWhiteSpace($env:KICK_GLITCHTIP_TRACES_SAMPLE_RATE)) {
    $flutterArgs += "--dart-define=KICK_GLITCHTIP_TRACES_SAMPLE_RATE=$($env:KICK_GLITCHTIP_TRACES_SAMPLE_RATE)"
  }

  & (Join-Path $repoRoot 'scripts\flutterw.ps1') @flutterArgs
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
}

if (-not (Test-Path $SourceDir)) {
  throw "Windows release bundle was not found at '$SourceDir'."
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$resolvedSourceDir = (Resolve-Path $SourceDir).Path
$resolvedOutputDir = (Resolve-Path $OutputDir).Path
$resolvedRepoRoot = (Resolve-Path $repoRoot).Path
$portableArchive = Join-Path $resolvedOutputDir "kick-windows-$AppVersion-portable.zip"

if (Test-Path $portableArchive) {
  Remove-Item $portableArchive -Force
}

Compress-Archive -Path (Join-Path $resolvedSourceDir '*') -DestinationPath $portableArchive -Force

$isccExecutable = @(
  (Get-Command iscc -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue),
  (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
  (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

if (-not $isccExecutable) {
  throw 'Inno Setup 6 was not found. Install ISCC.exe or add it to PATH.'
}

$installerScript = Join-Path $repoRoot 'installer\windows\kick.iss'

if (-not (Test-Path $installerScript)) {
  throw "Installer script was not found at '$installerScript'."
}

& $isccExecutable `
  "/DAppVersion=$AppVersion" `
  "/DRepoRoot=$resolvedRepoRoot" `
  "/DSourceDir=$resolvedSourceDir" `
  "/DOutputDir=$resolvedOutputDir" `
  $installerScript

if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

Write-Host "Portable archive: $portableArchive"
Write-Host "Installer output dir: $resolvedOutputDir"
