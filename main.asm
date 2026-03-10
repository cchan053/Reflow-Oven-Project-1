$MODMAX10


CSEG
ORG 0000h
    LJMP Main_Program_Start

; dseg variables------------------------------------
dseg at 30h
; Math calculation variables
x:    ds 4
y:    ds 4

; Temperature measurement variables
reference_voltage_reading: ds 2
cold_junction_temp_celsius:         ds 4

; Temperature display BCD
bcd:    ds 5

; Keypad edit entry BCD
parameter_edit_bcd:   ds 5

; Reflow oven controller variables
fsm_current_state:      ds 1
edit_parameter_index:   ds 1
total_runtime_seconds:  ds 2
state_runtime_seconds:  ds 2

soak_temperature_target:      ds 1
soak_duration_seconds:   ds 2
reflow_temperature_target:    ds 1
reflow_duration_seconds: ds 2

current_temperature_celsius:      ds 1
maximum_temp_first_60_seconds:    ds 1

pwm_duty_cycle:       ds 1
pwm_counter_index:    ds 1

; Keypad parameters
edit_mode_active:  ds 1    ; 0,1 (view, edit)
keypad_previous_key:    ds 1    ; last keycode entered (edge detection)
keypad_current_key:     ds 1

bseg
mf:    dbit 1  ; Math overflow flag

; Constants-------------------------------------------
CPU_FREQUENCY   EQU 33333333
SERIAL_BAUD_RATE   EQU 115200
TIMER2_RELOAD_VALUE EQU 65536-(CPU_FREQUENCY/(32*SERIAL_BAUD_RATE))

; Wiring / Inputs-----------------------------------------
RESET_BUTTON    EQU KEY_0      ; de-10 reset
PARAMETER_SELECT_BUTTON    EQU P3.2      ; button to select 4 params (ST, SS, RT, RS)
UNUSED_KEY3     EQU KEY_3    

START_STOP_BUTTON  EQU P3.4       ; Start/Stop abort button
BUZZER_OUTPUT  EQU P2.1      
SOLID_STATE_RELAY_OUTPUT  EQU P0.0

; FSM States---------------------------------------------
STATE_IDLE     EQU 0
STATE_PREHEAT  EQU 1
STATE_SOAK     EQU 2
STATE_PREFLOW  EQU 3
STATE_REFLOW   EQU 4
STATE_COOLING     EQU 5
STATE_DONE     EQU 6
STATE_ERROR    EQU 7

; Serial init + helpers-----------------------------------
Initialize_Serial_Port:
clr TR2
mov T2CON, #30H
mov RCAP2H, #high(TIMER2_RELOAD_VALUE)
mov RCAP2L, #low(TIMER2_RELOAD_VALUE)
setb TR2
mov SCON, #52H
ret

Send_Serial_Char:
    JNB TI, Send_Serial_Char
    CLR TI
    MOV SBUF, a
    RET

Send_Serial_String:
    CLR A
    MOVC A, @A+DPTR
    JZ Serial_String_Done
    LCALL Send_Serial_Char
    INC DPTR
    SJMP Send_Serial_String
Serial_String_Done:
    ret

$include(math32.asm)

; LCD wiring + library -----------------------
ELCD_RS equ P1.7
ELCD_E  equ P1.1
ELCD_D4 equ P0.7
ELCD_D5 equ P0.5
ELCD_D6 equ P0.3
ELCD_D7 equ P0.1
$NOLIST
$include(LCD_4bit_DE10Lite_no_RW.inc)
$LIST

; LCD_SendString --------------------------------
Send_LCD_String:
    clr a
LCD_String_Loop:
    movc a, @a+dptr
    jz   LCD_String_Complete
    lcall ?WriteData
    inc dptr
    clr a
    sjmp LCD_String_Loop
LCD_String_Complete:
    ret

; 7-seg LUT (segments on when signal is low)---------------------
Seven_Segment_Lookup_Table:
    DB 0xC0, 0xF9, 0xA4, 0xB0, 0x99
    DB 0x92, 0x82, 0xF8, 0x80, 0x90
    DB 0x88, 0x83, 0xC6, 0xA1, 0x86, 0x8E

; Delays + Debounce--------------------------------
Delay_50_Milliseconds:
mov R0, #30
Delay_50ms_Loop3:
mov R1, #74
Delay_50ms_Loop2:
mov R2, #250
Delay_50ms_Loop1:
djnz R2, Delay_50ms_Loop1
    djnz R1, Delay_50ms_Loop2
    djnz R0, Delay_50ms_Loop3
    ret

Delay_25_Milliseconds:
mov R0, #15
Delay_25ms_Loop3: mov R1, #74
Delay_25ms_Loop2: mov R2, #250
Delay_25ms_Loop1: djnz R2, Delay_25ms_Loop1
        djnz R1, Delay_25ms_Loop2
        djnz R0, Delay_25ms_Loop3
ret

Delay_Debounce_Chunk:
    mov R6, #60
Debounce_Chunk_Loop1: mov R5, #255
Debounce_Chunk_Loop2: djnz R5, Debounce_Chunk_Loop2
    djnz R6, Debounce_Chunk_Loop1
    ret

