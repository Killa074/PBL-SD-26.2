param([switch]$Compile,[switch]$Tests,[switch]$Autonomous,
 [string]$QuartusRoot='C:\altera_lite\25.1std\quartus')
$ErrorActionPreference='Stop'
if($PSScriptRoot -match '[^\x00-\x7F]'){throw 'Copie esta pasta completa para um caminho ASCII antes de compilar.'}
Push-Location $PSScriptRoot
try {
 & python tools/build_assets.py
 if($LASTEXITCODE){throw 'Falha assets'}
 & python tools/assemble.py programs/demo.asm programs/demo.hex --listing programs/demo.lst
 if($LASTEXITCODE){throw 'Falha assembler'}
 if($Tests){& ./run_tests.ps1}
 if($Compile){
  $project=if($Autonomous){'pbl_fase2'}else{'pbl_hps_professor'}
  & "$QuartusRoot\bin64\quartus_sh.exe" --flow compile $project
  if($LASTEXITCODE){throw "Falha compilando $project; veja output_files"}
 }
} finally {Pop-Location}
