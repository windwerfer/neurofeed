# Windows x64 release artifact (same steps as the `windows` job in .github/workflows/release.yml):
#   dist/neurofeed-<version>-windows-x64.zip   portable: neurofeed.exe + licence files
# Usage: pwsh scripts/package-windows.ps1 [-Version 1.2.3] [-SkipBuild]
param([string]$Version = "", [switch]$SkipBuild)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
# Version: -Version > $env:NEUROFEED_VERSION > git tag > Cargo.toml (same rules as scripts/version.sh).
if (-not $Version) { $Version = $env:NEUROFEED_VERSION }
if (-not $Version) {
  $Version = git -C $Root describe --tags --match '[0-9]*' --match 'v[0-9]*' --exclude '*[!0-9.v]*' 2>$null
  if ($LASTEXITCODE -ne 0) { $Version = "" }
}
if (-not $Version) {
  $Version = (Select-String -Path "$Root/Cargo.toml" -Pattern '^version = "(.*)"' | Select-Object -First 1).Matches[0].Groups[1].Value
}
$Version = $Version.TrimStart("v")
$env:NEUROFEED_VERSION = $Version  # baked into the binary (nf_core::APP_VERSION)
$TargetDir = if ($env:CARGO_TARGET_DIR) { $env:CARGO_TARGET_DIR } else { "$Root/target" }
if (-not $SkipBuild) {
  Push-Location $Root
  cargo build --release --locked -p neurofeed-egui --target x86_64-pc-windows-msvc
  if ($LASTEXITCODE -ne 0) { throw "cargo build failed" }
  Pop-Location
}
$Name = "neurofeed-$Version-windows-x64"
$Work = "$TargetDir/windows-package/$Name"
Remove-Item -Recurse -Force "$TargetDir/windows-package" -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $Work, "$Root/dist" | Out-Null
Copy-Item "$TargetDir/x86_64-pc-windows-msvc/release/neurofeed-egui.exe" "$Work/neurofeed.exe"
Copy-Item "$Root/LICENSE.txt", "$Root/THIRD_PARTY_NOTICES.md", "$Root/README.md" $Work
$Zip = "$Root/dist/$Name.zip"
Remove-Item -Force $Zip -ErrorAction SilentlyContinue
Compress-Archive -Path $Work -DestinationPath $Zip
Get-Item $Zip | Format-List Name, Length