Debounce_Start_Stop_Press:
    LCALL Delay_Debounce_Chunk
    jb  START_STOP_BUTTON, Debounce_Start_Stop_Press
    LCALL Delay_Debounce_Chunk
    jb  START_STOP_BUTTON, Debounce_Start_Stop_Press
    ret

Debounce_Start_Stop_Release:
    LCALL Delay_Debounce_Chunk
    jnb START_STOP_BUTTON, Debounce_Start_Stop_Release
    LCALL Delay_Debounce_Chunk
    jnb START_STOP_BUTTON, Debounce_Start_Stop_Release
    ret

Debounce_Reset_Button_Press:
    LCALL Delay_Debounce_Chunk
    jb  RESET_BUTTON, Debounce_Reset_Button_Press
    LCALL Delay_Debounce_Chunk
    jb  RESET_BUTTON, Debounce_Reset_Button_Press
    ret

Debounce_Reset_Button_Release:
    LCALL Delay_Debounce_Chunk
    jnb RESET_BUTTON, Debounce_Reset_Button_Release
    LCALL Delay_Debounce_Chunk
    jnb RESET_BUTTON, Debounce_Reset_Button_Release
    ret

Debounce_Parameter_Select_Press:
    LCALL Delay_Debounce_Chunk
    jb  PARAMETER_SELECT_BUTTON, Debounce_Parameter_Select_Press
    LCALL Delay_Debounce_Chunk
    jb  PARAMETER_SELECT_BUTTON, Debounce_Parameter_Select_Press
    ret

Debounce_Parameter_Select_Release:
    LCALL Delay_Debounce_Chunk
    jnb PARAMETER_SELECT_BUTTON, Debounce_Parameter_Select_Release
    LCALL Delay_Debounce_Chunk
    jnb PARAMETER_SELECT_BUTTON, Debounce_Parameter_Select_Release
    ret

; Buzzer tones + beeps--------------------------------
Play_Buzzer_Note:
Note_Play_Loop:
    mov TH0, R4
    mov TL0, R3
    clr TF0
    setb TR0
Wait_Timer_Overflow:
    jnb TF0, Wait_Timer_Overflow
    clr TR0
    cpl BUZZER_OUTPUT
    djnz R7, Note_Play_Loop
    clr BUZZER_OUTPUT
    ret

Beep_Single_Tone:
    push 03h
    push 04h
    push 07h
    mov R4, #0FCh
    mov R3, #40h
    mov R7, #255 ; adjust to control beep length, max 255 (one byte)
    LCALL Play_Buzzer_Note
    pop 07h
    pop 04h
    pop 03h
    ret

Beep_Multiple_Times:
    push ACC
Beep_Multiple_Loop:
    LCALL Beep_Single_Tone
    LCALL Delay_50_Milliseconds
    djnz ACC, Beep_Multiple_Loop
    pop ACC
    ret

; Displays (temperatures use bcd)--------------------------
Display_Temperature_On_7Segment:
mov dptr, #Seven_Segment_Lookup_Table

mov a, bcd+1
anl a, #0FH
movc a, @a+dptr
mov HEX2, a

mov a, bcd+0
swap a
anl a, #0FH
movc a, @a+dptr
mov HEX1, a

mov a, bcd+0
anl a, #0FH
movc a, @a+dptr
mov HEX0, a
ret

; Display real temperature as T=###C------------------
Print_3Digit_Number_To_LCD:
    mov b, #100
    div ab
    add a, #'0'
    lcall ?WriteData
    mov a, b
    mov b, #10
    div ab
    add a, #'0'
    lcall ?WriteData
    mov a, b
    add a, #'0'
    lcall ?WriteData
    ret

Display_Current_Temperature_On_LCD:
Set_Cursor(2,1)
mov a, #'T'
lcall ?WriteData
mov a, #'='
lcall ?WriteData

mov a, current_temperature_celsius
lcall Print_3Digit_Number_To_LCD

mov a, #'C'
lcall ?WriteData

mov a, #' '
lcall ?WriteData

mov a, #' '
lcall ?WriteData

ret

; Displays 16-bit runtime ------------------------------
Display_Total_Runtime_On_LCD:
    Set_Cursor(2,10)
    mov a, #'T'
    lcall ?WriteData
    mov a, #'T'
    lcall ?WriteData
    mov a, #'='
    lcall ?WriteData

    ; Load the total_runtime_seconds into x
    mov x+0, total_runtime_seconds+0  ; Low byte
    mov x+1, total_runtime_seconds+1  ; High byte
    mov x+2, #0          
    mov x+3, #0

    ; convert x to bcd
    lcall hex2bcd

    ; display hundreds digit
    mov a, bcd+1
    anl a, #0x0F
    orl a, #'0'           ; Convert number to ASCII character
    lcall ?WriteData

    ; display middle digit
    mov a, bcd+0
    swap a
    anl a, #0x0F
    orl a, #'0'
    lcall ?WriteData

    ; display ones digit
    mov a, bcd+0
    anl a, #0x0F
    orl a, #'0'
    lcall ?WriteData

    ret

mov a, total_runtime_seconds
lcall Print_3Digit_Number_To_LCD

ret

Display_State_Time_On_LCD:
Set_Cursor(1,6)
mov a, state_runtime_seconds
lcall Print_3Digit_Number_To_LCD
ret


