; Version: louder/higher Mario-style music for buzzer
; Version: Mario melody one octave higher for buzzer
; ============================================================
; dino_game.asm
; ATmega128L-4MHz-STK300
; Dino LCD game + RC5 menu + Sharp analog distance sensor
; Uses course files: macros.asm, definitions.asm, lcd.asm
;
; Required files in same Atmel Studio folder:
;   macros.asm
;   definitions.asm
;   lcd.asm
;
; Modules:
;   LCD on STK300 LCD connector
;   IR Receiver module on PORTE
;   Sharp GP2Y0A21 complete module on M4/PORTF analog connector
;     AVAL/OUT is read on PF3 = ADC3 = GP2_AVAL from definitions.asm
;   LEDs on PORTB
;   Buzzer on PORTE bit SPEAKER
; ============================================================

.include "macros.asm"
.include "definitions.asm"
.include "lcd.asm"

.equ T1 = 1870

.equ STATE_MENU = 0
.equ STATE_PLAY = 1
.equ STATE_DIFF = 2
.equ STATE_BEST = 3

.equ EASY   = 1
.equ NORMAL = 2
.equ HARD   = 3

.equ OBST_START = 15
.equ DINO_COL = 0           ; Dino fixed on left column
.equ JUMP_TICKS = 10
.equ ADC_THRESHOLD = 115       ; tune this value if jump is too sensitive/not sensitive

.dseg
state_s:       .byte 1
diff_s:        .byte 1
lives_s:       .byte 1
score_s:       .byte 1     ; low byte
score_hi_s:    .byte 1     ; high byte, score no longer resets at 256
best_s:        .byte 1     ; low byte
best_hi_s:     .byte 1     ; high byte saved in EEPROM
obst_lo_s:     .byte 1     ; obstacle bitmask columns 0..7
obst_hi_s:     .byte 1     ; obstacle bitmask columns 8..15
gap_s:         .byte 1     ; random gap before next obstacle
rng_s:         .byte 1     ; pseudo-random state
jump_s:        .byte 1
adc_s:         .byte 1
frame_s:       .byte 1
music_s:       .byte 1

.cseg

; ------------------------------------------------------------
; RESET
; ------------------------------------------------------------
reset:
    LDSP    RAMEND

    ; LEDs output
    OUTI    DDRB,0xff
    OUTI    PORTB,0xff

    ; PORTE: speaker output, IR input with pull-up
    in      w,DDRE
    sbr     w,(1<<SPEAKER)
    out     DDRE,w
    in      w,PORTE
    sbr     w,(1<<IR)
    out     PORTE,w

    rcall   LCD_init
    rcall   adc_init

    ldi     w,STATE_MENU
    sts     state_s,w
    ldi     w,NORMAL
    sts     diff_s,w
    rcall   eeprom_read_best

    rcall   show_main_menu
    rjmp    main

; ============================================================
; MAIN MENU LOOP
; ============================================================
main:
    rcall   read_rc5_button      ; result in b0

    lds     w,state_s
    cpi     w,STATE_MENU
    breq    handle_menu

    cpi     w,STATE_DIFF
    breq    handle_diff

    cpi     w,STATE_BEST
    breq    handle_best

    rjmp    main

; ------------------------------------------------------------
; RC5 BUTTON READER, same logic as course ir_rc5.asm
; result: b0 = command
; Dans le livre section 13.6.1
; ------------------------------------------------------------
read_rc5_button:
    CLR2    b1,b0
    ldi     b2,14

    WP1     PINE,IR
    WAIT_US (T1/4)

read_rc5_loop:
    P2C     PINE,IR
    ROL2    b1,b0
    WAIT_US (T1-4)
    DJNZ    b2,read_rc5_loop

    com     b0
    ret

; ============================================================
; MENU HANDLERS
; ON change state_s à ce moment la du code car les valeurs lues par la télécommmande ne ont pas forcément des state
; ============================================================
handle_menu:
    cpi     b0,0x01
    brne    menu_check_2
    rjmp    start_game
menu_check_2:
    cpi     b0,0x02
    brne    menu_check_3
    rjmp    open_diff
