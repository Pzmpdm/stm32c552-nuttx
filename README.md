# STM32C552VET6 DevKit Core · NuttX NSH

默认板级配置为 `stm32c552vet6-devkit:nsh`。固件从片内 Flash
`0x08000000` 的复位向量启动，沿用芯片复位时的 48 MHz HSIDIV3
系统时钟及总线分频。512 KiB Flash 可用，静态数据、栈和堆均使用
`0x20000000` 起的 64 KiB SRAM1。
板上的 8 MHz HSE 和 32.768 kHz LSE 在此配置中闲置。

串口控制台为 USART1，115200 8N1。原理图的 H4.4（PA9、AF7）是 TX，
H4.6（PA10、AF7）是 RX。连接 3.3 V USB 转串口时交叉连接 TX/RX，并从
板上 GND 共地。USB-C 的数据线连接到 MCU 的 USB 接口。

## 构建和仿真

从本目录运行。需要 CMake、Ninja、`arm-none-eabi-gcc` 和 Renode。
macOS 下面的路径对应当前安装。其他系统将 `RENODE_HOME` 指向含
`renode-test` 和 `tests/requirements.txt` 的 Renode 安装目录。

```sh
RENODE_HOME=/Applications/Renode.app/Contents/MacOS
python3 -m venv .venv
. .venv/bin/activate
python -m pip install kconfiglib==14.1.0 -r "$RENODE_HOME/tests/requirements.txt"

cmake -S nuttx -B build/stm32c552 -G Ninja \
  -DBOARD_CONFIG=stm32c552vet6-devkit:nsh
cmake --build build/stm32c552

mkdir -p build/board-gpio-cmake
(cd build/board-gpio-cmake && "$RENODE_HOME/renode-test" \
  ../../renode/nsh.robot ../../renode/nsh-regression.robot ../../renode/gpio.robot)
```

已有构建目录会保留展开后的 `.config`。修改板级 `defconfig` 后，
使用新的 CMake 构建目录可重新应用默认配置。测试可用
`--variable ELF:/absolute/path/to/nuttx` 指定 ELF。

- 运行 `renode renode/interactive.resc`，在 USART1 分析器输入命令。
- ELF、BIN 和 HEX 镜像位于 `build/stm32c552/`。
- CMake 测试报告位于 `build/board-gpio-cmake/report.html`。

同一配置也通过 GNU Make 构建和同一套 Renode 测试。对应产物与报告位于
`build/stm32c552-gpio-make/` 和 `build/board-gpio-make/report.html`。

Robot 测试确认冷启动提示符，检查 RCC 门控位、PA9/PA10 的 AF7 配置和
USART1 波特率分频，通过 UART 执行 `echo`、`pwd` 和 `sleep 1`。
测试要求 `sleep 1` 用时 0.95–1.10 秒仿真时间，返回提示符后继续执行命令。
回归覆盖退格、CR 和 CRLF、连续命令、`ps`、`free`、`/dev`、`/proc`、
注册应用 `dd`、`/tmp` 的 tmpfs 文件读写和 `sh`。100 轮文件操作测试会
在第 0、50、100 轮比较可用堆和任务数量。
当前行编辑器以 63 字节为一段处理输入，超过的字符进入下一段。串口命令
应保持在这一长度以内。

NSH 中可运行 `leds` 和 `buttons`，分别访问 `/dev/userleds` 和
`/dev/buttons`。GPIO 回归覆盖 PH3 灯灭、点亮、熄灭，及 PC13 低电平
按下和高电平松开的两轮通知。

Renode 平台包含 Cortex-M33、NVIC/SysTick、Flash、SRAM、GPIOA/C/H、
USART1 和 EXTI13。
RCC 使用寄存器存储和固定时钟，UART 使用 Renode 自带的 STM32F7 USART
模型，模型会忽略 C552 的 FIFO 使能位。EXTI 使用 STM32WBA 模型验证引脚
路由、边沿和中断回调。C5 的屏蔽及挂起寄存器语义、按键抖动和串口电气
行为仍需实体板验证。
`BOARD_LOOPSPERMSEC=2400` 按参考板的系统时钟比例取值，忙等待延时还需
在实体板校准。

## SRAM2 和 144 MHz 配置

两个配置分别验证内存和时钟。默认 `nsh` 可继续作为 48 MHz 调试基线。