; Show edit digits when editing
Display_Parameter_Edit_Entry_On_LCD:
Set_Cursor(2,1)
mov a,#'S'   ; SET=XXXX
lcall ?WriteData
mov a,#'E'
lcall ?WriteData
mov a,#'T'
lcall ?WriteData
mov a,#'='
lcall ?WriteData

mov a, parameter_edit_bcd+1
swap a
anl a, #0FH
add a, #'0'
lcall ?WriteData

mov a, parameter_edit_bcd+1
anl a, #0FH
add a, #'0'
lcall ?WriteData

mov a, parameter_edit_bcd+0
swap a
anl a, #0FH
add a, #'0'
lcall ?WriteData

mov a, parameter_edit_bcd+0
anl a, #0FH
add a, #'0'
lcall ?WriteData

; pad remaining
mov a,#' '
lcall ?WriteData
mov a,#' '
lcall ?WriteData
mov a,#' '
lcall ?WriteData
mov a,#' '
lcall ?WriteData
mov a,#' '
lcall ?WriteData
mov a,#' '
lcall ?WriteData
ret

; Serial prints as: "S:<state> C:<temp>\r\n"
Display_Temperature_On_Serial:
   
    mov a, #'S'
    lcall Send_Serial_Char
    mov a, #':'
    lcall Send_Serial_Char

    ; print state
    mov a, fsm_current_state
    mov b, #10
    div ab              ; A=tens, B=ones
    jz  Serial_State_One_Digit
    add a, #'0'
    lcall Send_Serial_Char
Serial_State_One_Digit:
    mov a, b
    add a, #'0'
    lcall Send_Serial_Char

   
    mov a, #' '
    lcall Send_Serial_Char
    mov a, #'C'
    lcall Send_Serial_Char
    mov a, #':'
    lcall Send_Serial_Char

    ; print current_temperature_celsius (3 digits)
    mov a, current_temperature_celsius
    mov b, #100
    div ab              ; A=hundreds, B=remainder
    add a, #'0'
    lcall Send_Serial_Char

    mov a, b
    mov b, #10
    div ab              ; A=tens, B=ones
    add a, #'0'
    lcall Send_Serial_Char

    mov a, b
    add a, #'0'
    lcall Send_Serial_Char

    ; newline
    mov a, #'\r'
    lcall Send_Serial_Char
    mov a, #'\n'
    lcall Send_Serial_Char
    ret


Update_Current_Temp_From_Calculation:
    mov a, x+1
    jz  Temp_Within_Range
    ; If x+1 is greater than 0, temp is >= 256C.
    mov current_temperature_celsius, #255
    ret
Temp_Within_Range:
    mov a, x+0
    mov current_temperature_celsius, a
    ret


; LCD line 1 display---------------------------------
STRING_IDLE_STATE:    db 'IDLE:',0
STRING_PREHEAT_STATE:     db 'PRHT:',0
STRING_SOAK_STATE:    db 'SOAK:',0
STRING_REFLOW_STATE:  db 'RFLW:',0
STRING_COOLING_STATE:    db 'COOL:',0
STRING_DONE_STATE:    db 'DONE:',0
STRING_ERROR_STATE:   db 'ERR!:',0
STRING_PREFLOW_STATE: db 'PRFL:',0

LABEL_SOAK_TEMPERATURE:      db ' ST=',0
LABEL_SOAK_SECONDS:      db ' SS=',0
LABEL_REFLOW_TEMPERATURE:      db ' RT=',0
LABEL_REFLOW_SECONDS:      db ' RS=',0

Print_3Digit_Seconds_To_LCD:
    mov a, R3
    LCALL Print_3Digit_Number_To_LCD
    ret

Display_FSM_State_On_LCD_Line1:
    Set_Cursor(1,1)

    mov a, fsm_current_state
    cjne a, #STATE_IDLE, Check_State_Preheat
        mov dptr, #STRING_IDLE_STATE
        sjmp Print_State_String
Check_State_Preheat: cjne a, #STATE_PREHEAT, Check_State_Soak
        mov dptr, #STRING_PREHEAT_STATE
        sjmp Print_State_String
Check_State_Soak: cjne a, #STATE_SOAK, Check_State_Preflow
        mov dptr, #STRING_SOAK_STATE
        sjmp Print_State_String
Check_State_Preflow:
cjne a, #STATE_PREFLOW, Check_State_Reflow
mov dptr, #STRING_PREFLOW_STATE
        sjmp Print_State_String  
           
Check_State_Reflow: cjne a, #STATE_REFLOW, Check_State_Cooling
        mov dptr, #STRING_REFLOW_STATE
        sjmp Print_State_String
Check_State_Cooling: cjne a, #STATE_COOLING, Default_Error_State
        mov dptr, #STRING_COOLING_STATE
        sjmp Print_State_String
Default_Error_State:
        mov dptr, #STRING_ERROR_STATE


Print_State_String:
    LCALL Send_LCD_String

    mov a, fsm_current_state
    cjne a, #STATE_IDLE, State_Display_Complete

    mov a, #' '
    lcall ?WriteData
    mov a, #' '
    lcall ?WriteData
    mov a, #' '
    lcall ?WriteData

    mov a, edit_parameter_index
    cjne a, #0, Check_Parameter_Selection_1
        mov dptr, #LABEL_SOAK_TEMPERATURE
        LCALL Send_LCD_String
        mov a, soak_temperature_target
        LCALL Print_3Digit_Number_To_LCD
        sjmp State_Display_Complete
