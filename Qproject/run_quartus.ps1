param([string]$QuartusBin='D:\00study\01fpga\DownloadSoftware\Quarturs_II_13_0\quartus\bin64')
$ErrorActionPreference='Stop'
Push-Location $PSScriptRoot
try {
    New-Item -ItemType Directory -Force reports | Out-Null
    foreach ($taskRevision in @('accelerator','accelerator_cdc','board_selftest')) {
        & (Join-Path $QuartusBin 'quartus_sh.exe') --flow compile accelerator -c $taskRevision 2>&1 | Tee-Object -FilePath "reports/${taskRevision}_compile.log"
        if ($LASTEXITCODE -ne 0) {throw "Quartus compile failed for $taskRevision"}
        $taskCompileLog=Get-Content -Raw "reports/${taskRevision}_compile.log"
        if($taskCompileLog -match 'Timing requirements not met|Ignored filter|Read_sdc failed') {
            throw "Timing or SDC validation failed for $taskRevision; inspect reports"
        }
        & (Join-Path $QuartusBin 'quartus_sta.exe') -t report_sta.tcl $taskRevision 2>&1 | Tee-Object -FilePath "reports/${taskRevision}_sta.log"
        if ($LASTEXITCODE -ne 0) {throw "STA report failed for $taskRevision"}
    }
} finally {Pop-Location}
