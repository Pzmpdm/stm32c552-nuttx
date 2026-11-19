*** Settings ***
Test Setup    Boot USB NSH

*** Variables ***
${ELF}    ${CURDIR}/../build/stm32c552-usb/nuttx
${PLATFORM}    ${CURDIR}/stm32c552vet6-devkit-usb.repl

*** Test Cases ***
USB Device Answers Setup From Packet Memory And Keeps USART1
    ${pullup}=    Execute Command    sysbus ReadDoubleWord 0x40016058
    ${ck48}=    Execute Command    sysbus ReadDoubleWord 0x44020CDC
    Should Be True    int($pullup, 16) & (1 << 15)
    Should Be True    ((int($ck48, 16) >> 24) & 3) == 2
    Execute Command    pause
    Execute Command    sysbus.usb BusReset
    Execute Command    emulation RunFor "0.01"
    Execute Command    sysbus.usb Setup "8006000100001200"
    Execute Command    emulation RunFor "0.01"
    ${desc}=    Execute Command    sysbus.usb TxHex 0
    Should Match Regexp    ${desc}    ^"?1201
    Execute Command    sysbus.usb CompleteIn 0
    Execute Command    emulation RunFor "0.002"
    Execute Command    sysbus.usb StatusOut 0
    Execute Command    emulation RunFor "0.002"
    Execute Command    sysbus.usb Setup "0005020000000000"
    Execute Command    emulation RunFor "0.01"
    Execute Command    sysbus.usb CompleteIn 0
    Execute Command    emulation RunFor "0.01"
    ${addr}=    Execute Command    sysbus ReadDoubleWord 0x4001604C
    Should Be True    int($addr, 16) == 0x82
    Execute Command    sysbus.usb Setup "0009010000000000"
    Execute Command    emulation RunFor "0.01"
    Execute Command    sysbus.usb CompleteIn 0
    Execute Command    emulation RunFor "0.01"
    Execute Command    start
    Write Line To Uart    echo usb-in > /dev/ttyACM0
    Wait For Prompt On Uart    nsh>
    ${sent}=    Execute Command    sysbus.usb TxHex 2
    Should Match Regexp    ${sent}    ^"?7573622D696E0A
    Execute Command    start
    Write Line To Uart    cat /dev/ttyACM0
    Sleep    0.2
    Execute Command    sysbus.usb InjectEarlyCtr true
    Execute Command    sysbus.usb BulkOut 3 "7573622d6f6b0a"
    Execute Command    pause
    Execute Command    emulation RunFor "0.02"
    Execute Command    start
    Wait For Line On Uart    ^usb-ok$    treatAsRegex=True
    ${early}=    Execute Command    sysbus.usb EarlyReads
    ${delayed}=    Execute Command    sysbus.usb DelayedPackets
    Should Be Equal As Integers    ${early}    0
    Should Be Equal As Integers    ${delayed}    1

*** Keywords ***
Boot USB NSH
    Execute Command    $firmware = @${ELF}
    Execute Command    $platform = @${PLATFORM}
    Execute Command    include @${CURDIR}/boot.resc
    Create Terminal Tester    sysbus.usart1    timeout=10
    Start Emulation
    Wait For Line On Uart    NuttShell (NSH)
    Wait For Prompt On Uart    nsh>
