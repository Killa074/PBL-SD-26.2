# ISA grafica de 32 bits — fase 2

O programa em `programs/demo.asm` e Assembly **da nossa ISA**, diferente de
Assembly ARM executado pela HPS. `python tools/assemble.py programs/demo.asm`
gera `programs/demo.hex`: 1024 palavras, completadas com HALT. Para mudar a ROM
de configuracao da FPGA, monte o programa e recompile o Quartus.

## Formato e instrucoes

Campos: opcode `[31:28]`, destino Rd `[27:24]`, fonte Ra `[23:20]`, fonte Rb
`[19:16]`, imediato `[15:0]`. Ha 16 registradores de 32 bits; R0 sempre vale zero.
Campos nao usados devem ser zero; palavras malformadas encerram com ERROR.

| Codigo | Assembly | Efeito |
|---|---|---|
| 0 | NOP | Avanca |
| 1 | LDI Rd, imediato | Imediato com sinal, -32768..32767 |
| 2 | ADD Rd, Ra, Rb | Soma modulo 2^32 |
| 3 | SUB Rd, Ra, Rb | Subtracao modulo 2^32 |
| 4 | AND Rd, Ra, Rb | E bit a bit |
| 5 | OR Rd, Ra, Rb | OU bit a bit |
| 6 | XOR Rd, Ra, Rb | OU exclusivo |
| 7 | SHL Rd, Ra, Rb | Desloca para esquerda por Rb[4:0] |
| 8 | SHR Rd, Ra, Rb | Desloca logicamente para direita por Rb[4:0] |
| 9 | MOV Rd, Ra | Copia Ra |
| A | OUT Ra, porta | Envia Ra a porta grafica de 8 bits |
| B | JMP endereco | PC recebe endereco `[9:0]` |
| C | JZ Ra, endereco | Salta quando Ra vale zero |
| D | SLT Rd, Ra, Rb | 1 se Ra < Rb, comparacao com sinal; senao 0 |
| E | LUI Rd, imediato | Carrega imediato sem sinal 0..65535 nos bits31:16 |
| F | HALT | Encerra com DONE=1; precisa RESTART para executar novamente |

Exemplos: `LDI R1,100` = 11000064; `OUT R1,0` = A0100000;
`HALT` = F0000000. OUT usa Ra, nao Rd. JZ compara o registrador diretamente,
independentemente das flags anteriores. Enderecos de salto sao indices de
instrucoes, nao enderecos em bytes.

ADD/SUB/AND/OR/XOR/SHL/SHR/SLT atualizam flags `[3:0]={V,C,N,Z}`. SUB define C=1
quando nao ha emprestimo. SHL/SHR guardam o ultimo bit removido em C; deslocamento
zero define C=0. Operacoes logicas e SLT definem C=V=0. LDI/LUI/MOV nao alteram
flags. Um salto para fora da memoria ou avanco alem da ultima palavra causa
ERROR=1, DONE=0, CPU parada; o PC nunca circula silenciosamente para zero.

## Montador

Aceita rotulos, `.equ NOME, expressao`, `.word expressao` e comentarios `;`, `#`
ou `//`. Expressoes inteiras aceitam +, -, *, %, <<, >>, &, |, ^ e ~.
Valores decimais/hexadecimais/binarios sao aceitos. Nomes nao diferenciam caixa.
Nao executa codigo Python do arquivo. Saltos, registradores, argumentos e
imediatos sao verificados; erro encerra o comando sem sobrescrever o HEX.

Pseudoinstrucoes sao expandidas pelo montador; nao exigem novos opcodes:

- `LI32 Rd, Rt, valor`: LUI, LDI e ADD para qualquer inteiro de 32 bits. Rd e Rt
  devem ser diferentes e nao podem ser R0. Rt e alterado. O montador ajusta a
  metade superior para compensar a extensao de sinal de LDI.
- `WRITE porta, valor`: LI32 R14,R15,valor seguido de OUT R14,porta; altera R14 e
  R15. Cada WRITE ocupa quatro palavras. Rotulos ja consideram essa expansao.

## Busca ativa e controle

FETCH solicita uma leitura sincrona da RAM; CAPTURE guarda a palavra no IR;
EXECUTE decodifica e executa. OUT entra em OUTPUT_WAIT: valid, porta e valor
permanecem estaveis ate ready=1. Somente essa transferencia avanca o PC.
Isso permite ao motor grafico atrasar comandos durante renderizacao/apresentacao.

RUN=0 pausa sem perder o estado da instrucao. Uma saida ja oferecida continua
valida e pode terminar mesmo com RUN=0; depois a CPU fica pausada. RESTART zera
PC, IR, registradores, flags, DONE e ERROR e cancela uma saida ainda nao aceita;
nao desfaz comandos ja aceitos. Reset e RESTART preservam a memoria do programa.
Escritas do host so sao aceitas com RUN=0 e nenhuma saida CPU pendente. Apos
carregar um programa novo, usar RESTART antes de executar.

CPU_DONE informa HALT; nao garante que o quadro foi exibido. Acompanhar
GFX_BUSY/FRAME_COUNT quando o programa usa PRESENT. Sao eventos diferentes.

## Portas graficas

| Porta | Registro/operacao |
|---|---|
| 00 / 01 / 02 / 03 | scroll X / scroll Y / prioridade background / enable |
| 10..14 | indice sprite / X / Y / padrao / flags |
| 20 / 21 | endereco tilemap / dados com autoincremento |
| 22 / 23 | endereco pixel tile / dados com autoincremento |
| 24 / 25 | endereco pixel sprite / dados com autoincremento |
| 26 / 27 | endereco paleta / RGB24 com autoincremento |
| 30..38 | indice poligono / X0 / Y0 / X1 / Y1 / X2 / Y2 / cor / flags |
| F0 | PRESENT: renderiza quadro de tras e troca na fronteira de quadro |
| F1 | Limpa erro grafico |

Flags sprite: enable bit0, espelho H bit1, espelho V bit2, prioridade bits4:3,
banco de paleta bits8:5. Poligono indice0=retangulo, indice1=triangulo; flags
enable bit0, prioridade bits2:1. Consulte tambem a documentacao grafica para
dimensoes, limites, empates de prioridade e formato das memorias.
