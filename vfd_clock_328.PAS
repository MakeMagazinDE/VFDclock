program vfd_clock;
// C. Meyer 12/2020

{$NOSHADOW}
{ $WG}                     {global Warnings off}

// 2. Platinenversion TTH mit MAX6921AWI, sonst 4094-SR
{$DEFINE NEW_PCB}

{$DEFINE MEGA328}

{$DEFINE SENSOR_BTN}
{ $DEFINE DCF_IN_POS}
{ $DEFINE DCF_IN_NEG}
{ $DEFINE DCF_TEST}
{ $DEFINE DEBUG}
{ $DEFINE STARTUP_ANIM}

{$IFDEF MEGA328}
Device = mega328pb, VCC=5;
{$ELSE}
Device = mega168, VCC=5;  // Margas Uhr
{$ENDIF}

{ $BOOTRST $00C00}         {Reset Jump to $00C00}

Define_Fuses
//  Override_Fuses;
  Override_Fuses;    // optional, always replaces fuses in ISPE
  COMport = USB;     // COM2..COM7, USB
  FuseBits0 = [];
{$IFDEF MEGA328}
  FuseBits1 = [BOOTSZ1,BOOTRST];
  FuseBits2 = [BODLEVEL1];
  LockBits0 = [BOOTLOCK12, BOOTLOCK11];
{$ENDIF}
  ProgMode = SPI;    // SPI, JTAG or OWD
  ProgFuses = true;
  ProgLock = true;
  ProgFlash = true;
  ProgEEprom= true;
  

Import SysTick, TWImaster, RTClock, SerPort, BeepPort;
{$IFDEF DCF_IN_POS}
{$DEFINE DCF_IN}
Import DCFclock;
{$ENDIF}

{$IFDEF DCF_IN_NEG}
{$DEFINE DCF_IN}
Import DCFclock;
{$ENDIF}

From System Import LongWord, Random;


Define
  ProcClock      = 16000000;       {Hertz}
  SysTick        = 2;              {msec}
  StackSize      = $0032, iData;
  FrameSize      = $0032, iData;
  TWIpresc       = TWI_BR400;
  RTClock        = iData, DateTime;
  RTCsource      = SysTick;
{$IFDEF DCF_IN_NEG}
  DCFclock = iData;
  DCFport = PinC, 0, negative; // Port, bitnummer, Polarität
  DCFfieldMode = decrement;    // decrement, optional "reset"
{$ENDIF}
{$IFDEF DCF_IN_POS}
  DCFclock = iData;
  DCFport = PinC, 0, postive; // Port, bitnummer, Polarität
  DCFfieldMode = decrement;    // decrement, optional "reset"
{$ENDIF}

  SerPort= 57600;
  RxBuffer       = 32, iData;
  TxBuffer       = 64, iData;
  
//  ADCchans = [1], iData, Int2; // 1 Kanäle benutzen, PC0
//  ADCpresc = 64;           // Vorteiler 64
  
  BeepPort = PortD, 7;

Implementation

{$IDATA}
const
  sr_on: Boolean = false;
  sr_off: Boolean = true;
  rtc_adr: byte = $68;
  lm75_adr: byte = $48;
  c_DecodeArr: Array[0..4,0..15] of Byte =
  ((
  $01,   // 0 UP2
  $00,   // 1
  $01,   // 2
  $01,   // 3
  $00,   // 4
  $01,   // 5
  $01,   // 6
  $00,   // 7
  $01,   // 8
  $01,   // 9
  0,   // A
  0,   // b
  0,   // c
  0,   // d
  0,   // E
  0    // F
  ),(
  $62,   // 0 UP 1
  $02,   // 1
  $61,   // 2
  $43,   // 3
  $03,   // 4
  $43,   // 5
  $63,   // 6
  $02,   // 7
  $63,   // 8
  $43,   // 9
  0,   // A
  0,   // b
  0,   // c
  0,   // d
  0,   // E
  0    // F
  ),(
  %00111111,   // 0 NORMAL
  %00000110,   // 1
  %01011011,   // 2
  %01001111,   // 3
  %01100110,   // 4
  %01101101,   // 5
  %01111101,   // 6
  %00000111,   // 7
  %01111111,   // 8
  %01101111,   // 9
  %01110111,   // A
  %01111100,   // b
  %01011000,   // c
  %01011110,   // d
  %01111001,   // E
  %01110001    // F
  ),(
  $54,   // 0 DOWN 1
  $04,   // 1
  $4C,   // 2
  $4C,   // 3
  $1C,   // 4
  $58,   // 5
  $58,   // 6
  $44,   // 7
  $5C,   // 8
  $5C,   // 9
  0,   // A
  0,   // b
  0,   // c
  0,   // d
  0,   // E
  0    // F
  ),(
  $08,   // 0 DOWN 2
  $00,   // 1
  $08,   // 2
  $08,   // 3
  $00,   // 4
  $08,   // 5
  $08,   // 6
  $08,   // 7
  $08,   // 8
  $08,   // 9
  0,   // A
  0,   // b
  0,   // c
  0,   // d
  0,   // E
  0    // F
  ));

  DayOfWeekArr: Array[0..6] of String[9] = (
  'Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday');

//erstellt mit https://jasonacox.github.io/TM1637TinyDisplay/examples/7-segment-animator.html
{$IFDEF STARTUP_ANIM}
  StartupAnimationArr2: Array[0..11, 0..3] of Byte = (
  ( $08, $00, $00, $00 ),  // Frame 0
  ( $00, $08, $00, $00 ),  // Frame 1
  ( $00, $00, $08, $00 ),  // Frame 2
  ( $00, $00, $00, $08 ),  // Frame 3
  ( $00, $00, $00, $04 ),  // Frame 4
  ( $00, $00, $00, $02 ),  // Frame 5
  ( $00, $00, $00, $01 ),  // Frame 6
  ( $00, $00, $01, $00 ),  // Frame 7
  ( $00, $01, $00, $00 ),  // Frame 8
  ( $01, $00, $00, $00 ),  // Frame 9
  ( $20, $00, $00, $00 ),  // Frame 10
  ( $10, $00, $00, $00 ));  // Frame 11
{$ENDIF}

type
  // Quelle einer Parameter-Änderung
  t_displaymode = (t_clock, t_clockstatic, t_second, t_alarm, t_alarm_msg, t_deggtimer, t_ddate, t_float, t_int, t_celsius);
  t_devicemode = (t_clock_0, t_clock_1, t_clock_2, t_serdisp, t_temp, t_waitdcf);
  t_clockstate = (t_normal, t_date, t_eggtimer, t_alarmtime, t_setalarmhour, t_setalarmminute,
                 t_sethour, t_setminute, t_setday, t_setmonth,
                 t_seteggminute, t_seteggsecond, t_eggalarm,
                 t_wakeupalarm, t_editend);

var
{$EEPROM}
  EE_dummy1       : word;
  EE_dummy2       : word;
  EE_InitFlag     : byte;
  EE_DeviceMode   : t_devicemode;
  EE_tfac, EE_toffs, EE_vfac : Integer;
  EE_Enables      : byte;
  EE_SnoozeMinutes: byte; // Snooze-Zeit in Minuten
  EE_AlarmSeconds: byte;  // Alarmdauer in Sekunden
  EE_SecondCorrect : Int8;

{$PDATA}
  SR_CLK[@PortB, 5]: Bit;
  SR_DATA[@PortB, 3]: Bit;
  SR_STRB[@PortD, 5]: Bit;
  BUZZER[@PortD, 7]: Bit;
  LED[@PortC, 3]: Bit;

  BTN_1[@PinD, 2]: Bit;
  BTN_2[@PinD, 3]: Bit;
  BTN_3[@PinB, 0]: Bit;
  BTN_4[@PinB, 1]: Bit;

  DCFPIN[@PinC, 0]: Bit;

{$DATA}
  i, n: byte;
  TickSema, Tick100sema, BlinkTicksema: Boolean;
{$IDATA}

  DisplayMsgTimer: SysTimer;
  
  aWord: Word;
  aInt: Integer;
  DeviceMode: t_devicemode;
  DisplayMode: t_displaymode;
  ClockState: t_clockstate;
  
// ################# 1. Platinenversion THT mit 4094 SR ########################
// SRsendWord+1                SRsendWord+0
//  7  6  5  4  3  2   1  0     7 6 5 4 3 2 1 0
// S1 S2 S3 S4 G5 G34 G2 G1 -- DP G F E D C B A
// ################# 2. Platinenversion SMD mit MAX6921AWI #####################
// SRsendWord+1                SRsendWord+0
//  7  6  5  4  3  2   1  0     7 6 5 4 3 2 1 0
// S1 S2 S3 S4 DP G5 G34 G2 -- G1 G F E D C B A
// #############################################################################
  SRsendWord: Word;
  SRsendWord_lo[@SRsendWord]: Byte;
  SRsendWord_hi[@SRsendWord + 1]: Byte;
