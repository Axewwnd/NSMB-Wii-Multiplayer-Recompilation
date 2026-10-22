# Populates Launcher/artifacts/dependencies for Android CI - Windows-specific deps skipped
# Skips: cppwinrt-tool (Windows UWP only), dawn_prebuilt (Windows only - Android uses dawn_prebuilt_android)
[CmdletBinding()]
param(
    [string]$Destination
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$auroraCMake = Join-Path $repoRoot 'aurora-main\CMakeLists.txt'
$auroraExtern = Join-Path $repoRoot 'aurora-main\extern\CMakeLists.txt'
$auroraLibUsb = Join-Path $repoRoot 'aurora-main\cmake\AuroraLibUSB.cmake'
$auroraSdl = Join-Path $repoRoot 'aurora-main\cmake\AuroraSDL3Provider.cmake'
$auroraDawn = Join-Path $repoRoot 'aurora-main\cmake\AuroraDawnProvider.cmake'

# Android CI packages: same as Prepare-Dependencies.ps1 but WITHOUT cppwinrt-tool and dawn_prebuilt (Windows only)
# INCLUDES dawn_prebuilt_android (pinned v20260603.191052 for aarch64)
$packages = @(
    [pscustomobject]@{
        Name = 'SDL'; File = 'SDL3-3.4.4.tar.gz'
        Uris = @('https://github.com/libsdl-org/SDL/releases/download/release-3.4.4/SDL3-3.4.4.tar.gz')
        Pins = @(@{ File = $auroraCMake; Text = 'set(AURORA_SDL3_VERSION "3.4.4"' },
                 @{ File = $auroraSdl; Text = 'releases/download/release-${AURORA_SDL3_VERSION}/SDL3-${AURORA_SDL3_VERSION}.tar.gz' })
    },
    [pscustomobject]@{
        Name = 'abseil-cpp'; File = 'abseil-cpp-20240722.0.tar.gz'
        Uris = @('https://github.com/abseil/abseil-cpp/archive/refs/tags/20240722.0.tar.gz')
        Pins = @(@{ File = $auroraExtern; Text = 'https://github.com/abseil/abseil-cpp/archive/refs/tags/20240722.0.tar.gz' })
    },
    [pscustomobject]@{
        Name = 'dawn_prebuilt_android'; File = 'dawn-v20260603.191052-android-aarch64.tar.gz'
        Uris = @('https://github.com/theofficialgman/dawn-build/releases/download/v20260603.191052/dawn-android-aarch64.tar.gz')
        Pins = @(@{ File = $auroraCMake; Text = 'set(AURORA_DAWN_VERSION "v20260603.191052"' },
                 @{ File = $auroraDawn; Text = 'SHA256=0e63e8cbf53551f703f582d1306f4257c0380353f66b53369d96952ce6d9f934' })
    },
    [pscustomobject]@{
        Name = 'fmt'; File = 'fmt-11.1.4.tar.gz'
        Uris = @('https://github.com/fmtlib/fmt/archive/refs/tags/11.1.4.tar.gz')
        Pins = @(@{ File = $auroraExtern; Text = 'https://github.com/fmtlib/fmt/archive/refs/tags/11.1.4.tar.gz' })
    },
    [pscustomobject]@{
        Name = 'freetype'; File = 'freetype-2.14.3.tar.gz'
        Uris = @('https://files.twilitrealm.dev/freetype-2.14.3.tar.gz',
                 'https://download.savannah.gnu.org/releases/freetype/freetype-2.14.3.tar.gz',
                 'https://downloads.sourceforge.net/project/freetype/freetype2/2.14.3/freetype-2.14.3.tar.gz')
        Pins = @(@{ File = $auroraExtern; Text = 'https://files.twilitrealm.dev/freetype-2.14.3.tar.gz' })
    },
    [pscustomobject]@{
        Name = 'imgui'; File = 'imgui-1.91.9b-docking.tar.gz'
        Uris = @('https://github.com/ocornut/imgui/archive/refs/tags/v1.91.9b-docking.tar.gz')
        Pins = @(@{ File = $auroraExtern; Text = 'https://github.com/ocornut/imgui/archive/refs/tags/v1.91.9b-docking.tar.gz' })
    },
    [pscustomobject]@{
        Name = 'libusb'; File = 'libusb-1.0.30.tar.bz2'
        Uris = @('https://github.com/libusb/libusb/releases/download/v1.0.30/libusb-1.0.30.tar.bz2')
        Pins = @(@{ File = $auroraCMake; Text = 'set(AURORA_LIBUSB_VERSION "1.0.30"' },
                 @{ File = $auroraLibUsb; Text = 'releases/download/v${AURORA_LIBUSB_VERSION}/libusb-${AURORA_LIBUSB_VERSION}.tar.bz2' })
    },
    [pscustomobject]@{
        Name = 'png'; File = 'libpng-1.6.58.tar.gz'
        Uris = @('https://github.com/pnggroup/libpng/archive/refs/tags/v1.6.58.tar.gz')
        Pins = @(@{ File = $auroraExtern; Text = 'https://github.com/pnggroup/libpng/archive/refs/tags/v1.6.58.tar.gz' })
    },
    [pscustomobject]@{
        Name = 'sqlite3'; File = 'sqlite-amalgamation-3510300.zip'
        Uris = @('https://sqlite.org/2026/sqlite-amalgamation-3510300.zip')
        Pins = @(@{ File = $auroraExtern; Text = 'https://sqlite.org/2026/sqlite-amalgamation-3510300.zip' })
    },
    [pscustomobject]@{
        Name = 'tracy'; File = 'tracy-a64b9a20294d59421a2f57aeca3c6383d8c48169.tar.gz'
        Uris = @('https://github.com/wolfpld/tracy/archive/a64b9a20294d59421a2f57aeca3c6383d8c48169.tar.gz')
        Pins = @(@{ File = $auroraExtern; Text = 'https://github.com/wolfpld/tracy/archive/a64b9a20294d59421a2f57aeca3c6383d8c48169.tar.gz' })
    },
    [pscustomobject]@{
        Name = 'xxhash'; File = 'xxHash-0.8.4.tar.gz'
        Uris = @('https://github.com/Cyan4973/xxHash/archive/refs/tags/v0.8.4.tar.gz')
        Pins = @(@{ File = $auroraExtern; Text = 'https://github.com/Cyan4973/xxHash/archive/refs/tags/v0.8.4.tar.gz' })
    },
    [pscustomobject]@{
        Name = 'zlib'; File = 'zlib-1.3.2.tar.gz'
        Uris = @('https://github.com/madler/zlib/releases/download/v1.3.2/zlib-1.3.2.tar.gz')
        Pins = @(@{ File = $auroraExtern; Text = 'https://github.com/madler/zlib/releases/download/v1.3.2/zlib-1.3.2.tar.gz' })
    },
    [pscustomobject]@{
        Name = 'zstd'; File = 'zstd-1.5.7.tar.gz'
        Uris = @('https://github.com/facebook/zstd/releases/download/v1.5.7/zstd-1.5.7.tar.gz')
        Pins = @(@{ File = $auroraExtern; Text = 'https://github.com/facebook/zstd/releases/download/v1.5.7/zstd-1.5.7.tar.gz' })
    }
)

if (-not $Destination) { $Destination = Join-Path $PSScriptRoot 'artifacts\dependencies' }
$Destination = [IO.Path]::GetFullPath($Destination)
$downloads = Join-Path $PSScriptRoot 'artifacts\downloads'
$tar = Join-Path $env:SystemRoot 'System32\tar.exe'
if (-not (Test-Path -LiteralPath $tar -PathType Leaf)) { throw "Windows archive tool is missing: $tar" }
[IO.Directory]::CreateDirectory($Destination) | Out-Null
[IO.Directory]::CreateDirectory($downloads) | Out-Null

function Assert-Pinned($Package) {
    foreach ($pin in $Package.Pins) {
        if (-not (Test-Path -LiteralPath $pin.File -PathType Leaf)) { throw "Pin source is missing: $($pin.File)" }
        $content = [IO.File]::ReadAllText($pin.File)
        if (-not $content.Contains($pin.Text)) {
            throw "$($Package.Name) is pinned to '$($pin.Text)' here but $($pin.File) no longer declares it; update both."
        }
    }
}

function Get-Archive($Package) {
    $archive = Join-Path $downloads $Package.File
    if (Test-Path -LiteralPath $archive -PathType Leaf) { return $archive }
    $temporary = $archive + '.partial'
    $failures = @()
    foreach ($uri in $Package.Uris) {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        Write-Host "Downloading $($Package.Name) from $uri..."
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $uri -OutFile $temporary
        } catch {
            $failures += "$uri ($($_.Exception.Message))"
            continue
        }
        Move-Item -LiteralPath $temporary -Destination $archive -Force
        return $archive
    }
    Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    throw "$($Package.Name) could not be fetched: $($failures -join '; ')"
}

