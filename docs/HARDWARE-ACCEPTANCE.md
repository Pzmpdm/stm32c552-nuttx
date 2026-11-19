# STM32C552VET6 DevKit Core 实板验收

日期为 2026-11-19。每项实板验证完成后记录测试条件、固件版本和结果。

## SWD 与启动条件

| 检查 | 结果 |
|---|---|
| SWD 识别 | STM32CubeProgrammer 2.23.0 从安装目录运行，以 100 kHz Hot Plug 识别 STM32C5x、Cortex-M33、设备 ID `0x44E`、Rev Y。读取 `DBGMCU_IDCODE` 得 `0x1003644e`。 |
| Flash 读取 | 在 `0x08000000` 多次读到同一组字 `200007C8 08000775 08000841 08000839`，对应板上已有镜像。 |
| 目标电压 | CubeProgrammer 报告过 0.71–1.77 V，独立用 OpenOCD 0.12.0 读到约 0.15 V 并提示电压过低。两者读取的是探针的目标电压参考，板上实际 VDD 尚未测量。 |
| USART1 | 主机枚举出 ST-Link VCP `/dev/cu.usbmodem11303`。以 115200 8N1 监听原有固件两秒无输出，VCP 到目标 USART1 的接线待现场确认。 |
| 烧录和运行 | 供电和 VTref 未确认，暂停写 Flash。NSH 和板载外设运行均待测。 |

板上 H4.1 为 D_3V3，H4.8 为 GND。继续前确认以 USB-C 为板供电，
H4.1 接探针 VTref 并共地，确认板上 D_3V3 和探针参考电压稳定。
若探针仍报告异常，直接测量 H4.1 对 H4.8 的电压，检查探针 VTref 连通性。
H4.3 为 SWCLK，H4.5 为 SWDIO，H4.2 为 NRST。控制台接线为
H4.4（PA9）到接收端，H4.6（PA10）到发送端，并共地。
芯片供电范围见 [ST DS14928](https://www.st.com/resource/en/datasheet/stm32c552ve.pdf)。

## NSH 待烧录镜像

- NuttX `da807047c4e5c76316abd7bb8d4da28b4195d881`，配置
  `stm32c552vet6-devkit:nsh`。
- NuttX Apps `d14111ebeff7e8eb0512e63238883dece6842c05`。
- macOS 上用 Arm GNU Toolchain 15.2.Rel1、CMake 和 Ninja 干净构建。
  BIN 106124 字节，SHA-256 为
  `6c123d826148454abac442e8c5b6e431cf86e4de249a95944d3ff553720773aa`。
- 同一构建的 ELF 在 Renode 跑完 `nsh.robot`、`nsh-regression.robot`、
  `gpio.robot`，8 项通过，0 项失败。
- 本机原始日志和产物在 `build/hardware-2026-11-19/`，包括
  `probe-*.log`、`build-nsh.log`、`nsh/nuttx.bin` 和
  `renode-nsh/report.html`。

供电确认后按 [NSH 实板计划](superpowers/plans/2026-11-06-stm32c552-nsh.md)
验收烧录校验、10 次冷启动、10 次 NRST、100 条串口命令和 30 分钟运行。
随后按 [六阶段计划](superpowers/plans/2026-11-06-stm32c552-board-port.md)
记录 LED/按键、SRAM2、时钟、各外设和 USB/IWDG 的实体板结果。
