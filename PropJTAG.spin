{{
┌─────────────────────────────────────────────────┐
│ JTAG/IEEE 1149.1                                │
│ Interface Object                                │
│                                                 │
│ Author: Joe Grand                               │                     
│ Copyright (c) 2013-2016 Grand Idea Studio, Inc. │
│ Web: http://www.grandideastudio.com             │
│                                                 │
│ Distributed under a Creative Commons            │
│ Attribution 3.0 United States license           │
│ http://creativecommons.org/licenses/by/3.0/us/  │
└─────────────────────────────────────────────────┘

Program Description:

This object provides the low-level communication interface for JTAG/IEEE 1149.1
(http://en.wikipedia.org/wiki/Joint_Test_Action_Group). 

JTAG routines based on Intel Application Note AP-720: Programming Flash Memory
through the Intel386 EX Embedded Microprocessor JTAG Port (http://intel-vintage-
developer.eu5.org/DESIGN/INTARCH/APPLNOTS/27275301.PDF). 

Usage: Call Config first to properly set the desired JTAG pinout
 
}}


CON
{{ IEEE Std. 1149.1 2001
   TAP Signal Descriptions

   ┌───────────┬────────────────────────────────────────────────────────────────────────────────────────┐
   │    Name   │                                   Description                                          │
   ├───────────┼────────────────────────────────────────────────────────────────────────────────────────┤
   │    TDI    │    Test Data Input: Serial test instructions and data received by the test logic.      │
   ├───────────┼────────────────────────────────────────────────────────────────────────────────────────┤ 
   │    TDO    │    Test Data Output: Serial output for instructions and data from the test logic.      │
   ├───────────┼────────────────────────────────────────────────────────────────────────────────────────┤
   │           │    Test Port Clock: Synchronous clock for the test logic that accompanies any data     │
   │    TCK    │    transfer. Data on input lines is sampled on the rising edge, data on the output     │
   │           │    line is sampled on the falling edge.                                                │
   ├───────────┼────────────────────────────────────────────────────────────────────────────────────────┤
   │    TMS    │    Test Mode Select: Used in conjunction with TDI to control the state machine and     │
   │           │    determine the state of the test logic.                                              │ 
   ├───────────┼────────────────────────────────────────────────────────────────────────────────────────┤
   │           │    Test Port Reset: Optional signal for asynchronous initialization of the test logic. │
   │    TRST#  │    Some targets intentionally hold TRST# low to keep JTAG disabled. If so, the pin     │
   │           │    will need to be located and pulled high. This object assumes TRST# assertion (if    │
   │           │    required) is done in advance by the top object.                                     │
   └───────────┴────────────────────────────────────────────────────────────────────────────────────────┘
 }}

 {{ IEEE Std. 1149.1 2001
    TAP Controller
 
    The movement of data through the TAP can be controlled by supplying the proper logic level to the
    TMS pin at the rising edge of consecutive TCK cycles. The TAP controller itself is a finite state
    machine that is capable of 16 states. Each state contains a link in the operation sequence necessary
    to manipulate the data moving through the TAP.
 }}


CON
  MAX_DEVICES_LEN      =  32       ' Maximum number of devices in the JTAG chain

  MIN_IR_LEN           =  2        ' Minimum length of instruction register per IEEE Std. 1149.1
  MAX_IR_LEN           =  32       ' Maximum length of instruction register
  MAX_IR_CHAIN_LEN     =  MAX_DEVICES_LEN * MAX_IR_LEN  ' Maximum total length of JTAG chain w/ IR selected
  
  MAX_DR_LEN           =  1024      ' Maximum length of data register

  
VAR
  long TDI, TDO, TCK, TMS       ' JTAG pins (must stay in this order)


OBJ
 

