# SPI1 适配记录

2026-11-07，第四阶段的第四个外设子项。`stm32c552vet6-devkit:nsh-spi` 在 I²C/UART/PWM 配置上增加 `/dev/spi1` 和标准 `spi` 工具。当前使用 48 MHz PCLK2、控制器模式、全双工、MSB 优先、软件 GPIO 片选和轮询传输。

NuttX 本地提交为 `1bb4a68e4ed5d64ff9d98917212502d553033a29`，apps 保持 `d14111ebeff7e8eb0512e63238883dece6842c05`。

## 接口与实现

| 项目 | 核对值 |
|---|---|
| SCK / MISO / MOSI | PA5 / PA6 / PA7，AF5，H2.8 / H2.7 / H2.10 |
| CS | PA4 GPIO，H2.5，低有效，`SPIDEV_USER(0)`；其他设备编号保持 CS 高 |
| 地址 / IRQ | `0x40013000` / 外部 IRQ 48 |
| 门控 / 复位 | APB2ENR `0x44020CA4` bit 12 / APB2RSTR `0x44020C7C` bit 12 |
| 内核时钟 | CCIPR1 `0x44020CD8` bits 17:16 = 0，PCLK2 = 48 MHz |
| 寄存器布局 | CR1/CR2、CFG1/CFG2、IER/SR/IFCR、TXDR `+0x20`、RXDR `+0x30` |
| FIFO | 每个方向 16 字节，8/16/32 位分别最多预装 16/8/4 帧 |
| 当前验收 | 8/16/32 位帧、mode 0–3、分频、20 字节载荷、多事务片选与重新打开 |

