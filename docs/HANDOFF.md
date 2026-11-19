# STM32C552VET6 DevKit Core 交接文档

更新时间为 2026-11-19。工作目录为 `/Users/pzmpdm/WorkSpace/Embedded_Project/NuttX/STM32C552`。

## 当前状态

前三阶段的仿真已完成启动和 NSH、板载 GPIO、SRAM2 和高速时钟。第四阶段已完成 TIM2_CH1 PWM（PA0/H2.3）、USART2（PA2/PA3，H2.1/H2.6）、I²C1（PB8/PB9，H3.21/H3.20）、SPI1（PA5/PA6/PA7，PA4 片选）、ADC1_IN8（PC0/H3.14）和 LPDMA 六个子项。仿真能做的 USB 设备与会复位 CPU 的 IWDG 也已完成。实体板验收待连接 SWD 探针与 3.3 V USB 转串口。

| 配置 | 用途 | Renode 结果 |
|---|---|---|
| `stm32c552vet6-devkit:nsh` | 48 MHz HSIDIV3、64 KiB SRAM1、USART1、LED、按键、tmpfs | 8 项通过 |
| `stm32c552vet6-devkit:nsh-sram2` | 保持 48 MHz，将清零后的 64 KiB SRAM2 注册为第二堆区，带 ramtest | CMake 和 Make 各 10 项通过 |
| `stm32c552vet6-devkit:nsh-hse` | 8 MHz HSE 驱动 144 MHz PSI，超时回退至 144 MHz HSIS，并锁存 CK48 | Renode 5 项时钟测试通过 |
| `stm32c552vet6-devkit:nsh-pwm` | 48 MHz、SRAM1，新增 PA0 TIM2_CH1 `/dev/pwm0` | CMake 和 Make 各 14 项通过，含六项 PWM 与八项 NSH/GPIO |
| `stm32c552vet6-devkit:nsh-uart` | 在 PWM 配置上新增 USART2 `/dev/ttyS1`、termios 与 stty | CMake 和 Make 各 19 项通过，新增五项串口测试 |
| `stm32c552vet6-devkit:nsh-i2c` | 在 UART/PWM 配置上新增 I²C1 `/dev/i2c1` 与 i2c 工具，NSH 参数上限 12 | CMake 和 Make 各 27 项通过，新增八项 I²C 测试 |
| `stm32c552vet6-devkit:nsh-spi` | 在 I²C/UART/PWM 配置上新增 SPI1 `/dev/spi1`、标准 spi 工具、8/16/32 位轮询交换与 GPIO CS | CMake 和 Make 各 36 项通过，新增九项 SPI 测试 |
| `stm32c552vet6-devkit:nsh-adc` | 在 SPI 配置上新增 ADC1_IN8 `/dev/adc0`、标准 adc 示例与 12 位单次采样 | CMake 和 Make 各 43 项通过，新增七项 ADC 测试 |
| `stm32c552vet6-devkit:nsh-lpdma` | 两个 LPDMA 实例、启动内存自检及 ADC1 四样本采集 | CMake 和 Make 各 44 项通过，新增八项 DMA 测试 |
| `stm32c552vet6-devkit:nsh-lpdma-sram2` | 同一外设集保持 48 MHz，并加入清零后的 SRAM2 堆 | Renode 46 项通过，含 SRAM2 分配测试 |
| `stm32c552vet6-devkit:nsh-lpdma-hse` | 同一外设集走 144 MHz，失败时回退 HSIS | Renode 48 项通过，含四项时钟测试 |
| `stm32c552vet6-devkit:nsh-usb` | 48 MHz NSH，USART1 仍是控制台，CDC ACM 为 `/dev/ttyACM0` | `usb.robot` 1 项通过 |
| `stm32c552vet6-devkit:nsh-ostest` | 48 MHz NSH，SRAM2 堆，运行上游 `ostest` | `ostest.robot` 1 项通过，退出状态 0 |

