*** Settings ***
Test Setup    Boot I2C NSH

*** Variables ***
${ELF}    ${CURDIR}/../build/stm32c552-i2c/nuttx
${PLATFORM}    ${CURDIR}/stm32c552vet6-devkit-i2c.repl
${KERNEL_HZ}    48000000

*** Test Cases ***
I2C1 Is Registered
    Write Line To Uart    ls /dev
    Wait For Line On Uart    ^\\s*i2c1$    treatAsRegex=True
    Wait For Prompt On Uart    nsh>
    ${mode}=    Execute Command    sysbus ReadDoubleWord 0x42020400
    ${af}=    Execute Command    sysbus ReadDoubleWord 0x42020424
    ${pull}=    Execute Command    sysbus ReadDoubleWord 0x4202040C
    ${gate}=    Execute Command    sysbus ReadDoubleWord 0x44020C9C
    ${source}=    Execute Command    sysbus ReadDoubleWord 0x44020CDC
    ${nvic}=    Execute Command    sysbus ReadDoubleWord 0xE000E104
    ${od}=    Execute Command    sysbus.i2c1.register_memory OpenDrainWritten
    ${timing}=    Execute Command    sysbus.i2c1.register_memory LastTiming
    ${filter}=    Execute Command    sysbus.i2c1.register_memory AnalogDisableWritten
    ${unsafe}=    Execute Command    sysbus.i2c1.register_memory TimingWhileEnabled
    Should Be True    ((int($mode, 16) >> 16) & 15) == 10
    Should Be True    (int($af, 16) & 255) == 0x44
    Should Be True    ((int($pull, 16) >> 16) & 15) == 0
    Should Be True    int($gate, 16) & (1 << 21)
    Should Be True    (int($source, 16) & 3) == 0
    Should Be True    (int($nvic, 16) & 0x3000) == 0x3000
    Should Be Equal As Integers    ${od}    0x300
    ${expected}=    Evaluate    0x80814F4F if int(${KERNEL_HZ}) == 144000000 else 0x20814F4F
    Should Be Equal As Integers    ${timing}    ${expected}
    Should Contain    ${filter}    True
    Should Be Equal As Integers    ${unsafe}    0

I2C1 Reads And Writes A Register
    Execute Command    sysbus.i2c1.register_memory ClearTrace
    Run I2C Command    i2c get -b1 -a50 -r20 -f100000    Value: ab
    ${starts}=    Execute Command    sysbus.i2c1.register_memory Starts
    ${stops}=    Execute Command    sysbus.i2c1.register_memory StopRequests
    Should Be Equal As Integers    ${starts}    2
    Should Be Equal As Integers    ${stops}    1
    Run I2C Command    i2c set -b1 -a50 -r20 -f100000 a5    Value: a5
    Run I2C Command    i2c get -b1 -a50 -r20 -f100000    Value: a5
    ${value}=    Execute Command    sysbus.i2c1.register_memory GetByte 0x20
    Should Be Equal As Integers    ${value}    0xA5
    ${reload}=    Execute Command    sysbus.i2c1.register_memory ReloadWrites
    Should Be True    int($reload, 0) > 0

I2C1 Reports NACK And Recovers
    # An immediate NACK must complete before the 500 ms bus timeout.
    Run I2C Command    i2c get -b1 -a51 -r00 -f100000    Transfer failed: 1    timeout=0.1
    Run I2C Command    i2c get -b1 -a50 -r00 -f100000    Value: 0b

I2C1 Transfers Two Data Bytes At Fast Mode
    Run I2C Command    i2c set -b1 -a50 -r30 -w16 -f400000 beef    Value: beef
    Run I2C Command    i2c get -b1 -a50 -r30 -w16 -f400000    Value: beef
    ${lo}=    Execute Command    sysbus.i2c1.register_memory GetByte 0x30
    ${hi}=    Execute Command    sysbus.i2c1.register_memory GetByte 0x31
    ${timing}=    Execute Command    sysbus.i2c1.register_memory LastTiming
    ${unsafe}=    Execute Command    sysbus.i2c1.register_memory TimingWhileEnabled
    Should Be Equal As Integers    ${lo}    0xEF
    Should Be Equal As Integers    ${hi}    0xBE
    ${expected}=    Evaluate    0x80611214 if int(${KERNEL_HZ}) == 144000000 else 0x20611214
    Should Be Equal As Integers    ${timing}    ${expected}
    Should Be Equal As Integers    ${unsafe}    0

