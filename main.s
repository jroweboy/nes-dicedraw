
.macpack common

DEBUG = 1

BUFFER_HI   := popslide_buf + 0
BUFFER_LO   := popslide_buf + 1
BUFFER_LEN  := popslide_buf + 2
BUFFER_DATA := popslide_buf + 3

PLAYER_X_OFFSET = 0
PLAYER_Y_OFFSET = 1

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
PPUMASK = $2001
PPUSTATUS = $2002
PPUSCROLL = $2005
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
  GamePlay-1, \
  Fadeout-1, \
  Fadein-1

.enum Jump
    GAMEMODE_TITLE
    GAMEMODE_LOAD
    GAMEMODE_PLAY
    FADEOUT
    FADEIN
.endenum

; RAM values

.zeropage

temp: .res 8
R0 := temp
R1 := temp+1
R2 := temp+2
R3 := temp+3
R4 := temp+4
R5 := temp+5
R6 := temp+6
R7 := temp+7
.exportzp R0, R1, R2, R3, R4, R5, R6, R7

; save enough space for both controllers
buttons: .res 2
frame_count: .res 1
main_complete: .res 1
ppuctrl_mirror: .res 1
ppumask_mirror: .res 1
game_state: .res 1
level: .res 1

player_x: .res 1
player_y: .res 1

player_x_sub: .res 1
player_y_sub: .res 1

player_sprite_tile: .res 1

square_color: .res 6

screen_bottom: .res 1
scroll_x: .res 1

.segment "OAM"
.repeat 64, I
    .ident(.sprintf("spr_y_%d", I)): .res 1
    .ident(.sprintf("spr_tile_%d", I)): .res 1
    .ident(.sprintf("spr_attr_%d", I)): .res 1
    .ident(.sprintf("spr_x_%d", I)): .res 1
.endrepeat

.bss
stamped: .res (32 * 32) / 8
palette: .res 32

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
    ; disable rendering on boot
    lda #0 sta ppumask_mirror sta PPUMASK
    jsr popslide_init

    ; Clear out the CHR, nametables, and attributes
    lda #$20
    sta PPUADDR
    lda #0
    sta PPUADDR
    jsr ClearNMTLoop
    lda #$28
    sta PPUADDR
    lda #0
    sta PPUADDR
    jsr ClearNMTLoop
    jsr ResetToDefaultPalette
    jsr UploadPalette

    lda #$80 | $10 sta ppuctrl_mirror sta PPUCTRL

Main:
    ldx game_state
    jsr JumpEngine
    jsr WaitForNMI
    jmp Main
ClearNMTLoop:
    ldx #0
    lda #$ff
    -   sta PPUDATA
        sta PPUDATA
        sta PPUDATA
        sta PPUDATA
        dex
        bne -
    rts
.endproc

.proc ResetToDefaultPalette
    ldx #32
    - lda DefaultPalette,x
      sta palette,x
      dex
      bne -
    rts
DefaultPalette:
    ; bg
    .byte $0f, $0f, $0f, $16
    .byte $0f, $0f, $0f, $27
    .byte $0f, $0f, $0f, $18
    .byte $0f, $0f, $0f, $0f
    ; sprites
    .byte $0f, $10, $30, $16
    .byte $0f, $0f, $0f, $0f
    .byte $0f, $0f, $0f, $0f
    .byte $0f, $0f, $0f, $0f
.endproc
.proc UploadPalette
    ldy popslide_used
    lda #$3f
    sta BUFFER_HI,y
    lda #$00
    sta BUFFER_LO,y
    lda #31
    sta BUFFER_LEN,y
    ldx #0
    - lda palette,x
      sta BUFFER_DATA,y
      iny
      inx
      cpx #32
      bne -
    sty popslide_used
    rts
.endproc

.proc WaitForNMI
    dec main_complete
    lda frame_count
-   cmp frame_count
    beq -
    inc main_complete
    rts
.endproc

.proc JumpEngine
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
    lda buttons and #BUTTON_A | BUTTON_B | BUTTON_START
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
    ; copy the CHR into vram
.if !DEBUG
    ldx #Jump::FADEOUT
    jsr JumpEngine
.endif
    lda ppumask_mirror and #~$1e sta ppumask_mirror
    jsr WaitForNMI

    jsr ResetToDefaultPalette


    ; reset player position
    ldx #16
    stx player_x
    dex
    stx player_y
    ldx #0
    sta player_x_sub
    sta player_y_sub

    lda #16


    ; Draw player CHR into offscreen ram
    ldx #0 stx PPUADDR stx PPUADDR
    -   lda DiceCHR,x
        sta PPUDATA
        inx
        cpx #DiceCHR_SIZE
        bne -

    lda ppumask_mirror ora #$1e sta ppumask_mirror
.if !DEBUG
    ldx #Jump::FADEIN
    jsr JumpEngine
.endif
    inc game_state
    rts
.endproc

.proc GamePlay
    lda buttons and #BUTTON_UP | BUTTON_DOWN | BUTTON_LEFT | BUTTON_RIGHT
    beq +
        jsr ProcessPlayerMovement
    +

    jsr DrawPlayer
    nop
    rts
.endproc

.proc ProcessPlayerMovement
    lda buttons and #BUTTON_UP | BUTTON_DOWN
    beq Exit
    ldx #PLAYER_Y_OFFSET
    and #BUTTON_UP
    beq Down
        ldy player_y
        beq +
            dey
            sty player_y
        +
        lda #-1
        jmp AnimateMovement
