# Build aplinks32_c17.exe (Windows) from APLINKS_C17.C -- the C17 readability
# variant. APLINKS.C / aplinks32.exe (C99) remain the untouched reference.

$ErrorActionPreference = "Stop"

$cc = (Get-Command gcc -ErrorAction SilentlyContinue) ?? (Get-Command clang -ErrorAction SilentlyContinue)
if (-not $cc) { Write-Error "No gcc or clang found on PATH."; exit 1 }

& $cc.Source -x c -std=c17 -O2 -Wall -Wextra -o aplinks32_c17.exe APLINKS_C17.C
if ($LASTEXITCODE -ne 0) { Write-Error "Build failed."; exit $LASTEXITCODE }

Write-Host "Built aplinks32_c17.exe with $($cc.Name) (C17)."
