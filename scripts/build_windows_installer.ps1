<#
Build a real Windows .exe installer for Suibo (not a portable EXE).
Run on Windows with Flutter 3.47.6, Visual Studio C++ and Inno Setup 6.
Outputs stay in a PRIVATE folder outside the public Git repository.

Example:
  powershell -ExecutionPolicy Bypass -File scripts/build_windows_installer.ps1 -OutputDirectory C:\Private\SuiboReleases
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,
    [switch]$SkipFlutterBuild
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$privateOutput = [System.IO.Path]::GetFullPath($OutputDirectory)
if ($privateOutput -eq $root -or $privateOutput.StartsWith($root + [System.IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Installer output must be OUTSIDE the public Git repository."
}

$pubspec = [System.IO.File]::ReadAllText((Join-Path $root "pubspec.yaml"))
$versionMatch = [regex]::Match($pubspec, '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$')
if (-not $versionMatch.Success) { throw "pubspec.yaml version is missing or invalid." }
$version = $versionMatch.Groups[1].Value
$versionCode = $versionMatch.Groups[2].Value

if (-not $SkipFlutterBuild) {
    if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        throw "Flutter SDK is missing on this Windows build machine."
    }
    & flutter config --enable-windows-desktop
    if ($LASTEXITCODE -ne 0) { throw "flutter config failed" }
    & flutter pub get
    if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }
    $buildArgs = @("build", "windows", "--release")
    if (-not [string]::IsNullOrWhiteSpace($env:DANDANAPI_APPID) -and
        -not [string]::IsNullOrWhiteSpace($env:DANDANAPI_KEY)) {
        $buildArgs += @("--dart-define=DANDANAPI_APPID=$env:DANDANAPI_APPID",
                        "--dart-define=DANDANAPI_KEY=$env:DANDANAPI_KEY")
    }
    & flutter @buildArgs
    if ($LASTEXITCODE -ne 0) { throw "Flutter Windows release build failed" }
}

$releaseDir = Join-Path $root "build\windows\x64\runner\Release"
$required = @(
    (Join-Path $releaseDir "suibo.exe"),
    (Join-Path $releaseDir "flutter_windows.dll"),
    (Join-Path $releaseDir "data\icudtl.dat"),
    (Join-Path $releaseDir "data\flutter_assets")
)
foreach ($file in $required) {
    if (-not (Test-Path -LiteralPath $file)) {
        throw "The complete Flutter Windows release bundle is missing: $file"
    }
}

$isccCommand = Get-Command "ISCC.exe" -ErrorAction SilentlyContinue
$iscc = if ($isccCommand) { $isccCommand.Source } else { $null }
if (-not $iscc) {
    $candidates = @(
        (Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) "Inno Setup 6\ISCC.exe"),
        (Join-Path ([Environment]::GetFolderPath('ProgramFiles')) "Inno Setup 6\ISCC.exe")
    )
    $iscc = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not $iscc) { throw "Inno Setup 6 ISCC.exe is missing; install it privately." }

New-Item -ItemType Directory -Force -Path $privateOutput | Out-Null
$installer = Join-Path $privateOutput "Suibo-Setup-$version-Windows-x64.exe"
$report = Join-Path $privateOutput "Suibo-Windows-install-report-$versionCode.txt"
if ((Test-Path -LiteralPath $installer) -or (Test-Path -LiteralPath $report)) {
    throw "This release already exists in the private output directory; refusing to overwrite."
}

& $iscc "/DMyAppVersion=$version" "/DFlutterReleaseDir=$releaseDir" "/DInstallerOutputDir=$privateOutput" (Join-Path $root "installer\windows\Suibo.iss")
if ($LASTEXITCODE -ne 0) { throw "Inno Setup compilation failed" }
if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
    throw "Installer output not found after Inno Setup compilation"
}

$hash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash
$bytes = (Get-Item -LiteralPath $installer).Length
$identity = @(
    "Suibo Windows installer verification",
    "Version: $version",
    "Build code: $versionCode",
    "Filename: $(Split-Path -Leaf $installer)",
    "Size bytes: $bytes",
    "SHA256: $hash",
    "Installer: Inno Setup 6; includes complete Flutter runtime",
    "Upgrade AppId: {FE6015EC-9973-449D-9B64-662CF98C580B}",
    "Existing user data: preserved in application-support directory",
    "Portable predecessor: installed separately; data migration requires verification",
    "Authenticode digital signature: NOT CONFIGURED (Android JKS cannot sign Windows EXE)",
    "Smoke installation and overlay upgrade: NOT YET VERIFIED",
    "Report written: $([DateTime]::UtcNow.ToString('u')) UTC"
)
[System.IO.File]::WriteAllLines($report, $identity, [System.Text.Encoding]::UTF8)
if (-not (Test-Path -LiteralPath $report)) { throw "Installer report was not created." }
Write-Output "PRIVATE INSTALLER: $installer"
Write-Output "REPORT: $report, bytes: $((Get-Item -LiteralPath $report).Length), modified: $((Get-Item -LiteralPath $report).LastWriteTime)"
Write-Output "Installer bytes: $bytes; SHA256: $hash"