PUB Config(tdi_pin, tdo_pin, tck_pin, tms_pin)
{
  Set JTAG pins
  Parameters : TDI, TDO, TCK, TMS channels provided by top object
}
  longmove(@TDI, @tdi_pin, 4)   ' Move passed variables into globals for use in this object

  ' Set direction of JTAG pins
  ' Output
  dira[TDI] := 1                          
  dira[TCK] := 1          
  dira[TMS] := 1

  ' Input 
  dira[TDO] := 0


PUB Detect_Devices : num
{
  Performs a blind interrogation to determine how many devices are connected in the JTAG chain.

  In BYPASS mode, data shifted into TDI is received on TDO delayed by one clock cycle. We can
  force all devices into BYPASS mode, shift known data into TDI, and count how many clock
  cycles it takes for us to see it on TDO.

  Based on http://www.fpga4fun.com/JTAG3.html

  Returns    : Number of JTAG/IEEE 1149.1 devices in the chain (if any)
}
  Restore_Idle                ' Reset TAP to Run-Test-Idle 

  ' Force all devices in the chain (if they exist) into BYPASS mode using opcode of all 1s
  ' Modified version of Send_Instruction/Shift_Data_Array
  Enter_Shift_IR              ' Enter Shift IR state
  outa[TMS] := 0              ' TMS low (to remain in this state while shifting/sampling data)
  outa[TDI] := 1              ' Output data bit HIGH
  repeat MAX_IR_CHAIN_LEN - 1    ' Send lots of 1s to account for multiple devices in the chain and varying IR lengths
    TCK_Pulse

  TMS_High                    ' Go to Exit1
  TMS_High                    ' Go to Update IR, new data in effect
  TMS_Low                     ' Go to Run-Test-Idle
  Enter_Shift_DR              ' Go to Shift DR
                          
  repeat MAX_DEVICES_LEN      ' Send 1s to fill DRs of all devices in the chain (In BYPASS mode, DR length = 1 bit)
    TCK_Pulse 

  ' We are now in BYPASS mode with all DR set
  ' Send in a 0 on TDI and count until we see it on TDO
  outa[TDI] := 0              ' Output data bit LOW
  repeat num from 0 to MAX_DEVICES_LEN - 1 
    outa[TCK] := 1              ' TCK high (target samples TDI bit)
    if (ina[TDO] == 0)          ' If we have received our 0, it has propagated through the entire chain (one clock cycle per device in the chain)
      outa[TCK] := 0
      quit                        '  Exit function (num gets returned)
    outa[TCK] := 0

  if (num > MAX_DEVICES_LEN - 1)  ' If no 0 is received, then no devices are in the chain
    num := 0

  TMS_High                    ' Go to Exit1
  TMS_High                    ' Update DR, new data in effect
  TMS_Low                     ' Go to Run-Test-Idle                                                        


PUB Detect_IR_Length : num 
{
  Performs an interrogation to determine the instruction register length of the target device.
  Limited in length to MAX_IR_LEN.
  Assumes a single device in the JTAG chain.

  Returns    : Length of the instruction register
}
  Restore_Idle                ' Reset TAP to Run-Test-Idle
      
  ' Flush the IR
  ' Modified version of Send_Instruction/Shift_Data_Array
  Enter_Shift_IR              ' Enter Shift IR state
  outa[TMS] := 0              ' TMS low (to remain in this state while shifting/sampling data)
  outa[TDI] := 0              ' Output data bit LOW
  repeat MAX_IR_LEN - 1       ' Since the length is unknown, send lots of 0s
    TCK_Pulse

  ' Once we are sure that the IR is filled with 0s
  ' Send in a 1 on TDI and count until we see it on TDO
  outa[TDI] := 1              ' Output data bit HIGH
  repeat num from 0 to MAX_IR_LEN - 1 
    outa[TCK] := 1              ' TCK high (target samples TDI bit)
    if (ina[TDO] == 1)          ' If we have received our 1, it has propagated through the entire instruction register
       outa[TCK] := 0
      quit                        '  Exit function (num gets returned)
    outa[TCK] := 0

  if (num > MAX_IR_LEN - 1) or (num < MIN_IR_LEN)  ' If no 1 is received, then we are unable to determine IR length
    num := 0

  TMS_High                    ' Go to Exit1
  TMS_High                    ' Go to Update IR, new data in effect
  TMS_Low                     ' Go to Run-Test-Idle


