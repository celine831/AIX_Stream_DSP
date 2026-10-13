# AXI4-Stream 参数化流水线 FIR DSP 加速器

本项目在 Cyclone IV E **EP4CE10F17C8** 上实现参数化定点 FIR 加速器。核心顶层为 `accelerator`，板级自检顶层为 `board_selftest`；可综合源码采用 Verilog-2001 `.v`，测试平台采用 SystemVerilog `.sv`。

## 功能

- 参数化有符号输入、系数及输出位宽，1 至 64 抽头，乘法器并行、寄存器平衡加法树。
- AXI4-Stream `TDATA/TVALID/TREADY/TLAST`，数据总线向上补齐到 8 位整数倍；输出高位符号扩展，输入只解释低 `DATA_WIDTH` 位。所有字节有效，无字节空洞、无多流交织。
- 输入/输出浅 FIFO 与弹性接口寄存器；停顿时保持输出数据及帧标记；无反压时每拍一个样本。
- 可选 Gray 指针异步输入 FIFO，源时钟 `s_axis_aclk`，运算及输出时钟 `aclk`。
- 影子系数、停止接收与排空握手、原子提交；提交清空历史，`TLAST` 是否清空历史由 `FRAME_RESET` 选择。
- 算术截位、最近舍入且中点远离零、最近偶数舍入；饱和或补码回绕。
- 独立 Python 整数黄金模型，ModelSim 自检、协议稳定性、Gray 变化、复位、参数与定点穷举测试。

## 目录

|目录|内容|
|---|---|
|`rtl`|7 个核心模块与板级自检顶层，均为 .v|
|`board`|板级黄金 ROM、向量生成器和上板操作说明|
|`sim`|黄金模型、4 个测试平台、自动回归及波形脚本|
|`sim/results`|逐测试日志、WLF 波形、Lint 日志及 summary.json|
|`Qproject`|原有 Quartus 工程、同步 CDC 板级三个 revision、管脚、SDC、STA 脚本|
|`Qproject/reports`|真实布局布线日志、Fmax、关键路径、约束完整性与 CDC 物理约束报告|
|`doc`|设计规划与模块实现 问题解决及问答两份 Word 文档|
|`scripts`|可重复生成文档和验证摘要的辅助脚本|

## 默认参数和接口契约

`DATA_WIDTH=16, COEFF_WIDTH=16, OUT_WIDTH=16, TAPS=8, SHIFT=15, ROUND_MODE=1, SATURATE=1, FRAME_RESET=0, FIFO_ADDR_WIDTH=4, USE_ASYNC=0`。

滤波器阶数为 `TAPS-1`。系数可理解为 15 个小数位，输入整数单位保持不变；小数位分配可通过 SHIFT 调整。复位后所有系数为零，应先编程再发送数据。任意配置受目标芯片乘法器和逻辑资源限制；16 抽头等变体已做 RTL 仿真，并不表示所有参数组合都在该芯片完成布局布线。

配置端口均属于 `aclk`。拉高 `cfg_we` 并给出 `cfg_addr/cfg_data`，在上升沿写入影子系数，可连续写。拉高 `cfg_quiesce` 后等待 `cfg_ready`；等待期间下游必须继续消费才能排空。`cfg_commit` 单拍且不得同时 `cfg_we`，完成后撤销 `cfg_quiesce`。`cfg_error` 是组合错误指示，非法地址、未排空提交或同拍写入提交均拒绝对应非法动作。尚未写入的影子系数保留上次值。有效提交复制整个影子表并清空 FIR 历史。

`aresetn` 共同异步拉低，各域两级同步释放；共同复位会丢弃未完成的数据。CDC 模式不能单独复位一个域。在 `USE_ASYNC=0` 时输入属于 `aclk`，`s_axis_aclk` 不参与逻辑，接线时可与 `aclk` 相连。

支持数据/系数 1 至 32 位、输出 1 至完整累加位宽、TAPS 1 至 64、SHIFT 0 至累加位宽减 1、ROUND_MODE 0/1/2、FIFO_ADDR_WIDTH 2 至 8。TAPS 非二次幂时加法树补零，TAPS=1 不生成加法树。FIFO 深度为 2 的地址位宽次方；浅 FIFO 使用逻辑寄存器，若需深 RAM FIFO应另行调整结构并验证。

## 一键复现

```powershell
# 本机一键执行所有仿真、Quartus 编译、STA 与结果汇总
& ./scripts/run_all.ps1

# 可用普通 Python；本机工具路径已经配置为实际安装路径
python sim/run_regression.py
# 若 Python 不在 PATH，替换为本机 Python 的绝对路径。
# ModelSim 可传 --modelsim-bin，也可设置环境变量 MODELSIM_BIN。
& ./Qproject/run_quartus.ps1
# Quartus 可传 -QuartusBin 指向 bin64。
```

ModelSim 图形查看：切换目录到 `sim`，运行 `do run.do`；若要交互查看，不执行脚本最后的 quit，加载 `do wave.do`。回归保留每个案例的 WLF，可在 GUI 中打开；`sim/gui.do` 提供直接加载默认案例并保留界面的入口。

最终工作频率约束为核心约 75 MHz，CDC 源约 50 MHz，外部输入/输出延迟预算为 2 ns。实际 Fmax、裕量和资源以 `Qproject/reports` 和 `verification_summary.json` 为准。RTL 回归使用理想时钟，不是 SDF 后仿真，也不能验证模拟亚稳态。ModelSim `vlog -lint` 已执行；未宣称完成专业 CDC 形式证明或 LEC。

两个核心测量 revision 的 AXI 端口仍由 Quartus 自动分配，**不能直接将 accelerator.sof 或 accelerator_cdc.sof 上板**。已经另外提供使用真实 E1 时钟、M15 复位以及 L7/M6/P3/N3 LED 的板级自检版本，采用 3.3 V LVTTL；可下载文件是 **Qproject/output_files_board/board_selftest.sof**。具体步骤及资料中的 Pro/Mini 标记差异见 [board/README.md](board/README.md)。

验证结果：18 项 ModelSim 测试通过（16,896 个核心 FIR 输出、122,880 个量化结果、512 个板级黄金比对），另覆盖板级故障注入与复位重跑。三个配置均编译成功且满足工作频率约束：核心性能配置 75 MHz、CDC 源 50 MHz、板级自检 50 MHz。现场观察确认 D6 心跳闪烁、D7 PASS 常亮、D8 FAIL 与 D9 RUN 熄灭，复位释放后可重测通过；实物结论限于单时钟版本。数值摘要见 verification_summary.json。

正式项目文档为 `doc/01_项目设计说明书.docx` 和 `doc/02_模块实现与验证报告.docx`，分别说明设计规格以及模块实现、验证结果、问题解决和技术问答。

参考：ARM IHI 0051A AXI4-Stream 规范、Altera 双时钟 FIFO 约束文档，以及本机 Quartus II 13.0.1 的 Tcl 命令帮助。现代工具文档与旧版约束能力的差异已在 Word 文档说明。
