# Laboratório — integração do professor

O roteiro atualizado e os comandos estão no [README desta versão](../README.md).

Projeto: `pbl_hps_professor.qpf`; saída: `output_files/pbl_hps_professor.sof`.
Transporte: mailbox na RAM em **0xC0000000**, pela ponte HPS→FPGA principal.
Ferramenta: `software/gpuctl`, compilada para Linux ARM na placa.

Não usar as instruções de `pbl_fase2_hps`/`guardiao --fpga 0xFF200000`
da versão anterior. A janela direta GPU3 não existe nesta revisão.

## Descobrir o Linux do cartão, sem modificar nada

1. Com a placa desligada, mantenha o cartão inserido e conecte a porta USB-UART
   ao computador. Não confundir com a USB-Blaster.
2. No Gerenciador de Dispositivos do Windows, procure a porta em
   **Portas (COM e LPT)**. Se não aparecer, conferir cabo/driver da revisão da
   placa antes de alterar o SD.
3. Abra PuTTY em modo Serial: COM encontrada, **115200, 8N1, flow control None**.
4. Ligue a placa e capture o texto. A ausência de texto, isoladamente, não prova
   ausência de Linux: pode ser porta, cabo, driver, boot ou configuração serial.
5. Se aparecer login, use as credenciais informadas pelo laboratório. Caso não
   saiba, mande a tela; não é necessário reinstalar Linux.

O baud rate é documentado no [guia Terasic DE1-SoC](https://www.terasic.com.tw/attachment/archive/836/DE1SOC_OpenCL_v02.pdf).
Não é necessário instalar OpenCL: a referência aqui é somente a conexão UART.

Se houver um shell Linux, executar:

```sh
uname -a
cat /etc/os-release
cat /proc/device-tree/model
ls /sys/class/fpga_bridge
command -v gcc
command -v make
```

Ou, se já tiver copiado o projeto:

```sh
sh software/diagnostico_hps.sh
```

O script apenas lê informações; não acessa `/dev/mem`, não habilita pontes,
não programa FPGA, não altera cartão/configuração. Envie a saída, inclusive
arquivos inexistentes. O resultado serve para decidir o fluxo de boot/ponte;
não execute a ferramenta gráfica até esse fluxo estar confirmado.
