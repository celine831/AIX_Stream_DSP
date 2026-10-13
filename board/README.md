# 征途 EP4CE10 板级自检

先使用 `Qproject/output_files_board/board_selftest.sof` 进行 JTAG 临时配置。**不要使用核心测量版 `accelerator.sof` 或 `accelerator_cdc.sof` 上板**：它们的 AXI 数据端口没有板级接线。

## 板级接口

|功能|顶层端口|FPGA 球号|电平|
|---|---|---|---|
|50 MHz 有源晶振|sys_clk|E1|3.3-V LVTTL|
|RESET 复位按钮|sys_rst_n|M15|低电平复位|
|D6 用户 LED|led[0]|L7|低电平点亮|
|D7 用户 LED|led[1]|M6|低电平点亮|
|D8 用户 LED|led[2]|P3|低电平点亮|
|D9 用户 LED|led[3]|N3|低电平点亮|

管脚已放在 `Qproject/board_pins.qsf`，由 `board_selftest.qsf` 引用。四个 LED 明确选择 4 mA 驱动。其他普通用户管脚在本机 Quartus 拟合报告中显示为输入三态带弱上拉，本测试没有新增 SDRAM、Flash、显示屏或扩展口输出。

来源为征途引脚绑定映射表 XLSX Sheet1 第 3、71、79 至 82 行，以及征途 Pro 开发板硬件规格书 V1.0.1。Pro 手册第 21 页给出 D6、D7、D8、D9 四个用户 LED。Mini 手册的 LED 器件编号不同，不用于本板的 D 编号标识。

## 自检行为和 LED

上电配置完成后自动复位并测试四套 8 抽头系数，每套 64 个样本，共 256 个结果。包含正负极值、半单位舍入、饱和、随机数据和 TLAST，并在硬件中制造反压。板上将 FIR 输出逐一与 Python 预计算的黄金 ROM 对比，差错会锁存；看见 PASS 是完成全部比对后的结果。

|用户灯|含义|
|---|---|
|D6 对应 LED1|时钟心跳，完成后继续闪烁|
|D7 对应 LED2|全部测试通过后常亮|
|D8 对应 LED3|数值、TLAST、配置错误或超时后常亮|
|D9 对应 LED4|测试运行时亮，完成后熄灭|

正常最终现象为 LED1 闪烁、LED2 亮、LED3 灭、LED4 灭。按 RESET 后重新开始。软件仿真还覆盖复位重跑、心跳以及人为破坏一次输出，验证 FAIL 能锁存且不会错误显示 PASS。此板级版本是单时钟测试；异步 CDC 仍由独立回归和专门的 Quartus CDC revision 验证。

## 下载步骤

1. 给板供电，将 USB-Blaster 接到板上 JTAG 口并连接电脑。
2. 在 Quartus Programmer 选择 USB-Blaster，模式选择 JTAG。
3. 添加 `Qproject/output_files_board/board_selftest.sof`，勾选 Program/Configure，点击 Start。
4. 等待 Programmer 完成后检查上述四个 LED；需要重测时按 RESET。

SOF 配置是易失性的，掉电后消失。本次提供的是 JTAG 测试文件，没有写入配置 Flash。板上 USB 转串口接口不等于 USB-Blaster/JTAG 下载器。

## 复现

运行 `scripts/run_all.ps1` 可重新进行核心与板级仿真、三个 Quartus revision 编译与 STA。只打开 GUI 时，打开 `Qproject/accelerator.qpf`，在 Project → Revisions 选择 `board_selftest`。核心为 Verilog-2001 `.v` 文件，测试平台保留 SystemVerilog `.sv`。

2026年10月13日现场人工观察记录：D6 闪烁、D7 常亮、D8 和 D9 熄灭；按住 RESET 时 D6 和 D7 熄灭，释放后恢复正常。单时钟板级自检和复位重测通过。该记录不包含双时钟实物验证。编译与仿真结果见 `Qproject/reports` 和 `sim/results/board_selftest.log`。
