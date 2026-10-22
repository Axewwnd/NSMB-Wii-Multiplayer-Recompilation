# Build targets of the Android (arm64-v8a) native build configured by configure-android-ci.ps1 (CI version)
[CmdletBinding()]
param(
    [string[]]$Target = @('WiiCompiled'),
    [int]$Jobs = 10,
    [string]$BuildDirectory,
    [string]$LogPath,
    [switch]$KeepGoing
)

$ErrorActionPreference = 'Stop'

# Resolve workspace root (repo root)
$workspace = $PSScriptRoot
for ($i = 0; $i -lt 3; $i++) { $workspace = Split-Path $workspace }

$portableTools = Join-Path $workspace 'Launcher\artifacts\portable-tools'

# Default build/log directories if not provided
if (-not $BuildDirectory) { $BuildDirectory = Join-Path $workspace 'android-build' }
if (-not $LogPath) { $LogPath = Join-Path $workspace 'build-nsmbw\logs\build-android.log' }

# Use only the portable toolchain
$env:PATH = "$portableTools\CMake\bin;$portableTools\Ninja;$env:SystemRoot\System32;$env:SystemRoot"

$arguments = @('--build', $BuildDirectory)
foreach ($t in $Target) { $arguments += @('--target', $t) }
$arguments += @('--parallel', $Jobs)
if ($KeepGoing) { $arguments += @('--', '-k', '0') }

# Ensure log directory exists
$logDir = Split-Path $LogPath
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

$ErrorActionPreference = 'Continue'
& (Join-Path $portableTools 'CMake\bin\cmake.exe') @arguments 2>&1 |
    ForEach-Object { "$_" } | Out-File -LiteralPath $LogPath -Encoding utf8
exit $LASTEXITCODE