// #############################################################################

  // Symbole      Ziffern (0=rechts)
  // S1 S2 S3 S4  0  0  0  0
  Symbols: Byte;
  // Symbole      Ziffern (0=rechts)  1 = Blinkt
  // S1 S2 S3 S4  Z3 Z2 Z1 Z0
  BlinkMask:  Byte;

  BlinkTimerValue:  Byte;

  BtnDebounceArr: Array[0..3] of Byte;
  BtnDebounce_1[@BtnDebounceArr + 0]: Byte;
  BtnDebounce_2[@BtnDebounceArr + 1]: Byte;
  BtnDebounce_3[@BtnDebounceArr + 2]: Byte;
  BtnDebounce_4[@BtnDebounceArr + 3]: Byte;

  BtnArr: Array[0..3] of Boolean;
  Btn1[@BtnArr + 0]: Boolean;
  Btn2[@BtnArr + 1]: Boolean;
  Btn3[@BtnArr + 2]: Boolean;
  Btn4[@BtnArr + 3]: Boolean;
  
  BtnSemaArr: Array[0..3] of Boolean;
  Btn1sema[@BtnSemaArr + 0]: Boolean;
  Btn2sema[@BtnSemaArr + 1]: Boolean;
  Btn3sema[@BtnSemaArr + 2]: Boolean;
  Btn4sema[@BtnSemaArr + 3]: Boolean;

  AnyBtn, b: Boolean;
  BtnTimer: Systimer;
  BtnLastPressed, BtnAutorepeatTime: Word;
  BtnAutorepeatCount: byte;
  
  DigitCount,
  Tick100count, BlinkTickcount:  Byte;

  RTCtoDS1307done, BlinkToggle, FastBlinkToggle,
  SecondCorrectSema,
  SecondSema, MinuteSema, HourSema, SyncDS1307done, DCFpresent: Boolean;
  SecondCounter: Byte;
  hour, minute, second: Byte;
  weekday, day, month, year: Byte;
  PreviousHour, PreviousMinute: Byte;
  Temperature, Voltage: Integer;
  LM75_present, DS1307_present,
  ClockTickEnable: Boolean;
  BuzzTick: Boolean;

  CurrentAlarmMinute, CurrentAlarmHour,
  CurrentAlarmTimeout, CurrentAlarmPause: Byte;
  CurrentAlarmTriggered: Boolean;
  CurrentAlarm: Byte;
  AlarmTimeReached, AlarmTimeReached_old: Boolean;
  HourAnimationDue: Boolean;
  HourAnimationEnable, MinuteAnimationEnable: Boolean;

  EggtimerMinute, EggTimerSecond: Byte;
  EggTimerRunning, EggTimerInterrupted, EggtimerElapsed: Boolean;

  AlarmMinutes: Array[0..3] of Byte; // 4 Alarmzeiten, 0 nicht benutzt
  AlarmHours: Array[0..3] of Byte;
  AlarmsTriggered: Array[0..3] of Boolean; // Alarm ausgelöst
  AlarmsPaused: Array[0..3] of Byte;       // Alarm pausiert
  AlarmsTimeout: Array[0..3] of Byte;      // Alarm automatisch abschalten

  SerInpStr: String[15];
  aStr: String[7];
  SegmentsArr, TempArr: Array[0..3] of Byte;


//##############################################################################

procedure onSysTick;
begin
  if BuzzTick and ClockTickEnable then
    BuzzTick:= false;
    BUZZER:= true;
    udelay(4);
    BUZZER:= false;
    BlinkTickcount:= 0;
  endif;
  
  if not inctolim(BlinkTickcount, BlinkTimerValue) then      // 0,5s bei 2ms SysTick
    BlinkTickcount:= 0;
    BlinkToggle:= not BlinkToggle;
    BlinkTicksema:= true;
    if ClockTickEnable then
      BUZZER:= true;
      if BlinkToggle then
       udelay(3);
      else
       udelay(2);
      endif;
      BUZZER:= false;
    endif;
  endif;

  if not inctolim(Tick100count, 75) then
    FastBlinkToggle:= not FastBlinkToggle;
    Tick100count:= 0;
    Tick100sema:= true;
  endif;

  AnyBtn:= false;
{$IFDEF SENSOR_BTN}
  if BTN_1 then  // pos. Logik!
    if not inctolim(BtnDebounce_1, 15) then
      Btn1sema:= true;
      Btn1:= true;
      AnyBtn:= true;
    endif;
  else
    if not dectolim(BtnDebounce_1, 0) then
      Btn1:= false;
    endif;
  endif;
  if BTN_2 then  // pos. Logik!
    if not inctolim(BtnDebounce_2, 15) then
      Btn2sema:= true;
      Btn2:= true;
      AnyBtn:= true;
    endif;
  else
    if not dectolim(BtnDebounce_2, 0) then
      Btn2:= false;
    endif;
  endif;
  if BTN_3 then  // pos. Logik!
    if not inctolim(BtnDebounce_3, 15) then
      Btn3sema:= true;
      Btn3:= true;
      AnyBtn:= true;
    endif;
  else
    if not dectolim(BtnDebounce_3, 0) then
      Btn3:= false;
    endif;
  endif;
  if BTN_4 then  // pos. Logik!
    if not inctolim(BtnDebounce_4, 15) then
      Btn4sema:= true;
      Btn4:= true;
      AnyBtn:= true;
    endif;
  else
    if not dectolim(BtnDebounce_4, 0) then
      Btn4:= false;
    endif;
  endif;
{$ELSE}
  if BTN_1 then  // neg. Logik!
    if not dectolim(BtnDebounce_1, 0) then
      Btn1:= false;
    endif;
  else
    if not inctolim(BtnDebounce_1, 15) then
      Btn1sema:= true;
      Btn1:= true;
      AnyBtn:= true;
    endif;
  endif;
  if BTN_2 then  // neg. Logik!
    if not dectolim(BtnDebounce_2, 0) then
      Btn2:= false;
    endif;
  else
    if not inctolim(BtnDebounce_2, 15) then
      Btn2sema:= true;
      Btn2:= true;
      AnyBtn:= true;
    endif;
  endif;
  if BTN_3 then  // neg. Logik!
    if not dectolim(BtnDebounce_3, 0) then
      Btn3:= false;
    endif;
  else
    if not inctolim(BtnDebounce_3, 15) then
      Btn3sema:= true;
      Btn3:= true;
      AnyBtn:= true;
    endif;
  endif;
  if BTN_4 then  // neg. Logik!
    if not dectolim(BtnDebounce_4, 0) then
      Btn4:= false;
    endif;
  else
    if not inctolim(BtnDebounce_4, 15) then
      Btn4sema:= true;
      Btn4:= true;
      AnyBtn:= true;
    endif;
  endif;
{$ENDIF}
  TickSema:= true;
end;

procedure RTCtickHour;
begin
  HourSema:= true;
end;

procedure RTCtickMinute;
begin
  MinuteSema:= true;
end;

procedure RTCtickSecond;
begin
  SecondSema:= true;
end;



//##############################################################################
{
  SR_CLK[@PortB,5]: Bit;
  SR_DATA[@PortB,3]: Bit;
  SR_STRB[@PortD,5]: Bit;

  BTN_1[@PinD, 2]: Bit;
  BTN_2[@PinD, 3]: Bit;
  BTN_3[@PinB, 0]: Bit;
  BTN_4[@PinB, 1]: Bit;

  DCFPIN[@PinC,0]: Bit;
}
procedure InitPorts;
begin
  SPCR:= %00011101;          // Disable SPI, Master, CPOL/CPHA=1,1 Mode 3
  SPSR:= %00000001;          // %00000001 = Double Rate, %00000000 = Normal Rate

  PortB:= %11000111; //
  DDRB:=  %00111000;

{$IFDEF DCF_IN}
  PortC:= %00001011; // C0 = DCF77 in oder Voltage, C1 = Temp-Sensor. C3 = LED
  DDRC:=  %00001000;
{$ELSE}
  ADMUX:= ADMUX or %11000000;
  PortC:= %00001010; // C0 = DCF77 in oder Voltage, C1 = Temp-Sensor. C3 = LED
  DDRC:=  %00001000;
{$ENDIF}

  PortD:= %00001110;
  DDRD:=  %10100010;
end InitPorts;

procedure Send_SPI_16;
//Sende und empfange ein Daten-Wort (16 Bit-Register) an den FPGA-Chip über SPI
// SRsendWord+1                SRsendWord+0
//  7  6  5  4  3  2   1  0     7 6 5 4 3 2 1 0
// S1 S2 S3 S4 G5 G34 G2 G1 -- DP G F E D C B A
// benötigt 10 µs
begin
  SR_CLK:= false;
  SPCR := %01111101;          // Enable SPI, LSB first, Master, CPOL/CPHA=1,1 Mode 3
  asm;
    lds  _ACCA, vfd_clock.SRsendWord+0
    out SPDR, _ACCA    ; SPI wurde von FAT16-Treiber eingeschaltet!
  SPIwait16_0:
    in _ACCA, SPSR
    sbrs _ACCA,7
    rjmp SPIwait16_0

    lds  _ACCA, vfd_clock.SRsendWord+1
    out SPDR, _ACCA
  SPIwait16_1:
    in _ACCA, SPSR
    sbrs _ACCA,7
    rjmp SPIwait16_1
  endasm;
  SPCR := %00111101;          // Disable SPI, Master, CPOL/CPHA=1,1 Mode 3
  SR_STRB:= true;
  nop; nop;
  nop; nop;
  SR_STRB:= false;
