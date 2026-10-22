# Configure the NSMBW runtime for Android arm64-v8a (CI version)
# Uses paths relative to the GitHub Actions workspace.
# Run after Prepare-PortableTools.ps1 and Prepare-Dependencies.ps1.
[CmdletBinding()]
param(
    [int]$TranslatedJobs = 6,
    [string]$BuildDirectory,
    [string]$LogPath
)

$ErrorActionPreference = 'Stop'

# In CI, the workspace root is the repo root
$workspace = $PSScriptRoot
for ($i = 0; $i -lt 3; $i++) { $workspace = Split-Path $workspace }
# $workspace is now the repo root (e.g., D:\a\...\NSMB-Wii-Multiplayer-Recompilation)

$portableTools = Join-Path $workspace 'Launcher\artifacts\portable-tools'
$dependencies  = Join-Path $workspace 'Launcher\artifacts\dependencies'
$runtimeDir    = Join-Path $workspace 'runtime'

# NDK path from android-actions/setup-android
$ndk = $env:ANDROID_NDK_HOME
if (-not $ndk) { throw "ANDROID_NDK_HOME not set. Run android-actions/setup-android first." }
if (-not (Test-Path (Join-Path $ndk 'build\cmake\android.toolchain.cmake'))) { throw "NDK missing: $ndk" }

if (-not (Test-Path (Join-Path $dependencies 'dawn_prebuilt_android\lib\libwebgpu_dawn.a'))) {
    throw 'Dependencies\dawn_prebuilt_android is missing (pinned dawn-android-aarch64 v20260603.191052)'
}

# Use only the portable toolchain (CMake, Ninja, clang from NDK)
$env:PATH = "$portableTools\CMake\bin;$portableTools\Ninja;$env:SystemRoot\System32;$env:SystemRoot"

function ConvertTo-CMakePath([string]$Path) { [IO.Path]::GetFullPath($Path).Replace('\', '/') }

# Default build/log directories if not provided
if (-not $BuildDirectory) { $BuildDirectory = Join-Path $workspace 'android-build' }
if (-not $LogPath) { $LogPath = Join-Path $workspace 'build-nsmbw\logs\configure-android.log' }

$configure = @(
    '-S', (ConvertTo-CMakePath $runtimeDir),
    '-B', (ConvertTo-CMakePath $BuildDirectory),
    '-G', 'Ninja',
    "-DCMAKE_MAKE_PROGRAM=$(ConvertTo-CMakePath (Join-Path $portableTools 'Ninja\ninja.exe'))",
    "-DCMAKE_TOOLCHAIN_FILE=$(ConvertTo-CMakePath (Join-Path $ndk 'build\cmake\android.toolchain.cmake'))",
    '-DANDROID_ABI=arm64-v8a',
    # memfd_create (guest RAM) is in bionic from API 30.
    '-DANDROID_PLATFORM=android-30',
    # One native library holds everything (SDL, Dawn, the game), so libc++ is linked in statically.
    '-DANDROID_STL=c++_static',
    '-DCMAKE_BUILD_TYPE=Release',
    '-DAURORA_DAWN_PROVIDER=package', '-DAURORA_SDL3_PROVIDER=vendor',
    '-DCMAKE_POLICY_DEFAULT_CMP0168=NEW', '-DFETCHCONTENT_FULLY_DISCONNECTED=ON',
    # Target ARMv8-A baseline (Cortex-A53/A73 compatible) for Kryo 265 (Snapdragon 680)
    # Avoids SIGILL from CRC32/AES/LSE/Atomics instructions not present on older ARMv8 cores
    '-DCMAKE_C_FLAGS=-march=armv8-a',
    '-DCMAKE_CXX_FLAGS=-march=armv8-a',
    "-DMKW_TRANSLATED_COMPILE_JOBS=$TranslatedJobs"
)

foreach ($directory in Get-ChildItem -LiteralPath $dependencies -Directory) {
    # Windows-only trees, and the Windows Dawn package (the Android one replaces it below).
    if ($directory.Name -in @('native_prebuilt', 'cppwinrt', 'dawn_prebuilt', 'dawn_prebuilt_android')) { continue }
    $configure += "-DFETCHCONTENT_SOURCE_DIR_$($directory.Name.ToUpperInvariant())=$(ConvertTo-CMakePath $directory.FullName)"
}
$configure += "-DFETCHCONTENT_SOURCE_DIR_DAWN_PREBUILT=$(ConvertTo-CMakePath (Join-Path $dependencies 'dawn_prebuilt_android'))"

# Ensure log directory exists
$logDir = Split-Path $LogPath
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

# Windows PowerShell 5.1 turns a native program's stderr lines into error records; CMake prints
# ordinary status there, so run it with 'Continue' and keep the log as plain text.
# Also output to stdout so CI logs show the error.
$ErrorActionPreference = 'Continue'
& (Join-Path $portableTools 'CMake\bin\cmake.exe') @configure 2>&1 |
    ForEach-Object { "$_" } | Tee-Object -FilePath $LogPath -Encoding utf8
exit $LASTEXITCODE