# Build aplinks32_107.exe (Windows) from APLINKS107.C -- the 1.07 server (256K mode).
# The reference server APLINKS.C / aplinks32.exe (1.06) is NOT touched by this script.
# Requires gcc (MinGW-w64) or clang on PATH.

$ErrorActionPreference = "Stop"

$cc = (Get-Command gcc -ErrorAction SilentlyContinue) ?? (Get-Command clang -ErrorAction SilentlyContinue)
if (-not $cc) { Write-Error "No gcc or clang found on PATH."; exit 1 }

& $cc.Source -x c -std=c99 -O2 -Wall -Wextra -o aplinks32_107.exe APLINKS107.C
if ($LASTEXITCODE -ne 0) { Write-Error "Build failed."; exit $LASTEXITCODE }

Write-Host "Built aplinks32_107.exe with $($cc.Name)."
