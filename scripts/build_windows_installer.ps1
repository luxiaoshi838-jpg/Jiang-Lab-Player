# Requires Windows, Flutter 3.47.6, Visual Studio C++ tools and Inno Setup 6.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
  $line = Select-String -Path "pubspec.yaml" -Pattern '^version:\s*([0-9]+(?:\.[0-9]+)+)\+' | Select-Object -First 1
  if (-not $line) { throw "Cannot read application version from pubspec.yaml" }
  $version = $line.Matches[0].Groups[1].Value
  flutter pub get
  if ($LASTEXITCODE -ne 0) { throw "Flutter dependency resolution failed" }
  flutter build windows --release
  if ($LASTEXITCODE -ne 0) { throw "Windows release build failed" }
  $iscc = Get-Command ISCC.exe -ErrorAction SilentlyContinue
  $compiler = if ($iscc) { $iscc.Source } else { "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" }
  if (-not (Test-Path $compiler)) { throw "Install Inno Setup 6; ISCC.exe was not found" }
  & $compiler "/DMyAppVersion=$version" "scripts\windows_installer.iss"
  if ($LASTEXITCODE -ne 0) { throw "Windows installer packaging failed" }
  $installer = "build\windows\installer\Suibo-Windows-Setup-$version.exe"
  if (-not (Test-Path $installer)) { throw "Windows installer is missing" }
  Get-Item $installer | Select-Object FullName, Length, LastWriteTime
  Get-FileHash $installer -Algorithm SHA256
} finally {
  Pop-Location
}