end;

{$IFDEF NEW_PCB}

// ################# 2. Platinenversion SMD mit MAX6921AWI #####################
// SRsendWord+1                SRsendWord+0
//  7  6  5  4  3  2   1  0     7 6 5 4 3 2 1 0
// S1 S2 S3 S4 DP G5 G34 G2 -- G1 G F E D C B A
// #############################################################################

// Symbole      Ziffern (0=rechts)
// S1 S2 S3 S4   0  0  0  0  - Symbols
// S1 S2 S3 S4  Z3 Z2 Z1 Z0 - BlinkMask, 1 = blinkt

procedure SendDigit(const my_display_mode: t_displaymode; const my_digit: byte);
var temp_symbols: Byte;
begin

  SRsendWord:= 0;
  if not (Bit(BlinkMask, my_digit) and BlinkToggle) then
    SRsendWord_lo:= SegmentsArr[my_digit] and $7F;  // normale Ziffer
  endif;
  Incl(SRsendWord, my_digit + 7);            // Grid-Bit setzen

  case my_digit of
  2:  // Grid 3+4, mit DP und Symbol 4
    case my_display_mode of
    t_clock :
      if BlinkToggle then
        SRsendWord_hi:= SRsendWord_hi or %00011000;  // DP und Symbol blinken
        // if RTCtoDS1307done then
        // endif;
      endif;
      |
    t_clockstatic, t_alarm:
        SRsendWord_hi:= SRsendWord_hi or %00011000;  // DP und Symbol an
      |
    t_ddate, t_float, t_celsius:
      Incl(SRsendWord_hi, 3);   // DP dauerhaft an
      |
    t_deggtimer:
      if BlinkToggle then
        Incl(SRsendWord_hi, 3);   // DP blinkt
      else
        Incl(SRsendWord_hi, 4);   // Symbol blinkt abwechselnd
      endif;
      |
    endcase;
    |
  3: // Linke Ziffer und kleine Ziffern-Symbole
    if FastBlinkToggle then
      temp_symbols:= Symbols xor (BlinkMask and $F0);
    else
      temp_symbols:= Symbols and $F0;
    endif;
    hi(SRsendWord):= hi(SRsendWord) or temp_symbols;
    |
  endcase;
  Send_SPI_16;
end;
// ############# Ende 2. Platinenversion TTH mit MAX6921AWI ####################

{$ELSE}

// ################# 1. Platinenversion THT mit 4094 SR ########################
// SRsendWord+1                SRsendWord+0
//  7  6  5  4  3  2   1  0     7 6 5 4 3 2 1 0
// S1 S2 S3 S4 G5 G34 G2 G1 -- DP G F E D C B A
// #############################################################################
// Korrektur auf Platine: Leiterbahn an Pin 17 VFD auftrennen
// und VFD Pin 17 mit VFD Pin 14 verbinden
// Pin 7 VFD mit Pin 13 U7 verbinden (oberes Sekunden-Symbol)

// SRsendWord+1                SRsendWord+0
//  7  6  5  4  3   2  1  0     7 6 5 4 3 2 1 0
// S1 S2 S3 G5 G34 S4 G2 G1 -- DP G F E D C B A
// G1 = rechte Ziffer, Sx = kleine Zahlen, S4 = auch Symbol über DP

// Symbole      Ziffern (0=rechts)
// S1 S2 S3  0   0  0  0  0  - Symbols
// S1 S2 S3 --  Z3 Z2 Z1 Z0 - BlinkMask, 1 = blinkt

procedure SendDigit(const my_display_mode: t_displaymode; const my_digit: byte);
var temp_symbols: Byte;
begin

  if Bit(BlinkMask, my_digit) and BlinkToggle then
    SRsendWord_lo:= 0;
  else
    SRsendWord_lo:= SegmentsArr[my_digit];  // normale Ziffer
  endif;
  hi(SRsendWord):= 0;
  case my_digit of
  0:
      Incl(SRsendWord, 8);            // Grid-Bit setzen
      |
  1:
      Incl(SRsendWord, 9);            // Grid-Bit setzen
      |
  2:  // Grid 3+4, mit DP und Symbol 4
    case my_display_mode of
    t_clock :
      if BlinkToggle then
        Incl(SRsendWord, 7);            // DP
        Incl(SRsendWord, 10);           // Symbol
        // if RTCtoDS1307done then
        // endif;
      endif;
      |
    t_clockstatic, t_alarm:
      Incl(SRsendWord, 7);            // DP dauerhaft an
      Incl(SRsendWord, 10);           // Symbol dauerhaft an
      |
    t_ddate, t_float, t_celsius:
      Incl(SRsendWord, 7);            // DP dauerhaft an
      |
    t_deggtimer:
      if BlinkToggle then
        Incl(SRsendWord, 7);          // DP und Symbol blinken abwechselnd
      else
        Incl(SRsendWord, 10);
      endif;
      |
    endcase;
    Incl(SRsendWord, 11);            // Grid-Bit setzen
    |
  3: // Linke Ziffer und kleine Ziffern-Symbole
    if BlinkToggle then
      temp_symbols:= Symbols xor (BlinkMask and $F0);
    else
      temp_symbols:= Symbols and $F0;
    endif;
    if Bit(temp_symbols, 4) then
      Incl(SRsendWord, 10);          // Symbol dauerhaft an
    endif;
    hi(SRsendWord):= hi(SRsendWord) or (temp_symbols and $E0);
    Incl(SRsendWord, 12);            // Grid-Bit setzen
    |
  endcase;
  Send_SPI_16;
end;
// ################# 1. Platinenversion THT mit 4094 SR ########################
{$ENDIF}


procedure SendNextDigitSimple_WaitSema;
// einfache Anzeige, ohne Symbole, für Animationen etc.
begin
  repeat until TickSema;
  TickSema:= false;
  SendDigit(t_int, DigitCount);
  inctolimWrap(DigitCount, 3, 0);
end;

procedure BCDtoDigits(const updown_shift, ls_digit, bcd_value: Byte);
// BCD-kodierter Wert 0_0..9_9 in Segment-Array
// ls_digit enthält Ziffern-Nummer, zählt von rechts aufwärts
begin
  SegmentsArr[ls_digit]:= c_DecodeArr[updown_shift, bcd_value and 15];
  SegmentsArr[ls_digit + 1]:= c_DecodeArr[updown_shift, bcd_value shr 4];
end;

procedure ByteToSingleDigit(const updown_shift, ls_digit, bin_value: Byte);
// Ziffer des Binärwerts 0..9 in Segment-Array
// ls_digit enthält Ziffern-Nummer, zählt von rechts aufwärts
// Gerade Ziffern erhalten Einer-, ungerade Zehner-Stelle
begin
  SegmentsArr[ls_digit]:= c_DecodeArr[updown_shift, ByteToBCD(bin_value) and 15];
end;

procedure ByteToDigits(const updown_shift, ls_digit, bin_value: Byte);
// Binärwert 0..99 in Segment-Array
// ls_digit enthält Ziffern-Nummer, zählt von rechts aufwärts
begin
  BCDtoDigits(updown_shift, ls_digit, ByteToBCD(bin_value));
end;

procedure IntToDigits(const bin_value: Integer);
// Binärwert 0..99 in Segment-Array, normale Darstellung
var my_bcd_word: Word;
begin
  if bin_value >= 0 then
    my_bcd_word:= WordToBCD(bin_value);
  else
    my_bcd_word:= WordToBCD(-bin_value);
  endif;
  BCDtoDigits(2, 0, lo(my_bcd_word));
  BCDtoDigits(2, 2, hi(my_bcd_word));
  if bin_value < 0 then
    SegmentsArr[3]:= %01000000;  // negativer Wert, Minuszeichen
  endif;
end;

procedure BlankDigits;
var my_digit: Byte;
begin
  for my_digit:= 0 to 3 do
    SegmentsArr[my_digit]:= 0;
  endfor;
  SRsendWord:= 0;
  Send_SPI_16;
end;

//##############################################################################

procedure MessageLoop(const msg_time: Word);
// einfache Anzeige, ohne Symbole, für Animationen etc.
begin
  SetSysTimer(DisplayMsgTimer, msg_time);
  repeat
    SendDigit(t_int, DigitCount);
    inctolimWrap(DigitCount, 3, 0);
    mdelay(2);
  until IsSysTimerZero(DisplayMsgTimer);
end;

procedure SetClockTickEnable;
begin
  i:= EE_Enables;
  if valueinrange(Hour, 8, 21) then
    ClockTickEnable:= Bit(i, 0);
  else
    ClockTickEnable:= false;
  endif;
  HourAnimationEnable:= Bit(i, 2);
  MinuteAnimationEnable:= Bit(i, 1);
