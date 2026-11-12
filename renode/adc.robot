*** Settings ***
Test Setup    Boot ADC NSH

*** Variables ***
${ELF}    ${CURDIR}/../build/stm32c552-adc/nuttx
${PLATFORM}    ${CURDIR}/stm32c552vet6-devkit-adc.repl

*** Test Cases ***
ADC1 Is Registered With PC0 In Analog Mode
    Write Line To Uart    ls /dev
    Wait For Line On Uart    ^\\s*adc0$    treatAsRegex=True
    Wait For Prompt On Uart    nsh>
    ${mode}=    Execute Command    sysbus ReadDoubleWord 0x42020800
    ${pull}=    Execute Command    sysbus ReadDoubleWord 0x4202080C
    Should Be True    (int($mode, 16) & 3) == 3
    Should Be True    (int($pull, 16) & 3) == 0
    ADC Is Closed
    ADC Counter Equals    Calibrations    0

ADC1 Converts Distinct Voltages And Full Scale
    # Drive a different voltage on a neighboring input to distinguish channels.
    Execute Command    sysbus.adc1 SetVoltage 3000000 9
    FOR    ${voltage}    ${code}    IN
    ...    0          0
    ...    330000     410
    ...    1650000    2048
    ...    2640000    3276
    ...    3300000    4095
        Read ADC Voltage    ${voltage}    ${code}
        ADC Is Closed
    END
    ADC Counter Equals    CalibrationStarts    5
    ADC Counter Equals    Calibrations    5
    ADC Counter Equals    Starts    5
    ADC Counter Equals    DataReads    5
    ADC Counter Equals    SequencingErrors    0

ADC1 Samples Repeatedly During A Single Open
    Execute Command    sysbus.adc1 SetVoltage 2200000 8
    Write Line To Uart    adc -n32
    FOR    ${index}    IN RANGE    32
        Wait For Line On Uart    ^1: channel: 8 value: 2730$    treatAsRegex=True
    END
    Wait For Prompt On Uart    nsh>
    ADC Counter Equals    Calibrations    1
    ADC Counter Equals    Starts    32
    ADC Counter Equals    DataReads    32
    ADC Counter Equals    SequencingErrors    0
    ADC Is Closed

ADC1 Waits For The Conversion IRQ And Delivers The Pending Sample
    Execute Command    sysbus.adc1 SetVoltage 1100000 8
    # Mask IRQ when ADSTART is written. Setup otherwise enables it on open.
    Execute Command    sysbus AddWatchpointHook 0x42028008 DoubleWord Write "if value & 4: self.Machine.SystemBus.WriteDoubleWord(0xE000E184, 1)"
    Write Line To Uart    adc -n1 &
    Wait For Line On Uart    Opening the ADC device: /dev/adc0
    Write Line To Uart    echo adc-console-ok
    Wait For Line On Uart    ^adc-console-ok$    treatAsRegex=True
    Wait For Prompt On Uart    nsh>
    ${isr}=    Execute Command    sysbus ReadDoubleWord 0x42028000
    ${ier}=    Execute Command    sysbus ReadDoubleWord 0x42028004
    ${gate}=    Execute Command    sysbus ReadDoubleWord 0x44020C8C
    ${clock}=    Execute Command    sysbus ReadDoubleWord 0x44020CDC
    Should Be True    (int($isr, 16) & 0xC) == 0xC
    Should Be True    (int($ier, 16) & 0x14) == 0x14
    Should Be True    int($gate, 16) & 0x400
    Should Be True    (int($clock, 16) & 0x7C00) == 0x2000
    ADC Counter Equals    LastConfiguration    0
    ADC Counter Equals    LastPreselection    0x100
    ADC Counter Equals    LastSequence    0x200
    ADC Counter Equals    LastSampleTime    0x05000000
    ADC Counter Equals    DataReads    0
    Execute Command    sysbus WriteDoubleWord 0xE000E104 1
    Wait For Line On Uart    ^1: channel: 8 value: 1365$    treatAsRegex=True
    Execute Command    pause
    Execute Command    emulation RunFor "0.020"
    ADC Counter Equals    DataReads    1
    ADC Counter Equals    SequencingErrors    0
    ADC Is Closed

ADC1 Times Out When Its Regulator Fails And Recovers
    ADC Open Fails And Recovers    StallRegulator    0    0    0

ADC1 Times Out When Calibration Stalls And Recovers
    ADC Open Fails And Recovers    StallCalibration    1    0    0

ADC1 Times Out When Ready Is Missing And Recovers
    ADC Open Fails And Recovers    StallReady    1    1    1

*** Keywords ***
Boot ADC NSH
    Execute Command    $firmware=@${ELF}
    Execute Command    $platform=@${PLATFORM}
    Execute Command    include @${CURDIR}/boot.resc
    Create Terminal Tester    sysbus.usart1    timeout=3
    Start Emulation
    Wait For Line On Uart    NuttShell (NSH)
    Wait For Prompt On Uart    nsh>
    Execute Command    sysbus.adc1 ClearTrace

Read ADC Voltage
    [Arguments]    ${microvolts}    ${code}
    Execute Command    sysbus.adc1 SetVoltage ${microvolts} 8
    Write Line To Uart    adc -n1
    Wait For Line On Uart    ^1: channel: 8 value: ${code}$    treatAsRegex=True
    Wait For Prompt On Uart    nsh>

ADC Counter Equals
    [Arguments]    ${name}    ${expected}
    ${value}=    Execute Command    sysbus.adc1 ${name}
    Should Be Equal As Integers    ${value}    ${expected}

ADC Is Closed
    ${gate}=    Execute Command    sysbus ReadDoubleWord 0x44020C8C
    ${control}=    Execute Command    sysbus ReadDoubleWord 0x42028008
    ${ier}=    Execute Command    sysbus ReadDoubleWord 0x42028004
    ${nvic}=    Execute Command    sysbus ReadDoubleWord 0xE000E104
    Should Be True    (int($gate, 16) & 0x400) == 0
    Should Be True    int($control, 16) == 0x20000000
    Should Be Equal As Integers    ${ier}    0
    Should Be True    (int($nvic, 16) & 1) == 0

ADC Open Fails And Recovers
    [Arguments]    ${fault}    ${calibration_starts}    ${calibrations}    ${enables}
    Execute Command    sysbus.adc1 ${fault} true
    Write Line To Uart    adc -n1
    Wait For Line On Uart    adc_main: open /dev/adc0 failed: 110    timeout=0.1
    Wait For Prompt On Uart    nsh>
    ADC Counter Equals    CalibrationStarts    ${calibration_starts}
    ADC Counter Equals    Calibrations    ${calibrations}
    ADC Counter Equals    Enables    ${enables}
    ADC Counter Equals    Resets    2
    ADC Counter Equals    Starts    0
    ADC Counter Equals    DataReads    0
    ADC Is Closed
    Execute Command    sysbus.adc1 ${fault} false
    Read ADC Voltage    1650000    2048
    ADC Counter Equals    Starts    1
    ADC Counter Equals    DataReads    1
    ADC Counter Equals    SequencingErrors    0
    ADC Is Closed
