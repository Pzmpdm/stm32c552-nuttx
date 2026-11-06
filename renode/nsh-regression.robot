*** Settings ***
Test Setup    Boot NSH

*** Variables ***
${ELF}    ${CURDIR}/../build/stm32c552/nuttx

*** Test Cases ***
Serial Input Recovers After Invalid Lines
    Send UART Bytes    echo editeX\x08d\r
    Expect Output Line    edited
    Wait For Prompt On Uart    nsh>
    Send UART Bytes    \r
    Wait For Prompt On Uart    nsh>
    Send UART Bytes    echo crlf-ok\r\n
    Expect Output Line    crlf-ok
    Wait For Prompt On Uart    nsh>
    Send UART Bytes    echo first\recho second\r
    Expect Output Line    first
    Expect Output Line    second
    Wait For Prompt On Uart    nsh>

    Run NSH Command    nsh_invalid_probe    ^nsh: nsh_invalid_probe: command not found$
    FOR    ${length}    IN    63    64    65
        ${payload}=    Evaluate    'x' * (${length} - len('echo '))
        Send UART Bytes    echo ${payload}\recho recovered-${length}\r
        IF    ${length} > 63
            ${remainder}=    Evaluate    'x' * (${length} - 63)
            Expect Output Line    nsh: ${remainder}: command not found
        END
        Expect Output Line    recovered-${length}
        Wait For Prompt On Uart    nsh>
    END

NSH Exposes System Diagnostics
    Run NSH Command    help    (^|\\s)dd(\\s|$)
    Write Line To Uart    ps
    Wait For Line On Uart    ^\\s*TID\\s+PID\\s+PPID.*COMMAND    treatAsRegex=True
    Wait For Line On Uart    ^\\s*\\d+\\s+\\d+\\s+\\d+\\s+    treatAsRegex=True
    Wait For Prompt On Uart    nsh>
    ${free}=    Get Available Heap
    Should Be True    ${free} > 0
    Run NSH Command    ls /dev    ^\\s*console\\s*$
    Run NSH Command    ls /proc    ^\\s*\\d+/?\\s*$

NSH Waits For A Registered Application
    Run NSH Command    dd if=/dev/zero of=/dev/null bs=16 count=4    ^64 bytes \\(4 blocks\\) copied,
    Run NSH Command    dd invalid=1    ^usage:$
    Run NSH Command    echo after-dd    ^after-dd$

*** Keywords ***
Boot NSH
    Execute Command    $firmware = @${ELF}
    Execute Command    include @${CURDIR}/boot.resc
    Create Terminal Tester    sysbus.usart1    timeout=3
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

Send UART Bytes
    [Arguments]    ${data}
    # XML-RPC strings cannot carry all UART control bytes.
    ${bytes}=    Evaluate    list(map(ord, $data))
    Execute Command    python "uart = self.Machine['sysbus.usart1']; [uart.WriteChar(byte) for byte in ${bytes}]"

Expect Output Line
    [Arguments]    ${line}
    ${pattern}=    Evaluate    '^' + re.escape($line) + '$'    modules=re
    Wait For Line On Uart    ${pattern}    treatAsRegex=True

Get Available Heap
    Write Line To Uart    free
    Wait For Line On Uart    ^\\s*total\\s+used\\s+free    treatAsRegex=True
    ${row}=    Wait For Line On Uart    ^\\s*\\d+\\s+\\d+\\s+\\d+    treatAsRegex=True
    Wait For Prompt On Uart    nsh>
    ${free}=    Evaluate    int($row.Line.split()[2])
    RETURN    ${free}
