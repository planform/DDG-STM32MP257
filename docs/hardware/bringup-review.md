# DDG-DLMP257 首次启动资料核对

检查日期：2026-09-25。本文是原理图与源码的静态核对结果，尚未编译或上板验证。

依据：

- `SCH_DDG-DLMP257_BD_2026-09-25.pdf`，共 7 页；页码按 PDF 顺序。
- `【正点原子】ATK-CLMP257B核心板接口数据手册V1.2.xlsx`，工作表 `ABCD座子`。下文 A/B/C/D 为核心板连接器编号。
- 本机 OpenSTLinux v26.06.10 开发包中的 external-dt v6.0-stm32mp-r3.1、Linux 6.6.129 源码及 ST 补丁。

Excel 中的“出厂系统默认配置”指厂家底板，DDG 的实际用途以本项目原理图为准。未连接的引脚不能仅因 Excel 标了某外设就启用。

## 已确认的最小启动连接

| 功能 | DDG 连接 | 来源与适配要点 |
| --- | --- | --- |
| 调试串口通道 0 | USART1 TX=PG14（A54），RX=PG15（A53），AF6 | PDF 第 1、3 页；CH342F 的 RXD0/TXD0 分别连接 SoC TX/RX。建议作为 A35 控制台，115200n8 为初始配置建议。 |
| 调试串口通道 1 | UART4 TX=PB7（D51），RX=PB6（D52），AF3 | PDF 第 1、3 页；接 CH342F RXD1/TXD1。后续用途与 A35/M33 资源分配一起确定。 |
| USART2 | A51/A52 在底板标为未连接 | PDF 第 1 页。当前 ST EV1 示例的控制台为 USART2，不能照搬。 |
| TF 卡 | SDMMC1，4 bit；CLK=PE3，CMD=PE2，D0=PE4，D1=PE5，D2=PE0，D3=PE1 | PDF 第 1、7 页；D21～D26。卡供电来自 VDD_SDOUT，上拉来自 VDDIO_SDOUT；两条电源在核心板内的来源待确认。 |
| TF 卡检测 | PI8（D20），CD# | PDF 第 7 页：上拉、插卡接地，对应低有效检测。ST EV1 示例使用 PD9，需要修改。 |
| 用户 LED | PH4（A55），LED0，低有效 | PDF 第 5 页：VCC3.3 经电阻及 LED 接到 LED0。 |
| 用户按键 | KEY1=PH5（A16），KEY2=PI6（B36），低有效 | PDF 第 1、5 页；均有外部上拉，按下接地。 |
| 核心板输入电源 | VCC5，A76～A80 | PDF 第 1、5 页；底板另有 VCC3.3、VCC5_USB 等电源，不能据此推断核心板 PMIC 的 regulator 配置。 |

DEBUG Type-C 接 CH342F；原生 USB 数据通路接另一个标为 OTG 的 Type-C。两者用途必须区分。ROM 支持哪些 UART 下载引脚仍需核对，不能由 Linux 串口可用推导 ROM 下载可用。

PDF 第 1 页的 BOOT 表标注 BOOT3..0：`0000` 为 UART/USB，A35 `0001` 为 SD 卡、`0010` 为 eMMC。此处仅记录图纸标注；首次上电前还要核对实际拨码、电平和核心板版本，不能把位值直接当作开关 ON/OFF 方向。

## 后续外设连接

| 外设 | 已确认连接 | 后续工作 |
| --- | --- | --- |
| 千兆以太网 | ETH1 + YT8531C-CA；PHY 地址图纸标注 4；RESET=PF3（C13），INT=PA12（C21），MDIO=PF2，MDC=PF0 | PDF 第 4 页。核对 `eth1` pinctrl、复位时序、PHY 驱动和 RGMII 延时。ETH2 多个脚在 DDG 上用于扩展 GPIO，不能启用厂家双网口配置。 |
| PHY 时钟 | PHY 有 25MHz 晶体；CLKOUT 到 ETH1_CLK125 的 R78 标为 DNP | 不应直接假定 MAC 接收 PHY 的 125MHz CLKOUT。图纸标注 TXC/RXC 无 2ns 延时，最终 `phy-mode` 和延时参数需结合 PCB、实际贴装和驱动确定。 |
| USB OTG | USB3_D±（C8/C9）；FUSB302 在 I2C2；SCL=PB5（D9），SDA=PB4（D8）；INT=PZ6，VBUS 开关控制=PZ5 | PDF 第 1、6 页。核对 Type-C 角色切换、VBUS regulator、控制器与 PHY；DEBUG 串口芯片不能替代这条原生 USB 通路。 |
| USB Host | USBH_D±（C5/C6）接 CH334R Hub；下游接 USB 插座及 RTL8733BUUA | PDF 第 6、7 页。Wi-Fi/BT 使用 USB 通路；驱动支持待单独检查。 |
| CAN | FDCAN1 TX/RX=PB9/PB11；FDCAN2 TX/RX=PI9/PI10；TPT1051VQ 收发器 | PDF 第 3、6 页；初次启动后再确定 Linux/M33 归属。 |
| EEPROM | AT24C64，I2C4：SCL=PD11、SDA=PD10；A0/A1/A2 接地 | PDF 第 7 页。器件地址按 datasheet/驱动 binding 再核对。 |
| SPI Flash | W25Q128JVSIQ，SPI8：SCK=PZ2、MISO=PZ1、MOSI=PZ0、NSS=PZ3 | PDF 第 7 页；不可直接当成 ST 示例里的 OSPI 启动闪存。 |
| 音频 | ES8388，I2C4 + SAI1；MCLK_B=PD7、SCK_B=PD6、FS_B=PD5、SD_B=PD4、SD_A=PD9 | PDF 第 2 页。AUDIO_RST=PD12（D30）在本图连接功放 CTRL，不能只按网名当成 codec 复位。 |
| 显示 | MIPI DSI 两条数据 lane；触摸 I2C8：SCL=PZ4、SDA=PZ9；触摸 RST=PB1、INT=PB2；面板 RESET=PI11、TE=PB12 | PDF 第 7 页。还缺具体面板/触摸型号、时序和初始化序列。 |
| 摄像头 | MIPI CSI 两条数据 lane，I2C4；RESET=PG4、PWDN=PG3 | PDF 第 7 页；还缺实际摄像头型号。 |
| 风扇/RGB LED | FAN_PWM=PB10，RGB_LED_DIN=PF13 | PDF 第 1、5 页；风扇输出级存在 DNP 元件，按实际贴装配置。 |

