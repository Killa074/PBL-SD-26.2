# Contrato do motor gráfico

Coordenadas são pixels lógicos em 320×240. O VGA mostra cada pixel em 2×2, totalizando 640×480. O clock de pixels é 25 MHz (50 MHz / 2), total 800×525: aproximadamente **59,52 Hz**, não exatamente 60,00 Hz. Monitor e DAC reais ainda precisam ser testados.

## Memórias e objetos

| Recurso | Organização |
|---|---|
| Tilemap | 40×30 entradas de 8 bits; endereço = y×40+x |
| Tiles | 256 padrões 8×8; endereço = padrão×64+y×8+x |
| Sprites | 256 padrões 16×16; endereço = padrão×256+y×16+x |
| Atributos sprites | 32 slots: X, Y, padrão, enable, flips, prioridade, banco |
| Paleta | 256 entradas RGB24 |
| Polígonos | Um retângulo e um triângulo |
| Framebuffers | Dois buffers 320×240, cada pixel com cor8+prioridade2 |

Pixels dos tiles contêm diretamente um índice 0..255. Pixels de sprite contêm índice LOCAL 0..15; o índice final é banco×16+local. O local zero é transparente em qualquer banco.

Polígonos também usam índice de paleta, não RGB direto; cor zero é transparente. O background pode exibir sua cor zero normalmente. Coordenadas de objetos são signed16 nos 16 bits inferiores do dado.

## Comandos

Todos usam porta8+dado32. A ISA envia com OUT; a HPS publica na fila.

| Porta hex | Dado e efeito |
|---|---|
| 00 / 01 | Scroll X 0..319 / Y 0..239, com circulação do mapa |
| 02 / 03 | Prioridade background 0..3 / enable 0 ou 1 |
| 10 | Seleciona slot sprite 0..31 |
| 11 / 12 | X / Y do sprite selecionado |
| 13 | Padrão sprite 0..255 |
| 14 | Flags sprite |
| 20 / 21 | Seleciona endereço tilemap / escreve tile 0..255, incrementa endereço |
| 22 / 23 | Seleciona endereço tile / escreve índice 0..255, incrementa |
| 24 / 25 | Seleciona endereço sprite / escreve índice LOCAL 0..15, incrementa |
| 26 / 27 | Seleciona endereço paleta / escreve RGB24, incrementa |
| 30 | Seleciona polígono: 0 retângulo, 1 triângulo |
| 31 / 32 | X0 / Y0 |
| 33 / 34 | X1 / Y1 |
| 35 / 36 | X2 / Y2 (triângulo) |
| 37 / 38 | Índice de cor 0..255 / flags polígono |
| F0 | PRESENT, dado ignorado |
| F1 | Limpa erro gráfico, dado ignorado |

Sprite flags: bit0 enable; bit1 flip H; bit2 flip V; bits4:3 prioridade; bits8:5 banco. Exemplo 0x19 = habilitado, prioridade3, banco0, sem flip.

Polígono flags: bit0 enable; bits2:1 prioridade. Retângulo inclui os dois extremos, normaliza cantos invertidos. Triângulo aceita as duas ordens dos vértices, usa produtos inteiros de 35 bits e não desenha quando a área é zero. Objetos fora da tela são recortados, não circulam para a outra borda.

Maior prioridade vence. Em empate: sprite de maior slot > outros sprites > triângulo > retângulo > background. Transparência nunca apaga o que já estava atrás.

## Sincronização e erros

Enquanto PRESENT renderiza/aguarda troca, ready=0 e busy=1. O produtor deve manter valid/porta/dado, ou guardar comandos na fila. Não modificar VRAM durante esse período: a interface só aceita quando ready=1.

FRAME_COUNT aumenta **depois** da troca. Não confundir terminar de enfileirar com terminar de mostrar. O C guarda o contador antes de enviar PRESENT e espera mudar, com timeout.

Comandos/endereço/cor inválidos geram erro persistente e não escrevem fora dos limites. Um endereço que ultrapassa o final pelo autoincremento torna-se inválido, não volta a zero. Seleções inválidas também não reutilizam silenciosamente o objeto anterior.

Reset zera controle e atributos de objetos e mantém VGA preto até PRESENT, mas não recarrega RAM/VRAM. Os HEXs são preload da configuração da FPGA. O RPG faz upload de seus assets e atributos antes do primeiro quadro.
