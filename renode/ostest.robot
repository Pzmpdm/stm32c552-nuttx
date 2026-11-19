*** Variables ***
${ELF}        ${CURDIR}/../build/stm32c552-ostest/nuttx
${PLATFORM}   ${CURDIR}/stm32c552vet6-devkit.repl

*** Test Cases ***
OS Test Exits Zero On The Simulated Cortex-M
    Execute Command          $firmware = @${ELF}
    Execute Command          $platform = @${PLATFORM}
    Execute Command          include @${CURDIR}/boot.resc
    Create Terminal Tester   sysbus.usart1    timeout=240
    Start Emulation
    Wait For Line On Uart    NuttShell (NSH)
    Wait For Prompt On Uart  nsh>
    Write Line To Uart       ostest
    ${line}=    Wait For Line On Uart    (ERROR|Assertion failed|ostest_main: Exiting with status \\d+)    treatAsRegex=True
    Should Be Equal          ${line.Line}    ostest_main: Exiting with status 0
