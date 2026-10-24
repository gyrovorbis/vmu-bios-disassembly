;; =============================================================================
;;  Sega Dreamcast Visual Memory Unit (VMU) BIOS, American v1.05 (1999/10/26)
;;  "SEGA Visual Memory System BIOS Produced by Sue"   CPU: Sanyo LC86K87 (LC8670)
;; =============================================================================
;;
;;  ROM MAP
;;    $0000-$0062  interrupt vectors + trivial ISRs
;;    $0100-$01F2  public firmware entry points (FM_WRT_EX, FM_PRD_EX, ...)
;;    $0200-$3F32  the BIOS proper (menu, file manager, clock, Maple, VMU-to-VMU copy)
;;    $4000-$7FFF  zero fill
;;    $E000-$E02F  flash library jump table (Sanyo-supplied, BRF r16 each)
;;    $E100-$E4E7  flash library: factory tests, page read/write/verify, clock tick
;;    $E800-$EFFF  6x8 ASCII font, 8 planes of 256 bytes (plane n = pixel row n)
;;
;;  BIOS MODES (BiosMode, cycled by the MODE button in P3Isr: 0 -> 1 -> 2 -> 0)
;;    0 = file manager, 1 = game (run the mini-game in flash), 2 = clock
;;    The main menu (MainMenu) blinks the matching icon; pressing A enters it.
;;    Plugging into a controller (P7.0 = 5V detect) always drops into MapleMode.
;;
;;  CONVENTIONS USED BELOW
;;    Buttons_Current ($70) holds P3 inverted: 1 = pressed.
;;      bit0 Up  bit1 Down  bit2 Left  bit3 Right  bit4 A  bit5 B  bit6 MODE  bit7 SLEEP
;;    The WaitKeyEvent* family returns one of those button bits in ACC, or:
;;      $FF  controller plugged in (P7.0 high), caller must bail to the main menu
;;      $FE  SLEEP pressed in a context that wants to handle sleep itself
;;      $FD  BiosMode changed (MODE pressed), caller must bail to the main menu
;;      $FC  another VMU is plugged into the top connector -> start copy receive
;;    Text cursor: CursorX ($60) / CursorY ($61). Small text is 8 columns x 4 rows of
;;    6x8 cells, big glyphs are 6 columns x 4 rows of 8x8 cells. TextInvert ($67) = $FF
;;    draws inverse video.
;;    Flash addresses are 17 bits: FPR.0 (or FmBank/FlashBankTemp) is A16, TRH:TRL A15-A0.
;;    A filesystem block is 512 bytes; block n lives at flash address n * $200.
;;
;;  FLASH FILESYSTEM (as the BIOS uses it)
;;    Root block 255 ($1FE00): $00-$0F all $55 = formatted, $44 root loc, $46 FAT loc (254),
;;    $4A directory loc (253), $4C directory size (13). FAT: 16-bit LE per block,
;;    $FFFC = free, $FFFA = end of chain. Directory entries are 32 bytes:
;;    +$00 type ($00 none, $33 data, $CC game), +$01 copy protect ($FF), +$02 first block,
;;    +$04 name (12 chars), +$10 BCD timestamp (8), +$18 size in blocks, +$1A header offset.
;;
;;  RAM variables are named in the definitions at the end of this file. The BIOS keeps
;;  its own state in bank 0; bank 1 is the application's bank and is also used for the
;;  firmware-call parameters (FmBank/FmAddrHi/FmAddrLo at $7D-$7F, data buffer $80-$FF).
;; =============================================================================
;;
  ;; ========== INTERRUPT VECTOR TABLE ==========
  ;; Reset ISR
  .org 0
  jmp   ResetEntry

  .byte $FF

  ;; INT0 (external) ISR
  .org $0003
  jmp   IsrInt0

  .byte $FF, $FF, $FF, $FF, $FF, $FF

  ;; INT1 (external) ISR
  .org $000B
  jmp   IsrInt1

  .byte $FF, $FF, $FF, $FF, $FF, $FF

  ;; INT2 (external) OR Timer 0 T0L overflow ISR
  .org $0013
  jmp   IsrInt2Timer0Low

  .byte $FF, $FF, $FF, $FF, $FF, $FF

  ;; INT3 (external) OR Base Timer overflow ISR
  .org $001B
  callf BaseTimerIsr
  reti

  .byte $FF, $FF, $FF, $FF

  ;; Timer 0 T0H or T0H overflow ISR
  .org $0023
  jmp   IsrTimer0High

  .byte $FF, $FF, $FF, $FF, $FF, $FF

  ;; Timer 1 T1H or T1L overflow ISR
  .org $002B
  jmp   IsrTimer1

  .byte $FF, $FF, $FF, $FF, $FF, $FF

  ;; SIO0 (Serial Port 0) ISR
  .org $0033
  callf HandleIntSIO0
  reti

  .byte $FF, $FF, $FF, $FF

  ;; SIO1 (Serial Port 1) ISR
  .org $003B
  callf IsrSio1
  reti

  .byte $FF, $FF, $FF, $FF

 ;; Maple bus ISR (a Maple frame has arrived in work RAM)
  .org $0043
  callf MapleRxIsr
  reti

  .byte $FF, $FF, $FF, $FF

  ;; P3 ISR
  .org $004B
  callf P3Isr
  reti
;; ========== END INTERRUPT VECTOR TABLE ==========
;; -----------------------------------------------------------------------------
;; IsrInt0 ($004F)
;; External INT0: just acknowledge (clear I01CR.1). The BIOS doesn't use INT0.
;; -----------------------------------------------------------------------------
IsrInt0:
  clr1  i01cr, $01
  reti
;; -----------------------------------------------------------------------------
;; IsrInt1 ($0052)
;; External INT1: just acknowledge (clear I01CR.5).
;; -----------------------------------------------------------------------------
IsrInt1:
  clr1  i01cr, $05
  reti
;; -----------------------------------------------------------------------------
;; IsrInt2Timer0Low ($0055)
;; INT2 / Timer 0 low overflow: acknowledge both sources, nothing else.
;; -----------------------------------------------------------------------------
IsrInt2Timer0Low:
  clr1  t0con, $01
  clr1  i23cr, $05
  reti
;; -----------------------------------------------------------------------------
;; IsrTimer0High ($005A)
;; Timer 0 high overflow: acknowledge.
;; -----------------------------------------------------------------------------
IsrTimer0High:
  clr1  t0con, $03
  reti
;; -----------------------------------------------------------------------------
;; IsrTimer1 ($005D)
;; Timer 1 overflow: acknowledge both T1L and T1H flags. Timer 1 drives the buzzer
;; in PWM mode, so this only fires if someone enables its interrupt.
;; -----------------------------------------------------------------------------
IsrTimer1:
  clr1  t1cnt, $01
  clr1  t1cnt, $03
  reti

  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF

;; ========== PUBLIC FIRMWARE SUBROUTINES ==========
;; An application calls these with CALLF from its own code in flash. The BIOS
;; routine runs from ROM, then "not1 ext, $00" flips instruction fetches back to
;; flash and the JMPF lands on the same address in flash, where the application's
;; copy of this table continues (normally with a RET). TIMER_EX returns to $0139.
;; Parameters live in RAM bank 1: FmBank/FmAddrHi/FmAddrLo ($7D-$7F) and the
;; 128-byte buffer at $80-$FF.
  ;; FM_WRT_EX (Write to Flash Memory)
  .org $0100
  callf FmWrtExGuard
  not1  ext, $00
  jmpf  $0105

  ;; FM_WRTA_EX (Write to Flash Memory)
  .org $0108
  callf FmWrtExGuard
  not1  ext, $00
  jmpf  $010B

  ;; FM_VRF_EX (Flash Memory Verify)
  .org $0110
  callf FlashVerifyEntry
  not1  ext, $00
  jmpf  $0115

  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF

  ;; FM_PRD_EX (Flash Memory Page Data Readout)
  .org $0120
  callf FlashReadEntry
  not1  ext, $00
  jmpf  $0125

  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF

  ;; TIMER_EX (Base Timer/Clock 1/2 Second Clock Update)
  .org $0130
  callf BaseTimerIsr
  not1  ext, $00
  jmpf  $0139

  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF

  ;; SLEEP_EX (Sleep/CPU Halt)
  .org $0140
  callf SleepUntilWake
  not1  ext, $00
  jmpf  $0145

  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF

  ;; EXIT_EX (Mode Button)
  .org $01F0
  brf   ExitToBios

  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF

;; ========== END PUBLIC FIRMWARE SUBROUTINES ==========

;; -----------------------------------------------------------------------------
;; ResetEntry ($0200)
;; Cold/warm reset. Brings up the hardware, plays the start-up beep and then decides
;; whether RAM survives:
;;   - Buttons_Current must read $F0 (A+B+MODE+SLEEP held; the P3 interrupt records
;;     held buttons while StartupBeep waits)
;;     AND WarmBootMagic ($2C-$2F) must already hold "REST" -> keep RAM (clock keeps
;;     running), go straight to MaybeSetDefaultDate.
;;   - otherwise clear both RAM banks and write "REST" to WarmBootMagic.
;; Then reset the Maple hardware, and if the date was never set run the
;; SetClock procedure before entering MainMenu.
;; -----------------------------------------------------------------------------
ResetEntry:
  mov   #$A3, ocr                       ; OCR: 32kHz quartz, /6, RC + CF oscillators stopped
  mov   #$7F, sp        ; initialize stack pointer
  clr1  psw, rambk0     ; change to system RAM
  clr1  p3int, $00
  mov   #$FF, BatteryCheck              ; BatteryCheck = $FF: no low-battery check during boot
  mov   #$FF, TextInvert                ; TextInvert = $FF, so ClearScreenAndIcons lights every icon (lamp test)
  callf ClearScreenAndIcons
  callf HardwareInit
  callf StartupBeep
  ld    Buttons_Current                 ; warm-boot key combo held?
  be    #$F0, .warmCandidate
  br    .coldBoot
.warmCandidate:
  ; compare WarmBootMagic against "REST" stored in ROM at Str_RestMagic ($05C3)
  mov   #$04, b
  mov   #$00, acc
  mov   #WarmBootMagic, $00
.checkMagic:
  push  b
  push  acc
  ld    @R0
  inc   $00
  st    b
  pop   acc
  push  acc
  mov   #<Str_RestMagic, trl
  mov   #>Str_RestMagic, trh
  ldc
  sub   b
  bnz   .coldBoot
  pop   acc
  inc   acc
  pop   b
  dbnz  b, .checkMagic
  br    .ramReady
.coldBoot:
  mov   #$7F, sp
  mov   #$02, c
  clr1  psw, rambk0
  mov   #$00, acc
.clearBank:
  mov   #$00, $00
  mov   #$40, b
.clearLoop:
  st    @R0
  inc   $00
  st    @R0
  inc   $00
  st    @R0
  inc   $00
  st    @R0
  inc   $00
  dbnz  b, .clearLoop
  mov   #$00, $00
  set1  psw, rambk0                     ; second pass clears bank 1
  dbnz  c, .clearBank
  ; write "REST" into WarmBootMagic so the next reset is a warm one
  clr1  psw, rambk0
  mov   #WarmBootMagic, $00
  mov   #$00, acc
  mov   #$04, b
.writeMagic:
  push  acc
  mov   #<Str_RestMagic, trl
  mov   #>Str_RestMagic, trh
  ldc
  st    @R0
  pop   acc
  inc   $00
  inc   acc
  dbnz  b, .writeMagic
  clr1  psw, rambk0
.ramReady:
  mov   #$00, Buttons_Current
  mov   #$00, TextInvert
  callf MapleHwReset                    ; MapleHwReset
  callf MapleInitAddress                ; MapleInitAddress
  clr1  vsel, $00                       ; VSEL: work RAM owned by the CPU, auto-increment off
  clr1  vsel, $01
  clr1  mapletxrxctl, $02               ; Maple receive disabled until MapleMode
  mov   #$00, BatteryCheck              ; enable automatic low-battery check
  mov   #$00, BiosMode
  mov   #$00, SleepCtl
;; -----------------------------------------------------------------------------
;; MaybeSetDefaultDate ($02AF)
;; If the date was never set (DateSet == 0), load 2000-01-01 00:00:00 and ask the
;; user to set the clock. While plugged into a controller this is skipped and the
;; BIOS goes straight to MapleMode.
;; -----------------------------------------------------------------------------
MaybeSetDefaultDate:
  ld    DateSet
  bnz   MainMenu
  mov   #$00, $6C                       ; $6C is written here and never read anywhere else
  callf InitDefaultDateTime             ; InitDefaultDateTime
  ld    p7
  and   #$01                            ; P7.0: controller 5V present?
  bz    .standalone
  jmpf  MapleMode
.standalone:
  push  ocr
  mov   #$81, ocr                       ; OCR $81: RC oscillator so the XRAM icon writes work
  mov   #$02, xbnk                      ; XBNK 2 = icon area: show only the clock icon
  mov   #$00, xram_0181
  mov   #$00, xram_0182
  mov   #$04, xram_0183
  mov   #$00, xram_0184
  mov   #$00, xbnk
  pop   ocr
  mov   #$40, SleepCtl                  ; SleepCtl $40: sleep button ignored while setting the clock
  callf SetClockProcedure               ; SetClockProcedure; ACC != 0 if aborted (controller plugged in)
  bnz   MainMenu
  mov   #$FF, DateSet                   ; remember that the date has been set
  mov   #$00, BatteryCheck
  mov   #$00, BiosMode
  mov   #$00, SleepCtl
;; -----------------------------------------------------------------------------
;; MainMenu ($02EF)
;; Main menu / mode select. Draws the "Visual Memory Unit" banner, then idles in HALT,
;; waking on every interrupt. MODE (handled in P3Isr) cycles BiosMode 0/1/2 and the
;; matching icon blinks on every half-second tick; A enters the selected mode.
;; Re-entered from almost everywhere when a mode exits, so it re-validates
;; everything: controller plugged in -> MapleMode, date not set -> MaybeSetDefaultDate.
;; -----------------------------------------------------------------------------
MainMenu:
  clr1  psw, rambk0    ; BIOS RAM
  clr1  p3int, $00     ; P3 interrupts off
  ld    p7             ; get port 7 and isolate the 5V detect pin
  and   #$01
  bnz   .toMaple                        ; controller plugged in -> MapleMode
  ld    DateSet
  bz    MaybeSetDefaultDate             ; date never set -> back to the set-clock flow
  callf ClearScreenAndIcons
  mov   #<Str_VmuBanner, trl            ; Str_VmuBanner ($05C7)
  mov   #>Str_VmuBanner, trh
  mov   #$00, CursorX
  mov   #$00, CursorY
  callf DrawString
  set1  p3int, $00                      ; enable button interrupts
  mov   #$01, IdleTicks                 ; IdleTicks = 1: restart the auto-sleep timeout
  mov   #$00, HalfSecTicks
.idle:
  set1  pcon, $00                       ; HALT until the next interrupt (base timer, buttons, Maple)
  ld    p7
  and   #$01
  bnz   .toMaple
  ld    IdleTicks                       ; IdleTicks wrapped to 0 (~2 minutes idle) -> sleep
  bz    .sleep
  ld    SleepCtl                        ; SLEEP pressed -> sleep
  bnz   .sleep
  ld    BiosMode
  bz    .fileSelected
  be    #$01, .gameSelected
  be    #$02, .clockSelected
  br    .idle
.sleep:
  call  SleepUntilWake
  br    .idle

.toMaple:
  jmpf  MapleMode

.fileSelected:
  ld    Buttons_Current                 ; A pressed?
  and   #$10
  bnz   .toFileManager
  ld    HalfSecTicks                    ; half-second tick?
  bz    .idle
  mov   #$00, HalfSecTicks
  push  ocr
  mov   #$81, ocr
  mov   #$02, xbnk
  not1  xram_0181, $06                  ; blink the file icon
  mov   #$00, xram_0182
  mov   #$00, xram_0183
  mov   #$00, xbnk
  pop   ocr
  br    .idle
.toFileManager:
  jmp   EnterFileManager
.gameSelected:
  ld    Buttons_Current
  and   #$10
  bnz   .toGame
  ld    HalfSecTicks
  bz    .idle
  mov   #$00, HalfSecTicks
  push  ocr
  mov   #$81, ocr
  mov   #$02, xbnk
  not1  xram_0182, $04                  ; blink the game icon
  mov   #$00, xram_0181
  mov   #$00, xram_0183
  mov   #$00, xbnk
  pop   ocr
  br    .idle
.toGame:
  jmpf  GameModeLaunch
.clockSelected:
  ld    Buttons_Current
  and   #$10
  bnz   .toClock
  ld    HalfSecTicks
  bz    .idle
  mov   #$00, HalfSecTicks
  push  ocr
  mov   #$81, ocr
  mov   #$02, xbnk
  not1  xram_0183, $02                  ; blink the clock icon
  mov   #$00, xram_0181
  mov   #$00, xram_0182
  mov   #$02, xbnk                      ; BIOS bug: leaves XBNK at 2 here (the other two modes restore 0)
  pop   ocr
  jmp   .idle
.toClock:
  jmpf  ClockMode
;; -----------------------------------------------------------------------------
;; EnterFileManager ($03AE)
;; A pressed with the file icon selected: light the file icon, check that the root
;; block starts with 16 x $55 (formatted) and hand over to FileManager. Otherwise
;; show "Format memory" until the mode changes or the controller is plugged in.
;; The BIOS has no formatter, the Dreamcast does that.
;; -----------------------------------------------------------------------------
EnterFileManager:
  push  ocr
  mov   #$81, ocr
  mov   #$02, xbnk
  mov   #$40, xram_0181
  mov   #$00, xram_0182
  mov   #$00, xram_0183
  mov   #$00, xbnk
  pop   ocr
  mov   #$01, fpr                       ; FPR.0 = 1: root block lives in the upper 64K
  mov   #$01, FlashBankTemp
  mov   #$FE, trh
  mov   #$00, trl
  mov   #$10, b
.checkFormat:
  ldf
  xor   #$55
  bnz   .notFormatted
  dbnz  b, .checkFormat
  mov   #$00, CopyRxArm                 ; CopyRxArm = 0: don't offer VMU-to-VMU receive yet
  jmpf  FileManager
.notFormatted:
  clr1  p3int, $00
  callf ClearScreen
  mov   #<Str_FormatMemory, trl         ; Str_FormatMemory
  mov   #>Str_FormatMemory, trh
  mov   #$00, CursorX
  mov   #$00, CursorY
  callf DrawString
  set1  p3int, $00
  mov   #$01, IdleTicks
.waitLoop:
  callf WaitKeyEvent
  be    #$FF, .exit
  be    #$FD, .exit
  be    #$FE, .sleep
  br    .waitLoop
.exit:
  jmp   MainMenu
.sleep:
  call  SleepUntilWake
  br    .waitLoop

Str_FormatMemory:
  .byte $46, $6F, $72, $6D, $61, $74, $20, $20, $0D, $0A, $20, $20, $6D, $65, $6D, $6F
  .byte $72, $79, $00

;; -----------------------------------------------------------------------------
;; SleepUntilWake ($0421)
;; SLEEP_EX ($0140) lands here too. Turns the LCD off (VCCR/MCR = 0), waits for all
;; buttons to be released, then HALTs until SLEEP is pressed again. Preserves
;; BiosMode and BatteryCheck. If the VMU gets plugged into a controller while asleep
;; it doesn't return: it resets SP and enters MapleMode.
;; -----------------------------------------------------------------------------
SleepUntilWake:
  push  acc
  push  psw
  clr1  psw, rambk0
  push  BiosMode
  push  BatteryCheck
  mov   #$FF, BatteryCheck              ; no battery nagging while asleep
  mov   #$00, vccr                      ; LCD off
  mov   #$00, mcr
  callf WaitAllButtonsReleased          ; WaitAllButtonsReleased
  set1  p3int, $00
.halt:
  set1  pcon, $00
  ld    p7
  and   #$01
  bnz   .pluggedIn
  ld    Buttons_Current                 ; SLEEP pressed again?
  and   #$80
  bz    .halt
  mov   #$09, mcr                       ; LCD back on
  mov   #$80, vccr
  mov   #$00, SleepCtl                  ; clear the sleep request, restart idle timeout
  mov   #$01, IdleTicks
  pop   BatteryCheck
  pop   BiosMode
  pop   psw
  pop   acc
  ret
.pluggedIn:
  mov   #$09, mcr
  mov   #$80, vccr
  mov   #$00, SleepCtl
  mov   #$00, BiosMode
  mov   #$FF, BatteryCheck
  clr1  psw, rambk0
  mov   #$7F, sp
  jmpf  MapleMode

;; -----------------------------------------------------------------------------
;; FontGlyphs8x8 ($0473)
;; 8x8 glyphs used by DrawGlyph8x8 (8 bytes each, MSB = leftmost pixel):
;;   $00-$09 '0'-'9'   $0A ':'   $0B down-triangle   $0C up-triangle
;;   $0D-$0F '/' (three copies)   $10-$29 'A'-'Z'
;; -----------------------------------------------------------------------------
FontGlyphs8x8:
  .byte $7C, $C6, $C6, $C6, $C6, $C6, $7C, $00, $18, $38, $18, $18, $18, $18, $3C, $00
  .byte $7C, $C6, $C6, $1C, $70, $C0, $FE, $00, $7C, $C6, $C6, $1C, $C6, $C6, $7C, $00
  .byte $C0, $D8, $D8, $D8, $FE, $18, $3C, $00, $FE, $C0, $FC, $06, $C6, $C6, $7C, $00
  .byte $7C, $C6, $C0, $FC, $C6, $C6, $7C, $00, $7E, $C6, $C6, $06, $06, $06, $06, $00
  .byte $7C, $C6, $C6, $7C, $C6, $C6, $7C, $00, $7C, $C6, $C6, $7E, $06, $C6, $7C, $00
  .byte $00, $30, $30, $00, $30, $30, $00, $00, $00, $FE, $7C, $38, $10, $00, $00, $00
  .byte $00, $00, $10, $38, $7C, $FE, $00, $00, $02, $04, $08, $10, $20, $40, $80, $00
  .byte $02, $04, $08, $10, $20, $40, $80, $00, $02, $04, $08, $10, $20, $40, $80, $00
  .byte $38, $6C, $C6, $C6, $FE, $C6, $C6, $00, $FC, $C6, $C6, $FC, $C6, $C6, $FC, $00
  .byte $7C, $C6, $C6, $C0, $C6, $C6, $7C, $00, $FC, $C6, $C6, $C6, $C6, $C6, $FC, $00
  .byte $FC, $C0, $C0, $F8, $C0, $C0, $FC, $00, $FC, $C0, $C0, $F8, $C0, $C0, $C0, $00
  .byte $7C, $C6, $C6, $C0, $DE, $C6, $7E, $00, $C6, $C6, $C6, $FE, $C6, $C6, $C6, $00
  .byte $78, $30, $30, $30, $30, $30, $78, $00, $06, $06, $06, $06, $66, $66, $3C, $00
  .byte $CC, $CC, $D8, $F0, $D8, $CC, $CC, $00, $C0, $C0, $C0, $C0, $C0, $C0, $FC, $00
  .byte $C6, $EE, $FE, $D6, $C6, $C6, $C6, $00, $C6, $E6, $F6, $DE, $CE, $C6, $C6, $00
  .byte $38, $6C, $C6, $C6, $C6, $6C, $38, $00, $FC, $C6, $C6, $FC, $C0, $C0, $C0, $00
  .byte $38, $6C, $C6, $C6, $D6, $6C, $36, $00, $FC, $C6, $C6, $FC, $C6, $C6, $C6, $00
  .byte $7C, $C6, $C0, $7C, $06, $C6, $7C, $00, $7E, $18, $18, $18, $18, $18, $18, $00
  .byte $C6, $C6, $C6, $C6, $C6, $C6, $7C, $00, $C6, $C6, $C6, $6C, $6C, $38, $10, $00
  .byte $C6, $C6, $D6, $D6, $FE, $EE, $C6, $00, $C6, $C6, $6C, $38, $6C, $C6, $C6, $00
  .byte $CC, $CC, $CC, $78, $30, $30, $30, $00, $FE, $06, $0C, $38, $60, $C0, $FE, $00
;; -----------------------------------------------------------------------------
;; Str_RestMagic ($05C3)
;; "REST" (warm-boot magic). Str_VmuBanner starts right after it; bytes $17-$1A
;; are the bold "SEGA" logo characters of the 6x8 font.
;; -----------------------------------------------------------------------------
Str_RestMagic:
  .byte $52, $45, $53, $54
Str_VmuBanner:
  .byte $20, $20, $17, $18, $19, $1A, $0D, $0A, $20, $56, $69, $73
  .byte $75, $61, $6C, $0D, $0A, $20, $4D, $65, $6D, $6F, $72, $79, $0D, $0A, $20, $20
  .byte $55, $6E, $69, $74, $00

; ===== MAPLE FRAME RX ENTRY POINT ======
;; -----------------------------------------------------------------------------
;; MapleRxIsr ($05E8)
;; Maple bus interrupt: a complete frame from the Dreamcast is sitting in the
;; 512-byte work RAM (read through VRMAD/VTRBF). The frame header word is stored
;; byte-reversed: WRAM+3 = command, +2 = recipient address, +1 = sender address,
;; +0 = payload length in 32-bit words. Payload words follow from WRAM+4.
;;
;; Until we know our own address (MapleAddrState == 0) only a Device Request (1)
;; addressed to our port/slot is accepted; that latches MapleMyAddr. After a Device
;; Kill (4) MapleAddrState is $55 and every frame is ignored.
;; Function codes handled (MapleFuncType, see MapleParseFunctionCode):
;;   $02 storage (flash), $04 LCD, $08 clock (timer, buttons, buzzer).
;; Commands:
;;   $01 device request       -> MapleCmdDeviceInfo   (reply $05)
;;   $02 all status request   -> MapleCmdAllStatus    (reply $06)
;;   $03 device reset         -> MapleCmdReset        (reply $07)
;;   $04 device kill          -> MapleCmdKill         (reply $07)
;;   $09 get condition        -> clock: MapleClockGetCondition (buttons)
;;   $0A get media info       -> storage/LCD media info
;;   $0B block read           -> storage: MapleStorageBlockRead, clock: MapleClockBlockRead
;;   $0C block write          -> storage/LCD/clock block write
;;   $0D get last error       -> MapleStorageGetLastError (end of a block write)
;;   $0E set condition        -> clock: MapleClockSetCondition (buzzer)
;;   $FC resend request       -> MapleResendLastReply
;; Anything else gets $FD (unknown command); unsupported functions get $FE;
;; malformed frames (bad length) get $FC (please resend).
;; -----------------------------------------------------------------------------
MapleRxIsr:
  clr1  vsel, $00                       ; hand work RAM to the CPU
  push  acc
  push  b
  push  c
  push  $00
  push  $01
  push  $02
  push  $03
  ld    maplesta                        ; MAPLESTA error bits (5, 4, 1) set?
  and   #$76
  st    b
  bp    acc, $05, .frameError
  bp    acc, $04, .frameError
  bp    acc, $01, .frameError
  ld    MapleAddrState                  ; do we know our address yet?
  bnz   .addressKnown
  mov   #$03, vrmad1                    ; WRAM+3: command
  clr1  vrmad2, $00
  ld    vtrbf
  be    #$01, .checkRecipient
  jmp   .done
.checkRecipient:
  mov   #$02, vrmad1                    ; WRAM+2: recipient address
  ld    vtrbf
  st    c
  and   #$3F
  sub   MapleMyAddr                     ; our port/slot bits?
  bz    .latchAddress
  jmp   .done
.latchAddress:
  ld    c                               ; latch recipient address (with the port bits) as ours
  st    MapleMyAddr
  mov   #$FF, MapleAddrState
  jmp   .dispatch
.frameError:
  ld    MapleAddrState
  bnz   .frameErrorForUs
  jmp   .done
.frameErrorForUs:
  call  MapleCheckRecipient
  bz    .replyResend
  jmp   .done
.replyResend:
  call  MapleReplyResend
  jmp   .done
.addressKnown:
  ld    MapleAddrState
  bne   #$55, .dispatch                 ; $55 = killed (device kill): ignore everything
  jmp   .done
.dispatch:
  call  MapleCheckRecipient
  bz    .addressedToUs
  jmp   .done
.addressedToUs:
  mov   #$03, vrmad1
  clr1  vrmad2, $00
  ld    vtrbf
  bne   #$01, .cmd2
  mov   #$00, vrmad1                    ; WRAM+0: payload length must be 0
  clr1  vrmad2, $00
  ld    vtrbf
  bnz   .badLength1
  mov   #$01, MapleLastCmd
  call  MapleCmdDeviceInfo
  jmp   .done
.badLength1:
  call  MapleReplyResend
  jmp   .done
.cmd2:
  bne   #$02, .cmd3
  mov   #$00, vrmad1
  clr1  vrmad2, $00
  ld    vtrbf
  bnz   .badLength2
  mov   #$02, MapleLastCmd
  call  MapleCmdAllStatus
  jmp   .done
.badLength2:
  call  MapleReplyResend
  jmp   .done
.cmd3:
  bne   #$03, .cmd4
  mov   #$00, vrmad1
  clr1  vrmad2, $00
  ld    vtrbf
  bnz   .badLength3
  mov   #$FF, MapleLastCmd
  call  MapleCmdReset
  jmp   .done
.badLength3:
  call  MapleReplyResend
  jmp   .done
.cmd4:
  bne   #$04, .cmdA
  mov   #$00, vrmad1
  clr1  vrmad2, $00
  ld    vtrbf
  bnz   .badLength4
  mov   #$FF, MapleLastCmd
  call  MapleCmdKill
  jmp   .done
.badLength4:
  call  MapleReplyResend
  jmp   .done
.cmdA:
  bne   #$0A, .cmdB
  mov   #$00, vrmad1
  clr1  vrmad2, $00
  ld    vtrbf
  bne   #$02, .badLengthA               ; 2 words: function code + partition
  mov   #$0A, MapleLastCmd
  call  MapleParseFunctionCode
  ld    MapleFuncType
  be    #$02, .mediaInfoStorage
  be    #$04, .mediaInfoLcd
  jmp   .unsupportedFunction
.mediaInfoStorage:
  call  MapleStorageGetMediaInfo
  jmp   .done
.mediaInfoLcd:
  call  MapleLcdGetMediaInfo
  jmp   .done
.badLengthA:
  call  MapleReplyResend
  jmp   .done
.cmdB:
  bne   #$0B, .cmdC
  mov   #$00, vrmad1
  clr1  vrmad2, $00
  ld    vtrbf
  bne   #$02, .badLengthB
  mov   #$0B, MapleLastCmd
  call  MapleParseFunctionCode
  ld    MapleFuncType
  be    #$02, .blockReadStorage
  be    #$08, .blockReadClock
  jmp   .unsupportedFunction
.blockReadClock:
  call  MapleClockBlockRead
  jmp   .done
.blockReadStorage:
  mov   #$00, vrmad1
  clr1  vrmad2, $00
  set1  psw, rambk0
  mov   #$70, $00
  ld    vtrbf
  st    @R0
  inc   $00
  mov   #$04, vrmad1
  mov   #$02, b
.copyLocation:
  ld    vtrbf
  st    @R0
  inc   $00
  ld    vtrbf
  st    @R0
  inc   $00
  ld    vtrbf
  st    @R0
  inc   $00
  ld    vtrbf
  st    @R0
  inc   $00
  dbnz  b, .copyLocation
  clr1  psw, rambk0
  mov   #$00, MapleExpectedPhase
  mov   #$00, MapleStorageErr
  call  MapleBlockToFlashAddr
  call  MapleStorageBlockRead
  jmp   .done
.badLengthB:
  call  MapleReplyResend
  jmp   .done
.cmdC:
  bne   #$0C, .cmdD
  mov   #$0C, MapleLastCmd
  call  MapleParseFunctionCode
  ld    MapleFuncType
  be    #$04, .blockWriteLcd
  be    #$08, .blockWriteClock
  bne   #$02, .unsupportedC
  call  MapleStorageBlockWrite
  jmp   .done
.blockWriteLcd:
  call  MapleLcdBlockWrite
  jmp   .done
.blockWriteClock:
  call  MapleClockBlockWrite
  jmp   .done
.unsupportedC:
  jmp   .unsupportedFunction
.cmdD:
  bne   #$0D, .cmdFC
  mov   #$00, vrmad1
  clr1  vrmad2, $00
  ld    vtrbf
  be    #$02, .getLastError
  call  MapleReplyResend
  jmp   .done
.getLastError:
  mov   #$0D, MapleLastCmd
  call  MapleParseFunctionCode
  ld    MapleFuncType
  bne   #$02, .unsupportedD
  mov   #$0A, vrmad1                    ; WRAM+$0A: phase of the write being finished
  clr1  vrmad2, $00
  ld    vtrbf
  sub   MapleExpectedPhase
  bz    .phaseOk
  set1  MapleStorageErr, $01
.phaseOk:
  mov   #$00, MapleExpectedPhase
  call  MapleStorageGetLastError
  jmp   .done
.unsupportedD:
  jmp   .unsupportedFunction
.cmdFC:
  bne   #$FC, .cmd9
  call  MapleResendLastReply
  jmp   .done
.cmd9:
  bne   #$09, .cmdE
  mov   #$09, MapleLastCmd
  mov   #$00, vrmad1
  clr1  vrmad2, $00
  ld    vtrbf
  bne   #$01, .badLength9
  call  MapleParseFunctionCode
  ld    MapleFuncType
  bne   #$08, .unsupported9
  call  MapleClockGetCondition
  jmp   .done
.badLength9:
  call  MapleReplyResend
  jmp   .done
.unsupported9:
  jmp   .unsupportedFunction
.cmdE:
  bne   #$0E, .unknownCommand
  mov   #$0E, MapleLastCmd
  mov   #$00, vrmad1
  clr1  vrmad2, $00
  ld    vtrbf
  bne   #$02, .badLengthE
  call  MapleParseFunctionCode
  ld    MapleFuncType
  bne   #$08, .unsupportedE
  call  MapleClockSetCondition  ; Play maple buzzer
  jmp   .done
.badLengthE:
  call  MapleReplyResend
  jmp   .done
.unsupportedE:
  jmp   .unsupportedFunction
.unknownCommand:
  call  MapleReplyUnknownCommand
  jmp   .done
.unsupportedFunction:
  call  MapleReplyFunctionUnsupported
  jmp   .done
.done:
  clr1  maplesta, $02                   ; acknowledge the frame
  pop   $03
  pop   $02
  pop   $01
  pop   $00
  pop   c
  pop   b
  pop   acc
  set1  vsel, $00                       ; give work RAM back to the Maple hardware
  ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; -----------------------------------------------------------------------------
;; MapleCheckRecipient ($07EB)
;; Out: ACC = MapleMyAddr - recipient (0 if the frame is for us), B = recipient.
;; Also latches the sender into MapleHostAddr for the reply.
;; -----------------------------------------------------------------------------
MapleCheckRecipient:
  mov   #$02, vrmad1
  clr1  vrmad2, $00
  ld    vtrbf
  st    b
  mov   #$01, vrmad1
  ld    vtrbf
  st    MapleHostAddr
  ld    MapleMyAddr
  sub   b
  ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; -----------------------------------------------------------------------------
;; MapleReplyResend ($0800)
;; Reply with command $FC ("request resend"), no payload. Used for malformed frames.
;; -----------------------------------------------------------------------------
MapleReplyResend:
  call  MapleBeginReply
  mov   #$00, vtrbf
  ld    MapleMyAddr
  st    vtrbf
  ld    MapleHostAddr
  st    vtrbf
  mov   #$FC, vtrbf
  mov   #$FC, MapleLastCmd
  mov   #$00, vlreg
  set1  vsel, $00
  set1  mapletxrxctl, $04
  set1  mapletxrxctl, $00
  ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; -----------------------------------------------------------------------------
;; MapleBeginReply ($081D)
;; Point work RAM at $100 (the transmit half) with the CPU owning it, ready to write
;; a reply header with successive VTRBF stores.
;; -----------------------------------------------------------------------------
MapleBeginReply:
  clr1  vsel, $00          ; WRAM is set to be accessed by CPU
  clr1  mapletxrxctl, $04               ; MAPLETXRXCTL.4 off while building the reply
  mov   #$00, vrmad1                    ; VRMAD = $100
  set1  vrmad2, $00
  ret

;; -----------------------------------------------------------------------------
;; MapleParseFunctionCode ($0827)
;; Decode the first payload word (function code, WRAM+4..7) into MapleFuncType:
;; $02 storage, $04 LCD, $08 clock, $FF anything else (or more than one bit set).
;; -----------------------------------------------------------------------------
MapleParseFunctionCode:
  mov   #$05, vrmad1
  clr1  vrmad2, $00
  ld    vtrbf
  bnz   .unsupported
  ld    vtrbf
  bnz   .unsupported
  ld    vtrbf
  bnz   .unsupported
  mov   #$04, vrmad1
  ld    vtrbf
  be    #$04, .lcd
  be    #$08, .clock
  bne   #$02, .unsupported
  mov   #$02, MapleFuncType
  br    .return
.lcd:
  mov   #$04, MapleFuncType
  br    .return
.clock:
  mov   #$08, MapleFuncType
.return:
  ret
.unsupported:
  mov   #$FF, MapleFuncType
  ret
;; -----------------------------------------------------------------------------
;; MapleBlockToFlashAddr ($0858)
;; Validate the storage location word copied to bank 1 ($75 block lo, $76 block hi,
;; $77 phase, $78 partition) and turn it into firmware-call parameters
;; FmBank/FmAddrHi/FmAddrLo = block * 512 + phase * 128.
;; Errors are OR'ed into MapleStorageErr: bit0 partition != 0, bit1 phase != expected
;; (MapleExpectedPhase is then set to $FF), bit2 block > 255. Also sets FlashWaitMode = 1.
;; -----------------------------------------------------------------------------
MapleBlockToFlashAddr:
  set1  psw, rambk0
  mov   #$78, $00
  ld    @R0
  bz    .checkPhase
  clr1  psw, rambk0
  set1  MapleStorageErr, $00
.checkPhase:
  clr1  psw, rambk0
  ld    MapleExpectedPhase              ; expected phase
  set1  psw, rambk0
  dec   $00
  sub   @R0
  bz    .checkBlockHi
  clr1  psw, rambk0
  set1  MapleStorageErr, $01
  mov   #$FE, MapleExpectedPhase
