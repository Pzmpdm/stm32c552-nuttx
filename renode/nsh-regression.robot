*** Settings ***
Test Setup    Boot NSH

*** Variables ***
${ELF}    ${CURDIR}/../build/stm32c552/nuttx
${PLATFORM}    ${CURDIR}/stm32c552vet6-devkit.repl

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

NSH Runs A Script From Tmpfs
    Run NSH Command    mkdir /tmp/nsh-test
    Run NSH Command    ls /tmp    ^\\s*nsh-test/?\\s*$
    Run NSH Command    echo first > /tmp/nsh-test/data
    Run NSH Command    echo second >> /tmp/nsh-test/data
    Run NSH Command    cp /tmp/nsh-test/data /tmp/nsh-test/copy
    Write Line To Uart    cat /tmp/nsh-test/copy
    Expect Output Line    first
    Expect Output Line    second
    Wait For Prompt On Uart    nsh>

    Run NSH Command    echo 'set token ready' > /tmp/nsh-test/run
    Run NSH Command    echo 'if test "$token" = ready; then' >> /tmp/nsh-test/run
    Run NSH Command    echo 'echo script-ok' >> /tmp/nsh-test/run
    Run NSH Command    echo 'fi' >> /tmp/nsh-test/run
    Run NSH Command    sh /tmp/nsh-test/run    ^script-ok$
    Run NSH Command    cat /tmp/nsh-test/missing    ^nsh: cat:.*failed
    FOR    ${file}    IN    data    copy    run
        Run NSH Command    rm /tmp/nsh-test/${file}
    END
    Run NSH Command    rmdir /tmp/nsh-test
    Run NSH Command    ls /tmp/nsh-test    ^nsh: ls:.*failed

NSH Recovers Resources After Repeated Commands
    Exercise Tmpfs    warmup
    ${initial_heap}=    Get Available Heap
    ${initial_tasks}=    Get Task Count
    FOR    ${round}    IN RANGE    1    51
        Exercise Tmpfs    loop-${round}
    END
    ${middle_heap}=    Get Available Heap
    ${middle_tasks}=    Get Task Count
    FOR    ${round}    IN RANGE    51    101
        Exercise Tmpfs    loop-${round}
    END
    ${final_heap}=    Get Available Heap
    ${final_tasks}=    Get Task Count
    Should Be Equal As Integers    ${middle_tasks}    ${initial_tasks}
    Should Be Equal As Integers    ${final_tasks}    ${initial_tasks}
    Should Be True    ${initial_heap} - ${middle_heap} < 1024
    Should Be True    ${initial_heap} - ${final_heap} < 1024
    Should Be True    ${final_heap} >= ${middle_heap}

*** Keywords ***
Boot NSH
    Execute Command    $firmware = @${ELF}
    Execute Command    $platform = @${PLATFORM}
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

Get Task Count
    Write Line To Uart    ps; echo task-sample-end
    Wait For Line On Uart    ^\\s*TID\\s+PID\\s+PPID.*COMMAND    treatAsRegex=True
    ${count}=    Set Variable    ${0}
    WHILE    True    limit=32
        ${row}=    Wait For Line On Uart    ^(\\s*\\d+\\s+\\d+\\s+\\d+\\s+|task-sample-end$)    treatAsRegex=True
        IF    $row.Line == 'task-sample-end'
            BREAK
        END
        ${count}=    Evaluate    ${count} + 1
    END
    Wait For Prompt On Uart    nsh>
    Should Be True    ${count} > 0
    RETURN    ${count}

Exercise Tmpfs
    [Arguments]    ${payload}
    Write Line To Uart    echo ${payload} > /tmp/n;cat /tmp/n;rm /tmp/n;echo rc-$?
    Expect Output Line    ${payload}
    Expect Output Line    rc-0
    Wait For Prompt On Uart    nsh>
