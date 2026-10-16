# Arquitetura da integração HPS do professor

O HPS usa a ponte principal para escrever/ler a RAM64KiB do professor.
A segunda porta dessa RAM liga-se ao novo `gpu_mailbox`. Ele é o único
produtor da interface interna GPU3 e oferece dois modos de trabalho:

- Programa externo: copia palavras32 para IMEM; CPU com PC/IR/ULA executa
  nossa ISA e produz `OUT`.
- Comandos externos: converte pares porta32/dado32 da RAM para a fila de
  porta8/dado32 do `gpu_host`, respeitando a disponibilidade da fila.

Em ambos os casos, `gpu_graphics` recebe o mesmo contrato valid/ready.
PRESENT renderiza no buffer traseiro e publica no intervalo vertical;
FRAME_COUNT informa quando ocorreu a troca. VGA funciona independentemente
da velocidade das operações HPS.

Clock comum FPGA: 50 MHz; VGA usa habilitação de pixels a cada dois ciclos.
O reset GPU só é liberado quando a HPS e o controlador de reset da RAM estão
prontos, passando pelo sincronizador de `gpu_buttons`. KEY0 também reinicia
esse núcleo; KEY1 fica desabilitado para não disputar o controle com o ARM.

O `.qsys` preservado documenta a base do professor, não a segunda porta
acrescentada no HDL. Consulte [protocolo/adaptações](PROTOCOLO_HPS.md),
[README](../README.md) e [validação](VALIDACAO.md).