.checkBlockHi:
  clr1  psw, rambk0
  inc   MapleExpectedPhase
  set1  psw, rambk0
  dec   $00
  ld    @R0                             ; block number high byte
  bz    .computeAddress
  clr1  psw, rambk0
  set1  MapleStorageErr, $02
  set1  psw, rambk0
.computeAddress:
  clr1  psw, rambk0
  ld    MapleStorageErr
  bnz   .return
  set1  psw, rambk0
  dec   $00
  ld    @R0                             ; block number low byte
  clr1  psw, cy
  rolc
  rolc
  st    b
  and   #$01
  st    FmBank
  ld    b
  and   #$FC
  mov   #$77, $00
  or    @R0
  st    c
  and   #$00
  rolc
  mov   #$80, b                         ; (bit 6 of block : block<<2 | phase) * $80
  mul
  st    FmAddrHi
  ld    c
  st    FmAddrLo
  mov   #$01, FlashWaitMode             ; FM_WRT completion: DQ7 data polling
  clr1  psw, rambk0
.return:
  ret
;; -----------------------------------------------------------------------------
;; MapleCmdDeviceInfo ($08B9)
;; Device Request -> reply $05 "device status", 28 words copied from MapleDeviceInfo:
;; function codes, function definition words, area, connector direction, product
;; name, license string, power figures.
;; -----------------------------------------------------------------------------
MapleCmdDeviceInfo:
  call  MapleBeginReply
  mov   #$00, MapleExpectedPhase
  mov   #$1C, vtrbf                     ; length $1C words
  ld    MapleMyAddr
  st    vtrbf
  ld    MapleHostAddr
  st    vtrbf
  mov   #$05, vtrbf                     ; command $05
  mov   #<MapleDeviceInfo, trl
  mov   #>MapleDeviceInfo, trh
  mov   #$00, acc
  mov   #$03, vlreg
  mov   #$03, b
  call  MapleTxRomWords                 ; first 3 words, then 6 x 4, then 1
  set1  vsel, $00
  set1  mapletxrxctl, $00
  call  MapleWaitTxReady
  mov   #$06, c
.sendChunk:
  clr1  vsel, $00
  mov   #$00, vrmad1
  mov   #$04, b
  call  MapleTxRomWords
  set1  vsel, $00
  set1  mapletxrxctl, $01
  call  MapleWaitTxReady
  dbnz  c, .sendChunk
  clr1  vsel, $00
  mov   #$00, vrmad1
  mov   #$00, vlreg
  mov   #$01, b
  call  MapleTxRomWords
  set1  vsel, $00
  set1  mapletxrxctl, $04
  set1  mapletxrxctl, $01
  call  MapleWaitTxReady
  ret
;; -----------------------------------------------------------------------------
;; MapleCmdAllStatus ($090F)
;; All Status Request -> reply $06, 48 words: the 28 device-info words followed by the
;; BIOS version string ("Version 1.005,1999/10/26,315-6208-05,...").
;; -----------------------------------------------------------------------------
MapleCmdAllStatus:
  call  MapleBeginReply
  mov   #$00, MapleExpectedPhase
  mov   #$30, vtrbf
  ld    MapleMyAddr
  st    vtrbf
  ld    MapleHostAddr
  st    vtrbf
  mov   #$06, vtrbf
  mov   #<MapleDeviceInfo, trl
  mov   #>MapleDeviceInfo, trh
  mov   #$00, acc
  mov   #$03, vlreg
  mov   #$03, b
  call  MapleTxRomWords
  set1  vsel, $00
  set1  mapletxrxctl, $00
  call  MapleWaitTxReady
  mov   #$0B, c
.sendChunk:
  clr1  vsel, $00
  mov   #$00, vrmad1
  mov   #$04, b
  call  MapleTxRomWords
  set1  vsel, $00
  set1  mapletxrxctl, $01
  call  MapleWaitTxReady
  dbnz  c, .sendChunk
  clr1  vsel, $00
  mov   #$00, vrmad1
  mov   #$01, b
  call  MapleTxRomWords
  set1  vsel, $00
  set1  mapletxrxctl, $04
  set1  mapletxrxctl, $01
  call  MapleWaitTxReady
  ret
;; -----------------------------------------------------------------------------
;; MapleCmdReset ($0962)
;; Device Reset: ack, re-derive our address from the P7 ID pins and clear the screen.
;; -----------------------------------------------------------------------------
MapleCmdReset:
  call  MapleBeginReply
  mov   #$00, MapleExpectedPhase
  call  MapleReplyAck
  callf MapleInitAddress
  callf ClearScreen
  ret
;; -----------------------------------------------------------------------------
;; MapleCmdKill ($0970)
;; Device Kill: ack and stop answering (MapleAddrState = $55).
;; -----------------------------------------------------------------------------
MapleCmdKill:
  call  MapleBeginReply
  mov   #$00, MapleExpectedPhase
  call  MapleReplyAck
  mov   #$55, MapleAddrState
  ret
;; -----------------------------------------------------------------------------
;; MapleReplyUnknownCommand ($097B)
;; Reply $FD (unknown command), no payload.
;; -----------------------------------------------------------------------------
MapleReplyUnknownCommand:
  call  MapleBeginReply
  mov   #$00, MapleExpectedPhase
  mov   #$00, vtrbf
  ld    MapleMyAddr
  st    vtrbf
  ld    MapleHostAddr
  st    vtrbf
  mov   #$FD, vtrbf
  mov   #$FD, MapleLastCmd
  mov   #$00, vlreg
  set1  vsel, $00
  set1  mapletxrxctl, $04
  set1  mapletxrxctl, $00
  ret
;; -----------------------------------------------------------------------------
;; MapleReplyFunctionUnsupported ($099B)
;; Reply $FE (function code not supported), no payload.
;; -----------------------------------------------------------------------------
MapleReplyFunctionUnsupported:
  call  MapleBeginReply
  mov   #$00, MapleExpectedPhase
  mov   #$00, vtrbf
  ld    MapleMyAddr
  st    vtrbf
  ld    MapleHostAddr
  st    vtrbf
  mov   #$FE, vtrbf
  mov   #$FE, MapleLastCmd
  mov   #$00, vlreg
  set1  vsel, $00
  set1  mapletxrxctl, $04
  set1  mapletxrxctl, $00
  ret
;; -----------------------------------------------------------------------------
;; MapleStorageGetMediaInfo ($09BB)
;; Get Media Info for storage -> reply $08 with 7 words: the function code and 6 words
;; of volume layout. If the root block carries the $55 format marker, the layout
;; (FAT/directory location and size, icon shape, user blocks, ...) is read from root
;; block offsets $46-$57; otherwise the default layout at MapleStorageMediaInfo is sent.
;; -----------------------------------------------------------------------------
MapleStorageGetMediaInfo:
  call  MapleBeginReply
  mov   #$00, MapleExpectedPhase
  mov   #$07, vtrbf
  ld    MapleMyAddr
  st    vtrbf
  ld    MapleHostAddr
  st    vtrbf
  mov   #$08, vtrbf
  mov   #$07, vlreg
  mov   #$00, acc
  mov   #$01, fpr
  mov   #$01, FlashBankTemp
  mov   #$FE, trh
  mov   #$00, trl
  mov   #$10, b
.checkFormat:
  ldf                                   ; root block format marker
  bne   #$55, .unformatted
  dbnz  b, .checkFormat
  mov   #$03, vlreg
  mov   #<MapleStorageMediaInfo, trl
  mov   #>MapleStorageMediaInfo, trh
  mov   #$00, acc
  mov   #$02, b
  call  MapleTxRomWords
  mov   #$01, fpr
  mov   #$01, FlashBankTemp
  mov   #$FE, trh
  mov   #$47, trl                       ; root+$47/$46
  ldf
  st    vtrbf
  dec   trl
  ldf
  st    vtrbf
  mov   #$00, vtrbf
  mov   #$FF, vtrbf
  set1  vsel, $00
  set1  mapletxrxctl, $00
  call  MapleWaitTxReady
  mov   #$01, fpr
  mov   #$01, FlashBankTemp
  mov   #$FE, trh                       ; root+$48.. (16 bytes)
  mov   #$48, trl
  clr1  vsel, $00
  mov   #$00, vrmad1
  mov   #$04, b
  call  MapleTxFlashWords
  set1  vsel, $00
  set1  mapletxrxctl, $04
  set1  mapletxrxctl, $01
  ret
.unformatted:
  mov   #<MapleStorageMediaInfo, trl
  mov   #>MapleStorageMediaInfo, trh
  mov   #$00, acc
  mov   #$03, vlreg
  mov   #$03, b
  call  MapleTxRomWords
  set1  vsel, $00
  set1  mapletxrxctl, $00
  call  MapleWaitTxReady
  clr1  vsel, $00
  mov   #$00, vrmad1
  mov   #$03, vlreg
  mov   #$04, b
  call  MapleTxRomWords
  set1  vsel, $00
  set1  mapletxrxctl, $04
  set1  mapletxrxctl, $01
  call  MapleWaitTxReady
  clr1  vsel, $00
  mov   #$00, vrmad1
  ret
;; -----------------------------------------------------------------------------
;; MapleLcdGetMediaInfo ($0A6A)
;; Get Media Info for LCD -> reply $08: function code + MapleLcdMediaInfo
;; (48x32, 1 bpp, ...).
;; -----------------------------------------------------------------------------
MapleLcdGetMediaInfo:
  call  MapleBeginReply
  mov   #$00, MapleExpectedPhase
  mov   #$02, vtrbf
  ld    MapleMyAddr
  st    vtrbf
  ld    MapleHostAddr
  st    vtrbf
  mov   #$08, vtrbf
  mov   #$02, vlreg
  mov   #<MapleLcdMediaInfo, trl
  mov   #>MapleLcdMediaInfo, trh
  mov   #$00, acc
  mov   #$02, b
  call  MapleTxRomWords
  set1  vsel, $00
  set1  mapletxrxctl, $04
  set1  mapletxrxctl, $00
  ret

;; -----------------------------------------------------------------------------
;; MapleDeviceInfo ($0A95)
;; Maple device info (28 words, kept in Dreamcast word order; MapleTxRomWords reverses
;; each word for the wire): functions $0E (storage|LCD|clock), the three function definition
;; words, area code $FF, connector direction 0, then the 30-char product name and the
;; 60-char license string, then standby/max power.
;; -----------------------------------------------------------------------------
MapleDeviceInfo:
  .byte $00, $00, $00, $0E, $7E, $7E, $3F, $40, $00, $05, $10, $00, $00, $0F, $41, $00
  .byte $FF, $00
  .string 92 "Visual Memory                 Produced By or Under License From SEGA ENTERPRISES,LTD.     |"
  .byte $82, $00
Str_BiosVersion:
  .byte $56, $65, $72, $73, $69, $6F, $6E, $20, $31, $2E, $30, $30, $35, $2C, $31, $39
  .byte $39, $39, $2F, $31, $30, $2F, $32, $36, $2C, $33, $31, $35, $2D, $36, $32, $30
  .byte $38, $2D, $30, $35, $2C, $53, $45, $47, $41, $20, $56, $69, $73, $75, $61, $6C
  .byte $20, $4D, $65, $6D, $6F, $72, $79, $20, $53, $79, $73, $74, $65, $6D, $20, $42
  .byte $49, $4F, $53, $20, $50, $72, $6F, $64, $75, $63, $65, $64, $20, $62, $79, $20
  .byte $53, $75, $65, $20
MapleStorageMediaInfo:
  .byte $00, $00, $00, $02, $FF, $00, $00, $00, $FF, $00, $FE, $00
  .byte $01, $00, $FD, $00, $0D, $00, $00, $00, $C8, $00, $1F, $00, $00, $00, $80, $00
MapleLcdMediaInfo:
  .byte $00, $00, $00, $04, $2F, $1F, $10, $02

;; -----------------------------------------------------------------------------
;; MapleStorageBlockRead ($0B7D)
;; Block Read on storage -> reply $08 with $82 words: function code, location word,
;; then the 512-byte block straight out of flash (the flash access icon is lit
;; while it streams). Any location error (MapleStorageErr) -> MapleReplyFileError.
;; -----------------------------------------------------------------------------
MapleStorageBlockRead:
  ld    MapleStorageErr
  bnz   .error
  mov   #$00, MapleExpectedPhase
  call  MapleBeginReply
  mov   #$82, vtrbf                     ; length $82 words
  ld    MapleMyAddr
  st    vtrbf
  ld    MapleHostAddr
  st    vtrbf
  mov   #$08, vtrbf
  mov   #$02, vlreg
  set1  psw, rambk0
  mov   #$71, $00
  mov   #$02, b
  clr1  psw, rambk0
  call  MapleTxRamWords                 ; echo function code + location word from bank 1 $71..
  set1  vsel, $00
  set1  mapletxrxctl, $00
  call  MapleWaitTxReady
  set1  psw, rambk0
  ld    FmBank
  clr1  psw, rambk0
  st    fpr
  st    FlashBankTemp
  set1  psw, rambk0
  ld    FmAddrHi
  st    trh
  ld    FmAddrLo
  st    trl
  clr1  psw, rambk0
  mov   #$03, vlreg
  mov   #$1F, c                         ; 31 chunks of 16 bytes here, the 32nd below
  mov   #$02, xbnk
  mov   #$01, xram_0184                 ; flash access icon on
.sendChunk:
  clr1  vsel, $00
  mov   #$00, vrmad1
  mov   #$04, b
  call  MapleTxFlashWords
  ld    trl
  bnz   .noCarry
  inc   trh
.noCarry:
  set1  vsel, $00
  set1  mapletxrxctl, $01
  call  MapleWaitTxReady
  dbnz  c, .sendChunk
  clr1  vsel, $00
  mov   #$00, vrmad1
  mov   #$04, b
  call  MapleTxFlashWords
  set1  vsel, $00
  set1  mapletxrxctl, $04
  set1  mapletxrxctl, $01
  mov   #$00, xram_0184
  mov   #$00, xbnk
  ret
.error:
  call  MapleReplyFileError
  ret
;; -----------------------------------------------------------------------------
;; MapleClockBlockRead ($0BFE)
;; Block Read on the clock -> reply $08: function code + date/time word pair
;; (year, month, day, hour, minute, second, weekday = 0).
;; -----------------------------------------------------------------------------
MapleClockBlockRead:
  mov   #$08, vrmad1
  clr1  vrmad2, $00
  ld    vtrbf
  bnz   .badLocation
  ld    vtrbf
  bnz   .badLocation
  ld    vtrbf
  bnz   .badLocation
  ld    vtrbf
  bnz   .badLocation
  call  MapleBeginReply
  mov   #$03, vtrbf
  ld    MapleMyAddr
  st    vtrbf
  ld    MapleHostAddr
  st    vtrbf
  mov   #$08, vtrbf
  mov   #$03, vlreg
  mov   #$08, vtrbf
  mov   #$00, acc
  st    vtrbf
  st    vtrbf
  st    vtrbf
  ld    Day
  st    vtrbf
  ld    Month
  st    vtrbf
  ld    YearHi
  st    vtrbf
  ld    YearLo
  st    vtrbf
  mov   #$00, vtrbf
  ld    Second
  st    vtrbf
  ld    Minute
  st    vtrbf
  ld    Hour
  st    vtrbf
  set1  vsel, $00
  set1  mapletxrxctl, $04
  set1  mapletxrxctl, $00
  ret
.badLocation:
  call  MapleReplyResend
  ret
;; -----------------------------------------------------------------------------
;; MapleStorageBlockWrite ($0C5B)
;; Block Write on storage. A 512-byte block arrives as 4 frames of 128 bytes
;; (phase 0-3). Each frame is acked immediately, then written to flash with
;; FM_WRT + verify; errors accumulate in MapleStorageErr:
;;   bit2 block differs from phase 0's, bit4 wrong frame length, bit3 verify failed.
;; The Dreamcast finishes with Get Last Error (cmd $0D).
;; -----------------------------------------------------------------------------
MapleStorageBlockWrite:
  set1  psw, rambk0
  mov   #$00, vrmad1
  clr1  vrmad2, $00
  mov   #$70, $00                       ; bank 1 $70.. = length, function code, location
  mov   #$02, b
  ld    vtrbf
  st    @R0
  inc   $00
  mov   #$04, vrmad1
.copyHeader:
  ld    vtrbf
  st    @R0
  inc   $00
  ld    vtrbf
  st    @R0
  inc   $00
  ld    vtrbf
  st    @R0
  inc   $00
  ld    vtrbf
  st    @R0
  inc   $00
  dbnz  b, .copyHeader
  mov   #$80, $00                       ; bank 1 $80-$FF = the 128 data bytes
  mov   #$20, b
.copyData:
  ld    vtrbf
  st    @R0
  inc   $00
  ld    vtrbf
  st    @R0
  inc   $00
  ld    vtrbf
  st    @R0
  inc   $00
  ld    vtrbf
  st    @R0
  inc   $00
  dbnz  b, .copyData
  clr1  psw, rambk0
  call  MapleBeginReply
  call  MapleReplyAck
  mov   #$02, xbnk
  mov   #$01, xram_0184                 ; flash access icon on
  ld    MapleExpectedPhase              ; phase 0?
  bnz   .checkBlock
  set1  psw, rambk0
  ld    $75
  clr1  psw, rambk0
  st    MapleWriteBlock                 ; remember the block number for the next phases
  mov   #$00, MapleStorageErr
.checkBlock:
  set1  psw, rambk0
  ld    $75
  clr1  psw, rambk0
  sub   MapleWriteBlock
  bz    .checkLength
  set1  MapleStorageErr, $02
.checkLength:
  set1  psw, rambk0
  ld    $70
  clr1  psw, rambk0
  be    #$22, .write
  set1  MapleStorageErr, $04
.write:
  call  MapleBlockToFlashAddr
  ld    MapleStorageErr
  bnz   .return2
  set1  psw, rambk0
  mov   #$80, $00
  mov   #$20, c
  clr1  psw, rambk0
  call  ByteSwapWordsBank1              ; Maple words arrive byte-reversed
  set1  psw, rambk0
  clr1  ie, $07                         ; no interrupts while the flash is being programmed
  callf FlashWriteEntry                 ; FM_WRT (unlock + program 128 bytes)
  set1  ie, $07
  callf FlashVerifyEntry                ; FM_VRF
  ld    $00
  bz    .return
  clr1  psw, rambk0
  set1  MapleStorageErr, $03
  set1  psw, rambk0
.return:
  clr1  psw, rambk0
  ret
.return2:
  ret
;; -----------------------------------------------------------------------------
;; MapleLcdBlockWrite ($0D02)
;; Block Write on the LCD: a 48x32 1bpp image (48 words) is byte-swapped in bank 1
;; ($40-$FF) and copied into both XRAM banks. Errors (wrong length, nonzero
;; partition/phase/block) are collected in MapleLcdErr and answered with $FA.
;; -----------------------------------------------------------------------------
MapleLcdBlockWrite:
  mov   #$00, MapleLcdErr
  mov   #$00, vrmad1
  clr1  vrmad2, $00
  ld    vtrbf
  be    #$32, .checkPhase
  ld    MapleLcdErr
  or    #$10
  st    MapleLcdErr
.checkPhase:
  mov   #$0B, vrmad1
  ld    vtrbf
  bz    .checkPartition
  ld    MapleLcdErr
  or    #$01
  st    MapleLcdErr
.checkPartition:
  mov   #$0A, vrmad1
  ld    vtrbf
  bz    .checkBlock
  ld    MapleLcdErr
  or    #$02
  st    MapleLcdErr
.checkBlock:
  mov   #$08, vrmad1
  ld    vtrbf
  bnz   .badBlock
  ld    vtrbf
  bz    .checkErrors
.badBlock:
  ld    MapleLcdErr
  or    #$04
  st    MapleLcdErr
.checkErrors:
  ld    MapleLcdErr
  bz    .copyImage
  call  MapleReplyLcdError
  jmp   .return
.copyImage:
  set1  psw, rambk0
  mov   #$40, $00
  mov   #$0C, vrmad1
  mov   #$30, b
.copyLoop:
  ld    vtrbf
  st    @R0
  inc   $00
  ld    vtrbf
  st    @R0
  inc   $00
  ld    vtrbf
  st    @R0
  inc   $00
  ld    vtrbf
  st    @R0
  inc   $00
  dbnz  b, .copyLoop
  clr1  psw, rambk0
  call  MapleBeginReply
  call  MapleReplyAck
  set1  psw, rambk0
  mov   #$40, $00
  mov   #$30, c
  clr1  psw, rambk0
  call  ByteSwapWordsBank1
  set1  psw, rambk0
  mov   #$40, $00
  mov   #$00, xbnk
  mov   #$02, $01                       ; $01 counts the two XRAM banks
.xbank:
  mov   #$08, b
  mov   #$80, $02
.row:
  mov   #$03, c
.copy12:
  ld    @R0
  st    @R2
  inc   $00
  inc   $02
  ld    @R0
  st    @R2
  inc   $00
  inc   $02
  ld    @R0
  st    @R2
  inc   $00
  inc   $02
  ld    @R0
  st    @R2
  inc   $00
  inc   $02
  dbnz  c, .copy12
  ld    $02
  add   #$04
  st    $02
  dbnz  b, .row
  mov   #$01, xbnk
  dbnz  $01, .xbank
.return:
  clr1  psw, rambk0
  ret
;; -----------------------------------------------------------------------------
;; MapleClockBlockWrite ($0DBD)
;; Block Write on the clock (set date/time): takes year/month/day/hour/minute/second
;; from the payload, recomputes the leap-year flag and marks the date as set.
;; -----------------------------------------------------------------------------
MapleClockBlockWrite:
  mov   #$00, vrmad1
  clr1  vrmad2, $00
  ld    vtrbf
  bne   #$04, .badLocation
  mov   #$08, vrmad1
  ld    vtrbf
  bnz   .badLocation
  ld    vtrbf
  bnz   .badLocation
  ld    vtrbf
  bnz   .badLocation
  ld    vtrbf
  bnz   .badLocation
  ld    vtrbf
  st    Day
  ld    vtrbf
  st    Month
  ld    vtrbf
  st    YearHi
  ld    vtrbf
  st    YearLo
  ld    vtrbf
  ld    vtrbf
  st    Second
  ld    vtrbf
  st    Minute
  ld    vtrbf
  st    Hour
  call  MapleBeginReply
  call  MapleReplyAck
  callf UpdateLeapYearEntry             ; UpdateLeapYear
  clr1  psw, rambk0
  mov   #$FF, DateSet
  ret
.badLocation:
  call  MapleReplyResend
  ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; -----------------------------------------------------------------------------
;; MapleClockGetCondition ($0E08)
;; Get Condition on the clock: reply with the raw button state (P3, active low),
;; MODE and SLEEP masked off so the DC only sees the d-pad and A/B.
;; -----------------------------------------------------------------------------
MapleClockGetCondition:
  call  MapleBeginReply     ; set WRAM to reply mode
  mov   #$02, vtrbf                     ; length: 2 words
  ld    MapleMyAddr                     ; sender: us
  st    vtrbf          ; $08, $00, $00, $00
  ld    MapleHostAddr                   ; recipient: the host
  st    vtrbf
  mov   #$08, vtrbf                     ; command $08: data transfer
  mov   #$02, vlreg
  mov   #$08, vtrbf                     ; function code $00000008 (clock), stored byte-reversed
  mov   #$00, acc
  st    vtrbf
  st    vtrbf
  st    vtrbf
  st    vtrbf
  st    vtrbf
  st    vtrbf
  ld    p3                              ; raw P3, active low
  or    #$C0                            ; MODE and SLEEP always read as released
  st    vtrbf
  set1  vsel, $00                       ; hand work RAM back to the Maple hardware
  set1  mapletxrxctl, $04               ; MAPLETXRXCTL.4 + .0: send the reply
  set1  mapletxrxctl, $00
  ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; -----------------------------------------------------------------------------
;; MapleClockSetCondition ($0E3A)
;; Set Condition on the clock: start the buzzer. Timer 1 runs in PWM mode on P1.7;
;; the DC supplies a period and a duty value.
;; -----------------------------------------------------------------------------
MapleClockSetCondition:
  mov   #$0A, vrmad1
  clr1  vrmad2, $00
  ld    vtrbf         ; Grab duty
  st    b
  ld    vtrbf         ; Grab pitch
  st    c
  mov   #$00, t1cnt   ; Stop T1
  mov   #$FF, acc     ; T1LR = FF - pitch number
  sub   c
  st    t1lr
  add   b             ; T1LC = (FF - pitch number) + duty
  st    t1lc
  mov   #$50, t1cnt   ; T1L on, pulse on
  call  MapleBeginReply    ; Maple-related calls
  call  MapleReplyAck
  ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; -----------------------------------------------------------------------------
;; MapleStorageGetLastError ($0E5D)
;; Get Last Error (end of block write): turn the flash icon off and ack, or report
;; MapleStorageErr with $FB.
;; -----------------------------------------------------------------------------
MapleStorageGetLastError:
  mov   #$02, xbnk
  mov   #$00, xram_0184
  ld    MapleStorageErr
  bnz   .error
  call  MapleBeginReply
  call  MapleReplyAck
  ret
.error:
  call  MapleReplyFileError
  ret
;; -----------------------------------------------------------------------------
;; MapleResendLastReply ($0E6F)
;; The DC asked us to resend ($FC): rebuild the reply for MapleLastCmd.
;; -----------------------------------------------------------------------------
MapleResendLastReply:
  ld    MapleLastCmd
  bnz   .dispatch
  br    .return
.dispatch:
  be    #$01, .deviceInfo
  be    #$02, .allStatus
  be    #$0A, .mediaInfo
  be    #$0B, .blockRead
  be    #$0C, .ack
  be    #$0D, .lastError
  be    #$09, .condition
  be    #$0E, .buzzer ; beep
  be    #$FD, .unknown
  be    #$FC, .resend
  be    #$FB, .fileError
  be    #$FA, .lcdError
  br    .return
.deviceInfo:
  call  MapleCmdDeviceInfo
  br    .return
.allStatus:
  call  MapleCmdAllStatus
  br    .return
.mediaInfo:
  ld    MapleFuncType
  be    #$04, .mediaInfoLcd
  call  MapleStorageGetMediaInfo
  br    .return
.mediaInfoLcd:
  call  MapleLcdGetMediaInfo
  br    .return
.blockRead:
  ld    MapleFuncType
  be    #$08, .blockReadClock
  call  MapleStorageBlockRead
  br    .return
.blockReadClock:
  call  MapleClockBlockRead
  br    .return
.ack:
  call  MapleBeginReply
  call  MapleReplyAck
  br    .return
.lastError:
  call  MapleStorageGetLastError
  br    .return
.condition:
  call  MapleClockGetCondition
  br    .return
.buzzer:
  call  MapleClockSetCondition  ; Play maple buzzer
  br    .return
.unknown:
  call  MapleReplyUnknownCommand
  br    .return
.resend:
  call  MapleReplyResend
  br    .return
.fileError:
  call  MapleReplyFileError
  br    .return
.lcdError:
  call  MapleReplyLcdError
.return:
  ret
;; -----------------------------------------------------------------------------
;; MapleReplyFileError ($0EDE)
;; Reply $FB (file error) with one word: MapleStorageErr.
;; -----------------------------------------------------------------------------
MapleReplyFileError:
  call  MapleBeginReply
  mov   #$01, vtrbf
  ld    MapleMyAddr
  st    vtrbf
  ld    MapleHostAddr
  st    vtrbf
  mov   #$FB, vtrbf
  mov   #$FB, MapleLastCmd
  mov   #$01, vlreg
  ld    MapleStorageErr
  st    vtrbf
  mov   #$00, acc
  st    vtrbf
  st    vtrbf
  st    vtrbf
  set1  vsel, $00
  set1  mapletxrxctl, $04
  set1  mapletxrxctl, $00
  ret
;; -----------------------------------------------------------------------------
;; MapleReplyLcdError ($0F08)
;; Reply $FA with one word: MapleLcdErr.
;; -----------------------------------------------------------------------------
MapleReplyLcdError:
  call  MapleBeginReply
  mov   #$01, vtrbf
  ld    MapleMyAddr
  st    vtrbf
  ld    MapleHostAddr
  st    vtrbf
  mov   #$FA, vtrbf
  mov   #$FA, MapleLastCmd
  mov   #$01, vlreg
  ld    MapleLcdErr
  st    vtrbf
  mov   #$00, acc
  st    vtrbf
  st    vtrbf
  st    vtrbf
  set1  vsel, $00
  set1  mapletxrxctl, $04
  set1  mapletxrxctl, $00
  ret
;; -----------------------------------------------------------------------------
;; MapleReplyAck ($0F32)
;; Reply $07 (device reply / ack), no payload. Caller must have called MapleBeginReply.
;; -----------------------------------------------------------------------------
MapleReplyAck:
  mov   #$00, vtrbf
  ld    MapleMyAddr
  st    vtrbf
  ld    MapleHostAddr
  st    vtrbf
  mov   #$07, vtrbf
  mov   #$00, vlreg
  set1  vsel, $00
  set1  mapletxrxctl, $04
  set1  mapletxrxctl, $00
  ret
;; -----------------------------------------------------------------------------
;; MapleTxRomWords ($0F4A)
;; Copy B words from ROM (TRH:TRL + ACC) into work RAM, reversing the byte order of
;; every word. ACC is advanced past the copied words on return.
;; -----------------------------------------------------------------------------
MapleTxRomWords:
  add   #$03
  mov   #$00, fpr
.loop:
  push  acc
  ldc
  st    vtrbf
  pop   acc
  dec   acc
  push  acc
  ldc
  st    vtrbf
  pop   acc
  dec   acc
  push  acc
  ldc
  st    vtrbf
  pop   acc
  dec   acc
  push  acc
  ldc
  st    vtrbf
  pop   acc
  add   #$07
  dbnz  b, .loop
  sub   #$03
  ret
;; -----------------------------------------------------------------------------
;; MapleTxRamWords ($0F79)
;; Copy B words from bank 1 @R0 into work RAM as-is.
;; -----------------------------------------------------------------------------
MapleTxRamWords:
  set1  psw, rambk0
.loop:
  ld    @R0
  st    vtrbf
  inc   $00
  ld    @R0
  st    vtrbf
  inc   $00
  ld    @R0
  st    vtrbf
  inc   $00
  ld    @R0
  st    vtrbf
  inc   $00
  dbnz  b, .loop
  clr1  psw, rambk0
  ret
;; -----------------------------------------------------------------------------
;; MapleTxFlashWords ($0F95)
;; Copy B words from flash (FPR, TRH:TRL) into work RAM, byte-reversed, lighting
;; the flash access icon. TRL is advanced past the copied words.
;; -----------------------------------------------------------------------------
MapleTxFlashWords:
  mov   #$02, xbnk
  mov   #$01, xram_0184
  ld    trl
  add   #$03
.loop:
  st    trl
  ldf
  st    vtrbf
  dec   trl
  ldf
  st    vtrbf
  dec   trl
  ldf
  st    vtrbf
  dec   trl
  ldf
  st    vtrbf
  ld    trl
  add   #$07
  dbnz  b, .loop
  sub   #$03
  st    trl
  ret
;; -----------------------------------------------------------------------------
;; MapleWaitTxReady ($0FBF)
;; Spin until MAPLESTA.0 says the transmit chunk has been taken by the hardware.
;; -----------------------------------------------------------------------------
MapleWaitTxReady:
  push  acc
.wait:
  ld    maplesta
  bn    acc, $00, .wait
  pop   acc
  ret
;; -----------------------------------------------------------------------------
;; ByteSwapWordsBank1 ($0FC9)
;; Reverse the byte order of C 32-bit words in bank 1 starting at R0 (rounded down
;; to a multiple of 4).
;; -----------------------------------------------------------------------------
ByteSwapWordsBank1:
  push  acc
  push  b
  push  c
  set1  psw, rambk0
  ld    $00
  and   #$FC
  st    $00
  add   #$03
  st    $01
.loop:
  ld    @R1
  st    b
  ld    @R0
  st    @R1
  ld    b
  st    @R0
  dec   $01
  inc   $00
  ld    @R1
  st    b
  ld    @R0
  st    @R1
  ld    b
  st    @R0
  ld    $01
  add   #$05
  st    $01
  ld    $00
  add   #$03
  st    $00
  dbnz  c, .loop
  clr1  psw, rambk0
  pop   c
  pop   b
  pop   acc
  ret
;; -----------------------------------------------------------------------------
;; MapleHwReset ($1007)
;; Pulse MAPLERST, then VSEL = $13 (work RAM to Maple, auto-increment) and enable
;; frame reception (MAPLETXRXCTL.2).
;; -----------------------------------------------------------------------------
MapleHwReset:
  mov   #$80, maplerst
  nop
  nop
  mov   #$00, maplerst
  nop
  nop
  mov   #$13, vsel
  set1  mapletxrxctl, $02
  ret
;; -----------------------------------------------------------------------------
;; MapleInitAddress ($1017)
;; Forget our Maple address and compute the expansion-slot bit from P7.2-3 (which
;; slot of the controller we are in) via MapleSlotBits; MapleIdPins keeps the raw
;; pin state so MapleMode can notice a move to another slot.
;; -----------------------------------------------------------------------------
MapleInitAddress:
  mov   #$00, acc
  st    MapleMyAddr
  st    MapleAddrState
  ld    p7
  and   #$0C
  st    MapleIdPins
  ror
  ror
  mov   #<MapleSlotBits, trl
  mov   #>MapleSlotBits, trh
  ldc
  st    MapleMyAddr
  ret

MapleSlotBits:
  .byte $01, $02, $04, $08