menu_check_3:
    cpi     b0,0x03
    brne    menu_no_action
    rjmp    open_best
menu_no_action:
    rjmp    main

open_diff:
    ldi     w,STATE_DIFF
    sts     state_s,w
    rcall   show_diff_menu
    rjmp    main

open_best:
    ldi     w,STATE_BEST
    sts     state_s,w
    rcall   show_best_page
    rjmp    main

handle_best:
    cpi     b0,0x00
    brne    best_no_action
    rjmp    back_to_menu
best_no_action:
    rjmp    main

handle_diff:
    cpi     b0,0x00
    brne    diff_check_1
    rjmp    back_to_menu
diff_check_1:
    cpi     b0,0x01
    breq    choose_easy

    cpi     b0,0x02
    breq    choose_normal

    cpi     b0,0x03
    breq    choose_hard

    rjmp    main

choose_easy:
    ldi     w,EASY
    sts     diff_s,w
    rcall   show_easy_selected
    WAIT_MS 700
    rcall   show_diff_menu
    rjmp    main

choose_normal:
    ldi     w,NORMAL
    sts     diff_s,w
    rcall   show_normal_selected
    WAIT_MS 700
    rcall   show_diff_menu
    rjmp    main

choose_hard:
    ldi     w,HARD
    sts     diff_s,w
    rcall   show_hard_selected
    WAIT_MS 700
    rcall   show_diff_menu
    rjmp    main

back_to_menu:
    ldi     w,STATE_MENU
    sts     state_s,w
    rcall   show_main_menu
    rjmp    main

; ============================================================
; GAME
; ============================================================
start_game:
    rcall   init_game

game_loop:
    rcall   read_distance
    rcall   update_jump
    rcall   render_game
    rcall   game_delay
    rcall   game_tick
    rcall   music_step

    lds     w,lives_s
    tst     w
    breq    game_over

    rjmp    game_loop

game_over:
    rcall   update_best_score
    rcall   show_game_over
    ; keep final score visible for about 3 seconds
    WAIT_MS 1000
    WAIT_MS 1000
    WAIT_MS 1000
    rcall   show_main_menu
    ldi     w,STATE_MENU
    sts     state_s,w
    rjmp    main

init_game:
    clr     w
    sts     score_s,w
    sts     score_hi_s,w
    sts     jump_s,w
    sts     frame_s,w
    sts     music_s,w

    clr     w
    sts     obst_lo_s,w
    sts     obst_hi_s,w
    ldi     w,3
    sts     gap_s,w
    ldi     w,0x5A
    sts     rng_s,w

    lds     w,diff_s
    cpi     w,EASY
    breq    init_easy
    cpi     w,HARD
    breq    init_hard

init_normal:
    ldi     w,2
    rjmp    init_lives_done
init_easy:
    ldi     w,3
    rjmp    init_lives_done
init_hard:
    ldi     w,1
init_lives_done:
    sts     lives_s,w
    rcall   update_leds
    rcall   beep_start
    ret

; ------------------------------------------------------------
; ADC - Sharp GP2Y0A21 complete module
; Module placed on M4 / analog connector.
; The analog output AVAL/OUT is connected to PF3 = ADC3.
; GP2_AVAL is defined in definitions.asm as 3.
; ADCH contains the 8 MSB of the conversion.
; ------------------------------------------------------------
adc_init:
    ; PF3 / ADC3 input, no pull-up
    lds     w,DDRF
    cbr     w,(1<<GP2_AVAL)
    sts     DDRF,w
    lds     w,PORTF
    cbr     w,(1<<GP2_AVAL)
    sts     PORTF,w

    ; AVCC reference, left-adjusted result, channel ADC3
    ldi     w,(1<<REFS0)|(1<<ADLAR)|GP2_AVAL
    out     ADMUX,w
    ldi     w,(1<<ADEN)|(1<<ADPS2)|(1<<ADPS1)|(1<<ADPS0)
    out     ADCSRA,w
    ret

read_distance:
    sbi     ADCSRA,ADSC
