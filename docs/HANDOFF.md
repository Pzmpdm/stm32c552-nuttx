# STM32C552VET6 DevKit Core 交接文档

更新时间为 2026-11-07。工作目录为 `/Users/pzmpdm/WorkSpace/Embedded_Project/NuttX/STM32C552`。

## 当前状态

前三阶段的仿真已完成启动和 NSH、板载 GPIO、SRAM2 和高速时钟。实体板验收待连接 SWD 探针与 3.3 V USB 转串口。下一项为第四阶段的 TIM2_CH1 PWM，候选引脚 PA0 AF1，对应 H2.3。

| 配置 | 用途 | Renode 结果 |
|---|---|---|
| `stm32c552vet6-devkit:nsh` | 48 MHz HSIDIV3、64 KiB SRAM1、USART1、LED、按键、tmpfs | 8 项通过 |
| `stm32c552vet6-devkit:nsh-sram2` | 保持 48 MHz，将清零后的 64 KiB SRAM2 注册为第二堆区，带 ramtest | CMake 和 Make 各 10 项通过 |
| `stm32c552vet6-devkit:nsh-hse` | 8 MHz HSE 驱动 144 MHz PSI，超时回退至 144 MHz HSIS | CMake 和 Make 各 4 项时钟测试通过 |

默认配置中 SRAM1 从 `0x20000000` 开始，SRAM2 从 `0x20010000` 开始。Flash 为 `0x08000000` 起的 512 KiB。静态数据和初始堆留在 SRAM1。

## 仓库和提交

项目根目录与 `nuttx/` 是独立的 Git 仓库，两者的工作分支均为 `stm32c552vet6-devkit`。根仓库跟踪文档和 Renode 测试，忽略 `nuttx/`、`apps/`、`build/`、`.venv/`。原始 PADS ZIP 保持为用户提供的未跟踪资料。阶段完成后需要在相应仓库本地提交。

| 仓库 | 关键提交 |
|---|---|
| `nuttx/` | `c58ec414` 初始板级移植，`336d3854` tmpfs，`a838abd0` 用户 LED 与按键，`cf0d9f10` SRAM2，`bc24ef0c` 144 MHz 与回退 |
| 根目录 | `20a31e5` 首轮回归，`299212c` 文件和脚本，`da7bc50` 六阶段计划与 GPIO，`5c16b7c` SRAM2 测试，`c5adf05` 高速时钟测试 |
| `apps/` | 基线 `d14111ebeff7e8eb0512e63238883dece6842c05` |
| NuttX 上游基线 | `9ffe7625cb187004cf209f113b3cd96472c92ab2` |

## 硬件与接口

- USART1 控制台为 115200 8N1。PA9/TX 为 H4.4，PA10/RX 为 H4.6，需共地。
- 用户 LED2 在 PH3，低电平点亮，设备为 `/dev/userleds`，NSH 命令为 `leds`。
- 用户按键 SW2 在 PC13，内部上拉，低电平按下，设备为 `/dev/buttons`，NSH 命令为 `buttons`。
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
- GNU Make 在独立临时 checkout 中运行 `tools/configure.sh -m -a ../apps BOARD:CONFIG`，再 `make -jN`。本机缺省 PATH 的补充工具位于 `build/host-tools/`，含 kconfig-tweak 与 flock。
- 手动控制台使用 `renode renode/interactive.resc`。
- 真机编号命令测试使用 `tools/check-nsh-serial.py`，用法及烧录命令见 [README](../README.md)。

## 验证证据和限制

| 证据 | 路径 |
|---|---|
| 基线完整回归 | `build/board-default-stage3/report.html` |
| SRAM2 CMake / Make | `build/board-sram2/report.html`、`build/board-sram2-make/report.html` |
| 时钟 CMake / Make | `build/board-clock/report.html`、`build/board-clock-make/report.html` |

- RCC 门控以寄存器存储建模。高速时钟模型模拟就绪位和切换状态，并可注入 HSE/PSI/切换超时，UART 和 SysTick 采用固定 144 MHz。
- UART 复用 STM32F7 模型，其 FIFO 使能位会被忽略。
- EXTI 复用 STM32WBA 模型，验证引脚路由、边沿和 NuttX 回调。C552 屏蔽与挂起寄存器的硬件语义仍待实测。
- SRAM2 模型验证初始化内容、地址、分配和释放。ECC 检测、纠错与真实复位条件需实体板确认。
- SRAM2 配置保留当前 option-byte 的 ECC 设置，用对齐的整字写入初始化。尚未实测 ECC 错误中断与错误地址勘误。
- 当前 NSH 行缓冲为 64 字节，单段处理 63 个字符，余下字符会成为下一段输入。
- 高速配置当前不支持电源管理，HSIS 回退维持标称 144 MHz。若两条高速路径均失败，启动会停在时钟初始化处。
- 实物尚待烧录读回、反复冷启动、NRST、时钟测量、波形验证和 30 分钟运行。

## 接续工作

先验证 PA0 的 TIM2_CH1 PWM。复用公共驱动前核对 C552 寄存器、RCC 和计数器位宽，使用 NuttX PWM upper/lower-half 与 `/dev/pwm0`。测试先覆盖多组频率和占空比、GPIO AF、停止和重新启动，再跑现有 NSH/GPIO 回归。每个通过的子阶段在 NuttX 仓库和项目根仓库各自提交，并更新本文件与六阶段计划。