I2C1 Reads Across The 255 Byte Reload Boundary
    Execute Command    sysbus.i2c1.register_memory ClearTrace
    Write Line To Uart    i2c dump -b1 -a50 -r00 -f100000 256
    FOR    ${offset}    IN RANGE    0    256    16
        ${pattern}=    Evaluate    '^%08x[ ]+' % int($offset) + '[ ]+'.join('%02x' % ((i * 37 + 11) & 255) for i in range(int($offset), int($offset) + 16))
        Wait For Line On Uart    ${pattern}    treatAsRegex=True
    END
    Wait For Prompt On Uart    nsh>
    ${reload}=    Execute Command    sysbus.i2c1.register_memory ReloadWrites
    ${read}=    Execute Command    sysbus.i2c1.register_memory ReadBytes
    Should Be True    int($reload, 0) > 0
    Should Be Equal As Integers    ${read}    256

I2C1 Times Out With Its Event IRQ Masked And Recovers
    Execute Command    sysbus.i2c1.register_memory ClearTrace
    Execute Command    sysbus WriteDoubleWord 0xE000E184 0x1000
    Run I2C Command    i2c get -b1 -a50 -r00 -f100000    Transfer failed: 1
    ${stops}=    Execute Command    sysbus.i2c1.register_memory StopRequests
    Should Be Equal As Integers    ${stops}    1
    Execute Command    sysbus WriteDoubleWord 0xE000E104 0x1000
    Run I2C Command    i2c get -b1 -a50 -r00 -f100000    Value: 0b

I2C1 Rejects An Unsupported Frequency And Recovers
    Execute Command    sysbus.i2c1.register_memory ClearTrace
    Run I2C Command    i2c get -b1 -a50 -r00 -f1000000    Transfer failed: 1
    ${starts}=    Execute Command    sysbus.i2c1.register_memory Starts
    Should Be Equal As Integers    ${starts}    0
    Run I2C Command    i2c get -b1 -a50 -r00 -f100000    Value: 0b

I2C1 Clears A Spurious Bus Error And Continues
    Execute Command    sysbus.i2c1 InjectBusErrorOnNextStart true
    Run I2C Command    i2c get -b1 -a50 -r00 -f100000    Value: 0b    timeout=0.1
    ${injected}=    Execute Command    sysbus.i2c1 InjectedBusErrors
    ${cleared}=    Execute Command    sysbus.i2c1 ClearedBusErrors
    Should Be Equal As Integers    ${injected}    1
    Should Be Equal As Integers    ${cleared}    1

*** Keywords ***
Boot I2C NSH
    Execute Command    $firmware = @${ELF}
    Execute Command    $platform = @${PLATFORM}
    Execute Command    include @${CURDIR}/boot.resc
    Execute Command    sysbus AddWatchpointHook 0x40005404 DoubleWord Write "self.Machine['sysbus.i2c1.register_memory'].ObserveControl(value)"
    Execute Command    sysbus AddWatchpointHook 0x40005400 DoubleWord Write "self.Machine['sysbus.i2c1.register_memory'].ObserveConfig(value)"
    Execute Command    sysbus AddWatchpointHook 0x40005410 DoubleWord Write "self.Machine['sysbus.i2c1.register_memory'].ObserveTiming(value)"
    Execute Command    sysbus AddWatchpointHook 0x42020404 DoubleWord Write "self.Machine['sysbus.i2c1.register_memory'].ObserveOutputType(value)"
    Create Terminal Tester    sysbus.usart1    timeout=3
    Start Emulation
    Wait For Line On Uart    NuttShell (NSH)
    Wait For Prompt On Uart    nsh>

Run I2C Command
    [Arguments]    ${command}    ${pattern}    ${timeout}=3
    Write Line To Uart    ${command}
    Wait For Line On Uart    ${pattern}    timeout=${timeout}
    Wait For Prompt On Uart    nsh>