adc_wait:
    sbic    ADCSRA,ADSC
    rjmp    adc_wait
    in      w,ADCH
    sts     adc_s,w
    ret

update_jump:
    ; if already jumping, decrement jump counter
    lds     w,jump_s
    tst     w
    breq    check_new_jump
    dec     w
    sts     jump_s,w
    ret

check_new_jump:
    lds     w,adc_s
    cpi     w,ADC_THRESHOLD
    brlo    no_new_jump
    ldi     w,JUMP_TICKS
    sts     jump_s,w
    rcall   beep_jump
no_new_jump:
    ret

move_obstacle:
    ; Move obstacles left every game tick.
    ; Obstacles are generated in GROUPS.
    ; A group can be:
    ;   - one obstacle  : #
    ;   - two glued     : ##
    ; After each group, there is ALWAYS at least 2 empty spaces.
    ; This is done by using gap_s >= 3 before the next spawn.
    lds     b0,obst_lo_s
    lds     b1,obst_hi_s

    lsr     b1
    ror     b0

    sts     obst_lo_s,b0
    sts     obst_hi_s,b1

    ; countdown before next new group
    lds     w,gap_s
    tst     w
    breq    spawn_obstacle
    dec     w
    sts     gap_s,w
    rjmp    inc_score

spawn_obstacle:
    ; Around 25% double glued obstacles, 75% single obstacles.
    ; Not all obstacles are glued.
    rcall   next_random

    lds     b0,obst_lo_s
    lds     b1,obst_hi_s

    mov     a0,w
    andi    a0,0x03
    tst     a0
    brne    spawn_single

spawn_double:
    ; two glued obstacles at columns 14 and 15
    ori     b1,0b11000000
    rjmp    spawn_store_pattern

spawn_single:
    ; one obstacle at column 15
    ori     b1,0b10000000

spawn_store_pattern:
    sts     obst_lo_s,b0
    sts     obst_hi_s,b1

    ; Random distance until next group.
    ; gap_s = 3..7 gives at least two empty spaces between groups.
    ; 3 = close, 7 = far.
    rcall   next_random
    andi    w,0x07             ; 0..7
    cpi     w,5
    brlo    gap_ok             ; 0..4 accepted
    subi    w,5                ; 5,6,7 -> 0,1,2

gap_ok:
    subi    w,-3               ; final gap 3..7
    sts     gap_s,w

inc_score:
    ; 16-bit score: score_hi_s:score_s
    lds     w,score_s
    inc     w
    sts     score_s,w
    brne    inc_score_done
    lds     w,score_hi_s
    inc     w
    sts     score_hi_s,w
inc_score_done:
    ret

next_random:
    ; Simple 8-bit pseudo-random generator.
    ; rng = rng*5 + 1 modulo 256, using shifts/adds.
    lds     w,rng_s
    mov     b0,w
    lsl     w
    lsl     w
    add     w,b0
    inc     w
    sts     rng_s,w
    ret

check_collision:
    ; Collision only if there is an obstacle in column 0
    ; and the Dino is not jumping.
    lds     w,obst_lo_s
    sbrs    w,0
    rjmp    no_collision

    lds     w,jump_s
    tst     w
    brne    no_collision

    lds     w,lives_s
    tst     w
    breq    no_collision
    dec     w
    sts     lives_s,w
    rcall   update_leds
    rcall   beep_hit

    ; Clear obstacles after hit and add a short safety gap.
    clr     w
    sts     obst_lo_s,w
    sts     obst_hi_s,w
    ldi     w,3
    sts     gap_s,w

no_collision:
    ret

update_best_score:
    ; Compare 16-bit best with current score.
    ; If score > best, update best and EEPROM.
    lds     b0,score_s
    lds     b1,score_hi_s
    lds     b2,best_s
    lds     b3,best_hi_s

    cp      b3,b1
    brlo    new_best
    brne    best_done
    cp      b2,b0
    brsh    best_done

new_best:
    sts     best_s,b0
    sts     best_hi_s,b1
    rcall   eeprom_write_best
best_done:
    ret


