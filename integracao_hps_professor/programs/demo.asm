; Programa da ISA GPU: cena completa, apresentado apenas depois das alteracoes.
; WRITE porta,valor expande para LUI/LDI/ADD/OUT usando R14 e R15.
.equ SCROLL_X, 0x00
.equ SCROLL_Y, 0x01
.equ SPRITE, 0x10
.equ POLYGON, 0x30
.equ PRESENT, 0xF0

WRITE 0x03, 1             ; background habilitado
WRITE 0x02, 0             ; prioridade baixa
WRITE SCROLL_X, 24
WRITE SCROLL_Y, 16

; Uma entrada do tilemap, endereco linear y*40+x.
WRITE 0x20, 65
WRITE 0x21, 2

; Cor 6 da paleta, demonstrando envio de uma cor RGB de 24 bits.
WRITE 0x26, 6
WRITE 0x27, 0xF6C85F

; Quatro sprites; o segundo espelhado horizontalmente, o terceiro verticalmente.
WRITE SPRITE, 0
WRITE 0x11, 110
WRITE 0x12, 120
WRITE 0x13, 0
WRITE 0x14, 0x19          ; enable, prioridade 3
WRITE SPRITE, 1
WRITE 0x11, 150
WRITE 0x12, 120
WRITE 0x13, 1
WRITE 0x14, 0x1B          ; enable + hflip, prioridade 3
WRITE SPRITE, 2
WRITE 0x11, 190
WRITE 0x12, 120
WRITE 0x13, 2
WRITE 0x14, 0x15          ; enable + vflip, prioridade 2
WRITE SPRITE, 3
WRITE 0x11, 130
WRITE 0x12, 135
WRITE 0x13, 0
WRITE 0x14, 0x09          ; prioridade 1: sobreposicao visivel

; Retangulo por dois cantos inclusivos.
WRITE POLYGON, 0
WRITE 0x31, 220
WRITE 0x32, 150
WRITE 0x33, 290
WRITE 0x34, 195
WRITE 0x37, 6
WRITE 0x38, 3             ; enable, prioridade 1

; Triangulo com tres vertices.
WRITE POLYGON, 1
WRITE 0x31, 245
WRITE 0x32, 95
WRITE 0x33, 215
WRITE 0x34, 145
WRITE 0x35, 275
WRITE 0x36, 145
WRITE 0x37, 5
WRITE 0x38, 5             ; enable, prioridade 2

; Laco real da ISA: gera scroll 25,26,27,28 antes de apresentar.
LDI R3, 4
LDI R4, 1
LDI R5, 24
scroll_loop:
ADD R5, R5, R4
OUT R5, SCROLL_X
SUB R3, R3, R4
JZ R3, show
JMP scroll_loop
show:
WRITE PRESENT, 1
HALT