Check_Parameter_Selection_1:
    cjne a, #1, Check_Parameter_Selection_2
        mov dptr, #LABEL_SOAK_SECONDS
        LCALL Send_LCD_String
        mov R2, soak_duration_seconds+1
        mov R3, soak_duration_seconds+0
        LCALL Print_3Digit_Seconds_To_LCD
        sjmp State_Display_Complete
Check_Parameter_Selection_2:
    cjne a, #2, Check_Parameter_Selection_3
        mov dptr, #LABEL_REFLOW_TEMPERATURE
        LCALL Send_LCD_String
        mov a, reflow_temperature_target
        LCALL Print_3Digit_Number_To_LCD
        sjmp State_Display_Complete
Check_Parameter_Selection_3:
        mov dptr, #LABEL_REFLOW_SECONDS
        LCALL Send_LCD_String
        mov R2, reflow_duration_seconds+1
        mov R3, reflow_duration_seconds+0
        LCALL Print_3Digit_Seconds_To_LCD

State_Display_Complete:
    ret

; PWM 20 ticks/sec ---------------------------------
; active-low SSR
PWM_Update_Output:
    inc pwm_counter_index
    mov a, pwm_counter_index
    cjne a, #20, PWM_Continue ; keep as 20!!!!
        mov pwm_counter_index, #0
PWM_Continue:
    mov a, pwm_counter_index
    clr c
    subb a, pwm_duty_cycle
    jc  Turn_SSR_On

Turn_SSR_Off:
    clr SOLID_STATE_RELAY_OUTPUT         ; off (active-high)
    clr LEDRA.0
    ret
Turn_SSR_On:
    setb SOLID_STATE_RELAY_OUTPUT          ; on (active-high)
    setb LEDRA.0
    ret



; Control
Update_Heating_Control:
    mov a, fsm_current_state
   
    cjne a, #STATE_PREHEAT, Check_Control_Soak
    ; preheat logic
    mov pwm_duty_cycle, #20       ; 100% power
    ret

Check_Control_Soak:
    cjne a, #STATE_SOAK, Check_Control_Preflow
    ; soak logic
    mov a, current_temperature_celsius
    clr c
    subb a, soak_temperature_target
    jc  Set_PWM_Duty_100_Percent     ; If current_temperature_celsius < soak_temperature_target, 100% power
   
    mov a, current_temperature_celsius
    clr c
    subb a, soak_temperature_target
    clr c
    subb a, #2
    jnc Set_PWM_Duty_0_Percent      ; If current_temperature_celsius >= soak_temperature_target + 2, 0% power
   
    mov pwm_duty_cycle, #4        ; Target reached, 20% maintenance power
    ret

Check_Control_Preflow:
    cjne a, #STATE_PREFLOW, Check_Control_Reflow
    sjmp Apply_Reflow_Heating

Check_Control_Reflow:
    cjne a, #STATE_REFLOW, Set_PWM_Duty_0_Percent ; turn off if not in preflow or reflow

Apply_Reflow_Heating:
    ; preflow and reflow logic
    mov a, current_temperature_celsius
    clr c
    subb a, reflow_temperature_target
    jc  Set_PWM_Duty_100_Percent     ; If current_temperature_celsius < reflow_temperature_target, 100% power
   
    mov a, current_temperature_celsius
    clr c
    subb a, reflow_temperature_target
    clr c
    subb a, #2
    jnc Set_PWM_Duty_0_Percent      ; If current_temperature_celsius >= reflow_temperature_target + 2, 0% power
   
    mov pwm_duty_cycle, #6        ; Target reached, 30% maintenance power
    ret

; duty setters
Set_PWM_Duty_100_Percent:
    mov pwm_duty_cycle, #20
    ret

Set_PWM_Duty_0_Percent:
    mov pwm_duty_cycle, #0
    ret

; full reset (with RESET_BUTTON)-------------------------
Clear_Parameter_Edit_Entry:
    clr a
    mov parameter_edit_bcd+0, a
    mov parameter_edit_bcd+1, a
    mov parameter_edit_bcd+2, a
    mov parameter_edit_bcd+3, a
    mov parameter_edit_bcd+4, a
    ret

Reset_System_To_Defaults:
    mov pwm_duty_cycle, #0
    setb SOLID_STATE_RELAY_OUTPUT         ; off (active-low)

    mov fsm_current_state, #STATE_IDLE
    mov edit_parameter_index, #0
    mov edit_mode_active, #0
    mov keypad_previous_key,  #0FFh

    mov total_runtime_seconds+0, #0
    mov total_runtime_seconds+1, #0
    mov state_runtime_seconds+0, #0
    mov state_runtime_seconds+1, #0
    mov maximum_temp_first_60_seconds, #0
    mov pwm_counter_index, #0

    mov soak_temperature_target, #150
    mov soak_duration_seconds+0, #90
    mov soak_duration_seconds+1, #0
    mov reflow_temperature_target, #220
    mov reflow_duration_seconds+0, #45
    mov reflow_duration_seconds+1, #0
   

    lcall Clear_Parameter_Edit_Entry
    mov a, #2
    LCALL Beep_Multiple_Times
    ret