引脚与排针取自 PADS 原理图；寄存器、IRQ、BPASS 和 FIFO 与匹配的 ST C552 CMSIS/LL/HAL2 源码核对。参考 [RM0522](https://www.st.com/resource/en/reference_manual/rm0522-stm32c5-series-armbased-32bit-mcus-stmicroelectronics.pdf)。PA5/PA7 使用 high speed GPIO 档，PA4 初始输出高，并在 SPI 引脚复用及总线注册前初始化。实板建议给 CS 增加外部上拉，保证 MCU 复位及尚未配置时从设备也不被选中。

C552 的 CFG1/CFG2 布局不兼容旧公共 CR1/CR2 SPI 驱动。本次将原 H5 实现移到公共 `stm32_spi_v5.c`，以独立的 IP 能力选择，不按 CPU 类型判断。H5 原寄存器头路径保留为转接头。C5 只开放 SPI1；没有启用中断数据传输、DMA、设备模式、I2S、CRC 或 RDY。C5 不能直接采用 H5 的 GPDMA 通道配置。

同时修复公共轮询路径：32 位帧使用 32 位 TXDR/RXDR 访问及缓冲元素，避免原有 16 位路径截断；在 SPI 关闭时写 CRCPOLY；仅在需要时停用 SPI 再修改 DMA 请求位。8/16 位保持对应访问宽度。SPI_SEND 的 32 位路径也改用宽访问，但本轮运行测试通过标准交换接口，未独立调用 SPI_SEND。

[ES0661 SPI 限制](https://www.st.com/content/st_com/en/technical-documents/es0661-stm32c551xx552xx562xx-device-errata-stmicroelectronics_asset/chunk-003-topic-function-es-uart-usart.html)涉及设备模式下的 RDY 输出；当前控制器模式、GPIO CS 且不使用 RDY，未启用该受影响功能。

## 频率与使用

当前板级把 SCK 请求上限限制为 24 MHz。48 MHz 内核可选择 `/2` 至 `/256`，实际分频值如下。请求值不能直接当作实测线速。

| 请求值 | 分频值 | 标称 SCK |
|---|---|---|
| 100 kHz / 187.5 kHz | /256 | 187.5 kHz（硬件最低档） |
| 1 MHz | /64 | 750 kHz |
| 12 MHz | /4 | 12 MHz |
| 24 MHz / 48 MHz | /2 | 24 MHz（板级限幅） |

以下命令针对 Renode 的测试从设备；板上未内置 SPI 从设备，连接其他器件时须使用其协议。工具把十六进制数据依次填入小端内存；例如 16 位参数 `1234` 代表帧值 `0x3412`，在线上 MSB 优先发送 `34 12`。

```text
spi bus
spi exch -b1 -m0 -f1000000 -w8 -x4 12345678
spi exch -w16 -x2 12345678
spi exch -w32 -x1 12345678
```

当前 flat 构建的工具使用静态参数状态，选项会在多次调用之间保留；脚本应显式给出需要的选项，避免沿用前次设置。命令不得超过 NSH 的 63 字符行长。标准工具的发送/接收数组为 40 字节，使用时还必须保证 `帧数 × 每帧字节 × 事务数 <= 40`；其参数解析没有完整保护多事务宽帧的总大小。本轮最长总载荷为 20 字节，未修改 apps 基线。

## 复现与证据

```sh
. .venv/bin/activate
RENODE_HOME=/Applications/Renode.app/Contents/MacOS
cmake -S nuttx -B build/stm32c552-spi -G Ninja \
  -DBOARD_CONFIG=stm32c552vet6-devkit:nsh-spi
cmake --build build/stm32c552-spi
mkdir -p build/board-spi-final-cmake
spi_elf="$PWD/build/stm32c552-spi/nuttx"
spi_platform="$PWD/renode/stm32c552vet6-devkit-spi.repl"
(cd build/board-spi-final-cmake && "$RENODE_HOME/renode-test" \
  ../../renode/nsh.robot ../../renode/nsh-regression.robot \
  ../../renode/gpio.robot ../../renode/pwm.robot ../../renode/uart.robot \
  ../../renode/i2c.robot ../../renode/spi.robot \
  --variable ELF:"$spi_elf" --variable PLATFORM:"$spi_platform")
```

GNU Make 在独立 checkout 中构建，同样指定 SPI ELF 和完整平台运行。报告分别为 `build/board-spi-final-cmake/report.html` 和 `build/board-spi-final-make/report.html`，各 36 项：九项 SPI 加此前 27 项回归。

| SPI 专项 | 验收内容 |
|---|---|
| 注册及初值 | `/dev/spi1`、PA4 输出高、PA5/6/7 AF5、SCK/MOSI GPIO 速度、时钟源/门控和配置 |
| 8 位 | 20 字节完整双向数据、FIFO 周转、字节访问 |
| 16 位 | 10 帧完整双向数据、MSB 字节顺序、半字访问 |
| 32 位 | 5 帧完整双向数据、高 16 位保留、整字访问 |
| mode 0–3 | 每次重新打开后双向交换，核对 CPHA/CPOL 配置 |
| 分频 | 六组请求值、分频寄存器、24 MHz 请求上限 |
| 三次事务 | 动态响应、三次实际 GPIO CS 拉低/释放、三个暂停通知 |
| 未映射 CS | 不选中从设备；随后 USER(0) 交换成功 |
| 零长度 | 返回提示符，之后非零数据传输成功 |

所有交换检查：TXDR/RXDR 访问位宽匹配，待接收总量不超过 16 字节，配置寄存器没有在 SPE=1 时写入。另构建禁用 32 位修复的负向固件，仅运行 32 位用例，确认其失败；恢复实现后的全套用例通过。负向报告 `build/board-spi-negative/report.html` 是预期失败证据。

默认 NSH/GPIO 八项及 SRAM2 两项回归见 `build/board-default-spi/report.html`。C562 原参考配置重新编译；H563ZI 的 NSH 开启 SPI1/标准工具后，分别以轮询及 SPI1 DMA 配置编译通过，验证公共驱动移动后的构建兼容性，不代表 H5 外设实测。

## 模型与未验证项目

`STM32C5_SPI.cs` 继承 Renode 1.17 的 `STM32WBA_SPI`（CFG1/CFG2、CSTART/CSUSP）。模型补齐配置寄存器和 SSI 读回，并把宽帧的字节流转换为 MSB 优先。数据和状态仍由原控制器模型处理；没有注入固定接收值或就绪标志。

`SPIStatefulTarget.cs` 经实际 PA4 GPIO 收到 CS。每字节响应为 `MOSI XOR 前一字节 XOR 0xA5`，每次 CS 拉低把前一字节重置为 `0x3C`。因此响应依赖发送内容和事务边界，控制器暂停通知不会代替 GPIO CS 释放。

- 原控制器 FIFO 无容量上限；被动计数核对驱动待接收数据不超过硬件容量，未验证真实 OVR/UDR、FIFO 延迟和错误恢复。
- MBR、CPHA/CPOL、GPIO AF/速度、SSM/AFCNTR 通过寄存器检查；模型不生成对应 SCK/MOSI 电气波形，收发数据流直接连接模型从设备。不能据此确认实际频率、采样边沿、建立保持时间、首末时钟和复位期间 CS 无毛刺。
- RCC 使用寄存器存储；实际门控、外设复位及真实时钟启停尚待实测。SPI 内部错误及 CRC 没有建模。
- 保留公共驱动的轮询等待；控制器故障导致标志不出现时可能无限等待，尚未加入可报告的超时恢复。正常交换不依赖外设 IRQ。
- 未验收非 8/16/32 位帧、LSB 优先、NULL 缓冲、独立 SPI_SEND、在线保持打开的改速、多线程竞争、DMA、中断数据传输、PM 或 HSE/SRAM2 与该配置组合。
- 实板待连接真实从设备与逻辑分析仪，确认电平、CS/SCK、四种模式及多位宽数据，再做故障和长时间运行。
- PC0 的 ADC1_IN8 已通过仿真验收，见 [ADC1 记录](ADC.md)。下一子项为 LPDMA。