| 配置 | 功能与仿真验收 |
|---|---|
| `stm32c552vet6-devkit:nsh-sram2` | 保持 48 MHz，启动时打开 SRAM2 门控并以对齐的 32 位写入清零，将 `0x20010000` 起的 64 KiB 加入独立堆区。测试覆盖冷启动、复位、60,000 字节的 32 位及 8 位读写和释放。CMake 与 Make 各通过 10 项测试。 |
| `stm32c552vet6-devkit:nsh-hse` | 从板载 8 MHz HSE 驱动 144 MHz PSI。HSE 就绪、PSI 就绪或系统时钟切换超时时回退至标称 144 MHz HSIS。测试核对 Flash 等待状态、系统时钟状态、USART1 分频及 `sleep 1`。CMake 与 Make 各通过 4 项时钟测试。 |

从工程根目录构建并复跑 SRAM2：

```sh
cmake -S nuttx -B build/stm32c552-sram2 -G Ninja \
  -DBOARD_CONFIG=stm32c552vet6-devkit:nsh-sram2
cmake --build build/stm32c552-sram2
mkdir -p build/board-sram2
sram_elf="$PWD/build/stm32c552-sram2/nuttx"
(cd build/board-sram2 && "$RENODE_HOME/renode-test" \
  ../../renode/nsh.robot ../../renode/nsh-regression.robot \
  ../../renode/gpio.robot ../../renode/sram2.robot \
  --variable ELF:"$sram_elf")
```

复跑高速时钟：

```sh
cmake -S nuttx -B build/stm32c552-hse -G Ninja \
  -DBOARD_CONFIG=stm32c552vet6-devkit:nsh-hse
cmake --build build/stm32c552-hse
mkdir -p build/board-clock
(cd build/board-clock && "$RENODE_HOME/renode-test" ../../renode/clock.robot)
```