; FSM (1 Hz) ------------------------------------
FSM_Execute_One_Second_Update:
    mov a, fsm_current_state
    cjne a, #STATE_IDLE, FSM_System_Running
        ret
FSM_System_Running:
    inc total_runtime_seconds+0
    mov a, total_runtime_seconds+0
    jnz FSM_Increment_State_Time
    inc total_runtime_seconds+1
FSM_Increment_State_Time:
    inc state_runtime_seconds+0
    mov a, state_runtime_seconds+0
    jnz FSM_Track_Max_Temperature
    inc state_runtime_seconds+1
FSM_Track_Max_Temperature:

    ; track max temp in first 60s
    mov a, total_runtime_seconds+1
    jnz Skip_Maximum_Temperature_Tracking
    mov a, total_runtime_seconds+0
    cjne a, #60, Check_If_Less_Than_60_Seconds
        sjmp Check_60_Second_Abort_Condition
Check_If_Less_Than_60_Seconds:
    jc  Update_Maximum_Temperature
    sjmp Skip_Maximum_Temperature_Tracking
Update_Maximum_Temperature:
    mov a, current_temperature_celsius
    clr c
    subb a, maximum_temp_first_60_seconds
    jc  Skip_Maximum_Temperature_Tracking
    mov a, current_temperature_celsius
    mov maximum_temp_first_60_seconds, a
Skip_Maximum_Temperature_Tracking:

Check_60_Second_Abort_Condition:
    mov a, total_runtime_seconds+1
    jnz No_60_Second_Abort
    mov a, total_runtime_seconds+0
    cjne a, #60, No_60_Second_Abort
        mov a, maximum_temp_first_60_seconds
        clr c
        subb a, #50
        jnc No_60_Second_Abort
            mov fsm_current_state, #STATE_ERROR
            mov pwm_duty_cycle, #0
            setb SOLID_STATE_RELAY_OUTPUT
            mov a, #10
            LCALL Beep_Multiple_Times
            ret
No_60_Second_Abort:

    mov a, fsm_current_state
    cjne a, #STATE_PREHEAT, FSM_Check_Soak_Transition
        mov a, current_temperature_celsius
        clr c
        subb a, soak_temperature_target
        jc  FSM_Update_Complete
            mov fsm_current_state, #STATE_SOAK
            mov state_runtime_seconds+0, #0
            mov state_runtime_seconds+1, #0
            mov a, #1
            LCALL Beep_Multiple_Times
            ret

FSM_Check_Soak_Transition:
    cjne a, #STATE_SOAK, FSM_Check_Preflow_Transition
        mov a, state_runtime_seconds+0
        clr c
        subb a, soak_duration_seconds+0
        mov a, state_runtime_seconds+1
        subb a, soak_duration_seconds+1
        jc  FSM_Update_Complete
            mov fsm_current_state, #STATE_PREFLOW
            mov state_runtime_seconds+0, #0
            mov state_runtime_seconds+1, #0
            mov a, #1
            LCALL Beep_Multiple_Times
            ret
           
FSM_Check_Preflow_Transition:
cjne a, #STATE_PREFLOW, FSM_Check_Reflow_Transition
mov a, current_temperature_celsius
clr c
subb a, reflow_temperature_target
jc FSM_Update_Complete
mov fsm_current_state, #STATE_REFLOW
mov state_runtime_seconds+0, #0
            mov state_runtime_seconds+1, #0
            mov a, #1
            LCALL Beep_Multiple_Times
            ret

FSM_Check_Reflow_Transition:
    cjne a, #STATE_REFLOW, FSM_Check_Cooling_Transition
        mov a, state_runtime_seconds+0
        clr c
        subb a, reflow_duration_seconds+0
        mov a, state_runtime_seconds+1
        subb a, reflow_duration_seconds+1
        jc  FSM_Update_Complete
            mov fsm_current_state, #STATE_COOLING
            mov state_runtime_seconds+0, #0
            mov state_runtime_seconds+1, #0
            mov a, #1
            LCALL Beep_Multiple_Times
            ret

FSM_Check_Cooling_Transition:
    cjne a, #STATE_COOLING, FSM_Update_Complete
        mov a, current_temperature_celsius
        clr c
        subb a, #50
        jnc FSM_Update_Complete
            mov fsm_current_state, #STATE_IDLE ; changed from STATE_DONE, I dont think we need that state at all
            mov pwm_duty_cycle, #0
            setb SOLID_STATE_RELAY_OUTPUT
            mov a, #5
            LCALL Beep_Multiple_Times
            ret

FSM_Update_Complete:
    ret

; Start/Abort-------------------------------
Start_Reflow_Process:
    mov fsm_current_state, #STATE_PREHEAT
    mov total_runtime_seconds+0, #0
    mov total_runtime_seconds+1, #0
    mov state_runtime_seconds+0, #0
    mov state_runtime_seconds+1, #0
    mov maximum_temp_first_60_seconds, #0
    mov pwm_counter_index, #0
    mov a, #1
    LCALL Beep_Multiple_Times
    ret

