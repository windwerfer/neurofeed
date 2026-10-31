# Windows x64 release artifact (same steps as the `windows` job in .github/workflows/release.yml):
#   dist/neurofeed-<version>-windows-x64.zip   portable: neurofeed.exe + licence files
# Usage: pwsh scripts/package-windows.ps1 [-Version 1.2.3] [-SkipBuild]
param([string]$Version = "", [switch]$SkipBuild)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
if (-not $Version) {
  $Version = (Select-String -Path "$Root/Cargo.toml" -Pattern '^version = "(.*)"' | Select-Object -First 1).Matches[0].Groups[1].Value
}
$Version = $Version.TrimStart("v")
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
