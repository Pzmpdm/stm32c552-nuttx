*** Variables ***
${ELF}       ${CURDIR}/../build/stm32c552/nuttx
${PLATFORM}    ${CURDIR}/stm32c552vet6-devkit.repl
${KERNEL_HZ}    48000000

*** Test Cases ***
NSH boots and executes commands over USART1
    Execute Command             $firmware = @${ELF}
    Execute Command    $platform = @${PLATFORM}
    Execute Command             include @${CURDIR}/boot.resc
    Create Terminal Tester      sysbus.usart1    timeout=5
    Start Emulation
    Wait For Line On Uart        NuttShell (NSH)
    Wait For Prompt On Uart      nsh>
    USART1 Is Configured On PA9 And PA10
    Write Line To Uart           echo phase1-ready
    Wait For Line On Uart        ^phase1-ready$    treatAsRegex=True
    Wait For Prompt On Uart      nsh>
    Write Line To Uart           pwd
    Wait For Line On Uart        ^/$    treatAsRegex=True
    Wait For Prompt On Uart      nsh>
    Execute Command             pause
    ${before}=                   Virtual Time In Seconds
    Write Line To Uart           sleep 1
    Wait For Prompt On Uart      nsh>    pauseEmulation=True
    ${after}=                    Virtual Time In Seconds
    Should Be True               0.95 <= ${after} - ${before} <= 1.10
    Write Line To Uart           echo phase1-tick-ok
    Wait For Line On Uart        ^phase1-tick-ok$    treatAsRegex=True
    Wait For Prompt On Uart      nsh>

*** Keywords ***
USART1 Is Configured On PA9 And PA10
    ${gpio_gate}=    Execute Command    sysbus ReadDoubleWord 0x44020C8C
    ${uart_gate}=    Execute Command    sysbus ReadDoubleWord 0x44020CA4
    ${gpio_mode}=    Execute Command    sysbus ReadDoubleWord 0x42020000
    ${gpio_af}=      Execute Command    sysbus ReadDoubleWord 0x42020024
    ${uart_cr1}=     Execute Command    sysbus ReadDoubleWord 0x40013800
    ${uart_brr}=     Execute Command    sysbus ReadDoubleWord 0x4001380C
    Should Be True    int($gpio_gate, 16) & 1
    Should Be True    (int($uart_gate, 16) >> 14) & 1
    Should Be True    ((int($gpio_mode, 16) >> 18) & 0xF) == 0xA
    Should Be True    ((int($gpio_af, 16) >> 4) & 0xFF) == 0x77
    # Decode USARTDIV for either oversampling mode and check 115200 baud.
    ${brr}=    Evaluate    int($uart_brr, 16)
    ${baud}=    Evaluate    (2 * ${KERNEL_HZ}) / (($brr & 0xFFF0) | (($brr & 7) << 1)) if int($uart_cr1, 16) & 0x8000 else ${KERNEL_HZ} / $brr
    Should Be True    114048 <= ${baud} <= 116352

Virtual Time In Seconds
    ${seconds}=    Execute Command    python "print(self.Machine.LocalTimeSource.ElapsedVirtualTime.TotalSeconds)"
    RETURN    ${seconds.strip()}