function Expand-Package([string]$Archive, [string]$Target) {
    $extract = Join-Path (Split-Path -Parent $Target) ('.extract-' + (Split-Path -Leaf $Target))
    if (Test-Path -LiteralPath $extract) { Remove-Item -LiteralPath $extract -Recurse -Force }
    [IO.Directory]::CreateDirectory($extract) | Out-Null
    $listing = & $tar -tvf $Archive
    if ($LASTEXITCODE -ne 0) { throw "Listing $Archive failed with exit code $LASTEXITCODE." }
    $excludes = @($listing | ForEach-Object { if ($_ -match '^l.*\s(\S+)\s->\s') { '--exclude=' + $Matches[1] } })
    & $tar -xf $Archive -C $extract @excludes
    if ($LASTEXITCODE -ne 0) { throw "Extracting $Archive failed with exit code $LASTEXITCODE." }
    $entries = @(Get-ChildItem -LiteralPath $extract -Force)
    $source = $extract
    if ($entries.Count -eq 1 -and $entries[0].PSIsContainer) { $source = $entries[0].FullName }
    if (Test-Path -LiteralPath $Target) { Remove-Item -LiteralPath $Target -Recurse -Force }
    Move-Item -LiteralPath $source -Destination $Target
    if (Test-Path -LiteralPath $extract) { Remove-Item -LiteralPath $extract -Recurse -Force }
}

foreach ($package in $packages) {
    Assert-Pinned $package
    $target = Join-Path $Destination $package.Name
    if (Test-Path -LiteralPath $target -PathType Container) { continue }
    Expand-Package (Get-Archive $package) $target
    Write-Host "Prepared $($package.Name)"
}

Write-Host "Pinned dependency sources ready (Android CI): $Destination"