SRAM2 仿真验证内存内容和分配，ECC 硬件行为仍需真机测试。时钟模型用固定
144 MHz 驱动 UART 和 SysTick，并注入寄存器级超时。晶振起振、频率和
Flash 时序仍需真机验证。LSE/RTC 单列后续，ES0661 指出 LQFP 上的 PC13
跳变可能影响 LSE，因此需评估 RTC 使用 LSI 或另建停用 PC13 按键的 LSE
配置。[ST AN5342](https://www.st.com/content/st_com/en/technical-documents/an5342--how-to-use-error-correction-code-ecc-management-for-internal-memories-protection-on-stm32-mcus-stmicroelectronics_asset/chunk-001-topic-an5342-ecc-overview.html) · [ST ES0661](https://www.st.com/content/st_com/en/technical-documents/es0661-stm32c551xx552xx562xx-device-errata-stmicroelectronics_asset/chunk-001-topic-es-description.html)

## TIM2 PWM 配置

`stm32c552vet6-devkit:nsh-pwm` 新增 `/dev/pwm0`。TIM2_CH1 使用 PA0 AF1，
对应 H2.3。NSH 中运行 `pwm -f 1000 -d 50 -t 5`，输出五秒 1 kHz、50%
PWM。该配置使用 48 MHz、SRAM1，并保留控制台、LED、按键和 tmpfs。

CMake 和 GNU Make 固件各通过 14 项 Renode 测试，覆盖所选的 1 Hz～10 kHz、
1%～99% 占空比测试点、停止、重新打开及 NSH/GPIO 回归。仿真补齐了原
STM32_Timer 模型的 UG 周期装载行为，PA0 边沿通过 GPIO AF1 路由测量。
预装载细节、首次输出相位和实板波形仍待验证。构建命令、报告位置与模型
限制见 [PWM 记录](docs/PWM.md)。当前状态与接续任务见 [交接文档](docs/HANDOFF.md)。

## USART2 配置

`stm32c552vet6-devkit:nsh-uart` 在 PWM 配置上新增 USART2 `/dev/ttyS1`，
TX 为 PA2 AF7（H2.1），RX 为 PA3 AF7（H2.6），USART1 保持 NSH 控制台。
用 `stty -F /dev/ttyS1 raw speed 115200` 设置二进制收发模式。

CMake 和 GNU Make 固件各通过 19 项 Renode 测试，包含 4 KiB 二进制收发、
TX/RX 回环、9600/115200/921600 三组波特率及 NSH/GPIO/PWM 回归。
测试波特率由稳定后的寄存器计算，尚需实板核对线速、FIFO 和错误恢复。
构建命令、报告与模型限制见 [USART2 记录](docs/UART.md)。

## I²C1 配置

`stm32c552vet6-devkit:nsh-i2c` 在串口/PWM 配置上新增 `/dev/i2c1` 和
`i2c` 工具。SCL 为 PB8 AF4（H3.21），SDA 为 PB9 AF4（H3.20），实板需要
外部上拉。当前为 48 MHz 内核时钟、7 位地址、中断控制器模式，支持
100/400 kHz 请求档位；实际线速需测量。

CMake 和 GNU Make 固件各通过 27 项 Renode 测试，包含重复起始、连续写入、
跨 255 字节读取、NACK、超时恢复及 ES0661 的 BERR 勘误路径，并保留全部
NSH/GPIO/PWM/UART 回归。完整模型通过 `PLATFORM` 参数传给所有套件。
构建命令、外部上拉要求及模型限制见 [I²C1 记录](docs/I2C.md)。

## SPI1 配置

`stm32c552vet6-devkit:nsh-spi` 保留 I²C/UART/PWM，新增 `/dev/spi1` 和
标准 `spi` 工具。PA5/PA6/PA7 AF5 为 SCK/MISO/MOSI，PA4 为低有效 GPIO CS。
当前 48 MHz 内核、全双工轮询，验收 8/16/32 位及 mode 0–3；SCK 请求
上限为 24 MHz，最低分频档为 187.5 kHz。

CMake 和 GNU Make 各通过 36 项 Renode 测试，包含九项 SPI 和此前所有
NSH/GPIO/PWM/UART/I²C 回归。动态从设备验证双向数据与实际 GPIO 片选，
实际时钟波形仍待真机确认。构建命令、工具载荷限制及模型边界见
[SPI1 记录](docs/SPI.md)。

## ADC1 配置

`stm32c552vet6-devkit:nsh-adc` 新增 `/dev/adc0`，使用 PC0（H3.14）的
ADC1_IN8、12 位单次转换及软件触发。`adc -n1` 读取一个原始码值，
`adc -n32` 在一次打开期间重复采样 32 次。

CMake 和 GNU Make 各通过 43 项 Renode 测试。七项 ADC 专项覆盖已知
输入、重复采样、转换中断及三种初始化超时后的恢复。复现和模型边界
见 [ADC1 记录](docs/ADC.md)。

## LPDMA 配置

`stm32c552vet6-devkit:nsh-lpdma` 增加 LPDMA1/2 内存自检和 ADC1 批量采样。
`adc -n1` 通过 LPDMA1 读取四个 PC0 样本。CMake 和 GNU Make 各通过
44 项 Renode 测试，覆盖 12 个通道的内存搬运、ADC 请求、完成中断与故障恢复。
复现及实板待测项目见 [LPDMA 记录](docs/LPDMA.md)。

## 实体板验收

当前主机未检测到 ST-Link 或外接串口，实体板验收待接线。使用 SWD 连接
目标板，另接 3.3 V USB 转串口。识别到目标后，从工程根目录记录固件散列，
烧录并执行逐字节校验，再复位：

```sh
mkdir -p build/nsh-hardware
shasum -a 256 build/stm32c552/nuttx.bin >build/nsh-hardware/firmware.sha256
set -o pipefail
STM32_Programmer_CLI -c port=SWD -d build/stm32c552/nuttx.bin 0x08000000 -v -rst \
  2>&1 | tee build/nsh-hardware/flash.log
```

打开 NSH 后运行 100 条带序号的命令并保存串口记录。将下方的设备名换成
实际串口：

```sh
python -m pip install pyserial==3.5
python tools/check-nsh-serial.py /dev/cu.usbserial-XXXX build/nsh-hardware/uart.log
```

冷启动、NRST、人工输入和 30 分钟运行的验收项见
[实施计划](docs/superpowers/plans/2026-11-06-stm32c552-nsh.md)。串口脚本已用
Renode 伪串口验证。

完整板级适配的顺序、排针候选和验收条件见
[六阶段计划](docs/superpowers/plans/2026-11-06-stm32c552-board-port.md)。

## 版本与依据

- NuttX 基线 `9ffe7625cb187004cf209f113b3cd96472c92ab2`。已验证的板级提交为
  `ea017765265c8d2a96a450e08a954277373e8717`，位于 `nuttx/` 的
  `stm32c552vet6-devkit` 本地分支。
- NuttX Apps 基线 `d14111ebeff7e8eb0512e63238883dece6842c05`。
- 验证环境为 Arm GNU Toolchain 15.2.Rel1、Renode 1.17.0、Robot Framework 6.1。
- 板级信号来自同目录的 PADS 原理图及已有 STM32CubeMX2 工程。芯片定义与 ST CMSIS
  设备头文件核对。 [STM32C552VE 产品资料](https://www.st.com/en/microcontrollers-microprocessors/stm32c552ve.html)
  [RM0522 参考手册](https://www.st.com/resource/en/reference_manual/rm0522-stm32c5-series-armbased-32bit-mcus-stmicroelectronics.pdf)
