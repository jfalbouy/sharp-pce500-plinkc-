# Build aplinks32.exe (Windows) from APLINKS.C.
# Requires gcc (MinGW-w64) or clang on PATH. Do NOT name the output aplinks.exe:
# on Windows the FS is case-insensitive and it would clobber the DOS APLINKS.EXE.

$ErrorActionPreference = "Stop"

$cc = (Get-Command gcc -ErrorAction SilentlyContinue) ?? (Get-Command clang -ErrorAction SilentlyContinue)
if (-not $cc) { Write-Error "No gcc or clang found on PATH."; exit 1 }

& $cc.Source -x c -std=c99 -O2 -Wall -Wextra -o aplinks32.exe APLINKS.C
if ($LASTEXITCODE -ne 0) { Write-Error "Build failed."; exit $LASTEXITCODE }

Write-Host "Built aplinks32.exe with $($cc.Name)."
