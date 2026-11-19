*** Settings ***
Test Setup    Boot SPI NSH

*** Variables ***
${ELF}    ${CURDIR}/../build/stm32c552-spi/nuttx
${PLATFORM}    ${CURDIR}/stm32c552vet6-devkit-spi.repl
${KERNEL_HZ}    48000000

*** Test Cases ***
SPI1 Is Registered With Inactive GPIO Chip Select
    Write Line To Uart    ls /dev
    Wait For Line On Uart    ^\\s*spi1$    treatAsRegex=True
    Wait For Prompt On Uart    nsh>
    ${mode}=    Execute Command    sysbus ReadDoubleWord 0x42020000
    ${speed}=    Execute Command    sysbus ReadDoubleWord 0x42020008
    ${af}=    Execute Command    sysbus ReadDoubleWord 0x42020020
    ${output}=    Execute Command    sysbus ReadDoubleWord 0x42020014
    ${gate}=    Execute Command    sysbus ReadDoubleWord 0x44020CA4
    ${source}=    Execute Command    sysbus ReadDoubleWord 0x44020CD8
    ${cfg}=    Execute Command    sysbus ReadDoubleWord 0x4001300C
    ${control}=    Execute Command    sysbus ReadDoubleWord 0x40013000
    Should Be True    ((int($mode, 16) >> 8) & 255) == 0xA9
    Should Be True    ((int($af, 16) >> 20) & 0xFFF) == 0x555
    Should Be True    (int($speed, 16) & 0xCC00) == 0x8800
    Should Be True    int($output, 16) & 16
    Should Be True    int($gate, 16) & (1 << 12)
    Should Be True    ((int($source, 16) >> 16) & 3) == 0
    Should Be True    (int($cfg, 16) & 0x84400000) == 0x84400000
    Should Be True    (int($control, 16) & 0x1001) == 0x1001
    Check Controller Accesses    0    0    0

SPI1 Exchanges More Than One FIFO Of Bytes
    Exchange Pattern    spi exch -b1 -w8 -x20    0011FF807E55AA1234DEADBEEF01998877443322    1
    Check Controller Accesses    20    0    0

SPI1 Exchanges Sixteen Bit Frames Without Packing Or Truncation
    Exchange Pattern    spi exch -w16 -x10    0011FF807E55AA1234DEADBEEF01998877443322    2
    Check Controller Accesses    0    10    0

SPI1 Exchanges Thirty Two Bit Frames Without Truncation
    Exchange Pattern    spi exch -w32 -x5    0011FF807E55AA1234DEADBEEF01998877443322    4
    Check Controller Accesses    0    0    5

SPI1 Applies All Four Clock Modes Across Reopen
    FOR    ${mode}    IN RANGE    4
        Exchange Pattern    spi exch -m${mode} -x4    12345678    1
        ${cfg}=    Execute Command    sysbus ReadDoubleWord 0x4001300C
        Should Be True    ((int($cfg, 16) >> 24) & 3) == int($mode)
    END
    Check Controller Accesses    16    0    0

SPI1 Selects A Prescaler And Caps Requests At Twenty Four MHz
    FOR    ${frequency}    IN    100000    187500    1000000    12000000    24000000    48000000
        ${prescaler}=    Evaluate    next((shift - 1 for shift in range(1, 8) if min(${frequency}, 24000000) >= (${KERNEL_HZ} >> shift)), 7) if min(${frequency}, 24000000) < ${KERNEL_HZ} else 0
        Exchange Pattern    spi exch -f${frequency} -x4    0012ABFF    1
        ${cfg}=    Execute Command    sysbus ReadDoubleWord 0x40013008
        Should Be True    ((int($cfg, 16) >> 28) & 7) == int($prescaler)
        Should Be True    (int($cfg, 16) & (1 << 31)) == 0
    END
    Check Controller Accesses    24    0    0

SPI1 Toggles GPIO Chip Select Between Three Transfers
    Exchange Pattern    spi exch -x4 -r3    1234567889ABCDEF10FF0080    1    transfers=3
    ${selects}=    Execute Command    sysbus.spi1.target Selects
    ${deselects}=    Execute Command    sysbus.spi1.target Deselects
    ${suspends}=    Execute Command    sysbus.spi1.target SuspendNotifications
    Should Be Equal As Integers    ${selects}    3
    Should Be Equal As Integers    ${deselects}    3
    Should Be Equal As Integers    ${suspends}    3
    Check Controller Accesses    12    0    0

