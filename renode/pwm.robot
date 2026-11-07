*** Settings ***
Test Setup    Boot PWM NSH

*** Variables ***
${ELF}    ${CURDIR}/../build/stm32c552-pwm/nuttx
${PLATFORM}    ${CURDIR}/stm32c552vet6-devkit-pwm.repl

*** Test Cases ***
PWM Device Is Registered Without Starting The Timer
    Write Line To Uart    ls /dev
    Wait For Line On Uart    ^\\s*pwm0$    treatAsRegex=True
    Wait For Prompt On Uart    nsh>
    ${control}=    Execute Command    sysbus ReadDoubleWord 0x40000000
    ${clock}=    Execute Command    sysbus ReadDoubleWord 0x44020C9C
    Should Be True    (int($control, 16) & 1) == 0
    Should Be True    (int($clock, 16) & 1) == 0

One Hz PWM Has Twenty Five Percent Duty
    Exercise PWM    1    25    5    2.1

One Hundred Hz PWM Has One Percent Duty
    Exercise PWM    100    1    1    0.05

One kHz PWM Has Fifty Percent Duty
    Exercise PWM    1000    50    1    0.02

Ten kHz PWM Has Ninety Nine Percent Duty
    Exercise PWM    10000    99    1    0.01

PWM Can Be Closed And Reopened With New Settings
    Exercise PWM    1000    25    1    0.02
    Exercise PWM    2000    75    1    0.02
    Exercise PWM    1000    50    1    0.02

*** Keywords ***
Boot PWM NSH
    Execute Command    $firmware = @${ELF}
    Execute Command    $platform = @${PLATFORM}
    Execute Command    include @${CURDIR}/boot.resc
    Create Terminal Tester    sysbus.usart1    timeout=6
    Create LED Tester    sysbus.gpioa.pwm_output    defaultTimeout=1
    Start Emulation
    Wait For Line On Uart    NuttShell (NSH)
    Wait For Prompt On Uart    nsh>

Exercise PWM
    [Arguments]    ${frequency}    ${duty}    ${seconds}    ${sample_time}
    Write Line To Uart    pwm -f ${frequency} -d ${duty} -t ${seconds}
    Wait For Line On Uart    pwm_main: starting output with frequency: ${frequency}
    Execute Command    pause
    Execute Command    emulation RunFor "0.010"
    PWM Registers Match    ${frequency}    ${duty}
    ${period}=    Evaluate    1.0 / int($frequency)
    ${on_time}=    Evaluate    $period * int($duty) / 100
    ${off_time}=    Evaluate    $period - $on_time
    Assert LED Is Blinking    testDuration=${sample_time}    onDuration=${on_time}    offDuration=${off_time}    tolerance=0.02    pauseEmulation=true
    Wait For Line On Uart    pwm_main: stopping output
    Wait For Prompt On Uart    nsh>
    PWM Is Stopped

PWM Registers Match
    [Arguments]    ${frequency}    ${duty}
    ${mode}=    Execute Command    sysbus ReadDoubleWord 0x42020000
    ${af}=    Execute Command    sysbus ReadDoubleWord 0x42020020
    ${clock}=    Execute Command    sysbus ReadDoubleWord 0x44020C9C
    ${control}=    Execute Command    sysbus ReadDoubleWord 0x40000000
    ${compare_mode}=    Execute Command    sysbus ReadDoubleWord 0x40000018
    ${enable}=    Execute Command    sysbus ReadDoubleWord 0x40000020
    ${prescaler}=    Execute Command    sysbus ReadDoubleWord 0x40000028
    ${reload}=    Execute Command    sysbus ReadDoubleWord 0x4000002C
    ${compare}=    Execute Command    sysbus ReadDoubleWord 0x40000034
    Should Be True    (int($mode, 16) & 3) == 2
    Should Be True    (int($af, 16) & 15) == 1
    Should Be True    int($clock, 16) & 1
    Should Be True    (int($control, 16) & 0x71) == 1
    # Renode tags OC1PE as unimplemented and reads it back as zero.
    Should Be True    (int($compare_mode, 16) & 0xF7) == 0x60
    Should Be True    (int($enable, 16) & 3) == 1
    ${actual_frequency}=    Evaluate    48000000.0 / (int($prescaler, 16) + 1) / (int($reload, 16) + 1)
    ${actual_duty}=    Evaluate    int($compare, 16) / (int($reload, 16) + 1)
    Should Be True    abs($actual_frequency / int($frequency) - 1) < 0.002
    Should Be True    abs($actual_duty - int($duty) / 100.0) < 0.001

PWM Is Stopped
    Execute Command    pause
    ${control}=    Execute Command    sysbus ReadDoubleWord 0x40000000
    ${enable}=    Execute Command    sysbus ReadDoubleWord 0x40000020
    ${clock}=    Execute Command    sysbus ReadDoubleWord 0x44020C9C
    ${mode}=    Execute Command    sysbus ReadDoubleWord 0x42020000
    Should Be True    (int($control, 16) & 1) == 0
    Should Be True    (int($enable, 16) & 1) == 0
    Should Be True    (int($clock, 16) & 1) == 0
    Should Be True    (int($mode, 16) & 3) == 0
    ${counter_before}=    Execute Command    sysbus ReadDoubleWord 0x40000024
    Execute Command    emulation RunFor "0.020"
    ${counter_after}=    Execute Command    sysbus ReadDoubleWord 0x40000024
    Should Be Equal    ${counter_before}    ${counter_after}
