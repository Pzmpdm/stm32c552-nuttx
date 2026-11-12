# LPDMA 与 ADC1 批量采样

2026-11-13，第四阶段的第六个子项。`stm32c552vet6-devkit:nsh-lpdma` 启用两组 LPDMA、启动内存自检和 ADC1 的四样本 DMA 采集。`adc -n1` 触发一组，`adc -n16` 在一次打开期间采集 16 组，共 64 个原始码值。

NuttX 驱动和板级配置提交为 `ea017765265c8d2a96a450e08a954277373e8717`。

| 项目 | C552 配置 |
|---|---|
| LPDMA1 | `0x40020000`，8 通道，外部 IRQ 23–30 |
| LPDMA2 | `0x40021000`，4 通道，外部 IRQ 78–81 |
| RCC | AHB1ENR `0x44020C88`，bit 0/1 分别为 LPDMA1/2 门控 |
| 通道寄存器 | 起点为实例基址 + `0x50`，通道步长 `0x80` |
| 块大小 | `CBR1.BNDT` 以字节为单位，宽度为 1、2 或 4 字节 |
| ADC1 | PC0（H3.14），IN8，ADC_DR `0x42028040`，LPDMA1 请求号 0 |

通道数量、中断和寄存器按 STM32C552 设备头文件核对。LPDMA 复用 GPDMA 通道寄存器中的通用位定义，C552 使用独立的 LPDMA 能力选项和 `stm32_lpdma_*` 接口。单块传输使用相同的源与目的宽度，支持固定或递增地址。软件触发内存搬运写 SWREQ，外设传输用 REQSEL，C552 的保留位 DREQ 保持复位值。[RM0522 第 14 章](https://www.st.com/resource/en/reference_manual/rm0522-stm32c5-series-armbased-32bit-mcus-stmicroelectronics.pdf)

启动前检查长度与端点对齐，通道由申请者独占。传输完成或出错时清除中断标志，再通知调用者。取消时先暂停，再复位通道，两处等待均有上限。停止超时时保留通道所有权和静态传输缓冲。内存自检由板级诊断选项启用，逐一复制并比较每个通道的 128 字节数据，同时检查目标两端的保护值。

ADC1 每组在 SQR1 中安排四次 IN8 转换。驱动先配置 16 字节 DMA 块，再启用本组的 ADC DMA 请求并启动转换。每次请求将 ADC_DR 的一个 32 位数据搬入 SRAM1，组完成后关闭该请求模式，将四个样本一起放入 ADC 队列。软件触发等待 DMA 完成中断，等待预算为 100 ms。失败的块返回错误，取消后可重新采样。ADC 上半部在空队列发生错误时通知读者，避免读者一直等待该块的数据。[RM0522 ADC DMA 说明](https://www.st.com/resource/en/reference_manual/rm0522-stm32c5-series-armbased-32bit-mcus-stmicroelectronics.pdf)

## 构建与复现

```sh
. .venv/bin/activate
RENODE_HOME=/Applications/Renode.app/Contents/MacOS
cmake -S nuttx -B build/stm32c552-lpdma -G Ninja \
  -DBOARD_CONFIG=stm32c552vet6-devkit:nsh-lpdma
cmake --build build/stm32c552-lpdma
mkdir -p build/board-lpdma-final-cmake
lpdma_elf="$PWD/build/stm32c552-lpdma/nuttx"
lpdma_platform="$PWD/renode/stm32c552vet6-devkit-lpdma.repl"
(cd build/board-lpdma-final-cmake && "$RENODE_HOME/renode-test" \
  ../../renode/nsh.robot ../../renode/nsh-regression.robot \
  ../../renode/gpio.robot ../../renode/pwm.robot ../../renode/uart.robot \
  ../../renode/i2c.robot ../../renode/spi.robot ../../renode/lpdma.robot \
  --variable ELF:"$lpdma_elf" --variable PLATFORM:"$lpdma_platform")
```

GNU Make 在隔离 checkout 配置同一 `nsh-lpdma`，仿真使用 `build/stm32c552-lpdma-make/nuttx`。ADC 中断版回归使用 `nsh-adc` ELF、`stm32c552vet6-devkit-adc.repl` 及 `adc.robot`。

## 验收

| 用例 | 验收内容 |
|---|---|
| 内存搬运 | 两个实例共 12 个通道，8/16/32 位宽，128 字节内容与两端保护值一致 |
| 传输错误 | 注入 DTE，确认错误中断、标志清除及原通道重试 |
| 传输超时 | 停住 LPDMA2 的首个块，确认超时、暂停、复位及重试 |
| ADC 电压点 | 三种输入，每次触发四个结果，核对请求次数和所有码值 |
| ADC 重复块 | 一次打开校准一次，连续触发 16 组，核对 64 个样本及每组重新启用 DMA |
| DMA 完成中断 | 屏蔽 LPDMA1 通道 0 的 IRQ，检查四次搬运和待处理中断，恢复 IRQ 后取得样本 |
| ADC DMA 错误 | 错误经触发和读取接口返回，重新打开后取得完整块 |
| ADC DMA 超时 | 停止转换、取消 DMA、清理状态，重新打开后取得完整块 |

CMake 与 GNU Make 各 44 项通过，包含 8 项 LPDMA/ADC DMA 和此前 36 项 NSH/GPIO/PWM/UART/I²C/SPI 回归。ADC 中断版的 43 项独立回归通过。报告为 `build/board-lpdma-final-cmake/report.html`、`build/board-lpdma-final-make/report.html`、`build/board-lpdma-final-adc/report.html`。

## 模型与实板范围

Renode 的 C552 LPDMA 模型根据寄存器内容读写总线，处理字节计数、递增地址、每次 ADC 请求、完成中断和写一清零标志。错误和停顿由测试显式注入。内存自检和 ADC 缓冲位于 SRAM1，模型的 ADC 参考电压为 3.3 V。

实板的 DMA 总线仲裁、搬运时延、采样间隔、模拟精度及 SRAM2 组合待验证。当前软件验收为单块搬运和 ADC1 四样本采集。链表、循环传输、外设节拍触发、其他外设的 DMA 接入和低功耗行为属于后续范围。

下一阶段为 USB-C 设备，先验证 C552 USB FS 的 48 MHz 时钟、设备控制器和 CDC ACM 枚举。
