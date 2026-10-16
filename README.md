# PBL 2 — Coprocessador gráfico em FPGA


O projeto implementa um sistema gráfico programável na DE1-SoC. O Linux da HPS recebe comandos do usuário e se comunica com a FPGA por uma RAM compartilhada. Na FPGA, o controle pode executar um programa de ISA própria ou consumir comandos gráficos enviados pelo software. O motor gráfico transforma a configuração da cena em pixels e mantém a saída VGA funcionando de forma independente.


## Guia de execução e avaliação

Este documento orienta a gravação do circuito na DE1-SoC e a execução de duas demonstrações da fase 2:

| Demonstração | Comando na HPS | O que demonstra |
| --- | --- | --- |
| Cena controlada por comandos externos | `sudo ./gpuctl --fpga demo` | O programa C envia comandos gráficos pela mailbox; a FIFO da FPGA alimenta o motor gráfico. |
| Programa da ISA do coprocessador | `sudo ./gpuctl --fpga load ../programs/demo.hex` | A HPS carrega instruções de 32 bits; a CPU da FPGA busca e executa o programa até `HALT`. |

**As duas demonstrações usam a mailbox como transporte HPS–FPGA.** A diferença é o conteúdo enviado e quem executa a sequência: comandos porta/dado no primeiro caso, programa da ISA no segundo.

O projeto desta entrega está em **`integracao_hps_professor/`**. Outras pastas de versões, se presentes no repositório, não são necessárias para este roteiro.

## 1. Arquivos e ambiente

Arquivos principais, a partir da raiz do repositório:

```text
integracao_hps_professor/
├── pbl_hps_professor.qpf              Projeto a abrir no Quartus
├── pbl_hps_professor.qsf              Fontes, dispositivo e pinagem
├── hps_ddr_locations.qsf              Restrições de pinos DDR
├── hps_gpu.sdc                        Restrições de clock da integração
├── professor/                        IPs e HDL HPS adaptados
├── rtl/                              Circuito do coprocessador e mailbox
├── assets/                           Memórias iniciais de gráficos
├── output_files/
│   └── pbl_hps_professor.sof          Circuito compilado para gravar
├── software/
│   ├── Makefile                      Compilação na HPS
│   ├── gpuctl.c                      Interface de comandos
│   ├── mailbox.c                     Protocolo de comunicação
│   ├── mmio_arm.S                    Acessos e barreiras no ARM
│   └── scene.c                       Cena da demonstração externa
└── programs/
    ├── demo.asm                      Programa fonte da ISA
    └── demo.hex                      Programa montado, pronto para carregar
```

Ambiente necessário:

- Placa DE1-SoC com FPGA Cyclone V 5CSEMA5F31C6.
- Alimentação, conexão USB-Blaster, monitor VGA e cabo de rede.
- Cartão SD do laboratório com Linux e inicialização HPS compatíveis com a base do professor.
- Computador do laboratório com Quartus Programmer e cliente SSH/SCP.
- GCC e `make` no Linux da HPS, além de permissão para executar `gpuctl` com `sudo`.

Neste guia, **PC** significa o computador Linux do laboratório. **HPS** significa o Linux executado na placa, acessado por SSH. Os comandos de acesso à FPGA devem ser executados na HPS.

A integração utiliza a **ponte principal HPS-to-FPGA**, com RAM compartilhada de 64 KiB em **`0xC0000000`**. A janela lightweight `0xFF200000` não é a interface gráfica desta versão. O software usa `/dev/mem` e `mmap`; não exige um módulo próprio de kernel nem um dispositivo `/dev/gpu`.

## 2. Gravar o circuito na FPGA — no PC