Abort_Reflow_Process:
    mov fsm_current_state, #STATE_IDLE
    mov pwm_duty_cycle, #0
    setb SOLID_STATE_RELAY_OUTPUT
    mov total_runtime_seconds, #0
    mov state_runtime_seconds, #0
    mov a, #1
    LCALL Beep_Multiple_Times
    ret

; non block 4x4 keypad scanner
KEYPAD_ROW_1 EQU P1.2
KEYPAD_ROW_2 EQU P1.4
KEYPAD_ROW_3 EQU P1.6
KEYPAD_ROW_4 EQU P2.0
KEYPAD_COL_1 EQU P2.2
KEYPAD_COL_2 EQU P2.4
KEYPAD_COL_3 EQU P2.6
KEYPAD_COL_4 EQU P3.0

; keypad value lookup table
Keypad_Value_Table:
    DB 01h, 02h, 03h, 0Ah  ; 1, 2, 3, A
    DB 04h, 05h, 06h, 0Bh  ; 4, 5, 6, B
    DB 07h, 08h, 09h, 0Ch  ; 7, 8, 9, C
    DB 0Eh, 00h, 0Fh, 0Dh  ; *, 0, #, D

Configure_Keypad_Pin_Modes:
    orl P1MOD, #0b_01010100  ; rows 1,3 as outputs
    orl P2MOD, #0b_00000001  ; row 4 as output
    anl P2MOD, #0b_10101011  ; cols 1,2,3 as inputs
    anl P3MOD, #0b_11111110  ; col 4 as input
    ret

Read_Keypad_Non_Blocking:
    ; low for scanning
    clr KEYPAD_ROW_1
    clr KEYPAD_ROW_2
    clr KEYPAD_ROW_3
    clr KEYPAD_ROW_4
   
    ; check key press
    mov c, KEYPAD_COL_1
    anl c, KEYPAD_COL_2
    anl c, KEYPAD_COL_3
    anl c, KEYPAD_COL_4
    jc  No_Key_Detected
   
    lcall Delay_25_Milliseconds
   
    ; verify key pressed
    mov c, KEYPAD_COL_1
    anl c, KEYPAD_COL_2
    anl c, KEYPAD_COL_3
    anl c, KEYPAD_COL_4
    jc  No_Key_Detected
   
    ; release rows
    setb KEYPAD_ROW_1
    setb KEYPAD_ROW_2
    setb KEYPAD_ROW_3
    setb KEYPAD_ROW_4
   
    ; scans row 1
    clr KEYPAD_ROW_1
    mov R6, #0            
    jnb KEYPAD_COL_1, Key_Found_Col_1
    jnb KEYPAD_COL_2, Key_Found_Col_2
    jnb KEYPAD_COL_3, Key_Found_Col_3
    jnb KEYPAD_COL_4, Key_Found_Col_4
    setb KEYPAD_ROW_1
   
    ; scans row 2
    clr KEYPAD_ROW_2
    mov R6, #4            
    jnb KEYPAD_COL_1, Key_Found_Col_1
    jnb KEYPAD_COL_2, Key_Found_Col_2
    jnb KEYPAD_COL_3, Key_Found_Col_3
    jnb KEYPAD_COL_4, Key_Found_Col_4
    setb KEYPAD_ROW_2
   
    ; scans row 3
    clr KEYPAD_ROW_3
    mov R6, #8              
    jnb KEYPAD_COL_1, Key_Found_Col_1
    jnb KEYPAD_COL_2, Key_Found_Col_2
    jnb KEYPAD_COL_3, Key_Found_Col_3
    jnb KEYPAD_COL_4, Key_Found_Col_4
    setb KEYPAD_ROW_3
   
    ; scans row 4
    clr KEYPAD_ROW_4
    mov R6, #12            
    jnb KEYPAD_COL_1, Key_Found_Col_1
    jnb KEYPAD_COL_2, Key_Found_Col_2
    jnb KEYPAD_COL_3, Key_Found_Col_3
    jnb KEYPAD_COL_4, Key_Found_Col_4
    setb KEYPAD_ROW_4
   
No_Key_Detected:
    clr c                   ; no key carry is 0
    ret

Key_Found_Col_1:
    mov a, R6              
    mov dptr, #Keypad_Value_Table
    movc a, @a+dptr        
    mov R7, a
    setb c                  ; key found carry is 1
    ret

Key_Found_Col_2:
    mov a, R6
    add a, #1              
    mov dptr, #Keypad_Value_Table
    movc a, @a+dptr
    mov R7, a
    setb c
    ret

Key_Found_Col_3:
    mov a, R6
    add a, #2              
    mov dptr, #Keypad_Value_Table
    movc a, @a+dptr
    mov R7, a
    setb c
    ret

Key_Found_Col_4:
    mov a, R6
    add a, #3            
    mov dptr, #Keypad_Value_Table
    movc a, @a+dptr
    mov R7, a
    setb c
    ret
; Edit BCD shift and commit--------------------------------------
ROTATE_LEFT_WITH_CARRY_MACRO MAC
mov a, %0
rlc a
mov %0, a
ENDMAC

