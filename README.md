# STM32C552VET6 DevKit Core · NuttX NSH

首阶段配置为 `stm32c552vet6-devkit:nsh`。固件从片内 Flash
`0x08000000` 的复位向量启动，沿用芯片复位时的 48 MHz HSIDIV3
系统时钟及总线分频。512 KiB Flash 可用，静态数据、栈和堆均使用
`0x20000000` 起的 64 KiB SRAM1。SRAM2 的 ECC 初始化留待后续验证。
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

mkdir -p build/renode
(cd build/renode && "$RENODE_HOME/renode-test" ../../renode/nsh.robot)
```

已有构建目录会保留展开后的 `.config`。修改板级 `defconfig` 后，
使用新的 CMake 构建目录可重新应用默认配置。测试可用
`--variable ELF:/absolute/path/to/nuttx` 指定 ELF。

- 运行 `renode renode/interactive.resc`，在 USART1 分析器输入命令。
- ELF、BIN 和 HEX 镜像位于 `build/stm32c552/`。
- 测试报告位于 `build/renode/report.html`，详细步骤见 `build/renode/log.html`。

同一配置也通过 GNU Make 构建和同一套 Renode 测试。对应产物与报告位于
`build/stm32c552-make/` 和 `build/renode-make/report.html`。

Robot 测试确认冷启动提示符，检查 RCC 门控位、PA9/PA10 的 AF7 配置和
USART1 波特率分频，通过 UART 执行 `echo`、`pwd` 和 `sleep 1`。
测试要求 `sleep 1` 用时 0.95–1.10 秒仿真时间，返回提示符后继续执行命令。

Renode 平台包含 Cortex-M33、NVIC/SysTick、Flash、SRAM、GPIOA 和 USART1。
RCC 使用寄存器存储和固定时钟，UART 使用 Renode 自带的 STM32F7 USART
模型，模型会忽略 C552 的 FIFO 使能位。阶段验收覆盖仿真中的启动、节拍和
串口交互。实体板启动、电气和 FIFO 行为仍需实测。
`BOARD_LOOPSPERMSEC=2400` 按参考板的系统时钟比例取值，忙等待延时还需
在实体板校准。

## 版本与依据

- NuttX 基线 `9ffe7625cb187004cf209f113b3cd96472c92ab2`，板级移植在 `nuttx/`。
- NuttX Apps 基线 `d14111ebeff7e8eb0512e63238883dece6842c05`。
- 验证环境为 Arm GNU Toolchain 15.2.Rel1、Renode 1.17.0、Robot Framework 6.1。
- 板级信号来自同目录的 PADS 原理图及已有 STM32CubeMX2 工程。芯片定义与 ST CMSIS
  设备头文件核对。 [STM32C552VE 产品资料](https://www.st.com/en/microcontrollers-microprocessors/stm32c552ve.html)
  [RM0522 参考手册](https://www.st.com/resource/en/reference_manual/rm0522-stm32c5-series-armbased-32bit-mcus-stmicroelectronics.pdf)
