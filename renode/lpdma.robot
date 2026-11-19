*** Variables ***
${ELF}    ${CURDIR}/../build/stm32c552-lpdma/nuttx
${PLATFORM}    ${CURDIR}/stm32c552vet6-devkit-lpdma.repl

*** Test Cases ***
LPDMA Copies Memory Through All Twelve Channels
    Load LPDMA Board
    Start Emulation
    Check Memory Tests    8    4
    ${clock}=    Execute Command    sysbus ReadDoubleWord 0x44020C88
    Should Be True    (int($clock, 16) & 3) == 3

LPDMA Clears A Data Error And Retries On The Same Channel
    Load LPDMA Board
    Execute Command    sysbus.lpdma1 FailNext true
    Start Emulation
    Wait For Line On Uart    LPDMA1 channel 0 retry: -5
    Check Memory Tests    9    4
    DMA Counter Equals    1    Errors    1

LPDMA Suspends A Stalled Channel And Retries
    Load LPDMA Board
    Execute Command    sysbus.lpdma2 StallNext true
    Start Emulation
    Wait For Line On Uart    LPDMA2 channel 0 retry: -110
    Wait For Line On Uart    LPDMA2 memory test: 4 channels OK
    Wait For Prompt On Uart    nsh>
    DMA Counter Equals    2    SoftwareStarts    5
    DMA Counter Equals    2    Completions    4
    DMA Counter Equals    2    Suspensions    1

ADC1 Moves Four Samples Per Trigger Through LPDMA1
    Boot LPDMA NSH
    Read DMA Block    1650000    2048
    Read DMA Block    330000    410
    Read DMA Block    3300000    4095
    DMA Counter Equals    1    SoftwareStarts    8
    DMA Counter Equals    1    PeripheralBeats    12
    DMA Counter Equals    1    Completions    11
    ADC Counter Equals    Starts    3
    ADC Counter Equals    DataReads    12
    ADC Counter Equals    DmaArms    3
    ADC Counter Equals    LastConfiguration    0
    ADC Counter Equals    LastPreselection    0x100
    ADC Counter Equals    LastSequence    0x08208203
    ADC Counter Equals    SequencingErrors    0
    ADC DMA Is Closed

ADC1 Reuses The DMA Channel For Sixteen Blocks In One Open
    Boot LPDMA NSH
    Execute Command    sysbus.adc1 SetVoltage 2200000 8
    Write Line To Uart    adc -n16
    FOR    ${block}    IN RANGE    16
        Wait For DMA Samples    2730
    END
    Wait For Prompt On Uart    nsh>
    ADC Counter Equals    Calibrations    1
    ADC Counter Equals    Starts    16
    ADC Counter Equals    DmaArms    16
    ADC Counter Equals    SequencingErrors    0
    DMA Counter Equals    1    PeripheralBeats    64
    DMA Counter Equals    1    Completions    24
    ADC DMA Is Closed

ADC1 Waits For The DMA Completion Interrupt
    Boot LPDMA NSH
    Execute Command    sysbus.adc1 SetVoltage 1100000 8
    Execute Command    sysbus WriteDoubleWord 0xE000E180 0x00800000
    Write Line To Uart    adc -n1 &
    Wait For Line On Uart    Opening the ADC device: /dev/adc0
    Execute Command    pause
    Execute Command    emulation RunFor "0.003"
    ${status}=    Execute Command    sysbus ReadDoubleWord 0x40020060
    ${ier}=    Execute Command    sysbus ReadDoubleWord 0x42028004
    Should Be True    (int($status, 16) & 0x100) != 0
    Should Be Equal As Integers    ${ier}    0
    DMA Counter Equals    1    PeripheralBeats    4
    Execute Command    sysbus WriteDoubleWord 0xE000E100 0x00800000
    Wait For DMA Samples    1365
    Execute Command    pause
    Execute Command    emulation RunFor "0.020"
    ADC DMA Is Closed

ADC1 Reports A Failed DMA Block And Reopens
    Boot LPDMA NSH
    Execute Command    sysbus.lpdma1 FailNext true
    ADC DMA Error And Recovery    5
    DMA Counter Equals    1    Errors    1
    DMA Counter Equals    1    PeripheralBeats    4

ADC1 Cancels A Stalled DMA Block And Reopens
    Boot LPDMA NSH
    Execute Command    sysbus.lpdma1 StallNext true
    ADC DMA Error And Recovery    110
    DMA Counter Equals    1    Suspensions    1
    DMA Counter Equals    1    PeripheralBeats    4