Shift_Edit_Parameter_Left:
mov R0, #4
Shift_Edit_Loop:
clr c
ROTATE_LEFT_WITH_CARRY_MACRO(parameter_edit_bcd+0)
ROTATE_LEFT_WITH_CARRY_MACRO(parameter_edit_bcd+1)
ROTATE_LEFT_WITH_CARRY_MACRO(parameter_edit_bcd+2)
ROTATE_LEFT_WITH_CARRY_MACRO(parameter_edit_bcd+3)
ROTATE_LEFT_WITH_CARRY_MACRO(parameter_edit_bcd+4)
djnz R0, Shift_Edit_Loop
mov a, R7
orl a, parameter_edit_bcd+0
mov parameter_edit_bcd+0, a
ret

; parameter_edit_bcd[0..1]
Convert_BCD_Edit_To_16bit_Value:
    mov a, parameter_edit_bcd+0
    anl a, #0Fh
    mov R0, a
    mov a, parameter_edit_bcd+0
    swap a
    anl a, #0Fh
    mov R1, a
    mov a, parameter_edit_bcd+1
    anl a, #0Fh
    mov R2, a
    mov a, parameter_edit_bcd+1
    swap a
    anl a, #0Fh
    mov R3, a

    mov R5, #0
    mov R6, #0

    mov a, R5
    add a, R0
    mov R5, a
    clr a
    addc a, R6
    mov R6, a

    mov a, R1
    mov b, #10
    mul ab
    add a, R5
    mov R5, a
    mov a, b
    addc a, R6
    mov R6, a

    mov a, R2
    mov b, #100
    mul ab
    add a, R5
    mov R5, a
    mov a, b
    addc a, R6
    mov R6, a

    mov a, R3
    mov b, #232
    mul ab
    add a, R5
    mov R5, a
    mov a, b
    addc a, R6
    mov R6, a

    mov a, R3
    mov b, #3
    mul ab
    mov R4, a
    mov a, R6
    add a, R4
    mov R6, a
    ret

Commit_Edited_Parameter_Value:
    lcall Convert_BCD_Edit_To_16bit_Value
    mov a, edit_parameter_index
    cjne a, #0, Commit_Parameter_1
        mov soak_temperature_target, R5
        ret
Commit_Parameter_1: cjne a, #1, Commit_Parameter_2
        mov soak_duration_seconds+0, R5
        mov soak_duration_seconds+1, R6
        ret
Commit_Parameter_2: cjne a, #2, Commit_Parameter_3
        mov reflow_temperature_target, R5
        ret
Commit_Parameter_3:
        mov reflow_duration_seconds+0, R5
        mov reflow_duration_seconds+1, R6
        ret


; UI in IDLE -------------------------
Handle_User_Input_In_Idle_State:
    jnb PARAMETER_SELECT_BUTTON, Handle_Parameter_Select_Button
    sjmp Handle_Keypad_Input
Handle_Parameter_Select_Button:
    LCALL Debounce_Parameter_Select_Press
    inc edit_parameter_index
    mov a, edit_parameter_index
    cjne a, #4, Parameter_Select_OK
        mov edit_parameter_index, #0
Parameter_Select_OK:
    mov edit_mode_active, #0
    lcall Clear_Parameter_Edit_Entry
    LCALL Debounce_Parameter_Select_Release
    mov a, #1
    LCALL Beep_Multiple_Times

Handle_Keypad_Input:
    lcall Read_Keypad_Non_Blocking
    jnc User_Input_Complete

    mov keypad_current_key, R7
    mov a, keypad_previous_key
    cjne a, keypad_current_key, New_Keypress_Detected
    ret
New_Keypress_Detected:
    mov keypad_previous_key, keypad_current_key

    mov a, keypad_current_key
    cjne a, #0Eh, Check_Not_Star_Key
        mov a, edit_mode_active
        jz Enter_Edit_Mode
        mov edit_mode_active, #0
        lcall Clear_Parameter_Edit_Entry
        mov a, #1
        lcall Beep_Multiple_Times
        ret
Enter_Edit_Mode:
        mov edit_mode_active, #1
        lcall Clear_Parameter_Edit_Entry
        mov a, #1
        lcall Beep_Multiple_Times
        ret
Check_Not_Star_Key:

    mov a, edit_mode_active
    jz User_Input_Complete

    mov a, keypad_current_key
    cjne a, #0Fh, Check_Not_Hash_Key
        lcall Commit_Edited_Parameter_Value
        mov edit_mode_active, #0
        lcall Clear_Parameter_Edit_Entry
        mov a, #1
        lcall Beep_Multiple_Times
        ret
Check_Not_Hash_Key:

    mov a, keypad_current_key
    clr c
    subb a, #0Ah
    jnc User_Input_Complete

    mov R7, keypad_current_key
    lcall Shift_Edit_Parameter_Left
    ret

User_Input_Complete:
    mov keypad_previous_key, #0FFh
    ret


; Strings -------------
Startup_Message:  db 'GROUP A04 RC', 0


; Main ------------------

Main_Program_Start:
mov SP, #7FH
clr a
mov LEDRA, a
mov LEDRB, a


LCALL Initialize_Serial_Port