end;

procedure SetupDefaultSymbols;
// Aktiven Alarm anzeigen, ggf. Snooze-Blink
begin
  Symbols:= 0;
  BlinkMask:= 0;
  if (CurrentAlarm < 4) then
    Incl(Symbols, 7-CurrentAlarm);
    if (CurrentAlarmPause > 0) then
      BlinkMask:= $F0;
    endif;
  endif;
end;

procedure SetupDateDigits;
begin
  ByteToDigits(2, 0, month);
  ByteToDigits(2, 2, day);       // Datum
  SetupDefaultSymbols;
  DisplayMode:= t_ddate;
end;

procedure SetupClockDigits(const updown_shift: Byte);
begin
  ByteToDigits(updown_shift, 0, minute);
  ByteToDigits(updown_shift, 2, hour);      // 00:00 anzeigen
  SetupDefaultSymbols;
  DisplayMode:= t_clock;
end;

procedure SetupAlarmDigits;
begin
  if CurrentAlarm < 4 then
    ByteToDigits(2, 0, alarmMinutes[CurrentAlarm]);
    ByteToDigits(2, 2, alarmHours[CurrentAlarm]);   // 00:00 anzeigen
    SetupDefaultSymbols;
    BlinkMask:= Symbols;
    DisplayMode:= t_alarm;
  else
    SegmentsArr[3]:= 0;    // "OFF" anzeigen
    SegmentsArr[2]:= $3f;
    SegmentsArr[1]:= $71;
    SegmentsArr[0]:= $71;
    Symbols:= 0;
    BlinkMask:= 0;
    DisplayMode:= t_alarm_msg;
  endif;
  SetSysTimer(DisplayMsgTimer, 500);
end;

procedure SetupEggStartDigits;
begin
  SegmentsArr[3]:= 0;    // "EGG" anzeigen
  SegmentsArr[2]:= $79;
  SegmentsArr[1]:= $3D;
  SegmentsArr[0]:= $3D;
  Symbols:= 0;
  BlinkMask:= 0;
  MessageLoop(200); // 0,5 Sek.
end;

{$IFDEF DCF_IN}
procedure SetupDCFsyncDigits(const dcf_ready: Boolean; const displ_time: Word);
begin
  if dcf_ready then
    SegmentsArr[3]:= 0;    // "dcF" anzeigen
  else
    SegmentsArr[3]:= $54;    // "ndcF" anzeigen
  endif;
  SegmentsArr[2]:= $5E;
  SegmentsArr[1]:= $58;
  SegmentsArr[0]:= $71;
  Symbols:= 0;
  BlinkMask:= 0;
  MessageLoop(displ_time); // 0,5 Sek.
end;
{$ENDIF}

procedure SetupEndDigits;
begin
  SegmentsArr[3]:= 0;    // "End" anzeigen
  SegmentsArr[2]:= $5E;
  SegmentsArr[1]:= $58;
  SegmentsArr[0]:= $71;
  Symbols:= 0;
  BlinkMask:= 0;
  MessageLoop(750); // 1,5 Sek.
end;

procedure SetUpDigits;
begin
  BlinkTimerValue:= 250;
  if IsSysTimerZero(DisplayMsgTimer) then
    case ClockState of
    t_normal:
      case DeviceMode of
      t_clock_0:
        SetClockTickEnable;
        SetupClockDigits(2);
        |
      t_clock_1:
        SetClockTickEnable;
        if SecondCounter > 7 then
          SetupDateDigits;
        else
          SetupClockDigits(2);
        endif;
        |
      t_clock_2:
        SetClockTickEnable;
        if SecondCounter > 8 then
          IntToDigits(Temperature);
          SetupDefaultSymbols;
          SegmentsArr[0]:= $63;
          DisplayMode:= t_celsius;
        elsif SecondCounter > 7 then
          SetupDateDigits;
        else
          SetupClockDigits(2);
        endif;
        |
      t_temp:
        DisplayMode:= t_celsius;
        IntToDigits(Temperature);
        ClockTickEnable:= false;
        HourAnimationEnable:= false;
        MinuteAnimationEnable:= false;
        |
      endcase;
      |
    t_setminute, t_sethour:
      SetupClockDigits(2);
      DisplayMode:= t_clockstatic;
      Symbols:= 0;
      BlinkMask:= 0;
      ClockTickEnable:= false;
      |
    t_date:
      SetupDateDigits;
      ClockTickEnable:= false;
      |
    t_setday, t_setmonth:
      SetupDateDigits;
      Symbols:= 0;
      BlinkMask:= 0;
      ClockTickEnable:= false;
      |
    t_alarmtime, t_setalarmhour, t_setalarmminute, t_wakeupalarm:
      SetupAlarmDigits;
      DisplayMode:= t_clockstatic;
      ClockTickEnable:= false;
      |
    t_seteggminute, t_seteggsecond, t_eggalarm, t_eggtimer:
      Symbols:= 0;
      BlinkMask:= 0;
      ByteToDigits(2, 0, EggtimerSecond);
      ByteToDigits(2, 2, EggtimerMinute);      // 00:00 anzeigen
      DisplayMode:= t_deggtimer;
      BlinkTimerValue:= 125;
      ClockTickEnable:= true;
      |
    endcase;
  endif;
end;


{$IFDEF STARTUP_ANIM}
procedure StartupAnimation;
var my_step, my_digit: Byte;
begin
  Tick100count:= 0;
  for my_step:= 0 to 11 do
    for i:= 0 to 3 do
      SegmentsArr[3-i]:= StartupAnimationArr2[my_step, i];
    endfor;
    repeat
      SendNextDigitSimple_WaitSema;
    until Tick100sema;
    Tick100sema:= false;
  endfor;
end;
{$ENDIF}

procedure MinuteAnimation;
var my_step, my_digit, my_loop, my_mask, my_shift, my_loopdigit: Byte;
  my_repeat: Byte;
begin
  SetupDefaultSymbols;
  ByteToDigits(2, 0, PreviousMinute);
  ByteToDigits(2, 2, PreviousHour);      // vorherige Zeit
  for my_digit:= 3 downto 0 do

    for my_repeat:= 0 to 1 do
      my_mask:= %00000001;
      for my_step:= 0 to 5 do
        SegmentsArr[my_digit]:= my_mask;
        for my_loop:= 0 to 15 do
          if AnyBtn or serstat then
            return;
          endif;
          my_loopdigit:= my_loop mod 4;
          SendDigit(t_int, my_loopdigit);
          mdelay(1);
          if my_loopdigit = my_digit then // hellere aktive Ziffer
            mdelay(7);
          endif;
        endfor;
        my_mask:= my_mask shl 1;
      endfor;
    endfor;
    
    case my_digit of
    0:
      ByteToSingleDigit(2, my_digit, Minute mod 10);
      |
    1:
      ByteToSingleDigit(2, my_digit, Minute div 10);
      |
    2:
      ByteToSingleDigit(2, my_digit, Hour mod 10);
      |
    3:
      ByteToSingleDigit(2, my_digit, Hour div 10);
      |
    endcase;
    
    for my_loop:= 0 to 31 do
      if AnyBtn or serstat then
        return;
      endif;
      my_loopdigit:= my_loop mod 4;
      SendDigit(t_int, my_loopdigit);
      mdelay(1);
      if my_loopdigit = my_digit then   // hellere aktive Ziffer
        mdelay(7);
      endif;
    endfor;
  endfor;
end;

procedure HourAnimation;
var my_timer_val, my_digit, my_loop, my_timer,
  my_shift, my_hilightdigit, my_timer_inc: Byte;
  shift_hour_1, shift_hour_10, shift_minute_1, shift_minute_10: Byte;
  dest_hour_1, dest_hour_10, dest_minute_1, dest_minute_10: Byte;
  next_digit_sema: Boolean;
