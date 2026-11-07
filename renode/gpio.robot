*** Settings ***
Test Setup    Boot NSH

*** Variables ***
${ELF}    ${CURDIR}/../build/stm32c552/nuttx
${PLATFORM}    ${CURDIR}/stm32c552vet6-devkit.repl

*** Test Cases ***
PH3 User LED Starts Off And Can Be Toggled
    Write Line To Uart    ls /dev
    Wait For Line On Uart    ^\\s*userleds$    treatAsRegex=True
    Wait For Prompt On Uart    nsh>
    Create LED Tester    sysbus.gpioh.user_led    defaultTimeout=1
    Assert LED State    false    timeout=0
    Write Line To Uart    leds
    Wait For Line On Uart    Supported LEDs 0x01
    Assert LED State    true
    Assert LED State    false

PC13 Button Delivers Press And Release Interrupts
    Write Line To Uart    ls /dev
    Wait For Line On Uart    ^\\s*buttons$    treatAsRegex=True
    Wait For Prompt On Uart    nsh>
    Write Line To Uart    buttons
    Wait For Line On Uart    Supported BUTTONs 0x01
    Wait Until Keyword Succeeds    1s    20ms    PC13 Interrupt Is Configured
    Repeat Keyword    2 times    Press And Release Button

*** Keywords ***
Boot NSH
    Execute Command    $firmware = @${ELF}
    Execute Command    $platform = @${PLATFORM}
    Execute Command    include @${CURDIR}/boot.resc
    Create Terminal Tester    sysbus.usart1    timeout=2
    Start Emulation
    Wait For Line On Uart    NuttShell (NSH)
    Wait For Prompt On Uart    nsh>

PC13 Interrupt Is Configured
    ${mode}=    Execute Command    sysbus ReadDoubleWord 0x42020800
    ${pull}=    Execute Command    sysbus ReadDoubleWord 0x4202080C
    ${rising}=    Execute Command    sysbus ReadDoubleWord 0x44022000
    ${falling}=    Execute Command    sysbus ReadDoubleWord 0x44022004
    ${source}=    Execute Command    sysbus ReadDoubleWord 0x4402206C
    ${nvic}=    Execute Command    sysbus ReadDoubleWord 0xE000E100
    Should Be True    ((int($mode, 16) >> 26) & 3) == 0
    Should Be True    ((int($pull, 16) >> 26) & 3) == 1
    Should Be True    int($rising, 16) & (1 << 13)
    Should Be True    int($falling, 16) & (1 << 13)
    Should Be True    ((int($source, 16) >> 8) & 0xFF) == 2
    Should Be True    int($nvic, 16) & (1 << 20)

Press And Release Button
    Button Reports    Press    1
    Button Reports    Release    0

Button Reports
    [Arguments]    ${action}    ${sample}
    Execute Command    sysbus.gpioc.user_button ${action}
    Wait For Line On Uart    Sample = ${sample}$    treatAsRegex=True
    # Let the example's post-notification sleep finish before the next edge.
    Execute Command    pause
    Execute Command    emulation RunFor "0.030"
