# Protocolo RAM HPSG — ABI 1

## Organização

HPS ARM → ponte hps2fpga principal → RAM64 KiB (porta A64) ↔ porta B32 adaptada → `gpu_mailbox` → registradores internos GPU3 → CPU ou FIFO → gráficos → VGA.

Foi escolhida a alternativa de segunda porta descrita no relatório, em vez de gerar um novo mestre/interconector Qsys. A configuração HPS/DDR e o handoff do professor permanecem os mesmos. A interface externa é uma mailbox na RAM, não a janela MMIO direta da versão anterior. Assim também eliminamos a disputa entre dois produtores GPU3: somente a mailbox escreve nesses registradores, e KEY1 não executa o programa nesse alvo.

Endereço físico base ARM: **0xC0000000**, tamanho 65.536 bytes. A lightweight original continua oferecendo System ID em `0xFF210000` e JTAG UART em `0xFF220000`; não é o transporte gráfico desta versão.

## Cabeçalho: offsets em bytes

| Offset | Campo | Quem escreve |
|---|---|---|
| 00 | MAGIC = 48505347 (HPSG) | FPGA |
| 04 | ABI = 1 | FPGA |
| 08 | DONE_SEQ, última sequência concluída | FPGA |
| 0C | Reservado, não usar | — |
| 10 | BUSY (0/1) | FPGA |
| 14 | ERROR, erro do protocolo | FPGA |
| 18 | RESULT, resultado de READ_REGISTER | FPGA |
| 1C | PROCESSED, instruções copiadas/comandos enfileirados | FPGA |
| 20 | Snapshot GPU_STATUS | FPGA |
| 24 | Snapshot GPU_ERROR | FPGA |
| 28 | Snapshot FRAME_COUNT | FPGA |
| 2C | Snapshot OUT_COUNT | FPGA |
| 30 / 34 / 38 | Snapshot PC / IR / CONTROL | FPGA |
| 40 | REQUEST_SEQ, publicar por último | HPS |
| 44 | Reservado, não escrever | — |
| 48 | OP | HPS |
| 4C | COUNT | HPS |
| 50 / 54 | ARG0 / ARG1 | HPS |
| 100… | Payload | HPS enquanto ocioso |

Todos os campos têm 32 bits little-endian, com acesso alinhado. REQUEST_SEQ e DONE_SEQ têm palavras físicas de 64 bits exclusivas: não colocar campos mutáveis nos offsets reservados adjacentes. A RAM usa byteenable para proteger a outra metade. O leitor confirma a sequência em duas leituras para não interpretar um valor transitório de leitura/escrita simultânea como pedido válido.

No reset, FPGA limpa as primeiras 128 bytes e publica ABI/MAGIC ao final. RAM de payload, IMEM e VRAM não são restauradas por esse reset. Não resetar durante uma sessão de software; a recuperação exige nova conexão/preparação.

## Operações

| OP | Significado | Parâmetros |
|---|---|---|
| 1 | READ_REGISTER | ARG0 = offset GPU3 em bytes; RESULT recebe valor |
| 2 | WRITE_REGISTER | ARG0 = offset GPU3; ARG1 = dado |
| 3 | LOAD_PROGRAM | COUNT = 1…1024; payload de COUNT palavras32 |
| 4 | COMMANDS | COUNT = 1…4096; payload = pares porta32, dado32 |

READ/WRITE permitem endereços alinhados 00…40. A GPU aplica as permissões dos seus registradores e sinaliza GPU_ERROR; erro de GPU não é o mesmo que ERROR da mailbox. Para o mapa GPU3, consulte MMIO.md; os offsets lá são **internos**, não somáveis a `0xFF200000` nesta integração.

LOAD_PROGRAM só é aceito com CONTROL=0, CPU/renderizador ociosos e FIFO vazia. A cópia começa na IMEM0 e não inicia execução automaticamente. Escrever CONTROL=3 posteriormente inicia/reinicia a CPU. A RAM comporta mais dados, mas a CPU continua limitada a 1.024 instruções.

