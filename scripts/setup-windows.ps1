# Windows counterpart of scripts/setup.sh: toolchain, packages, type definitions, Blender, first build.
# Run from the repository root in PowerShell:
#   powershell -ExecutionPolicy Bypass -File scripts\setup-windows.ps1
# Safe to run again: every step checks what is already there.
$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)

function Step($message) { Write-Host "`n> $message" -ForegroundColor Cyan }

# 1. Rokit (installs the pinned tools listed in rokit.toml).
$rokitBin = Join-Path $env:USERPROFILE ".rokit\bin"
if (-not (Get-Command rokit -ErrorAction SilentlyContinue) -and -not (Test-Path (Join-Path $rokitBin "rokit.exe"))) {
	Step "rokit"
	$release = Invoke-RestMethod "https://api.github.com/repos/rojo-rbx/rokit/releases/latest"
	$asset = $release.assets | Where-Object { $_.name -like "*windows-x86_64.zip" } | Select-Object -First 1
	if (-not $asset) { throw "No Windows build found in the latest rokit release." }
	$zip = Join-Path $env:TEMP $asset.name
	$dir = Join-Path $env:TEMP "rokit-install"
	Invoke-WebRequest $asset.browser_download_url -OutFile $zip
	Expand-Archive $zip -DestinationPath $dir -Force
	& (Join-Path $dir "rokit.exe") self-install
}
$env:Path = "$rokitBin;$env:Path"

Step "rokit install"
rokit install --no-trust-check

Step "wally install"
wally install

Step "Roblox type definitions for luau-lsp"
Invoke-WebRequest "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau" -OutFile "globalTypes.d.luau"

# 2. Blender. The tools default to the macOS path; on Windows they read BLENDER.
Step "Blender"
$blender = Get-ChildItem "C:\Program Files\Blender Foundation\*\blender.exe" -ErrorAction SilentlyContinue |
	Sort-Object FullName -Descending | Select-Object -First 1
if ($blender) {
	[Environment]::SetEnvironmentVariable("BLENDER", $blender.FullName, "User")
	$env:BLENDER = $blender.FullName
	Write-Host "BLENDER = $($blender.FullName) (saved for new terminals)"
} else {
	Write-Warning "Blender not found under C:\Program Files\Blender Foundation. Set BLENDER to blender.exe by hand."
}

# 3. Rojo plugin in Studio, and a first build.
Step "rojo plugin install"
rojo plugin install

Step "rojo build"
New-Item -ItemType Directory -Force build | Out-Null
rojo build default.project.json -o build/Vellum.rbxl

Write-Host "`nSetup complete." -ForegroundColor Green
Write-Host "Play now: open build\Vellum.rbxl in Studio."
Write-Host "Live sync: rojo serve default.project.json, then Plugins > Rojo > Connect in Studio."
