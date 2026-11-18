# Windows MSI installer (same steps as the `windows` job in .github/workflows/release.yml):
#   dist/neurofeed-<version>-windows-x64.msi   per-user or per-machine (ALLUSERS=2), WiX v5
# Usage: pwsh scripts/package-windows-msi.ps1 [-Version 1.2.3] [-Exe path] [-OutDir dir]
#   -Exe     the (signed) neurofeed.exe to install; default: build via package-windows.ps1 -BuildOnly
#   -OutDir  default dist/ (CI uses target/windows-msi-unsigned/ so the MSI can be signed first)
# Needs the WiX CLI: dotnet tool install --global wix --version 5.0.2
#                    wix extension add --global WixToolset.UI.wixext/5.0.2
param([string]$Version = "", [string]$Exe = "", [string]$OutDir = "")
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
if (-not $Version) { $Version = $env:NEUROFEED_VERSION }
if (-not $Version) {
  $Version = git -C $Root describe --tags --match '[0-9]*' --match 'v[0-9]*' --exclude '*[!0-9.v]*' 2>$null
  if ($LASTEXITCODE -ne 0) { $Version = "" }
}
if (-not $Version) {
  $Version = (Select-String -Path "$Root/Cargo.toml" -Pattern '^version = "(.*)"' | Select-Object -First 1).Matches[0].Groups[1].Value
}
$Version = $Version.TrimStart("v")
# MSI ProductVersion must be numeric major.minor.build: 0.64.0-3-gabc1234 -> 0.64.0
if ($Version -notmatch '^(\d+)\.(\d+)\.(\d+)') { throw "version '$Version' is not X.Y.Z" }
$MsiVersion = "$($Matches[1]).$($Matches[2]).$($Matches[3])"
$TargetDir = if ($env:CARGO_TARGET_DIR) { $env:CARGO_TARGET_DIR } else { "$Root/target" }
if (-not $Exe) {
  pwsh "$PSScriptRoot/package-windows.ps1" -Version $Version -BuildOnly
  if ($LASTEXITCODE -ne 0) { throw "build failed" }
  $Exe = "$TargetDir/windows-unsigned/neurofeed.exe"
}
if (-not (Test-Path $Exe)) { throw "exe not found: $Exe" }
if (-not $OutDir) { $OutDir = "$Root/dist" }
$Work = "$TargetDir/windows-msi"
New-Item -ItemType Directory -Force $Work, $OutDir | Out-Null
# WixUI shows the licence as RTF; wrap the plain-text Apache-2.0 text.
$text = (Get-Content -Raw "$Root/LICENSE.txt") -replace '\\', '\\' -replace '\{', '\{' -replace '\}', '\}'
$text = ($text -replace "`r", '') -replace "`n", "\par`n"
$Rtf = "$Work/license.rtf"
[IO.File]::WriteAllText($Rtf, "{\rtf1\ansi\deff0{\fonttbl{\f0\fmodern Consolas;}}\f0\fs18 $text}", [Text.Encoding]::ASCII)
$Msi = "$OutDir/neurofeed-$Version-windows-x64.msi"
wix build -arch x64 -ext WixToolset.UI.wixext `
  -d ProductVersion=$MsiVersion -d "ExePath=$Exe" -d "LicenseRtf=$Rtf" `
  -d "IconPath=$Root/apps/neurofeed-egui/assets/neurofeed.ico" `
  -d "LicenseTxt=$Root/LICENSE.txt" -d "ThirdPartyNotices=$Root/THIRD_PARTY_NOTICES.md" `
  -o $Msi "$Root/packaging/windows/neurofeed.wxs"
if ($LASTEXITCODE -ne 0) { throw "wix build failed" }
Get-Item $Msi | Format-List Name, Length