COMMANDS exige CONTROL=5 (RUN|PASSIVE). Cada registro ocupa 8 bytes; porta precisa caber em 8 bits. O leitor espera FIFO_FREE, escreve CMD_PORT e CMD_DATA consecutivamente e nunca mistura produtores. Um comando já na FIFO pode aguardar renderização. Após 50.000.000 ciclos consecutivos sem vaga (1 s a 50 MHz), o lote termina com erro e contagem parcial; comandos já publicados não são desfeitos.

O driver C divide lotes em até 256 comandos para cada transação. Essa é uma escolha de software; a capacidade de um pedido no hardware é 4.096.

## Publicação e conclusão

1. Um único processo proprietário verifica MAGIC/ABI, BUSY=0 e REQUEST_SEQ=DONE_SEQ.
2. Escreve payload e descritor. Faz barreiras de memória e readback pela mesma ponte para ordenar e confirmar escritas.
3. Publica REQUEST_SEQ não zero, diferente da última concluída.
4. Não modifica cabeçalho HPS/payload até DONE_SEQ corresponder ao pedido.
5. FPGA captura descritor, executa, grava snapshots/resultado/contagem/erro, limpa BUSY e escreve DONE_SEQ **por último**.
6. HPS lê resultado. Repetir a mesma sequência não executa novamente o pedido concluído.

Os snapshots são do momento da conclusão; não são telemetria continuamente atualizada. Para obter estado novo, usar READ_REGISTER/status. Não se deve esperar FRAME_COUNT mudar apenas relendo um snapshot antigo.

CONCLUSÃO DO LOTE ≠ CONCLUSÃO DO QUADRO. `PROCESSED` conta inserções na fila, não pixels apresentados. Usar leituras novas de FRAME_COUNT e esperar GPU/FIFO ociosas; a ferramenta faz isso para os comandos de alto nível.

## Erros do protocolo

0 sucesso; 1 OP desconhecida; 2 parâmetros/alinhamento/quantidade inválidos; 3 estado GPU incompatível; 4 porta fora de 8 bits; 5 timeout de FIFO.

Porta inválida no meio do lote e timeout podem produzir conclusão parcial. PROCESSED informa exatamente o prefixo já transferido. Não reenviar o lote inteiro automaticamente.

## Adaptação do professor, arquivos e regeneração

- `professor/soc_system/synthesis/soc_system.v`: quatro portas de dados adicionais encaminhadas para a RAM e uma saída `gpu_ram_ready`, que impede liberar o reset GPU antes da RAM estar disponível.
- `professor/soc_system/synthesis/submodules/soc_system_onchip_memory2_0.v`: mesma RAM64KiB, agora BIDIR_DUAL_PORT; adaptação da porta B para palavras32 e byteenable.
- `professor/soc_system/synthesis/soc_system.qip`: removida referência MISC_FILE a `../../E`, inexistente no pacote original.
- `rtl/ghrd_top.v`: adiciona GPU/mailbox/reset sincronizado/VGA e LEDs; sinais de diagnóstico antes sem driver são definidos.
- `hps_ddr_locations.qsf`: fixa posições já registradas no `.pin` original do professor. Não modifica pinmux/periféricos HPS.
- `pbl_hps_professor.qsf`: reúne fontes, memórias e restrições; preserva a hierarquia HPS `u0` usada pelas restrições DDR.

O `.qsys` incluído permanece referência da base original. Não produz sozinho as alterações locais descritas acima. Para migrar/regenerar IPs, implementar/exportar a segunda porta novamente e adaptar seus nomes/latência antes de usar o resultado. Nesta entrega, os HDL necessários já estão incluídos e o QPF compila diretamente; não depende de geração HPS/DDR nova.

## Limitações deliberadas

Sem DMA DDR, interrupção para a mailbox, múltiplos blocos simultâneos ou ring buffer. Memória compartilhada é RAM FPGA, não DDR HPS. Transferência feita por polling; taxa máxima não foi medida em placa. Timeout de software não interrompe uma transação física pendurada na ponte.

Os comandos de software exigem modo passivo preparado; `load` usa a CPU ativa. Receber um arquivo do ARM não torna esse programa Assembly ARM: o coprocessador continua executando sua ISA própria.