1. Extraia o ZIP para uma pasta de sua escolha.
2. Abra a pasta integracao_hps_professor
3. Abra pbl_hps_professor.qpf no Quartus.
5. Conecte alimentação, USB-Blaster, rede e monitor VGA. Preserve o cartão SD já preparado pelo laboratório.
6. Abra **Tools > Programmer**.
7. Em **Hardware Setup**, selecione o USB-Blaster correspondente à placa.
8. Selecione **Auto Detect** e **5CSEMA5**. Na linha do dispositivo FPGA Cyclone V, selecione **Change File** ou **Add File**, conforme a configuração do Programmer, e escolha:
   ```text
   integracao_hps_professor/output_files/pbl_hps_professor.sof
   ```
9. Marque **Program/Configure** na linha da FPGA. Não selecione o componente HPS como destino do SOF.
10. Clique em **Start** e aguarde **100% (Successful)**.

O SOF fornecido já está compilado. **Não é necessário recompilar para executar as demonstrações.** A programação por SOF é volátil: depois de desligar a placa, o circuito precisa ser carregado novamente.

### Condições antes de acessar a FPGA

Antes do primeiro `gpuctl --fpga`, o SOF correto deve estar configurado, a HPS inicializada e a ponte **principal** HPS-to-FPGA habilitada. 

As pontes são pré configuradas pelo laboratorio.


### Se for necessário recompilar

Use o projeto `pbl_hps_professor.qpf`, preferencialmente em um caminho sem espaços e acentos, e execute **Processing > Start Compilation**. A compilação fornecida utilizou Quartus Prime 25.1 Standard/Lite com suporte a Cyclone V.

## 3. Transferir o software e o programa da ISA — no PC Linux

Obtenha os 3 ultimos numeros do IP da placa e as credenciais utilizadas no laboratório. Os exemplos usam o usuário `aluno`; ajuste-o caso a conta seja outra. Substitua `IP_DA_PLACA` pelo endereço real. 

No terminal do PC, a partir da raiz deste repositório, sendo essa **integracao_hps_professor**:

```sh
ssh aluno@IP_DA_PLACA 'mkdir -p ~/pbl_fase2_entrega'
scp -O -r software programs aluno@IP_DA_PLACA:~/pbl_fase2_entrega/
ssh aluno@IP_DA_PLACA
```

O primeiro SSH cria a pasta remota e retorna. O `scp` transfere os arquivos. O último SSH abre a sessão na HPS.

Não é necessário copiar os arquivos do Quartus para a HPS: para estas demos, basta transferir `software/` e `programs/`. O circuito e as memórias iniciais de gráficos já estão no SOF.

## 4. Compilar e verificar a comunicação — na HPS, por SSH

A partir deste ponto, execute os comandos **no terminal remoto da placa**.

**Garanta que a placa esteja ligada e com SOF carregado!**

```sh
cd ~/pbl_fase2_entrega/software
make -B
```

O `-B` força a recompilação para o processador da HPS, evitando reutilizar um binário de outra máquina. O executável produzido chama-se **`gpuctl`**, sem extensão. Os arquivos `.exe`, se presentes, são executáveis Windows e não devem ser usados na placa.

Se a compilação terminar sem erros:

```sh
sudo ./gpuctl --fpga status
```

Resultado esperado:

- Identificação `GPU3 id=47505533`.
- Leitura de `CONTROL`, `STATUS`, `PC`, `IR`, `OUT_COUNT`, `FIFO_FREE`, `FRAME_COUNT` e `ERROR`.
- `ERROR = 0x00000000 (0)` no estado sem falhas.
- Mensagem `OK` ao final.

Os demais valores variam conforme o estado do circuito e as execuções anteriores. SSH funcionando, isoladamente, não comprova que a ponte e a mailbox estão disponíveis.


## 5. Demonstração A — cena por comandos externos / mailbox

Na HPS, dentro de `~/pbl_fase2_entrega/software`:

```sh
sudo ./gpuctl --fpga demo
sudo ./gpuctl --fpga status
```

O comando `demo` prepara o modo passivo, envia a paleta, os padrões gráficos e a configuração da cena pela mailbox, solicita `PRESENT` e aguarda a apresentação do quadro.