;; -----------------------------------------------------------------------------
;; ClockMode ($1034)
;; BiosMode 2, A pressed. Shows HH:MM in big digits with the selected animal
;; animation (ClockAnimationStep) on the right. Keys:
;;   A alone / Right -> ClockShowDate for a few seconds
;;   A + Left        -> ClockSettingsMenu
;;   MODE / plug in  -> back to MainMenu (via WaitKeyEvent's $FD / $FF)
;;   SLEEP           -> SleepUntilWake, then redraw
;; -----------------------------------------------------------------------------
ClockMode:
  push  ocr
  mov   #$81, ocr
  mov   #$02, xbnk
  mov   #$00, xram_0181
  mov   #$00, xram_0182
  mov   #$04, xram_0183
  mov   #$00, xbnk
  pop   ocr
  mov   #$00, BatteryCheck
.redraw:
  call  ClockDrawTime
  mov   #$01, IdleTicks
  mov   #$00, HalfSecTicks
  mov   #$80, SleepCtl
.loop:
  callf WaitKeyEvent
  be    #$FF, .exit
  be    #$FE, .sleep
  be    #$FD, .exit
  be    #$08, .showDate
  ld    Buttons_Current
  be    #$14, .settings                 ; A + Left held together?
  be    #$10, .showDate
  ld    Second                          ; seconds changed since last pass?
  xor   b
  bz    .noTick
  call  ClockAnimationStep              ; advance the clock animation one frame
.noTick:
  ld    Second                          ; new minute -> redraw HH:MM
  st    b
  bnz   .loop
  push  ocr
  mov   #$81, ocr
  call  ClockUpdateTime
  pop   ocr
  br    .loop
.sleep:
  callf SleepUntilWake
  br    .redraw
.settings:
  call  ClockSettingsMenu
  bnz   .exit
  mov   #$00, SleepCtl
  mov   #$01, IdleTicks
  jmp   .redraw
.showDate:
  call  ClockShowDate
  mov   #$00, HalfSecTicks
  mov   #$01, IdleTicks
  mov   #$80, SleepCtl                  ; SleepCtl $80: SLEEP returns $FE to this loop
.dateLoop:
  callf WaitKeyEvent
  be    #$FF, .exit
  be    #$FE, .sleep
  be    #$FD, .exit
  be    #$04, .redraw
  ld    Buttons_Current
  and   #$38
  be    #$20, .redraw                   ; B (without A/Right) -> back to the time
  ld    IdleTicks                       ; show the date for 8 half-second ticks
  be    #$08, .dateLoop
  bp    psw, cy, .dateLoop
  br    .redraw
.exit:
  mov   #$00, SleepCtl
  jmpf  MainMenu
;; -----------------------------------------------------------------------------
;; ClockDrawTime ($10CA)
;; Clear the screen and draw HH:MM with the big 8x8 digits (row 0). Also resets the
;; animation frame counter in ClockAnim (keeps the animal selection bits).
;; -----------------------------------------------------------------------------
ClockDrawTime:
  push  acc
  push  b
  push  CursorX
  push  CursorY
  push  psw
  clr1  psw, rambk0
  clr1  p3int, $00
  ld    ClockAnim
  and   #$C0
  st    ClockAnim
  callf ClearScreen
  mov   #$00, CursorY
  call  DrawHour
  st    BcdHour
  call  DrawMinute                      ; ACC = BCD minute
  st    BcdMinute
  mov   #$03, CursorX
  mov   #$0A, acc                       ; glyph $0A = ':'
  callf DrawGlyph8x8
  set1  p3int, $00
  pop   psw
  pop   CursorY
  pop   CursorX
  pop   b
  pop   acc
  ret
;; -----------------------------------------------------------------------------
;; ClockUpdateTime ($1102)
;; Called when Second == 0: redraw the minutes, and the hours too on the hour.
;; -----------------------------------------------------------------------------
ClockUpdateTime:
  push  acc
  push  b
  push  c
  push  CursorX
  push  CursorY
  clr1  p3int, $00
  mov   #$00, CursorY
  ld    Second
  bnz   .return
  call  DrawMinute
  st    BcdMinute
  ld    Minute
  bnz   .return
  call  DrawHour
  st    BcdHour
.return:
  set1  p3int, $00
  pop   CursorY
  pop   CursorX
  pop   c
  pop   b
  pop   acc
  ret
;; -----------------------------------------------------------------------------
;; ClockShowDate ($112E)
;; Draw the date below the time: year on row 2, month name + day on row 0 (the
;; row-0 time is overwritten), and refresh the BCD copies BcdYearHi..BcdDay.
;; -----------------------------------------------------------------------------
ClockShowDate:
  push  acc
  push  $00
  push  CursorX
  push  CursorY
  clr1  p3int, $00
  callf ClearScreen
  mov   #$02, CursorY
  call  DrawYear
  clr1  p3int, $00
  mov   #MathHi, $00
  ld    @R0
  st    BcdYearHi
  inc   $00
  ld    @R0
  st    BcdYearLo
  mov   #$00, CursorY
  call  DrawMonthName
  clr1  p3int, $00
  st    BcdMonth
  call  DrawDay
  clr1  p3int, $00
  st    BcdDay
  set1  p3int, $00
  pop   CursorY
  pop   CursorX
  pop   $00
  pop   acc
  ret
;; -----------------------------------------------------------------------------
;; ClockSettingsMenu ($1167)
;; "Set clock" with a Yes/No choice (Left/Right, kept in B, No preselected).
;; A on Yes runs SetClockProcedure; A on No moves on to the animal picker
;; (AnimalMenu). B returns to the clock.
;; Out: ACC = 0 back to ClockMode, $FF if the controller was plugged in.
;; -----------------------------------------------------------------------------
ClockSettingsMenu:
  clr1  p3int, $00
  callf ClearScreen
  call  DrawSetClockTitle
  mov   #$00, acc
  callf DrawYesNoChoice
  mov   #$40, SleepCtl
  set1  p3int, $00
  st    b
  callf WaitAllButtonsReleased
.loop:
  callf WaitKeyEvent
  be    #$10, .select
  be    #$20, AnimalMenu_accept
  be    #$04, .toggle
  be    #$08, .toggle
  be    #$FF, AnimalMenu_pluggedIn
  br    .loop
.select:
  ld    b
  bz    AnimalMenu
  call  SetClockProcedure
  be    #$FF, AnimalMenu_pluggedIn
  br    AnimalMenu
.toggle:
  ld    b
  xor   #$FF
  st    b
  callf DrawYesNoChoice
  callf WaitDpadReleased
  br    .loop
;; -----------------------------------------------------------------------------
;; AnimalMenu ($11AB)
;; Pick the clock animation: Up/Down cycles ClockAnim bits 7-6 through
;; Dog (0), Fish ($40), Bird ($80). A accepts, B goes back to ClockSettingsMenu.
;; -----------------------------------------------------------------------------
AnimalMenu:
  callf ClearScreen
  call  DrawAnimalMenu
  mov   #$40, SleepCtl
  callf WaitAllButtonsReleased
.loop:
  callf WaitKeyEvent
  be    #$10, AnimalMenu_accept
  be    #$20, ClockSettingsMenu
  be    #$01, .next
  be    #$02, .prev
  be    #$FF, AnimalMenu_pluggedIn
  br    .loop
.next:
  ld    ClockAnim
  and   #$C0
  be    #$40, .add
  bp    psw, cy, .add
  mov   #$00, ClockAnim
  br    .redraw
.add:
  add   #$40
  st    ClockAnim
.redraw:
  call  DrawAnimalName
  br    .loop
.prev:
  ld    ClockAnim
  and   #$C0
  bnz   .sub
  mov   #$80, ClockAnim
  br    .redraw
.sub:
  sub   #$40
  st    ClockAnim
  br    .redraw
AnimalMenu_accept:
  set1  p3int, $00
  mov   #$00, acc
  mov   #$02, BiosMode
  ret
AnimalMenu_pluggedIn:
  mov   #$FF, acc
  ret
;; -----------------------------------------------------------------------------
;; DrawAnimalMenu ($11FF)
;; "Animated display" title, then falls into DrawAnimalName.
;; -----------------------------------------------------------------------------
DrawAnimalMenu:
  clr1  p3int, $00
  mov   #<Str_AnimatedDisplay, trl
  mov   #>Str_AnimatedDisplay, trh
  mov   #$00, TextInvert
  mov   #$00, CursorX
  mov   #$00, CursorY
  callf DrawString
;; -----------------------------------------------------------------------------
;; DrawAnimalName ($1213)
;; Name of the animal selected in ClockAnim bits 7-6 on row 3.
;; -----------------------------------------------------------------------------
DrawAnimalName:
  clr1  p3int, $00
  ld    ClockAnim
  and   #$C0
  bz    .dog
  be    #$40, .fish
  mov   #<Str_Bird, trl
  mov   #>Str_Bird, trh
  br    .draw
.dog:
  mov   #<Str_Dog, trl
  mov   #>Str_Dog, trh
  br    .draw
.fish:
  mov   #<Str_Fish, trl
  mov   #>Str_Fish, trh
.draw:
  mov   #$00, CursorX
  mov   #$03, CursorY
  callf DrawString
  set1  p3int, $00
  ret
;; -----------------------------------------------------------------------------
;; DrawSetClockTitle ($1240)
;; "Set clock" on rows 0-1.
;; -----------------------------------------------------------------------------
DrawSetClockTitle:
  mov   #<Str_SetClock, trl
  mov   #>Str_SetClock, trh
  mov   #$00, TextInvert
  mov   #$00, CursorX
  mov   #$00, CursorY
  callf DrawString
  ret
;; -----------------------------------------------------------------------------
;; InitDefaultDateTime ($1253)
;; Load 2000-01-01 00:00:00 into the BCD copy (BcdYearHi..BcdSecond) and the binary
;; date/time (YearHi..Second), and clear HalfSecond.
;; -----------------------------------------------------------------------------
InitDefaultDateTime:
  mov   #$20, BcdYearHi
  mov   #$00, BcdYearLo
  mov   #BcdYearHi, $00                 ; R0 -> BcdYearHi: Bcd16ToBin -> MathHi:MathLo
  callf Bcd16ToBin
  ld    MathHi
  st    YearHi
  ld    MathLo
  st    YearLo
  mov   #$01, BcdMonth
  ld    BcdMonth
  callf BcdToBin
  st    Month
  mov   #$01, BcdDay
  ld    BcdDay
  callf BcdToBin
  st    Day
  mov   #$00, BcdHour
  ld    BcdHour
  callf BcdToBin
  st    Hour
  mov   #$00, BcdMinute
  ld    BcdMinute
  callf BcdToBin
  st    Minute
  mov   #$00, BcdSecond
  ld    BcdSecond
  callf BcdToBin
  st    Second
  mov   #$00, HalfSecond
  ret
;; -----------------------------------------------------------------------------
;; SetClockProcedure ($129D)
;; The set-the-clock wizard: year, month, day, hour, minute, then "OK ?". Each step
;; returns $20 (B pressed) to step back to the previous field. Gives up with
;; ACC = $FF as soon as the VMU is plugged into a controller; ACC = 0 when done.
;; Seconds are reset to 0 when the user confirms.
;; -----------------------------------------------------------------------------
SetClockProcedure:
  push  psw
  clr1  psw, rambk0
  ld    Hour
  callf BinToBcd
  st    BcdHour
  ld    Minute
  callf BinToBcd
  st    BcdMinute
  mov   #$00, Second                    ; seconds restart from zero
  ld    p7
  and   #$01
  bnz   .pluggedIn
  mov   #$40, SleepCtl                  ; SleepCtl $40: ignore SLEEP while editing
.year:
  callf ClearScreen
  ld    p7
  and   #$01
  bnz   .pluggedIn
  mov   #$00, TextInvert
  call  SetClockShowYear
  call  SetClockEditYear
  callf UpdateLeapYearEntry             ; UpdateLeapYear
.month:
  ld    p7
  and   #$01
  bnz   .pluggedIn
  call  SetClockShowMonth
  call  SetClockEditMonth
  be    #$20, .year
.day:
  ld    p7
  and   #$01
  bnz   .pluggedIn
  call  SetClockShowDay
  call  SetClockEditDay
  be    #$20, .month
.hour:
  ld    p7
  and   #$01
  bnz   .pluggedIn
  ld    Hour
  callf BinToBcd
  st    BcdHour
  ld    Minute
  callf BinToBcd
  st    BcdMinute
  call  SetClockShowHour
  call  SetClockEditHour
  be    #$20, .day
.minute:
  ld    p7
  and   #$01
  bnz   .pluggedIn
  call  SetClockShowMinute
  call  SetClockEditMinute
  be    #$20, .hour
  ld    p7
  and   #$01
  bnz   .pluggedIn
  call  SetClockShowConfirm
  call  SetClockConfirm
  be    #$20, .minute
  mov   #$00, Second
  mov   #$00, acc
.return:
  mov   #$00, SleepCtl
  pop   psw
  ret
.pluggedIn:
  mov   #$FF, acc
  br    .return
;; -----------------------------------------------------------------------------
;; SetClockEditYear ($132E)
;; Up/Down change the year (wraps 0 <-> 9999), A or B leave the field.
;; Out: ACC = key that ended the edit.
;; -----------------------------------------------------------------------------
SetClockEditYear:
  callf WaitAllButtonsReleased
  mov   #$00, HalfSecTicks
.loop:
  callf WaitKeyEventRepeat
  mov   #$00, Second
  be    #$10, .return
  be    #$01, .inc
  be    #$02, .dec
  be    #$FF, .return
  br    .loop
.inc:
  ld    YearLo
  clr1  psw, cy
  add   #$01
  st    YearLo
  mov   #$00, acc
  addc  YearHi
  st    YearHi
  ld    YearHi
  be    #$26, .redraw                   ; year > $270F (9999) -> wrap to 0
  bp    psw, cy, .redraw
  ld    YearLo
  be    #$0F, .redraw
  bp    psw, cy, .redraw
  mov   #$00, YearHi
  mov   #$00, YearLo
  br    .redraw
.dec:
  ld    YearLo
  clr1  psw, cy
  sub   #$01
  st    YearLo
  ld    YearHi
  subc  #$00
  st    YearHi
  ld    YearHi
  bne   #$FF, .redraw
  ld    YearLo
  bne   #$FF, .redraw
  mov   #$27, YearHi
  mov   #$0F, YearLo
.redraw:
  mov   #$01, CursorY
  call  DrawYear
  br    .loop
.return:
  ret
;; -----------------------------------------------------------------------------
;; SetClockEditMonth ($1395)
;; Up/Down change the month (1-12, wrapping) and clamp the day to the new month's
;; length (February honours LeapYear).
;; -----------------------------------------------------------------------------
SetClockEditMonth:
  callf WaitAllButtonsReleased
  mov   #$00, HalfSecTicks
.loop:
  callf WaitKeyEventRepeat
  mov   #$00, Second
  be    #$10, .return
  be    #$20, .return
  be    #$01, .inc
  be    #$02, .dec
  be    #$FF, .return
  br    .loop
.inc:
  inc   Month
  ld    Month
  be    #$0C, .redraw
  bp    psw, cy, .redraw
  mov   #$01, Month
  br    .redraw
.dec:
  dec   Month
  ld    Month
  bnz   .redraw
  mov   #$0C, Month
.redraw:
  call  DrawMonthName
  ld    Month
  be    #$02, .clampFeb
  ld    Day
  be    #$1E, .clamp30
  bn    psw, cy, .clamp30
  br    .loop
.return:
  ret
.clamp30:
  ld    Month
  be    #$04, .setDay30
  be    #$06, .setDay30
  be    #$09, .setDay30
  be    #$0B, .setDay30
  br    .loop
.setDay30:
  mov   #$1E, Day
  call  DrawDay
  br    .loop
.clampFeb:
  ld    Day
  be    #$1D, .feb
  bn    psw, cy, .feb
  br    .loop
.feb:
  ld    LeapYear
  bz    .feb28
  mov   #$1D, Day
  br    .redrawDay
.feb28:
  mov   #$1C, Day
.redrawDay:
  call  DrawDay
  br    .loop
;; -----------------------------------------------------------------------------
;; SetClockEditDay ($140D)
;; Up/Down change the day within the current month's length. On exit the day is
;; clamped again in case the month/leap year changed.
;; -----------------------------------------------------------------------------
SetClockEditDay:
  callf WaitAllButtonsReleased
  mov   #$00, HalfSecTicks
.loop:
  callf WaitKeyEventRepeat
  mov   #$00, Second
  be    #$10, .clampAndReturn
  be    #$20, .clampAndReturn
  be    #$01, .inc
  be    #$FF, .clampAndReturn
  bne   #$02, .loop
  jmp   .dec
.clampAndReturn:
  push  acc
  ld    Month
  be    #$02, .clampFeb
  be    #$04, .clamp30
  be    #$06, .clamp30
  be    #$09, .clamp30
  be    #$0B, .clamp30
  pop   acc
  ret
.clampFeb:
  ld    LeapYear
  bnz   .clampFebLeap
  ld    Day
  be    #$1C, .return
  bp    psw, cy, .return
  mov   #$1C, Day
  br    .return
.clampFebLeap:
  ld    Day
  be    #$1D, .return
  bp    psw, cy, .return
  mov   #$1D, Day
  br    .return
.clamp30:
  ld    Day
  be    #$1E, .return
  bp    psw, cy, .return
  mov   #$1E, Day
.return:
  pop   acc
  ret
.inc:
  inc   Day
  ld    Month
  be    #$02, .incFeb
  be    #$04, .inc30
  be    #$06, .inc30
  be    #$09, .inc30
  be    #$0B, .inc30
  ld    Day
  be    #$1F, .redraw
  bp    psw, cy, .redraw
  mov   #$01, Day
  br    .redraw
.inc30:
  ld    Day
  be    #$1E, .redraw
  bp    psw, cy, .redraw
  mov   #$01, Day
  br    .redraw
.incFeb:
  ld    LeapYear
  bnz   .incFebLeap
  ld    Day
  be    #$1C, .redraw
  bp    psw, cy, .redraw
  mov   #$01, Day
  br    .redraw
.incFebLeap:
  ld    Day
  be    #$1D, .redraw
  bp    psw, cy, .redraw
  mov   #$01, Day
  br    .redraw
.dec:
  dec   Day
  ld    Month
  be    #$02, .decFeb
  be    #$04, .dec30
  be    #$06, .dec30
  be    #$09, .dec30
  be    #$0B, .dec30
  ld    Day
  bnz   .redraw
  mov   #$1F, Day
  br    .redraw
.dec30:
  ld    Day
  bnz   .redraw
  mov   #$1E, Day
  br    .redraw
.decFeb:
  ld    LeapYear
  bnz   .decFebLeap
  ld    Day
  bnz   .redraw
  mov   #$1C, Day
  br    .redraw
.decFebLeap:
  ld    Day
  bnz   .redraw
  mov   #$1D, Day
.redraw:
  call  DrawDay
  jmp   .loop
;; -----------------------------------------------------------------------------
;; SetClockEditHour ($14F4)
;; Up/Down change the hour (0-23, wrapping).
;; -----------------------------------------------------------------------------
SetClockEditHour:
  callf WaitAllButtonsReleased
  mov   #$00, HalfSecTicks
.loop:
  callf WaitKeyEventRepeat
  mov   #$00, Second
  be    #$10, .return
  be    #$20, .return
  be    #$01, .inc
  be    #$02, .dec
  be    #$FF, .return
  br    .loop
.inc:
  inc   Hour
  ld    Hour
  be    #$17, .redraw
  bp    psw, cy, .redraw
  mov   #$00, Hour
  br    .redraw
.dec:
  dec   Hour
  ld    Hour
  bne   #$FF, .redraw
  mov   #$17, Hour
.redraw:
  mov   #$01, CursorY
  call  DrawHour
  br    .loop
.return:
  ret
;; -----------------------------------------------------------------------------
;; SetClockEditMinute ($1532)
;; Up/Down change the minute (0-59, wrapping).
;; -----------------------------------------------------------------------------
SetClockEditMinute:
  callf WaitAllButtonsReleased
  mov   #$00, HalfSecTicks
.loop:
  callf WaitKeyEventRepeat
  mov   #$00, Second
  be    #$10, .return
  be    #$20, .return
  be    #$01, .inc
  be    #$02, .dec
  be    #$FF, .return
  br    .loop
.inc:
  inc   Minute
  ld    Minute
  be    #$3B, .redraw
  bp    psw, cy, .redraw
  mov   #$00, Minute
  br    .redraw
.dec:
  dec   Minute
  ld    Minute
  bne   #$FF, .redraw
  mov   #$3B, Minute
.redraw:
  mov   #$01, CursorY
  call  DrawMinute
  br    .loop
.return:
  ret
;; -----------------------------------------------------------------------------
;; SetClockConfirm ($1570)
;; "OK ?" with a Yes/No choice (Left/Right). A on Yes -> ACC = 0 (done),
;; A on No or B -> ACC = $20 (go back to the minute field).
;; -----------------------------------------------------------------------------
SetClockConfirm:
  callf WaitAllButtonsReleased
  mov   #$00, b
  mov   #$00, HalfSecTicks
.loop:
  callf WaitKeyEvent
  mov   #$00, Second
  be    #$10, .select
  be    #$20, .return
  be    #$04, .toggle
  be    #$08, .toggle
  be    #$FF, .return
  br    .loop
.toggle:
  ld    b
  xor   #$FF
  st    b
  callf DrawYesNoChoice
  callf WaitDpadReleased
  br    .loop
.select:
  ld    b
  bz    .no
  mov   #$00, acc
  br    .return
.no:
  mov   #$20, acc
.return:
  ret
;; -----------------------------------------------------------------------------
;; DrawYear ($15AB)
;; Year (YearHi:YearLo) as 4 big digits at column 2 of row CursorY.
;; -----------------------------------------------------------------------------
DrawYear:
  clr1  p3int, $00
  mov   #YearHi, $00
  callf Bin16ToBcd                      ; Bin16ToBcd -> MathHi:MathLo
  mov   #MathHi, $00
  mov   #$02, CursorX
  callf DrawBcd16Big
  set1  p3int, $00
  ret
;; -----------------------------------------------------------------------------
;; DrawMonthName ($15BF)
;; Three-letter month name from MonthNames in big glyphs at columns 3-5.
;; The big font has no lower case: glyph = ASCII - $31 maps 'A' to glyph $10.
;; -----------------------------------------------------------------------------
DrawMonthName:
  push  b
  push  c
  push  trh
  push  trl
  clr1  p3int, $00
  mov   #<MonthNames, trl
  mov   #>MonthNames, trh
  ld    Month
  and   #$0F
  rol
  rol
  st    b
  mov   #$03, c
  mov   #$03, CursorX
.loop:
  ld    b
  inc   b
  ldc
  sub   #$31
  callf DrawGlyph8x8
  inc   CursorX
  dbnz  c, .loop
  set1  p3int, $00
  pop   trl
  pop   trh
  pop   c
  pop   b
  ret

MonthNames:
  .string 4 "    "
  .string 4 "JAN"
  .string 4 "FEB"
  .string 4 "MAR"
  .string 4 "APR"
  .string 4 "MAY"
  .string 4 "JUN"
  .string 4 "JUL"
  .string 4 "AUG"
  .string 4 "SEP"
  .string 4 "OCT"
  .string 4 "NOV"
  .string 4 "DEC"

;; -----------------------------------------------------------------------------
;; DrawDay ($162B)
;; Day at column 0 of row CursorY, big digits; one digit is drawn after a blank cell.
;; -----------------------------------------------------------------------------
DrawDay:
  clr1  p3int, $00
  ld    Day
  be    #$09, .oneDigit
  bp    psw, cy, .oneDigit
  callf BinToBcd
  mov   #$00, CursorX
  callf DrawBcdByteBig
  br    .return
.oneDigit:
  mov   #$00, CursorX
  callf ClearCell8x8
  inc   CursorX
  callf DrawGlyph8x8
.return:
  set1  p3int, $00
  ret
;; -----------------------------------------------------------------------------
;; DrawHour ($164E)
;; Hour at column 1 (single digit after a blank), big digits. Out: ACC = BCD hour.
;; -----------------------------------------------------------------------------
DrawHour:
  clr1  p3int, $00
  ld    Hour
  be    #$09, .oneDigit
  bp    psw, cy, .oneDigit
  callf BinToBcd
  mov   #$01, CursorX
  callf DrawBcdByteBig
  br    .return
.oneDigit:
  mov   #$01, CursorX
  callf ClearCell8x8
  inc   CursorX
  callf DrawGlyph8x8
.return:
  set1  p3int, $00
  ret
;; -----------------------------------------------------------------------------
;; DrawMinute ($1671)
;; Minute at columns 4-5, big digits. Out: ACC = BCD minute.
;; -----------------------------------------------------------------------------
DrawMinute:
  clr1  p3int, $00
  ld    Minute
  callf BinToBcd
  mov   #$04, CursorX
  callf DrawBcdByteBig
  set1  p3int, $00
  ret
;; -----------------------------------------------------------------------------
;; SetClockShowYear ($1681)
;; Screen for the year field: up/down arrows above/below the year, ":Select" hint.
;; -----------------------------------------------------------------------------
SetClockShowYear:
  clr1  p3int, $00
  mov   #$05, CursorX
  mov   #$00, CursorY
  mov   #$0C, acc
  callf DrawGlyph8x8
  mov   #$02, CursorY
  mov   #$0B, acc
  callf DrawGlyph8x8
  mov   #$01, CursorY
  call  DrawYear
  mov   #<Str_SelectHint, trl
  mov   #>Str_SelectHint, trh
  mov   #$00, CursorX
  mov   #$03, CursorY
  callf DrawString
  set1  p3int, $00
  ret
;; -----------------------------------------------------------------------------
;; SetClockShowMonth ($16AF)
;; Screen for the month field: month name + day, arrows over the month.
;; -----------------------------------------------------------------------------
SetClockShowMonth:
  push  b
  clr1  p3int, $00
  mov   #$00, CursorY
  mov   #$00, TextInvert
  mov   #$02, b
.clear:
  mov   #$01, CursorX
  callf ClearCell8x8
  mov   #$02, CursorY
  dbnz  b, .clear
  mov   #$02, CursorX
  mov   #$01, CursorY
  callf ClearCell8x8
  mov   #$05, CursorX
  mov   #$00, CursorY
  mov   #$0C, acc
  callf DrawGlyph8x8
  mov   #$02, CursorY
  mov   #$0B, acc
  callf DrawGlyph8x8
  mov   #$01, CursorY
  call  DrawMonthName
  call  DrawDay
  set1  p3int, $00
  pop   b
  ret
;; -----------------------------------------------------------------------------
;; SetClockShowDay ($16F2)
;; Screen for the day field: arrows over the day.
;; -----------------------------------------------------------------------------
SetClockShowDay:
  push  b
  clr1  p3int, $00
  mov   #$00, CursorY
  mov   #$00, TextInvert
  mov   #$02, b
.clear:
  mov   #$02, CursorX
  callf ClearCell8x8
  mov   #$05, CursorX
  callf ClearCell8x8
  mov   #$02, CursorY
  dbnz  b, .clear
  mov   #$02, CursorX
  mov   #$01, CursorY
  callf ClearCell8x8
  mov   #$01, CursorX
  mov   #$00, CursorY
  mov   #$0C, acc
  callf DrawGlyph8x8
  mov   #$02, CursorY
  mov   #$0B, acc
  callf DrawGlyph8x8
  mov   #$01, CursorY
  call  DrawMonthName
  call  DrawDay
  set1  p3int, $00
  pop   b
  ret
;; -----------------------------------------------------------------------------
;; SetClockShowHour ($173B)
;; Screen for the hour field: HH:MM with arrows over the hour.
;; -----------------------------------------------------------------------------
SetClockShowHour:
  push  b
  mov   #$00, Second
  clr1  p3int, $00
  mov   #$00, CursorY
  mov   #$00, TextInvert
  mov   #$02, b
.clear:
  mov   #$01, CursorX
  callf ClearCell8x8
  mov   #$05, CursorX
  callf ClearCell8x8
  mov   #$02, CursorY
  dbnz  b, .clear
  mov   #$00, CursorX
  mov   #$01, CursorY
  callf ClearCell8x8
  mov   #$02, CursorX
  mov   #$00, CursorY
  mov   #$0C, acc
  callf DrawGlyph8x8
  mov   #$02, CursorY
  mov   #$0B, acc
  callf DrawGlyph8x8
  mov   #$03, CursorX
  mov   #$01, CursorY
  mov   #$0A, acc
  callf DrawGlyph8x8
  ld    BcdHour
  callf BcdToBin
  st    Hour
  call  DrawHour
  ld    BcdMinute
  callf BcdToBin
  st    Minute
  call  DrawMinute
  set1  p3int, $00
  pop   b
  ret
;; -----------------------------------------------------------------------------
;; SetClockShowMinute ($179E)
;; Screen for the minute field: arrows over the minutes, ":Select" hint.
;; -----------------------------------------------------------------------------
SetClockShowMinute:
  mov   #$00, Second
  clr1  p3int, $00
  mov   #$00, TextInvert
  mov   #$00, CursorY
  mov   #$02, CursorX
  callf ClearCell8x8
  mov   #$01, xbnk
  callf ClearHalfScreen
  mov   #<Str_SelectHint, trl
  mov   #>Str_SelectHint, trh
  mov   #$00, CursorX
  mov   #$03, CursorY
  callf DrawString
  mov   #$05, CursorX
  mov   #$00, CursorY
  mov   #$0C, acc
  callf DrawGlyph8x8
  mov   #$02, CursorY
  mov   #$0B, acc
  callf DrawGlyph8x8
  set1  p3int, $00
  ret
;; -----------------------------------------------------------------------------
;; SetClockShowConfirm ($17DC)
;; "OK ?" prompt with the Yes/No choice, Yes highlighted.
;; -----------------------------------------------------------------------------
SetClockShowConfirm:
  mov   #$00, Second
  clr1  p3int, $00
  mov   #$00, TextInvert
  mov   #$00, CursorY
  mov   #$05, CursorX
  callf ClearCell8x8
  mov   #<Str_OkPrompt, trl
  mov   #>Str_OkPrompt, trh
  mov   #$00, CursorX
  mov   #$02, CursorY
  callf DrawString
  mov   #$00, acc
  callf DrawYesNoChoice
  set1  p3int, $00
  ret
;; -----------------------------------------------------------------------------
;; ClockAnimationStep ($1805)
;; Called once per second from ClockMode. ClockAnim layout:
;;   bits 7-6 animal (0 dog, 1 fish, 2 bird), bit 5 sprite frame toggle,
;;   bit 4 "resting" (draw the blank sprite), bits 3-0 position counter.
;; AnimSequences holds, per animal, an end marker N followed by N-1 XRAM offsets
;; (lower screen half, XBNK 1); the counter walks 1..N-1 and then wraps, flipping
;; bit 4 so every other pass erases the trail with the blank sprite.
;; -----------------------------------------------------------------------------
ClockAnimationStep:
  push  acc
  push  trh
  push  trl
  push  b
  push  c
  push  $02
  mov   #$01, xbnk
  mov   #<AnimSequences, trl
  mov   #>AnimSequences, trh
  inc   ClockAnim
  ld    ClockAnim
  and   #$C0
  rol
  rol
  st    b
  bz    .lookup
.skipSequence:
  mov   #$00, acc
  ldc
  add   trl
  st    trl
  mov   #$00, acc
  addc  trh
  st    trh
  dbnz  b, .skipSequence
.lookup:
  mov   #$00, acc
  ldc
  st    b
  ld    ClockAnim
  and   #$0F
  xor   b
  bz    .wrap
  ld    ClockAnim
  bp    acc, $04, .resting
  and   #$0F
  ldc
  or    #$80
  st    $02
  mov   #<AnimSprites, trl
  mov   #>AnimSprites, trh
  ld    ClockAnim
  and   #$E0
  ror
  ror
  add   trl
  st    trl
  mov   #$00, acc
  addc  trh
  st    trh
  call  BlitSprite8x8
  not1  ClockAnim, $05
.return:
  pop   $02
  pop   c
  pop   b
  pop   trl
  pop   trh
  pop   acc
  ret
.resting:
  and   #$0F
  ldc
  or    #$80
  st    $02
  mov   #<AnimSpriteBlank, trl
  mov   #>AnimSpriteBlank, trh
  call  BlitSprite8x8
  br    .return
.wrap:
  ld    ClockAnim
  and   #$D0
  st    ClockAnim
  not1  ClockAnim, $04
  inc   ClockAnim
  br    .lookup
;; -----------------------------------------------------------------------------
;; BlitSprite8x8 ($1897)
;; Copy 8 bytes from ROM (TRH:TRL) to XRAM at R2, stepping one LCD line per byte
;; (lines are 6 bytes apart, with a 4-byte gap after every second line).
;; -----------------------------------------------------------------------------
BlitSprite8x8:
  push  acc
  push  b
  push  $02
  mov   #$00, acc
  mov   #$08, b
  push  acc
.loop:
  ldc
  st    @R2
  ld    $02
  and   #$0F
  be    #$05, .nextLine
  bp    psw, cy, .nextLine
  ld    $02
  add   #$04
  st    $02
.nextLine:
  ld    $02
  add   #$06
  st    $02
  pop   acc
  inc   acc
  push  acc
  dbnz  b, .loop
  pop   acc
  pop   $02
  pop   b
  pop   acc
  ret

;; -----------------------------------------------------------------------------
;; AnimSprites ($18CF)
;; Clock animation sprites, 8 bytes each: dog x2, fish x2, bird x2, then a blank one.
;; -----------------------------------------------------------------------------
AnimSprites:
  .byte $00, $08, $8E, $8E, $78, $78, $C8, $84, $00, $08, $8E, $8E, $78, $78, $48, $50
  .byte $30, $18, $BC, $FA, $FE, $BC, $30, $60, $30, $18, $BC, $FA, $FE, $BC, $30, $60
  .byte $E0, $76, $3D, $FE, $7C, $38, $40, $00, $06, $1D, $FE, $7C, $3C, $4E, $02, $00
AnimSpriteBlank:
  .byte $00, $00, $00, $00, $00, $00, $00, $00
AnimSequences:
  .byte $07, $86, $91, $98, $A3, $AA, $B5, $07
  .byte $90, $A1, $92, $A3, $94, $A5, $07, $B0, $A1, $A2, $93, $94, $85

Str_AnimatedDisplay:
  .string 19 "Animated\r\n display"
Str_Bird:
  .string 9 "Bird    "
Str_Dog:
  .string 9 "Dog     "
Str_Fish:
  .string 9 "Fish    "
Str_SetClock:
  .string 19 "Set     \r\n   clock"
Str_SelectHint:
  .byte $1A
  .string 8 ":Select"
Str_OkPrompt:
  .string 9 "OK ?    "

;; -----------------------------------------------------------------------------
;; FileManager ($196F)
;; BiosMode 0 entry (also the return point after copy/delete). Sanity-checks the root
;; block first; FsError bits from this check:
;;   $40 root+$44 (root location) is not 255
;;   $20 root+$46 (FAT location) is not 254 or in $C7-$E6
;;   $10 root+$4A (directory location) is outside $C7-$E5 / $F1-$FD
;; (a directory location in $E6-$F0 fails without setting a bit, showing code 00).
;; Any failure shows "System error" with the FsError code in hex.
;; -----------------------------------------------------------------------------
FileManager:
  mov   #$01, fpr
  mov   #$01, FlashBankTemp
  mov   #$FE, trh
  mov   #$44, trl
  mov   #$00, FsError
  ldf                                   ; root+$44 must be $00FF
  bne   #$FF, .badRoot
  inc   trl
  ldf
  bz    .checkFat
.badRoot:
  ld    FsError
  or    #$40
  st    FsError
.checkFat:
  inc   trl
  ldf
  inc   trl
  be    #$FE, .fatHi
  be    #$C7, .badFat
  bp    psw, cy, .badFat
  be    #$E7, .badFat
  bn    psw, cy, .badFat
.fatHi:
  ldf
  bz    .checkDir
  br    .badFat
.badFat:
  ld    FsError
  or    #$20
  st    FsError
.checkDir:
  mov   #$4A, trl
  ldf
  inc   trl
  be    #$C7, .badDir
  bp    psw, cy, .badDir
  be    #$FE, .badDir
  bn    psw, cy, .badDir
  be    #$E6, .dirHi
  bp    psw, cy, .dirHi
  be    #$F1, .dirHi
  bn    psw, cy, .dirHi
  br    FsSystemError
.dirHi:
  ldf
  bnz   .badDir
  ld    FsError
  bnz   FsSystemError
  br    FileList
.badDir:
  ld    FsError
  or    #$10
  st    FsError
;; -----------------------------------------------------------------------------
;; FsSystemError ($19DB)
;; "System error" + FsError in hex on row 3; waits for MODE or a controller.
;; -----------------------------------------------------------------------------
FsSystemError:
  clr1  p3int, $00
  mov   #<Str_SystemError, trl
  mov   #>Str_SystemError, trh
  mov   #$00, CursorX
  mov   #$00, CursorY
  callf DrawString
  mov   #$01, xbnk
  callf ClearHalfScreen
  ld    FsError
  mov   #$06, CursorX
  mov   #$03, CursorY
  callf DrawHexByte
.wait:
  callf WaitKeyEvent
  be    #$FF, .exit
  bne   #$FD, .wait
.exit:
  jmp   FileManagerExit
;; -----------------------------------------------------------------------------
;; FileList ($1A08)
;; Shows the free-block summary until A or Right is pressed (or ~6.5 s pass), then
;; scans the directory and shows one file at a time. If another VMU is connected
;; (WaitKeyEvent returns $FC) it switches to CopyReceive.
;; Keys in the list: Up/Down step SelectedFile through 1..FileCount (wrapping),
;; Right shows details, B / Left go back to the summary.
;; -----------------------------------------------------------------------------
FileList:
  clr1  p3int, $00
  call  DrawFreeBlocksScreen
  set1  p3int, $00
  mov   #$00, SelectedFileHi            ; SelectedFile = 1
  mov   #$01, SelectedFile
  mov   #$01, IdleTicks
FileList_summaryLoop:
  set1  pcon, $00
  ld    BiosMode
  bz    .stillFileMode
  jmp   FileManagerExit
.stillFileMode:
  ld    SleepCtl
  bnz   FileListScan_sleep
  ld    p7
  and   #$01
  bnz   FileListScan_exit
  ld    IdleTicks
  be    #$0D, FileListScan              ; 13 half-second ticks on the summary screen, then scan anyway
  ld    Buttons_Current
  and   #$18
  bz    FileList_summaryLoop
;; -----------------------------------------------------------------------------
;; FileListScan ($1A34)
;; (Re)scan the directory and draw the current entry. Also the return point after a
;; delete. FileCount == 0 -> FileListEmpty.
;; -----------------------------------------------------------------------------
FileListScan:
  clr1  p3int, $00
  callf ClearScreen
  call  CountFiles
  set1  p3int, $00
  ld    FsError
  bnz   FsSystemError
  ld    FileCount
  bnz   FileListScan_showEntry
  jmp   FileListEmpty
FileListScan_sleep:
  callf SleepUntilWake
  br    FileList_summaryLoop
FileListScan_exit:
  jmp   FileManagerExit
FileListScan_showEntry:
  clr1  p3int, $00
  call  DrawFileCounter
  call  DrawFileEntry
  mov   #$01, IdleTicks
  ld    CopyRxArm                       ; first time here: arm VMU-to-VMU receive
  bnz   FileListLoop
  mov   #$01, CopyRxArm
FileListLoop:
  callf WaitKeyEventRepeat
  be    #$FC, FileListLoop_receive
  be    #$FF, FileListLoop_exit
  be    #$FD, FileListLoop_exit
  be    #$01, FileListNext
  be    #$02, FileListPrev
  be    #$08, FileDetails
  be    #$20, FileList
  be    #$04, FileList
  br    FileListLoop
FileListLoop_receive:
  jmpf  CopyReceive
FileListLoop_exit:
  jmp   FileManagerExit
;; -----------------------------------------------------------------------------
;; FileListNext ($1A80)
;; Select the next file, wrapping to 1 after FileCount.
;; -----------------------------------------------------------------------------
FileListNext:
  inc   SelectedFile
  ld    SelectedFile
  sub   FileCount
  bne   #$01, .redraw
  mov   #$01, SelectedFile
.redraw:
  clr1  p3int, $00
  call  DrawFileEntry
  set1  p3int, $00
  br    FileListLoop
;; -----------------------------------------------------------------------------
;; FileListPrev ($1A94)
;; Select the previous file, wrapping to FileCount below 1.
;; -----------------------------------------------------------------------------
FileListPrev:
  dec   SelectedFile
  ld    SelectedFile
  bnz   .redraw
  ld    FileCount
  st    SelectedFile
.redraw:
  clr1  p3int, $00
  call  DrawFileEntry
  set1  p3int, $00
  br    FileListLoop
;; -----------------------------------------------------------------------------
;; FileDetails ($1AA6)
;; Details for the selected file: 16-char VMS description on rows 1-2, type and size
;; on row 3. Up/Down go straight to the next/previous file, B/Left back to the list,
;; Right opens the Copy/Delete menu. Receiving from another VMU is disarmed here.
;; -----------------------------------------------------------------------------
FileDetails:
  clr1  p3int, $00
  callf ClearScreen
  call  DrawVmsDescription
  ld    FsError
  bnz   .loop
  call  DrawFileType
  call  DrawFileSize
  mov   #$01, IdleTicks
  ld    CopyRxArm
  be    #$FF, .loop
  mov   #$00, CopyRxArm
.loop:
  callf WaitKeyEventRepeat
  be    #$FF, FileListLoop_exit
  be    #$FD, FileListLoop_exit
  be    #$01, .back
  be    #$02, .back
  be    #$08, FileActionMenu
  be    #$20, .back
  be    #$04, .back
  br    .loop
.back:
  clr1  p3int, $00
  callf ClearScreen
  call  DrawFileCounter
  be    #$02, FileListPrev
  be    #$01, FileListNext
  call  DrawFileEntry
  jmp   FileListLoop
;; -----------------------------------------------------------------------------
;; FileActionMenu ($1AEB)
;; "Copy" / "Delete" menu (Up/Down toggles the highlight). A runs the highlighted
;; action (FileCopy / FileDelete), B / Left return to FileDetails.
;; -----------------------------------------------------------------------------
FileActionMenu:
  call  DrawYesHint
.copyHighlighted:
  call  DrawActionMenuCopy
  mov   #$01, IdleTicks
.copyLoop:
  callf WaitKeyEventRepeat
  be    #$FF, FileManagerExit
  be    #$FD, FileManagerExit
  be    #$01, .deleteHighlighted
  be    #$02, .deleteHighlighted
  be    #$10, .doCopy
  be    #$20, FileDetails
  be    #$04, FileDetails
  br    .copyLoop
.doCopy:
  jmpf  FileCopy
.deleteHighlighted:
  call  DrawActionMenuDelete
  mov   #$01, IdleTicks
.deleteLoop:
  callf WaitKeyEventRepeat
  be    #$FF, FileManagerExit
  be    #$FD, FileManagerExit
  be    #$01, .copyHighlighted
  be    #$02, .copyHighlighted
  be    #$10, .doDelete
  be    #$20, .back
  be    #$04, .back
  br    .deleteLoop
.back:
  jmp   FileDetails
.doDelete:
  jmpf  FileDelete
;; -----------------------------------------------------------------------------
;; FileListEmpty ($1B33)
;; "No saved files"; B / Left -> summary, another VMU -> CopyReceive.
;; -----------------------------------------------------------------------------
FileListEmpty:
  clr1  p3int, $00
  mov   #<Str_NoSavedFiles, trl
  mov   #>Str_NoSavedFiles, trh
  mov   #$00, CursorX
  mov   #$00, CursorY
  callf DrawString
  mov   #$01, xbnk
  callf ClearHalfScreen
  mov   #$01, IdleTicks
  mov   #$01, CopyRxArm
.loop:
  callf WaitKeyEvent
  be    #$FC, .receive
  be    #$FF, FileManagerExit
  be    #$FD, FileManagerExit
  be    #$20, .back
  be    #$04, .back
  br    .loop
.back:
  jmp   FileList
.receive:
  jmp   FileListLoop_receive
;; -----------------------------------------------------------------------------
;; FileManagerExit ($1B68)
;; Common exit to MainMenu.
;; -----------------------------------------------------------------------------
FileManagerExit:
  jmpf  MainMenu
;; -----------------------------------------------------------------------------
;; CountFreeUserBlocks ($1B6B)
;; Count $FFFC (free) FAT entries for blocks 0-199 into FreeUserBlocksHi:FreeUserBlocks.
;; -----------------------------------------------------------------------------
CountFreeUserBlocks:
  mov   #$00, FreeUserBlocksHi
  mov   #$00, FreeUserBlocks
  mov   #$01, fpr
  mov   #$01, FlashBankTemp
  mov   #$FE, trh
  mov   #$46, trl   ; Read FAT First (0x1FE46)
  call  PrepareFlashBlockRead
  mov   #$C8, c
.loop:
  ldf
  inc   trl
  be    #$FC, .checkHi
  inc   trl
  br    .next
.checkHi:
  ldf
  inc   trl
  bne   #$FF, .next
  inc   FreeUserBlocks
.next:
  ld    trl
  bnz   .noCarry
  inc   trh
.noCarry:
  dbnz  c, .loop
  ret

.org $1B9E
;; -----------------------------------------------------------------------------
;; CountFreeGameBlocks ($1B9E)
;; Count the free ($FFFC) FAT entries at the very start of the volume (blocks 0-127)
;; into FreeGameBlocks, stopping at the first used block: a game must occupy
;; consecutive blocks from block 0, while data files are allocated from the top.
;; -----------------------------------------------------------------------------
CountFreeGameBlocks:
  mov   #$00, FreeGameBlocksHi
  mov   #$00, FreeGameBlocks
  mov   #$01, fpr
  mov   #$01, FlashBankTemp
  mov   #$FE, trh
  mov   #$46, trl               ; Read FAT First within the root block (0x1FE46)
  call  PrepareFlashBlockRead   ; Load address of FAT into (fpr, trh, trl)
  mov   #$80, c                 ; Count down from $80 (maximum size of the game region / 1st flash bank)
.CheckNextBlock:
  ldf                           ; Check for *free block* (0xfffc, little endian)
  bne   #$FC, .DoneCounting
  inc   trl
  ldf
  bne   #$FF, .DoneCounting
  inc   trl
  inc   FreeGameBlocks             ; Found a free block.
  dbnz  c, .CheckNextBlock
.DoneCounting:
  ret

;; -----------------------------------------------------------------------------
;; DrawFreeBlocksScreen ($1BC7)
;; "Free" / "Game" summary: total free user blocks on row 0 and the number of free
;; blocks at the start of the volume (usable for a game) on row 1.
;; -----------------------------------------------------------------------------
DrawFreeBlocksScreen:
  mov   #$00, CursorX
  mov   #$00, CursorY
  callf ClearScreen
  mov   #<Str_FreeGame, trl
  mov   #>Str_FreeGame, trh
  callf DrawString
  call  CountFreeUserBlocks
  call  CountFreeGameBlocks
  call  CountFreeExtraBlocks
  mov   #FreeUserBlocksHi, $00
  callf Bin16ToBcd
  mov   #MathHi, $00
  mov   #$05, CursorX
  mov   #$00, CursorY
  callf DrawBcd3Digits
  mov   #FreeGameBlocksHi, $00
  callf Bin16ToBcd
  mov   #MathHi, $00
  mov   #$01, CursorY
  callf DrawBcd3Digits
  ret
;; -----------------------------------------------------------------------------
;; CountFiles ($1C01)
;; Walk the directory (following the FAT chain from the root's directory location)
;; and count non-empty entries into FileCountHi:FileCount. A broken chain sets
;; FsError bit 2. Leaves the FAT address in FatBank/FatAddrHi/FatAddrLo.
;; -----------------------------------------------------------------------------
CountFiles:
  mov   #$01, fpr
  mov   #$01, FlashBankTemp
  mov   #$FE, trh
  mov   #$46, trl
  call  PrepareFlashBlockRead
  st    FatBank
  ld    trh
  st    FatAddrHi
  ld    trl
  st    FatAddrLo
  mov   #$FE, trh
  mov   #$4A, trl
  call  PrepareFlashBlockRead
  ld    MathHi
  st    DirBlock
  mov   #$00, FileCountHi
  mov   #$00, FileCount
.block:
  mov   #$10, c
.entry:
  ldf
  bz    .nextEntry
  inc   FileCount
.nextEntry:
  ld    trl
  add   #$20
  st    trl
  ld    trh
  addc  #$00
  st    trh
  dbnz  c, .entry
  ld    FatBank
  st    fpr
  st    FlashBankTemp
  ld    FatAddrHi
  st    trh
  ld    FatAddrLo
  st    trl
  ld    DirBlock
  clr1  psw, cy
  rolc
  st    c
  mov   #$00, acc
  rolc
  st    MathHi
  ld    trl
  add   c
  st    trl
  ld    trh
  add   MathHi
  st    trh
  ldf
  bne   #$FA, .nextBlock
  inc   trl
  ldf
  dec   trl
  be    #$FF, .return
  bz    .nextBlock
  br    .badChain
.nextBlock:
  inc   trl
  ldf
  bnz   .badChain
  dec   trl
  call  PrepareFlashBlockRead
  ld    MathHi
  st    DirBlock
  br    .block
.return:
  ret
.badChain:
  ld    FsError
  or    #$04
  st    FsError
  ret
;; -----------------------------------------------------------------------------
;; CountFreeExtraBlocks ($1C90)
;; Count free FAT entries for blocks 200-230 (the area past the user blocks) into
;; FreeExtraBlocksHi:FreeExtraBlocks. Only used by the copy-receive space check.
;; -----------------------------------------------------------------------------
CountFreeExtraBlocks:
  mov   #$01, fpr
  mov   #$01, FlashBankTemp
  mov   #$FE, trh
  mov   #$46, trl
  call  PrepareFlashBlockRead
  mov   #$90, trl
  inc   trh
  mov   #$00, FreeExtraBlocksHi
  mov   #$00, FreeExtraBlocks
  mov   #$1F, b
.loop:
  ldf
  bne   #$FC, .next
  inc   trl
  ldf
  dec   trl
  bne   #$FF, .next
  inc   FreeExtraBlocks
.next:
  inc   trl
  inc   trl
  dbnz  b, .loop
  ret

;; PRE:
;; (FPR0, trh, trl): Address of a block ID in the FAT
;;
;; POST:
;; (FPR0, trh, trl): Address of the file content
;; acc: MSB of the file content address (same as FPR0)
.org $1CC2
PrepareFlashBlockRead:
  push  b
  push  c
  push  psw
  clr1  psw, rambk0
  ldf                 ; Read FAT Block ID
  st    b
  st    MathHi
  mov   #$02, acc
  mov   #$00, c
; Multiply block ID (stored in b) by FAT block size 0x200 (stored in acc, c)
; This translates the block ID to the address of the file content
  mul
  st    trh           ; Store a8-a15 of file content address to trh
  ld    b
  and   #$01
  st    fpr           ; Store a16 of file content address to FPR0
  st    FlashBankTemp ; Store a16 to a temp also
  ld    c
  st    trl           ; Store a0-a7 of file content address to trl
  ld    FlashBankTemp
  pop   psw
  pop   c
  pop   b
  ret

;; -----------------------------------------------------------------------------
;; DrawFileCounter ($1CED)
;; "  n/ N" on row 0 (current index is drawn by DrawFileEntry) and the "/  /" date
;; separators on row 3. Preserves ACC.
;; -----------------------------------------------------------------------------
DrawFileCounter:
  push  acc
  mov   #<Str_FileCounter, trl
  mov   #>Str_FileCounter, trh
  mov   #$00, CursorX
  mov   #$00, CursorY
  callf DrawString
  mov   #FileCountHi, $00
  callf Bin16ToBcd
  mov   #MathHi, $00
  mov   #$05, CursorX
  callf DrawBcd3Digits
  pop   acc
  ret
;; -----------------------------------------------------------------------------
;; DrawFileEntry ($1D10)
;; Locate entry SelectedFile and draw it: index on row 0, 12-char name on rows 1-2
;; (inverted if the file is copy protected), MM/DD/YY on row 3. On return TRH:TRL
;; point at the entry. If the entry can't be found, "No saved files" + FsError.
;; -----------------------------------------------------------------------------
DrawFileEntry:
  push  CursorX
  push  CursorY
  mov   #SelectedFileHi, $00
  callf Bin16ToBcd
  mov   #MathHi, $00
  mov   #$01, CursorX
  callf DrawBcd3Digits
  mov   #$00, CursorX
  mov   #$01, CursorY
  mov   #$00, TextInvert                ; protected files are drawn inverted
  call  FindDirEntryByIndex
  ld    FsError
  bnz   .notFound
  inc   trl
  ldf
  bne   #$FF, .name
  mov   #$FF, TextInvert
.name:
  inc   trl
  inc   trl
  mov   #$08, c                         ; 8 name characters on row 1
.nameRow1:
  inc   trl
  ldf
  callf DrawChar6x8
  inc   CursorX
  dbnz  c, .nameRow1
  inc   CursorY
  mov   #$00, CursorX
  mov   #$04, c
.nameRow2:
  inc   trl
  ldf
  callf DrawChar6x8
  inc   CursorX
  dbnz  c, .nameRow2
  mov   #$00, TextInvert
  inc   trl
  inc   CursorY
  mov   #$00, CursorX
  inc   trl
  inc   trl
  ldf                                   ; timestamp month
  callf DrawHexByte
  inc   CursorX
  inc   CursorX
  inc   CursorX
  inc   trl
  ldf                                   ; timestamp day
  callf DrawHexByte
  inc   CursorX
  inc   CursorX
  inc   CursorX
  dec   trl
  dec   trl
  ldf                                   ; timestamp year
  callf DrawHexByte
  ld    trl                             ; back to the start of the entry
  sub   #$11
  st    trl
.return:
  pop   CursorY
  pop   CursorX
  ret
.notFound:
  mov   #$00, CursorX
  mov   #$01, CursorY
  mov   #<Str_NoSavedFiles, trl
  mov   #>Str_NoSavedFiles, trh
  callf DrawString
  ld    FsError
  or    #$02
  st    FsError
  mov   #$06, CursorX
  mov   #$03, CursorY
  callf DrawHexByte
  br    .return
;; -----------------------------------------------------------------------------
;; DrawVmsDescription ($1DB7)
;; Follow the file's FAT chain to its header block (entry+$1A = header offset in
;; blocks; must be < 256) and draw the first 16 bytes of the VMS header (the
;; description) on rows 0-1. Any inconsistency -> "File is damaged" + FsError bit 0.
;; -----------------------------------------------------------------------------
DrawVmsDescription:
  push  CursorX
  push  CursorY
  push  FlashBankTemp
  push  trh
  push  trl
  mov   #$00, CursorX
  mov   #$01, CursorY
  mov   #$00, TextInvert
  ld    trl
  add   #$1B
  st    trl
  ldf
  bnz   .damaged
  dec   trl
  ldf
  bz    .headerInFirstBlock
  st    b
  ld    trl
  sub   #$18
  st    trl
.walk:
  inc   trl
  ldf
  bnz   .damaged
  dec   trl
  ldf
  clr1  psw, cy
  rolc
  st    c
  mov   #$00, acc
  rolc
  add   FatAddrHi
  st    trh
  ld    c
  add   FatAddrLo
  st    trl
  ld    FatBank
  st    fpr
  st    FlashBankTemp
  dbnz  b, .walk
  br    .readHeader
.headerInFirstBlock:
  ld    trl
  sub   #$18
  st    trl
.readHeader:
  inc   trl
  ldf
  bnz   .damaged
  dec   trl
  call  PrepareFlashBlockRead
  mov   #$02, b
  mov   #$00, CursorY
.row:
  mov   #$08, c
  mov   #$00, CursorX
.char:
  ldf
  callf DrawChar6x8
  inc   trl
  inc   CursorX
  dbnz  c, .char
  mov   #$01, CursorY
  dbnz  b, .row
.return:
  pop   trl
  pop   trh
  pop   FlashBankTemp
  ld    FlashBankTemp
  st    fpr
  pop   CursorY
  pop   CursorX
  ret
.damaged:
  mov   #$00, CursorX
  mov   #$00, CursorY
  mov   #<Str_FileDamaged, trl
  mov   #>Str_FileDamaged, trh
  callf DrawString
  ld    FsError
  or    #$01
  st    FsError
  mov   #$06, CursorX
  mov   #$03, CursorY
  callf DrawHexByte
  br    .return
;; -----------------------------------------------------------------------------
;; DrawFileType ($1E61)
;; "Data" ($33), "Game" ($CC) or "Other" on row 3.
;; -----------------------------------------------------------------------------
DrawFileType:
  push  FlashBankTemp
  push  trh
  push  trl
  ldf
  be    #$33, .data
  be    #$CC, .game
  mov   #<Str_TypeOther, trl
  mov   #>Str_TypeOther, trh
  br    .draw
.data:
  mov   #<Str_TypeData, trl
  mov   #>Str_TypeData, trh
  br    .draw
.game:
  mov   #<Str_TypeGame, trl
  mov   #>Str_TypeGame, trh
.draw:
  mov   #$00, CursorX
  mov   #$03, CursorY
  callf DrawString
  pop   trl
  pop   trh
  pop   FlashBankTemp
  ld    FlashBankTemp
  st    fpr
  ret
;; -----------------------------------------------------------------------------
;; DrawFileSize ($1E98)
;; Size in blocks (entry+$18) at column 5 of row 2.
;; -----------------------------------------------------------------------------
DrawFileSize:
  push  FlashBankTemp
  push  trh
  push  trl
  ld    trl
  add   #$19
  st    trl
  ldf
  st    MathHi
  dec   trl
  ldf
  st    MathLo
  mov   #MathHi, $00
  callf Bin16ToBcd
  mov   #MathHi, $00
  mov   #$05, CursorX
  mov   #$02, CursorY
  callf DrawBcd3Digits
  pop   trl
  pop   trh
  pop   FlashBankTemp
  ld    FlashBankTemp
  st    fpr
  ret
;; -----------------------------------------------------------------------------
;; DrawYesHint ($1EC9)
;; Clear the bottom half and draw the "A :Yes" hint on row 2.
;; -----------------------------------------------------------------------------
DrawYesHint:
  push  trh
  push  trl
  clr1  p3int, $00
  mov   #$01, xbnk
  callf ClearHalfScreen
  mov   #$00, CursorX
  mov   #$02, CursorY
  mov   #<Str_YesHint, trl
  mov   #>Str_YesHint, trh
  callf DrawString
  set1  p3int, $00
  pop   trl
  pop   trh
  ret
;; -----------------------------------------------------------------------------
;; DrawActionMenuCopy ($1EEB)
;; "Copy" (inverted) and "Delete".
;; -----------------------------------------------------------------------------
DrawActionMenuCopy:
  push  trh
  push  trl
  clr1  p3int, $00
  mov   #$FF, TextInvert
  mov   #<Str_Copy, trl
  mov   #>Str_Copy, trh
  mov   #$00, CursorX
  mov   #$00, CursorY
  callf DrawString
  mov   #$00, TextInvert
  mov   #<Str_Delete, trl
  mov   #>Str_Delete, trh
 ; String prefixes like $EF are ordinary 6x8 font glyphs: $EF bullet, $1A/$1B bold
 ; A/B button icons, $82 right arrow, $85 "No." sign, $17-$1A bold SEGA logo.
  mov   #$01, CursorY
  callf DrawString
  set1  p3int, $00
  pop   trl
  pop   trh
  ret
;; -----------------------------------------------------------------------------
;; DrawActionMenuDelete ($1F19)
;; "Copy" and "Delete" (inverted).
;; -----------------------------------------------------------------------------
DrawActionMenuDelete:
  push  trh
  push  trl
  clr1  p3int, $00
  mov   #<Str_Copy, trl
  mov   #>Str_Copy, trh
  mov   #$00, CursorX
  mov   #$00, CursorY
  callf DrawString
  mov   #<Str_Delete, trl
  mov   #>Str_Delete, trh
  mov   #$FF, TextInvert
  mov   #$01, CursorY
  callf DrawString
  mov   #$00, TextInvert
  set1  p3int, $00
  pop   trl
  pop   trh
  ret
;; -----------------------------------------------------------------------------
;; DrawYesNoChoice ($1F47)
;; "Yes" / "No" on row 3, ACC != 0 highlights Yes, ACC == 0 highlights No.
;; Preserves ACC (the callers keep their choice in it).
;; -----------------------------------------------------------------------------
DrawYesNoChoice:
  push  trh
  push  trl
  bz    .yes
  mov   #$FF, TextInvert
.yes:
  mov   #<Str_Yes, trl
  mov   #>Str_Yes, trh
  mov   #$00, CursorX
  mov   #$03, CursorY
  callf DrawString
  mov   #$00, TextInvert
  bnz   .no
  mov   #$FF, TextInvert
.no:
  mov   #<Str_No, trl
  mov   #>Str_No, trh
  mov   #$04, CursorX
  callf DrawString
  mov   #$00, TextInvert
  pop   trl
  pop   trh
  ret
;; -----------------------------------------------------------------------------
;; FindDirEntryByIndex ($1F7B)
;; Point TRH:TRL (and FPR) at the SelectedFile-th used directory entry (1-based,
;; only types $33/$CC count). Past the end of the directory FsError bit 7 is set.
;; -----------------------------------------------------------------------------
FindDirEntryByIndex:
  push  psw
  clr1  psw, rambk0
  mov   #$01, fpr
  mov   #$01, FlashBankTemp
  mov   #$FE, trh
  mov   #$46, trl
  call  PrepareFlashBlockRead
  st    FatBank
  ld    trh
  st    FatAddrHi
  ld    trl
  st    FatAddrLo
  mov   #$FE, trh
  mov   #$4A, trl
  call  PrepareFlashBlockRead
  ld    MathHi
  st    DirBlock
  mov   #$00, b
.block:
  mov   #$10, c
.entry:
  ldf
  be    #$33, .used
  be    #$CC, .used
  br    .next
.used:
  inc   b
  ld    SelectedFile
  sub   b
  bz    .return
.next:
  ld    trl
  add   #$20
  st    trl
  ld    trh
  addc  #$00
  st    trh
  dbnz  c, .entry
  callf DirNextBlock
  ld    FsError
  bnz   .end
  br    .block
.return:
  pop   psw
  ret
.end:
  ld    FsError
  or    #$80
  st    FsError
  br    .return
;; -----------------------------------------------------------------------------
;; FindDataFileByName ($1FDD)
;; Search the directory for a data file ($33) whose name matches the 12 bytes at
;; bank 1 $29 (the name received from the other VMU). Out: ACC = $FF found, 0 not.
;; -----------------------------------------------------------------------------
FindDataFileByName:
  push  psw
  clr1  psw, rambk0
  mov   #$01, fpr
  mov   #$01, FlashBankTemp
  mov   #$FE, trh
  mov   #$46, trl
  call  PrepareFlashBlockRead
  st    FatBank
  ld    trh
  st    FatAddrHi
  ld    trl
  st    FatAddrLo
  mov   #$FE, trh
  mov   #$4A, trl
  callf PrepareFlashBlockRead
  ld    MathHi
  st    DirBlock
.block:
  mov   #$10, c
.entry:
  ldf
  be    #$33, .compare
  br    .next
.compare:
  callf CompareFileName
  bz    .found
.next:
  ld    trl
  add   #$20
  st    trl
  ld    trh
  addc  #$00
  st    trh
  dbnz  c, .entry
  callf DirNextBlock
  ld    FsError
  bnz   .notFound
  br    .block
.notFound:
  ld    FsError
  and   #$7F
  st    FsError
  mov   #$00, acc
.return:
  pop   psw
  ret
.found:
  ld    FsError
  and   #$7F
  st    FsError
  mov   #$FF, acc
  br    .return
;; -----------------------------------------------------------------------------
;; DirNextBlock ($2043)
;; Follow the FAT from DirBlock to the next directory block and point TRH:TRL at it.
;; End of chain ($FFFA) or a bad link sets FsError bit 7.
;; -----------------------------------------------------------------------------
DirNextBlock:
  push  psw
  clr1  psw, rambk0
  ld    FatBank
  st    fpr
  st    FlashBankTemp
  ld    FatAddrHi
  st    trh
  ld    FatAddrLo
  st    trl
  ld    DirBlock
  clr1  psw, cy
  rolc
  st    c
  mov   #$00, acc
  rolc
  st    MathHi
  ld    trl
  add   c
  st    trl
  ld    trh
  add   MathHi
  st    trh
  ldf
  bne   #$FA, .follow
  inc   trl
  ldf
  dec   trl
  be    #$FF, .end
  bz    .follow
  br    .end
.follow:
  inc   trl
  ldf
  bnz   .end
  dec   trl
  callf PrepareFlashBlockRead
  ld    MathHi
  st    DirBlock
.return:
  pop   psw
  ret
.end:
  ld    FsError
  or    #$80
  st    FsError
  br    .return
;; -----------------------------------------------------------------------------
;; CompareFileName ($2097)
;; Compare the name of the entry at TRH:TRL (+4, 12 bytes) with bank 1 $29..$34.
;; Out: ACC = 0 if equal.
;; -----------------------------------------------------------------------------
CompareFileName:
  push  psw
  set1  psw, rambk0
  push  trh
  push  trl
  push  b
  push  $00
  ld    trl
  add   #$04
  st    trl
  mov   #$29, $00
  mov   #$0C, b
.loop:
  ldf
  xor   @R0
  inc   $00
  inc   trl
  bnz   .return
  dbnz  b, .loop
.return:
  pop   $00
  pop   b
  pop   trl
  pop   trh
  pop   psw
  ret

Str_FreeGame:
  .string 11 "Free\r\nGame"
Str_FileCounter:
  .byte $85  
  .string 20 "   /   \r\r\r\n  /  /  "

Str_SystemError:
  .string 19 "System  \r\n   error"
Str_NoSavedFiles:
  .string 19 "No saved\r\n   files"
Str_FileDamaged:
  .string 19 "File is \r\n damaged"
Str_Copy:
  .byte $EF
  .string 8 "Copy   "
Str_Delete:
  .byte $EF
  .string 8 "Delete "
Str_YesHint:
  .byte $1A
  .string 6 ":Yes\r\n"
Str_NoHint:
  .byte $1B
  .string 5 ":No "
Str_Yes:
  .string 5 "Yes "
Str_No:
  .string 5 " No "
Str_TypeData:
  .string 7 "Data   "
  .byte  $82
  .byte  $00
Str_TypeGame:
  .string 7 "Game   "
  .byte  $82
  .byte  $00
Str_TypeOther:
  .string 7 "Other  "
  .byte  $82
  .byte  $00

;; -----------------------------------------------------------------------------
;; FileCopy ($2162)
;; "Copy ?" for the selected file (TRH:TRL = its directory entry). Copy-protected files
;; get "Unable to copy". On Yes: if another VMU is plugged into the top connector
;; (P7.3 set, P7.0 clear) start CopySend, otherwise show "Connect VM" with a spinner
;; until one appears ($FC) or B is pressed.
;; -----------------------------------------------------------------------------
FileCopy:
  inc   trl
  ldf
  dec   trl
  bne   #$FF, .confirm                  ; copy protect byte = $FF?
  jmp   FileCopyProtected
.confirm:
  call  DrawCopyPrompt
  mov   #$00, c
  callf WaitAllButtonsReleased
  mov   #$01, IdleTicks
  mov   #$00, SleepCtl
.confirmLoop:
  callf WaitKeyEvent
  be    #$FF, FileCopy_exit
  be    #$FD, FileCopy_exit
  be    #$20, .cancel
  be    #$04, .toggle
  be    #$08, .toggle
  be    #$10, .select
  br    .confirmLoop
.toggle:
  ld    c
  xor   #$FF
  st    c
  callf DrawYesNoChoice
  callf WaitDpadReleased
  br    .confirmLoop
.select:
  ld    c
  bnz   .yes
.cancel:
  jmpf  FileActionMenu
.yes:
  mov   #$00, HalfSecTicks
  ld    p7                              ; another VMU connected and no controller?
  and   #$09
  bne   #$08, .waitForVmu
  jmp   CopySend
.waitForVmu:
  clr1  p3int, $00
  call  DrawConnectVmu
  mov   #$01, IdleTicks
  mov   #$F0, c                         ; spinner: font characters $F0-$F7
  mov   #$01, CopyRxArm
.spinLoop:
  callf WaitKeyEventSlow
  be    #$FF, FileCopy_exit
  be    #$FD, FileCopy_exit
  be    #$FC, .connected
  be    #$20, .cancel
  ld    c
  and   #$FC
  be    #$F4, .drawSpinner
  ld    c
  bne   #$F8, .drawSpinner
  and   #$F0
  st    c
.drawSpinner:
  mov   #$07, CursorX
  mov   #$03, CursorY
  callf DrawChar6x8
  inc   c
  br    .spinLoop
.connected:
  mov   #$FF, CopyRxArm
  jmp   FileCopy
FileCopy_exit:
  jmpf  FileManagerExit
;; -----------------------------------------------------------------------------
;; FileCopyProtected ($21F3)
;; "Unable to copy" until B / Left.
;; -----------------------------------------------------------------------------
FileCopyProtected:
  push  trh
  push  trl
  clr1  p3int, $00
  mov   #$01, xbnk
  callf ClearHalfScreen
  mov   #<Str_UnableToCopy, trl
  mov   #>Str_UnableToCopy, trh
  mov   #$00, CursorX
  mov   #$00, CursorY
  callf DrawString
  pop   trl
  pop   trh
  callf WaitAllButtonsReleased
  mov   #$01, IdleTicks
.loop:
  callf WaitKeyEvent
  be    #$FF, FileCopy_exit
  be    #$FD, FileCopy_exit
  be    #$20, .back
  be    #$04, .back
  br    .loop
.back:
  jmpf  FileActionMenu
;; -----------------------------------------------------------------------------
;; CopySend ($222C)
;; Send the selected file over SIO to the other VMU. Packet sequence (the receiver
;; acks every header with $0C, see CheckPeerReadyToReceiveMessage):
;;   [$11 $02 type size $FF]     file info
;;   [$1B $06 name(12) $FF]      file name
;;   per 128-byte page: [$5x $04 data(128)] then [$10 $08 $00 $FF]
;;   [$1B $03 entry+$10..$1B $FF] timestamp, size, header offset
;;   [$10 $08 $00 $FF]            done
;; A $0A answer to the name packet means the receiver already has a file with that
;; name; a $0A after the info packet means it has no room.
;; -----------------------------------------------------------------------------
CopySend:
  mov   #$81, ocr                       ; OCR $81: run from the RC oscillator
  mov   #$FF, CopyRxArm
  call  InitializeSerialIO
  mov   #$00, CursorX
  mov   #$02, CursorY
  clr1  p3int, $00                      ; "Copying!" on row 2
  mov   #$01, xbnk
  callf ClearHalfScreen
  push  trh
  push  trl
  mov   #<Str_Copying, trl
  mov   #>Str_Copying, trh
  callf DrawString
  pop   trl
  pop   trh
  mov   #$00, sbuf1                     ; bank 1 $10.. = DataToTransmit, $28.. = DataTransmitted
  set1  psw, rambk0
  mov   #DataToTransmit, $00
  mov   #DataTransmitted, $01
  mov   #$11, @R0
  inc   $00
  mov   #$02, @R0
  inc   $00
  ldf                 ; Read file Type (Directory 0x00) https://vmu.falcogirgis.net/filesystem.html#fs_dir
  st    @R0
  inc   $00
  push  trl
  ld    trl
  add   #$18
  st    trl
  ldf                 ; Read file block count (Directory 0x18)
  pop   trl
  st    @R0
  st    CopyBlocksLeft                  ; CopyBlocksLeft = file size in blocks
  inc   $00
  mov   #$FF, @R0
  mov   #$04, b       ; Number of bytes to send
  mov   #DataToTransmit, $00
  mov   #DataTransmitted, $01
  call  SerialTxMultiple
  bnz   FailTransfer
  call  VerifyDataPostTx
  bnz   FailTransfer
  call  CheckPeerReadyToReceiveMessage
  bne   #$0A, .sendName                 ; $0A after the info packet: no room on the other side
  jmp   CopyFailNoRoom
.sendName:
  mov   #DataToTransmit, $00
  mov   #$1B, @R0
  inc   $00
  mov   #$06, @R0
  inc   $00
  push  trh
  push  trl
  ld    trl
  add   #$04
  st    trl
  mov   #$0C, b
.loop:
  ldf
  st    @R0
  inc   trl
  inc   $00
  dbnz  b, .loop
  pop   trl
  pop   trh
  mov   #$FF, @R0
  mov   #$0E, b
  mov   #DataToTransmit, $00
  mov   #DataTransmitted, $01
  call  SerialTxMultiple
  bnz   FailTransfer
  call  VerifyDataPostTx
  bnz   FailTransfer
  call  CheckPeerReadyToReceiveMessage
  set1  scon1, $01                      ; keep receiving
  be    #$0A, CopyFailSameFile          ; $0A after the name: same file exists
  call  CopySendFileBlocks
  bnz   FailTransfer
  call  CopySendDirTail
  bnz   FailTransfer
  clr1  psw, rambk0
  call  DrawCopied
;; -----------------------------------------------------------------------------
;; CopyFinished ($22DF)
;; Restore P1/SIO, back to the quartz clock, and wait for A before returning to the
;; file manager. Also reached after a failure or "Not enough memory".
;; -----------------------------------------------------------------------------
CopyFinished:
  call  SerialRestorePorts
  mov   #$A3, ocr
  callf WaitAllButtonsReleased
  mov   #$01, IdleTicks
  mov   #$00, SleepCtl
  mov   #$00, BiosMode
.waitA:
  callf WaitKeyEvent
  be    #$FF, .exit
  be    #$FD, .exit
  be    #$10, .restart
  br    .waitA
.exit:
  jmpf  FileManagerExit
.restart:
  mov   #$00, CopyRxArm
  jmpf  FileManager

.org $2307
FailTransfer:
  ld    p7
  and   #$09
  bne   #$08, .Fail   ; Other VMU not connected. Skip sending a message.
  call  CheckPeerReadyToReceiveMessage
  be    #$0A, .Fail   ; Other VMU not ready to receive a message. Skip sending it.
  ; Write message 0x10, 0xb, 0x0, 0xff into DataToTransmit array
  mov   #DataToTransmit, $00
  mov   #$10, @R0
  inc   $00
  mov   #$0B, @R0
  inc   $00
  mov   #$00, @R0
  inc   $00
  mov   #$FF, @R0
  mov   #DataToTransmit, $00
  mov   #DataTransmitted, $01
  ; Send the failure message to the other VMU
  call  SerialTxMultiple
.Fail:
  clr1  psw, rambk0
  call  IndicateCopyFailed  ; Display failure message on the local VMU
  br    CopyFinished
CopyFailNoRoom:
  clr1  psw, rambk0
  call  DrawNotEnoughMemory
  br    CopyFinished
CopyFailSameFile:
  clr1  psw, rambk0
  call  DrawSameFileExists
  br    CopyFinished
;; -----------------------------------------------------------------------------
;; CopySendFileBlocks ($233E)
;; Walk the file's FAT chain (CopyBlocksLeft blocks) and send every block as four
;; 128-byte pages (CopySendPage), each followed by a [$10 $08 $00 $FF] packet.
;; Out: ACC = 0 ok, $FF on any transfer error.
;; -----------------------------------------------------------------------------
CopySendFileBlocks:
  push  b
  push  c
  clr1  psw, rambk0
  push  FlashBankTemp
  set1  psw, rambk0
  push  trh
  push  trl
  mov   #$01, fpr
  clr1  psw, rambk0
  mov   #$01, FlashBankTemp
  mov   #$FE, trh
  mov   #$46, trl
  callf PrepareFlashBlockRead
  set1  psw, rambk0
  st    $54
  ld    trh
  st    $55
  ld    trl
  st    $56
  pop   trl
  pop   trh
  clr1  psw, rambk0
  pop   FlashBankTemp
  ld    FlashBankTemp
  st    fpr
  push  FlashBankTemp
  push  trh
  push  trl
  ld    trl
  add   #$02
  st    trl
.block:
  clr1  psw, rambk0
  callf PrepareFlashBlockRead
  set1  psw, rambk0
  st    FmBank
  ld    trh
  st    FmAddrHi
  ld    trl
  st    FmAddrLo
  mov   #$04, c
.page:
  push  c
  call  CopySendPage
  bnz   .fail
  callf FlashVerifyEntry                ; FM_VRF (result unused)
  mov   #DataToTransmit, $00
  mov   #$10, @R0
  inc   $00
  mov   #$08, @R0
  inc   $00
  mov   #$00, @R0
  inc   $00
  mov   #$FF, @R0
  mov   #$03, b
  call  CheckPeerReadyToReceiveMessage
  be    #$0A, .fail
  mov   #DataToTransmit, $00
  mov   #DataTransmitted, $01
  call  SerialTxMultiple
  bnz   .fail
  call  VerifyDataPostTx
  bnz   .fail
  ld    FmAddrLo                        ; next 128 bytes
  add   #$80
  st    FmAddrLo
  mov   #$00, acc
  addc  FmAddrHi
  st    FmAddrHi
  pop   c
  dbnz  c, .page
  ld    $54                             ; FAT entry of this block -> next block number
  st    fpr
  clr1  psw, rambk0
  st    FlashBankTemp
  set1  psw, rambk0
  ld    FmBank
  and   #$01
  add   $55
  st    trh
  ld    FmAddrHi
  and   #$FE
  add   $56
  dec   acc
  dec   acc
  st    trl
  dbnz  CopyBlocksLeft, .block
  pop   trl
  pop   trh
  clr1  psw, rambk0
  pop   FlashBankTemp
  ld    FlashBankTemp
  st    fpr
  set1  psw, rambk0
  pop   c
  pop   b
  mov   #$00, acc
  ret
.fail:
  pop   c
  pop   trl
  pop   trh
  clr1  psw, rambk0
  pop   FlashBankTemp
  ld    FlashBankTemp
  st    fpr
  set1  psw, rambk0
  pop   c
  pop   b
  mov   #$FF, acc
  ret
;; -----------------------------------------------------------------------------
;; CopySendDirTail ($2426)
;; Send [$1B $03 entry+$10..$1B $FF] (timestamp, size, header offset) and the final
;; [$10 $08 $00 $FF]. Out: ACC = 0 ok, $FF on error.
;; -----------------------------------------------------------------------------
CopySendDirTail:
  push  b
  clr1  psw, rambk0
  push  FlashBankTemp
  set1  psw, rambk0
  push  trh
  push  trl
  mov   #DataToTransmit, $00
  mov   #$1B, @R0
  inc   $00
  mov   #$03, @R0
  inc   $00
  ld    trl
  add   #$10
  st    trl
  mov   #$0C, b
.loop:
  ldf
  st    @R0
  inc   trl
  inc   $00
  dbnz  b, .loop
  mov   #$FF, @R0
  mov   #$0E, b
  call  CheckPeerReadyToReceiveMessage
  be    #$0A, .fail
  mov   #DataToTransmit, $00
  mov   #DataTransmitted, $01
  call  SerialTxMultiple
  bnz   .fail
  call  VerifyDataPostTx
  bnz   .fail
  mov   #DataToTransmit, $00
  mov   #$10, @R0
  inc   $00
  mov   #$08, @R0
  inc   $00
  mov   #$00, @R0
  inc   $00
  mov   #$FF, @R0
  mov   #$03, b
  call  CheckPeerReadyToReceiveMessage
  be    #$0A, .fail
  mov   #DataToTransmit, $00
  mov   #DataTransmitted, $01
  call  SerialTxMultiple
  bnz   .fail
  call  VerifyDataPostTx
  bnz   .fail
  mov   #$00, acc
.return:
  pop   trl
  pop   trh
  clr1  psw, rambk0
  pop   FlashBankTemp
  push  acc
  ld    FlashBankTemp
  st    fpr
  pop   acc
  set1  psw, rambk0
  pop   b
  ret
.fail:
  mov   #$FF, acc
  br    .return
;; -----------------------------------------------------------------------------
;; CopySendPage ($24AB)
;; FM_PRD the 128 bytes at FmBank/FmAddrHi/FmAddrLo into bank 1 $80-$FF and send it as
;; [$50 $04 data] from $7E (the two header bytes overwrite FmAddrHi/FmAddrLo, which are
;; saved and restored around the send). Out: ACC = 0 ok.
;; -----------------------------------------------------------------------------
CopySendPage:
  callf FlashReadEntry
  push  FmBank
  push  FmAddrHi
  push  FmAddrLo
  mov   #FmAddrHi, $00
  mov   #$50, @R0
  inc   $00
  mov   #$04, @R0
  mov   #$82, b
  call  CheckPeerReadyToReceiveMessage
  be    #$0A, .fail
  mov   #FmAddrHi, $00
  mov   #FmAddrHi, $01
  call  SerialTxMultiple
  bnz   .fail
  call  CheckDataPacketEcho
  bnz   .fail
  mov   #$00, acc
.return:
  pop   FmAddrLo
  pop   FmAddrHi
  pop   FmBank
  ret
.fail:
  mov   #$FF, acc
  br    .return

;; PRE:
;; b: number of bytes to send
;; r0: pointer to data to transmit
;; r1: pointer to data we finished transmitting
;; - scon1, 3 (transfer start) should be set already
;;
;; POST:
;; acc: ff on failure, 0 on success
;;
;; Note: SIO0 interrupt is generally enabled while SIO1 interrupt is disabled when this is used
.org $24E2
SerialTxMultiple:
  mov   #$01, NBytesToSend
  clr1  psw, rambk0
  mov   #$00, HalfSecTicks     ; Reset HalfSecTicks to 0
  set1  psw, rambk0
  set1  scon1, $03              ; Begin receiving
  call  SerialTxOneByte         ; Send the first byte in @R0
.WaitForRx:
  set1  pcon, $00               ; Enter halt mode
  push  psw
  clr1  psw, rambk0
  ld    HalfSecTicks           ; Check serial timeout
  pop   psw
  be    #$06, .ErrReturn
  bn    psw, cy, .ErrReturn     ; Fail if HalfSecTicks >= 6
  ld    p7                      ; Check if other VMU connected
  and   #$09
  bne   #$08, .ErrReturn        ; Fail if other VMU not connected
  bn    scon1, $01, .WaitForRx  ; Keep waiting if rx not finished
  clr1  scon1, $01
  ld    sbuf1                   ; Load received data
  bne   #$E0, .ErrReturn        ; Fail if received something besides $E0 from other VMU
  inc   $00                     ; Inc tx data pointer (preparing to send rest of data)
  ld    b                       ; Load number of bytes to send
  dec   $01                     ; Dec pointer to data we finished transmitting (why??)
  st    NBytesToSend            ; Store number of bytes we will send
  st    NBytesToVerify          ; Store number of bytes we will verify after sending
  mov   #$00, sbuf1             ; Clear rx data
  clr1  scon1, $01              ; Clear receive end flag
  set1  scon1, $03              ; Start receiving again
  call  SerialTxOneByte         ; Send the next byte
  inc   $00                     ; Inc tx data pointer
  clr1  psw, rambk0
  mov   #$00, HalfSecTicks     ; Reset serial timeout
  set1  psw, rambk0
.WaitToSendNextByte:
  set1  pcon, $00
  clr1  psw, rambk0
  ld    HalfSecTicks           ; Check serial timeout
  set1  psw, rambk0
  be    #$06, .ErrReturn
  bn    psw, cy, .ErrReturn     ; Fail if HalfSecTicks >= 6
  ld    p7                      ; Check if other VMU connected
  and   #$09
  bne   #$08, .ErrReturn        ; Fail if other VMU not connected
  ld    NBytesToSend            ; Check if we have more bytes to send (note that 'HandleIntSIO0' decrements this)
  bnz   .WaitToSendNextByte
  mov   #$00, acc
  ret
.ErrReturn:
  mov   #$FF, acc
  ret

;; PRE:
;; - Psw,1 is set (Ram bank 1 is being used)
;; - NBytesToVerify contains how far we should seek
;; POST:
;; - acc=0: Success
;; - acc!=0: Failure
;;
;; Verify that the data we intended to transmit (stored at $10)
;; is the same as the data we actually transmitted (stored at $28)
.org $254E
VerifyDataPostTx:
  mov   #DataToTransmit, $00
  mov   #DataTransmitted, $01
.VerifyOneByte:
  ld    @R0
  xor   @R1
  bnz   .End                ; Failure case (acc!=0)
  inc   $00
  inc   $01
  dbnz  NBytesToVerify, .VerifyOneByte ; Verify next byte, or success case (acc=0)
.End:
  ret

;; -----------------------------------------------------------------------------
;; CheckDataPacketEcho ($2560)
;; After a data packet: the first two bytes looped back must still be $50 $04.
;; -----------------------------------------------------------------------------
CheckDataPacketEcho:
  mov   #FmAddrHi, $00
  mov   #$50, acc
  xor   @R0
  bnz   .fail
  mov   #$04, acc
  inc   $00
  xor   @R0
  bnz   .fail
  mov   #$00, acc
  ret
.fail:
  mov   #$FF, acc
  ret

;; Postconditions:
;; - acc=0: Happy case
;; - acc=0xa: Sad case
.org $2579
CheckPeerReadyToReceiveMessage:
  push  psw
  clr1  psw, rambk0             ; Use ram bank 0
  mov   #$00, HalfSecTicks
.Wait:
  ld    HalfSecTicks
  be    #$06, .Fail
  bn    psw, cy, .Fail          ; Fail if !(timeout < 6)
  bn    scon1, $01, .Wait       ; Keep waiting if receive end flag not set
  clr1  scon1, $01              ; Finished receiving. Clear the end flag
  ld    sbuf1
  bz    .Wait                   ; We received zero. Wait to receive another serial byte.
  bne   #$0C, .Fail             ; Received unexpected value. Assume peer is not ready.
  pop   psw
  mov   #$00, acc
  ret
.Fail:
  pop   psw
  mov   #$0A, acc
  ret

;; Called to wait for interrupt-driven, multi-byte SIO0 transfer to complete.
.org $25A0
WaitUntilAllBytesSent:
  set1  pcon, $00             ; Enter halt mode
  ld    NBytesToSend
  bnz   WaitUntilAllBytesSent ; Repeat if still have bytes to send
  ret

;; Setup a bunch of registers to prepare to perform serial I/O.
.org $25A7
InitializeSerialIO:
  mov   #$F8, sbr     ; Set baud rate
  mov   #$40, p1      ; Enable SO1 data output
  mov   #$8D, p1fcr
  mov   #$8D, p1ddr
  mov   #$04, scon0   ; Use MSB first transmit order
  mov   #$00, sbuf0
  mov   #$04, scon1   ; Use MSB first receive order
  mov   #$00, sbuf1
  mov   #$FF, BatteryCheck
  ret

;; -----------------------------------------------------------------------------
;; SerialRestorePorts ($25C3)
;; Undo InitializeSerialIO: P1 back to its idle configuration, IP = 0, re-enable the
;; automatic battery check.
;; -----------------------------------------------------------------------------
SerialRestorePorts:
  mov   #$40, p1
  mov   #$80, p1ddr
  mov   #$BF, p1fcr
  mov   #$00, ip
  mov   #$00, BatteryCheck
  ret

;; PRE:
;; R0: Pointer to data to send
;;
;; POST:
;; Have started (but not completed) transmitting
.org $25D3
SerialTxOneByte:
  clr1  scon0, $01    ; Clear transfer end flag
  ld    @R0           ; Read data to send
  st    sbuf0         ; Store in transmit buffer
  set1  scon0, $00    ; Enable SIO0 interrupt
  mov   #$16, acc     ; Busy wait
.BusyWait:
  nop
  dbnz  acc, .BusyWait
  set1  scon0, $03    ; Done waiting, start transfer
  ret

.org $25E4
HandleIntSIO0:
  push  acc
  clr1  scon0, $01        ; Clear transfer end flag
  ld    sbuf0             ; Load transmitted data
  push  psw
  set1  psw, rambk0       ; Use main memory bank 1
  st    @R1               ; Store the data we transmitted
  inc   $01               ; Inc transmitted data pointer
  dbnz  NBytesToSend, .MoreBytesToSend
  pop   psw
  clr1  scon0, $00        ; Disable SIO0 interrupt
  pop   acc
  ret
.MoreBytesToSend:
  mov   #$0E, acc         ; Delay before starting next transfer
.BusyWait:
  nop
  dbnz  acc, .BusyWait
  ld    @R0               ; Read the next byte to transmit
  st    sbuf0
  inc   $00               ; Inc tx data pointer
  set1  scon0, $03        ; Start transmitting
  pop   psw
  pop   acc
  ret

;; -----------------------------------------------------------------------------
;; IsrSio1 ($260E)
;; SIO1 (receive) interrupt: store SBUF1 at bank 1 @R1++, re-arm, and stop receiving
;; (SCON1 = $04) when NBytesToReceive reaches 0.
;; -----------------------------------------------------------------------------
IsrSio1:
  push  acc
  clr1  scon1, $01
  ld    sbuf1
  set1  scon1, $03
  push  psw
  set1  psw, rambk0
  st    @R1
  inc   $01
  dbnz  NBytesToReceive, .return
  mov   #$04, scon1
.return:
  pop   psw
  pop   acc
  ret
;; -----------------------------------------------------------------------------
;; SwitchToCfClock ($2628)
;; Start the ceramic (CF) oscillator while still running from RC (OCR $80), give it
;; ~100 loops to settle, then run from it: OCR = $12 (CF, 1/12, RC stopped).
;; -----------------------------------------------------------------------------
SwitchToCfClock:
  mov   #$81, ocr
  ld    ocr
  and   #$FC
  st    ocr
  mov   #$64, acc
.delay:
  dbnz  acc, .delay
  mov   #$12, ocr
  ret
;; -----------------------------------------------------------------------------
;; DrawCopyPrompt ($263B)
;; File name on rows 0-1, "Copy ?" on row 2 and the Yes/No choice (No highlighted).
;; -----------------------------------------------------------------------------
DrawCopyPrompt:
  push  trh
  push  trl
  clr1  p3int, $00
  callf ClearScreen
  mov   #$00, CursorX
  mov   #$00, CursorY
  ld    trl
  add   #$04
  st    trl
  mov   #$08, c
  mov   #$02, b
.loop:
  ldf
  callf DrawChar6x8
  inc   trl
  inc   CursorX
  dbnz  c, .loop
  inc   CursorY
  mov   #$00, CursorX
  mov   #$04, c
  dbnz  b, .loop
  mov   #<Str_CopyPrompt, trl
  mov   #>Str_CopyPrompt, trh
  mov   #$00, CursorX
  mov   #$02, CursorY
  callf DrawString
  mov   #$00, acc
  callf DrawYesNoChoice
  set1  p3int, $00
  pop   trl
  pop   trh
  ret
;; -----------------------------------------------------------------------------
;; DrawCopied ($2688)
;; "Copied" on row 2.
;; -----------------------------------------------------------------------------
DrawCopied:
  push  trh
  push  trl
  clr1  p3int, $00
  mov   #$00, CursorX
  mov   #$02, CursorY   ; Load string "Copied  "
  mov   #<Str_Copied, trl
  mov   #>Str_Copied, trh
  callf DrawString
  set1  p3int, $00
  pop   trl
  pop   trh
  ret

.org $26A4
IndicateCopyFailed:
  push  trh
  push  trl
  clr1  p3int, $00  ; Disable P3 interrupt
  mov   #$00, CursorX
  mov   #$02, CursorY
  mov   #<Str_CopyFailed, trl
  mov   #>Str_CopyFailed, trh
  callf DrawString
  set1  p3int, $00  ; Enable P3 interrupt
  pop   trl
  pop   trh
  ret

DrawNotEnoughMemory:
  push  trh
  push  trl
  clr1  p3int, $00
  mov   #$00, CursorX
  mov   #$00, CursorY
  mov   #<Str_NotEnoughMemory, trl
  mov   #>Str_NotEnoughMemory, trh
  callf DrawString
  set1  p3int, $00
  pop   trl
  pop   trh
  ret
DrawSameFileExists:
  push  trh
  push  trl
  clr1  p3int, $00
  mov   #$00, CursorX
  mov   #$01, CursorY
  mov   #<Str_SameFileExists, trl
  mov   #>Str_SameFileExists, trh
  callf DrawString
  set1  p3int, $00
  pop   trl
  pop   trh
  ret
;; -----------------------------------------------------------------------------
;; DrawConnectVmu ($26F8)
;; Clear the bottom half and draw "Connect VM" (the spinner supplies the "U").
;; -----------------------------------------------------------------------------
DrawConnectVmu:
  push  trh
  push  trl
  mov   #$01, xbnk
  callf ClearHalfScreen
  mov   #<Str_ConnectVm, trl
  mov   #>Str_ConnectVm, trh
  mov   #$00, CursorX
  mov   #$02, CursorY
  callf DrawString
  pop   trl
  pop   trh
  ret

Str_CopyPrompt:
  .string 9 "Copy ?  "
Str_Copying:
  .string 9 "Copying!"
Str_Copied:
  .string 9 "Copied  "
Str_CopyFailed:
  .string 19 "Copy    \r\n  failed"
Str_NotEnoughMemory:
  .string 39 "Not     \r\n enough \r\n  free  \r\n  memory"
Str_SameFileExists:
  .string 29 "Same    \r\n file   \r\n  exists"
Str_UnableToCopy:
  .string 19 "Unable  \r\n to copy"
Str_ConnectVm:
  .string 19 "Connect \r\nVM      "

;; -----------------------------------------------------------------------------
;; CopyReceive ($27AE)
;; Another VMU was plugged in while browsing files. Show "Waiting for data", count the
;; free blocks and load the FAT into Maple work RAM (it is used as a 512-byte scratch
;; copy of the FAT for the whole transfer). Then wait for a header packet ($1x).
;; A+B together cancels.
;;   info packet  [$02 type size]: room check (free game blocks for $CC, free user
;;                blocks otherwise), answer $0A if it doesn't fit
;;   name packet  [$06 name(12)]: $0A if a data file with that name exists
;;   data packets: CopyReceiveBlocks writes them straight to newly allocated blocks
;;   tail packet  [$03 ...]: copied into the new directory entry
;;   done packet  [$08]: CopyCommitFile writes FAT + directory
;; -----------------------------------------------------------------------------
CopyReceive:
  mov   #$81, ocr
  call  SwitchToCfClock
  call  IndicateWaitingForData
  callf CountFreeUserBlocks
  callf CountFreeGameBlocks
  call  InitializeSerialIO
  mov   #$E0, sbr
  clr1  psw, rambk0
  mov   #$40, SleepCtl
  set1  psw, rambk0
  call  LoadFatToWram                   ; FAT -> work RAM
  mov   #DataTransmitted, $01
  mov   #$20, ip                        ; IP: SIO1 has priority
  mov   #$00, sbuf1
  set1  scon1, $03      ; Start receiving
.waitHeader:
  callf WaitKeyEventSlow
  be    #$FD, .modeChanged
  push  psw
  clr1  psw, rambk0
  ld    Buttons_Current                 ; A+B held -> cancel
  pop   psw
  be    #$30, .cancel
  ld    p7              ; Check other VMU still connected
  and   #$09
  bne   #$08, .abort
  ld    sbuf1
  bz    .waitHeader
  and   #$F0
  be    #$10, .gotHeader
  set1  scon1, $03      ; Start receiving
  br    .waitHeader
.cancel:
  clr1  psw, rambk0
  mov   #$FF, CopyRxArm
.abort:
  jmp   SerialTeardown
.modeChanged:
  jmp   CopyReceiveCancel
.gotHeader:
  clr1  p3int, $00
  ld    sbuf1
  and   #$0F                            ; payload length is in the low nibble
  clr1  scon1, $01
  inc   acc
  inc   acc
  st    RxPayloadSize
  inc   acc
  st    NBytesToReceive
  call  IndicateReceiving
  mov   #DataToTransmit, $00            ; ack the header byte with $E0
  mov   #$E0, @R0
  mov   #$01, NBytesToSend
  callf SerialTxOneByte
  callf WaitUntilAllBytesSent
  mov   #DataTransmitted, $01
  mov   #$0D, scon1
.loop:
  set1  pcon, $00
  ld    p7                    
  and   #$09
  bne   #$08, .abort
  ld    NBytesToReceive
  bnz   .loop
  mov   #DataTransmitted, $01
  ld    @R1
  bne   #$02, .reject
  inc   $01
  ld    @R1
  st    $60
  inc   $01
  ld    @R1
  st    NBlocksToWrite                  ; bank 1 $3D = blocks needed, $78/$79 = size for the directory entry
  st    $78
  mov   #$00, $79
  ld    $60
  clr1  psw, rambk0
  bne   #$CC, .dataFile    ; Branch if not a game file
  ld    FreeGameBlocks
  br    .checkRoom
.dataFile:
  ld    FreeUserBlocks                  ; data file: compare against free user blocks
.checkRoom:
  set1  psw, rambk0
  be    NBlocksToWrite, .accepted
  bn    psw, cy, .accepted
.reject:
  mov   #$0A, acc
  call  SendStatusByte
  clr1  psw, rambk0
  jmp   CopyReceive
.accepted:
  call  ProgressBarInit
  call  RecvAck
  bz    .expectName
  jmp   SerialTeardown
.expectName:
  mov   #DataTransmitted, $01
  ld    @R1
  be    #$06, .gotName
  br    .reject
.gotName:
  call  ProgressBarStep
  call  CheckNameAndStage
  push  acc
  ld    $60
  bne   #$CC, .checkUnique              ; game files always start at block 0
  mov   #$00, $62
  mov   #$00, $63
.checkUnique:
  pop   acc
  bz    .receiveBlocks
  br    .failed
.receiveBlocks:
  call  CopyReceiveBlocks
  bnz   .failedQuiet
  call  RecvAck
  bz    .expectTail
  jmp   SerialTeardown
.expectTail:
  mov   #DataTransmitted, $01
  ld    @R1
  be    #$03, .gotTail
  jmp   .failed
.gotTail:
  call  ProgressBarStep
  call  StageDirTail
  call  RecvAck
  bz    .expectDone
  jmp   SerialTeardown
.expectDone:
  mov   #DataTransmitted, $01
  ld    @R1
  be    #$08, .commit
  jmp   .failed
.commit:
  call  CopyCommitFile
  bnz   .failed
  call  ProgressBarStep
  clr1  psw, rambk0
  jmp   CopyReceive
.failed:
  ld    p7
  and   #$09
  bne   #$08, .disconnected
  mov   #$0A, acc
  call  SendStatusByte
  clr1  psw, rambk0
  jmp   CopyReceive
.failedQuiet:
  ld    p7
  and   #$09
  bne   #$08, .disconnected
  clr1  psw, rambk0
  jmp   CopyReceive
.disconnected:
  jmp   SerialTeardown
;; -----------------------------------------------------------------------------
;; CopyCommitFile ($28E0)
;; Write the work-RAM FAT back to flash, then insert the new directory entry (bank 1
;; $60-$7B) into a free slot and program that page (3 tries; a bad page triggers
;; RelocateDirBlock). Answers $0C (ok) or $0A (failed) to the sender.
;; Out: ACC = 0 ok, $FF failed.
;; -----------------------------------------------------------------------------
CopyCommitFile:
  clr1  ie, $07
  call  WriteFatFromWram
  clr1  psw, rambk0
  ld    FsError
  set1  psw, rambk0
  bz    .insertEntry
  br    .fail
.insertEntry:
  call  FindFreeDirSlot
  bnz   .fail
  call  InsertDirEntry
  bnz   .fail
  mov   #$03, b
.writeDir:
  push  b
  callf FlashWriteEntry
  pop   b
  callf FlashVerifyEntry
  bz    .ok
  dbnz  b, .writeDir
  callf RelocateDirBlock
.ok:
  set1  ie, $07
  mov   #$0C, acc
  call  SendStatusByte
  clr1  psw, rambk0
  mov   #$00, acc
  ret
.fail:
  set1  ie, $07
  mov   #$0A, acc
  call  SendStatusByte
  mov   #$FF, acc
  ret
;; -----------------------------------------------------------------------------
;; CopyReceiveCancel ($2923)
;; A+B (or MODE) during receive: restore the ports and clock, back to the file manager.
;; -----------------------------------------------------------------------------
CopyReceiveCancel:
  clr1  psw, rambk0
  set1  p3int, $00
  call  SerialRestorePorts
  mov   #$A3, ocr
  mov   #$00, CopyRxArm
  mov   #$00, SleepCtl
  mov   #$01, IdleTicks
  jmpf  FileManagerExit

.org $2938
SerialTeardown:
  clr1  psw, rambk0
  set1  p3int, $00
  call  SerialRestorePorts
  mov   #$02, xbnk
  mov   #$00, xram_0184 ; clear flash icon
  mov   #$A3, ocr
  mov   #$01, IdleTicks
  mov   #$00, SleepCtl
  mov   #$00, BiosMode
  jmpf  FileManager

;; -----------------------------------------------------------------------------
;; RecvAck ($2953)
;; Send $0C ("ready") and receive the next packet (RecvPacket).
;; -----------------------------------------------------------------------------
RecvAck:
  mov   #$0C, acc
  call  SendStatusByte
  call  RecvPacket
  ret
;; -----------------------------------------------------------------------------
;; CopyReceiveBlocks ($295B)
;; Receive NBlocksToWrite blocks. Game files take consecutive blocks from 0 and only if
;; the FAT entry at block 0 says $FFFC and the region is free; data files get blocks
;; allocated from 199 downwards (AllocDataBlock). Out: ACC = 0 ok.
;; -----------------------------------------------------------------------------
CopyReceiveBlocks:
  push  b
  push  c
  ld    $60
  bne   #$CC, .dataNext
  mov   #$00, vrmad1
  clr1  vrmad2, $00
  ld    vtrbf
  bne   #$FC, .fail
  ld    vtrbf
  be    #$FF, .gameStart
.fail:
  jmp   CopyReceiveBlocks_fail2
.gameStart:
  mov   #$00, vrmad1
  clr1  vrmad2, $00
  mov   #$FA, vtrbf
  mov   #$FF, vtrbf
  mov   #$00, FmBank                    ; game data starts at flash $00000
  mov   #$00, FmAddrHi
  mov   #$00, FmAddrLo
  br    .receiveBlock
.gameNext:
  call  AllocGameBlock
  bz    .receiveBlock
  br    CopyReceiveBlocks_fail2
.dataNext:
  call  AllocDataBlock
  bz    .receiveBlock
  br    CopyReceiveBlocks_fail2
.receiveBlock:
  call  ReceiveBlockPages
  bnz   CopyReceiveBlocks_fail2
  call  ProgressBarStep
  ld    $60
  be    #$CC, .moreGame
  dbnz  NBlocksToWrite, .dataNext
  br    .ok
.moreGame:
  dbnz  NBlocksToWrite, .gameNext
.ok:
  mov   #$00, acc
  pop   c
  pop   b
  ret
CopyReceiveBlocks_fail2:
  mov   #$FF, acc
  pop   c
  pop   b
  ret
;; -----------------------------------------------------------------------------
;; ReceiveBlockPages ($29BA)
;; Receive the four 128-byte pages of one block and program each one
;; (WritePageWithRetry). Out: ACC = 0 ok.
;; -----------------------------------------------------------------------------
ReceiveBlockPages:
  push  b
  push  c
  mov   #$04, c
.page:
  push  FmBank
  push  FmAddrHi
  push  FmAddrLo
  call  RecvAck
  mov   #FmAddrLo, $01
  ld    @R1
  be    #$04, .gotPage
  br    .badPage
.gotPage:
  pop   FmAddrLo
  pop   FmAddrHi
  pop   FmBank
  call  RecvAck
  bnz   .fail
  mov   #DataTransmitted, $01
  ld    @R1
  be    #$08, .write
  br    CopyReceiveBlocks_fail2
.write:
  call  WritePageWithRetry
  bnz   .badPage
  dbnz  c, .page
  pop   c
  pop   b
  mov   #$00, acc
  ret
.badPage:
  mov   #$0A, acc
  call  SendStatusByte
.fail:
  pop   c
  pop   b
  mov   #$FF, acc
  ret
;; -----------------------------------------------------------------------------
;; CheckNameAndStage ($2A01)
;; FindDataFileByName; if no clash copy the received name into bank 1 $64 (staging
;; directory entry) and mark the first block ($62/$63) as not allocated yet ($FFFF).
;; -----------------------------------------------------------------------------
CheckNameAndStage:
  callf FindDataFileByName
  bnz   .exists
  mov   #$29, $01
  mov   #$64, $00
  mov   #$0C, b
.copy:
  ld    @R1
  st    @R0
  inc   $01
  inc   $00
  dbnz  b, .copy
  mov   #$00, $61
  mov   #$FF, $62
  mov   #$FF, $63
  mov   #$00, acc
  ret
.exists:
  mov   #$FF, acc
  ret
;; -----------------------------------------------------------------------------
;; StageDirTail ($2A29)
;; Copy the received tail (timestamp, size, header offset) to bank 1 $70.
;; -----------------------------------------------------------------------------
StageDirTail:
  mov   #$29, $01
  mov   #$70, $00
  mov   #$0C, b
.copy:
  ld    @R1
  st    @R0
  inc   $01
  inc   $00
  dbnz  b, .copy
  ret
;; -----------------------------------------------------------------------------
;; AllocDataBlock ($2A3C)
;; Find the highest free block below 200 in the work-RAM FAT, mark it end-of-chain,
;; link the previous block to it (or record it as the first block) and set
;; FmBank/FmAddrHi/FmAddrLo to its flash address. Out: ACC = 0 ok, $FF disk full.
;; -----------------------------------------------------------------------------
AllocDataBlock:
  push  c
  mov   #$8E, vrmad1
  set1  vrmad2, $00
  mov   #$C8, c
.scan:
  ld    vtrbf
  bne   #$FC, .used
  ld    vtrbf
  be    #$FF, .found
  br    .next
.used:
  ld    vtrbf
.next:
  ld    vrmad1
  sub   #$04
  st    vrmad1
  ld    vrmad2
  subc  #$00
  and   #$01
  st    vrmad2
  dbnz  c, .scan
  jmp   .full
.found:
  ld    vrmad1
  sub   #$02
  st    vrmad1
  ld    vrmad2
  subc  #$00
  and   #$01
  st    vrmad2
  clr1  psw, cy
  rorc
  ld    vrmad1
  rorc
  st    $44
  mov   #$00, $45
  ld    $62
  bne   #$FF, .link
  ld    $63
  be    #$FF, .first
  jmp   .full
.first:
  ld    $44
  st    $62
  ld    $45
  st    $63
  br    .setAddress
.link:
  ld    $70
  st    vrmad2
  ld    $71
  st    vrmad1
  ld    $44
  st    vtrbf
  ld    $45
  st    vtrbf
.setAddress:
  ld    $44
  clr1  psw, cy
  rolc
  st    $71
  st    FmAddrHi
  st    vrmad1
  mov   #$00, acc
  rolc
  st    $70
  st    FmBank
  st    vrmad2
  mov   #$00, FmAddrLo
  mov   #$FA, vtrbf
  mov   #$FF, vtrbf
  pop   c
  mov   #$00, acc
  ret
.full:
  pop   c
  mov   #$FF, acc
  ret
;; -----------------------------------------------------------------------------
;; AllocGameBlock ($2AD0)
;; Claim the next consecutive block for a game file (must be free), link it from the
;; previous one and set FmBank/FmAddrHi/FmAddrLo. Out: ACC = 0 ok.
;; -----------------------------------------------------------------------------
AllocGameBlock:
  push  b
  ld    vtrbf
  bne   #$FC, .fail
  ld    vtrbf
  bne   #$FF, .fail
  ld    vrmad1
  sub   #$02
  st    vrmad1
  st    FmAddrHi
  ld    vrmad2
  subc  #$00
  and   #$01
  st    vrmad2
  st    FmBank
  mov   #$00, FmAddrLo
  clr1  psw, cy
  rorc
  ld    vrmad1
  rorc
  st    b
  ld    vrmad1
  sub   #$02
  st    vrmad1
  ld    vrmad2
  subc  #$00
  st    vrmad2
  ld    b
  st    vtrbf
  mov   #$00, vtrbf
  mov   #$FA, vtrbf
  mov   #$FF, vtrbf
  pop   b
  mov   #$00, acc
  ret
.fail:
  pop   b
  mov   #$FF, acc
  ret
;; -----------------------------------------------------------------------------
;; FindFreeDirSlot ($2B1E)
;; Find the directory page (128 bytes, 4 entries) holding the first empty entry,
;; following the directory chain through the work-RAM FAT, and FM_PRD it into bank 1
;; $80-$FF. Out: ACC = 0 ok, $FF directory full/broken.
;; -----------------------------------------------------------------------------
FindFreeDirSlot:
  mov   #$01, fpr
  clr1  psw, rambk0
  mov   #$01, FlashBankTemp
  mov   #$FE, trh
  mov   #$46, trl             ; Read FAT First block ID (0xFE46)
  callf PrepareFlashBlockRead
  set1  psw, rambk0
  st    $54
  ld    trh
  st    $55
  ld    trl
  st    $56
  mov   #$01, fpr
  clr1  psw, rambk0
  mov   #$01, FlashBankTemp
  mov   #$FE, trh
  mov   #$4A, trl
  callf PrepareFlashBlockRead
  set1  psw, rambk0
.block:
  mov   #$10, b
.entry:
  ldf
  bz    .found
  ld    trl
  add   #$20
  st    trl
  mov   #$00, acc
  addc  trh
  st    trh
  dbnz  b, .entry
  ld    trh
  and   #$FE
  st    vrmad1
  clr1  psw, rambk0
  ld    FlashBankTemp
  set1  psw, rambk0
  st    vrmad2
  ld    vtrbf
  bne   #$FA, .checkLink
  ld    vtrbf
  bnz   .fail
  br    .nextBlock
.checkLink:
  ld    vtrbf
  bnz   .fail
.nextBlock:
  ld    vrmad1
  sub   #$02
  st    FmAddrHi
  ld    vrmad2
  subc  #$00
  st    FmBank
  mov   #$00, FmAddrLo
  br    .block
.found:
  push  trl
  ld    trl
  and   #$80
  st    FmAddrLo
  ld    trh
  st    FmAddrHi
  clr1  psw, rambk0
  ld    FlashBankTemp
  set1  psw, rambk0
  st    FmBank
  callf FlashReadEntry
  pop   trl
  mov   #$00, acc
  ret
.fail:
  mov   #$FF, acc
  ret
;; -----------------------------------------------------------------------------
;; InsertDirEntry ($2BB3)
;; Copy the staged entry (bank 1 $60-$7B, 28 bytes) into the first empty slot of the
;; page at bank 1 $80 and zero the last 4 bytes. Out: ACC = 0 ok.
;; -----------------------------------------------------------------------------
InsertDirEntry:
  mov   #$04, b
  mov   #$80, $00
.find:
  ld    @R0
  bz    .copy
  ld    $00
  add   #$20
  st    $00
  dbnz  b, .find
  br    .full
.copy:
  mov   #$60, $01
  mov   #$1C, b
.loop:
  ld    @R1
  st    @R0
  inc   $01
  inc   $00
  dbnz  b, .loop
  mov   #$00, acc
  st    @R0
  inc   $00
  st    @R0
  inc   $00
  st    @R0
  inc   $00
  st    @R0
  ret
.full:
  mov   #$FF, acc
  ret
;; -----------------------------------------------------------------------------
;; WritePageWithRetry ($2BE8)
;; FM_WRT + FM_VRF the page at FmBank/FmAddrHi/FmAddrLo up to 3 times, then advance
;; the address by 128. If it never verifies, the block is marked $FFFF (bad) in the
;; FAT and the FAT is written back. Out: ACC = 0 ok, $FF bad block.
;; -----------------------------------------------------------------------------
WritePageWithRetry:
  push  b
  mov   #$03, b
  clr1  ie, $07
.try:
  push  b
  push  c
  callf FlashWriteEntry
  pop   c
  pop   b
  callf FlashVerifyEntry
  bz    .ok
  dbnz  b, .try
  br    .badBlock
.ok:
  ld    FmAddrLo
  add   #$80
  st    FmAddrLo
  mov   #$00, acc
  addc  FmAddrHi
  st    FmAddrHi
  mov   #$00, acc
.return:
  set1  ie, $07
  pop   b
  ret
.badBlock:
  ld    FmBank
  and   #$01
  push  acc
  ld    FmAddrHi
  and   #$FE
  push  acc
  call  LoadFatToWram
  pop   acc
  st    vrmad1
  pop   acc
  st    vrmad2
  mov   #$FF, vtrbf
  mov   #$FF, vtrbf
  call  WriteFatFromWram
  mov   #$FF, acc
  br    .return
;; -----------------------------------------------------------------------------
;; RecvPacket ($2C3C)
;; Wait for a header ($1x: length in the low nibble, stored at bank 1 $28) or data
;; ($5x: 130 bytes from bank 1 $7F) packet, ack its first byte with $E0 and receive
;; the rest through IsrSio1. Out: ACC = 0 ok, $FF if the other VMU went away.
;; -----------------------------------------------------------------------------
RecvPacket:
  set1  pcon, $00
  ld    p7
  and   #$09
  bne   #$08, .fail
  ld    sbuf1
  bz    RecvPacket
  and   #$F0
  be    #$10, .header
  bne   #$50, .ignore
  jmp   .data
.ignore:
  set1  scon1, $03
  br    RecvPacket
.header:
  ld    sbuf1
  and   #$0F
  clr1  scon1, $01
  inc   acc
  inc   acc
  st    RxPayloadSize
  inc   acc
  st    NBytesToReceive
  mov   #DataToTransmit, $00
  mov   #$E0, @R0
  mov   #$01, NBytesToSend
  callf SerialTxOneByte
  callf WaitUntilAllBytesSent
  mov   #DataTransmitted, $01
  mov   #$0D, scon1
.waitHeader:
  set1  pcon, $00
  ld    p7
  and   #$09
  bne   #$08, .fail
  ld    NBytesToReceive
  bnz   .waitHeader
  mov   #$00, acc
  ret
.fail:
  mov   #$FF, acc
  ret
.data:
  mov   #$82, NBytesToReceive
  mov   #$81, RxPayloadSize
  mov   #DataToTransmit, $00
  mov   #$E0, @R0
  mov   #$01, NBytesToSend
  callf SerialTxOneByte
  callf WaitUntilAllBytesSent
  mov   #FmAddrLo, $01
  mov   #$0D, scon1
.waitData:
  set1  pcon, $00
  ld    p7
  and   #$09
  bne   #$08, .fail
  ld    NBytesToReceive
  bnz   .waitData
  ret
;; -----------------------------------------------------------------------------
;; SendStatusByte ($2CB8)
;; Send the single byte in ACC ($0C ok/ready, $0A refused) and keep receiving.
;; -----------------------------------------------------------------------------
SendStatusByte:
  mov   #DataToTransmit, $00
  mov   #DataTransmitted, $01
  st    @R0
  mov   #$01, NBytesToSend
  callf SerialTxOneByte
  callf WaitUntilAllBytesSent
  mov   #DataTransmitted, $01
  set1  scon1, $03
  ret
;; -----------------------------------------------------------------------------
;; ProgressBarInit ($2CCE)
;; Draw a progress bar on the bottom rows (XRAM bank 1, from $C0), one pixel per block
;; plus 3.
;; -----------------------------------------------------------------------------
ProgressBarInit:
  push  b
  mov   #$01, xbnk
  mov   #$C0, $02
  ld    NBlocksToWrite
  add   #$03
  st    b
.loop:
  ld    @R2
  be    #$FF, .nextByte
  set1  psw, cy
  rorc
  st    @R2
  dbnz  b, .loop
  br    .return
.nextByte:
  inc   $02
  ld    $02
  and   #$0F
  bne   #$0C, .newByte
  ld    $02
  add   #$04
  or    #$C0
  st    $02
.newByte:
  mov   #$80, @R2
  dbnz  b, .loop
.return:
  pop   b
  ret
;; -----------------------------------------------------------------------------
;; ProgressBarStep ($2D02)
;; Remove one pixel from the progress bar.
;; -----------------------------------------------------------------------------
ProgressBarStep:
  push  b
  push  acc
  ld    @R2
  st    b
  clr1  psw, cy
  rolc
  and   b
  st    @R2
  bnz   .return
  dec   $02
  ld    $02
  and   #$0F
  bne   #$0F, .return
  ld    $02
  sub   #$04
  or    #$C0
  st    $02
.return:
  pop   acc
  pop   b
  ret

;; -----------------------------------------------------------------------------
;; UnusedTail_2D27 ($2D27)
;; Unreachable leftover: the tail of some older prompt routine.
;; -----------------------------------------------------------------------------
UnusedTail_2D27:
  mov   #$FF, acc
  callf DrawYesNoChoice
  pop   trl
  pop   trh
  ret

.org $2D32
IndicateWaitingForData:
  push  trh
  push  trl
  clr1  p3int, $00
  callf ClearScreen
  mov   #$00, CursorX
  mov   #$00, CursorY
  mov   #<Str_WaitingForData, trl
  mov   #>Str_WaitingForData, trh
  callf DrawString
  callf DisableFlashIcon
  set1  p3int, $00
  pop   trl
  pop   trh
  ret

.org $2D54
IndicateReceiving:
  clr1  psw, rambk0
  mov   #$00, CursorX
  mov   #$00, CursorY
  mov   #<Str_Receiving, trl
  mov   #>Str_Receiving, trh
  callf DrawString
  callf EnableFlashIcon
  set1  psw, rambk0
  ret

.org $2D6B
Str_WaitingForData:
  .string 29 "Waiting \r\nfor data\r\n        "
.org $2D88
Str_Receiving:
  .string 29 "Reciving\r\n Do Not \r\n  Unplug"

;; -----------------------------------------------------------------------------
;; FileDelete ($2DA5)
;; "Delete ?" for the selected file. On Yes: free its FAT chain, erase its directory
;; entry (flash icon lit, battery check off meanwhile), select the previous file and
;; rescan the list.
;; -----------------------------------------------------------------------------
FileDelete:
  call  DrawDeletePrompt
  callf WaitAllButtonsReleased
  mov   #$00, c
  mov   #$01, IdleTicks
  mov   #$00, SleepCtl
.loop:
  callf WaitKeyEvent
  be    #$FF, .exit
  be    #$FD, .exit
  be    #$10, .select
  be    #$20, .cancel
  be    #$04, .toggle
  be    #$08, .toggle
  br    .loop
.cancel:
  set1  p3int, $00
  jmpf  FileActionMenu
.select:
  ld    c
  bz    .cancel
  br    .yes
.toggle:
  ld    c
  xor   #$FF
  st    c
  callf DrawYesNoChoice
  callf WaitDpadReleased
  br    .loop
.yes:
  call  DrawDeleted
  mov   #$FF, BatteryCheck
  callf EnableFlashIcon
  call  FreeFileBlocks
  call  EraseDirEntry
  mov   #$00, BatteryCheck
  callf DisableFlashIcon
  ld    SelectedFile
  be    #$01, .rescan
  dec   SelectedFile
.rescan:
  jmpf  FileListScan
.exit:
  set1  p3int, $00
  jmpf  FileManagerExit
;; -----------------------------------------------------------------------------
;; DrawDeletePrompt ($2E04)
;; File name on rows 0-1, "Delete ?" on row 2 and the Yes/No choice (No highlighted).
;; -----------------------------------------------------------------------------
DrawDeletePrompt:
  push  trh
  push  trl
  clr1  p3int, $00
  callf ClearScreen
  mov   #$00, CursorX
  mov   #$00, CursorY
  ld    trl
  add   #$04
  st    trl
  mov   #$08, c
  mov   #$02, b
.loop:
  ldf
  callf DrawChar6x8
  inc   trl
  inc   CursorX
  dbnz  c, .loop
  inc   CursorY
  mov   #$00, CursorX
  mov   #$04, c
  dbnz  b, .loop
  mov   #<Str_DeletePrompt, trl
  mov   #>Str_DeletePrompt, trh
  mov   #$00, CursorX
  mov   #$02, CursorY
  callf DrawString
  mov   #$00, acc
  callf DrawYesNoChoice
  set1  p3int, $00
  pop   trl
  pop   trh
  ret
;; -----------------------------------------------------------------------------
;; DrawDeleted ($2E51)
;; "Deleted" on row 2.
;; -----------------------------------------------------------------------------
DrawDeleted:
  push  trh
  push  trl
  clr1  p3int, $00
  mov   #$01, xbnk
  callf ClearHalfScreen
  mov   #<Str_Deleted, trl
  mov   #>Str_Deleted, trh
  mov   #$00, CursorX
  mov   #$02, CursorY
  callf DrawString
  set1  p3int, $00
  pop   trl
  pop   trh
  ret
;; -----------------------------------------------------------------------------
;; EraseDirEntry ($2E73)
;; Zero the 32-byte directory entry at TRH:TRL: FM_PRD its page, clear the entry in
;; bank 1, FM_WRT + FM_VRF up to 3 times; a page that never verifies goes through
;; RelocateDirBlock.
;; -----------------------------------------------------------------------------
EraseDirEntry:
  mov   #$81, ocr
  clr1  p3int, $00
  set1  psw, rambk0
  clr1  ie, $07
  mov   #$01, FmBank
  ld    trh
  st    FmAddrHi
  ld    trl
  and   #$80
  st    FmAddrLo
  push  trh
  push  trl
  callf FlashReadEntry
  pop   trl
  pop   trh
  mov   #$03, c
.try:
  ld    trl
  and   #$7F
  or    #$80
  st    $00
  mov   #$00, acc
  mov   #$08, b
.clear:
  st    @R0
  inc   $00
  st    @R0
  inc   $00
  st    @R0
  inc   $00
  st    @R0
  inc   $00
  dbnz  b, .clear
  push  trh
  push  trl
  push  c
  callf FlashWriteEntry
  pop   c
  callf FlashVerifyEntry
  pop   trl
  pop   trh
  bz    .return
  dbnz  c, .try
  callf RelocateDirBlock
.return:
  set1  ie, $07
  clr1  psw, rambk0
  set1  p3int, $00
  mov   #$A3, ocr
  ret
;; -----------------------------------------------------------------------------
;; FreeFileBlocks ($2ED8)
;; Mark every block of the file at TRH:TRL as free ($FFFC) in the work-RAM FAT, then
;; write the FAT back (WriteFatFromWram). FsError bit 3 if the chain is broken.
;; -----------------------------------------------------------------------------
FreeFileBlocks:
  push  trh
  push  trl
  clr1  p3int, $00
  clr1  ie, $07
  mov   #$81, ocr
  set1  psw, rambk0
  call  LoadFatToWram
  mov   #$01, fpr
  clr1  psw, rambk0
  mov   #$01, FlashBankTemp
  set1  psw, rambk0
  mov   #$03, acc
  add   trl
  st    trl
  ldf
  bz    .first
  brf   .badEntry
.first:
  dec   trl
  ldf
.walk:
  clr1  psw, cy
  rolc
  push  acc
  st    vrmad1
  mov   #$00, acc
  rolc
  push  acc
  st    vrmad2
  ld    vtrbf
  bne   #$FA, .link
  ld    vtrbf
  dec   vrmad1
  bz    .link
  be    #$FF, .last
  pop   acc
  pop   acc
  brf   .badChain
.link:
  st    b
  ld    vtrbf
  bz    .free
  pop   acc
  pop   acc
  brf   .badChain
.free:
  pop   acc
  st    vrmad2
  pop   acc
  st    vrmad1
  mov   #$FC, vtrbf
  mov   #$FF, vtrbf
  ld    b
  br    .walk
.last:
  ld    vtrbf
  pop   acc
  st    vrmad2
  pop   acc
  st    vrmad1
  mov   #$FC, vtrbf
  mov   #$FF, vtrbf
  call  WriteFatFromWram
  ld    $5C
  bnz   .badChain
.return:
  mov   #$A3, ocr
  set1  ie, $07
  clr1  psw, rambk0
  set1  p3int, $00
  pop   trl
  pop   trh
  ret
.badEntry:
  clr1  psw, rambk0
  ld    FsError
  or    #$80
  st    FsError
.badChain:
  clr1  psw, rambk0
  ld    FsError
  or    #$08
  st    FsError
  br    .return
;; -----------------------------------------------------------------------------
;; LoadFatToWram ($2F7A)
;; Copy the 512-byte FAT block into Maple work RAM ($000-$1FF) via bank 1 $80-$FF,
;; 128 bytes at a time. Leaves the FAT flash address in bank 1 $54-$56.
;; -----------------------------------------------------------------------------
LoadFatToWram:
  push  trh
  push  trl
  push  acc
  push  b
  clr1  psw, rambk0
  mov   #$01, fpr
  mov   #$01, FlashBankTemp
  mov   #$FE, trh
  mov   #$46, trl
  callf PrepareFlashBlockRead
  set1  psw, rambk0
  st    $54
  ld    trh
  st    $55
  ld    trl
  st    $56
  clr1  vrmad2, $00
  mov   #$00, vrmad1
  mov   #$04, b
.page:
  clr1  psw, rambk0
  ld    FlashBankTemp
  set1  psw, rambk0
  st    FmBank
  ld    trh
  st    FmAddrHi
  ld    trl
  st    FmAddrLo
  callf FlashReadEntry
  callf CopyBufToWram
  ld    trl
  bnz   .next
  inc   trh
.next:
  dbnz  b, .page
  pop   b
  pop   acc
  pop   trl
  pop   trh
  ret
;; -----------------------------------------------------------------------------
;; WriteFatFromWram ($2FCF)
;; Write the work-RAM FAT back to flash page by page; pages that already match are
;; skipped (FM_VRF first). A page that won't program after 3 tries makes
;; RelocateFatBlock move the FAT elsewhere and starts over. FsError bit 3 if even
;; that fails.
;; -----------------------------------------------------------------------------
WriteFatFromWram:
  clr1  vrmad2, $00
  mov   #$00, vrmad1
  mov   #$04, b
.page:
  mov   #$03, c
  callf CopyWramToBuf
  ld    $54
  st    FmBank
  ld    $55
  st    FmAddrHi
  ld    $56
  st    FmAddrLo
  callf FlashVerifyEntry
  bnz   .program
.next:
  clr1  psw, rambk0
  ld    FlashBankTemp
  set1  psw, rambk0
  st    $54
  clr1  psw, cy
  mov   #$80, acc
  add   trl
  st    $56
  st    trl
  mov   #$00, acc
  addc  trh
  st    $55
  st    trh
  dbnz  b, .page
  ret
.program:
  ld    $54
  st    FmBank
  ld    $55
  st    FmAddrHi
  ld    $56
  st    FmAddrLo
  push  b
  push  c
  callf FlashWriteEntry
  pop   c
  pop   b
  callf FlashVerifyEntry
  bz    .next
  dbnz  c, .program
  callf RelocateFatBlock
  ld    $5C
  bnz   .fail
  br    WriteFatFromWram
.fail:
  ld    $5C
  or    #$08
  st    $5C
  ret
;; -----------------------------------------------------------------------------
;; RelocateFatBlock ($303D)
;; The FAT block has gone bad: mark it $FFFF in the work-RAM FAT, pick the highest
;; free block below 200, mark it $FFFA, point root+$46 at it and rewrite the root block.
;; FsError bit 6 if the root block can't be written, bit 2 if there is no free block.
;; -----------------------------------------------------------------------------
RelocateFatBlock:
  push  acc
  push  b
  push  c
  set1  vrmad2, $00
  mov   #$00, vrmad1
  mov   #$01, fpr
  clr1  psw, rambk0
  mov   #$01, FlashBankTemp
  set1  psw, rambk0
  mov   #$FE, trh
  mov   #$46, trl
  ldf
  clr1  psw, cy
  rolc
  st    vrmad1
  mov   #$FF, vtrbf
  mov   #$FF, vtrbf
  set1  vrmad2, $00
  mov   #$CC, vrmad1
.scan:
  ld    vtrbf
  bne   #$FC, .next
  ld    vtrbf
  be    #$FF, .found
  ld    vrmad1
  sub   #$02
  st    vrmad1
.next:
  ld    vrmad1
  and   #$FE
  sub   #$02
  be    #$8E, .full
  st    vrmad1
  br    .scan
.found:
  ld    vrmad1
  sub   #$02
  st    vrmad1
  mov   #$FA, vtrbf
  mov   #$FF, vtrbf
  ror
  or    #$80
  push  acc
  mov   #$01, FmBank
  mov   #$FE, FmAddrHi
  mov   #$00, FmAddrLo
  callf FlashReadEntry
  pop   acc
  st    $C6
  mov   #$00, $C7
  mov   #$03, c
  push  acc
.writeRoot:
  push  c
  callf FlashWriteEntry
  pop   c
  callf FlashVerifyEntry
  bz    .ok
  dbnz  c, .writeRoot
  br    .rootFailed
.ok:
  pop   acc
  clr1  psw, cy
  rolc
  st    $55
  mov   #$00, acc
  st    $56
  rolc
  st    $54
  br    .return
.rootFailed:
  ld    $5C
  or    #$40
  st    $5C
  pop   acc
  br    .return
.full:
  ld    $5C
  or    #$04
  st    $5C
.return:
  pop   c
  pop   b
  pop   acc
  ret
;; -----------------------------------------------------------------------------
;; RelocateDirBlock ($30E8)
;; A directory page at TRH:TRL won't program. Copy the whole directory block (with the
;; freshly modified page from bank 1 swapped in) to a free block in the 200-230 area,
;; relink it in place of the bad one (either root+$4A or the previous block's FAT
;; entry), mark the bad block $FFFF and write FAT/root back.
;; FsError: bit 2 no free block, bit 3 broken chain, bit 5/6 root or FAT write failed.
;; -----------------------------------------------------------------------------
RelocateDirBlock:
  push  acc
  push  b
  push  c
  ld    trh
  and   #$01
  st    vrmad2
  ld    trl
  and   #$80
  st    vrmad1
  call  CopyBufToWram
  mov   #$04, b
  mov   #$00, vrmad1
  clr1  vrmad2, $00
  clr1  psw, rambk0
  ld    FlashBankTemp
  set1  psw, rambk0
  st    FmBank
  ld    trh
  and   #$FE
  st    FmAddrHi
  mov   #$00, FmAddrLo