默认配置中 SRAM1 从 `0x20000000` 开始，SRAM2 从 `0x20010000` 开始。Flash 为 `0x08000000` 起的 512 KiB。静态数据和初始堆留在 SRAM1。

## 仓库和提交

项目根目录与 `nuttx/` 是独立的 Git 仓库，两者的工作分支均为 `stm32c552vet6-devkit`。根仓库跟踪文档和 Renode 测试，忽略 `nuttx/`、`apps/`、`build/`、`.venv/`。原始 PADS ZIP 保持为用户提供的未跟踪资料。阶段完成后需要在相应仓库本地提交。

| 仓库 | 关键提交 |
|---|---|
| `nuttx/` | `c58ec414` 初始板级移植，`336d3854` tmpfs，`a838abd0` 用户 LED 与按键，`cf0d9f10` SRAM2，`bc24ef0c` 144 MHz 与回退，`83519d96` TIM2 PWM，`31a24fec` USART2，`f2d061f7` I²C1，`1bb4a68e` SPI1，`ec9aea59` ADC 打开失败恢复，`5bcb29fe` ADC1，`ea017765` LPDMA 和 ADC1 批量采样 |
| 根目录 | `20a31e5` 首轮回归，`299212c` 文件和脚本，`da7bc50` 六阶段计划与 GPIO，`5c16b7c` SRAM2 测试，`c5adf05` 高速时钟测试，`b340157` 首版交接文档，`1917a46` PWM 测试，`643f563` USART2 测试，`5d85238` I²C 测试及统一平台选择，`c80d515` SPI 测试。`e706fdb` ADC 测试和 USART2 回环节拍。当前提交加入 LPDMA 测试 |
| `apps/` | 基线 `d14111ebeff7e8eb0512e63238883dece6842c05` |
| NuttX 上游基线 | `9ffe7625cb187004cf209f113b3cd96472c92ab2` |

## 硬件与接口

- USART1 控制台为 115200 8N1。PA9/TX 为 H4.4，PA10/RX 为 H4.6，需共地。
- 用户 LED2 在 PH3，低电平点亮，设备为 `/dev/userleds`，NSH 命令为 `leds`。
- 用户按键 SW2 在 PC13，内部上拉，低电平按下，设备为 `/dev/buttons`，NSH 命令为 `buttons`。
- PWM 为 PA0 AF1（H2.3），设备为 `/dev/pwm0`。`pwm -f 1000 -d 50 -t 5` 输出五秒 PWM，结束后 PA0 回到浮空输入。详细接口和测试见 [PWM 记录](PWM.md)。
- USART2 TX 为 PA2 AF7（H2.1），RX 为 PA3 AF7（H2.6），设备 `/dev/ttyS1`。默认 115200 8N1，无流控及 DMA，用 `stty` 设置 raw 模式。详细测试及限制见 [USART2 记录](UART.md)。
- I²C1 SCL 为 PB8 AF4（H3.21），SDA 为 PB9 AF4（H3.20），设备 `/dev/i2c1`。需要外部 3.3 V 上拉。100/400 kHz 档位支持 48 和 144 MHz 内核时钟，实际线速待测。详见 [I²C1 记录](I2C.md)。
- SPI1 SCK PA5 / MISO PA6 / MOSI PA7 AF5（H2.8/H2.7/H2.10），PA4（H2.5）为低有效 GPIO CS，设备 `/dev/spi1`。当前为 48 MHz 内核、MSB 优先、轮询全双工；SCK 请求上限 24 MHz，最低档 187.5 kHz。见 [SPI1 记录](SPI.md)。
- ADC1_IN8 为 PC0（H3.14），设备 `/dev/adc0`，内核时钟 12 MHz，12 位软件触发与 EOC 中断。`adc -n1` 输出通道号和原始码值。详见 [ADC1 记录](ADC.md)。
- LPDMA1/2 共 12 个通道。`nsh-lpdma` 启动时自检内存搬运，`adc -n1` 通过 LPDMA1 采集四个 IN8 样本。见 [LPDMA 记录](LPDMA.md)。
- 板载 HSE 为 8 MHz，LSE 为 32.768 kHz。ES0661 指出 LQFP 封装上 PC13 跳变可能干扰 LSE。RTC 需评估 LSI，或另建停用 PC13 按键的 LSE 配置。
- USB-C 数据线直接接 MCU USB FS，CDC ACM 适配属于第五阶段。

