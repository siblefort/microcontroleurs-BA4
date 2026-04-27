; ============================================================
; main_menu.asm
; ATmega128L - STK300 - Remote RC5 + LCD menu
; ============================================================

.include "macros.asm"
.include "definitions.asm"

.equ T1 = 1870          ; valeur RC5 calibrée, à adapter si besoin

.def state = r20
.def difficulty = r21

.equ STATE_MENU       = 0
.equ STATE_PLAY       = 1
.equ STATE_DIFFICULTY = 2
.equ STATE_BEST       = 3

.equ DIFF_EASY   = 1
.equ DIFF_NORMAL = 2
.equ DIFF_HARD   = 3

; ------------------------------------------------------------
; RESET
; ------------------------------------------------------------

reset:
    LDSP RAMEND
    rcall LCD_init

    ldi state, STATE_MENU
    ldi difficulty, DIFF_NORMAL

    rcall show_main_menu

main_loop:
    rcall read_rc5_key        ; bouton lu dans b0

    cpi state, STATE_MENU
    breq handle_menu

    cpi state, STATE_DIFFICULTY
    breq handle_difficulty

    cpi state, STATE_PLAY
    breq handle_play

    cpi state, STATE_BEST
    breq handle_best

    rjmp main_loop

; ------------------------------------------------------------
; MENU PRINCIPAL
; 1 = PLAY
; 2 = DIFFICULTY
; 3 = BEST SCORES
; ------------------------------------------------------------

handle_menu:
    cpi b0, 0x01
    breq menu_to_play

    cpi b0, 0x02
    breq menu_to_difficulty

    cpi b0, 0x03
    breq menu_to_best

    rjmp main_loop

menu_to_play:
    ldi state, STATE_PLAY
    rcall show_play_page
    rjmp main_loop

menu_to_difficulty:
    ldi state, STATE_DIFFICULTY
    rcall show_difficulty_menu
    rjmp main_loop

menu_to_best:
    ldi state, STATE_BEST
    rcall show_best_scores
    rjmp main_loop

; ------------------------------------------------------------
; PAGE PLAY
; 0 = retour menu
; ------------------------------------------------------------

handle_play:
    cpi b0, 0x00
    breq back_to_menu

    rjmp main_loop

; ------------------------------------------------------------
; PAGE BEST SCORES
; 0 = retour menu
; ------------------------------------------------------------

handle_best:
    cpi b0, 0x00
    breq back_to_menu

    rjmp main_loop

; ------------------------------------------------------------
; MENU DIFFICULTY
; 1 = EASY
; 2 = NORMAL
; 3 = HARD
; 0 = retour menu
; ------------------------------------------------------------

handle_difficulty:
    cpi b0, 0x00
    breq back_to_menu

    cpi b0, 0x01
    breq select_easy

    cpi b0, 0x02
    breq select_normal

    cpi b0, 0x03
    breq select_hard

    rjmp main_loop

select_easy:
    ldi difficulty, DIFF_EASY
    rcall show_easy_selected
    rjmp main_loop

select_normal:
    ldi difficulty, DIFF_NORMAL
    rcall show_normal_selected
    rjmp main_loop

select_hard:
    ldi difficulty, DIFF_HARD
    rcall show_hard_selected
    rjmp main_loop

back_to_menu:
    ldi state, STATE_MENU
    rcall show_main_menu
    rjmp main_loop

; ------------------------------------------------------------
; LECTURE TELECOMMANDE RC5
; Résultat : b0 contient le code bouton
; ------------------------------------------------------------

read_rc5_key:
    CLR2 b1,b0
    ldi b2,14

    WP1 PINE,IR
    WAIT_US (T1/4)

read_rc5_loop:
    P2C PINE,IR
    ROL2 b1,b0
    WAIT_US (T1-4)
    DJNZ b2,read_rc5_loop

    com b0
    ret

; ------------------------------------------------------------
; AFFICHAGES LCD
; Chaque string fait environ 32 caractères pour écraser l'écran.
; ------------------------------------------------------------

show_main_menu:
    rcall LCD_home
    PRINTF LCD
.db "1:PLAY 2:DIFF   3:BEST SCORES  ",0
    ret

show_difficulty_menu:
    rcall LCD_home
    PRINTF LCD
.db "1:EASY 2:NORMAL 3:HARD 0:BACK   ",0
    ret

show_play_page:
    rcall LCD_home
    PRINTF LCD
.db "PLAY MODE       0:MENU          ",0
    ret

show_best_scores:
    rcall LCD_home
    PRINTF LCD
.db "BEST SCORES     NO SCORES YET   ",0
    ret

show_easy_selected:
    rcall LCD_home
    PRINTF LCD
.db "DIFFICULTY      EASY SELECTED   ",0
    ret

show_normal_selected:
    rcall LCD_home
    PRINTF LCD
.db "DIFFICULTY      NORMAL SELECTED ",0
    ret

show_hard_selected:
    rcall LCD_home
    PRINTF LCD
.db "DIFFICULTY      HARD SELECTED   ",0
    ret

; ------------------------------------------------------------
; LIBRAIRIES
; ------------------------------------------------------------

.include "lcd.asm"
.include "printf.asm"