.page:
  push  trh
  push  trl
  callf FlashReadEntry
  pop   trl
  pop   trh
  ld    FmAddrHi
  and   #$01
  st    c
  ld    trh
  and   #$01
  xor   c
  bnz   .swap
  ld    FmAddrLo
  and   #$80
  st    c
  ld    trl
  and   #$80
  xor   c
  bz    .next
.swap:
  call  CopyBufToWram
  br    .advance
.next:
  ld    vrmad1
  add   #$80
  st    vrmad1
  ld    vrmad2
  addc  #$00
  and   #$01
  st    vrmad2
.advance:
  ld    FmAddrLo
  add   #$80
  st    FmAddrLo
  ld    FmAddrHi
  addc  #$00
  st    FmAddrHi
  dbnz  b, .page
  clr1  psw, rambk0
  push  FlashBankTemp
  push  trh
  push  trl
  mov   #$01, fpr
  mov   #$01, FlashBankTemp
  mov   #$FE, trh
  mov   #$46, trl
  callf PrepareFlashBlockRead
  set1  psw, rambk0
  st    FmBank
  ld    trh
  or    #$01
  st    FmAddrHi
  mov   #$80, FmAddrLo
  callf FlashReadEntry
  mov   #$00, vrmad1
  clr1  vrmad2, $00
  call  SwapBufWithWram
  pop   trl
  pop   trh
  clr1  psw, rambk0
  pop   FlashBankTemp
  ld    FlashBankTemp
  st    fpr
  set1  psw, rambk0
  ld    trh
  ror
  or    #$80
  st    $42
  st    $44
  mov   #$00, $43
  mov   #$00, $45
  ld    trh
  and   #$7E
  st    vrmad1
  clr1  vrmad2, $00
  ld    vtrbf
  st    $40
  ld    vtrbf
  st    $41
