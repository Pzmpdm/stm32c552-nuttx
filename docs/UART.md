# USART2 适配记录

2026-11-07，第四阶段的第二个外设子项。新增 `stm32c552vet6-devkit:nsh-uart`，在 48 MHz、SRAM1 的 PWM 配置上加入 USART2、termios 和 `stty`。USART1 继续作为 NSH 控制台，USART2 注册为 `/dev/ttyS1`。两个串口复用现有 M33 USART lower-half，无需新增应用或修改公共驱动。

## 硬件和接口

| 项目 | 核对值 |
|---|---|
| USART2 TX | PA2 AF7，H2.1 |
| USART2 RX | PA3 AF7，H2.6 |
| 外设地址 / 外部 IRQ | `0x40004400` / 52 |
| RCC 门控 / 复位 | APB1LENR `0x44020C9C` bit 17 / APB1LRSTR `0x44020C74` bit 17 |
| Kernel clock | CCIPR1 `0x44020CD8` bits 3:2 复位为 0，选择 48 MHz PCLK1 |
| 数据格式 | 8N1，无 RTS/CTS，无 DMA |
| 软件缓冲 | RX、TX 各 252 字节，使用串口中断 |

引脚、地址和 IRQ 与 ST DFP 的 `stm32c552xx.h`、NuttX C5 定义核对，AF 见 [DS14928](https://www.st.com/content/st_com/en/technical-documents/stm32c551cc_asset/chunk-009-topic-stm32c5xx-db-ds-alternate-functions.html)。BRR 与 OVER8 的计算依据为 [RM0522](https://www.st.com/resource/en/reference_manual/rm0522-stm32c5-series-armbased-32bit-mcus-stmicroelectronics.pdf)。当前依赖 MCU 复位后的 PCLK1 时钟源，不支持从改变了 kernel clock 的引导程序直接交接。

PA2/PA3 与 PA0 的 TIM2 PWM 无冲突。后续若启用 USART2 的 RTS/CTS，须重新选择引脚；PA0 的 USART2_CTS 选项会占用 PWM 引脚。

## 构建与复现

从工程根目录运行。

```sh
. .venv/bin/activate
RENODE_HOME=/Applications/Renode.app/Contents/MacOS
cmake -S nuttx -B build/stm32c552-uart -G Ninja \
  -DBOARD_CONFIG=stm32c552vet6-devkit:nsh-uart
cmake --build build/stm32c552-uart
mkdir -p build/board-uart-final-cmake
uart_elf="$PWD/build/stm32c552-uart/nuttx"
(cd build/board-uart-final-cmake && "$RENODE_HOME/renode-test" \
  ../../renode/nsh.robot ../../renode/nsh-regression.robot \
  ../../renode/gpio.robot ../../renode/pwm.robot ../../renode/uart.robot \
  --variable ELF:"$uart_elf")
```

实板接外部设备时，TX/RX 交叉连接，使用 3.3 V 电平并共地。做短接回环时连接 H2.1 与 H2.6，NSH 中先运行 `stty -F /dev/ttyS1 raw speed 115200`，再用后台 `dd` 接收、前台 `dd` 发送，并在接收任务结束后用 `cmp` 比较两个文件。测试流程见 `renode/uart.robot`，不要将主机注入脚本作为实板测试结果。

## 验收结果

CMake 和独立 checkout 的 GNU Make 固件分别运行同一套 19 项测试，包含五项 USART2 测试、六项 PWM 测试及八项 NSH/GPIO 测试。

| USART2 测试 | 验收内容 |
|---|---|
| 设备枚举 | `/dev/ttyS0` 与 `/dev/ttyS1` 同时存在 |
| 接收阻塞与控制台并行 | USART2 等待数据时 USART1 继续执行命令；收到的 64 字节完整读回 |
| 4 KiB 二进制收发 | 主机分块注入全部字节值，存入 tmpfs 后经 USART2 发出，逐字节检查长度和顺序 |
| 4 KiB 回环 | 将真实 TX 字符事件送回 RX；后台接收完成后 `cmp` 一致，同时校验实际 TX 字节序列 |
| 改速与重新打开 | 9600、115200、921600 三组设置分别检查稳定后的寄存器和 256 字节收发 |

数据覆盖 `0x00`～`0xFF`，不同的 256 字节块使用不同模式。4 KiB 数据超过 RX/TX 软件缓冲容量，覆盖分块传输。测试核对 PA2/PA3 的 AF7、RCC 源和门控、8N1、RX 中断使能与 NVIC 外部 IRQ 52。端口关闭后确认 UE/RE/TE、RCC 门控和 NVIC 使能均清零。

| 请求波特率 | OVER8 | BRR | 按寄存器计算的波特率 |
|---|---|---|---|
| 9600 | 0 | `0x1388` | 9600 |
| 115200 | 1 | `0x0340` | 115384.6 |
| 921600 | 1 | `0x0064` | 923076.9 |

测试要求计算误差小于 1%，这些值不等于实测线速。报告位置为 `build/board-uart-final-cmake/report.html` 和 `build/board-uart-final-make/report.html`。默认 NSH 与 C562 参考板均重新编译；默认配置另跑八项回归。

## 仿真边界和后续

`renode/stm32c552vet6-devkit-uart.repl` 复用 PWM 平台并增加 STM32F7 USART 模型。`uart2-wire.py` 只探测 TX 字符事件、按需送回 RX，并检查字节序列，不返回固定响应。引脚复用通过寄存器检查，串口字符并未在 PA2/PA3 上模拟电气波形。[Renode UART 模型](https://github.com/renode/renode-infrastructure/blob/master/src/Emulator/Peripherals/Peripherals/UART/STM32F7_USART.cs)

- RCC 门控是寄存器存储，UART 使用固定 48 MHz；FIFOEN 被模型忽略。尚未验证 C5 FIFO 深度、满载溢出、噪声、帧错误及电气特性。
- 改速时模型会检查中间 BRR/OVER8 组合并产生警告。当前验收是在重新打开后的稳定状态进行，未验收保持端口打开时的在线改速。现有 NuttX 驱动会在配置格式期间关闭 UE 再恢复。
- UART 模型提供字符队列和接收时序，不能用 `dd` 显示的吞吐率代替真实线速。未验收硬件流控、RS485、DMA 或高速时钟组合。
- 后台接收使用完成文件同步；每次轮询均推进虚拟时间，避免仅等待主机时间而让接收任务得不到运行机会。
- 实体板待验证 H2.1/H2.6 接线、三组波特率、长时间双向传输与错误恢复。
- I²C1 PB8/PB9 AF4（H3.21/H3.20）已作为后续子项完成仿真，并与串口/PWM 一起回归，见 [I²C1 记录](I2C.md)。