; ============================================================
; INTERNAL EEPROM - persistent best score
; EEPROM address 0 = best low byte, address 1 = best high byte.
; If EEPROM is erased (0xFFFF), best score becomes 0.
; ============================================================
eeprom_wait:
    sbic    EECR,EEWE
    rjmp    eeprom_wait
    ret

eeprom_read_best:
    ; read low byte from address 0
    rcall   eeprom_wait
    clr     w
    out     EEARH,w
    out     EEARL,w
    sbi     EECR,EERE
    in      b0,EEDR

    ; read high byte from address 1
    rcall   eeprom_wait
    clr     w
    out     EEARH,w
    ldi     w,1
    out     EEARL,w
    sbi     EECR,EERE
    in      b1,EEDR

    ; erased EEPROM gives 0xFFFF -> convert to 0
    cpi     b0,0xFF
    brne    eeprom_store_read
    cpi     b1,0xFF
    brne    eeprom_store_read
    clr     b0
    clr     b1

eeprom_store_read:
    sts     best_s,b0
    sts     best_hi_s,b1
    ret

eeprom_write_best:
    ; write low byte to address 0
    rcall   eeprom_wait
    lds     b0,best_s
    clr     w
    out     EEARH,w
    out     EEARL,w
    out     EEDR,b0
    sbi     EECR,EEMWE
    sbi     EECR,EEWE

    ; write high byte to address 1
    rcall   eeprom_wait
    lds     b0,best_hi_s
    clr     w
    out     EEARH,w
    ldi     w,1
    out     EEARL,w
    out     EEDR,b0
    sbi     EECR,EEMWE
    sbi     EECR,EEWE
    ret

; ============================================================
; DISPLAY
; ============================================================
show_main_menu:
    rcall   LCD_clear
    rcall   LCD_home
    LDIZ    2*txt_menu_1
    rcall   print_string
    rcall   LCD_lf
    LDIZ    2*txt_menu_2
    rcall   print_string
    ret

show_diff_menu:
    rcall   LCD_clear
    rcall   LCD_home
    LDIZ    2*txt_diff_1
    rcall   print_string
    rcall   LCD_lf
    LDIZ    2*txt_diff_2
    rcall   print_string
    ret

show_best_page:
    rcall   LCD_clear
    rcall   LCD_home
    LDIZ    2*txt_best_1
    rcall   print_string
    rcall   LCD_lf
    LDIZ    2*txt_best_2
    rcall   print_string
    lds     b0,best_s
    lds     b1,best_hi_s
    rcall   print_u16_4
    ret

show_easy_selected:
    rcall   LCD_clear
    rcall   LCD_home
    LDIZ    2*txt_easy
    rcall   print_string
    ret

show_normal_selected:
    rcall   LCD_clear
    rcall   LCD_home
    LDIZ    2*txt_normal
    rcall   print_string
    ret

show_hard_selected:
    rcall   LCD_clear
    rcall   LCD_home
    LDIZ    2*txt_hard
    rcall   print_string
    ret

show_game_over:
    rcall   LCD_clear
    rcall   LCD_home
    LDIZ    2*txt_game_over
    rcall   print_string
    rcall   LCD_lf
    LDIZ    2*txt_score
    rcall   print_string
    lds     b0,score_s
    lds     b1,score_hi_s
    rcall   print_u16_4
    ret
render_game:
    ; Smooth display: no LCD_clear each frame, overwrite full 2 lines.
    rcall   LCD_home

    ; Line 1, column 0: Dino if jumping, otherwise blank.
    lds     w,jump_s
    tst     w
    breq    top_blank
    ldi     a0,'D'
    rjmp    top_put_dino

top_blank:
    ldi     a0,' '

top_put_dino:
    rcall   LCD_putc

    ; columns 1..5: spaces
    ldi     b0,5