LPDMA Memory Self-Test Uses SRAM2 And Returns The Heap
    Execute Command    $firmware=@${CURDIR}/../build/stm32c552-lpdma-sram2/nuttx
    Execute Command    $platform=@${CURDIR}/stm32c552vet6-devkit-lpdma.repl
    Execute Command    include @${CURDIR}/boot.resc
    Create Terminal Tester    sysbus.usart1    timeout=4
    Start Emulation
    Wait For Line On Uart    LPDMA1 memory test: 8 channels OK
    Wait For Line On Uart    LPDMA2 memory test: 4 channels OK
    ${where}=    Wait For Line On Uart    LPDMA SRAM2 ([0-9a-f]{8}) ([0-9a-f]{8}) ([0-9a-f]{8})    treatAsRegex=True
    ${src}=    Evaluate    int($where.Groups[0], 16)
    ${dst}=    Evaluate    int($where.Groups[1], 16)
    ${gate}=    Evaluate    int($where.Groups[2], 16)
    Should Be True    0x20010000 <= ${src} and ${src} + 128 <= 0x20020000
    Should Be True    0x20010000 <= ${dst} and ${dst} + 128 <= 0x20020000
    Execute Command    pause
    ${before}=    Evaluate    ${dst} - 4
    ${after}=    Evaluate    ${dst} + 128
    ${guard0}=    Execute Command    sysbus ReadDoubleWord ${before}
    ${guard1}=    Execute Command    sysbus ReadDoubleWord ${after}
    Should Be Equal As Integers    ${guard0}    0xa5a5a5a5
    Should Be Equal As Integers    ${guard1}    0xa5a5a5a5
    FOR    ${j}    IN RANGE    32
        ${expected}=    Evaluate    (0x13579bdf ^ ((0x01020307 * ${j}) & 0xffffffff) ^ (3 << 16)) & 0xffffffff
        ${srcaddr}=    Evaluate    ${src} + 4 * ${j}
        ${dstaddr}=    Evaluate    ${dst} + 4 * ${j}
        ${got}=    Execute Command    sysbus ReadDoubleWord ${srcaddr}
        ${copied}=    Execute Command    sysbus ReadDoubleWord ${dstaddr}
        Should Be Equal As Integers    ${got}    ${expected}
        Should Be Equal As Integers    ${copied}    ${expected}
    END
    Execute Command    sysbus WriteDoubleWord ${gate} 1
    Execute Command    start
    ${released}=    Wait For Line On Uart    LPDMA SRAM2 released (\\d+) (\\d+)    treatAsRegex=True
    Should Be Equal    ${released.Groups[0]}    ${released.Groups[1]}
    Wait For Line On Uart    NuttShell (NSH)
    Wait For Prompt On Uart    nsh>

*** Keywords ***
Load LPDMA Board
    Execute Command    $firmware=@${ELF}
    Execute Command    $platform=@${PLATFORM}
    Execute Command    include @${CURDIR}/boot.resc
    Create Terminal Tester    sysbus.usart1    timeout=4

Check Memory Tests
    [Arguments]    ${starts1}    ${starts2}
    Wait For Line On Uart    LPDMA1 memory test: 8 channels OK
    Wait For Line On Uart    LPDMA2 memory test: 4 channels OK
    Wait For Line On Uart    NuttShell (NSH)
    Wait For Prompt On Uart    nsh>
    DMA Counter Equals    1    SoftwareStarts    ${starts1}
    DMA Counter Equals    2    SoftwareStarts    ${starts2}
    DMA Counter Equals    1    Completions    8
    DMA Counter Equals    2    Completions    4
    ${flags1}=    Execute Command    sysbus ReadDoubleWord 0x4002000C
    ${flags2}=    Execute Command    sysbus ReadDoubleWord 0x4002100C
    Should Be Equal As Integers    ${flags1}    0
    Should Be Equal As Integers    ${flags2}    0

DMA Counter Equals
    [Arguments]    ${instance}    ${name}    ${expected}
    ${value}=    Execute Command    sysbus.lpdma${instance} ${name}
    Should Be Equal As Integers    ${value}    ${expected}

Boot LPDMA NSH
    Load LPDMA Board
    Start Emulation
    Check Memory Tests    8    4
    Execute Command    sysbus.adc1 ClearTrace

Read DMA Block
    [Arguments]    ${voltage}    ${code}
    Execute Command    sysbus.adc1 SetVoltage ${voltage} 8
    Write Line To Uart    adc -n1
    Wait For DMA Samples    ${code}
    Wait For Prompt On Uart    nsh>

Wait For DMA Samples
    [Arguments]    ${code}
    FOR    ${index}    IN RANGE    1    5
        Wait For Line On Uart    ^${index}: channel: 8 value: ${code}$    treatAsRegex=True
    END

ADC Counter Equals
    [Arguments]    ${name}    ${expected}
    ${value}=    Execute Command    sysbus.adc1 ${name}
    Should Be Equal As Integers    ${value}    ${expected}

ADC DMA Is Closed
    ${control}=    Execute Command    sysbus ReadDoubleWord 0x40020064
    ${status}=    Execute Command    sysbus ReadDoubleWord 0x40020060
    ${adc}=    Execute Command    sysbus ReadDoubleWord 0x42028008
    ${gate}=    Execute Command    sysbus ReadDoubleWord 0x44020C8C
    Should Be Equal As Integers    ${control}    0
    Should Be Equal As Integers    ${status}    1
    Should Be Equal As Integers    ${adc}    0x20000000
    Should Be True    (int($gate, 16) & 0x400) == 0

ADC DMA Error And Recovery
    [Arguments]    ${trigger_errno}
    Write Line To Uart    adc -n1
    Wait For Line On Uart    ANIOC_TRIGGER ioctl failed: ${trigger_errno}    timeout=0.3
    Wait For Line On Uart    adc_main: read /dev/adc0 failed: 5
    Wait For Prompt On Uart    nsh>
    ADC DMA Is Closed
    DMA Counter Equals    1    PeripheralBeats    0
    Read DMA Block    1650000    2048
    ADC DMA Is Closed