begin
  SetupDefaultSymbols;
  ByteToDigits(2, 0, PreviousMinute);
  ByteToDigits(2, 2, PreviousHour);      // vorherige Zeit

  dest_hour_10:= Hour div 10;
  shift_hour_10:= dest_hour_10 + 1;

  dest_hour_1:= Hour mod 10;
  shift_hour_1:= dest_hour_1 + 1;

  dest_minute_10:= Minute div 10;
  shift_minute_10:= dest_minute_10 + 1;
  
  dest_minute_1:= Minute mod 10;
  shift_minute_1:= dest_minute_1 + 1;

  my_timer:= 0;
  my_shift:= 2; // normale Darstellung
  my_hilightdigit:= 3;
  my_digit:= 0;
  next_digit_sema:= false;
  my_timer_val:= 2;
  my_timer_inc:= 0;
  repeat           // Display-Refresh
    SendDigit(t_int, my_digit);
    mdelay(1);
    if AnyBtn then
      return;
    endif;
    if my_digit = my_hilightdigit then // hellere aktive Ziffer
      mdelay(7);
      if not inctolim(my_timer, my_timer_val) then
        my_timer:= 0;
        case my_digit of
        0:
          ByteToSingleDigit(my_shift, my_digit, shift_minute_1);
          if my_shift = 4 then   // letzter Shift nach unten, Ziffer wechseln
            BuzzTick:= true;
            inctolimwrap(shift_minute_1, 9, 0);
          elsif my_shift = 2 then   // Normalposition ist dargestellt
            if shift_minute_1 = dest_minute_1 then
              next_digit_sema:= true;
            endif;
          endif;
          |
        1:
          ByteToSingleDigit(my_shift, my_digit, shift_minute_10);
          if my_shift = 2 then
            if shift_minute_10 = dest_minute_10 then
              next_digit_sema:= true;
            endif;
          elsif my_shift = 4 then
            BuzzTick:= true;
            inctolimwrap(shift_minute_10, 9, 0);
          endif;
          |
        2:
          ByteToSingleDigit(my_shift, my_digit, shift_hour_1);
          if my_shift = 2 then
            if shift_hour_1 = dest_hour_1 then
              next_digit_sema:= true;
            endif;
          elsif my_shift = 4 then // letzter Shift nach unten, Ziffer wechseln
            BuzzTick:= true;
            inctolimwrap(shift_hour_1, 9, 0);
          endif;
          |
        3:
          ByteToSingleDigit(my_shift, my_digit, shift_hour_10);
          if my_shift = 2 then
            if shift_hour_10 = dest_hour_10 then
              next_digit_sema:= true;
            endif;
          elsif my_shift = 4 then // letzter Shift nach unten, Ziffer wechseln
            BuzzTick:= true;
            inctolimwrap(shift_hour_10, 9, 0);
          endif;
          |
        endcase;
        if (my_shift = 4) then // nach 5 kompletten Ziffern langsamer werden
          inc(my_timer_inc);
          if my_timer_inc > 4 then
            inc(my_timer_val);
          endif;
          if my_timer_inc > 7 then
            inc(my_timer_val, 3);
          endif;
        endif;
        inctolimwrap(my_shift, 4, 0);
      endif;
    endif;
    if next_digit_sema then
      next_digit_sema:= false;
      my_shift:= 2; // Ziffern-Grundstellung
      for my_loop:= 0 to 100 do
        SendDigit(t_int, my_digit);
        mdelay(1);
        if my_digit = my_hilightdigit then // hellere aktive Ziffer
          mdelay(7);
        endif;
        inctolimwrap(my_digit, 3, 0);
      endfor;
      dec(my_hilightdigit);  // fertig, nächste Ziffer
      my_timer_val:= 2;
      my_timer_inc:= 0;
    endif;
    inctolimwrap(my_digit, 3, 0);
  until (my_hilightdigit = 255) or serstat or AnyBtn;  // Überlauf
end;

procedure DisplayAll;
begin    // Display-Ziffern anzeigen
  if TickSema then
    TickSema:= false;
    if ClockState in [t_setalarmminute, t_setminute, t_setmonth, t_seteggsecond] then
      // rechte zwei Ziffern heller
      SendDigit(DisplayMode, 0);
      mdelay(8);
      SendDigit(DisplayMode, 1);
      mdelay(8);
      SendDigit(DisplayMode, 2);
      mdelay(1);
      SendDigit(DisplayMode, 3);
      mdelay(1);
    elsif ClockState in [t_setalarmhour, t_sethour, t_setday, t_seteggminute] then
      // linke zwei Ziffern heller
      SendDigit(DisplayMode, 0);
      mdelay(1);
      SendDigit(DisplayMode, 1);
      mdelay(1);
      SendDigit(DisplayMode, 2);
      mdelay(8);
      SendDigit(DisplayMode, 3);
      mdelay(8);
    else
      SendDigit(DisplayMode, DigitCount);
      inctolimWrap(DigitCount, 3, 0);
    endif;
  endif;
end;

function WaitBtnRelease(const btn_timeout: Word): boolean;
// wartet btn_timeout * 2 ms bis Taste(n) losgelassen,
// liefert TRUE wenn timeout erreicht
begin    // Display-Ziffern anzeigen
  SetSysTimer(BtnTimer, btn_timeout);
  repeat
    DisplayAll;
  until (not AnyBtn) or (isSysTimerzero(BtnTimer));
  if AnyBtn then
    if CurrentAlarmTriggered then
      BlankDigits;
      BeepOut(880, 25);
      BeepOut(659, 50);
      BeepOut(880, 25);
    endif;
    return(true);
  else
    return(false);
  endif;
end;

//##############################################################################

procedure SetLM75Temp(const my_temp: Integer);
// LM75 Alarm-Schalt-Temperatur °C * 100 in Param my_temp (2000 = 20 °C)
var my_int: Integer;
begin
  if LM75_present then
   TWIout(lm75_adr, 1, 4); // Optionsregister invertierter Ausgang

   my_int:= my_temp div 50;
   my_int:= swap(my_int shl 7);
   TWIout(lm75_adr, 3, my_int);  // Tos-Register wählen

   my_int:= (my_temp div 5) - 6; // Hysteresis 3°C
   my_int:= swap(my_int shl 7);
   TWIout(lm75_adr, 2, my_int);  // Thyst-Register wählen
   TWIout(lm75_adr, 0);
  endif;
end;

function GetLM75Temp: Integer;
// liefert LM75 Ist-Temperatur in °C * 100  (2000 = 20 °C)
var my_int: Integer;
begin
  if LM75_present then
    TWIout(lm75_adr, 0);
    TWIinp(lm75_adr, my_int);
    my_int:= swap(my_int) shr 7;
    return (my_int * 50);
  else
    return(0);
  endif;
end;

//##############################################################################

procedure DS1307writeRAM(ram_addr, data: byte);
begin
  if DS1307_present then
    ram_addr:= ram_addr + 8;
    TWIout(rtc_adr, ram_addr, data); // RAM-Register
  endif;
end;

function DS1307readRAM(ram_addr: Byte): byte;
var my_byte: byte;
begin
  if DS1307_present then
    ram_addr:= ram_addr + 8;
    TWIout(rtc_adr, ram_addr); // RAM-Register
    TWIinp(rtc_adr, my_byte);
    return(my_byte);
  else
    return(0);
  endif;
end;

procedure GetDS1307time;
var my_bcd: Byte;
begin
  if DS1307_present then
    TWIout(rtc_adr,0); // Sekunden-Register
    TWIinp(rtc_adr, my_bcd);
    second:= BCDtoByte(my_bcd);
    TWIout(rtc_adr,1); // Minuten-Register
    TWIinp(rtc_adr, my_bcd);
    minute:= BCDtoByte(my_bcd);
    TWIout(rtc_adr,2); // Stunden-Register
    TWIinp(rtc_adr, my_bcd);
    hour:= BCDtoByte(my_bcd);
  endif;
end;

procedure SetDS1307time;
var my_bcd: Byte;
begin
  if DS1307_present then
    my_bcd:= ByteToBCD(second) and $7F; // Clock HALT Bit immer löschen
    TWIout(rtc_adr, 0, my_bcd); // Sekunden-Register
    my_bcd:= ByteToBCD(Minute);
    TWIout(rtc_adr, 1, my_bcd); // Minuten-Register
    my_bcd:= ByteToBCD(hour) and $3F;
    TWIout(rtc_adr, 2, my_bcd); // Stunden-Register
  endif;
end;

procedure SetDS1307date;
var my_bcd: Byte;
begin
  if DS1307_present then
    TWIout(rtc_adr, 3, weekday);
    my_bcd:= ByteToBCD(day);
    TWIout(rtc_adr, 4, my_bcd);
    my_bcd:= ByteToBCD(month);
    TWIout(rtc_adr, 5, my_bcd);
    my_bcd:= ByteToBCD(year);
    TWIout(rtc_adr, 6, my_bcd);
  endif;
end;

procedure GetDS1307date;
var my_bcd: Byte;
begin
  if DS1307_present then
    TWIout(rtc_adr, 3); // Wochentags-Register
    TWIinp(rtc_adr, weekday);
    TWIout(rtc_adr, 4); // Datums-Register, BCD
    TWIinp(rtc_adr, my_bcd);
    day:= BCDtoByte(my_bcd);
    TWIout(rtc_adr, 5);
    TWIinp(rtc_adr, my_bcd);
    month:= BCDtoByte(my_bcd);
    TWIout(rtc_adr, 6);
    TWIinp(rtc_adr, my_bcd);
    year:= BCDtoByte(my_bcd);
  endif;
end;

procedure SetRTCtime;
begin
  DisableInts;
  RTCsetSecond(second);
  RTCsetMinute(minute);
  RTCsetHour(hour);
  EnableInts;
end;

procedure SetRTCdate;
begin
  DisableInts;
  RTCsetWeekday(weekday);  // 0 = Sonntag
  RTCsetDay(day);
  RTCsetMonth(month);
  RTCsetYear(year);
  EnableInts;
end;

procedure GetRTCtime;
begin
  second:= RTCgetSecond;
  minute:= RTCgetMinute;
  hour:= RTCgetHour;