排针候选、完整阶段顺序和剩余验收见 [六阶段计划](superpowers/plans/2026-11-06-stm32c552-board-port.md)。

## 构建与测试

当前环境为 Arm GNU Toolchain 15.2.Rel1、CMake/Ninja、Renode 1.17.0、Robot Framework 6.1。Python 依赖在 `.venv/`。

```sh
. .venv/bin/activate
RENODE_HOME=/Applications/Renode.app/Contents/MacOS
cmake -S nuttx -B build/stm32c552 -G Ninja \
  -DBOARD_CONFIG=stm32c552vet6-devkit:nsh
cmake --build build/stm32c552
mkdir -p build/board-gpio-cmake
(cd build/board-gpio-cmake && "$RENODE_HOME/renode-test" \
  ../../renode/nsh.robot ../../renode/nsh-regression.robot ../../renode/gpio.robot)
```

CMake 已有目录会保留展开后的 `.config`。换配置时使用新的构建目录。验证其他 ELF 时通过 `--variable ELF:/absolute/path/to/nuttx` 传入。

- SRAM2 使用 `build/stm32c552-sram2/`，运行上述三份测试及 `renode/sram2.robot`，全部指向 SRAM2 ELF。
- 高速时钟使用 `build/stm32c552-hse/`，运行 `renode/clock.robot`。该套件加载 144 MHz 模型。
- PWM 使用 `build/stm32c552-pwm/`，运行 `nsh.robot`、`nsh-regression.robot`、`gpio.robot`、`pwm.robot`，均指定 PWM ELF。构建和复现命令见 [PWM 记录](PWM.md)。
- USART2 使用 `build/stm32c552-uart/`，在上述四套测试上增加 `uart.robot`，均指定 UART ELF，见 [USART2 记录](UART.md)。该配置已同时验收 PWM。高速/SRAM2 与这两个外设的组合尚未验收。
- I²C 使用 `build/stm32c552-i2c/`，再增加 `i2c.robot`，统一指定 I²C ELF 和 `PLATFORM` 为 `renode/stm32c552vet6-devkit-i2c.repl` 的绝对路径。已同时验收 UART/PWM，见 [I²C1 记录](I2C.md)。高速/SRAM2 与这些外设的组合尚未验收。
- SPI 使用 `build/stm32c552-spi/`，运行前述六套测试及 `spi.robot`，统一指定 SPI ELF 和 `renode/stm32c552vet6-devkit-spi.repl`。详见 [SPI1 记录](SPI.md)。已同时验收 NSH/GPIO/PWM/UART/I²C；HSE/SRAM2 组合仍未验收。
- ADC 使用 `build/stm32c552-adc/`，运行前述七套测试及 `adc.robot`，统一指定 ADC ELF 和 `renode/stm32c552vet6-devkit-adc.repl`。复现见 [ADC1 记录](ADC.md)。
- LPDMA 使用 `build/stm32c552-lpdma/`，运行 NSH/GPIO/PWM/UART/I²C/SPI 和 `lpdma.robot`，指定 LPDMA ELF 与 `stm32c552vet6-devkit-lpdma.repl`。ADC 中断版另跑 43 项，见 [LPDMA 记录](LPDMA.md)。
- GNU Make 在独立临时 checkout 中运行 `tools/configure.sh -m -a ../apps BOARD:CONFIG`，再 `make -jN`。本机缺省 PATH 的补充工具位于 `build/host-tools/`，含 kconfig-tweak 与 flock。
- 手动控制台使用 `renode renode/interactive.resc`。
- 真机编号命令测试使用 `tools/check-nsh-serial.py`，用法及烧录命令见 [README](../README.md)。

## 验证证据和限制

