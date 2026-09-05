
DEBUG = 1

; Segment definitions for the memory layout
.segment "ZEROPAGE" :mem $0 :size $100 :zp
.segment "STACK" :mem $100 :size $100 :bss
.segment "OAM" :mem $200 :size $100 :bss
.segment "BSS" :mem $300 :size $500 :bss
.segment "HEADER" :mem $0 :size $10 :out :fill
.segment "CODE" :mem $8000 :size $8000 :out :fill

.include "popslide.inc"

; constants
OAM = $02

PPUCTRL = $2000
PPUADDR = $2006
PPUDATA = $2007

BUTTON_A      = 1 << 7
BUTTON_B      = 1 << 6
BUTTON_SELECT = 1 << 5
BUTTON_START  = 1 << 4
BUTTON_UP     = 1 << 3
BUTTON_DOWN   = 1 << 2
BUTTON_LEFT   = 1 << 1
BUTTON_RIGHT  = 1 << 0

; Global jump table
.define JmpTableList \
  GameTitle-1, \
  GameLoad-1, \
  GamePlay-1

.enum Jump
    GAMEMODE_TITLE
    GAMEMODE_LOAD
    GAMEMODE_PLAY
.endenum

; RAM values

.zeropage

temp: .res 16
; save enough space for both controllers
buttons: .res 2
frame_count: .res 1
main_complete: .res 1
ppuctrl_mirror: .res 1
game_state: .res 1
level: .res 1

.segment "OAM"
.repeat 64, I
    .ident(.sprintf("spr_x_%d", I)): .res 1
    .ident(.sprintf("spr_tile_%d", I)): .res 1
    .ident(.sprintf("spr_attr_%d", I)): .res 1
    .ident(.sprintf("spr_y_%d", I)): .res 1
.endrepeat

.bss


; ROM code / data
.segment "HEADER"
.byte "NES",$1A,$02,$00,$A0,$D8 ; set mapper 218

.code

.org $fffa
.word Nmi, Reset, $0000
.reloc

.proc Reset
    sei        ; ignore IRQs
    cld        ; disable decimal mode
    ldx #$40
    stx $4017  ; disable APU frame IRQ
    ldx #$ff
    txs        ; set stack pointer to $01ff
    inx        ; now X = 0
    stx $2000  ; disable NMI
    stx $2001  ; disable rendering
    stx $4010  ; disable DMC IRQs

    bit $2002

@vblankwait1:
    bit $2002
    bpl @vblankwait1

    txa
@clrmem:
    sta $00,x
    pha
    sta $200,x
    sta $300,x
    sta $400,x
    sta $500,x
    sta $600,x
    sta $700,x
    inx
    bne @clrmem

@vblankwait2:
    bit $2002
    bpl @vblankwait2

ColdBoot:
    ; Clear out the nametables and attributes
    ldx #$20
    stx PPUADDR
    ldx #0
    stx PPUADDR
    lda #$ff
    -   sta PPUDATA
        sta PPUDATA
        sta PPUDATA
        sta PPUDATA
        sta PPUDATA
        sta PPUDATA
        sta PPUDATA
        sta PPUDATA
        dex
        bne -

    lda #$80 | $10
    sta ppuctrl_mirror
    sta PPUCTRL

Main:
    lda frame_count
    inc main_complete
-   cmp frame_count
    beq -
StartFrame:
    ldx game_state
    jsr JmpEngine
    dec main_complete
    jmp Main
.endproc

.proc JmpEngine
    lda JmpTableListHi,x
    pha
    lda JmpTableListLo,x
    pha
    rts

JmpTableListLo:
.lobytes JmpTableList
JmpTableListHi:
.hibytes JmpTableList
.endproc

.proc GameTitle
    lda buttons
    and #BUTTON_A | BUTTON_B | BUTTON_START
    beq Exit
        inc game_state
Exit:
.if DEBUG
    ; skip the title screen
    inc game_state
.endif
    rts
.endproc

.proc GameLoad
    rts
.endproc

.proc GamePlay
    rts
.endproc

.proc Nmi
    pha
    txa
    pha
    tya
    pha

    ; Don't run OAMDMA or controller reads during a lag frame
    lda main_complete
    bmi MainNotComplete

    ; run the background update
    jsr popslide_terminate_blit

    ; Run OAMDMA + read controllers with synced code
    lda #OAM
    sta $4014          ; ------ OAM DMA ------
    ldx #1             ; get put          <- strobe code must take an odd number of cycles total
    stx buttons+0      ; get put get      <- buttons must be in the zeropage
    stx $4016          ; put get put get
    dex                ; put get
    stx $4016          ; put get put get
-
    lda $4017          ; put get put GET  <- loop code must take an even number of cycles total
    and #3             ; put get
    cmp #1             ; put get
    rol buttons+1, x   ; put get put get put get (X = 0; waste 1 cycle for alignment)
    lda $4016          ; put get put GET
    and #3             ; put get
    cmp #1             ; put get
    rol buttons+0      ; put get put get put
    bcc -              ; get put [get]    <- this branch must not be allowed to cross a page

    lda #0
MainNotComplete:
    inc frame_count
    pla
    tay
    pla
    tax
    pla
    rti
.endproc

.jsbegin
/**
 * @param {string} data
 * @returns {number[]}
 */
function parsePattern(data, key) {
  const text = data.trim().replace(/^[^|]*\||\|[^|]*$/mg, '').replace(/\n/g, '');
  if (text.length !== 64) throw new Error(`Bad CHR tile: ${text}`);
  const arr = new Array(16).fill(0);
  for (let i = 0, c = ''; c = text.charAt(i); ++i) {
    const off = i >>> 3;
    const lo = off;
    const hi = off | 8;
    const col = ~i & 7;
    const val = key[c] || 0;
    if (val & 1) {
      arr[lo] |= 1 << col;
    }
    if (val & 2) {
      arr[hi] |= 1 << col;
    }
  }
  return arr;
}

const DICE_FACE = parsePattern(`
    |xx::::::|
    |x:      |
    |:      *|
    |:    ***|
    |:   ****|
    |:  *****|
    |:  *****|
    |: ******|
`, {'x': 0, ':': 1, ' ': 2, '*': 3});

// put the chr bytes into the assembler
a.label("DICE_FACE");
a.byte(DICE_FACE);
.jsend