; LCD pins outputs
mov P0MOD, #10101010b
    mov P1MOD, #10000010b

    ; SSR + Buzzer outputs (P1.3, P1.5)
    ;orl P1MOD, #028h
    orl P0MOD, #01h
    orl P2MOD, #02h
   
    clr BUZZER_OUTPUT
    setb SOLID_STATE_RELAY_OUTPUT            ; off at boot (active-low)
    clr LEDRA.0
   

    ; keys + button pullups
    anl P4MOD, #08Eh
    setb P4.0
    setb P4.4
    setb P4.5
    setb P4.6

    mov TMOD, #01h

    lcall Configure_Keypad_Pin_Modes

    LCALL ELCD_4BIT
Set_Cursor(1, 1)
    Send_Constant_String(#Startup_Message)

    ; defaults
    mov fsm_current_state, #STATE_IDLE
    mov edit_parameter_index, #0
    mov edit_mode_active, #0
    mov keypad_previous_key, #0FFh
   

    mov soak_temperature_target, #150
    mov soak_duration_seconds+0, #90
    mov soak_duration_seconds+1, #0
    mov reflow_temperature_target, #220
    mov reflow_duration_seconds+0, #45
    mov reflow_duration_seconds+1, #0

    mov pwm_duty_cycle, #0
    mov pwm_counter_index, #0
   
    mov total_runtime_seconds, #0
mov state_runtime_seconds, #0

    lcall Clear_Parameter_Edit_Entry

mov ADC_C, #0x80
LCALL Delay_50_Milliseconds

Main_Loop:
    mov R7, #17

PWM_Tick_Loop:
    LCALL Delay_50_Milliseconds
    LCALL PWM_Update_Output

    ; RESET_BUTTON reset anytime
    jnb RESET_BUTTON, Execute_Reset_Button
    sjmp After_Reset_Button_Check
Execute_Reset_Button:
    LCALL Debounce_Reset_Button_Press
    LCALL Reset_System_To_Defaults
Wait_For_Reset_Release:
    jnb RESET_BUTTON, Wait_For_Reset_Release
    LCALL Debounce_Reset_Button_Release
After_Reset_Button_Check:

    ; Start/Stop button
    jnb START_STOP_BUTTON, Start_Stop_Button_Pressed
    sjmp Start_Stop_Button_Done
Start_Stop_Button_Pressed:
    LCALL Debounce_Start_Stop_Press
    mov a, fsm_current_state
    cjne a, #STATE_IDLE, Execute_Abort
        LCALL Start_Reflow_Process
        sjmp Wait_For_Button_Release
Execute_Abort:
        LCALL Abort_Reflow_Process
Wait_For_Button_Release:
Wait_For_Start_Stop_Release:
    jnb START_STOP_BUTTON, Wait_For_Start_Stop_Release
    LCALL Debounce_Start_Stop_Release
Start_Stop_Button_Done:

    ; UI only in IDLE
    mov a, fsm_current_state
    cjne a, #STATE_IDLE, Skip_User_Input
        LCALL Handle_User_Input_In_Idle_State
Skip_User_Input:

    djnz R7, PWM_Tick_Loop

; ADC / temperature math (1 Hz)

    ; Read LM4040 reference from channel 0
    mov ADC_C, #0
    LCALL Delay_50_Milliseconds
    mov reference_voltage_reading+0, ADC_L
    mov reference_voltage_reading+1, ADC_H

    ; Read cold temp from channel 1
    mov ADC_C, #1
    LCALL Delay_50_Milliseconds
    mov x+0, ADC_L
    mov x+1, ADC_H
    mov x+2, #0
    mov x+3, #0
    Load_y(41146)
    lcall mul32
    mov y+0, reference_voltage_reading+0
    mov y+1, reference_voltage_reading+1
    mov y+2, #0
    mov y+3, #0
    lcall div32
    load_Y(27300)
    lcall sub32
    load_Y(10)
    lcall div32
    mov cold_junction_temp_celsius+0, x+0
    mov cold_junction_temp_celsius+1, x+1

    ; read thermocouple from channel 2
    mov ADC_C, #2
    LCALL Delay_50_Milliseconds
    mov x+0, ADC_L
    mov x+1, ADC_H
    mov x+2, #0
    mov x+3, #0
    load_y(33452)
    lcall mul32
    mov y+0, reference_voltage_reading+0
    mov y+1, reference_voltage_reading+1
    mov y+2, #0
    mov y+3, #0
    lcall div32
    Load_y(10)
    lcall div32
    mov y+0, cold_junction_temp_celsius+0
    mov y+1, cold_junction_temp_celsius+1
    mov y+2, #0
    mov y+3, #0
    lcall add32

Load_y(10)
   
lcall div32

    LCALL Update_Current_Temp_From_Calculation
    LCALL hex2bcd
    LCALL Update_Heating_Control
    LCALL Display_FSM_State_On_LCD_Line1
    LCALL Display_Temperature_On_7Segment

    mov a, edit_mode_active
    jz  Display_Temperature_Mode
        LCALL Display_Parameter_Edit_Entry_On_LCD
        sjmp Display_Complete
Display_Temperature_Mode:
LCALL Display_Current_Temperature_On_LCD
lcall Display_Total_Runtime_On_LCD
lcall Display_State_Time_On_LCD

Display_Complete:

LCALL Display_Temperature_On_Serial

    LCALL FSM_Execute_One_Second_Update

LJMP Main_Loop

end
