# ADC1 适配记录

2026-11-13，第四阶段的第五个外设子项。`stm32c552vet6-devkit:nsh-adc` 在 SPI 配置上增加 `/dev/adc0` 和标准 `adc` 示例。板级选择 PC0 的 ADC1_IN8，使用 12 位、右对齐、单端输入。每次软件触发启动一次常规组转换，转换中断把通道号和原始码值送到 NuttX ADC 字符设备。

NuttX 提交 `5bcb29fe` 接入 ADC1，`ec9aea59` 修复初始化失败后的打开计数。

| 项目 | 配置 |
|---|---|
| 输入 | PC0（H3.14），模拟模式，无上下拉 |
| 外设 / IRQ | ADC1 `0x42028000`，外部 IRQ 32 |
| 门控 / 复位 | AHB2ENR `0x44020C8C`、AHB2RSTR `0x44020C64`，bit 10 |
| 内核时钟 | CCIPR2 `0x44020CDC`，HCLK / 4 = 12 MHz |
| 采样 | 48 ADC 时钟周期，`SMPR1.SMP8=5`，`PCSEL=0x100`，`SQR1=0x200` |
| 应用接口 | `adc` 读一次，`adc -n32` 在一次打开期间触发并读取 32 次 |

寄存器与时序依据匹配的 C552 CMSIS/LL 定义。C552 的 PCSEL、CALFACT 和 RCC 分频不同于现有 H5/G4 驱动，芯片层实现位于 `arch/arm/src/stm32c5/stm32_adc.c`。板级负责 PC0 配置和设备注册，采样队列、阻塞读取及多次打开计数沿用 NuttX ADC 上半部。[RM0522 参考手册](https://www.st.com/resource/en/reference_manual/rm0522-stm32c5-series-armbased-32bit-mcus-stmicroelectronics.pdf)

首次打开时，驱动配置时钟并复位 ADC12，退出深度掉电，等待 LDORDY 后启动自校准。校准完成后留出四个 ADC 时钟周期所需的间隔，配置单通道，等待 ADRDY，再启用转换中断。每个状态等待有 1000 轮轮询预算。初始化超时返回 `ETIMEDOUT`，复位 ADC12 并关闭门控，下一次打开可重新初始化。最后一次关闭停止仍在运行的转换、关中断并进入深度掉电。当前 ADC12 复位和 ADCDAC 时钟由 ADC1 独占，接入 ADC2 或 DAC 时需要协调共享资源。

恢复测试发现 ADC 上半部原先在初始化失败时也增加打开计数，导致下一次打开跳过初始化。现在只在打开成功后更新计数，三条故障用例覆盖了重新打开和采样。

当前配置的 C552 能力选项只开放 ADC1，芯片接口接受一个外部通道，板级测试覆盖 IN8。双 ADC、注入转换及 SMPTRIG 的限制见 [ES0661 ADC 勘误](https://www.st.com/content/st_com/en/technical-documents/es0661-stm32c551xx552xx562xx-device-errata-stmicroelectronics.html)。

## 复现

```sh
. .venv/bin/activate
RENODE_HOME=/Applications/Renode.app/Contents/MacOS
cmake -S nuttx -B build/stm32c552-adc -G Ninja \
  -DBOARD_CONFIG=stm32c552vet6-devkit:nsh-adc
cmake --build build/stm32c552-adc
mkdir -p build/board-adc-final-cmake
adc_elf="$PWD/build/stm32c552-adc/nuttx"
adc_platform="$PWD/renode/stm32c552vet6-devkit-adc.repl"
(cd build/board-adc-final-cmake && "$RENODE_HOME/renode-test" \
  ../../renode/nsh.robot ../../renode/nsh-regression.robot \
  ../../renode/gpio.robot ../../renode/pwm.robot ../../renode/uart.robot \
  ../../renode/i2c.robot ../../renode/spi.robot ../../renode/adc.robot \
  --variable ELF:"$adc_elf" --variable PLATFORM:"$adc_platform")
```

GNU Make 在隔离 checkout 构建同一 `nsh-adc` 配置，将 ELF 换为 `build/stm32c552-adc-make/nuttx` 后运行同一套测试。手动仿真可用 `renode/boot.resc` 指定上述 ELF 和平台，在 monitor 执行 `sysbus.adc1 SetVoltage 1650000 8`，再在 NSH 运行 `adc -n1`。模型输入单位为微伏。

## 验收项目

| ADC 测试 | 验收内容 |
|---|---|
| 设备与空闲 | `/dev/adc0`、PC0 模拟模式、门控关闭、ADC 深度掉电 |
| 电压转换 | IN8 的 0、0.33、1.65、2.64、3.30 V 分别得到 0、410、2048、3276、4095。IN9 保持不同电压以检查通道选择 |
| 重复采样 | 打开一次、校准一次、触发和读取各 32 次 |
| 中断路径 | 屏蔽 IRQ 时保留 EOC 和样本，NSH 仍可运行。恢复 IRQ 后读到待处理样本。检查 RCC、SMPR、PCSEL、SQR 和 IER |
| 三种初始化故障 | 分别停住 LDORDY、ADCAL 和 ADRDY，确认 100 ms 仿真时间内返回超时，故障解除后重新采样并正常关闭 |

CMake 与 GNU Make 的报告分别在 `build/board-adc-final-cmake/report.html` 和 `build/board-adc-final-make/report.html`，各含七项 ADC 及此前 36 项回归。修复打开计数之前的三项恢复失败保存在 `build/board-adc-open-failure/report.html`。默认 NSH/GPIO 和 SRAM2 专项共十项，报告在 `build/board-default-adc/report.html`。C562 参考配置及 H563ZI ADC 配置重新编译通过。

## 模型和实板验收

`STM32C5_ADC.cs` 复用 Renode 的 ADC 通道序列、可变电压源、量化、结果寄存器及中断。适配层对 ADC12 复位作出响应，模拟稳压器与校准状态，记录配置写入和转换次数。理想参考电压为 3.3 V，模型以 `round(Vin / Vref × 4095)` 计算 12 位结果。校准状态验证软件时序，采样时间和内核时钟通过寄存器写入检查。RCC 模型保留门控位，ADC12 复位通过寄存器写入触发。

PADS PCB 网表中，VREF+（U2.21、C19.2）属于 A_3V3，VREF−（U2.20、C15.1）属于 AGND。实板验收先测量这两点的电压差，再用低阻抗已知电压源与板共地，核对参考范围内的原始码值、重复性和噪声。模拟精度、有效采样时间、上电及复位时序等待实测。软件验证范围为单 ADC、单外部通道的软件触发和 EOC 中断。连续模式、定时器触发、DMA、双 ADC、注入组、过载及 144 MHz/SRAM2 组合待后续验证。

四样本 DMA 采集已接入 `nsh-lpdma`，详见 [LPDMA 记录](LPDMA.md)。下一阶段为 USB-C 设备与 CDC ACM。
