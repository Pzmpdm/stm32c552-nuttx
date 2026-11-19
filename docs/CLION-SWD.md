# CLion SWD 调试

配置名：`STM32C552 NSH - SWD Attach`。由 CLion 启动 OpenOCD，使用
ST-Link `02660247523100063638414B`、SWD 100 kHz、Cortex-M33 AP1，
GDB 连接 `127.0.0.1:3333`。本配置不自动烧录、不自动复位。

符号文件为 `build/hardware-2026-11-19/nsh/nuttx`。只有板上运行完全相同的
镜像时，源码行、调用栈和变量才可信。CLion 2026 还要求工程里有一个
CMake 目标；根目录的 `nsh-attach` 只为满足这项检查，不会被烧进芯片。

2026-11-20 CLion 用该配置附加上，并停在 `0x080009d4`
（符号文件里的 `up_irqinitialize+64`）。OpenOCD 先读到的 PC 是
`0x08000990`。`RCC_RSR`（`0x44020CF4`）为 `0x0c000000`，即引脚复位和
欠压复位标志。四次目标电压为 0.142 V、0.147 V、0.145 V、0.145 V，
稳定在约 0.15 V，低于 OpenOCD 的可靠调试阈值。片内向量
`200007c8 08000775 ...` 与这份 ELF 的 `200023f8 08000b2d ...`
（入口 `0x08000189`）不同，板上不是这份 ELF。
本配置仅支持附加和 CPU 调试；Flash 下载需使用 CubeProgrammer 或支持
STM32C5 Flash loader 的 ST OpenOCD，不能直接使用本配置执行 GDB `load`。

2026-11-19 本次 CubeProgrammer 探测识别到设备 ID `0x44E`，VTref 报告
`0.99 V`。应确认 USB-C 供电、H4.1 D_3V3 对 H4.8 GND 约 3.3 V，
且探针 VTref 与 D_3V3 连通，再烧录并验证 NuttX 源码断点。
H4.3 接 SWCLK，H4.5 接 SWDIO；NRST 为 H4.2。

AP 布局依据：[ST 官方 STM32C5 配置](https://github.com/STMicroelectronics/OpenOCD/blob/openocd-cubeide-r7/tcl/target/stm32c5x.cfg)。