.findBlock:
  ld    $44
  rol
  and   #$7E
  st    vrmad1
  clr1  vrmad2, $00
  mov   #$FF, vtrbf
  mov   #$FF, vtrbf
  mov   #$4C, vrmad1
  mov   #$1F, b
.scan:
  ld    vtrbf
  be    #$FC, .found
  ld    vtrbf
.next2:
  ld    vrmad1
  sub   #$04
  st    vrmad1
  dbnz  b, .scan
  ld    $5C
  or    #$04
  st    $5C
  jmp   .return
.found:
  ld    vtrbf
  bne   #$FF, .next2
  dec   vrmad1
  dec   vrmad1
  ld    vrmad1
  or    #$80
  ror
  or    #$80
  st    $44
  ld    $40
  st    vtrbf
  ld    $41
  st    vtrbf
  ld    $44
  clr1  psw, cy
  rolc
  st    FmAddrHi
  mov   #$00, acc
  rolc
  st    FmBank
  mov   #$00, FmAddrLo
  mov   #$80, vrmad1
  clr1  vrmad2, $00
  mov   #$04, c
  mov   #$03, b
.copyPage:
  push  b
  push  c
  callf FlashWriteEntry
  pop   c
  pop   b
  callf FlashVerifyEntry
  bz    .pageOk
  dbnz  b, .copyPage
  jmp   .findBlock