PUB Detect_DR_Length(value) : num | len
{
  Performs an interrogation to determine the data register length of the target device.
  The selected data register will vary depending on the the instruction.
  Limited in length to MAX_DR_LEN.
  Assumes a single device in the JTAG chain.

  Parameters : value = Opcode/instruction to be sent to TAP
  Returns    : Length of the data register
}
  len := Detect_IR_Length          ' Determine length of TAP IR
  Send_Instruction(value, len)     ' Send instruction/opcode

  ' At this point, a specific DR will be selected, so we can now determine its length.
  Enter_Shift_DR              ' Go to Shift DR
  
  ' Flush the DR
  ' Modified version of Send_Instruction/Shift_Data_Array
  outa[TMS] := 0              ' TMS low (to remain in this state while shifting/sampling data)
  outa[TDI] := 0              ' Output data bit LOW
  repeat MAX_DR_LEN - 1       ' Since the length is unknown, send lots of 0s
    TCK_Pulse

  ' Once we are sure that the DR is filled with 0s
  ' Send in a 1 on TDI and count until we see it on TDO
  outa[TDI] := 1              ' Output data bit HIGH
  repeat num from 0 to MAX_DR_LEN - 1 
    outa[TCK] := 1              ' TCK high (target samples TDI bit)
    if (ina[TDO] == 1)          ' If we have received our 1, it has propagated through the entire data register
      outa[TCK] := 0
      quit                        '  Exit function (num gets returned)
    outa[TCK] := 0

  if (num > MAX_DR_LEN - 1)  ' If no 1 is received, then we are unable to determine DR length
    num := 0

  TMS_High                    ' Go to Exit1
  TMS_High                    ' Go to Update DR, new data in effect
  TMS_Low                     ' Go to Run-Test-Idle
     
  
PUB Bypass_Test(num, bPattern) : value
{
  Run a Bypass through every device in the chain. 

  Parameters : num = Number of devices in JTAG chain
               bPattern = 32-bit value to shift into TDI
  Returns    : 32-bit value received from TDO
}
  Restore_Idle                ' Reset TAP to Run-Test-Idle

  ' Force all devices in the chain (if they exist) into BYPASS mode using opcode of all 1s
  ' Modified version of Send_Instruction/Shift_Data_Array
  Enter_Shift_IR              ' Enter Shift IR state
  outa[TMS] := 0              ' TMS low (to remain in this state while shifting/sampling data)
  outa[TDI] := 1              ' Output data bit HIGH
  repeat (num * MAX_IR_LEN)   ' Send in 1s
    TCK_Pulse
     
  TMS_High                    ' Go to Exit1
  TMS_High                    ' Go to Update IR, new data in effect
  TMS_Low                     ' Go to Run-Test-Idle
  Enter_Shift_DR              ' Go to Shift DR

  repeat (32 + num)           ' Shift in the 32-bit pattern. Each device in the chain delays the data propagation by one clock cycle. 
    value <<= 1
    outa[TDI] := bPattern & 1   ' Output data bit
    outa[TCK] := 1              ' TCK high (target samples TDI bit)
    value |= ina[TDO]           ' Input data bit from target
    outa[TCK] := 0              ' TCK low 
    bPattern >>= 1

  value ><= 32                ' Bitwise reverse since LSB came in first (we want MSB to be first)

  TMS_High                    ' Go to Exit1
  TMS_High                    ' Update DR, new data in effect
  TMS_Low                     ' Go to Run-Test-Idle
    

