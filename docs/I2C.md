# I²C1 适配记录

2026-11-07，第四阶段的第三个外设子项。`stm32c552vet6-devkit:nsh-i2c` 在串口/PWM 配置上加入 I²C1 和标准 `i2c` 工具，设备为 `/dev/i2c1`、总线号为 1。NSH 参数上限提高至 12，容纳带总线、地址、寄存器、频率和数据宽度的命令。

## 硬件与支持范围

| 项目 | 核对值 |
|---|---|
| SCL / SDA | PB8 AF4 / PB9 AF4，H3.21 / H3.20，开漏、无内部上拉 |
| 外设地址 | `0x40005400` |
| 外部 IRQ | 事件 44、错误 45 |
| 门控 / 复位 | RCC APB1LENR `0x44020C9C` bit 21 / APB1LRSTR `0x44020C74` bit 21 |
| Kernel clock | CCIPR2 `0x44020CDC` bits 1:0 主动选择 PCLK1，48 MHz |
| 当前驱动入口 | `stm32_i2cbus_initialize(1)`，公共板级初始化注册 `/dev/i2c1` |
| 当前范围 | 7 位地址、控制器模式、中断传输、100/400 kHz 请求档位，无 DMA |

引脚、IRQ、RCC、CR1/CR2、TIMINGR、ISR/ICR、RXDR/TXDR 布局与 ST 的 C552 设备头文件核对。复用公共 STM32 I²C v2 驱动，补充 C5 的 32 位寄存器访问、RCC 和 IRQ 映射。仅开放 I²C1，禁用 C5 的目标模式选择。其他频率、10 位地址及不合法的连续消息在拿锁前返回错误；48 MHz 以外的内核时钟在编译时拒绝。

PB8/PB9 不与已有 PA0 PWM、PA2/PA3 USART2、PA9/PA10 控制台冲突。实板需要外接至 3.3 V 的上拉，按总线电容选择阻值，并确认上升时间不超过 300 ns、下降时间不超过 100 ns。

## 时序与勘误