.pageOk:
  ld    FmAddrLo
  add   #$80
  st    FmAddrLo
  ld    FmAddrHi
  addc  #$00
  st    FmAddrHi
  call  SwapBufWithWram
  ld    vrmad1
  add   #$80
  st    vrmad1
  mov   #$00, acc
  addc  vrmad2
  and   #$01
  st    vrmad2
  mov   #$03, b
  dbnz  c, .copyPage
  mov   #$01, fpr
  clr1  psw, rambk0
  mov   #$01, FlashBankTemp
  set1  psw, rambk0
  mov   #$FE, trh
  mov   #$4A, trl
  ldf
  xor   $42
  bnz   .relinkChain
  inc   trl
  ldf
  xor   $43
  dec   trl
  bnz   .relinkChain
  mov   #$00, vrmad1
  clr1  vrmad2, $00
  call  CopyBufToWram
  mov   #$01, FmBank
  mov   #$FE, FmAddrHi
  mov   #$00, FmAddrLo
  callf FlashReadEntry
  ld    $44
  st    $CA
  ld    $45
  st    $CB
  mov   #$03, c
.writeRoot:
  push  c
  callf FlashWriteEntry
  pop   c
  callf FlashVerifyEntry
  bz    .rootUpdated
  dbnz  c, .writeRoot
  ld    $5C
  or    #$40
  st    $5C
  jmp   .return
.rootUpdated:
  mov   #$00, vrmad1
  clr1  vrmad2, $00
  call  CopyWramToBuf
  jmp   .writeFat
.relinkChain:
  ldf
.walk:
  and   #$7F
  rol
  st    $00
  ld    @R0
  st    b
  inc   $00
  ld    @R0
  st    c
  dec   $00
  ld    b
  be    #$FA, .endOfChain
.compare:
  ld    b
  xor   $42
  bnz   .continue
  ld    c
  xor   $43
  bnz   .continue
  ld    $44
  st    @R0
  inc   $00
  ld    $45
  st    @R0
  jmp   .writeFat
.continue:
  ld    b
  jmp   .walk
.endOfChain:
  ld    c
  bne   #$FF, .compare
  ld    $5C
  or    #$08
  st    $5C
  jmp   .return
.writeFat:
  mov   #$01, fpr
  clr1  psw, rambk0
  mov   #$01, FlashBankTemp
  mov   #$FE, trh
  mov   #$46, trl
  callf PrepareFlashBlockRead
  set1  psw, rambk0
  st    FmBank
  ld    trh
  or    #$01
  st    FmAddrHi
  mov   #$80, FmAddrLo
  mov   #$03, b
.tryFat:
  push  b
  callf FlashWriteEntry
  pop   b
  callf FlashVerifyEntry
  bnz   .fatRetry
  jmp   .return
.fatRetry:
  dbnz  b, .tryFat
  mov   #$80, vrmad1
  set1  vrmad2, $00
  call  CopyBufToWram
  mov   #$01, fpr
  clr1  psw, rambk0
  mov   #$01, FlashBankTemp
  mov   #$FE, trh
  mov   #$46, trl
  callf PrepareFlashBlockRead
  set1  psw, rambk0
  st    $54
  st    FmBank
  ld    trh
  st    $55
  st    FmAddrHi
  ld    trl
  st    $56
  st    FmAddrLo
  mov   #$00, vrmad1
  clr1  vrmad2, $00
  mov   #$03, c
.reload:
  callf FlashReadEntry
  call  CopyBufToWram
  ld    FmAddrLo
  add   #$80
  st    FmAddrLo
  mov   #$00, acc
  addc  FmAddrHi
  st    FmAddrHi
  dbnz  c, .reload
  callf RelocateFatBlock
  ld    $5C
  bz    .fatMoved
  or    #$20
  st    $5C
  brf   .return
.fatMoved:
  callf WriteFatFromWram
  ld    $5C
.return:
  pop   c
  pop   b
  pop   acc
  ret

Str_DeletePrompt:
  .string 9 "Delete ?"
Str_Deleted:
  .string 9 "Deleted "

;; -----------------------------------------------------------------------------
;; HardwareInit ($338F)
;; Power-on peripheral setup: flash controller (FlashInit), interrupt enables and
;; priorities, base timer (0.5 s interrupt 0, fast interrupt 1 off), LCD controller
;; on, P1 idle, P3 as inputs with interrupts, SIO and timers stopped.
;; -----------------------------------------------------------------------------
HardwareInit:
  callf FlashInitEntry
  mov   #$03, ie                        ; IE: enable INT0/INT1 (IE.7, the master enable, is set below)
  mov   #$02, ip
  clr1  btcr, $06
  clr1  btcr, $07
  clr1  isl, $04
  set1  btcr, $00                       ; BTCR.0: base timer interrupt 0 (half-second) enabled
  set1  btcr, $06                       ; BTCR.6: base timer running
  set1  ie, $07
  mov   #$09, mcr                       ; MCR $09: LCD on, graphics mode
  mov   #$05, cnr
  mov   #$20, tdr
  mov   #$80, vccr                      ; VCCR.7: LCD power on
  mov   #$00, stad
  mov   #$00, b
  mov   #$80, p1ddr
  mov   #$BF, p1fcr
  clr1  p1, $02
  clr1  p1, $05
  set1  p1, $06
  set1  p1, $07
  mov   #$00, p3ddr
  mov   #$05, p3int                     ; P3INT: button interrupt enabled, wake from HALT
  mov   #$FF, p3
  mov   #$00, i01cr
  mov   #$00, i23cr
  mov   #$00, scon0
  mov   #$00, scon1
  mov   #$FF, t1lr
  mov   #$FF, t1lc
  mov   #$00, t1cnt
  mov   #$00, t0con
  ret
;; -----------------------------------------------------------------------------
;; StartupBeep ($33E6)
;; Short beep at power-on: Timer 1 PWM on P1.7. Standalone it waits 3-4 half-second
;; ticks; in a controller it stops at the next tick.
;; -----------------------------------------------------------------------------
StartupBeep:
  ld    p7
  and   #$01
  bnz   .inController
  mov   #$00, t1cnt
  clr1  p1, $07
  mov   #$FF, t1lc
  mov   #$FE, t1lr
  mov   #$50, t1cnt
  mov   #$00, HalfSecTicks
.wait:
  set1  pcon, $00
  ld    HalfSecTicks
  be    #$03, .wait
  bp    psw, cy, .wait
.stop:
  set1  p1, $07
  mov   #$FF, t1lr
  mov   #$FF, t1lc
  mov   #$00, t1cnt
  ret
.inController:
  mov   #$00, t1cnt
  clr1  p1, $07
  mov   #$FF, t1lc
  mov   #$FE, t1lr
  mov   #$50, t1cnt
  mov   #$00, HalfSecTicks
.waitTick:
  set1  pcon, $00
  ld    HalfSecTicks
  bnz   .stop
  br    .waitTick
;; -----------------------------------------------------------------------------
;; FastTickOn ($342C)
;; Enable base timer interrupt 1 (the fast tick used for key repeat) and let
;; BaseTimerIsr count it in FastTicks.
;; -----------------------------------------------------------------------------
FastTickOn:
  push  psw
  set1  btcr, $05
  set1  btcr, $04
  clr1  btcr, $03
  clr1  psw, rambk0
  mov   #$00, FastTickDisabled
  set1  btcr, $02
  br    FastTickOff_return
;; -----------------------------------------------------------------------------
;; FastTickOff ($343D)
;; Disable the fast tick again.
;; -----------------------------------------------------------------------------
FastTickOff:
  push  psw
  clr1  btcr, $03
  clr1  psw, rambk0
  mov   #$FF, FastTickDisabled
  clr1  btcr, $02
FastTickOff_return:
  pop   psw
  ret
;; -----------------------------------------------------------------------------
;; BcdToBin ($344B)
;; ACC (two BCD digits) -> ACC binary. Uses MathHi as scratch.
;; -----------------------------------------------------------------------------
BcdToBin:
  push  b
  push  c
  push  $00
  mov   #MathHi, $00
  st    @R0
  and   #$F0
  ror
  ror
  ror
  ror
  st    c
  mov   #$0A, b
  mov   #$00, acc
  mul
  ld    @R0
  and   #$0F
  add   c
  pop   $00
  pop   c
  pop   b
  ret
;; -----------------------------------------------------------------------------
;; Bcd16ToBin ($3470)
;; Four BCD digits at @R0 (high byte first) -> binary in MathHi:MathLo.
;; -----------------------------------------------------------------------------
Bcd16ToBin:
  push  b
  push  c
  push  $01
  push  $00
  mov   #$00, b
  mov   #$00, c
  mov   #MathHi, $01
  ld    @R0
  st    @R1
  inc   $00
  inc   $01
  ld    @R0
  st    @R1
  mov   #MathHi, $01
.thousands:
  ld    @R1
  be    @R1, #$10, .subThousand
  bp    psw, cy, .hundreds
.subThousand:
  sub   #$10
  st    @R1
  ld    b
  add   #$E8
  st    b
  ld    c
  addc  #$03
  st    c
  br    .thousands
.hundreds:
  ld    @R1
  bz    .tensDigit
  sub   #$01
  st    @R1
  ld    b
  add   #$64
  st    b
  ld    c
  addc  #$00
  st    c
  br    .hundreds
.tensDigit:
  inc   $01
.tens:
  ld    @R1
  be    @R1, #$10, .subTen
  bp    psw, cy, .ones
.subTen:
  sub   #$10
  st    @R1
  ld    b
  add   #$0A
  st    b
  ld    c
  addc  #$00
  st    c
  br    .tens
.ones:
  ld    @R1
  bz    .store
  sub   #$01
  st    @R1
  ld    b
  add   #$01
  st    b
  ld    c
  addc  #$00
  st    c
  br    .ones
.store:
  mov   #MathHi, $01
  ld    c
  st    @R1
  inc   $01
  ld    b
  st    @R1
  pop   $00
  pop   $01
  pop   c
  pop   b
  ret
;; -----------------------------------------------------------------------------
;; BinToBcd ($34FA)
;; ACC (0-99) -> ACC as two BCD digits.
;; -----------------------------------------------------------------------------
BinToBcd:
  push  b
  push  c
  push  $00
  st    c
  mov   #$0A, b
  mov   #$00, acc
  div
  ld    c
  rol
  rol
  rol
  rol
  and   #$F0
  add   b
  pop   $00
  pop   c
  pop   b
  ret
;; -----------------------------------------------------------------------------
;; Bin16ToBcd ($351A)
;; 16-bit binary at @R0 (high byte first, 0-9999) -> four BCD digits in MathHi:MathLo.
;; -----------------------------------------------------------------------------
Bin16ToBcd:
  push  b
  push  c
  push  $01
  push  $00
  mov   #$00, b
  mov   #$00, c
  mov   #MathHi, $01
  ld    @R0
  st    @R1
  inc   $00
  inc   $01
  ld    @R0
  st    @R1
  st    c
  dec   $01
  ld    @R1
  mov   #$64, b
  div
  mov   #$0A, b
  div
  ld    c
  and   #$0F
  st    b
  rol
  rol
  rol
  rol
  st    @R1
  mov   #$03, acc
  mov   #$E8, c
  mul
  st    b
  ld    @R0
  sub   c
  st    c
  dec   $00
  ld    @R0
  subc  b
  mov   #$64, b
  div
  ld    c
  and   #$0F
  or    @R1
  st    @R1
  inc   $01
  ld    b
  st    c
  mov   #$00, acc
  mov   #$0A, b
  div
  ld    c
  rol
  rol
  rol
  rol
  and   #$F0
  st    @R1
  ld    b
  and   #$0F
  or    @R1
  st    @R1
  pop   $00
  pop   $01
  pop   c
  pop   b
  ret
;; -----------------------------------------------------------------------------
;; CopyBufToWram ($358D)
;; Copy the 128-byte bank 1 buffer ($80-$FF) to work RAM at VRMAD (auto-increment).
;; -----------------------------------------------------------------------------
CopyBufToWram:
  push  b
  mov   #$80, $00
  mov   #$20, b
.loop:
  ld    @R0
  st    vtrbf
  inc   $00
  ld    @R0
  st    vtrbf
  inc   $00
  ld    @R0
  st    vtrbf
  inc   $00
  ld    @R0
  st    vtrbf
  inc   $00
  dbnz  b, .loop
  pop   b
  ret
;; -----------------------------------------------------------------------------
;; CopyWramToBuf ($35AF)
;; Copy 128 bytes of work RAM at VRMAD into the bank 1 buffer ($80-$FF).
;; -----------------------------------------------------------------------------
CopyWramToBuf:
  push  b
  mov   #$80, $00
  mov   #$20, b
.loop:
  ld    vtrbf
  st    @R0
  inc   $00
  ld    vtrbf
  st    @R0
  inc   $00
  ld    vtrbf
  st    @R0
  inc   $00
  ld    vtrbf
  st    @R0
  inc   $00
  dbnz  b, .loop
  pop   b
  ret
;; -----------------------------------------------------------------------------
;; SwapBufWithWram ($35D1)
;; Exchange the bank 1 buffer ($80-$FF) with 128 bytes of work RAM at VRMAD, 32 bytes
;; at a time through bank 1 $10-$2F.
;; -----------------------------------------------------------------------------
SwapBufWithWram:
  push  b
  push  c
  push  vrmad1
  push  vrmad2
  mov   #$80, $00
  mov   #$04, b
.chunk:
  mov   #$08, c
  mov   #DataToTransmit, $01
.save:
  ld    @R0
  st    @R1
  inc   $00
  inc   $01
  ld    @R0
  st    @R1
  inc   $00
  inc   $01
  ld    @R0
  st    @R1
  inc   $00
  inc   $01
  ld    @R0
  st    @R1
  inc   $00
  inc   $01
  dbnz  c, .save
  ld    $00
  sub   #$20
  st    $00
  mov   #$08, c
.fromWram:
  ld    vtrbf
  st    @R0
  inc   $00
  ld    vtrbf
  st    @R0
  inc   $00
  ld    vtrbf
  st    @R0
  inc   $00
  ld    vtrbf
  st    @R0
  inc   $00
  dbnz  c, .fromWram
  ld    vrmad1
  sub   #$20
  st    vrmad1
  mov   #DataToTransmit, $01
  mov   #$08, c
.toWram:
  ld    @R1
  st    vtrbf
  inc   $01
  ld    @R1
  st    vtrbf
  inc   $01
  ld    @R1
  st    vtrbf
  inc   $01
  ld    @R1
  st    vtrbf
  inc   $01
  dbnz  c, .toWram
  dbnz  b, .chunk
  pop   vrmad2
  pop   vrmad1
  pop   c
  pop   b
  ret

;; -----------------------------------------------------------------------------
;; WaitABReleased ($364F)
;; Unreferenced: like WaitDpadReleased but for A/B.
;; -----------------------------------------------------------------------------
WaitABReleased:
  set1  p3int, $00
  set1  pcon, $00
  clr1  p3int, $00
  ld    p7
  and   #$01
  bnz   .return
  ld    Buttons_Current
  and   #$30
  bnz   WaitABReleased
.return:
  ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; -----------------------------------------------------------------------------
;; WaitDpadReleased ($3662)
;; HALT until no d-pad direction is held (or the controller is plugged in).
;; -----------------------------------------------------------------------------
WaitDpadReleased:
  set1  p3int, $00 ; enable P3 IRQ
  set1  pcon, $00  ; halt
  clr1  p3int, $00 ; now disable it again
  ld    p7         ; check the 5V detect pin
  and   #$01
  bnz   .Still_In  ; 1 = VMU is inserted in the controller
  ld    Buttons_Current
  and   #%00001111
  bnz   WaitDpadReleased ; loop untill the player is not holding any Dpad direction
.Still_In:
  ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; -----------------------------------------------------------------------------
;; WaitAllButtonsReleased ($3675)
;; HALT until no button at all is held (or the controller is plugged in).
;; -----------------------------------------------------------------------------
WaitAllButtonsReleased:
  set1  p3int, $00 ; enable P3 IRQ
  set1  pcon, $00  ; halt
  clr1  p3int, $00 ; disable P3 again
  ld    p7         ; check the 5V detect pin
  and   #$01
  bnz   .Still_In ; 1 = VMU is inserted in the controller
  ld    Buttons_Current
  bnz   WaitAllButtonsReleased
