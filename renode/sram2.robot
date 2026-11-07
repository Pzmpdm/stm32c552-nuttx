*** Settings ***
Test Setup    Load SRAM2 Firmware

*** Variables ***
${ELF}    ${CURDIR}/../build/stm32c552-sram2/nuttx
${PLATFORM}    ${CURDIR}/stm32c552vet6-devkit.repl

*** Test Cases ***
Boot Scrubs SRAM2 Before Adding It To The Heap
    Seed SRAM2
    Start Emulation
    Wait For NSH
    SRAM2 Is Clocked And Scrubbed

    Execute Command    pause
    Seed SRAM2
    Execute Command    machine Reset
    Wait For NSH
    SRAM2 Is Clocked And Scrubbed

NSH Can Allocate Test And Free A Large SRAM2 Block
    Start Emulation
    Wait For NSH
    ${before}=    Get Available Heap
    Should Be True    ${before} > 110000
    Run SRAM2 Memory Test    w
    Run SRAM2 Memory Test    b
    ${after}=    Get Available Heap
    Should Be Equal As Integers    ${after}    ${before}

*** Keywords ***
Load SRAM2 Firmware
    Execute Command    $firmware = @${ELF}
    Execute Command    $platform = @${PLATFORM}
    Execute Command    include @${CURDIR}/boot.resc
    Create Terminal Tester    sysbus.usart1    timeout=4

Wait For NSH
    Wait For Line On Uart    NuttShell (NSH)
    Wait For Prompt On Uart    nsh>

Seed SRAM2
    Execute Command    sysbus WriteDoubleWord 0x20010040 0xA55AA55A
    Execute Command    sysbus WriteDoubleWord 0x20018000 0xA55AA55A
    Execute Command    sysbus WriteDoubleWord 0x2001FFB0 0xA55AA55A

SRAM2 Is Clocked And Scrubbed
    ${ahb1}=    Execute Command    sysbus ReadDoubleWord 0x44020C88
    Should Be True    int($ahb1, 16) & (1 << 30)
    FOR    ${address}    IN    0x20010040    0x20018000    0x2001FFB0
        ${word}=    Execute Command    sysbus ReadDoubleWord ${address}
        Should Be Equal As Integers    ${word}    0
    END

Get Available Heap
    Write Line To Uart    free
    Wait For Line On Uart    ^\\s*total\\s+used\\s+free    treatAsRegex=True
    ${row}=    Wait For Line On Uart    ^\\s*\\d+\\s+\\d+\\s+\\d+    treatAsRegex=True
    Wait For Prompt On Uart    nsh>
    ${free}=    Evaluate    int($row.Line.split()[2])
    RETURN    ${free}

Run SRAM2 Memory Test
    [Arguments]    ${width}
    Write Line To Uart    ramtest -${width} -s 60000; echo ram-done-$?
    ${start}=    Wait For Line On Uart    ^RAMTest: Marching ones: ([0-9a-f]{8}) 60000$    treatAsRegex=True
    ${address}=    Evaluate    int($start.Groups[0], 16)
    Should Be True    0x20010000 <= ${address} <= 0x20020000 - 60000
    FOR    ${pattern}    IN    Marching zeroes    Pattern test    Pattern test    Pattern test    Address-in-address test
        ${step}=    Wait For Line On Uart    ^RAMTest:    treatAsRegex=True
        Should Start With    ${step.Line}    RAMTest: ${pattern}:
    END
    ${end}=    Wait For Line On Uart    ^(RAMTest:|ram-done-)    treatAsRegex=True
    Should Be Equal    ${end.Line}    ram-done-0
    Wait For Prompt On Uart    nsh>
