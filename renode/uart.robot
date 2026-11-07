*** Settings ***
Test Setup    Boot UART NSH

*** Variables ***
${ELF}    ${CURDIR}/../build/stm32c552-uart/nuttx

*** Test Cases ***
USART2 Is Registered As The Second Serial Device
    Write Line To Uart    ls /dev
    Wait For Line On Uart    ^\\s*ttyS0$    treatAsRegex=True
    Wait For Line On Uart    ^\\s*ttyS1$    treatAsRegex=True
    Wait For Prompt On Uart    nsh>

USART2 Blocks For Input While The Console Remains Usable
    Configure UART2    115200
    Start Receiver    /tmp/s    1
    UART2 Is Receiving    115200
    Run NSH Command    echo console-alive    ^console-alive$
    Inject Bytes    64    19    115200
    Wait For Receiver
    Execute Command    uart2_clear
    Run NSH Command    dd if=/tmp/s of=/dev/ttyS1 bs=32
    Captured Bytes Match    64    19
    UART2 Is Closed

USART2 Transfers Four KiB Of Binary Data In Order
    Prepare Source    4096    37    115200
    Execute Command    uart2_clear
    Run NSH Command    dd if=/tmp/s of=/dev/ttyS1 bs=32
    Captured Bytes Match    4096    37
    UART2 Is Closed

USART2 Loops Back Four KiB Through Both Interrupt Paths
    Prepare Source    4096    83    115200
    Execute Command    uart2_clear
    Execute Command    uart2_loopback 1
    Start Receiver    /tmp/r    64
    UART2 Is Receiving    115200
    Run NSH Command    dd if=/tmp/s of=/dev/ttyS1 bs=32
    Wait For Receiver
    Run NSH Command    cmp /tmp/s /tmp/r
    Captured Bytes Match    4096    83
    Execute Command    uart2_loopback 0
    UART2 Is Closed

USART2 Changes Baud Rate Across Close And Reopen
    FOR    ${baud}    IN    9600    115200    921600
        Prepare Source    256    41    ${baud}
        Execute Command    uart2_clear
        Run NSH Command    dd if=/tmp/s of=/dev/ttyS1 bs=32
        Captured Bytes Match    256    41
        UART2 Is Closed
    END
    Run NSH Command    echo console-still-alive    ^console-still-alive$

*** Keywords ***
Boot UART NSH
    Execute Command    include @${CURDIR}/STM32C5_TIM2.cs
    Execute Command    mach create "stm32c552-uart"
    Execute Command    machine LoadPlatformDescription @${CURDIR}/stm32c552vet6-devkit-uart.repl
    Execute Command    sysbus LoadELF @${ELF}
    Execute Command    cpu VectorTableOffset 0x08000000
    Execute Command    include @${CURDIR}/uart2-wire.py
    Execute Command    uart2_install
    Create Terminal Tester    sysbus.usart1    timeout=5
    Start Emulation
    Wait For Line On Uart    NuttShell (NSH)
    Wait For Prompt On Uart    nsh>

Run NSH Command
    [Arguments]    ${command}    ${pattern}=${NONE}
    Write Line To Uart    ${command}
    IF    $pattern is not None
        Wait For Line On Uart    ${pattern}    treatAsRegex=True
    END
    Wait For Prompt On Uart    nsh>
    Write Line To Uart    echo rc-$?
    Wait For Line On Uart    ^rc-0$    treatAsRegex=True
    Wait For Prompt On Uart    nsh>

Configure UART2
    [Arguments]    ${baud}
    Run NSH Command    stty -F /dev/ttyS1 raw speed ${baud}    ^Settings applied to /dev/ttyS1$

Prepare Source
    [Arguments]    ${count}    ${seed}    ${baud}
    Configure UART2    ${baud}
    ${blocks}=    Evaluate    int($count) // 64
    Start Receiver    /tmp/s    ${blocks}
    UART2 Is Receiving    ${baud}
    Inject Bytes    ${count}    ${seed}    ${baud}
    Wait For Receiver

