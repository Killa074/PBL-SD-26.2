param([string]$TestFilter='tb_gpu_*',
 [string]$QuestaBin='C:\altera_lite\25.1std\questa_fse\win64',
 [string]$Gcc='C:\MinGW\bin\gcc.exe')
$ErrorActionPreference='Stop'
Push-Location $PSScriptRoot
try {
 & $Gcc -std=c99 -O2 -Wall -Wextra -Werror software/gpuctl.c software/mailbox.c software/scene.c -o software/gpuctl.exe
 if($LASTEXITCODE){throw 'Falha compilando ferramenta C'}
 & $Gcc -std=c99 -O2 -Wall -Wextra -Werror software/test_mailbox.c software/mailbox.c software/scene.c -o software/test_mailbox.exe
 if($LASTEXITCODE){throw 'Falha compilando testes C'}
 & ./software/test_mailbox.exe
 if($LASTEXITCODE){throw 'Falha testes C'}
 & $Gcc -std=c99 -O2 -Wall -Wextra -Werror software/test_cli.c software/mailbox.c software/scene.c -o software/test_cli.exe
 if($LASTEXITCODE){throw 'Falha compilando teste CLI'}
 & ./software/test_cli.exe programs/demo.hex
 if($LASTEXITCODE){throw 'Falha teste CLI'}
 & ./software/gpuctl.exe --export-demo tests/demo_commands.hex
 if($LASTEXITCODE){throw 'Falha exportando cena'}
 & python tests/test_assembler.py
 if($LASTEXITCODE){throw 'Falha assembler'}
 New-Item -ItemType Directory -Path simulation -Force | Out-Null
 if(-not(Test-Path simulation/work/_info)){& "$QuestaBin\vlib.exe" simulation/work;if($LASTEXITCODE){throw 'vlib'}}
 $rtl=@(Get-ChildItem rtl -Filter '*.v'|ForEach-Object {$_.FullName})
 $benches=@(Get-ChildItem tests -Filter '*.sv'|ForEach-Object {$_.FullName})
 & "$QuestaBin\vlog.exe" -sv -work simulation/work @rtl professor/soc_system/synthesis/submodules/soc_system_onchip_memory2_0.v @benches
 if($LASTEXITCODE){throw 'vlog'}
 $selected=@(Get-ChildItem tests -Filter '*.sv'|Where-Object {$_.BaseName -like $TestFilter})
 if(!$selected.Count){throw 'Nenhum teste selecionado'}
 foreach($tb in $selected){
  $name=$tb.BaseName
  $log=& "$QuestaBin\vsim.exe" -c -L altera_mf_ver -lib simulation/work $name -l "simulation/$name.log" -do 'run -all; quit -f' 2>&1
  $log|Out-Host
  if($LASTEXITCODE -or ($log -join "`n") -match '\*\* (Fatal|Error)' -or ($log -join "`n") -notmatch "PASS $name"){throw "Falhou $name"}
 }
} finally {Pop-Location}
