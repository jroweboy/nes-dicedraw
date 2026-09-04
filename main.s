
; constants
OAM = $02


; RAM values

.segment "ZEROPAGE" :mem $0 :size $100 :zp

temp: .res 16
; save enough space for both controllers
buttons: .res 2
frame_count: .res 1

.segment "STACK" :mem $100 :size $100 :bss


.segment "OAM" :mem $200 :size $100 :bss
.repeat 64, I
    .ident(.sprintf("spr_x_%d", I)): .res 1
    .ident(.sprintf("spr_tile_%d", I)): .res 1
    .ident(.sprintf("spr_attr_%d", I)): .res 1
    .ident(.sprintf("spr_y_%d", I)): .res 1
.endrepeat

.segment "BSS" :mem $300 :size $500 :bss

main_complete: .res 1

; ROM code / data

.segment "HEADER" :mem $0 :size $10 :fill
.byte "NES",$02,$00,$A0,$D8 ; set mapper 218

.segment "CODE" :mem $8000 :size $8000 :fill

.org $fffa
.word Nmi, Reset, $0000
.reloc

Reset:
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
    jmp StartFrame

Main:
    lda frame_count
    inc main_complete
-   cmp frame_count
    beq -
StartFrame:
    dec main_complete
    jmp Main

.proc Nmi
    pha
    txa
    pha
    tya
    pha

    ; Don't run OAMDMA or controller reads during a lag frame
    bit main_complete
    bvc MainNotComplete

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