Start Receiver
    [Arguments]    ${path}    ${blocks}
    Run NSH Command    echo pending > /tmp/done
    Run NSH Command    echo 'dd if=/dev/ttyS1 of=${path} bs=64 count=${blocks}' > /tmp/job
    Run NSH Command    echo 'echo done > /tmp/done' >> /tmp/job
    Run NSH Command    sh /tmp/job &

Wait For Receiver
    Wait Until Keyword Succeeds    3s    20ms    Receiver Has Finished

Receiver Has Finished
    # Host retry delays do not guarantee any guest scheduling time.
    Execute Command    pause
    Execute Command    emulation RunFor "0.020"
    Write Line To Uart    cat /tmp/done
    ${state}=    Wait For Line On Uart    ^(pending|done)$    treatAsRegex=True
    Wait For Prompt On Uart    nsh>
    Should Be Equal    ${state.Line}    done

Inject Bytes
    [Arguments]    ${count}    ${seed}    ${baud}
    Execute Command    pause
    ${delay}=    Evaluate    str(64 * 10.0 / int($baud) + 0.001)
    FOR    ${offset}    IN RANGE    0    ${count}    64
        Execute Command    uart2_feed ${offset} 64 ${seed}
        Execute Command    emulation RunFor "${delay}"
    END

Captured Bytes Match
    [Arguments]    ${count}    ${seed}
    ${result}=    Execute Command    uart2_check ${count} ${seed}
    Should Contain    ${result}    UART2_BYTES_OK ${count}

UART2 Is Receiving
    [Arguments]    ${baud}
    Execute Command    pause
    Execute Command    emulation RunFor "0.010"
    ${mode}=    Execute Command    sysbus ReadDoubleWord 0x42020000
    ${af}=    Execute Command    sysbus ReadDoubleWord 0x42020020
    ${clock}=    Execute Command    sysbus ReadDoubleWord 0x44020C9C
    ${source}=    Execute Command    sysbus ReadDoubleWord 0x44020CD8
    ${control}=    Execute Command    sysbus ReadDoubleWord 0x40004400
    ${format}=    Execute Command    sysbus ReadDoubleWord 0x40004404
    ${divisor}=    Execute Command    sysbus ReadDoubleWord 0x4000440C
    ${nvic}=    Execute Command    sysbus ReadDoubleWord 0xE000E104
    Should Be True    ((int($mode, 16) >> 4) & 15) == 10
    Should Be True    ((int($af, 16) >> 8) & 255) == 0x77
    Should Be True    int($clock, 16) & (1 << 17)
    Should Be True    (int($source, 16) & 12) == 0
    Should Be True    (int($control, 16) & 0x160D) == 13
    Should Be True    int($control, 16) & (1 << 5)
    Should Be True    (int($format, 16) & (3 << 12)) == 0
    Should Be True    int($nvic, 16) & (1 << 20)
    ${over8}=    Evaluate    bool(int($control, 16) & (1 << 15))
    ${divider}=    Evaluate    (int($divisor, 16) & 0xFFF0) + 2 * (int($divisor, 16) & 7) if $over8 else int($divisor, 16)
    ${actual_baud}=    Evaluate    (96000000.0 if $over8 else 48000000.0) / $divider
    Should Be True    abs($actual_baud / int($baud) - 1) < 0.01

UART2 Is Closed
    Execute Command    pause
    Execute Command    emulation RunFor "0.010"
    ${control}=    Execute Command    sysbus ReadDoubleWord 0x40004400
    ${clock}=    Execute Command    sysbus ReadDoubleWord 0x44020C9C
    ${nvic}=    Execute Command    sysbus ReadDoubleWord 0xE000E104
    Should Be True    (int($control, 16) & 13) == 0
    Should Be True    (int($clock, 16) & (1 << 17)) == 0
    Should Be True    (int($nvic, 16) & (1 << 20)) == 0
