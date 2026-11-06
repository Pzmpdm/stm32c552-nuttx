*** Variables ***
${ELF}    ${CURDIR}/../build/stm32c552-hse/nuttx

*** Test Cases ***
HSE Drives The 144 MHz PSI Clock
    Verify 144 MHz Clock    0    3

HSE Timeout Falls Back To 144 MHz HSIS
    Verify 144 MHz Clock    1    1

PSI Timeout Falls Back To 144 MHz HSIS
    Verify 144 MHz Clock    2    1

PSIS Switch Timeout Falls Back To 144 MHz HSIS
    Verify 144 MHz Clock    4    1

*** Keywords ***
Verify 144 MHz Clock
    [Arguments]    ${faults}    ${source}
    Execute Command    mach create "stm32c552-144mhz"
    Execute Command    machine LoadPlatformDescription @${CURDIR}/stm32c552vet6-devkit-144mhz.repl
    Execute Command    sysbus LoadELF @${ELF}
    Execute Command    sysbus WriteDoubleWord 0x44020C40 ${faults}
    Create Terminal Tester    sysbus.usart1    timeout=12
    Start Emulation
    Wait For Line On Uart    NuttShell (NSH)
    Wait For Prompt On Uart    nsh>

    ${acr}=    Execute Command    sysbus ReadDoubleWord 0x40022000
    ${cfgr}=    Execute Command    sysbus ReadDoubleWord 0x44020C1C
    ${cr1}=    Execute Command    sysbus ReadDoubleWord 0x44020C00
    ${cr2}=    Execute Command    sysbus ReadDoubleWord 0x44020C04
    ${uart_cr1}=    Execute Command    sysbus ReadDoubleWord 0x40013800
    ${brr}=    Execute Command    sysbus ReadDoubleWord 0x4001380C
    Should Be True    (int($acr, 16) & 0x3F) == 0x24
    Should Be True    ((int($cfgr, 16) >> 3) & 3) == ${source}
    Should Be Equal As Integers    ${brr}    1250
    Should Be True    (int($uart_cr1, 16) & (1 << 15)) == 0
    IF    ${source} == 3
        Should Be True    int($cr1, 16) & (1 << 17)
        Should Be True    int($cr1, 16) & (1 << 12)
        Should Be True    (int($cr2, 16) & 0x30730000) == 0x10100000
    ELSE
        Should Be True    int($cr1, 16) & (1 << 4)
        Should Be True    (int($cr1, 16) & 0x10100) == 0
    END

    Execute Command    pause
    ${before}=    Virtual Time In Seconds
    Write Line To Uart    sleep 1
    Wait For Prompt On Uart    nsh>    pauseEmulation=True
    ${after}=    Virtual Time In Seconds
    Should Be True    0.95 <= ${after} - ${before} <= 1.10
    Write Line To Uart    echo clock-ok
    Wait For Line On Uart    ^clock-ok$    treatAsRegex=True
    Wait For Prompt On Uart    nsh>

Virtual Time In Seconds
    ${seconds}=    Execute Command    python "print(self.Machine.LocalTimeSource.ElapsedVirtualTime.TotalSeconds)"
    RETURN    ${seconds.strip()}