SPI1 Keeps Unknown Chip Select Inactive And Resumes User Zero
    Write Line To Uart    spi exch -n1 -x4 12345678
    Wait For Line On Uart    Received:\\s+FF FF FF FF    treatAsRegex=True
    Wait For Prompt On Uart    nsh>
    ${selects}=    Execute Command    sysbus.spi1.target Selects
    ${unselected}=    Execute Command    sysbus.spi1.target UnselectedBytes
    Should Be Equal As Integers    ${selects}    0
    Should Be Equal As Integers    ${unselected}    4
    Execute Command    sysbus.spi1.target ClearTrace
    Exchange Pattern    spi exch -n0 -x4    12345678    1
    Check Controller Accesses    8    0    0

SPI1 Returns When Receive Stays Empty And Completes The Next Exchange
    Execute Command    sysbus.spi1 SuppressReceive true
    Write Line To Uart    spi exch -x4 -r2 1234567889ABCDEF
    Wait For Prompt On Uart    nsh>    timeout=2
    ${selects}=    Execute Command    sysbus.spi1.target Selects
    ${deselects}=    Execute Command    sysbus.spi1.target Deselects
    Should Be Equal As Integers    ${selects}    1
    Should Be Equal As Integers    ${deselects}    1
    Execute Command    sysbus.spi1 SuppressReceive false
    Exchange Pattern    spi exch -x4 -r1    12345678    1

SPI1 Completes A Zero Length Exchange And Remains Usable
    Write Line To Uart    spi exch -x0
    Wait For Prompt On Uart    nsh>
    ${bytes}=    Execute Command    sysbus.spi1.target Bytes
    Should Be Empty    ${bytes.strip('" \r\n')}
    Exchange Pattern    spi exch -x4    12345678    1
    Check Controller Accesses    4    0    0

*** Keywords ***
Boot SPI NSH
    Execute Command    $firmware=@${ELF}
    Execute Command    $platform=@${PLATFORM}
    Execute Command    include @${CURDIR}/boot.resc
    Create Terminal Tester    sysbus.usart1    timeout=3
    Start Emulation
    Wait For Line On Uart    NuttShell (NSH)
    Wait For Prompt On Uart    nsh>
    Execute Command    sysbus.spi1.target ClearTrace

Exchange Pattern
    [Arguments]    ${command}    ${hexdata}    ${width}    ${transfers}=1
    # The tool fills a little endian host buffer. SPI sends each frame MSB first.
    ${wire}=    Evaluate    (lambda data, width: b''.join(data[i:i+width][::-1] for i in range(0, len(data), width)))(bytes.fromhex($hexdata), int($width))
    ${chunk}=    Evaluate    len($wire) // int($transfers)
    ${response}=    Evaluate    (lambda wire, chunk: bytes(v ^ (0x3C if i % chunk == 0 else wire[i-1]) ^ 0xA5 for i, v in enumerate(wire)))($wire, int($chunk))
    ${expected}=    Evaluate    (lambda response, width: r'Received:\\s+' + ' '.join(response[i:i+width].hex().upper() for i in range(0, len(response), width)))($response, int($width))
    Execute Command    sysbus.spi1.target ClearTrace
    Write Line To Uart    ${command} ${hexdata}
    Wait For Line On Uart    ${expected}    treatAsRegex=True
    Wait For Prompt On Uart    nsh>
    ${bytes}=    Execute Command    sysbus.spi1.target Bytes
    Should Contain    ${bytes}    ${wire.hex().upper()}
    ${unselected}=    Execute Command    sysbus.spi1.target UnselectedBytes
    Should Be Equal As Integers    ${unselected}    0
    ${output}=    Execute Command    sysbus ReadDoubleWord 0x42020014
    Should Be True    int($output, 16) & 16

Check Controller Accesses
    [Arguments]    ${byte_writes}    ${word_writes}    ${dword_writes}
    ${bytes}=    Execute Command    sysbus.spi1 ByteWrites
    ${words}=    Execute Command    sysbus.spi1 WordWrites
    ${dwords}=    Execute Command    sysbus.spi1 DoubleWordWrites
    ${maximum}=    Execute Command    sysbus.spi1 MaxPending
    ${errors}=    Execute Command    sysbus.spi1 AccessErrors
    ${unsafe}=    Execute Command    sysbus.spi1 UnsafeConfigWrites
    Should Be Equal As Integers    ${bytes}    ${byte_writes}
    Should Be Equal As Integers    ${words}    ${word_writes}
    Should Be Equal As Integers    ${dwords}    ${dword_writes}
    Should Be True    0 <= int($maximum, 0) <= 16
    Should Be Equal As Integers    ${errors}    0
    Should Be Equal As Integers    ${unsafe}    0