render_top_spaces:
    ldi     a0,' '
    rcall   LCD_putc
    dec     b0
    brne    render_top_spaces

    ; columns 6..15: score + lives = S:0000 L:3
    LDIZ    2*txt_score_short
    rcall   print_string
    lds     b0,score_s
    lds     b1,score_hi_s
    rcall   print_u16_4
    LDIZ    2*txt_lives_short
    rcall   print_string
    lds     w,lives_s
    rcall   print_digit_w

    ; Line 2, column 0: Dino if on ground, otherwise blank.
    rcall   LCD_lf
    lds     w,jump_s
    tst     w
    brne    bottom_blank
    ldi     a0,'D'
    rjmp    bottom_put_dino

bottom_blank:
    ldi     a0,' '

bottom_put_dino:
    rcall   LCD_putc

    ; columns 1..15: obstacle mask or spaces
    lds     b0,obst_lo_s
    lds     b1,obst_hi_s

    ; shift once so bit0 corresponds to column 1
    lsr     b1
    ror     b0

    ldi     b2,15
render_bottom_loop:
    sbrc    b0,0
    rjmp    render_hash
    ldi     a0,' '
    rjmp    render_bottom_put

render_hash:
    ldi     a0,'#'

render_bottom_put:
    rcall   LCD_putc

    ; next column
    lsr     b1
    ror     b0
    dec     b2
    brne    render_bottom_loop
    ret


print_string:
    lpm     a0,Z+
    tst     a0
    breq    print_string_done
    rcall   LCD_putc
    rjmp    print_string
print_string_done:
    ret

print_digit_w:
    subi    w,-'0'
    mov     a0,w
    rcall   LCD_putc
    ret

; input: b1:b0 = 16-bit value, prints 4 decimal digits.
; If value exceeds 9999, only the last 4 displayed digits are meaningful.
print_u16_4:
    clr     b2                  ; thousands
p1000:
    ; while value >= 1000
    cpi     b0,low(1000)
    ldi     w,high(1000)
    cpc     b1,w
    brlo    p100_16
    subi    b0,low(1000)
    sbci    b1,high(1000)
    inc     b2
    cpi     b2,10
    brlo    p1000
    clr     b2                  ; avoid printing ':' if score is very high

p100_16:
    mov     a1,b2               ; save thousands digit
    clr     b2                  ; hundreds
p100_16_loop:
    cpi     b0,100
    ldi     w,0
    cpc     b1,w
    brlo    p10_16
    subi    b0,100
    sbci    b1,0
    inc     b2
    rjmp    p100_16_loop

p10_16:
    mov     a2,b2               ; save hundreds digit
    clr     b2                  ; tens
p10_16_loop:
    cpi     b0,10
    ldi     w,0
    cpc     b1,w
    brlo    p_digits_16
    subi    b0,10
    sbci    b1,0
    inc     b2
    rjmp    p10_16_loop

p_digits_16:
    mov     a3,b2               ; save tens digit

    mov     w,a1
    rcall   print_digit_w
    mov     w,a2
    rcall   print_digit_w
    mov     w,a3
    rcall   print_digit_w
    mov     w,b0
    rcall   print_digit_w
    ret

; ============================================================
; LEDS + BUZZER + TIMING
; ============================================================
; ------------------------------------------------------------
; Faster frame rate, slower game logic.
; The screen refreshes every game_delay.
; The obstacle moves only every N frames.
; EASY   : every 4 frames
; NORMAL : every 3 frames
; HARD   : every 2 frames
; ------------------------------------------------------------
game_tick:
    lds     b0,frame_s
    inc     b0
    sts     frame_s,b0

    lds     w,diff_s
    cpi     w,EASY
    breq    tick_easy
    cpi     w,HARD
    breq    tick_hard

tick_normal:
    ldi     b1,3
    rjmp    tick_check

tick_easy:
    ldi     b1,4
    rjmp    tick_check

tick_hard:
    ldi     b1,2

tick_check:
    cp      b0,b1
    brlo    tick_done

    clr     b0
    sts     frame_s,b0
    rcall   move_obstacle
    rcall   check_collision

tick_done:
    ret