| 证据 | 路径 |
|---|---|
| 最新基线与内存专项回归 | `build/board-default-adc/report.html`，默认 NSH 八项及 SRAM2 专项两项通过 |
| SRAM2 CMake / Make | `build/board-sram2/report.html`、`build/board-sram2-make/report.html` |
| 时钟 CMake / Make | `build/board-clock/report.html`、`build/board-clock-make/report.html` |
| PWM CMake / Make | `build/board-pwm-final-cmake/report.html`、`build/board-pwm-final-make/report.html`，各 14 项通过 |
| USART2 CMake / Make | `build/board-uart-final-cmake/report.html`、`build/board-uart-final-make/report.html`，各 19 项通过 |
| I²C CMake / Make | `build/board-i2c-final-cmake/report.html`、`build/board-i2c-final-make/report.html`，各 27 项通过 |
| SPI CMake / Make | `build/board-spi-final-cmake/report.html`、`build/board-spi-final-make/report.html`，各 36 项通过 |
| ADC CMake / Make | `build/board-adc-final-cmake/report.html`、`build/board-adc-final-make/report.html`，各 43 项通过 |
| LPDMA CMake / Make | `build/board-lpdma-final-cmake/report.html`、`build/board-lpdma-final-make/report.html`，各 44 项通过 |
| ADC 中断版回归 | `build/board-lpdma-final-adc/report.html`，43 项通过 |

- RCC 门控以寄存器存储建模。高速时钟模型模拟就绪位和切换状态，并可注入 HSE、PSI、切换和 CK48 分频器就绪超时。CK48SEL 只在 PSIDIV3 或 HSIDIV3 就绪时锁存，HSE 不作为 48 MHz 来源。UART 和 SysTick 仍是标称频率，这不是对 48 MHz 的测量。
- UART 复用 STM32F7 模型，其 FIFO 使能位会被忽略。
- USART2 采用按 115200 8N1 帧间隔回送的字符级回环，PA2/PA3 AF7 单独检查寄存器。4 KiB 数据覆盖全部字节值及软件缓冲周转。三组波特率在关闭重开后核对，未验收端口保持打开时的在线改速、C5 FIFO/溢出/噪声及实际线速。
- EXTI 复用 STM32WBA 模型，验证引脚路由、边沿和 NuttX 回调。C552 屏蔽与挂起寄存器的硬件语义仍待实测。
- SRAM2 模型验证初始化内容、地址、分配和释放。ECC 检测、纠错与真实复位条件需实体板确认。
- SRAM2 配置保留当前 option-byte 的 ECC 设置，用对齐的整字写入初始化。尚未实测 ECC 错误中断与错误地址勘误。
- 当前 NSH 行缓冲为 64 字节，单段处理 63 个字符，余下字符会成为下一段输入。
- 高速配置当前不支持电源管理，HSIS 回退维持标称 144 MHz。若两条高速路径均失败，启动会停在时钟初始化处。
- PWM 基于 Renode STM32_Timer，经 AF1 路由至 PA0。`STM32C5_TIM2.cs` 补齐 UG 装载 ARR 的行为。OC1PE 和首次输出相位仍有模型限制，频率有一个计数 tick 的差异，未验证无毛刺在线更新或 PWM 中断/DMA。
- I²C 使用修正的 Renode F7 控制器模型及可写寄存器从设备，验证消息、重复起始、RELOAD、NACK 和故障恢复。GPIO 开漏、TIMINGR、滤波与实际总线波形未被模型模拟，采用被动写入记录检查配置。BERR 勘误通过模型注入验证。外部上拉、线速及电气时序待真机确认。
- SPI 复用 Renode CFG1/CFG2 控制器，补齐配置读回和宽帧 MSB 字节顺序。动态从设备受 PA4 GPIO CS 控制；检查访问位宽、16 字节 FIFO 余量及配置写入时机。接收标志被模型压住时，轮询在 1000 次读之内返回 `ETIMEDOUT`，放开后下一次交换仍成功。原模型 FIFO 无限长，这不是 SCK、溢出或线速验收。SPI_SEND 仍未单独验收。
- ADC 模型使用可变电压和理想 3.3 V 参考，覆盖转换结果、重复触发、IRQ 送数及稳压器/校准/就绪故障恢复。采样时间由寄存器检查，实际参考电压、精度、噪声和转换时序等待实板测量。
- LPDMA 模型按真实地址搬运数据，验证 12 通道、ADC 请求和完成中断，以及错误、超时后恢复。`nsh-lpdma-sram2` 从 SRAM2 堆分配自检缓冲。固件验证搬运内容和两端哨兵，自行释放后 `fordblks` 回到分配前并启动 NSH。总线仲裁、速度和低功耗仍待实板。
- USB 复用现有 M0 V2 设备控制器。分组内存按真实地址读写。脚本主机完成复位、SETUP 设备描述符、SET_ADDRESS、SET_CONFIGURATION，以及 CDC 的批量 IN/OUT。ES0661 的完成中断可以先于最后一次分组内存写入；驱动在读之前等 2 µs，提前读会计入 `EarlyReads`。这项通过时 `EarlyReads` 为 0。它不代表 PHY、chirp、VBUS 或线速。
- IWDG 使用名义 32 kHz 和 /256 分频。停止喂狗后机器复位，NSH 提示符再次出现；在超时前反复写入重载键则不复位，已有的 tmpfs 文件还在。这不是实测的 LSI，模型也不记录复位原因标志。
- 实物尚待烧录读回、反复冷启动、NRST、时钟测量、波形验证和 30 分钟运行。