PUB Get_Device_IDs(num, idptr) | data, i
{
  Retrieves the JTAG device ID from each device in the chain. 

  The Device Identification register (if it exists) should be immediately available
  in the DR after power-up of the target device or after TAP reset.

  Parameters : num = Number of devices in JTAG chain
               idptr = Pointer to memory in which to store the received 32-bit device IDs (must be large enough for all IDs) 
}
{{ IEEE Std. 1149.1 2001
   Device Identification Register

   MSB                                                                          LSB
   ┌───────────┬──────────────────────┬───────────────────────────┬──────────────┐
   │  Version  │      Part Number     │   Manufacturer Identity   │   Fixed (1)  │
   └───────────┴──────────────────────┴───────────────────────────┴──────────────┘
      31...28          27...12                  11...1                   0
}}
  Restore_Idle                ' Reset TAP to Run-Test-Idle

  ' Modified version of Send_Data/Shift_Data_Array
  Enter_Shift_DR                ' Go to Shift DR    

  outa[TMS] := 0                ' TMS low (to remain in this state while shifting/sampling data)
  outa[TDI] := 1                ' Output data bit HIGH (TDI is ignored when shifting IDCODE, but we need to set a default state)
  
  repeat i from 1 to (num << 5)   ' Repeat for (num * 32) bits
    data <<= 1 
    outa[TCK] := 1                  ' TCK high
    data |= ina[TDO]                ' Input data bit from target
    outa[TCK] := 0                  ' TCK low 
    if (i // 32 == 0)               ' If we've read a complete 32-bit value...
      data ><= 32                         ' Bitwise reverse since LSB came in first (we want MSB to be first)
      long[idptr][(i >> 5) - 1] := data   ' Store it in hub memory
      data := 0                           ' Clear buffer

  TMS_High                      ' Go to Exit1
  TMS_High                      ' Update DR, new data in effect
  TMS_Low                       ' Go to Run-Test-Idle


PUB Send_Instruction(value, bits) : data
{
    Sends a JTAG instruction into the TAP via TDI. Receives data that is shifted out on TDO (limited to 32 bits).
    TAP must be in Run-Test-Idle state before being called.
}
{{ IEEE Std. 1149.1 2001
   Instructions
   
   Instruction Register/Opcode length vary per device family
   IR length must >= 2

   ┌───────────┬─────────────┬──────────┬───────────────────────────────────────────────────────────────────────┐
   │    Name   │  Required?  │  Opcode  │                          Description                                  │
   ├───────────┼─────────────┼──────────┼───────────────────────────────────────────────────────────────────────┤
   │   BYPASS  │      Y      │  All 1s  │   Bypass on-chip system logic. Allows serial data to be transferred   │
   │           │             │          │   from TDI to TDO without affecting operation of the IC.              │
   ├───────────┼─────────────┼──────────┼───────────────────────────────────────────────────────────────────────┤
   │   SAMPRE  │      Y      │  Varies  │   Used for controlling (preload) or observing (sample) the signals at │
   │           │             │          │   device pins. Enables the boundary scan register.                    │
   ├───────────┼─────────────┼──────────┼───────────────────────────────────────────────────────────────────────┤
   │   EXTEST  │      Y      │  All 0s  │   Places the IC in external boundary test mode. Used to test device   │
   │           │             │          │   interconnections. Enables the boundary scan register.               │
   ├───────────┼─────────────┼──────────┼───────────────────────────────────────────────────────────────────────┤
   │   INTEST  │      N      │  Varies  │   Used for static testing of internal device logic in a single-step   │
   │           │             │          │   mode. Enables the boundary scan register.                           │
   ├───────────┼─────────────┼──────────┼───────────────────────────────────────────────────────────────────────┤
   │   RUNBIST │      N      │  Varies  │   Places the IC in a self-test mode and selects a user-specified data │
   │           │             │          │   register to be enabled.                                             │
   ├───────────┼─────────────┼──────────┼───────────────────────────────────────────────────────────────────────┤
   │   CLAMP   │      N      │  Varies  │   Sets the IC outputs to logic levels as defined in the boundary scan │
   │           │             │          │   register. Enables the bypass register.                              │
   ├───────────┼─────────────┼──────────┼───────────────────────────────────────────────────────────────────────┤
   │   HIGHZ   │      N      │  Varies  │   Sets all IC outputs to a disabled (high impedance) state. Enables   │
   │           │             │          │   the bypass register.                                                │
   ├───────────┼─────────────┼──────────┼───────────────────────────────────────────────────────────────────────┤
   │   IDCODE  │      N      │  Varies  │   Enables the 32-bit device identification register. Does not affect  │
   │           │             │          │   operation of the IC.                                                │
   ├───────────┼─────────────┼──────────┼───────────────────────────────────────────────────────────────────────┤
   │  USERCODE │      N      │  Varies  │   Places user-defined information into the 32-bit device              │
   │           │             │          │   identification register. Does not affect operation of the IC.       │
   └───────────┴─────────────┴──────────┴───────────────────────────────────────────────────────────────────────┘
}}
  Enter_Shift_IR

  data := Shift_Data_Array(value, bits)
                            
  TMS_High                    ' Go to Exit1
  TMS_High                    ' Update IR, new instruction in effect
  TMS_Low                     ' Go to Run-Test-Idle 


PUB Send_Data(value, bits) : data
{
    Sends a JTAG data into the TAP via TDI. Receives data that is shifted out on TDO.
    TAP must be in Run-Test-Idle state before being called.
}
  Enter_Shift_DR

  data := Shift_Data_Array(value, bits)

  TMS_High                    ' Go to Exit1
  TMS_High                    ' Update DR, new data in effect
  TMS_Low                     ' Go to Run-Test-Idle


PRI Shift_Data_Array(value, bits) : data 
{
    Shifts a data string into the TAP while reading data back out.
    This function is called when the TAP state machine is in the Shift_DR or Shift_IR state.
}
  outa[TMS] := 0              ' TMS low (to remain in this state while shifting/sampling data)
  
  repeat (bits)
    data <<= 1
    outa[TCK] := 1            ' TCK high
    outa[TDI] := value & 1    ' Output data bit
    data |= ina[TDO]          ' Input data bit from target
    outa[TCK] := 0            ' TCK low
    value >>= 1

  data ><= bits               ' Bitwise reverse since LSB came in first (we want MSB to be first)

       
PRI Enter_Shift_DR      ' 
{
    Move TAP to the Shift-DR state.
    TAP must be in Run-Test-Idle state before being called.
}
  TMS_High                    ' Go to Select DR Scan
  TMS_Low                     ' Go to Capture DR
  TMS_Low                     ' Go to Shift DR
  

PRI Enter_Shift_IR  
{
    Move TAP to the Shift-IR state.
    TAP must be in Run-Test-Idle state before being called.
}
  TMS_High                    ' Go to Select DR Scan
  TMS_High                    ' Go to Select IR Scan
  TMS_Low                     ' Go to Capture IR
  TMS_Low                     ' Go to Shift IR
    
  
PUB Restore_Idle
{
    Resets the TAP to the Test-Logic-Reset state from any unknown state by transitioning through the state machine.
    TMS is held high for five consecutive TCK clock periods.
    Leaves the TAP in the Run-Test-Idle state.
}
  outa[TCK] := 0              ' Ensure TCK starts low for pulsing
 
  outa[TMS] := 1              ' TMS high
  repeat 5
    TCK_Pulse

  TMS_Low                     ' Go to Run-Test-Idle
    

PRI TMS_High
{
    One transition with TMS held high.
    Provides a vehicle for progression through the state machine.
    Used when shifting data into and out of the TAP.
}
  outa[TMS] := 1              ' TMS high
  TCK_Pulse

  
PRI TMS_Low
{
    One transition with TMS held low. 
    Provides a vehicle for progression through the state machine.
    Used when shifting data into and out of the TAP.
}
  outa[TMS] := 0              ' TMS low
  TCK_Pulse

  
PRI TCK_Pulse
{
    Generate one TCK pulse.
    Expects TCK to be low upon being called.
}     
  outa[TCK] := 1
  outa[TCK] := 0
  

DAT