; ------------------------------------------------------------
; HIGH AND LOUD MARIO-STYLE MUSIC
; Software square wave for the STK300 buzzer.
; period_table values are delay loop constants:
;     smaller value = higher pitch
; This version is intentionally much higher and punchier than before.
; ------------------------------------------------------------
music_step:
    lds     w,music_s
    inc     w
    andi    w,0x3F              ; 64-note loop
    sts     music_s,w

    ; load note period
    ldi     ZL,low(2*mario_period_table)
    ldi     ZH,high(2*mario_period_table)
    add     ZL,w
    clr     b2
    adc     ZH,b2
    lpm     b1,Z

    ; period = 0 => rest
    tst     b1
    breq    mario_rest

    ; load duration
    ldi     ZL,low(2*mario_duration_table)
    ldi     ZH,high(2*mario_duration_table)
    add     ZL,w
    clr     b2
    adc     ZH,b2
    lpm     b0,Z

mario_play:
    ; more energetic: two square-wave cycles per duration tick
    sbi     PORTE,SPEAKER
    rcall   mario_delay
    cbi     PORTE,SPEAKER
    rcall   mario_delay
    sbi     PORTE,SPEAKER
    rcall   mario_delay
    cbi     PORTE,SPEAKER
    rcall   mario_delay

    dec     b0
    brne    mario_play

mario_rest:
    ; explicit silence
    cbi     PORTE,SPEAKER
    ret

mario_delay:
    mov     b2,b1
mario_delay_loop:
    dec     b2
    brne    mario_delay_loop
    ret

mario_period_table:
.db 5,5,0,5,0,7,5,0,4,0,0,0,9,0,0,0
.db 7,0,0,9,0,0,11,0,0,8,0,7,0,8,8,0
.db 9,5,4,4,0,6,4,0,5,0,7,6,7,0,0,0
.db 7,0,0,9,0,0,11,0,0,8,0,7,0,8,8,0

mario_duration_table:
.db 9,9,4,9,4,9,9,4,12,4,4,4,12,4,4,4
.db 9,4,4,9,4,4,9,4,4,9,4,9,4,9,9,4
.db 12,12,12,10,4,9,9,4,9,4,9,9,9,4,4,4
.db 9,4,4,9,4,4,9,4,4,9,4,9,4,9,9,4

update_leds:
    lds     w,lives_s
    cpi     w,3
    breq    leds_3
    cpi     w,2
    breq    leds_2
    cpi     w,1
    breq    leds_1
    ldi     w,0x00
    rjmp    leds_out
leds_1:
    ldi     w,0xfe
    rjmp    leds_out
leds_2:
    ldi     w,0xfc
    rjmp    leds_out
leds_3:
    ldi     w,0xfe
leds_out:
    out     PORTB,w
    ret

beep_start:
    ldi     b0,20
    rjmp    beep_loop
beep_jump:
    ldi     b0,12
    rjmp    beep_loop
beep_hit:
    ldi     b0,35
beep_loop:
    sbi     PORTE,SPEAKER
    WAIT_US 500
    cbi     PORTE,SPEAKER
    WAIT_US 500
    dec     b0
    brne    beep_loop
    ret

game_delay:
    lds     w,diff_s
    cpi     w,EASY
    breq    delay_easy
    cpi     w,HARD
    breq    delay_hard

delay_normal:
    WAIT_MS 65
    ret
delay_easy:
    WAIT_MS 80
    ret
delay_hard:
    WAIT_MS 55
    ret

; ============================================================
; TEXTS
; ============================================================
txt_menu_1:     .db "1:PLAY 2:DIFF",0
txt_menu_2:     .db "3:BEST SCORES",0
txt_diff_1:     .db "1:EASY 2:NORMAL",0
txt_diff_2:     .db "3:HARD 0:BACK",0
txt_best_1:     .db "BEST SCORE",0
txt_best_2:     .db "SCORE:",0
txt_easy:       .db "EASY SELECTED",0
txt_normal:     .db "NORMAL SELECTED",0
txt_hard:       .db "HARD SELECTED",0
txt_game_over:  .db "GAME OVER",0
txt_score:      .db "SCORE:",0
txt_lives:      .db " L:",0
txt_score_short:.db "S:",0
txt_lives_short:.db " L:",0