Linux 6.6.129 原始包的 `drivers/net/phy/motorcomm.c` 已有 YT8531 支持，`Documentation/devicetree/bindings/net/motorcomm,yt8xxx.yaml` 包含延时等属性。后续先核对已有驱动及配置，无需先假设必须新增 PHY 驱动；仍需读取实际 PHY ID 并上板验证。

## 与 ST 示例的差异及修改范围

external-dt 的 `stm32mp2/a35-td/` 下分别有 `tf-a/`、`optee/`、`u-boot/`、`linux/`。已检查 `stm32mp257f-ev1-ca35tdcid-ostl` 系列作为结构参考，不代表选定 EV1 为 DDG 硬件基线。

- 四个阶段都要核对控制台、引脚和访问权限；仅改 Linux `stdout-path` 无法保证早期日志可见。
- 创建 DDG 专用的两线 USART1 pinctrl。ST Linux 补丁中 `stm32mp25-pinctrl.dtsi` 的 `usart1_pins_a` 使用 PG14 TX、PG15 RX，与 DDG 一致，但还包含 PI2/PI3 硬件流控，应按本板两线连接裁剪，并同步考虑 idle/sleep 状态。开发包也包含其他 MP2 型号的同名 pinctrl，核对时必须限定 STM32MP25。
- TF-A：核心板 DDR 配置、供电、时钟、串口、启动存储及配套 FW_CONFIG。
- OP-TEE：PMIC、电源、时钟、RIF 资源权限和安全内存；控制台及后续 M33 外设分配要一致。
- U-Boot：串口、TF/eMMC、必要的 USB 下载支持、启动配置和镜像加载。
- Linux：串口、SDMMC1 检测/供电、内存和保留区、LED/按键；进入 shell 后再逐项加入外设。
- 内存大小与保留区必须跨启动阶段保持一致。ST EV1 示例的 TF-A 配置是 4GiB DDR4，不能套用到未知容量的核心板。
- 启动还需要匹配的 rootfs、分区布局、FIP/DDR PHY 固件等产物；当前 SDK + SOURCES 不等于已经准备好可烧录系统镜像。

建议板级文件保存在 `boards/ddg-stm32mp257/`，构建脚本放 `scripts/`，驱动等第三方源码修改保存为 `patches/` 中的补丁；后续构建引用这些受版本管理的文件。

## 核心板资料缺口与公开来源

用户反馈目前没有厂家 BSP、出厂镜像或核心板内部原理图。

厂家公开页面列出 ATK-CLMP257B 使用 STM32MP257DAK3、DDR4 1GB/2GB、eMMC 8GB/16GB、STPMIC25。这只是产品系列信息，不能确定手头核心板的实际容量、版本及配置：

- [厂家核心板资源说明](https://wiki.alientek.com/docs/Boards/Linux/STM32MP257/STM32MP257%20硬件参考手册/1/1.2/)
- [厂家公开资料仓库](https://github.com/openedv/development_board_ATK-DLMP257)
- [代码下载入口](https://github.com/openedv/development_board_ATK-DLMP257/tree/main/1_codes)：README 指向外部网盘，本次未下载或验证其内容与版本。
- [厂家原理图目录](https://github.com/openedv/development_board_ATK-DLMP257/tree/main/2_sch)：列出 ATK-DLMP257B 底板原理图，尚未确认其中包含核心板内部设计。

在生成可上板的完整启动镜像前，需要确认：

1. 核心板实际型号/硬件版本、SoC 丝印和 DDR/eMMC 容量。
2. DDR 颗粒型号、组织方式、频率和经过验证的初始化参数；容量本身不足以生成这些参数。
3. PMIC 具体版本、I2C 连接、各路电压/用途、时钟源和核心板电源时序。
4. eMMC 连接与电源、启动域方案（A35-TD 或 M33-TD）、板上是否已有可启动系统。
5. 第一阶段用 SD 卡还是 eMMC，以及采用的 rootfs 和镜像分区布局。

优先从厂家 BSP 获取同核心板的初始化配置，再核对并移植到 v26.06.10。若无法取得 BSP，需要核心板内部设计与 DDR 资料，使用对应工具生成并验证初始化配置，不能用猜测值替代。

## 建议的验证顺序

1. 补齐核心板参数，以 A35 + TF 卡最小启动作为候选方案，最终由硬件和启动域要求确定。
2. 验证 USART1 输出早期日志，再验证 DDR 初始化与 TF 卡读取，进入 U-Boot。
3. 启动 Linux 并挂载 rootfs，通过串口进入 shell；验证 LED、按键、存储读写。
4. 加入 ETH1 和 USB，再逐项加入 CAN、音频、显示、摄像头和 M33 应用。

本次只做资料核对及记录，未修改 OpenSTLinux 源码或生成烧录镜像。
