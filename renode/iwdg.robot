*** Settings ***
Test Setup    Boot IWDG NSH

*** Variables ***
${ELF}    ${CURDIR}/../build/stm32c552/nuttx
${PLATFORM}    ${CURDIR}/stm32c552vet6-devkit.repl

*** Test Cases ***
Stopping The Watchdog Resets Back To NSH
    Arm Watchdog
    Execute Command    emulation RunFor "0.5"
    ${early}=    Execute Command    sysbus.iwdg Resets
    Should Be Equal As Integers    ${early}    0
    Execute Command    emulation RunFor "2"
    Execute Command    start
    Wait For Line On Uart    NuttShell (NSH)
    Wait For Prompt On Uart    nsh>

Feeding The Watchdog Leaves The Running Shell In Place
    Write Line To Uart    echo iwdg-alive > /tmp/mark
    Wait For Prompt On Uart    nsh>
    Execute Command    pause
    Arm Watchdog
    FOR    ${tick}    IN RANGE    5
        Execute Command    emulation RunFor "0.4"
        Execute Command    sysbus WriteDoubleWord 0x40003000 0xAAAA
    END
    Write Line To Uart    cat /tmp/mark
    Execute Command    pause
    Execute Command    emulation RunFor "0.02"
    ${kicks}=    Execute Command    sysbus.iwdg Kicks
    ${resets}=    Execute Command    sysbus.iwdg Resets
    Should Be Equal As Integers    ${kicks}    6
    Should Be Equal As Integers    ${resets}    0
    Wait For Line On Uart    ^iwdg-alive$    treatAsRegex=True
    Wait For Prompt On Uart    nsh>

*** Keywords ***
Boot IWDG NSH
    Execute Command    $firmware = @${ELF}
    Execute Command    $platform = @${PLATFORM}
    Execute Command    include @${CURDIR}/boot.resc
    Create Terminal Tester    sysbus.usart1    timeout=8
    Start Emulation
    Wait For Line On Uart    NuttShell (NSH)
    Wait For Prompt On Uart    nsh>

Arm Watchdog
    Execute Command    pause
    Execute Command    sysbus WriteDoubleWord 0x40003000 0x5555
    Execute Command    sysbus WriteDoubleWord 0x40003008 0x100
    Execute Command    sysbus WriteDoubleWord 0x40003000 0xAAAA
    Execute Command    sysbus WriteDoubleWord 0x40003000 0xCCCC
