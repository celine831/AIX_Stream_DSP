param(
    [string]$PythonExe=(Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'),
    [string]$ModelSimBin='D:\00study\01fpga\DownloadSoftware\modelsim_se\win64',
    [string]$QuartusBin='D:\00study\01fpga\DownloadSoftware\Quarturs_II_13_0\quartus\bin64'
)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path $PSScriptRoot -Parent
Push-Location $taskRoot
try {
    if(!(Test-Path -LiteralPath $PythonExe)){throw 'Pass -PythonExe with a working Python 3 executable'}
    & $PythonExe sim/run_regression.py --modelsim-bin $ModelSimBin
    if($LASTEXITCODE -ne 0){throw 'ModelSim regression failed'}
    & ./Qproject/run_quartus.ps1 -QuartusBin $QuartusBin
    & $PythonExe scripts/collect_results.py
    if($LASTEXITCODE -ne 0){throw 'Result validation failed'}
} finally {Pop-Location}
