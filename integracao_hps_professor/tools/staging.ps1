# Questa/Quartus have components that reject accented Windows paths.
# Compile a disposable ASCII copy, then bring the actual products back.
function New-GpuBuildStage([string]$SourceDir) {
    $stageRoot = if ($env:GPU_BUILD_ROOT) { $env:GPU_BUILD_ROOT } else {
        $asciiParent = Split-Path -Parent $SourceDir
        while ($asciiParent -match '[^\x00-\x7F]') {
            $asciiParent = Split-Path -Parent $asciiParent
        }
        Join-Path $asciiParent '.build_ascii'
    }
    $stageDir = Join-Path $stageRoot ('pbl_gpu_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stageDir | Out-Null
    foreach ($name in @('rtl','tests','tools','assets','programs','docs','hps','hps_soc','hps_isw_handoff')) {
        $source = Join-Path $SourceDir $name
        if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination $stageDir -Recurse }
    }
    Get-ChildItem -LiteralPath $SourceDir -File | Where-Object {
        $_.Extension -in @('.qpf','.qsf','.sdc','.ps1','.md','.qsys')
    } | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $stageDir }
    return $stageDir
}
function Complete-GpuBuildStage([string]$StageDir, [string]$DestinationDir) {
    foreach ($name in @('output_files','simulation','hps_soc','hps_isw_handoff')) {
        $source = Join-Path $StageDir $name
        if (Test-Path -LiteralPath $source) {
            $dest = Join-Path $DestinationDir $name
            New-Item -ItemType Directory -Path $dest -Force | Out-Null
            Get-ChildItem -LiteralPath $source -Force | ForEach-Object {
                Copy-Item -LiteralPath $_.FullName -Destination $dest -Recurse -Force
            }
        }
    }
    foreach ($name in @('assets','programs')) {
        $source = Join-Path $StageDir $name
        if (Test-Path -LiteralPath $source) {
            Get-ChildItem -LiteralPath $source -File | Where-Object {
                $_.Extension -in @('.hex','.lst') -or $_.Name -eq 'gpu_assets.h'
            } | ForEach-Object {
                Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $DestinationDir $name) -Force
            }
        }
    }
    foreach ($name in @('hps_soc.qsys','hps_soc.sopcinfo')) {
        $source = Join-Path $StageDir $name
        if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination $DestinationDir -Force }
    }
    Write-Host "Copia ASCII de compilacao e diagnosticos: $StageDir"
}
