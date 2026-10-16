# Validação desta integração — 09/10/2026

Este documento descreve somente `integracao_hps_professor`, não certifica
outras versões nem substitui o teste físico no laboratório.

## Software e simulação

- C Windows: `gpuctl.exe` e `test_mailbox.exe`, GCC 6.3, C99, `-Wall -Wextra -Werror`.
- Testes C: limites, publicação, readback, timeout sem reenvio automático,
  erro parcial, sequência e gerador de cena.
- Teste do código real de comandos do CLI com transporte simulado: demo,
  sprite/flip, tile, triângulo, retângulo, scroll, paleta, animação,
  rejeição de argumentos e carregamento do HEX. Não substitui o mmap Linux.
- Três testes do assembler Python.
- Oito testbenches RTL aprovados: CPU, host, gráficos, endpoint, sistema,
  captura da demo original, mailbox e mailbox com RAM real.
- `tb_gpu_mailbox_ram`: porta dupla REAL do altsyncram, ambas as metades32,
  campos da mailbox e programa externo executado pela CPU FPGA.
- `tb_gpu_mailbox`: 2.084 comandos exportados pelo mesmo gerador C usado
  na aplicação; cena completa; pixels conhecidos de tile/retângulo/triângulo/
  sprite; segunda atualização externa; fila cheia/timeout; erro parcial;
  sequência repetida; reset sem repetir pedido antigo.
- Captura VGA: 307.200 pixels em `simulation/hps_demo.ppm` (640×480).

Os logs ficam em `simulation`. O teste longo usa modelo comportamental
síncrono equivalente da RAM para acelerar vários quadros; o teste curto usa
o IP altsyncram da biblioteca Altera. Nenhum deles simula ARM/Linux/boot
ou o trajeto físico HPS AXI.

## Compilação FPGA

A compilação final terminou em **09/10/2026 às 17:09**, Quartus
25.1std.0 Build 1129, **0 erros, 0 avisos críticos e 716 avisos**.
Foi reproduzida sem regenerar HPS/DDR, usando o HDL do professor.

- ALMs: 6.745/32.070 (21%).
- Registradores: 10.180.
- Memória: 2.777.984/4.065.280 bits (68%); 346/397 blocos RAM (87%).
- DSPs: 10/87 (11%).
- Os 64 grupos do resumo STA têm slack positivo; menor valor +0,077 ns.
- SOF: `output_files/pbl_hps_professor.sof`, 7.398.017 bytes.
- SHA256: `8DADA071B0B2CD09FB6DDCF151824DCA55065113270BC945EEB5ACBFC6B21A29`.

Consulte os relatórios finais `output_files/pbl_hps_professor.*.summary`
e `compile_console.log` para detalhes do SOF entregue. Os pinos DDR antes
implícitos foram fixados conforme o `.pin` do professor, incluindo RZQ.

Permanecem avisos herdados de IPs antigos, sinais/pinos periféricos sem uso,
terminações/correntes de I/O e modelos/restrições de temporização antigos.
Timing interno com slacks positivos não é certificação elétrica da placa:
os atrasos externos VGA ainda são provisórios e existem caminhos de I/O
não completamente restringidos no topo de referência.

A captura da simulação está também em `simulation/hps_demo.png`, convertida
sem alteração dos pixels do PPM. Não é uma foto da placa nem uma renderização
substituta feita em software.

## Ainda precisa do laboratório

- Identificar Linux, U-Boot/preloader, revisão da placa e configuração SD.
- Compilar/rodar o executável ARM. O EXE Windows não é um binário ARM.
- Validar sequência de programação e habilitação da ponte HPS→FPGA principal.
- Validar mapeamento Linux da RAM, ordenação e comunicação física.
- Executar `status`, `load`, `demo`, alterações externas e animação no VGA.
- Registrar saídas, fotos e versão do ambiente de boot.

Não houve instalação de WSL, escrita em SD, programação de placa, push ou
alteração de QAR. O hardware pode ser compilado aqui; a integração física
com Linux ainda não foi comprovada.