end;

procedure GetRTCdate;
begin
  weekday:= RTCgetWeekday;
  day:= RTCgetDay;
  month:= RTCgetMonth;
  year:= RTCgetYear;
end;

procedure GetDS1307alarms;
begin
  for i:= 0 to 3 do
    AlarmHours[i]:= DS1307readRAM(i);
    AlarmMinutes[i]:= DS1307readRAM(i + 4);
  endfor;
  CurrentAlarm:= DS1307readRAM(10);
end;

procedure SetDS1307alarms;
begin
  for i:= 0 to 3 do
    DS1307writeRAM(i, alarmHours[i]);
    DS1307writeRAM(i + 4, alarmMinutes[i]);
  endfor;
  DS1307writeRAM(10, CurrentAlarm);
end;

//##############################################################################

procedure WriteTime(const my_hour, my_minute, my_second: Byte);
begin
  if my_hour < 10 then
    serout('0');
  endif;
  write(serout, ByteToStr(my_hour));
  serout(':');
  if my_minute < 10 then
    serout('0');
  endif;
  write(serout, ByteToStr(my_minute));
  serout(':');
  if my_second < 10 then
    serout('0');
  endif;
  write(serout, ByteToStr(my_second));
end;

procedure WriteDate(const my_day, my_month, my_year: Byte);
begin
  write(serout, ByteToStr(my_day));
  serout('.');
  write(serout, ByteToStr(my_month));
  serout('.');
  write(serout, ByteToStr(my_year));
end;

procedure WriteAlarm(const my_alarm: byte);
begin
  WriteTime(alarmHours[my_alarm], alarmMinutes[my_alarm], 0);
end;

//##############################################################################

procedure CancelAlarm(const my_alarm: Byte);
begin
  if AlarmsTriggered[my_alarm] then
    AlarmsPaused[my_alarm]:= 0;
    AlarmsTriggered[my_alarm]:= false;
    AlarmsTimeout[my_alarm]:= 0;
  endif;
  SetClockTickEnable;
end;

procedure PauseAlarm(const my_alarm: Byte);
begin
  if AlarmsTriggered[my_alarm] then
    AlarmsPaused[my_alarm]:= EE_SnoozeMinutes;
    AlarmsTimeout[my_alarm]:= EE_AlarmSeconds;
  endif;
  SetClockTickEnable;
end;

procedure SaveEggTimerVals;
begin
  DS1307writeRAM(16, EggTimerMinute);
  DS1307writeRAM(17, EggTimerSecond);
end;

procedure RestoreEggTimerVals;
begin
  EggTimerMinute:= DS1307readRAM(16);
  EggTimerSecond:= DS1307readRAM(17);
end;

//##############################################################################

procedure HelpText;
begin
  writeln(serout);
  writeln(serout, 'HX3 Time Engine 1.3');
  writeln(serout, 'Set values:');
  write(serout, 'Time:    t HH:MM:SS (');
  WriteTime(hour, minute, second);
  writeln(serout,')');
  write(serout, 'Date:    d DD.MM.YY (');
  WriteDate(day, month, year);
  writeln(serout,')');
  for i:= 0 to 3 do
    write(serout, 'Alarm:   ' + ByteToStr(i+1) + ' HH:MM    [');
    WriteAlarm(i);
    writeln(serout,')');
  endfor;
  write(serout, 'Weekday: w X (' + ByteToStr(weekday) + ') - ');
  writeln(serout, DayOfWeekArr[weekday]);
  writeln(serout, 'TempFac: f X (' + IntToStr(EE_tfac) + ')');
  writeln(serout, 'TempOfs: o X (' + IntToStr(EE_toffs) + ')');
  write(serout,   'Mode:    m X (' + ByteToStr(DeviceMode) + ') - ');
  case DeviceMode of
  t_clock_0:
    writeln(serout, 'Time only');
    |
  t_clock_1:
    writeln(serout, 'Time/Date altrn');
    |
  t_clock_2:
    writeln(serout, 'Time/Date/Temp altrn');
    |
  t_serdisp:
    writeln(serout, 'Serial Display');
    |
  t_temp:
    writeln(serout, 'Temperature');
    |
  endcase;
  i:= EE_Enables;
  write(serout, 'Enables: e X (' + ByteToStr(i) + ') - ');
  if Bit(i, 2) then
    write(serout, 'HourAnim ');
  endif;
  if Bit(i, 1) then
    write(serout, 'MinuteAnim ');
  endif;
  if Bit(i, 0) then
    write(serout, 'ClockTick ');
  endif;
  if i = 0 then
    write(serout, 'none');
  endif;
  writeln(serout);
  writeln(serout, 'Snooze Time:  s X (' + ByteToStr(EE_SnoozeMinutes) + ') - Minutes');
  writeln(serout, 'Alarm Length: b X (' + ByteToStr(EE_AlarmSeconds) + ') - Seconds');
  writeln(serout, 'Correction per day: c X (' + IntToStr(EE_SecondCorrect) + ') - Seconds');
end;

function ExtractNumber(var from_pos: Byte): Integer;
var
  my_char: Char;
begin
  aStr:='';
  for i:= from_pos to length(SerInpStr) do
    my_char:= SerInpStr[i];
    if my_char in ['-','+','0'..'9'] then
      append(my_char, aStr);
    else // Buchstabe oder sonstirgendwas, abbrechen
      break;
    endif;
  endfor;
  from_pos:= i + 1;
  return(StrToInt(aStr));
end;

procedure ParseSerInpStr;
// SerInpStr parsen
var
  str_ptr : byte;
  cmd_char: char;
  my_param, my_SubChOffset : integer;
begin
  if SerInpStr[2] = ' ' then
    str_ptr:= 3;
  else
    str_ptr:= 2;
  endif;
  cmd_char:= SerInpStr[1];
  case cmd_char of
  't':
    hour:= Byte(ExtractNumber(str_ptr));
    if str_ptr <= length(SerInpStr) then
      minute:= Byte(ExtractNumber(str_ptr));
    endif;
    if str_ptr <= length(SerInpStr) then
      second:= Byte(ExtractNumber(str_ptr));
    endif;
    SetDS1307time;
    SetRTCtime;
    |
  '1'..'4':
    n:= byte(cmd_char) - 49;
    AlarmHours[n]:= Byte(ExtractNumber(str_ptr));
    if str_ptr <= length(SerInpStr) then
      AlarmMinutes[n]:= Byte(ExtractNumber(str_ptr));
    endif;
    SetDS1307alarms;
    |
  'b':
    EE_AlarmSeconds:= Byte(ExtractNumber(str_ptr));
    |
  'c':
    EE_SecondCorrect:= Int8(ExtractNumber(str_ptr));
    |
  'd':
    day:= Byte(ExtractNumber(str_ptr));
    if str_ptr <= length(SerInpStr) then
      month:= Byte(ExtractNumber(str_ptr));
    endif;
    if str_ptr <= length(SerInpStr) then
      year:= Byte(ExtractNumber(str_ptr));
    endif;
    SetDS1307date;
    SetRTCdate;
    |
  'e':
    EE_Enables:= Byte(ExtractNumber(str_ptr));
    |
  'w':
    weekday:= Byte(ExtractNumber(str_ptr));
    SetDS1307date;
    SetRTCdate;
    |
  'm':
    DeviceMode:= t_devicemode(ExtractNumber(str_ptr));
    EE_DeviceMode:= DeviceMode;
    |
  'f':
    EE_tfac:= ExtractNumber(str_ptr);
    |
  'o':
    EE_toffs:= ExtractNumber(str_ptr);
    |
  'v':
    EE_vfac:= ExtractNumber(str_ptr);
    |
  'x':
    CancelAlarm(CurrentAlarm);
    |
  endcase;
  SerInpStr:='';
  PreviousHour:= hour;
  PreviousMinute:= minute;
  SetUpDigits;
  SetClockTickEnable;
  HelpText;
end;

procedure CheckSer;
var
  my_char : char;
