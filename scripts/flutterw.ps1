param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$FlutterArgs
)

$sdkCandidates = @(
  $env:FLUTTER_ROOT,
  $env:FLUTTER_HOME,
  $env:FLUTTER_SDK,
  'C:\flutter'
) | Where-Object { $_ } | Select-Object -Unique

$flutterExecutable = $null

foreach ($candidate in $sdkCandidates) {
  $possiblePath = Join-Path $candidate 'bin\flutter.bat'

  if (Test-Path $possiblePath) {
    $flutterExecutable = $possiblePath
    break
  }
}

if (-not $flutterExecutable) {
  $flutterOnPath = Get-Command flutter -ErrorAction SilentlyContinue

  if ($flutterOnPath) {
    $flutterExecutable = $flutterOnPath.Source
  }
}

if (-not $flutterExecutable) {
  Write-Error 'Flutter SDK not found. Set FLUTTER_ROOT, FLUTTER_HOME, or FLUTTER_SDK, or add flutter to PATH.'
  exit 1
}

& $flutterExecutable @FlutterArgs
exit $LASTEXITCODE
