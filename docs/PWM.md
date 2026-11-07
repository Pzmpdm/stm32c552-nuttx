# TIM2_CH1 PWM 适配记录

2026-11-07，第四阶段的第一个外设子项。新增 `stm32c552vet6-devkit:nsh-pwm`，沿用 48 MHz HSIDIV3、64 KiB SRAM1、USART1 控制台、LED、按键和 tmpfs。通过标准 PWM upper-half 注册 `/dev/pwm0`，复用 NuttX Apps 的 `pwm` 命令。

## 硬件和驱动

| 项目 | 核对值 |
|---|---|
| 输出 | TIM2_CH1，PA0 AF1，H2.3 |
| 外设地址 / IRQ | `0x40000000` / 40，连续 PWM 不启用定时器中断 |
| 时钟门控 | RCC `0x44020C9C`，APB1LENR.TIM2EN bit 0 |
| 复位 | RCC `0x44020C74`，APB1LRSTR.TIM2RST bit 0 |
| 输入时钟 | 本配置 APB1 不分频，TIM2 为 48 MHz |
| 模式 | 向上计数，PWM1，高有效，PSC 分频，ARR 周期，CCR1 占空比 |
| 位宽 | TIM2 CNT、ARR、CCR 为 32 位；复用驱动当前按 16 位重装范围计算频率 |

定义与 ST DFP 的 `stm32c552xx.h`、NuttX 的 C5 RCC/引脚定义和公共 TIM v3 寄存器头核对。公共 PWM 驱动补充 C5 的 TIM2 RCC 映射与关闭后 GPIO 浮空输入配置，Make/CMake 均接入同一驱动。Kconfig 只开放 C5 的 TIM2 PWM，其他定时器尚未适配。板级只选择 CH1/PA0。

依据为 [RM0522](https://www.st.com/resource/en/reference_manual/rm0522-stm32c5-series-armbased-32bit-mcus-stmicroelectronics.pdf) 和 [ST C5 定时器概述](https://www.st.com/content/st_com/en/technical-documents/stm32c551cc_asset/chunk-005-topic-stm32c5-db-ds-functional-overview-tim.html)。

## 复现

从工程根目录运行，环境准备见 README。

```sh
. .venv/bin/activate
RENODE_HOME=/Applications/Renode.app/Contents/MacOS
cmake -S nuttx -B build/stm32c552-pwm -G Ninja \
  -DBOARD_CONFIG=stm32c552vet6-devkit:nsh-pwm
cmake --build build/stm32c552-pwm
mkdir -p build/board-pwm-final-cmake
pwm_elf="$PWD/build/stm32c552-pwm/nuttx"
(cd build/board-pwm-final-cmake && "$RENODE_HOME/renode-test" \
  ../../renode/nsh.robot ../../renode/nsh-regression.robot \
  ../../renode/gpio.robot ../../renode/pwm.robot \
  --variable ELF:"$pwm_elf")
```

NSH 中使用 `pwm -f 1000 -d 50 -t 5` 产生持续五秒的 1 kHz、50% PWM。程序结束后停止计数和通道，关闭 TIM2 门控，将 PA0 恢复为浮空输入。浮空状态不保证引脚为低电平。

## 仿真结果

CMake 和独立 checkout 的 GNU Make 固件各通过 14 项测试，其中 PWM 为六项，NSH/GPIO 为八项。

| PWM 测试 | 验收 |
|---|---|
| 启动后枚举设备 | `/dev/pwm0` 存在，尚未启动计数和门控 |
| 1 Hz / 25% | PA0 边沿符合预期周期与高低电平时间 |
| 100 Hz / 1% | 同上 |
| 1 kHz / 50% | 同上 |
| 10 kHz / 99% | 同上 |
| 同一启动周期中三次打开 | 1 kHz/25%、2 kHz/75%、1 kHz/50%，每次均停止并成功重新打开 |

每次运行检查 PA0 的 AF1、TIM2 门控、CEN、CC1E、PWM1 模式、PSC/ARR/CCR1，并按输入时钟计算频率和占空比。寄存器计算的频率误差须低于 0.2%，占空比误差须低于 0.1 个百分点；GPIO 边沿测试的高低电平时间容差为 2%。停止后验证通道禁用、门控关闭、PA0 为输入，且计数器在后续虚拟时间中保持不变。

报告为 `build/board-pwm-final-cmake/report.html` 和 `build/board-pwm-final-make/report.html`。默认 `nsh` 配置另跑八项回归，参考 C562 板也已重新编译。

## 模型限制和待办

`renode/stm32c552vet6-devkit-pwm.repl` 使用 Renode 的 STM32_Timer，经 AF1 路由至 GPIOA，再用逻辑探针测量 PA0。`renode/STM32C5_TIM2.cs` 补齐软件更新事件 UG 对缓冲 ARR 的装载。未经补齐的模型在 ARPE 开启后继续按初始 `0xFFFFFFFF` 周期计数，已通过运行时 Limit 与 CNT 读数定位。该补齐由固件的实际 UG 写入触发，周期值来自 ARR；计数、比较和输出事件沿用原模型。[Renode 模型源码](https://github.com/renode/renode-infrastructure/blob/master/src/Emulator/Peripherals/Peripherals/Timers/STM32_Timer.cs)

- RCC 仍为寄存器存储，固定 48 MHz。门控和复位的物理效果不由此模型证明。
- Renode 忽略 OC1PE，比较值立即生效；周期计数有一个 timer tick 的模型差异。波形容差包含这一差异，首次输出相位与无毛刺在线更新尚未验证。
- 当前仅验收单通道、向上计数、高有效、1 Hz～10 kHz 中所列测试点。未验收完整频率范围、0%/100%、反相、多通道、有限脉冲、DMA 或中断。
- `nsh-pwm` 与高速/SRAM2 配置各自独立，组合配置尚未验收。
- 实体板待用逻辑分析仪检查 H2.3，核对频率、占空比、启动相位和关闭后的电气状态。
- USART2 PA2/PA3 AF7（H2.1/H2.6）已作为下一子项完成仿真，并在 `nsh-uart` 中与 PWM 一起回归，见 [USART2 记录](UART.md)。
