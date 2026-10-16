# Fontes e licenças

## Base HPS desta integração

A pasta `professor` contém a base Terasic/Altera entregue pelo professor.
Preservados os avisos de autoria/licença dos arquivos. As adaptações locais
estão relacionadas em PROTOCOLO_HPS.md. Esses IPs não são cobertos pela licença
MIT abaixo; aplicam-se seus próprios termos Terasic/Altera, preservados no HDL.

## Referência da versão anterior

O texto abaixo documenta a origem da alternativa HPS anterior, não o sistema
ativo desta revisão. `pbl_hps_professor` usa a base do professor; não depende
dos Tcl `hps/board_parameters.tcl` mencionados a seguir.

Os parâmetros DDR/periféricos em hps/board_parameters.tcl, atribuições elétricas em hps/pins_hps.qsf e correspondência dos pinos HPS em rtl/top_hps.v foram adaptados do [FPGAcademy Design_Examples](https://github.com/fpgacademy/Design_Examples).

Arquivos de origem consultados:

- Computer_Systems/common/scripts/common.tcl
- Computer_Systems/DE1-SoC/scripts/gen_arm_niosii_computer_system.tcl
- Computer_Systems/DE1-SoC/src/DE1_SoC_ARM_NiosII_Computer/DE1_SoC_ARM_NiosII_Computer.qsf
- Computer_Systems/DE1-SoC/src/DE1_SoC_ARM_NiosII_Computer/DE1_SoC_ARM_NiosII_Computer.v

O sistema foi reduzido à HPS, ponte lightweight e GPU; não copia o computador Nios completo. A referência não é evidência de que esta nova integração já foi testada em placa.

## Licença do material adaptado

MIT License

Copyright (c) 2024 FPGAcademy

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Outros materiais

IP de HPS, DDR, interconexão e ferramentas Altera/Siemens continuam sujeitos às licenças de seus fornecedores. Não se altera essa licença com este projeto.

Assets de teste (tiles, sprites, paleta e fonte simples) são gerados pelo código do projeto. A versão atual e seus assets não foram alterados. A pinagem VGA/CLOCK/KEY foi preservada a partir do projeto que o usuário já testou.

Especificações funcionais usadas: PBL01 e PBL02 fornecidos pelo usuário. Enunciado PBL03 não disponível.