Down:
    lda #1
    ldy player_y
    cmp screen_bottom
    beq +
        dey
        sty player_y
    +
    jmp AnimateMovement

    lda buttons and #BUTTON_LEFT | BUTTON_RIGHT
    beq Exit

Exit:
    rts
.endproc

.proc AnimateMovement
    sta R0
    stx R1
    lda #16
    sta R7
NextFrame:
    ldy R1
    lda R0 clc adc player_x_sub,y sta R0
    jsr DrawPlayer
    jsr WaitForNMI
    ; jsr WaitForNMI
    dec R7
    bne NextFrame
    rts
.endproc

.proc DrawPlayer
    ldy #5
    sty R6
    -
        ldy R6
        jsr DrawPlayerSquare
        dec R6
        bpl -
    rts
.endproc

.proc DrawPlayerSquare
    ; x = oam offset
    ; y = which square to draw
    lda SquareOAMOffset,y tax
    lda player_x asl asl asl ora player_x_sub
    clc adc SquareXOffset,y
    sta spr_x_0,x sta spr_x_1,x
    clc adc #8
    sta spr_x_2,x sta spr_x_3,x
    lda player_y asl asl asl ora player_y_sub
    clc adc SquareYOffset,y
    sta spr_y_0,x sta spr_y_2,x
    clc adc #8
    sta spr_y_1,x sta spr_y_3,x
    lda player_sprite_tile sta spr_tile_0,x sta spr_tile_1,x sta spr_tile_2,x sta spr_tile_3,x
    lda #0 ora square_color,y sta spr_attr_0,x
    lda #$80 ora square_color,y sta spr_attr_1,x
    lda #$40 ora square_color,y sta spr_attr_2,x
    lda #$c0 ora square_color,y sta spr_attr_3,x
    rts
SquareXOffset:
    .byte 0, -16, 0, 16, 0, 0 
SquareYOffset:
    .byte -16, 0, 0, 0, 16, 32
SquareOAMOffset:
    .byte 0, 16, 32, 48, 64, 80
.endproc

; random ordering chosen by fair dice roll
RandomOrderTable:
.byte 0, 3, 14, 5, 10, 1, 7, 13, 15, 2, 9, 6, 11, 4, 8, 12
PALETTE_FADE_LEN = * - RandomOrderTable
.proc Fadeout
    lda #$0f ldx #32
    -   sta palette,x
        dex
        bne -
FALLTHROUGH Fadein
.endproc

.proc Fadein
    lda #<palette
    sta R4
    lda #>palette
    sta R5
FALLTHROUGH FadeFunc
.endproc

.proc FadeFunc
    lda #0
    sta R7
NextFrame:
    ; Every 16 frames step to the next palette
    lda frame_count and #$01 beq Wait
    ldy R7 cpy #PALETTE_FADE_LEN bne +
        rts
    +
    ldx popslide_used
    lda #$3f
    sta BUFFER_HI + 0,x
    sta BUFFER_HI + 4,x
    sta BUFFER_HI + 8,x
    lda #0
    sta BUFFER_LO + 8,x
    sta BUFFER_LEN + 0,x
    sta BUFFER_LEN + 4,x
    sta BUFFER_LEN + 8,x
    lda RandomOrderTable,y
    tay
    sta BUFFER_LO + 0,x
    ora #$10
    sta BUFFER_LO + 4,x
    lda (R4), y
    sta BUFFER_DATA + 0,x
    tya ora #$10 tay
    lda (R4), y
    sta BUFFER_DATA + 4,x
    lda #$0f ; need to point ppuaddr to the bg color so we don't cause flashing
    sta BUFFER_DATA + 8,x
    lda #$ff
    sta BUFFER_HI + 12,x
    txa
    clc
    adc #13
    sta popslide_used
    ; Move to the next color
    inc R7
Wait:
    jsr WaitForNMI
    jmp NextFrame
.endproc

.proc Nmi
    pha
    txa
    pha
    tya
    pha

    ; Don't run OAMDMA or controller reads during a lag frame
    lda main_complete
    beq MainNotComplete

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

    jsr ClearSprites

    lda #0
MainNotComplete:

    lda scroll_x
    sta PPUSCROLL
    sta PPUSCROLL

    lda ppuctrl_mirror
    sta PPUCTRL
    lda ppumask_mirror
    sta PPUMASK

    inc frame_count
    pla
    tay
    pla
    tax
    pla
    rti
ClearSprites:
    lda #$f8
.repeat 64, I
    sta spr_y_0 + I*4
.endrepeat
    rts
.endproc

TILESIZE = 16
.macro SET_RES_BASE addr
    RES_BASE .set addr
    RES_OFFSET .set 0
.endmacro
.macro RESV name, size
    .ident(.string(name)) = RES_BASE + RES_OFFSET
    .ifnblank size
        .ident(.sprintf("%s_SIZE", .string(name))) = size * TILESIZE
        RES_OFFSET .set RES_OFFSET + size * TILESIZE
    .else
        .ident(.sprintf("%s_SIZE", .string(name))) = TILESIZE
        RES_OFFSET .set RES_OFFSET + TILESIZE
    .endif
.endmacro

CHRBase:
.incbin "graphics.chr"
SET_RES_BASE CHRBase
RESV DiceCHR
RESV MarioCHR, 4