No monitor VGA, devem aparecer:

- Fundo de grama, rio, caminho e bordas de pedra.
- Dois personagens representados por sprites.
- Uma casa formada por um retângulo e um triângulo.

O terminal deve terminar cada comando com `OK`, e o status deve indicar `ERROR=0`. Esta cena vem do gerador em `software/scene.c`; 

### Alterações interativas opcionais

Execute um comando por vez e observe a saída VGA:

```sh
sudo ./gpuctl --fpga sprite 0 160 144 0 0x19
sudo ./gpuctl --fpga sprite 0 220 144 0 0x19
sudo ./gpuctl --fpga tile 5 5 1
sudo ./gpuctl --fpga scroll 16 8
sudo ./gpuctl --fpga rect 100 80 150 120 11
sudo ./gpuctl --fpga triangle 180 160 260 160 220 100 10
sudo ./gpuctl --fpga palette 10 0x3366ff
sudo ./gpuctl --fpga animate 120
sudo ./gpuctl --fpga status
```

Esses exemplos movem o personagem, substituem um tile, deslocam o fundo, alteram os polígonos e a paleta e executam uma animação.

As coordenadas gráficas usam a resolução lógica **320 × 240**, exibida em VGA **640 × 480**. No comando `tile`, os dois primeiros parâmetros são coluna e linha do mapa, não pixels. Há um retângulo e um triângulo configuráveis; novos comandos alteram esses objetos, inclusive os utilizados na casa.

Os comandos de alto nível acima já solicitam a apresentação da imagem. Não é necessário executar `present` separadamente. Para restaurar a cena conhecida:

```sh
sudo ./gpuctl --fpga demo
```

## 6. Demonstração B — carregar e executar demo.hex / ISA

Para uma sequência de avaliação reproduzível, comece restaurando a demonstração externa. Depois carregue o programa:

```sh
sudo ./gpuctl --fpga demo
sudo ./gpuctl --fpga load ../programs/demo.hex
sudo ./gpuctl --fpga status
```

O comando `load` realiza a preparação do núcleo, transfere o arquivo para a memória de instruções e **inicia a execução automaticamente a partir do PC inicial**. Não é necessário pressionar um botão nem enviar um comando de start adicional.

A CPU da FPGA busca as instruções, carrega o IR, executa a ISA e envia os comandos `OUT` ao motor gráfico. A ferramenta aguarda `HALT` e o término da atividade da GPU/fila antes de retornar.

### O que observar

- `load` termina com `OK`.
- O status apresenta `ERROR=0`.
- O bit `CPU_DONE` de `STATUS` (bit 1, máscara `0x2`) indica o término da CPU.
- `OUT_COUNT` registra as saídas geradas pelo programa; `PC` e `IR` permitem inspecionar o estado final.
- A imagem muda de acordo com o programa: reposicionamento de sprites e polígonos, alteração de uma entrada da paleta e do tilemap e deslocamento do fundo.

## 7. Documentação técnica

- [Arquitetura](integracao_hps_professor/docs/ARQUITETURA.md)
- [ISA e formato das instruções](integracao_hps_professor/docs/ISA.md)
- [Comandos e recursos gráficos](integracao_hps_professor/docs/GRAFICOS.md)
- [Protocolo da mailbox e adaptações da base HPS](integracao_hps_professor/docs/PROTOCOLO_HPS.md)
- [Mapa interno de registradores GPU3](integracao_hps_professor/docs/MMIO.md)
- [Fonte do programa demonstrado](integracao_hps_professor/programs/demo.asm)
- [Origem e licenças dos componentes](integracao_hps_professor/docs/THIRD_PARTY.md)

O mapa GPU3 é interno e acessado por operações da mailbox. Seus offsets não devem ser somados diretamente à base da RAM como se fossem periféricos expostos na ponte.
