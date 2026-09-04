# Núcleo do Coprocessador Gráfico em FPGA

Núcleo de um coprocessador gráfico descrito em Verilog RTL, inspirado na
arquitetura de consoles de 16 bits, com suporte a plano de fundo em tiles,
sprites independentes e rasterização de polígonos. Desenvolvido como
Problema #1 (2026.2) da disciplina MI — Sistemas Digitais, Departamento de
Tecnologia / Área de Eletrônica, UEFS.

O núcleo é preparado para, em etapas posteriores, ser controlado por um
driver Linux em Assembly ARM (via MMIO) e utilizado por uma aplicação de
jogo em linguagem C

> Desenvolvedores: Jones Becelar e Matheus Coelhos

---

## Sumário

1. [Requisitos funcionais e não funcionais](#1-requisitos-funcionais-e-não-funcionais)
2. [Arquitetura proposta e justificativa](#2-arquitetura-proposta-e-justificativa)
3. [Especificação de hardware](#3-especificação-de-hardware)
4. [Demonstração em hardware](#4-demonstração-em-hardware)
5. [Análise de recursos, timing e desempenho](#5-análise-de-recursos-timing-e-desempenho)
6. [Limitações e funcionalidades não atendidas](#6-limitações-e-funcionalidades-não-atendidas)
7. [Como sintetizar e rodar](#7-como-sintetizar-e-rodar)
8. [Controles de demonstração na placa](#8-controles-de-demonstração-na-placa)

---

## 1. Requisitos funcionais e não funcionais

### 1.1 Requisitos funcionais

| ID | Requisito | Módulo(s) responsável(is) | Situação |
|----|-----------|-----------------------------|----------|
| RF01 | Gerar sinal de vídeo VGA 640×480 a ~60 Hz | `vga_timing.v` | Atendido |
| RF02 | Operar cena em resolução lógica 320×240, com duplicação 2×2 na saída | `top_de1_soc.v` (`logical_x = pixel_x[9:1]`, `logical_y = pixel_y[8:1]`) | Atendido |
| RF03 | Renderizar plano de fundo em tilemap 40×30, tiles de 8×8, ≥256 padrões | `background_engine.v`, `tilemap_memory.v`, `tile_memory.v` | Atendido |
| RF04 | Permitir alteração do tile associado a cada posição do tilemap em tempo real | `tilemap_memory.v` (porta de escrita) + máquina de estados de patch em `top_de1_soc.v` (`KEY[1]`) | Atendido (demo grava um tile fixo em uma região 6×6) |
| RF05 | Permitir deslocamento horizontal e vertical do background | `top_de1_soc.v` (registradores `scroll_x`/`scroll_y`) + `background_engine.v` (wrap) | Atendido |
| RF06 | Suportar no mínimo 32 sprites de 16×16 pixels | `sprite_engine.v` (32 bancos de atributos), `sprite_memory.v` | Atendido |
| RF07 | Cada sprite com posição X/Y, índice de padrão, habilitação, prioridade, espelhamento H/V, seleção de paleta | `sprite_engine.v` | Atendido (seleção de paleta armazenada mas não aplicada — ver 6.1) |
| RF08 | Definir e aplicar prioridade entre sprites sobrepostos | `sprite_engine.v` (maior prioridade vence; empate → maior índice vence) | Atendido |
| RF09 | Rasterizar retângulos e triângulos preenchidos com aritmética inteira | `polygon_engine.v` (teste de limites para retângulo; *edge function* com aritmética sinalizada para triângulo) | Atendido |
| RF10 | Compor background, polígonos e sprites por pixel, com ao menos 3 níveis de prioridade | `top_de1_soc.v` (compositor: sprite > polígono > background) | Atendido |
| RF11 | Aplicar transparência (índice de cor 0) antes da seleção do pixel final | `sprite_engine.v` (`pixel_visible`) | Atendido |
| RF12 | Converter índice de 8 bits em RGB por paleta programável de 256 entradas | `palette.v` (`palette_with_sprite.hex`) | Atendido |
| RF13 | Permitir troca de cena de polígonos sem artefatos visuais (double buffer) | `top_de1_soc.v` (`rect_left_buffer0/1`, `tri_left_buffer0/1`, `active_polygon_buffer`, `polygon_swap_lock`) | Atendido |
| RF14 | Permitir demonstração via botões/chaves/LEDs da placa | `top_de1_soc.v` (mapeamento `KEY`/`SW`, seção 8) | Atendido |

### 1.2 Requisitos não funcionais

| ID | Requisito | Observação a partir do código |
|----|-----------|----------------------------------|
| RNF01 | Núcleo descrito em Verilog, com arquitetura modular (controle, datapath, memórias, motores gráficos, saída de vídeo separados) | Confirmado: cada camada tem módulo próprio (`background_engine`, `sprite_engine`, `polygon_engine`), memórias isoladas (`tile_memory`, `tilemap_memory`, `sprite_memory`) e paleta separada (`palette`) |
| RNF02 | Registradores e memórias com estratégia definida de reset/inicialização | `KEY[0]` funciona como reset síncrono ativo em nível baixo (`reset_n`), zerando registradores de timing, sprites e buffers de polígono a cada `posedge`. As memórias ROM/RAM são inicializadas via `$readmemh` em bloco `initial` |
| RNF03 | Saída sem instabilidade, perda de sincronismo ou pixels indefinidos após inicialização | `VGA_R/G/B` são forçados a `8'h00` fora da área ativa (`active_video`); sincronismo gerado por contadores livres em `vga_timing.v` |
| RNF04 | Núcleo, comandos e mapa de registradores projetados sem dependência de uma cena/jogo específico | Parcialmente atendido — o **núcleo** (engines) é agnóstico de cena, mas o **top-level de demonstração** ainda contém valores fixos (posição inicial do sprite, cor/posição de referência de retângulo e triângulo) |
| RNF05 | Uso de aritmética inteira em todo o datapath (sem ponto flutuante) | Confirmado: `polygon_engine.v` usa apenas `reg signed`/`wire signed` inteiros na *edge function* |

## 2. Arquitetura proposta e justificativa

### 2.1 Visão geral do pipeline

```
CLOCK_50 (50 MHz)
    │  (toggle flip-flop, gated por KEY[0])
    ▼
pixel_clock (25 MHz)
    │
    ▼
vga_timing ──────────────────────────► hsync, vsync, active_video
    │  (pixel_x, pixel_y — 640×480)
    ▼
logical_x, logical_y (320×240, pixel_x[9:1] / pixel_y[8:1])
    │
    ├─────────────────────────────┬───────────────────────────┐
    ▼                             ▼                           ▼
sprite_engine              background_engine             world_x, world_y
(usa logical_x/y           (usa logical_x/y +            (logical + scroll,
 SEM scroll —               scroll_x/y internamente,      com wrap 320×240,
 sprite “preso à tela”)      próprio wrap)                 calculado no top)
    │                             │                           │
    │                             │                           ▼
    │                             │                     polygon_engine
    │                             │                     (retângulo + triângulo,
    │                             │                      “presos ao mapa”)
    ▼                             ▼                           ▼
sprite_color_index      background_color_index      polygon_color_index
    └─────────────────────────────┴───────────────────────────┘
                                  ▼
                            Compositor
                (sprite > polígono > background)
                                  ▼
                              palette
                    (índice 8 bits → RGB24)
                                  ▼
                         VGA_R / VGA_G / VGA_B
                    (forçado a 0 fora de active_video)
```

### 2.2 Justificativa das decisões de arquitetura

- **Sprites em espaço de tela vs. polígonos em espaço de mundo**: o
  `sprite_engine` recebe `logical_x`/`logical_y` diretamente, **sem** o
  deslocamento de scroll — ou seja, sprites se comportam como elementos de
  HUD/jogador, fixos em relação à tela, independente do scroll do cenário.
  Já o `polygon_engine` recebe `world_x`/`world_y` (coordenada lógica somada
  ao scroll, com wrap), fazendo os polígonos se moverem junto com o mapa,
  como se fossem objetos do cenário. Essa distinção foi uma escolha
  deliberada para cobrir os dois casos de uso mais comuns em jogos 2D
  (personagem fixo na tela vs. objeto preso ao mundo).
- **Prioridade fixa no compositor** (sprite > polígono > background):
  resolvida por um `assign` combinacional simples (`sprite_visible ? ... :
  polygon_visible ? ... : background_color_index`), sem custo de ordenação
  em tempo de execução, atendendo ao mínimo de 3 níveis de prioridade
  exigido.
- **Paleta indexada de 8 bits** em vez de RGB direto por pixel: reduz a
  largura de dados armazenada por tile/sprite/polígono (1 byte por pixel em
  vez de 3), ao custo de uma tabela de consulta (`palette.v`) antes da
  saída.
- **Resolução lógica 320×240 com duplicação 2×2**: simplifica os motores
  gráficos e reproduz a estética de consoles 16-bits, mantendo
  compatibilidade com VGA 640×480 @ 60 Hz sem exigir um segundo modo de
  vídeo.
- **Double buffer apenas para polígonos**: implementado com dois pares de
  registradores (`rect_left_buffer0/1`, `tri_left_buffer0/1`) e um bit de
  buffer ativo (`active_polygon_buffer`), trocado de forma atômica por
  `KEY[3]` com trava (`polygon_swap_lock`) para evitar múltiplas trocas em
  um único toque. Essa camada foi escolhida para o double buffer porque é a
  mais suscetível a trocas de cena em bloco (ex.: telas de menu/efeitos);
  sprites e tiles já são atualizados de forma incremental, célula a célula,
  sem esse risco.
- **Edge function com aritmética inteira sinalizada** para triângulos: evita
  qualquer divisão ou ponto flutuante; o teste de sinal dos três produtos
  vetoriais (`edge0`, `edge1`, `edge2`) funciona independentemente da ordem
  ou orientação dos vértices.
- **Reset único (`KEY[0]`) compartilhado por todo o datapath**: simplifica a
  demonstração (um único botão reinicializa scroll, sprites, buffers de
  polígono e a máquina de estados de edição do tilemap), mas também corta o
  próprio `pixel_clock` enquanto pressionado — importante explicar isso na
  demonstração ao vivo, para não ser confundido com perda de sincronismo.

## 3. Especificação de hardware

| Item | Especificação |
|------|----------------|
| Placa | Terasic **DE1-SoC** |
| FPGA | Intel/Altera **Cyclone V** (5CSEMA5F31C6) |
| Clock de entrada | `CLOCK_50` — 50 MHz (oscilador da placa) |
| Pixel clock (VGA) | 25 MHz, gerado por flip-flop de toggle a partir de `CLOCK_50`, gated por `KEY[0]` |
| Saída de vídeo | VGA (DAC de vídeo on-board da DE1-SoC), 640×480 @ 60 Hz |
| Entradas usadas na demonstração | `KEY[3:0]`, `SW[9:0]` |
| Ferramenta de síntese | Intel Quartus Prime **25.1std.0** (Build 1129, SC Lite Edition) |



## 5. Análise de recursos, timing e desempenho


| Recurso | Utilizado | Disponível na Cyclone V (5CSEMA5F31C6) | % |
|---------|-----------|------------------------------------------|---|
| Logic utilization (ALMs) | 3.301 | 32.070 | 10% |
| Registradores totais | 4.104 | — | — |
| Pinos totais | 44 | 457 | 10% |
| Memória embarcada (bits) | 0 | 4.065.280 | 0% |
| Blocos DSP | 3 | 87 | 3% |
| PLLs | 0 | 6 | 0% |
| DLLs | 0 | 4 | 0% |

**Observações a partir dos números acima:**

- **Utilização de ALMs baixa (10%)**: há bastante margem para crescer o
  projeto (mais sprites ativos simultaneamente, mais primitivas de
  polígono, paletas por sprite, etc.) sem esgotar a lógica disponível da
  Cyclone V.
- **Memória embarcada em 0%**: nenhuma das memórias do projeto
  (`tile_memory`, `sprite_memory`, `tilemap_memory`, `palette`) foi mapeada
  para blocos de memória dedicados (M10K); o Quartus sintetizou os arrays
  `reg` como lógica distribuída nos ALMs. Isso explica parte do consumo de
  ALMs e é uma oportunidade de otimização: inferir memória embarcada
  explicitamente tende a reduzir a utilização de lógica.
- **3 blocos DSP utilizados**: coerente com as multiplicações de 12×12 bits
  da *edge function* do `polygon_engine.v` (uma para cada aresta do
  triângulo), que o sintetizador mapeou para multiplicadores dedicados em
  vez de lógica genérica.
- **Nenhum PLL utilizado**: o `pixel_clock` de 25 MHz é gerado por um
  flip-flop de toggle simples a partir de `CLOCK_50`, e não por um PLL
  dedicado — funciona, mas não garante a mesma precisão/jitter de um clock
  gerado por PLL (ex.: 25,175 MHz do padrão VGA exato).


**Desempenho observado**: 60 quadros por segundo, sem tearing, com
composição em tempo real das três camadas (background, sprites e polígonos
com double buffer).


## 6. Como sintetizar e rodar

1. Abra o Intel Quartus Prime 25.1std.0 (SC Lite Edition).
2. Crie um novo projeto apontando para a placa **DE1-SoC**.
3. Clique em 'Project' -> 'Restore Archived Project' e selecione o arquivo 'pbl_gpu_final_Fase1_Bufferizado.qar' baixado neste repositorio, dentro da pasta 'Versão Atual'
4. Defina `top_de1_soc.v` como o módulo top-level.
5. Aplique o arquivo de restrições de pinos (`.qsf`/`.sdc`) mapeando VGA,
   `KEY`, `SW` e `CLOCK_50`.
6. Compile o projeto (Start Compilation) e verifique o relatório de síntese.
7. Grave o bitstream na FPGA (Programmer).
8. Conecte um monitor VGA à placa e utilize os controles da seção 8.

## 7. Controles de demonstração na placa

| Entrada | Função |
|---------|--------|
| `KEY[0]` | Reset global síncrono (ativo em nível baixo) — também interrompe o `pixel_clock` enquanto pressionado (ver 6.2) |
| `KEY[1]` | Entra/alterna o modo de edição dinâmica de uma região 6×6 do tilemap |
| `KEY[2]` | Habilita o scroll do background (mantido em nível baixo enquanto ativo) |
| `KEY[3]` | Modo polígono (`SW[5]=0`): move retângulo/triângulo do buffer ativo com `SW[9:6]`, ou troca de buffer se `SW[9:6]=0000` |
| `SW[2:0]` | Direção do scroll (usado com `KEY[2]`): `000` direita, `001` esquerda, `011` cima, `111` baixo |
| `SW[3]` | Flip horizontal do sprite 0 |
| `SW[4]` | Flip vertical do sprite 0 |
| `SW[5]` | `1` = modo sprite (move sprite 0 com `SW[9:6]`); `0` = modo polígono |
| `SW[9:6]` | Direção do movimento (sprite ou polígono, conforme `SW[5]`) |

> Conforme o enunciado, botões/chaves/LEDs são usados exclusivamente para
> demonstração neste entregável, e não substituem a futura interface MMIO
> que será implementada pelo driver Linux em etapas posteriores.
