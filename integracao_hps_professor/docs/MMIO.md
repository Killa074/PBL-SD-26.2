# Interface MMIO GPU3

**Nesta versão esta interface é INTERNA.** O HPS usa a mailbox da RAM
em 0xC0000000 (READ_REGISTER/WRITE_REGISTER); não existe aqui a janela direta
GPU3 em 0xFF200000. Os offsets abaixo são argumentos dessas operações.
Veja [PROTOCOLO_HPS.md](PROTOCOLO_HPS.md) e [README](../README.md).

Todos os acessos sao de 32 bits e alinhados. A coluna endereco usa **bytes**,
enquanto `gpu_host.avs_address` recebe palavras: endereco em bytes dividido por4.
A interface Avalon-MM tem leitura combinacional (`readLatency=0`) e aceita cada
escrita com `waitrequest=0`. Nao suporta byteenable: o adaptador deve usar acessos
completos de 32 bits. O master e o host devem compartilhar o mesmo clock.

| Byte | Nome | Acesso/efeito |
|---|---|---|
| 00 | ID | RO: 47505533 hexadecimal, ASCII GPU3 |
| 04 | CONTROL | RW: RUN0, RESTART1 pulso, PASSIVE2, CLEAR_ERRORS3 pulso |
| 08 | STATUS | RO: bits abaixo |
| 0C | IMEM_ADDR | RW: indice da instrucao, 0..1023 |
| 10 | IMEM_DATA | WO: palavra32; incrementa IMEM_ADDR se aceita |
| 14 | PC | RO: endereco atual de instrucao |
| 18 | IR | RO: instrucao capturada |
| 1C | OUT_DATA | RO: ultimo dado **aceito** pelo motor grafico |
| 20 | OUT_PORT | RO: ultima porta aceita |
| 24 | OUT_COUNT | RO: numero de comandos aceitos, ativo e passivo |
| 28 | FLAGS | RO: flags CPU V,C,N,Z nos bits3:0 |
| 30 | CMD_PORT | RW: porta8 para a proxima insercao; bits31:8 devem ser0 |
| 34 | CMD_DATA | WO: enfileira atomicamente {CMD_PORT,dados32} |
| 38 | FIFO_FREE | RO: vagas0..64 |
| 3C | FRAME_COUNT | RO: numero de quadros apresentados pelo motor grafico |
| 40 | ERROR | RO/W1C: erros persistentes; escrever1 limpa o bit |

STATUS: bit0 CPU_BUSY, 1 CPU_DONE, 2 ANY_ERROR, 3 GFX_BUSY, 4 FIFO_EMPTY,
5 FIFO_FULL, 6 PASSIVE, 7 GFX_DONE, 8 RUN, 9 CPU_ERROR. GFX_DONE segue o sinal do
motor grafico; para nao perder pulsos, software deve aguardar FRAME_COUNT mudar.

ERROR: bit0 acesso MMIO invalido/escrita em RO/porta fora de8bits;
bit1 escrita de programa rejeitada; bit2 FIFO cheia; bit3 troca de modo ou
RESTART rejeitado; bit4 erro CPU; bit5 erro grafico; bit6 CMD_DATA em modo ativo.
Erros CPU/grafico permanecem visiveis enquanto sua origem estiver ativa:
reiniciar CPU e/ou enviar comando grafico F1 antes de limpar ERROR.

## Uso ativo

1. Escrever CONTROL=0 e aguardar CPU_BUSY=0.
2. Escrever IMEM_ADDR=0 e todas as palavras em IMEM_DATA.
3. Escrever CONTROL=3 (RUN|RESTART); a CPU parte do PC0.
4. Aguardar CPU_DONE ou ERROR. Aguardar tambem FRAME_COUNT mudar para PRESENT.

O reset nao apaga a RAM. Escrever programa requer RUN=0 e nenhuma saida da CPU
pendente. Endereco1024 ou maior e rejeitado sem circulacao para zero. IMEM_DATA
e CMD_DATA retornam zero quando lidos. Leitura de endereco reservado retorna
zero e marca ERROR0. Escritas nao aceitas nao bloqueiam o barramento; software
deve verificar ERROR. Ao carregar ROM externamente, nao executar acessos
concorrentes de multiplos processos.

## Uso passivo (HPS/ARM)

1. Aguardar CPU parada, GPU ociosa e FIFO vazia; escrever CONTROL=5 (RUN|PASSIVE).
2. Aguardar FIFO_FREE>0.
3. Escrever CMD_PORT e depois CMD_DATA; a segunda escrita publica o par inteiro.
4. Repetir para os comandos da cena, finalizando com porta F0 (PRESENT).
5. Aguardar FRAME_COUNT avancar, verificando ERROR e um timeout de software.

CMD_DATA e aceito mesmo com RUN=0 se PASSIVE=1; isso permite preparar a fila
antes de consumir. Ela comporta **64 comandos completos** (64 palavras de dados
mais suas portas). RUN=0 pausa novas ofertas. Um comando ja oferecido permanece
valido ate ready e pode ser aceito apos a pausa. Nao existe timeout em hardware
para esperar o motor grafico: o software deve impor o seu.

Troca ativo/passivo so e aceita com CPU_BUSY=0, GFX_BUSY=0 e FIFO vazia. Pausar
uma CPU no meio de programa e depois voltar ao modo ativo preserva seu ponto
de execucao; use RESTART para novo programa. Mudar de modo nao e um reset.
CONTROL aceita RUN/PASSIVE como **niveis**, portanto preserve esses bits ao
enviar RESTART ou CLEAR_ERRORS. Uma escrita de controle rejeitada nao modifica
esses niveis. RESTART e rejeitado se a GPU estiver ocupada; quando aceito, limpa
a fila, reinicia CPU e zera OUT_COUNT/ultimo OUT. Nao apaga framebuffer, memoria
grafica ou FRAME_COUNT; nao desfaz comandos ja transferidos.

KEY1 (demo_start) e aceito apenas quando CPU/GPU estao ociosas e FIFO vazia;
seleciona ativo, reinicia e executa o programa da memoria. No boot, ativo parado.

## Conexao HPS

Os offsets acima são acessados por `gpu_mailbox` dentro da FPGA. No ARM,
utilize `gpuctl` ou implemente o protocolo RAM HPSG; não os trate como
registradores diretamente mapeados pela lightweight nesta revisão.
KEY1 está desabilitado no topo HPS para preservar um único produtor.