## 接续工作

`nsh-lpdma` 已分别叠到 SRAM2 和 144 MHz。中断版 `adc.robot` 用于 `nsh-adc`，LPDMA 配置每次触发搬四个样本，使用 `lpdma.robot` 验收。144 MHz 下 I²C 调整了 TIMINGR 的 PRESC，SPI 保留 24 MHz SCK 请求上限。两条总线的线速仍待上板测量。

SPI 轮询超时已在 48 MHz 和 144 MHz 的 LPDMA 镜像上通过，各 10 项。LPDMA 自检缓冲已放到 SRAM2 堆上，原有 8 项加 1 项地址和释放检查通过。CK48 选择、分频器就绪和超时已在 `clock.robot` 通过，共 5 项，USART1 分频仍按 144 MHz 验收。

`nsh-usb` 的 CDC ACM 已在寄存器级模型上通过：描述符来自分组内存，批量 OUT 在 ES0661 延迟之后进入 `/dev/ttyACM0`，批量 IN 能从分组内存读回，控制台仍是 USART1。接入 USB 类型之后，LPDMA 栈 46 项通过；ADC 中断栈按当前源重新编译后 44 项通过，其中 7 项仍是原来的单样本中断验收。

IWDG 会真正复位仿真里的 Cortex-M。停止喂狗后 NSH 重新出现；持续喂狗则当前 shell 和 tmpfs 文件都还在。仿真计划里能做的项到这里结束。实机烧录和计划里先不做的项继续不做。

`nsh-ostest` 在同一套 Renode 上跑完上游 ostest，退出状态为 0。验收看的是结束前没有 `ERROR` 或 `Assertion failed`，然后出现 `ostest_main: Exiting with status 0`。镜像使用已有的 SRAM2 堆，静态占用仍在 SRAM1。这覆盖调度、互斥、信号、POSIX 定时器、消息队列、FPU 上下文和轮转；工作队列子项没有打开。它不测量硬件时钟。

GNU Make 原先把 M0 V2 USB 驱动放在仅 Cortex-M0 的源文件列表里，C552 是 Cortex-M33，Make 镜像因此没编进这只驱动。源文件改到与 CMake 相同的公共位置后，Make 构建的 `nsh-usb` 在 `usb.robot` 通过：批量 OUT 前先暂停并推进 20 ms，使 ES0661 的分组写完再读控制台。`EarlyReads` 为 0，`DelayedPackets` 为 1。同一次中断前，这份 Make 镜像的 IWDG 两项已经通过，没有重跑。