时序按 [RM0522](https://www.st.com/resource/en/reference_manual/rm0522-stm32c5-series-armbased-32bit-mcus-stmicroelectronics.pdf) 配置，采用保守的 SCL 高低计数。模拟和数字滤波均关闭，PRESC=2，计数单位为 62.5 ns。

| 请求档位 | TIMINGR | SCLL / SCLH | SDADEL / SCLDEL | 计数器低/高时长 |
|---|---|---|---|---|
| 100 kHz | `0x20814F4F` | 79 / 79 | 1 / 8 | 5 µs / 5 µs |
| 400 kHz | `0x20611214` | 20 / 18 | 1 / 6 | 1.3125 µs / 1.1875 µs |

SCLDEL 对应 562.5 ns、437.5 ns，分别覆盖所述上升时间与标准/快速模式的数据建立时间。同步延迟、信号斜率及目标设备的时钟拉伸会降低实际线速。这是 100/400 kHz 模式的保守时序配置，不能由请求频率或仿真寄存器推定实板的精确 SCL 频率。滤波、时序和总线负载仍需示波器验证。

已核对 [ES0661 2.7.1、2.7.2](https://www.st.com/content/st_com/en/technical-documents/es0661-stm32c551xx552xx562xx-device-errata-stmicroelectronics_asset/chunk-002-topic-function-es-rng.html)。48 MHz 内核时钟高于两种模式所需的采样下限。控制器模式发生 BERR 时，先清除该标志，保留原消息继续传输；不会把仅有 BERR 的中断当作未知状态而结束消息。

驱动还修复了 C5 路径中的两处边界：在发送 START 前建立等待状态，避免快速 NACK 的完成通知丢失；在 TCR 时同时配置 NBYTES 与 RELOAD，正确结束连续消息和最后一段数据。

## 构建和复现

```sh
. .venv/bin/activate
RENODE_HOME=/Applications/Renode.app/Contents/MacOS
cmake -S nuttx -B build/stm32c552-i2c -G Ninja \
  -DBOARD_CONFIG=stm32c552vet6-devkit:nsh-i2c
cmake --build build/stm32c552-i2c
mkdir -p build/board-i2c-final-cmake
i2c_elf="$PWD/build/stm32c552-i2c/nuttx"
i2c_platform="$PWD/renode/stm32c552vet6-devkit-i2c.repl"
(cd build/board-i2c-final-cmake && "$RENODE_HOME/renode-test" \
  ../../renode/nsh.robot ../../renode/nsh-regression.robot \
  ../../renode/gpio.robot ../../renode/pwm.robot \
  ../../renode/uart.robot ../../renode/i2c.robot \
  --variable ELF:"$i2c_elf" --variable PLATFORM:"$i2c_platform")
```

`PLATFORM` 让所有套件使用包含 I²C1 的完整模型。旧套件未传入该参数时继续使用各自的默认平台。GNU Make 在隔离 checkout 构建，同一套测试用 `build/stm32c552-i2c-make/nuttx` 运行。

仿真测试设备地址为 `0x50`，是附加的寄存器存储模型，并非板载器件。示例 `i2c get -b1 -a50 -r20 -f100000` 与 `i2c set -b1 -a50 -r20 -f100000 a5` 仅适用于该模型或协议匹配的实际从设备。

## 测试证据

CMake 和 GNU Make 固件各运行 27 项测试，包含八项 I²C、五项 USART2、六项 PWM 和八项 NSH/GPIO 回归。

| I²C 测试 | 验收内容 |
|---|---|
| 设备与配置 | `/dev/i2c1`、PB8/PB9 AF4、开漏写入、RCC 源与门控、两条 IRQ、PE 关闭时写入时序 |
| 单字节读写 | 写入后返回新值，独立检查存储；组合读的两个 START 和一个 STOP |
| NACK 与恢复 | 不存在的地址失败，100 ms 内返回；随后合法地址读成功 |
| 400 kHz 档位 | 连续写两个数据字节并读回 16 位值，检查 TIMINGR |
| 跨 255 字节边界 | 单次读 256 字节，逐行核对全部数据及 RELOAD 使用 |
| 中断超时与恢复 | 屏蔽事件 IRQ 后传输失败，恢复 IRQ 后读成功 |
| 不支持的频率 | 拒绝 1 MHz 请求且不发 START，随后 100 kHz 读成功 |
| BERR 勘误路径 | 在数据就绪前注入 BERR；确认错误中断、清标志且原传输返回正确数据 |

标准 `i2c` 工具当前把 ioctl 失败统一显示为 `Transfer failed: 1`，NSH 退出码也不能区分这些底层错误。因此测试结合故障条件、完成时限、是否发 START 和恢复读写验证，未把这个显示数字解释为具体 errno。

报告为 `build/board-i2c-final-cmake/report.html`、`build/board-i2c-final-make/report.html`。默认 NSH 八项及 SRAM2 两项专项回归见 `build/board-default-i2c/report.html`。C562 参考板重新编译；F303RE 开启相同公共 I²C v2 驱动后编译通过，保留其原有 HSI 配置提醒，不代表 F303 外设实测。

## 模型与待验证项目

`STM32C5_I2C.cs` 基于 [Renode STM32F7_I2C 固定版本](https://github.com/renode/renode-infrastructure/blob/cdf0cd3dcda1ede992290128ef291600b720849a/src/Emulator/Peripherals/Peripherals/I2C/STM32F7_I2C.cs)，保留原版权及 `renode/licenses/Renode-MIT.txt`。本地修正 ICR 写入后的 IRQ 刷新、TC/TCR 边界的 TXIS、STOP 清除完成状态及地址 NACK 自动停止，并加入 BERR/ERRIE/ICR 与按需故障注入。

`I2CRegisterMemory.cs` 提供 256 字节可写存储、8 位自增指针和事务计数。固件写入会改变后续读取；没有固定的成功响应。被动记录的 START/STOP、RELOAD、开漏与时序写入用于核对模型忽略的字段。

- GPIO 模型忽略 OTYPER，I²C 模型忽略 TIMINGR 和滤波字段。测试确认软件写入，不能证明开漏电气行为、SCL 波形或滤波效果。
- RCC 门控使用寄存器存储，不模拟真实复位、时钟停止和上拉。错误路径中 BERR 是仿真注入，NACK 来自无从设备地址，超时来自 IRQ 屏蔽。
- 已测载荷为单/双字节写入和最长 256 字节读取；未验收更长写入、目标模式、多控制器、10 位地址、DMA、电源管理或物理总线卡死后的 GPIO 解锁。
- 尚未验证其他总线错误、仲裁丢失、噪声、时钟拉伸极限，以及高速时钟/SRAM2 与此配置的组合。
- 实板待确认上拉与电平、SCL 频率和建立保持时间，再连接真实器件验证读写、重复起始、NACK、长时间运行及恢复。
- 下一子项为 SPI1，候选 PA5/PA6/PA7 AF5，PA4 作为片选。