.Still_In:
  ret
  
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; -----------------------------------------------------------------------------
;; ClearUserRam ($3686)
;; Zero all of RAM bank 1 (the application's bank).
;; -----------------------------------------------------------------------------
ClearUserRam:
  set1  psw, rambk0 ; set to USER bank
  mov   #$00, $00
.loop:
  mov   #$00, @R0
  inc   $00
  ld    $00
  bnz   .loop
  clr1  psw, rambk0
  ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; -----------------------------------------------------------------------------
;; WaitKeyEvent ($3696)
;; Main input routine for menus. HALTs until something happens and returns it in ACC:
;; A, B, Left, Right return immediately while held; Up/Down only on a half-second tick
;; (slow auto-repeat). System events ($FF/$FE/$FD/$FC, see CheckSystemEvents) win.
;; B on entry is overwritten with the current BiosMode (used to detect MODE).
;; -----------------------------------------------------------------------------
WaitKeyEvent:
  push  b
  push  psw
  clr1  psw, rambk0
  ld    BiosMode
  st    b
.loop:
  set1  p3int, $00
  set1  pcon, $00
  clr1  p3int, $00
  call  CheckSystemEvents
  bnz   WaitKeyEvent_return
  ld    Buttons_Current
  and   #$10
  bnz   WaitKeyEvent_return
  ld    Buttons_Current
  and   #$20
  bnz   WaitKeyEvent_return
  ld    Buttons_Current
  and   #$04
  bnz   WaitKeyEvent_return
  ld    Buttons_Current
  and   #$08
  bnz   WaitKeyEvent_return
  ld    HalfSecTicks
  bz    .loop
  mov   #$00, HalfSecTicks
  ld    Buttons_Current
  and   #$01
  bnz   WaitKeyEvent_return
  ld    Buttons_Current
  and   #$02
WaitKeyEvent_return:
  pop   psw
  pop   b
  ret
;; -----------------------------------------------------------------------------
;; WaitKeyEventSlow ($36D8)
;; Like WaitKeyEvent, but only A/B are immediate; all four directions wait for a
;; half-second tick.
;; -----------------------------------------------------------------------------
WaitKeyEventSlow:
  push  b
  push  psw
  clr1  psw, rambk0
  ld    BiosMode
  st    b
.loop:
  set1  p3int, $00
  set1  pcon, $00
  clr1  p3int, $00
  call  CheckSystemEvents
  bnz   .return
  ld    Buttons_Current
  and   #$10
  bnz   .return
  ld    Buttons_Current
  and   #$20
  bnz   .return
  ld    HalfSecTicks
  bz    .loop
  mov   #$00, HalfSecTicks
  ld    Buttons_Current
  and   #$01
  bnz   .return
  ld    Buttons_Current
  and   #$02
  bnz   .return
  ld    Buttons_Current
  and   #$04
  bnz   .return
  ld    Buttons_Current
  and   #$08
.return:
  brf   WaitKeyEvent_return
;; -----------------------------------------------------------------------------
;; WaitKeyEventRepeat ($3718)
;; Like WaitKeyEvent with faster d-pad repeat: A/B immediate, directions once
;; FastTicks (base timer interrupt 1) has counted 4.
;; -----------------------------------------------------------------------------
WaitKeyEventRepeat:
  push  b
  push  psw
  clr1  psw, rambk0
  ld    BiosMode
  st    b
  call  FastTickOn
  mov   #$00, FastTicks
.loop:
  set1  p3int, $00
  set1  pcon, $00
  clr1  p3int, $00
  call  CheckSystemEvents
  bnz   .return
  ld    Buttons_Current
  and   #$10
  bnz   .return
  ld    Buttons_Current
  and   #$20
  bnz   .return
  ld    FastTicks
  be    #$04, .loop
  bp    psw, cy, .loop
  ld    Buttons_Current
  and   #$01
  bnz   .return
  ld    Buttons_Current
  and   #$02
  bnz   .return
  ld    Buttons_Current
  and   #$04
  bnz   .return
  ld    Buttons_Current
  and   #$08
.return:
  call  FastTickOff
  brf   WaitKeyEvent_return
;; -----------------------------------------------------------------------------
;; CheckSystemEvents ($3760)
;; Shared by the WaitKeyEvent family (B = BiosMode at entry). Out: ACC
;;   $FF  controller plugged in
;;   $FD  BiosMode changed (MODE was pressed)
;;   $FC  another VMU connected and CopyRxArm == 1, unless A alone is held
;;        (holding A suppresses it: CopyRxArm = $FF)
;;   $FE  sleep requested and SleepCtl says the caller handles it ($80 context)
;;   $00  nothing; auto-sleep/SLEEP may have been serviced in here (SleepUntilWake)
;; SleepCtl: bit0 toggled by SLEEP, $40 = never sleep here, $80 = return $FE.
;; IdleTicks wrapping to 0 (~2 minutes without a button) means auto-sleep.
;; -----------------------------------------------------------------------------
CheckSystemEvents:
  ld    p7
  and   #$01
  bnz   .pluggedIn
  ld    IdleTicks
  bz    .sleepCheck
  ld    SleepCtl
  and   #$01
  bnz   .sleepCheck
  ld    BiosMode
  xor   b
  bnz   .modeChanged
  ld    p7
  and   #$09
  be    #$08, .vmuConnected
  br    .none
.vmuConnected:
  ld    CopyRxArm
  bz    .none
  be    #$FF, .none
  ld    Buttons_Current
  bne   #$10, .startReceive
  mov   #$FF, CopyRxArm
  br    .none
.startReceive:
  mov   #$FC, acc
  ret
.none:
  mov   #$00, acc
  ret
.pluggedIn:
  mov   #$FF, acc
  ret
.sleepCheck:
  ld    IdleTicks
  bnz   .sleepRequested
  br    .sleepContext
.sleepRequested:
  ld    SleepCtl
  be    #$01, .sleepHere
  and   #$01
  bz    .none
.sleepContext:
  ld    SleepCtl
  bz    .sleepHere
  and   #$C0
  be    #$40, .none
  mov   #$FE, acc
  ret
.sleepHere:
  ld    FastTickDisabled
  bnz   .sleepNoFastTick
  call  FastTickOff
  callf SleepUntilWake
  call  FastTickOn
  clr1  p3int, $00
  br    .none
.sleepNoFastTick:
  callf SleepUntilWake
  clr1  p3int, $00
  br    .none
.modeChanged:
  mov   #$FD, acc
  ret
;; -----------------------------------------------------------------------------
;; DrawChar6x8 ($37D2)
;; Draw ASCII character ACC from the 6x8 font at text cell (CursorX 0-7, CursorY 0-3).
;; Cells are 6 pixels wide, so they straddle XRAM bytes: the glyph is shifted into
;; place and merged with CellMaskLeft/CellMaskRight. TextInvert != 0 draws inverted.
;; Out-of-range cells are ignored. Preserves all registers.
;; -----------------------------------------------------------------------------
DrawChar6x8:
  push  acc
  push  b
  push  c
  push  CursorX
  push  CursorY
  push  trh
  push  trl
  push  ocr
  mov   #$81, ocr                       ; OCR $81: XRAM is only writable on the RC clock
  mov   #<FontAscii6x8, trl
  mov   #>FontAscii6x8, trh
  add   trl                             ; font plane 0 = $E800 + character
  st    trl
  mov   #$00, $64
  ld    CursorX
  be    #$07, .checkRow
  bp    psw, cy, .checkRow
  jmp   .return
.checkRow:
  ld    CursorY
  be    #$03, .inRange
  bp    psw, cy, .inRange
  jmp   .return
.inRange:
  ld    CursorX
  st    c
  mov   #$00, acc
  mov   #$06, b
  mul
  ld    c
  st    CursorX
  and   #$07
  st    $66
  ld    CursorX
  and   #$38
  ror
  ror
  ror
  or    #$80
  st    $65
  ld    CursorY
  rol
  rol
  rol
  st    CursorY
  and   #$08
  bz    .checkBank
  ld    $65
  add   #$40
  st    $65
.checkBank:
  ld    CursorY
  and   #$10
  bz    .masks
  mov   #$01, $64
.masks:
  push  trl
  push  trh
  mov   #<CellMaskLeft, trl
  mov   #>CellMaskLeft, trh
  ld    $66
  ldc
  st    $6A
  mov   #<CellMaskRight, trl
  mov   #>CellMaskRight, trh
  ld    $66
  ldc
  st    $6B
  pop   trh
  pop   trl
  ld    $64
  st    xbnk
  ld    $65
  st    $02
  inc   acc
  st    $03
  mov   #$08, c
.row:
  mov   #$00, $68
  mov   #$00, $69
  mov   #$00, acc
  ldc
  st    $68
  ld    TextInvert
  bz    .shift
  ld    $68
  xor   #$FC
  st    $68
.shift:
  ld    $66
  st    b
  bz    .merge
.shiftLoop:
  clr1  psw, cy
  ld    $68
  rorc
  st    $68
  ld    $69
  rorc
  st    $69
  dbnz  b, .shiftLoop
.merge:
  ld    @R2
  and   $6A
  or    $68
  st    @R2
  ld    $66
  be    #$02, .nextLine
  bp    psw, cy, .nextLine
  ld    @R3
  and   $6B
  or    $69
  st    @R3
.nextLine:
  ld    $02
  and   #$0F
  be    #$06, .nextPair
  bn    psw, cy, .nextPair
  ld    $02
  add   #$06
  st    $02
  inc   acc
  st    $03
  br    .nextPlane
.nextPair:
  ld    $02
  add   #$0A
  st    $02
  inc   acc
  st    $03
.nextPlane:
  inc   trh
  dbnz  c, .row
.return:
  pop   ocr
  pop   trl
  pop   trh
  pop   CursorY
  pop   CursorX
  pop   c
  pop   b
  pop   acc
  ret

CellMaskLeft:
  .byte $03, $81, $C0, $E0, $F0, $F8, $FC, $FE
CellMaskRight:
  .byte $FF, $FF, $FF, $7F, $3F, $1F, $0F, $07

;; -----------------------------------------------------------------------------
;; DrawGlyph8x8 ($38F0)
;; Draw big glyph ACC (FontGlyphs8x8) at 8x8 cell (CursorX 0-5, CursorY 0-3).
;; TextInvert != 0 draws inverted. Preserves all registers.
;; -----------------------------------------------------------------------------
DrawGlyph8x8:
  push  acc
  push  b
  push  c
  push  trl
  push  trh
  push  ocr
  mov   #$81, ocr
  mov   #$00, xbnk
  rol
  rol
  rol
  st    b
  and   #$F8
  mov   #<FontGlyphs8x8, trl
  mov   #>FontGlyphs8x8, trh
  add   trl
  st    trl
  ld    b
  and   #$01
  addc  trh
  st    trh
  ld    CursorX
  be    #$06, .return
  bn    psw, cy, .return
  or    #$80
  st    $65
  ld    CursorY
  be    #$04, .return
  bn    psw, cy, .return
  ror
  ror
  and   #$C0
  st    $68
  and   #$80
  bz    .normal
  mov   #$01, xbnk
.normal:
  ld    $68
  and   #$40
  add   $65
  st    $02
  ld    TextInvert
  bnz   .inverted
  mov   #$00, acc
  mov   #$04, c
  st    b
.copy:
  ld    b
  ldc
  st    @R2
  inc   b
  ld    $02
  add   #$06
  st    $02
  ld    b
  ldc
  st    @R2
  inc   b
  ld    $02
  add   #$0A
  st    $02
  dbnz  c, .copy
  br    .return
.inverted:
  mov   #$00, acc
  mov   #$04, c
  st    b
.copyInv:
  ld    b
  ldc
  xor   #$FF
  st    @R2
  inc   b
  ld    $02
  add   #$06
  st    $02
  ld    b
  ldc
  xor   #$FF
  st    @R2
  inc   b
  ld    $02
  add   #$0A
  st    $02
  dbnz  c, .copyInv
.return:
  pop   ocr
  pop   trh
  pop   trl
  pop   c
  pop   b
  pop   acc
  ret
;; -----------------------------------------------------------------------------
;; ClearCell8x8 ($39A1)
;; Blank one 8x8 cell (filled black instead if TextInvert != 0).
;; -----------------------------------------------------------------------------
ClearCell8x8:
  push  acc
  push  b
  push  ocr
  mov   #$81, ocr
  mov   #$00, xbnk
  ld    CursorX
  be    #$06, .return
  bn    psw, cy, .return
  or    #$80
  st    $65
  ld    CursorY
  be    #$04, .return
  bn    psw, cy, .return
  ror
  ror
  and   #$C0
  st    $68
  and   #$80
  bz    .fill
  mov   #$01, xbnk
.fill:
  ld    $68
  and   #$40
  add   $65
  st    $02
  mov   #$04, c
  ld    TextInvert
  bz    .white
  mov   #$FF, acc
  st    b
  br    .loop
.white:
  mov   #$00, acc
  st    b
.loop:
  ld    b
  st    @R2
  ld    $02
  add   #$06
  st    $02
  ld    b
  st    @R2
  ld    $02
  add   #$0A
  st    $02
  dbnz  c, .loop
.return:
  pop   ocr
  pop   b
  pop   acc
  ret

.org $3A05
;; -----------------------------------------------------------------------------
;; DrawString ($3A05)
;; Draw a zero-terminated string with DrawChar6x8. $0D moves down a row, $0A back to
;; column 0 (so "\r\n" is a newline); text wraps from column 7 to column 0 of the
;; same row. Preserves registers and the cursor.
;; -----------------------------------------------------------------------------
DrawString:
  push  acc
  push  b
  push  trh
  push  trl
  push  CursorX
  push  CursorY
  mov   #$00, acc
  st    b
.loop:
  ld    b
  inc   b
  ldc
  bz    .return
  be    #$0D, .cr
  be    #$0A, .lf
  call  DrawChar6x8
  inc   CursorX
  ld    CursorX
  be    #$07, .loop
  bp    psw, cy, .loop
  mov   #$00, CursorX
  br    .loop
.return:
  pop   CursorY
  pop   CursorX
  pop   trl
  pop   trh
  pop   b
  pop   acc
  ret
.cr:
  inc   CursorY
  ld    CursorY
  be    #$03, .loop
  bp    psw, cy, .loop
  mov   #$00, CursorY
  br    .loop
.lf:
  mov   #$00, CursorX
  br    .loop

;; -----------------------------------------------------------------------------
;; DrawBcd16 ($3A55)
;; Unreferenced: four BCD digits at @R0 in the 6x8 font.
;; -----------------------------------------------------------------------------
DrawBcd16:
  push  CursorX
  push  CursorY
  push  trh
  push  trl
  push  $00
  push  b
  push  acc
  mov   #$02, b
.loop:
  push  b
  ld    @R0
  st    b
  and   #$F0
  ror
  ror
  ror
  ror
  call  NibbleToHexAscii
  call  DrawChar6x8
  inc   CursorX
  ld    b
  and   #$0F
  call  NibbleToHexAscii
  call  DrawChar6x8
  inc   $00
  inc   CursorX
  pop   b
  dbnz  b, .loop
  pop   acc
  pop   b
  pop   $00
  pop   trl
  pop   trh
  pop   CursorY
  pop   CursorX
  ret

;; -----------------------------------------------------------------------------
;; DrawBcd3Digits ($3A97)
;; The low three BCD digits of @R0:@R0+1 in the 6x8 font (block counts).
;; -----------------------------------------------------------------------------
DrawBcd3Digits:
  push  CursorX
  push  CursorY
  push  trh
  push  trl
  push  $00
  push  b
  push  acc
  ld    @R0
  and   #$0F
  call  NibbleToHexAscii
  call  DrawChar6x8
  inc   $00
  inc   CursorX
  ld    @R0
  st    b
  and   #$F0
  ror
  ror
  ror
  ror
  call  NibbleToHexAscii
  call  DrawChar6x8
  inc   CursorX
  ld    b
  and   #$0F
  call  NibbleToHexAscii
  call  DrawChar6x8
  pop   acc
  pop   b
  pop   $00
  pop   trl
  pop   trh
  pop   CursorY
  pop   CursorX
  ret
;; -----------------------------------------------------------------------------
;; DrawHexByte ($3AD6)
;; ACC as two hex digits in the 6x8 font (dates, error codes).
;; -----------------------------------------------------------------------------
DrawHexByte:
  push  CursorX
  push  CursorY
  push  trh
  push  trl
  push  b
  push  acc
  st    b
  and   #$F0
  ror
  ror
  ror
  ror
  call  NibbleToHexAscii
  call  DrawChar6x8
  inc   CursorX
  ld    b
  and   #$0F
  call  NibbleToHexAscii
  call  DrawChar6x8
  pop   acc
  pop   b
  pop   trl
  pop   trh
  pop   CursorY
  pop   CursorX
  ret
;; -----------------------------------------------------------------------------
;; DrawBcdByteBig ($3B05)
;; ACC as two BCD digits in big 8x8 glyphs.
;; -----------------------------------------------------------------------------
DrawBcdByteBig:
  push  CursorX
  push  CursorY
  push  trh
  push  trl
  push  b
  push  acc
  st    b
  and   #$F0
  ror
  ror
  ror
  ror
  call  DrawGlyph8x8
  inc   CursorX
  ld    b
  and   #$0F
  call  DrawGlyph8x8
  pop   acc
  pop   b
  pop   trl
  pop   trh
  pop   CursorY
  pop   CursorX
  ret
;; -----------------------------------------------------------------------------
;; DrawBcd16Big ($3B30)
;; Four BCD digits at @R0 in big 8x8 glyphs (the year).
;; -----------------------------------------------------------------------------
DrawBcd16Big:
  push  CursorX
  push  CursorY
  push  trh
  push  trl
  push  $00
  push  b
  push  acc
  mov   #$02, b
.loop:
  push  b
  ld    @R0
  st    b
  and   #$F0
  ror
  ror
  ror
  ror
  call  DrawGlyph8x8
  inc   CursorX
  ld    b
  and   #$0F
  call  DrawGlyph8x8
  inc   $00
  inc   CursorX
  pop   b
  dbnz  b, .loop
  pop   acc
  pop   b
  pop   $00
  pop   trl
  pop   trh
  pop   CursorY
  pop   CursorX
  ret
;; -----------------------------------------------------------------------------
;; NibbleToHexAscii ($3B6E)
;; ACC (0-15) -> '0'-'9' / 'a'-'f'.
;; -----------------------------------------------------------------------------
NibbleToHexAscii:
  be    #$09, .digit
  bp    psw, cy, .digit
  add   #$27
.digit:
  add   #$30
  ret

; ==== ENABLE FLASH SAVE ICON ======
.org $3B79
EnableFlashIcon:
  push  acc
  push  ocr
  ld    ocr
  be    #$81, .Skip
  mov   #$81, ocr           ; set clock mode to control flash
.Skip:
  mov   #$02, xbnk
  mov   #$01, xram_0184     ; set flash read icon to active
FlashEpilogue:
  pop   ocr
  ld    ocr                 ; restore previous clock state
  be    #$81, .End
.End:
  pop   acc
  ret

.org $3B95
DisableFlashIcon:
  push  acc
  push  ocr
  ld    ocr
  be    #$81, .skip
  mov   #$81, ocr
.skip:
  mov   #$02, xbnk
  mov   #$00, xram_0184
  br    FlashEpilogue

;; -----------------------------------------------------------------------------
;; ClearScreenAndIcons ($3BA9)
;; Clear both XRAM banks, then write TextInvert to the 6 icon bytes in XBNK 2.
;; -----------------------------------------------------------------------------
ClearScreenAndIcons:
  push  b
  call  ClearScreen
  ld    TextInvert
  st    b
  mov   #$02, xbnk
  mov   #$80, $02
.loop:
  ld    b
  push  ocr
  mov   #$81, ocr
  st    @R2
  pop   ocr
  inc   $02
  ld    $02
  be    #$86, .return
  br    .loop
.return:
  pop   b
  ret
;; -----------------------------------------------------------------------------
;; ClearHalfScreen ($3BCD)
;; Clear the XRAM bank currently selected in XBNK (16 lines) to TextInvert.
;; -----------------------------------------------------------------------------
ClearHalfScreen:
  push  acc
  push  b
  mov   #$80, $02
  ld    TextInvert
  st    b
.loop:
  ld    b
  push  ocr
  mov   #$81, ocr
  st    @R2
  inc   $02
  st    @R2
  inc   $02
  st    @R2
  inc   $02
  st    @R2
  inc   $02
  st    @R2
  inc   $02
  st    @R2
  inc   $02
  pop   ocr
  ld    $02
  and   #$0F
  bne   #$0C, .loop
  ld    $02
  add   #$04
  st    $02
  bnz   .loop
  pop   b
  pop   acc
  ret
;; -----------------------------------------------------------------------------
;; ClearScreen ($3C07)
;; Clear both halves of the LCD.
;; -----------------------------------------------------------------------------
ClearScreen:
  mov   #$00, xbnk
  call  ClearHalfScreen
  mov   #$01, xbnk
  call  ClearHalfScreen
  ret
;; -----------------------------------------------------------------------------
;; GameModeLaunch ($3C12)
;; BiosMode 1, A pressed: light the game icon, check the root block is formatted and
;; that FindGame accepts the directory's game entry, then start it: quartz clock,
;; SP = $7F, RAM bank 1, toggle EXT.0 so instruction fetches come from flash, and
;; jump to flash $0000 (the game's reset vector).
;; Errors: "Format memory", "No saved game" (no $CC entry), "Game is damaged".
;; -----------------------------------------------------------------------------
GameModeLaunch:
  push  ocr
  mov   #$81, ocr
  mov   #$02, xbnk
  mov   #$00, xram_0181
  mov   #$10, xram_0182
  mov   #$00, xram_0183
  mov   #$00, xbnk
  pop   ocr
  mov   #$00, BatteryCheck
  mov   #$01, fpr
  mov   #$01, FlashBankTemp
  mov   #$FE, trh
  mov   #$00, trl
  mov   #$10, b
.checkFormat:
  ldf
  xor   #$55
  bnz   .unformatted
  inc   trl
  dbnz  b, .checkFormat
  br    .findGame
.unformatted:
  mov   #$FF, acc
  br    GameLaunchError
.findGame:
  call  FindGame
  bnz   GameLaunchError
; Start GAME from flash, calling RESET interrupt
  mov   #$A3, ocr    ; Initialize clock (Quartz, /6)
  mov   #$7F, sp     ; Initialize stack
  set1  psw, rambk0  ; Swap to RAM bank 1
  not1  ext, $00     ; Swap to executing from Flash
  jmpf  $00          ; Jump to user's reset ISR
;; -----------------------------------------------------------------------------
;; ExitToBios ($3C5C)
;; EXIT_EX ($01F0) lands here when a game quits with MODE: reinitialise the hardware
;; and Maple, clear the game's RAM bank and return to MainMenu with the clock
;; selected (BiosMode 2, the mode after "game").
;; -----------------------------------------------------------------------------
ExitToBios:
  mov   #$A3, ocr
  mov   #$7F, sp
  clr1  psw, rambk0
  call  HardwareInit
  callf MapleHwReset
  callf MapleInitAddress
  clr1  vsel, $00
  clr1  vsel, $01
  clr1  mapletxrxctl, $02
  mov   #$02, BiosMode
  call  ClearUserRam
  jmpf  MainMenu
GameLaunchError:
  clr1  p3int, $00
  mov   #$01, xbnk
  call  ClearHalfScreen
  be    #$FE, .noGame
  be    #$FD, .damaged
  mov   #<Str_FormatMemory, trl
  mov   #>Str_FormatMemory, trh
  br    .draw
.noGame:
  mov   #<Str_NoSavedGame, trl
  mov   #>Str_NoSavedGame, trh
  br    .draw
.damaged:
  mov   #<Str_GameDamaged, trl
  mov   #>Str_GameDamaged, trh
.draw:
  mov   #$00, CursorX
  mov   #$00, CursorY
  call  DrawString
  mov   #$01, IdleTicks
.wait:
  call  WaitKeyEvent
  be    #$FF, .exit
  be    #$FD, .exit
  br    .wait
.exit:
  call  ClearUserRam
  jmpf  MainMenu
;; -----------------------------------------------------------------------------
;; FmWrtExGuard ($3CB7)
;; FM_WRT_EX / FM_WRTA_EX ($0100/$0108) land here. A game may only write to its own
;; blocks: FmBank must be 0 and FmAddrHi <= 2 * GameLastBlock + 1 (the last page of
;; the game file), otherwise ACC = $FF and nothing is written. On success the
;; 128-byte page at bank 1 $80 is programmed (FM_WRT); FmAddrLo is rounded down to a
;; page boundary. The flash access icon is lit meanwhile. Out: ACC = 0 ok.
;; (Calling FlashLib's write at $E024 directly skips this check.)
;; -----------------------------------------------------------------------------
FmWrtExGuard:
  call  EnableFlashIcon                 ; flash access icon on
  ld    FmBank                          ; FmBank must be 0
  bnz   .refuse                         ; refuse
  push  psw                             ; GameLastBlock is in bank 0
  clr1  psw, rambk0     ; swap to rambank 0
  ld    GameLastBlock                   ; GameLastBlock
  pop   psw             
  bz    .refuse                         ; no game file: refuse
  set1  psw, cy                         ; ACC = 2 * GameLastBlock + 1
  rolc
  bp    psw, cy, .refuse                ; GameLastBlock >= 128 (or 0, checked above): refuse
  sub   FmAddrHi                        ; FmAddrHi past the game's last page?
  bp    psw, cy, .refuse
  ld    FmAddrLo                        ; round the address down to a page boundary
  and   #$80                        ; aligned to 128 bytes
  st    FmAddrLo
  callf FlashWriteEntry                 ; FlashWritePage (FM_WRT)
  mov   #$00, acc
; === DISABLE FLASH SAVE ICON =====
.return:
  call  DisableFlashIcon
  ret
.refuse:
  mov   #$FF, acc
  br    .return
;; -----------------------------------------------------------------------------
;; FindGame ($3CE6)
;; Find the first game ($CC) directory entry and validate it: first block 0, size
;; 1-255 blocks, header offset 1-255 (the VMS header can't sit in block 0, that's
;; where the interrupt vectors go). Sets GameLastBlock = size - 1.
;; Out: ACC = 0 ok, $FE no game, $FD entry is inconsistent.
;; -----------------------------------------------------------------------------
FindGame:
  mov   #$01, fpr
  mov   #$01, FlashBankTemp
  mov   #$FE, trh
  mov   #$46, trl               ; Load FAT First (0x1FE46)
  callf PrepareFlashBlockRead
  ld    FlashBankTemp
  st    FatBank
  ld    trh
  st    FatAddrHi
  ld    trl
  st    FatAddrLo
  mov   #$FE, trh
  mov   #$4A, trl
  callf PrepareFlashBlockRead
  ld    MathHi
  st    DirBlock
.block:
  mov   #$10, c
.entry:
  ldf
  bz    .next
  be    #$CC, .found
.next:
  ld    trl
  add   #$20
  st    trl
  ld    trh
  addc  #$00
  st    trh
  dbnz  c, .entry
  ld    FatBank
  st    fpr
  st    FlashBankTemp
  ld    FatAddrHi
  st    trh
  ld    FatAddrLo
  st    trl
  ld    DirBlock
  clr1  psw, cy
  rolc
  st    c
  mov   #$00, acc
  rolc
  st    MathHi
  ld    trl
  add   c
  st    trl
  ld    trh
  add   MathHi
  st    trh
  ldf
  bne   #$FA, .nextBlock
  inc   trl
  ldf
  dec   trl
  be    #$FF, .none
  bz    .nextBlock
  br    .none
.nextBlock:
  inc   trl
  ldf
  bnz   .none
  dec   trl
  callf PrepareFlashBlockRead
  ld    MathHi
  st    DirBlock
  br    .block
.found:
  inc   trl
  inc   trl
  ldf
  bnz   .damaged
  inc   trl
  ldf
  bnz   .damaged
  ld    trl
  add   #$16
  st    trl
  ldf
  bnz   .damaged
  dec   trl
  ldf
  bz    .damaged
  dec   acc
  st    GameLastBlock
  inc   trl
  inc   trl
  ldf
  bz    .damaged
  inc   trl
  ldf
  bnz   .damaged
  mov   #$00, acc
  ret
.none:
  mov   #$FE, acc
  ret
.damaged:
  mov   #$FD, acc
  ret

Str_NoSavedGame:
.string 19 "No saved\r\n    game"
Str_GameDamaged:
.string 19 "Game is \r\n damaged"

;; -----------------------------------------------------------------------------
;; BaseTimerIsr ($3DC9)
;; Base timer interrupt; TIMER_EX ($0130) calls it too. Interrupt 1 (fast tick):
;; FastTicks++ while FastTickDisabled == 0. Interrupt 0 (every half second):
;;   - ClockTick (the date/time keeps running even while a game runs)
;;   - no button held -> remember the last state at $72, clear Buttons_Current
;;   - unless BatteryCheck == $FF, count ticks with P7.1 (battery OK) low in
;;     BatteryCheck; on the 6th:
;;     "Please change battery", then "return" into LowBatteryHalt by pushing $3E3E
;;     onto a fresh stack and executing RETI
;;   - IdleTicks++ (auto-sleep timeout) and HalfSecTicks++ (general timeouts)
;; -----------------------------------------------------------------------------
BaseTimerIsr:
  push  acc
  push  b
  push  c
  ld    psw                             ; the caller's PSW is restored on exit
  st    b
  clr1  psw, rambk0
  ld    FastTickDisabled
  bnz   .checkHalfSecond
  bn    btcr, $03, .checkHalfSecond ; if base timer irq1 not set then branch
  clr1  btcr, $03             ; otherwise clear base timer irq1
  inc   FastTicks
.checkHalfSecond:
  bn    btcr, $01, .return ; if base timer irq0 not set then branch
  clr1  btcr, $01             ; otherwise clear base timer irq0
  callf ClockTickEntry                  ; ClockTick
  ld    p3                              ; any button held?
  xor   #$FF                  ; xor causes pressed buttons to be set
  bnz   .checkBattery            ; branch if any are pressed
  ld    Buttons_Current                 ; nothing held: previous state -> Buttons_Last, clear Buttons_Current
  st    Buttons_Last
  mov   #$00, Buttons_Current
.checkBattery:
  ld    BatteryCheck                   ; load  battery check
  be    #$FF, .ticks                    ; BatteryCheck == $FF: battery check disabled
  ld    p7                    ; load Port7
  and   #$02                            ; P7.1 = 1: battery voltage OK
  bnz   .ticks            ; branch if low voltage not detected
  inc   BatteryCheck                    ; count low-battery ticks
  ld    BatteryCheck
  be    #$06, .ticks
  bp    psw, cy, .ticks
  mov   #<Str_ChangeBattery, trl        ; Str_ChangeBattery
  mov   #>Str_ChangeBattery, trh
  mov   #$00, TextInvert
  mov   #$00, CursorX
  mov   #$00, CursorY
  callf ClearScreen
  call  DrawString
  mov   #$7F, sp                        ; fresh stack, fake return address $3E3E (LowBatteryHalt)
  mov   #$3E, acc
  push  acc
  mov   #$3E, acc
  push  acc
  mov   #$FF, BatteryCheck
  reti
.ticks:
  inc   IdleTicks                       ; one more half second without a button press
  inc   HalfSecTicks
.return:
  ld    b
  st    psw
  pop   c
  pop   b
  pop   acc
  ret

;; -----------------------------------------------------------------------------
;; LowBatteryHalt ($3E3E)
;; Reached only through BaseTimerIsr's RETI trick, which is why a straight
;; disassembly finds no reference to it. Reinitialises everything, clears RAM bank 1
;; and sits in WaitKeyEvent: SLEEP still works, plugging into a controller goes to
;; MapleMode, everything else is ignored until the batteries are replaced.
;; -----------------------------------------------------------------------------
LowBatteryHalt:
  mov   #$A3, ocr
  callf HardwareInit
  callf MapleHwReset
  callf MapleInitAddress
  callf ClearUserRam
  clr1  vsel, $00
  clr1  vsel, $01
  clr1  mapletxrxctl, $02
  mov   #$01, IdleTicks
.loop:
  callf WaitKeyEvent
  be    #$FF, MapleMode
  be    #$FE, .sleep
  br    .loop
.sleep:
  callf SleepUntilWake
  br    .loop

;; -----------------------------------------------------------------------------
;; P3Isr ($3E66)
;; Button (P3) interrupt. IdleTicks = 1 (restart the auto-sleep timer), refresh
;; Buttons_Current (1 = pressed) and the newly-pressed mask; MODE cycles BiosMode
;; 0 -> 1 -> 2 -> 0 (any other value becomes 2), SLEEP toggles SleepCtl bit 0.
;; -----------------------------------------------------------------------------
P3Isr:
  push  acc
  push  psw
  clr1  psw, rambk0
  mov   #$01, IdleTicks                 ; any button: restart the auto-sleep timer
  ld    Buttons_Current
  st    Buttons_Last
  ld    p3                              ; P3 is active low
  xor   #$FF               ; invert them to make it so 0 = released
  st    Buttons_Current
  xor   Buttons_Last       ; set only keys that have changed their states
  and   Buttons_Current    ; if the state changed to "0", mask it out and only keep rising edge differences
  st    Buttons_Diff
  and   #%01000000                      ; MODE newly pressed?
  bz    .Check_Sleep
  inc   BiosMode                        ; MODE: next mode
  ld    BiosMode
  be    #$02, .Check_Sleep
  bp    psw, cy, .Check_Sleep
  bne   #$03, .Set30To2                 ; 3 wraps to 0, anything else (> 3) becomes 2
  mov   #$00, BiosMode
  br    .Check_Sleep
.Set30To2:
  mov   #$02, BiosMode                  ; any unexpected value becomes clock mode
.Check_Sleep:
  ld    Buttons_Diff
  and   #%10000000                      ; SLEEP newly pressed?
  bz    .exit
  not1  SleepCtl, $00                   ; SLEEP: toggle the sleep request
.exit:
  clr1  p3int, $01                      ; acknowledge the P3 interrupt
  pop   psw
  pop   acc
  ret

;; -----------------------------------------------------------------------------
;; MapleMode ($3EA7)
;; The VMU is plugged into a controller (P7.0 high). Switch to the 6 MHz ceramic
;; oscillator, set up P1 for the Maple bus, reset the Maple hardware and spin;
;; all the work happens in MapleRxIsr. The Maple hardware is reset (and the screen
;; cleared) on a Maple bus reset (MAPLESTA.6) or when the P7.2-3 ID pins read back
;; as the complement of the latched MapleIdPins.
;; When the 5V disappears, go back to standalone operation (MapleModeExit).
;; -----------------------------------------------------------------------------
MapleMode:
  clr1  p3int, $00
  call  ClearScreenAndIcons
  clr1  psw, rambk0
  mov   #$FF, BatteryCheck
  mov   #%10100010, ocr                 ; OCR $A2: quartz + CF running
  nop
  nop
  mov   #%10010010, ocr                 ; OCR $92: run from the CF oscillator
  mov   #$AD, p1ddr
  mov   #$BF, p1fcr
  set1  p1, $06
  clr1  p1, $07
  mov   #$00, t1cnt
  callf MapleHwReset
  callf MapleInitAddress
.loop:
  ld    maplesta
  bp    acc, $06, .busReset
  ld    p7
  xor   #$FF
  and   #$0C
  sub   MapleIdPins
  bz    .busReset
  ld    p7
  and   #$01
  bz    MapleModeExit
  br    .loop
.busReset:
  callf MapleHwReset
  callf MapleInitAddress
  callf ClearScreen
  br    .loop
;; -----------------------------------------------------------------------------
;; MapleModeExit ($3EED)
;; Unplugged: restore P1, clear RAM bank 1, stop the buzzer, quartz clock, and drop
;; back into MainMenu in file mode with a sleep request pending (SleepCtl = 1).
;; -----------------------------------------------------------------------------
MapleModeExit:
  mov   #$80, p1ddr
  mov   #$BF, p1fcr
  callf ClearUserRam
  mov   #$FF, t1lr
  mov   #$FF, t1lc
  mov   #$00, t1cnt
  set1  p3int, $00
  clr1  vsel, $00
  clr1  vsel, $01
  clr1  mapletxrxctl, $02
  mov   #%10100011, ocr                 ; OCR $A3: back to the 32kHz quartz, RC + CF stopped
  mov   #$00, BatteryCheck
  mov   #$00, BiosMode
  mov   #$01, SleepCtl
  jmpf  MainMenu

Str_ChangeBattery:
  .string 29 "Please  \r\n change \r\n battery" 

  .byte $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00, $00

  .org $7FF6
  .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
 .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
;; -----------------------------------------------------------------------------
;; FlashLibTable ($E000)
;; Flash library jump table (Sanyo). Only some entries are used by the BIOS:
;;   $E000 FactoryFlashTest       $E003 FactoryFlashEndurance1  $E006 FactoryFlashEndurance2
;;   $E009 FactoryFlashCycles1    $E00C FactoryFlashPageTest    $E00F FactoryFlashCycles2
;;   $E012 FactoryFlashCycles3    $E015 FlashInit               $E018 FlashProgramPage
;;   $E01B FlashVerifyPage        $E01E FlashReadByteBank0      $E021 FlashReadByteBank1
;;   $E024 FlashWritePage         $E027 FlashReadPage           $E02A ClockTick
;;   $E02D UpdateLeapYear
;; Page routines work on 128 bytes: flash address FmBank:FmAddrHi:FmAddrLo, data in
;; bank 1 $80-$FF (R0 is used as the buffer pointer). They expect RAM bank 1.
;; -----------------------------------------------------------------------------
FlashLibTable:
  brf   FactoryFlashTest
  brf   FactoryFlashEndurance1
  brf   FactoryFlashEndurance2
  brf   FactoryFlashCycles1
  brf   FactoryFlashPageTest
  brf   FactoryFlashCycles2
  brf   FactoryFlashCycles3
FlashInitEntry:
  brf   FlashInit
  brf   FlashProgramPage
FlashVerifyEntry:
  brf   FlashVerifyPage
  brf   FlashReadByteBank0
  brf   FlashReadByteBank1
FlashWriteEntry:
  brf   FlashWritePage
FlashReadEntry:
  brf   FlashReadPage
ClockTickEntry:
  brf   ClockTick
UpdateLeapYearEntry:
  brf   UpdateLeapYear

  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
;; -----------------------------------------------------------------------------
;; FactoryFlashTest ($E100)
;; Factory test (never called by the BIOS): fill all 128K of flash with $FF and
;; verify, then $00, then $FF again, reporting bad addresses on P3/P1, then STOP.
;; -----------------------------------------------------------------------------
FactoryFlashTest:
  mov   #$5F, sp
  mov   #$FF, p3ddr
  mov   #$00, p3
  mov   #$FF, p1ddr
  mov   #$00, p1
  callr FlashInit
  mov   #$FF, b
  callr FactoryFill
  callr FactoryVerify
  mov   #$00, b
  callr FactoryFill
  callr FactoryVerify
  mov   #$FF, b
  callr FactoryFill
.stop:
  set1  pcon, $01
  br    .stop
;; -----------------------------------------------------------------------------
;; FactoryFill ($E12E)
;; Program every byte of both flash banks with B, waiting for the toggle bit at the
;; end of each 128-byte page.
;; -----------------------------------------------------------------------------
FactoryFill:
  mov   #$00, trh
  mov   #$00, trl
  mov   #$00, $7D
  ld    $7D
.bank:
  st    fpr
.loop:
  ld    b
  stf
  ld    trl
  and   #$7F
  bne   #$7F, .next
  callr FlashWaitToggle
.next:
  inc   trl
  ld    trl
  bnz   .loop
  inc   trh
  ld    trh
  bnz   .loop
  inc   $7D
  ld    $7D
  bne   #$02, .bank
  ret
;; -----------------------------------------------------------------------------
;; FactoryVerify ($E15C)
;; Compare all of flash against B. Each bad page's address is put on P3/P1 and the
;; routine handshakes with the tester via P7.0 before moving on.
;; -----------------------------------------------------------------------------
FactoryVerify:
  mov   #$00, trh
  mov   #$00, trl
  mov   #$00, $7D
  ld    $7D
.bank:
  st    fpr
.loop:
  ldf
  be    b, .next
  ld    trl
  rolc
  ld    trh
  rolc
  st    p3
  ld    b
  and   #$02
  or    $7D
  rolc
  st    p1
  mov   #$FA, acc
.waitHigh:
  bn    p7, $00, .waitHigh
  dbnz  acc, .waitHigh
  mov   #$FA, acc
.waitLow:
  bp    p7, $00, .waitLow
  dbnz  acc, .waitLow
  ld    trl
  or    #$7F
  st    trl
.next:
  inc   trl
  ld    trl
  bnz   .loop
  inc   trh
  ld    trh
  bnz   .loop
  inc   $7D
  ld    $7D
  bne   #$02, .bank
  set1  p1, $03
  ret
;; -----------------------------------------------------------------------------
;; FlashWaitToggle ($E1AC)
;; Wait for a flash program operation to finish: poll until DQ6 stops toggling.
;; -----------------------------------------------------------------------------
FlashWaitToggle:
  ldf
  st    c
  not1  c, $06
.loop:
  not1  c, $06
  ldf
  xor   c
  bp    acc, $06, .loop
  ret
  .byte $50,$F3,$02,$7F,$00,$FA,$A0
;; -----------------------------------------------------------------------------
;; FactoryFlashEndurance1 ($E1C1)
;; Factory endurance test: $1488 x (fill $00, fill $FF), then count mismatches,
;; show the pass count on P1 and the error count on P3; repeat until an error.
;; -----------------------------------------------------------------------------
FactoryFlashEndurance1:
  mov   #$5F, sp
  mov   #$00, p1fcr
  mov   #$FF, p1ddr
  mov   #$FF, p3ddr
  mov   #$00, p3
  callr FlashInit
  mov   #$00, $77
.pass:
  mov   #$14, $78
  mov   #$88, $79
.cycle:
  mov   #$00, b
  callr FactoryFill
  mov   #$FF, b
  callr FactoryFill
  dbnz  $79, .cycle
  dbnz  $78, .cycle
  callr FactoryCountErrors
  ld    $77
  st    p1
  inc   $77
  ld    $76
  st    p3
  or    $75
  bz    .pass
.stop:
  set1  pcon, $01
  br    .stop
;; -----------------------------------------------------------------------------
;; FactoryFlashEndurance2 ($E203)
;; As FactoryFlashEndurance1 but never stops.
;; -----------------------------------------------------------------------------
FactoryFlashEndurance2:
  mov   #$5F, sp
  mov   #$00, p1fcr
  mov   #$FF, p1ddr
  mov   #$FF, p3ddr
  mov   #$00, p3
  callr FlashInit
  mov   #$00, $77
.pass:
  mov   #$14, $78
  mov   #$88, $79
.cycle:
  mov   #$00, b
  callr FactoryFill
  mov   #$FF, b
  callr FactoryFill
  dbnz  $79, .cycle
  dbnz  $78, .cycle
  callr FactoryCountErrors
  ld    $77
  st    p1
  inc   $77
  ld    $76
  st    p3
  br    .pass
;; -----------------------------------------------------------------------------
;; FactoryCountErrors ($E23F)
;; Count bad 128-byte pages (any byte != B) into $75:$76.
;; -----------------------------------------------------------------------------
FactoryCountErrors:
  mov   #$00, $75
  mov   #$00, $76
  mov   #$00, trh
  mov   #$00, trl
  mov   #$00, $7D
  ld    $7D
.bank:
  st    fpr
.loop:
  ldf
  be    b, .next
  inc   $76
  ld    $76
  bnz   .skipPage
  inc   $75
.skipPage:
  ld    trl
  or    #$7F
  st    trl
.next:
  inc   trl
  ld    trl
  bnz   .loop
  inc   trh
  ld    trh
  bnz   .loop
  inc   $7D
  ld    $7D
  bne   #$02, .bank
  ret
;; -----------------------------------------------------------------------------
;; FactoryFlashCycles1 ($E278)
;; Factory test: $2810 x (fill $00, fill $FF), then STOP.
;; -----------------------------------------------------------------------------
FactoryFlashCycles1:
  mov   #$5F, sp
  callr FlashInit
  mov   #$28, $78
  mov   #$10, $79
.cycle:
  mov   #$00, b
  callr FactoryFill
  mov   #$FF, b
  callr FactoryFill
  dbnz  $79, .cycle
  dbnz  $78, .cycle
.stop:
  set1  pcon, $01
  br    .stop
;; -----------------------------------------------------------------------------
;; FactoryFlashPageTest ($E29A)
;; Factory test: program the first page with $00, then repeatedly verify 10 pages,
;; counting passes on P1, until one fails; then STOP.
;; -----------------------------------------------------------------------------
FactoryFlashPageTest:
  mov   #$5F, sp
  mov   #$00, p1fcr
  mov   #$FF, p1ddr
  mov   #$00, p1
  callr FlashInit
  mov   #$00, fpr
  mov   #$00, trh
  mov   #$00, trl
  mov   #$00, b
  callr FactoryFillPage
  mov   #$00, $77
.loop:
  mov   #$00, trl
  mov   #$0A, c
  callr FactoryVerifyPages
  bnz   .stop
  inc   $77
  ld    $77
  st    p1
  br    .loop
.stop:
  set1  pcon, $01
  br    .stop
FactoryFillPage:
  ld    b
  stf
  ld    trl
  and   #$7F
  be    #$7F, .wait
  inc   trl
  br    FactoryFillPage
.wait:
  callr FlashWaitToggle
  ret
FactoryVerifyPages:
  ldf
  xor   b
  bnz   .return
  inc   trl
  ld    trl
  and   #$7F
  bnz   FactoryVerifyPages
  not1  trl, $07
  dbnz  c, FactoryVerifyPages
.return:
  ret
;; -----------------------------------------------------------------------------
;; FactoryFlashCycles2 ($E2F7)
;; Factory test: $C450 x (fill $00, fill $FF), then STOP.
;; -----------------------------------------------------------------------------
FactoryFlashCycles2:
  mov   #$5F, sp
  callr FlashInit
  mov   #$C4, $78
  mov   #$50, $79
.cycle:
  mov   #$00, b
  callr FactoryFill
  mov   #$FF, b
  callr FactoryFill
  dbnz  $79, .cycle
  dbnz  $78, .cycle
.stop:
  set1  pcon, $01
  br    .stop
;; -----------------------------------------------------------------------------
;; FactoryFlashCycles3 ($E319)
;; Factory test: $01FC x (fill $00, fill $FF), then STOP.
;; -----------------------------------------------------------------------------
FactoryFlashCycles3:
  mov   #$5F, sp
  callr FlashInit
  mov   #$01, $78
  mov   #$FC, $79
.cycle:
  mov   #$00, b
  callr FactoryFill
  mov   #$FF, b
  callr FactoryFill
  dbnz  $79, .cycle
  dbnz  $78, .cycle
.stop:
  set1  pcon, $01
  br    .stop

;; -----------------------------------------------------------------------------
;; FlashInit ($E33B)
;; Flash controller set-up done once by HardwareInit. Writes undocumented SFRs
;; ($155, $148, $151) and EXT bits 3/1.
;; -----------------------------------------------------------------------------
FlashInit:
  set1  ext, $03
  clr1  ext, $01
  mov   #$FF, sfr_0155
  mov   #$00, sfr_0148
  set1  sfr_0151, $05
  ret
;; -----------------------------------------------------------------------------
;; FlashProgramPage ($E348)
;; Program the 128-byte bank 1 buffer into flash at FmBank:FmAddrHi:FmAddrLo (wrapping
;; within the page) and wait for completion: DQ7 data polling if FlashWaitMode.0 is
;; set, DQ6 toggle polling otherwise. The unlock sequence must already have been
;; issued (FlashWritePage does both).
;; -----------------------------------------------------------------------------
FlashProgramPage:
  mov   #$80, $00
  ld    FmBank
  and   #$01
  st    fpr
  ld    FmAddrHi
  st    trh
  ld    FmAddrLo
  st    trl
.loop:
  ld    @R0
  stf
  st    b
  inc   $00
  ld    $00
  bz    .wait
  inc   trl
  ld    trl
  and   #$7F
  bnz   .loop
  not1  trl, $07
  br    .loop
.wait:
  bn    FlashWaitMode, $00, .toggle
.dataPoll:
  ldf
  xor   b
  bp    acc, $07, .dataPoll
  br    .return
.toggle:
  ldf
  st    c
  not1  c, $06
.toggleLoop:
  not1  c, $06
  ldf
  xor   c
  bp    acc, $06, .toggleLoop
.return:
  ret
;; -----------------------------------------------------------------------------
;; FlashVerifyPage ($E388)
;; FM_VRF_EX ($0110). Compare flash at FmBank:FmAddrHi:FmAddrLo with the bank 1 buffer.
;; Out: ACC = 0 if all 128 bytes match (R0 = $00), otherwise the XOR of the first
;; difference.
;; -----------------------------------------------------------------------------
FlashVerifyPage:
  mov   #$80, $00
  ld    FmBank
  st    fpr
  ld    FmAddrHi
  st    trh
  ld    FmAddrLo
  st    trl
.loop:
  ldf
  xor   @R0
  bnz   .return
  inc   trl
  ld    trl
  and   #$7F
  bnz   .next
  not1  trl, $07
.next:
  inc   $00
  ld    $00
  bnz   .loop
.return:
  ret

;; -----------------------------------------------------------------------------
;; FlashReadByteBank0 ($E3AC)
;; Unreferenced: read the byte at bank 0 FmAddrHi:FmAddrLo into bank 1 $80.
;; -----------------------------------------------------------------------------
FlashReadByteBank0:
  mov   #$80, $00
  mov   #$00, fpr
  ld    FmAddrHi
  st    trh
  ld    FmAddrLo
  st    trl
  ldf
  st    @R0
  ret
;; -----------------------------------------------------------------------------
;; FlashReadByteBank1 ($E3BD)
;; Unreferenced: same for flash bank 1.
;; -----------------------------------------------------------------------------
FlashReadByteBank1:
  mov   #$80, $00
  mov   #$01, fpr
  ld    FmAddrHi
  st    trh
  ld    FmAddrLo
  st    trl
  ldf
  st    @R0
  ret

; ====== PERFORM FLASH UNLOCKERY SAFETY DANCE ======
;; -----------------------------------------------------------------------------
;; FlashWritePage ($E3CE)
;; FM_WRT. Issue the AMD-style unlock sequence ($AA -> $5555, $55 -> $2AAA,
;; $A0 -> $5555) with FPR.1 (write enable) set, then FlashProgramPage.
;; No range checking at all: this is what FmWrtExGuard protects.
;; -----------------------------------------------------------------------------
FlashWritePage:
  set1  fpr, $01    ; unlock flash for write 
  call  FlashUnlock  ; write unlock state machine to flash
  clr1  fpr, $01    ; lock flash for write 
  call  FlashProgramPage  ; perform actual flash write 
  ret
FlashUnlock:         ; unlock SM state 0
  mov   #$55, trh   
  mov   #$55, trl   ; write 0xaa to 0x5555
  mov   #$AA, acc
  stf               ; unlock SM state 1
  mov   #$2A, trh
  mov   #$AA, trl
  mov   #$55, acc   ; write 0x55 to 0x2aaa
  stf               ; unlock SM state 2
  mov   #$55, trh
  mov   #$55, trl
  mov   #$A0, acc   ; write 0xa0 to 0x5555
  stf               ; should be unlocked now!
  ret
;; -----------------------------------------------------------------------------
;; FlashReadPage ($E3F6)
;; FM_PRD_EX ($0120). Copy 128 bytes of flash at FmBank:FmAddrHi:FmAddrLo into the
;; bank 1 buffer at $80-$FF (TRL wraps, so the read stays inside one 256-byte page).
;; -----------------------------------------------------------------------------
FlashReadPage:
  mov   #$80, $00
  ld    FmBank
  st    fpr
  ld    FmAddrHi
  st    trh
  ld    FmAddrLo
  st    trl
.loop:
  ldf
  st    @R0
  inc   $00
  ld    $00
  inc   trl
  bz    .return
  br    .loop
.return:
  ret
;; -----------------------------------------------------------------------------
;; ClockTick ($E412)
;; Called every half second by BaseTimerIsr. Every second tick advances the binary
;; date/time (Second..YearHi) with correct month lengths; on New Year it recomputes
;; LeapYear. The BCD copy at $10-$16 is NOT updated here.
;; -----------------------------------------------------------------------------
ClockTick:
  push  acc
  push  b
  push  c
  push  $00
  ld    HalfSecond
  bnz   .second
  jmp   .halfSecond
.second:
  mov   #$00, HalfSecond
  inc   Second
  ld    Second
  be    #$3C, .minute
  jmp   .return
.minute:
  mov   #$00, Second
  inc   Minute
  ld    Minute
  be    #$3C, .hour
  jmp   .return
.hour:
  mov   #$00, Minute
  inc   Hour
  ld    Hour
  be    #$18, .day
  jmp   .return
.day:
  mov   #$00, Hour
  inc   Day
  ld    Month
  be    #$0B, .month30
  be    #$09, .month30
  be    #$06, .month30
  be    #$04, .month30
  be    #$02, .february
  ld    Day
  be    #$20, .nextMonth
  jmp   .return
.month30:
  ld    Day
  be    #$1F, .nextMonth
  jmp   .return
.february:
  ld    LeapYear
  bnz   .februaryLeap
  ld    Day
  be    #$1D, .nextMonth
  jmp   .return
.februaryLeap:
  ld    Day
  be    #$1E, .nextMonth
  jmp   .return
.nextMonth:
  mov   #$01, Day
  inc   Month
  ld    Month
  be    #$0D, .nextYear
  jmp   .return
.nextYear:
  mov   #$01, Month
  inc   YearLo
  ld    YearLo
  bnz   .leap
  inc   YearHi
.leap:
  call  UpdateLeapYear
  jmp   .return
.halfSecond:
  set1  HalfSecond, $00
.return:
  pop   $00
  pop   c
  pop   b
  pop   acc
  ret
;; -----------------------------------------------------------------------------
;; UpdateLeapYear ($E4A0)
;; YearDiv4Hi:YearDiv4Lo = year / 4 and LeapYear = Gregorian leap year
;; (divisible by 4, and not by 100 unless by 400).
;; -----------------------------------------------------------------------------
UpdateLeapYear:
  push  $00
  push  b
  push  c
  clr1  psw, cy
  ld    YearLo
  st    c
  mov   #$04, b
  ld    YearHi
  div
  st    YearDiv4Hi
  ld    c
  st    YearDiv4Lo
  ld    b
  bnz   .notLeap
  set1  LeapYear, $00
  ld    YearLo
  st    c
  mov   #$64, b
  ld    YearHi
  div
  ld    b
  bnz   .return
  ld    YearDiv4Lo
  st    c
  ld    YearDiv4Hi
  mov   #$64, b
  div
  ld    b
  bnz   .notLeap
  set1  LeapYear, $00
  jmp   .return
.notLeap:
  mov   #$00, LeapYear
.return:
  pop   c
  pop   b
  pop   $00
  ret

  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
;; -----------------------------------------------------------------------------
;; FontAscii6x8 ($E800)
;; 6x8 font for DrawChar6x8: 8 planes of 256 bytes, plane n holds pixel row n of every
;; character (bits 7-2 used). Besides ASCII it has the bold SEGA logo ($17-$1A, also
;; used as the A/B button icons $1A/$1B), arrows ($82), the "No." sign ($85), a
;; bullet ($EF) and the connector spinner frames ($F0-$F7).
;; -----------------------------------------------------------------------------
FontAscii6x8:
  .byte $00, $00, $00, $00, $00, $00, $00, $00
  .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $20, $00, $00, $70, $D8, $88, $78
  .byte $78, $78, $20, $F0, $98, $D8, $D8, $70, $00, $20, $50, $50, $20, $C0, $60, $60
  .byte $10, $40, $00, $00, $00, $00, $00, $00, $70, $20, $70, $F8, $10, $F8, $30, $F8
  .byte $70, $70, $00, $00, $10, $00, $40, $70, $70, $70, $F0, $70, $E0, $F8, $F8, $70
  .byte $88, $70, $38, $88, $80, $88, $88, $70, $F0, $70, $F0, $78, $F8, $88, $88, $88
  .byte $88, $88, $F8, $70, $88, $70, $20, $00, $40, $00, $80, $00, $08, $00, $30, $00
  .byte $80, $20, $10, $80, $60, $00, $00, $00, $00, $00, $00, $00, $40, $00, $00, $00
  .byte $00, $00, $00, $10, $20, $40, $00, $00, $20, $20, $80, $08, $00, $90, $20, $00
  .byte $00, $00, $20, $00, $00, $E0, $38, $10, $40, $F8, $00, $20, $D8, $00, $30, $00
  .byte $00, $50, $20, $20, $70, $F8, $00, $70, $20, $00, $38, $00, $00, $00, $00, $00
  .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $F8, $08, $20, $00, $10, $40, $20
  .byte $00, $40, $00, $50, $00, $00, $40, $00, $00, $10, $00, $70, $40, $20, $00, $00
  .byte $20, $10, $00, $80, $00, $00, $20, $00, $00, $00, $00, $00, $40, $00, $00, $70
  .byte $90, $00, $00, $00, $00, $00, $20, $E0, $00, $00, $00, $20, $88, $00, $00, $50
  .byte $00, $00, $00, $00, $00, $00, $10, $00, $F8, $88, $88, $F8, $F8, $A8, $00, $00
  .byte $A8, $50, $00, $00, $00, $A8, $50, $F8, $00, $00, $00, $00, $00, $00, $00, $00
  .byte $00, $00, $00, $00, $00, $00, $00, $00, $50, $A8, $00, $00, $D8, $D8, $D8, $F8
  .byte $F8, $F8, $70, $D8, $D8, $D8, $D8, $F8, $00, $20, $50, $50, $78, $C8, $90, $20
  .byte $20, $20, $20, $20, $00, $00, $00, $08, $88, $60, $88, $10, $30, $80, $40, $08
  .byte $88, $88, $60, $60, $20, $00, $20, $88, $88, $88, $88, $88, $90, $80, $80, $88
  .byte $88, $20, $10, $90, $80, $D8, $88, $88, $88, $88, $88, $80, $20, $88, $88, $88
  .byte $88, $88, $08, $40, $50, $10, $50, $00, $20, $00, $80, $00, $08, $00, $48, $78
  .byte $80, $00, $00, $80, $20, $00, $00, $00, $00, $00, $00, $00, $40, $00, $00, $00
  .byte $00, $00, $00, $20, $20, $20, $20, $20, $70, $20, $C0, $18, $28, $D0, $70, $00
  .byte $20, $20, $70, $20, $20, $C0, $18, $20, $20, $88, $38, $30, $48, $00, $20, $70
  .byte $70, $F8, $70, $70, $70, $88, $88, $88, $70, $00, $20, $00, $00, $00, $F8, $00
  .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $08, $10, $F8, $F8, $F8, $F8, $F8
  .byte $78, $78, $F8, $F8, $C0, $F8, $F8, $88, $78, $E0, $A8, $00, $40, $20, $70, $F8
  .byte $F8, $10, $20, $80, $F8, $40, $F8, $F8, $70, $20, $08, $F8, $40, $70, $F8, $00
  .byte $90, $20, $80, $F8, $F8, $C0, $90, $A0, $00, $80, $20, $50, $50, $88, $20, $50
  .byte $00, $00, $F8, $00, $00, $00, $20, $70, $70, $F8, $88, $88, $F8, $50, $A8, $00
  .byte $00, $A8, $70, $A8, $50, $50, $A8, $F8, $00, $00, $00, $00, $00, $00, $00, $00
  .byte $00, $00, $00, $00, $00, $00, $00, $00, $A8, $A8, $70, $00, $D8, $D8, $F8, $C0
  .byte $C0, $C0, $F8, $D8, $F8, $F0, $D8, $D8, $00, $20, $50, $F8, $A0, $10, $A0, $40
  .byte $40, $10, $A8, $20, $00, $00, $00, $10, $98, $20, $08, $20, $50, $F0, $80, $10
  .byte $88, $88, $60, $60, $40, $F8, $10, $08, $08, $88, $88, $80, $88, $80, $80, $80
  .byte $88, $20, $10, $A0, $80, $A8, $C8, $88, $88, $88, $88, $80, $20, $88, $88, $88
  .byte $50, $88, $10, $40, $F8, $10, $88, $00, $10, $70, $B0, $70, $68, $70, $40, $88
  .byte $B0, $60, $30, $90, $20, $D0, $B0, $70, $F0, $68, $B0, $70, $E0, $88, $88, $88
  .byte $88, $88, $F8, $20, $20, $20, $10, $40, $A8, $20, $E0, $38, $48, $B0, $F8, $00
  .byte $60, $30, $F8, $70, $50, $80, $08, $20, $20, $B8, $28, $28, $90, $00, $30, $F8
  .byte $88, $F8, $F8, $F8, $F8, $88, $50, $70, $A8, $00, $20, $00, $00, $00, $08, $F8
  .byte $10, $20, $00, $10, $40, $00, $F0, $00, $00, $28, $20, $88, $20, $10, $48, $20
  .byte $48, $90, $08, $50, $08, $08, $48, $88, $48, $20, $A8, $F8, $40, $F8, $00, $08
  .byte $10, $10, $10, $F8, $08, $A0, $20, $08, $00, $40, $08, $40, $F8, $10, $08, $F8
  .byte $90, $A0, $80, $88, $88, $00, $40, $E0, $40, $40, $50, $88, $20, $50, $70, $50
  .byte $00, $70, $88, $20, $F8, $50, $40, $F8, $00, $70, $F8, $88, $88, $A8, $50, $A8
  .byte $00, $00, $88, $50, $A8, $A8, $50, $F8, $00, $00, $00, $00, $00, $00, $00, $00
  .byte $00, $00, $00, $00, $00, $00, $00, $00, $88, $70, $70, $00, $D8, $D8, $F8, $70
  .byte $F0, $F8, $D8, $F0, $F8, $E0, $F8, $D8, $00, $20, $00, $50, $70, $20, $40, $00
  .byte $40, $10, $70, $F8, $00, $F8, $00, $20, $A8, $20, $10, $10, $90, $08, $F0, $20
  .byte $70, $78, $00, $00, $80, $00, $08, $10, $68, $88, $F0, $80, $88, $F0, $F0, $B8
  .byte $F8, $20, $10, $C0, $80, $A8, $A8, $88, $F0, $88, $F0, $70, $20, $88, $88, $A8
  .byte $20, $50, $20, $40, $20, $10, $00, $00, $00, $08, $C8, $80, $98, $88, $E0, $88
  .byte $C8, $20, $10, $A0, $20, $A8, $C8, $88, $88, $98, $C8, $80, $40, $88, $88, $88
  .byte $50, $88, $10, $40, $20, $10, $F8, $F8, $20, $20, $F0, $78, $F8, $90, $00, $00
  .byte $E0, $38, $00, $F8, $88, $80, $08, $20, $20, $A0, $28, $20, $00, $A8, $20, $F8
  .byte $88, $F8, $F8, $F8, $F8, $88, $20, $20, $20, $00, $20, $20, $00, $60, $F8, $08
  .byte $20, $F8, $70, $F8, $F8, $70, $10, $A8, $F8, $30, $60, $88, $20, $30, $48, $F8
  .byte $88, $10, $08, $50, $C8, $10, $50, $48, $A8, $F8, $A8, $20, $60, $20, $00, $50
  .byte $20, $10, $88, $80, $08, $10, $20, $08, $70, $80, $50, $F8, $48, $10, $F8, $08
  .byte $90, $A0, $88, $88, $88, $08, $00, $00, $A8, $20, $88, $20, $88, $20, $70, $20
  .byte $20, $50, $88, $50, $00, $20, $00, $E8, $00, $00, $70, $F8, $88, $00, $A8, $50
  .byte $A8, $00, $A8, $A8, $50, $50, $A8, $F8, $00, $00, $00, $00, $00, $00, $00, $00
  .byte $00, $00, $00, $00, $00, $00, $00, $00, $88, $A8, $70, $70, $F8, $F8, $F8, $18
  .byte $C0, $D8, $D8, $D8, $F8, $F0, $D8, $D8, $00, $00, $00, $F8, $28, $40, $A8, $00
  .byte $40, $10, $A8, $20, $60, $00, $00, $40, $C8, $20, $20, $08, $F8, $08, $88, $40
  .byte $88, $08, $60, $60, $40, $F8, $10, $20, $A8, $F8, $88, $80, $88, $80, $80, $88
  .byte $88, $20, $10, $A0, $80, $88, $98, $88, $80, $A8, $A0, $08, $20, $88, $88, $A8
  .byte $50, $20, $40, $40, $F8, $10, $00, $00, $00, $78, $88, $80, $88, $F8, $40, $78
  .byte $88, $20, $10, $C0, $20, $A8, $88, $88, $F0, $78, $80, $70, $40, $88, $88, $A8
  .byte $20, $78, $20, $20, $20, $20, $10, $40, $20, $A8, $E0, $38, $40, $38, $00, $F8
  .byte $60, $30, $F8, $70, $50, $80, $08, $20, $20, $A0, $E8, $20, $00, $00, $70, $F8
  .byte $88, $70, $20, $70, $20, $88, $50, $F8, $70, $E0, $00, $20, $80, $60, $08, $30
  .byte $60, $88, $20, $30, $48, $10, $F0, $A8, $00, $20, $A0, $08, $20, $50, $48, $20
  .byte $08, $10, $08, $10, $08, $20, $40, $08, $18, $20, $08, $20, $50, $20, $00, $20
  .byte $70, $10, $88, $80, $08, $08, $A8, $50, $00, $88, $20, $40, $50, $10, $08, $08
  .byte $10, $A8, $90, $88, $08, $08, $00, $00, $10, $10, $20, $50, $50, $88, $70, $20
  .byte $00, $70, $88, $20, $F8, $50, $00, $D8, $00, $00, $00, $70, $F8, $00, $00, $A8
  .byte $50, $A8, $88, $50, $A8, $A8, $50, $F8, $00, $00, $00, $00, $00, $00, $00, $00
  .byte $00, $00, $00, $00, $00, $00, $00, $00, $50, $70, $F8, $F8, $D8, $70, $D8, $F8
  .byte $F8, $F8, $F8, $D8, $D8, $D8, $D8, $F8, $00, $00, $00, $50, $F0, $98, $90, $00
  .byte $20, $20, $20, $20, $20, $00, $60, $80, $88, $20, $40, $88, $10, $88, $88, $40
  .byte $88, $10, $60, $20, $20, $00, $20, $00, $A8, $88, $88, $88, $90, $80, $80, $88
  .byte $88, $20, $90, $90, $80, $88, $88, $88, $80, $90, $90, $08, $20, $88, $50, $A8
  .byte $88, $20, $80, $40, $20, $10, $00, $00, $00, $88, $88, $88, $88, $80, $40, $08
  .byte $88, $20, $90, $A0, $20, $88, $88, $88, $80, $08, $80, $08, $48, $98, $50, $A8
  .byte $50, $08, $40, $20, $20, $20, $20, $20, $20, $70, $C0, $18, $20, $28, $00, $70
  .byte $20, $20, $70, $20, $20, $C0, $18, $20, $20, $E0, $88, $E0, $00, $00, $50, $70
  .byte $70, $20, $70, $20, $70, $88, $88, $20, $88, $A0, $00, $20, $40, $00, $10, $20
  .byte $A0, $08, $20, $50, $50, $10, $10, $08, $00, $20, $20, $10, $20, $90, $48, $20
  .byte $10, $10, $08, $20, $10, $50, $40, $10, $10, $20, $10, $20, $40, $40, $00, $50
  .byte $A8, $20, $88, $80, $10, $08, $A8, $20, $70, $F8, $50, $40, $40, $10, $08, $10
  .byte $20, $A8, $A0, $88, $10, $10, $00, $00, $00, $08, $50, $88, $20, $50, $70, $20
  .byte $00, $00, $F8, $00, $20, $00, $00, $70, $70, $70, $70, $70, $70, $A8, $00, $00
  .byte $A8, $50, $70, $A8, $50, $50, $A8, $F8, $20, $20, $20, $20, $20, $20, $20, $20
  .byte $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $00, $00, $70, $20, $D8, $F0
  .byte $78, $78, $D8, $F8, $D8, $D8, $D8, $70, $00, $20, $00, $50, $20, $18, $68, $00
  .byte $10, $40, $00, $00, $40, $00, $60, $00, $70, $70, $F8, $70, $10, $70, $70, $40
  .byte $70, $60, $00, $40, $10, $00, $40, $20, $70, $88, $F0, $70, $E0, $F8, $80, $78
  .byte $88, $70, $60, $88, $F8, $88, $88, $70, $80, $68, $88, $F0, $20, $70, $20, $50
  .byte $88, $20, $F8, $70, $20, $70, $00, $F8, $00, $78, $F0, $70, $78, $70, $40, $70
  .byte $88, $70, $60, $90, $70, $88, $88, $70, $80, $08, $80, $F0, $30, $68, $20, $50
  .byte $88, $70, $F8, $10, $20, $40, $00, $00, $20, $20, $80, $08, $00, $38, $00, $20
  .byte $00, $00, $20, $00, $00, $E0, $38, $10, $40, $00, $F8, $E0, $00, $00, $70, $00
  .byte $00, $00, $00, $00, $00, $F8, $00, $20, $70, $E0, $00, $E0, $20, $00, $20, $40
  .byte $20, $30, $70, $90, $40, $F8, $F0, $30, $00, $40, $20, $20, $F8, $10, $90, $20
  .byte $60, $20, $F8, $40, $E0, $88, $38, $60, $60, $40, $20, $40, $40, $80, $F8, $80
  .byte $20, $40, $88, $78, $60, $00, $20, $10, $08, $08, $80, $38, $40, $F8, $F8, $20
  .byte $40, $B0, $C0, $F8, $20, $E0, $00, $00, $00, $00, $88, $00, $00, $20, $00, $20
  .byte $00, $00, $00, $00, $20, $00, $00, $00, $F8, $F8, $F8, $F8, $F8, $50, $A8, $00
  .byte $00, $A8, $00, $00, $00, $A8, $50, $F8, $00, $00, $00, $00, $00, $00, $00, $00

  .org $EFF8
  .byte $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
  .byte $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF

  ;; Pad size of binary
  .cnop $00, $0200

 ;; ===========================================================================
 ;; RAM definitions
 ;; ===========================================================================
 ;; Bank 0: BIOS system variables
BcdYearHi        = $10   ; BCD date/time copy (Maple/clock set, file timestamps)
BcdYearLo        = $11
BcdMonth         = $12
BcdDay           = $13
BcdHour          = $14
BcdMinute        = $15
BcdSecond        = $16
YearHi           = $17   ; binary date/time, advanced by ClockTick
YearLo           = $18
Month            = $19   ; 1-12
Day              = $1A   ; 1-31
Hour             = $1B   ; 0-23
Minute           = $1C   ; 0-59
Second           = $1D   ; 0-59
HalfSecond       = $1E   ; toggles every base timer tick; a second passes on 1 -> 0
LeapYear         = $1F   ; 1 if the current year is a leap year (UpdateLeapYear)
MapleMyAddr      = $20   ; our Maple address incl. port bits (latched from a device request)
MapleHostAddr    = $21   ; sender of the frame being answered
MapleAddrState   = $22   ; 0 = no address yet, $FF = addressed, $55 = killed
MapleIdPins      = $23   ; P7.2-3 when the address was derived
MapleLastCmd     = $24   ; last command handled / error reply sent, replayed on a resend request
MapleExpectedPhase = $25 ; storage block write: next expected phase (0-3)
MapleWriteBlock  = $26   ; storage block write: block number given in phase 0
MapleStorageErr  = $27   ; storage error bits (see MapleBlockToFlashAddr/MapleStorageBlockWrite)
MapleLcdErr      = $28   ; LCD block write error bits
MapleFuncType    = $29   ; function of the current frame: 2 storage, 4 LCD, 8 clock, $FF other
CopyRxArm        = $2B   ; VMU-to-VMU receive: 0 off, 1 armed, $FF suppressed
WarmBootMagic    = $2C   ; $2C-$2F = "REST" once RAM has been initialised
BiosMode         = $30   ; 0 file manager, 1 game, 2 clock
DateSet          = $31   ; $FF once the user (or the Dreamcast) has set the clock
ClockAnim        = $32   ; clock animation: bits 7-6 animal, 5 frame, 4 resting, 3-0 step
IdleTicks        = $33   ; reset to 1 by any button, +1 per half second; 0 = auto-sleep
HalfSecTicks     = $34   ; +1 per half second; cleared by code that wants a timeout
SleepCtl         = $35   ; bit0 SLEEP pressed, $40 = ignore sleep, $80 = caller handles it
FreeUserBlocksHi = $36   ; free blocks 0-199
FreeUserBlocks   = $37
FreeGameBlocksHi = $38   ; free blocks at the start of the volume (room for a game)
FreeGameBlocks   = $39
FileCountHi      = $3A   ; number of files (CountFiles)
FileCount        = $3B
SelectedFileHi   = $3C   ; file shown in the file manager (1-based)
SelectedFile     = $3D
FreeExtraBlocksHi = $3E  ; free blocks 200-230
FreeExtraBlocks  = $3F
YearDiv4Hi       = $50   ; year / 4 (UpdateLeapYear)
YearDiv4Lo       = $51
MathHi           = $52   ; result of the BCD/binary conversions and block-number scratch
MathLo           = $53
FatBank          = $54   ; flash address of the FAT block (FPR bit, high, low)
FatAddrHi        = $55
FatAddrLo        = $56
DirBlock         = $58   ; directory block being scanned
FsError          = $5C   ; filesystem error bits (shown as "System error xx")
CursorX          = $60   ; text cursor column
CursorY          = $61   ; text cursor row
TextInvert       = $67   ; $FF = draw inverted / clear to black
GameLastBlock    = $6D   ; last block of the game file (FmWrtExGuard limit)
BatteryCheck     = $6E   ; $FF = no low-battery check, else counts low-battery ticks
FlashBankTemp    = $6F   ; copy of FPR.0 for the current flash pointer
Buttons_Current  = $70   ; buttons held, 1 = pressed (see the overview)
Buttons_Diff     = $71   ; buttons newly pressed since the last P3 interrupt
Buttons_Last     = $72   ; previous Buttons_Current (also written by BaseTimerIsr)
FastTickDisabled = $73   ; 0 while FastTickOn is active
FastTicks        = $74   ; base timer interrupt 1 count (key repeat)

 ;; Bank 1: application bank, firmware-call parameters, copy buffers
DataToTransmit   = $10   ; VMU-to-VMU: outgoing packet
CopyBlocksLeft   = $24   ; VMU-to-VMU send: blocks still to send
NBytesToVerify   = $25
NBytesToSend     = $26
DataTransmitted  = $28   ; VMU-to-VMU: bytes as actually shifted out / received packet
NBlocksToWrite   = $3D   ; VMU-to-VMU receive: blocks in the incoming file
NBytesToReceive  = $3E
RxPayloadSize    = $3F
FlashWaitMode    = $7C   ; bit0: FlashProgramPage waits with DQ7 polling instead of DQ6 toggle
FmBank           = $7D   ; firmware calls: flash address bit 16
FmAddrHi         = $7E   ; firmware calls: flash address bits 15-8
FmAddrLo         = $7F   ; firmware calls: flash address bits 7-0; data buffer at $80-$FF

  ;; PSW bits
p EQU $00
rambk0 EQU $01
ov EQU $02
irbk0 EQU $03
irbk1 EQU $04
ac EQU $06
cy EQU $07

  ;; Special Function Registers
acc EQU $0100
psw EQU $0101
b EQU $0102
c EQU $0103
trl EQU $0104
trh EQU $0105
sp EQU $0106
pcon EQU $0107
ie EQU $0108
ip EQU $0109
sfr_010a EQU $010A
sfr_010b EQU $010B
sfr_010c EQU $010C
ext EQU $010D
ocr EQU $010E
sfr_010f EQU $010F
t0con EQU $0110
t0prr EQU $0111
t0l EQU $0112
t0lr EQU $0113
t0h EQU $0114
t0hr EQU $0115
sfr_0116 EQU $0116
sfr_0117 EQU $0117
t1cnt EQU $0118
sfr_0119 EQU $0119
t1lc EQU $011A
t1lr EQU $011B
t1hc EQU $011C
t1hr EQU $011D
sfr_011e EQU $011E
sfr_011f EQU $011F
mcr EQU $0120
sfr_0121 EQU $0121
stad EQU $0122
cnr EQU $0123
tdr EQU $0124
xbnk EQU $0125
sfr_0126 EQU $0126
vccr EQU $0127
sfr_0128 EQU $0128
sfr_0129 EQU $0129
sfr_012a EQU $012A
sfr_012b EQU $012B
sfr_012c EQU $012C
sfr_012d EQU $012D
sfr_012e EQU $012E
sfr_012f EQU $012F
scon0 EQU $0130
sbuf0 EQU $0131
sbr EQU $0132
sfr_0133 EQU $0133
scon1 EQU $0134
sbuf1 EQU $0135
sfr_0136 EQU $0136
sfr_0137 EQU $0137
sfr_0138 EQU $0138
sfr_0139 EQU $0139
sfr_013a EQU $013A
sfr_013b EQU $013B
sfr_013c EQU $013C
sfr_013d EQU $013D
sfr_013e EQU $013E
sfr_013f EQU $013F
sfr_0140 EQU $0140
sfr_0141 EQU $0141
sfr_0142 EQU $0142
sfr_0143 EQU $0143
p1 EQU $0144
p1ddr EQU $0145
p1fcr EQU $0146
sfr_0147 EQU $0147
sfr_0148 EQU $0148
sfr_0149 EQU $0149
sfr_014a EQU $014A
sfr_014b EQU $014B
p3 EQU $014C
p3ddr EQU $014D
p3int EQU $014E
sfr_014f EQU $014F
sfr_0150 EQU $0150
sfr_0151 EQU $0151
sfr_0152 EQU $0152
sfr_0153 EQU $0153
fpr EQU $0154
sfr_0155 EQU $0155
sfr_0156 EQU $0156
sfr_0157 EQU $0157
sfr_0158 EQU $0158
sfr_0159 EQU $0159
sfr_015a EQU $015A
sfr_015b EQU $015B
p7 EQU $015C
i01cr EQU $015D
i23cr EQU $015E
isl EQU $015F
mapletxrxctl EQU $0160
maplesta EQU $0161
maplerst EQU $0162
vsel EQU $0163
vrmad1 EQU $0164
vrmad2 EQU $0165
vtrbf EQU $0166
vlreg EQU $0167
sfr_0168 EQU $0168
sfr_0169 EQU $0169
sfr_016a EQU $016A
sfr_016b EQU $016B
sfr_016c EQU $016C
sfr_016d EQU $016D
sfr_016e EQU $016E
sfr_016f EQU $016F
sfr_0170 EQU $0170
sfr_0171 EQU $0171
sfr_0172 EQU $0172
sfr_0173 EQU $0173
sfr_0174 EQU $0174
sfr_0175 EQU $0175
sfr_0176 EQU $0176
sfr_0177 EQU $0177
sfr_0178 EQU $0178
sfr_0179 EQU $0179
sfr_017a EQU $017A
sfr_017b EQU $017B
sfr_017c EQU $017C
sfr_017d EQU $017D
sfr_017e EQU $017E
btcr EQU $017F
xram EQU $0180
xram_0181 EQU $0181
xram_0182 EQU $0182
xram_0183 EQU $0183
xram_0184 EQU $0184
xram_0185 EQU $0185
xram_0186 EQU $0186
xram_0187 EQU $0187
xram_0188 EQU $0188
xram_0189 EQU $0189
xram_018a EQU $018A
xram_018b EQU $018B
xram_018c EQU $018C
xram_018d EQU $018D
xram_018e EQU $018E
xram_018f EQU $018F
xram_0190 EQU $0190
xram_0191 EQU $0191
xram_0192 EQU $0192
xram_0193 EQU $0193
xram_0194 EQU $0194
xram_0195 EQU $0195
xram_0196 EQU $0196
xram_0197 EQU $0197
xram_0198 EQU $0198
xram_0199 EQU $0199
xram_019a EQU $019A
xram_019b EQU $019B
xram_019c EQU $019C
xram_019d EQU $019D
xram_019e EQU $019E
xram_019f EQU $019F
xram_01a0 EQU $01A0
xram_01a1 EQU $01A1
xram_01a2 EQU $01A2
xram_01a3 EQU $01A3
xram_01a4 EQU $01A4
xram_01a5 EQU $01A5
xram_01a6 EQU $01A6
xram_01a7 EQU $01A7
xram_01a8 EQU $01A8
xram_01a9 EQU $01A9
xram_01aa EQU $01AA
xram_01ab EQU $01AB
xram_01ac EQU $01AC
xram_01ad EQU $01AD
xram_01ae EQU $01AE
xram_01af EQU $01AF
xram_01b0 EQU $01B0
xram_01b1 EQU $01B1
xram_01b2 EQU $01B2
xram_01b3 EQU $01B3
xram_01b4 EQU $01B4
xram_01b5 EQU $01B5
xram_01b6 EQU $01B6
xram_01b7 EQU $01B7
xram_01b8 EQU $01B8
xram_01b9 EQU $01B9
xram_01ba EQU $01BA
xram_01bb EQU $01BB
xram_01bc EQU $01BC
xram_01bd EQU $01BD
xram_01be EQU $01BE
xram_01bf EQU $01BF
xram_01c0 EQU $01C0
xram_01c1 EQU $01C1
xram_01c2 EQU $01C2
xram_01c3 EQU $01C3
xram_01c4 EQU $01C4
xram_01c5 EQU $01C5
xram_01c6 EQU $01C6
xram_01c7 EQU $01C7
xram_01c8 EQU $01C8
xram_01c9 EQU $01C9
xram_01ca EQU $01CA
xram_01cb EQU $01CB
xram_01cc EQU $01CC
xram_01cd EQU $01CD
xram_01ce EQU $01CE
xram_01cf EQU $01CF
xram_01d0 EQU $01D0
xram_01d1 EQU $01D1
xram_01d2 EQU $01D2
xram_01d3 EQU $01D3
xram_01d4 EQU $01D4
xram_01d5 EQU $01D5
xram_01d6 EQU $01D6
xram_01d7 EQU $01D7
xram_01d8 EQU $01D8
xram_01d9 EQU $01D9
xram_01da EQU $01DA
xram_01db EQU $01DB
xram_01dc EQU $01DC
xram_01dd EQU $01DD
xram_01de EQU $01DE
xram_01df EQU $01DF
xram_01e0 EQU $01E0
xram_01e1 EQU $01E1
xram_01e2 EQU $01E2
xram_01e3 EQU $01E3
xram_01e4 EQU $01E4
xram_01e5 EQU $01E5
xram_01e6 EQU $01E6
xram_01e7 EQU $01E7
xram_01e8 EQU $01E8
xram_01e9 EQU $01E9
xram_01ea EQU $01EA
xram_01eb EQU $01EB
xram_01ec EQU $01EC
xram_01ed EQU $01ED
xram_01ee EQU $01EE
xram_01ef EQU $01EF
xram_01f0 EQU $01F0
xram_01f1 EQU $01F1
xram_01f2 EQU $01F2
xram_01f3 EQU $01F3
xram_01f4 EQU $01F4
xram_01f5 EQU $01F5
xram_01f6 EQU $01F6
xram_01f7 EQU $01F7
xram_01f8 EQU $01F8
xram_01f9 EQU $01F9
xram_01fa EQU $01FA
xram_01fb EQU $01FB
sfr_01fc EQU $01FC
sfr_01fd EQU $01FD
sfr_01fe EQU $01FE
sfr_01ff EQU $01FF