begin
  if serStat then //
    my_char:= serInp;
    case my_char of
      #8:   // BS
        if (length(SerInpStr) > 0) then
          setlength(SerInpStr, length(SerInpStr) - 1);
        endif;
        |
      #13:  // CR
        if (length(SerInpStr) > 0) then
          ParseSerInpStr;  // Befehl vollständig, also interpretieren
        else
          HelpText;
        endif;
        while serstat do // evt. noch ein LF
          serInp;
        endwhile;
        SerInpStr:= '';
{$IFDEF DCF_IN}
        SetupDCFsyncDigits(DCFpresent, 1000);
{$ENDIF}
        |
    else
      if my_char in [#32..#122] then // nur 7-Bit-ASCII ohne Controls
        append(my_char, SerInpStr);
      endif;
    endcase;
  endif;
end;

//##############################################################################

procedure GetTemperature;
// holt Temperatur als Festkomma-Integer, 2000 = 20,0°C mit Integrator
begin
  if LM75_present then
    aInt:= GetLM75Temp;
    // Temp = (Messwert * ProzentFaktor / 100) + (Offset * 10) ohne Überlauf!
    aInt:= muldivInt(aInt, EE_tfac, 100) + (EE_toffs * 10);  // 2000 = 20,0°C
    Temperature:= muldivInt(Temperature, 9, 10) + (aInt div 10);  // Integrator
  else
    Temperature:= 0;
  endif;
end;


procedure SyncCurrentTime;
begin
  SetRTCtime;
  SetDS1307time;
end;

procedure SyncCurrentDate;
begin
  SetRTCdate;
  SetDS1307date;
end;


//##############################################################################
//############################# M A I N ########################################
//##############################################################################

begin
  InitPorts;
  BlankDigits;
  SerInpStr:='';
  EnableInts;
  BlinkTimerValue:= 250;
  ClockState:= t_normal;
  
  // Initialwerte
  if EE_InitFlag <> $A5 then
    EE_InitFlag:= $A5;
    EE_DeviceMode:= t_clock_0;
    EE_vfac:= 102;
    EE_tfac:= 100;
    EE_toffs:= 0;
    
    EE_Enables:= %00000000; // Click und Animations :%00000111
    EE_SnoozeMinutes:= 10;
    EE_AlarmSeconds:= 60;   // Beep-Dauer pro Alarm
    EE_SecondCorrect:= 0;   // Sekunden-Korrektur auf 24h
  endif;
  mdelay(100);
  LM75_present:= TWIstat(lm75_adr);
  DS1307_present:= TWIstat(rtc_adr);
  mdelay(100);
  DS1307_present:= DS1307_present or TWIstat(rtc_adr);
  DCFpresent:= false;
  if LM75_present then
    aInt:= GetLM75Temp;
    Temperature:= muldivInt(aInt, EE_tfac, 100) - (EE_toffs * 10);  // 2000 = 20,0°C
  endif;
  DeviceMode:= EE_DeviceMode;
  if DS1307_present and (DeviceMode < t_serdisp) and (DS1307readRAM(20) <> $A5) then
    day:= 1;
    month:= 1;
    year:= 20;
    SetDS1307time;  // Uhr auf 00:00 initialisieren, Alarm löschen
    SetDS1307date;  // Datum Montag, 1.1.20
    for i:= 0 to 19 do
      DS1307writeRAM(i, 0);
    endfor;
    DS1307writeRAM(20, $A5);
  endif;

  if DS1307_present and (DeviceMode < t_serdisp) then
    GetDS1307time;
    GetDS1307date;
    GetDS1307alarms;
    SetRTCtime;
    SetRTCdate;
  endif;
  SetClockTickEnable;

  HelpText;
  mdelay(100);
{$IFDEF STARTUP_ANIM}
  StartupAnimation;
{$ENDIF}

  BlankDigits;

{$IFDEF DCF_TEST}
  repeat
    if BlinkTicksema then
      writeln(serout, 'DCF field: ' + ByteToStr(DCFfield));
    endif;
    LED:= DCFPIN;
    BlinkTicksema:= false;
  until AnyBtn;
{$ENDIF}

  HourAnimation;
  loop
    CheckSer;


    if HourSema then
      HourSema:= false;
      PreviousHour:= Hour;
      if (not SyncDS1307done) and (hour = 0) then
        CancelAlarm(CurrentAlarm);
        GetDS1307time;
        GetDS1307date;
        SetRTCtime;
        SetRTCdate;
        SyncDS1307done:= true;
{$IFDEF DEBUG}
        writeln(serout, 'DS1307 sync to RTC');
{$ENDIF}
      endif;
      if (hour = 1) then
        SyncDS1307done:= false;
        SecondCorrectSema:= true; // Sekundenkorrektur anstehend
      endif;
      if HourAnimationEnable and (ClockState = t_normal) then
        HourAnimationDue:= true;
      endif;
      SetClockTickEnable;
    endif;

    if MinuteSema then
      MinuteSema:= false;
      PreviousMinute:= minute;
      GetRTCtime;
      GetRTCdate;
      
      if (CurrentAlarm < 4) then
        b:= (CurrentAlarmMinute = minute) and (CurrentAlarmHour = hour);
        AlarmTimeReached:= b and (not AlarmTimeReached_old);
        AlarmTimeReached_old:= AlarmTimeReached;
        if AlarmTimeReached then
          ClockState:= t_wakeupalarm;
        endif;
      else
        AlarmTimeReached:= false;
      endif;

      // bei Empfang Uhrenchip einmal auf DCF-Zeit setzen
{$IFDEF DCF_IN}
      if DCFready and (not RTCtoDS1307done) then
        SetDS1307time;
        SetDS1307date;
        DCFpresent:= true;
        RTCtoDS1307done:= true;
        writeln(serout, 'DCF sync to DS1307');
        SetupDCFsyncDigits(DCFpresent, 2000);
      endif;
{$ENDIF}

      if (DeviceMode < t_serdisp) then
        if ClockState = t_normal then
          if HourAnimationDue then
            HourAnimation;
          elsif MinuteAnimationEnable then
            MinuteAnimation;
          endif;
        endif;
        HourAnimationDue:= false;

        if (CurrentAlarm < 4) then
          if AlarmsTriggered[CurrentAlarm] then
            n:= AlarmsPaused[CurrentAlarm];
            dectolim(n, 0);
            AlarmsPaused[CurrentAlarm]:= n;
{$IFDEF DEBUG}
            writeln(serout, 'Alarm Snooze Timer: ' + ByteToStr(b));
{$ENDIF}
          endif;
        endif;
      endif;
    endif;

//------------------------------------------------------------------------------

    if SecondSema then
      SecondSema:= false;
      if SecondCorrectSema and (Second = 30) then
        SecondCorrectSema:= false;
        i:= Byte(EE_SecondCorrect);
        if i <> 0 then
{$IFDEF DEBUG}
          writeln(serout, 'Second before: ' + ByteToStr(Second));
{$ENDIF}
          Second:= Second + i;
          SetDS1307time;
          SetRTCtime;
{$IFDEF DEBUG}
          writeln(serout, 'Second after: ' + ByteToStr(Second));
{$ENDIF}
        endif;
      endif;
      inctolimwrap(SecondCounter, 9, 0);
      GetTemperature; // regelmäßig wg. Integrator
      
      // Alarm erreicht oder Snooze abgelaufen?
      GetRTCtime;
      if (CurrentAlarm < 4) then
        CurrentAlarmMinute:= AlarmMinutes[CurrentAlarm];
        CurrentAlarmHour:=   AlarmHours[CurrentAlarm];
        CurrentAlarmTimeout:= AlarmsTimeout[CurrentAlarm];
        CurrentAlarmPause:= AlarmsPaused[CurrentAlarm];
        CurrentAlarmTriggered:= AlarmsTriggered[CurrentAlarm];
      else
        CurrentAlarmMinute:= 0;
        CurrentAlarmHour:=   0;
        CurrentAlarmPause:= 0;
        CurrentAlarmTimeout:= 0;
        CurrentAlarmTriggered:= false;
      endif;

      if EggTimerRunning then
        ClockTickEnable:= true;  // Tick ON
        if not dectolim(EggTimerSecond, 0) then
          EggTimerSecond:= 59;
          BlankDigits;
          BeepOut(440, 10);
          if not dectolim(EggTimerMinute, 0) then
            EggTimerElapsed:= true;
            EggTimerRunning:= false;
            EggTimerSecond:= 0;
            ClockState:= t_eggalarm;
            SetClockTickEnable;
          endif;
        endif;
      endif;
      
      if AlarmTimeReached then
        AlarmTimeReached:= false;
{$IFDEF DEBUG}
        writeln(serout, 'Alarm Time Reached: ' + ByteToStr(CurrentAlarmTimeout));
{$ENDIF}
        CurrentAlarmTriggered:= true;
        AlarmsTriggered[CurrentAlarm]:= true;
        CurrentAlarmPause:= 0;
        AlarmsPaused[CurrentAlarm]:= 0;
        CurrentAlarmTimeout:= EE_AlarmSeconds;
        AlarmsTimeout[CurrentAlarm]:= CurrentAlarmTimeout; // Abschalten nach n Sekunden
      endif;

      // solange AlarmPaused > 0 ist, kein Beep
      if CurrentAlarmTriggered then
        if CurrentAlarmPause = 0 then // nur bestimmte Zeit klingeln lassen
          CurrentAlarmTimeout:= AlarmsTimeout[CurrentAlarm];
          dectolim(CurrentAlarmTimeout, 0);
          AlarmsTimeout[CurrentAlarm]:= CurrentAlarmTimeout;
          if CurrentAlarmTimeout = 0 then
            CancelAlarm(CurrentAlarm);
{$IFDEF DEBUG}
            writeln(serout, 'Alarm Beep Timeout');
{$ENDIF}
          else
            BlankDigits;
            BeepChirpH(4);
          endif;
        endif;
      endif;

      if EggtimerElapsed then
{$IFDEF DEBUG}
        writeln(serout, 'Egg Timer Elapsed ');
{$ENDIF}
        BlankDigits;
        BeepChirpL(4);
      endif;
      SetUpDigits;
    endif;

//------------------------------------------------------------------------------

    if Btn1sema then
      BtnAutorepeatCount:= 0;
      BtnAutorepeatTime:= 250;
      repeat
        case ClockState of
        t_normal:
          inctolimwrap(CurrentAlarm, 4, 0);
          SetDS1307alarms;
          DisplayMode:= t_clockstatic;
          SetUpAlarmDigits;
          SetSysTimer(DisplayMsgTimer, 750);    // 1,5 Sek.
          |
        t_sethour: // Stunden
          inctolimwrap(hour,23,0);
          SyncCurrentTime;
          SetUpDigits;
          |
        t_setminute: // Minuten
          inctolimwrap(minute,59,0);
          SyncCurrentTime;
          SetUpDigits;
          |
        t_setalarmhour: // Stunden
          n:= AlarmHours[CurrentAlarm];
          inctolimwrap(n,23,0);
          AlarmHours[CurrentAlarm]:= n;
          SetDS1307alarms;
          SetUpAlarmDigits;
          |
        t_setalarmminute: // Minuten
          n:= AlarmMinutes[CurrentAlarm];
          inctolimwrap(n,59,0);
          AlarmMinutes[CurrentAlarm]:= n;
          SetDS1307alarms;
          SetUpAlarmDigits;
          |
        t_setday: // Tag
          inctolimwrap(day,31,1);
          SyncCurrentDate;
          SetUpDigits;
          |
        t_setmonth: // Monat
          inctolimwrap(month,12,1);
          SyncCurrentDate;
          SetUpDigits;
          |
        t_seteggminute:
          inctolimwrap(EggTimerMinute,59, 0);
          SaveEggTimerVals;
          EggTimerInterrupted:= false;
          SetUpDigits;
          |
        t_seteggsecond:
          inctolimwrap(EggTimerSecond,59, 0);
          SaveEggTimerVals;
          EggTimerInterrupted:= false;
          SetUpDigits;
          |
        endcase;
        BeepOut(1320, 2);
        WaitBtnRelease(BtnAutorepeatTime);
        if not inctolim(BtnAutorepeatCount, 2) then
          BtnAutorepeatTime:= 75;
        endif;
      until not AnyBtn;
      Btn1sema:= false;
    endif;
      
    if Btn2sema then
      BtnAutorepeatCount:= 0;
      BtnAutorepeatTime:= 250;
      repeat
        case ClockState of
        t_normal:
          dectolimwrap(CurrentAlarm, 0, 4);
          SetDS1307alarms;
          DisplayMode:= t_clockstatic;
          SetUpAlarmDigits;
          SetSysTimer(DisplayMsgTimer, 750);    // 1,5 Sek.
          |
        t_sethour: // Stunden/Tag
          dectolimwrap(hour,0,23);
          SyncCurrentTime;
          SetUpDigits;
          |
        t_setminute: // Minuten/Monat
          dectolimwrap(minute,0,59);
          SyncCurrentTime;
          SetUpDigits;
          |
        t_setalarmhour: // Stunden
          n:= AlarmHours[CurrentAlarm];
          dectolimwrap(n,0,23);
          AlarmHours[CurrentAlarm]:= n;
          SetDS1307alarms;
          SetUpAlarmDigits;
          |
        t_setalarmminute: // Minuten
          n:= AlarmMinutes[CurrentAlarm];
          dectolimwrap(n,0,59);
          AlarmMinutes[CurrentAlarm]:= n;
          SetDS1307alarms;
          SetUpAlarmDigits;
          |
        t_setday: // Tag
          dectolimwrap(day,1,31);
          SyncCurrentDate;
          SetUpDigits;
          |
        t_setmonth: // Monat
          dectolimwrap(month,1,12);
          SyncCurrentDate;
          SetUpDigits;
          |
        t_seteggminute:
          dectolimwrap(EggTimerMinute, 0, 59);
          SaveEggTimerVals;
          EggTimerInterrupted:= false;
          SetUpDigits;
         |
        t_seteggsecond:
          dectolimwrap(EggTimerSecond, 0, 59);
          SaveEggTimerVals;
          EggTimerInterrupted:= false;
          SetUpDigits;
          SetUpDigits;
          |
        endcase;
        BeepOut(1320, 2);
        WaitBtnRelease(BtnAutorepeatTime);
        if not inctolim(BtnAutorepeatCount, 2) then
          BtnAutorepeatTime:= 75;
        endif;
      until not AnyBtn;
      Btn2sema:= false;
    endif;
    
    if Btn3sema then // Setting Mode
      EggtimerElapsed:= false;
      EggtimerRunning:= false;
      EggTimerInterrupted:= false;
      case ClockState of
      t_normal:
        if CurrentAlarm > 3 then  // OFF, Alarm überspringen
          ClockState:= t_sethour;
        else
          ClockState:= t_setalarmhour;
        endif;
        SetUpDigits;
        |
      t_setalarmhour:
        ClockState:= t_setalarmminute;
        SetUpDigits;
        |
      t_setalarmminute:
        ClockState:= t_sethour;
        SetUpDigits;
        |
      t_sethour:
        ClockState:= t_setminute;
        SetUpDigits;
        |
      t_setminute:
        ClockState:= t_setday;
        SetUpDigits;
        |
      t_setday:
        ClockState:= t_setmonth;
        SetUpDigits;
        |
      t_setmonth:
        BlankDigits;
        BeepOut(1320, 20);
        BeepOut(880, 20);
        BeepOut(1320, 20);
        ClockState:= t_normal;
{$IFDEF DCF_IN}
        SetupDCFsyncDigits(DCFpresent, 500); // kurz DCF-Status anzeigen und Ende
{$ENDIF}
        |
      else
        ClockState:= t_normal;
      endcase;
{$IFDEF DEBUG}
      writeln(serout, 'ClockState: ' + ByteToStr(byte(ClockState)));
{$ENDIF}
      BeepOut(1320, 2);
      WaitBtnRelease(1000);
      Btn3sema:= false;
    endif;

    if Btn4sema then  // Snooze/Cancel Alarm
      EggtimerElapsed:= false;
      BeepOut(1320, 2);
      if not CurrentAlarmTriggered then
        case ClockState of
        t_normal:
          DisplayMode:= t_clockstatic;
          if CurrentAlarm < 4 then
            SetUpAlarmDigits;
          else
            SetupEggStartDigits;
            if not EggTimerInterrupted then
              RestoreEggTimerVals;
            endif;
            ClockState:= t_seteggminute;
          endif;
          EggtimerRunning:= false;
          EggTimerInterrupted:= false;
          |
        t_seteggminute:
          ClockState:= t_seteggsecond;
          |
        t_seteggsecond:
          ClockState:= t_eggtimer;
          EggtimerRunning:= true;
          BlankDigits;
          BeepOut(880, 25);
          |
        t_eggtimer:
          EggTimerInterrupted:= EggtimerRunning;
          EggtimerRunning:= false;
          BlankDigits;
          BeepOut(1320, 20);
          BeepOut(880, 20);
          BeepOut(1320, 20);
          ClockState:= t_normal;
          |
        else
          EggtimerRunning:= false;
          BlankDigits;
          BeepOut(880, 25);
          ClockState:= t_normal;
       endcase;
       SetUpDigits;
      endif;
      b:= WaitBtnRelease(1000);


      if CurrentAlarmTriggered then
        SetUpAlarmDigits;
        if not b then // nur kurz gedrückt, kein Timeout
          PauseAlarm(CurrentAlarm);
{$IFDEF DEBUG}
          writeln(serout, 'Alarm Snooze: ' + ByteToStr(CurrentAlarm));
{$ENDIF}
          BlankDigits;
          BeepOut(880, 25);
         else
          CancelAlarm(CurrentAlarm);
{$IFDEF DEBUG}
          writeln(serout, 'Alarm Cancel: ' + ByteToStr(CurrentAlarm));
{$ENDIF}
        endif;
        ClockState:= t_normal;
      endif;
      
      if EggtimerRunning and EggtimerElapsed then
{$IFDEF DEBUG}
        writeln(serout, 'Egg Timer Canceled: ' + ByteToStr(CurrentAlarm));
{$ENDIF}
        BlankDigits;
        BeepOut(880, 25);
        ClockState:= t_normal;
        SetUpDigits;
        EggtimerRunning:= false;
        EggtimerElapsed:= false;
        EggTimerInterrupted:= false;
      endif;
      
      if b and ClockState in [t_seteggminute, t_seteggsecond, t_eggtimer] then
        BlankDigits;
        BeepChirpL(1);
        ClockState:= t_normal;
        SetUpDigits;
      endif;
      Btn4sema:= false;
    endif;

    DisplayAll; // Display-Ziffern anzeigen, muss regelmäßig aufgerufen werden
    if EggtimerRunning or CurrentAlarmTriggered then
      LED:= BlinkToggle;
    else
      LED:= DCFPIN;
    endif;

  endloop;
end vfd_clock.

