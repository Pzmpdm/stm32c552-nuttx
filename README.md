# STM32C552VET6 DevKit Core · NuttX NSH

板级配置为 `stm32c552vet6-devkit:nsh`。固件从片内 Flash
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

mkdir -p build/board-gpio-cmake
(cd build/board-gpio-cmake && "$RENODE_HOME/renode-test" \
  ../../renode/nsh.robot ../../renode/nsh-regression.robot ../../renode/gpio.robot)
```

已有构建目录会保留展开后的 `.config`。修改板级 `defconfig` 后，
使用新的 CMake 构建目录可重新应用默认配置。测试可用
`--variable ELF:/absolute/path/to/nuttx` 指定 ELF。

- 运行 `renode renode/interactive.resc`，在 USART1 分析器输入命令。
- ELF、BIN 和 HEX 镜像位于 `build/stm32c552/`。
- CMake 测试报告位于 `build/board-gpio-cmake/report.html`。

同一配置也通过 GNU Make 构建和同一套 Renode 测试。对应产物与报告位于
`build/stm32c552-gpio-make/` 和 `build/board-gpio-make/report.html`。

Robot 测试确认冷启动提示符，检查 RCC 门控位、PA9/PA10 的 AF7 配置和
USART1 波特率分频，通过 UART 执行 `echo`、`pwd` 和 `sleep 1`。
测试要求 `sleep 1` 用时 0.95–1.10 秒仿真时间，返回提示符后继续执行命令。
回归覆盖退格、CR 和 CRLF、连续命令、`ps`、`free`、`/dev`、`/proc`、
注册应用 `dd`、`/tmp` 的 tmpfs 文件读写和 `sh`。100 轮文件操作测试会
在第 0、50、100 轮比较可用堆和任务数量。
当前行编辑器以 63 字节为一段处理输入，超过的字符进入下一段。串口命令
应保持在这一长度以内。

NSH 中可运行 `leds` 和 `buttons`，分别访问 `/dev/userleds` 和
`/dev/buttons`。GPIO 回归覆盖 PH3 灯灭、点亮、熄灭，及 PC13 低电平
按下和高电平松开的两轮通知。

Renode 平台包含 Cortex-M33、NVIC/SysTick、Flash、SRAM、GPIOA/C/H、
USART1 和 EXTI13。
RCC 使用寄存器存储和固定时钟，UART 使用 Renode 自带的 STM32F7 USART
模型，模型会忽略 C552 的 FIFO 使能位。EXTI 使用 STM32WBA 模型验证引脚
路由、边沿和中断回调。C5 的屏蔽及挂起寄存器语义、按键抖动和串口电气
行为仍需实体板验证。
`BOARD_LOOPSPERMSEC=2400` 按参考板的系统时钟比例取值，忙等待延时还需
在实体板校准。

## 实体板验收

当前主机未检测到 ST-Link 或外接串口，实体板验收待接线。使用 SWD 连接
目标板，另接 3.3 V USB 转串口。识别到目标后，从工程根目录记录固件散列，
烧录并执行逐字节校验，再复位：

```sh
mkdir -p build/nsh-hardware
shasum -a 256 build/stm32c552/nuttx.bin >build/nsh-hardware/firmware.sha256
set -o pipefail
STM32_Programmer_CLI -c port=SWD -d build/stm32c552/nuttx.bin 0x08000000 -v -rst \
  2>&1 | tee build/nsh-hardware/flash.log
```

打开 NSH 后运行 100 条带序号的命令并保存串口记录。将下方的设备名换成
实际串口：

```sh
python -m pip install pyserial==3.5
python tools/check-nsh-serial.py /dev/cu.usbserial-XXXX build/nsh-hardware/uart.log
```

冷启动、NRST、人工输入和 30 分钟运行的验收项见
[实施计划](docs/superpowers/plans/2026-11-06-stm32c552-nsh.md)。串口脚本已用
Renode 伪串口验证。

完整板级适配的顺序、排针候选和验收条件见
[六阶段计划](docs/superpowers/plans/2026-11-06-stm32c552-board-port.md)。

## 版本与依据

- NuttX 基线 `9ffe7625cb187004cf209f113b3cd96472c92ab2`。已验证的板级提交为
  `a838abd093bfae3ed307078e889c5ee5ff9b2831`，位于 `nuttx/` 的
  `stm32c552vet6-devkit` 本地分支。
- NuttX Apps 基线 `d14111ebeff7e8eb0512e63238883dece6842c05`。
- 验证环境为 Arm GNU Toolchain 15.2.Rel1、Renode 1.17.0、Robot Framework 6.1。
- 板级信号来自同目录的 PADS 原理图及已有 STM32CubeMX2 工程。芯片定义与 ST CMSIS
  设备头文件核对。 [STM32C552VE 产品资料](https://www.st.com/en/microcontrollers-microprocessors/stm32c552ve.html)
  [RM0522 参考手册](https://www.st.com/resource/en/reference_manual/rm0522-stm32c5-series-armbased-32bit-mcus-stmicroelectronics.pdf)
