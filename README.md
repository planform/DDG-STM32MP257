# DDG-STM32MP257

STM32MP257 板级开发工作区，OpenSTLinux 基线为 `v26.06.10`（Yocto Scarthgap，Linux 6.6.129）。

仓库提供 A35/Linux 与 M33 的开发目录、环境脚本及 TF-A、OP-TEE、U-Boot 构建入口；每台开发机独立安装工具链及第三方源码。

## 当前进度（2026-09-29）

DDG 的 TF-A、OP-TEE、U-Boot 已通过主机编译；FIP 已解包比对，FWU v2 元数据已校验 CRC、槽位和 GUID。
固定入口为 `make tfa`、`make optee`、`make uboot`、`make fip`、`make metadata`。
目前尚未上板验证，下一步是 eMMC 分区/烧录布局以及首次加载所需的下载模式固件。
`docs/linux/handoff-2026-09-28.md` 是此前换机记录，其中进度以本节为准。

## 目录约定

| 路径 | 用途 | Git |
| --- | --- | --- |
| `boards/ddg-stm32mp257/` | 板级设备树、配置片段、烧录布局 | 跟踪 |
| `scripts/` | 后续统一构建、环境和部署入口 | 跟踪 |
| `apps/linux/` | A35/Linux 应用 | 跟踪 |
| `apps/m33/` | M33 应用固件，各应用单独子目录 | 跟踪 |
| `modules/` | Linux 独立内核模块 | 跟踪 |
| `shared/ipc/` | 双核通信协议、共享头文件及说明 | 跟踪 |
| `boards/ddg-stm32mp257/m33/` | CubeMX 配置、板级代码及链接脚本 | 跟踪 |
| `toolchains/arm-gnu/` | M33 工具链，本机安装 | 仅目录占位 |
| `third_party/stm32cube/` | 固定版本的 Cube 包及依赖 | 仅目录占位 |
| `patches/` | 相对于 ST 基线的组件补丁 | 跟踪 |
| `docs/` | 安装和开发说明 | 跟踪 |
| `downloads/openstlinux/` | 下载的原始开发包 | 仅目录占位 |
| `openstlinux/sdk/` | 解开的 SDK 安装程序 | 仅目录占位 |
| `openstlinux/sdk-installed/` | 本机安装的 SDK | 仅目录占位 |
| `openstlinux/sources/ostl-linux/` | 第三方组件及解压后的源码 | 仅目录占位 |
| `build/ddg-stm32mp257/` | 编译中间文件 | 仅目录占位 |
| `deploy/ddg-stm32mp257/` | 最终产物 | 仅目录占位 |

安装步骤见 [docs/setup.md](docs/setup.md)。Git 不保存空目录，因此用 `.gitkeep` 保留目录骨架。

## 多机开发

- 每台机器克隆本仓库后，在本机安装相同版本 SDK、准备相同版本源码；不要同步安装后的 SDK。
- 共享脚本应从自身位置计算项目根目录，避免写死用户名和绝对路径。
- 本机覆盖配置可使用 `*.local.conf` 或 `*.local.mk`，这些文件不会提交。
- **`openstlinux/sources` 中的修改不会上传到本仓库。** 对第三方源码的修改应导出补丁到 `patches/` 并提交；也可以后续改用独立源码仓库，并明确记录其远程地址和提交号。
- 自研设备树、配置及业务代码优先保存在受版本管理的目录。
- 当前统一构建入口为 `make tfa`、`make optee`、`make uboot`，FIP 打包入口为 `make fip`，FWU 元数据入口为 `make metadata`。
- TF-A 板级设备树为 `stm32mp257d-ddg`，目标为 STM32MP257D、DDR4 2 GiB、eMMC 启动。

## TF-A 构建

安装 SDK，并将 Developer Package 的组件包放入 `openstlinux/sources/ostl-linux/` 后，在项目根目录执行：

```bash
make tfa
```

入口调用 `scripts/build-tfa.sh`，自动准备 TF-A 源码与 DDR PHY 固件、加载 A35 SDK，使用 SDK 内的
`aarch64-none-elf-` 工具链进行增量编译。可以从 Bash 或 Zsh 运行，无需提前
`source scripts/env-a35.sh`。构建脚本应执行，不应 source；也可以从任意目录运行
`bash /项目路径/scripts/build-tfa.sh`。

- 板级设备树：`boards/ddg-stm32mp257/tf-a/`，直接参与编译。
- 中间文件：`build/ddg-stm32mp257/tf-a/emmc/`。
- 日志：该目录内的 `build.log`，每次构建覆盖，同时显示在终端。
- 最终产物：`deploy/ddg-stm32mp257/tf-a/emmc/`，包含启动镜像、BL31、两个配置 DTB 和 DDR4 训练固件。

脚本固定使用已验证的 TF-A `v2.10.24-stm32mp-r3.1` 和 DDR PHY `A2022.11`，
版本与构建参数集中保存在脚本中。SDK 和源码根目录可分别通过已有的
`DDG_LINUX_SDK_ROOT`、`DDG_LINUX_SOURCE_ROOT` 环境变量指定（使用绝对路径）。
构建失败返回非零状态，不复制产物；之前的部署文件会保留，不能视为本次构建结果。
这里的部署仅整理本机文件，不执行烧录，也尚未生成完整 FIP。

## OP-TEE 构建

将官方 OP-TEE `4.0.0-stm32mp-r3.1` 组件包放入源码根目录后，在项目根目录执行：

```bash
make optee
```

入口调用 `scripts/build-optee.sh`，自动解压源码、字体并应用补丁，加载 A35 SDK，使用 `aarch64-ostl-linux-`
工具链增量编译 AArch64 运行时固件及 TA。保留 SDK 的 `LIBGCC_LOCATE_CFLAGS`
作为 `CFLAGS`，以正确定位 `libgcc.a`。构建配置为 `secure_and_system_services`，开启调试。
可从 Bash 或 Zsh 调用，无需提前加载环境；也可在其他目录执行
`bash /项目路径/scripts/build-optee.sh`，不要 source 构建脚本。

- 板级配置：`boards/ddg-stm32mp257/optee/`。
- 中间文件和日志：`build/ddg-stm32mp257/optee/runtime/` 下的产物及 `build.log`。
- 部署目录：`deploy/ddg-stm32mp257/optee/runtime/`，包含三个 `tee-*_v2.bin`。
- 调试符号：部署目录下的 `debug/tee.elf`。

`tee-pageable_v2.bin` 在 `CFG_WITH_PAGER=n` 时允许为空。构建输出实时显示并写入日志，
每次覆盖日志。失败返回非零状态并跳过产物复制，旧部署文件仍会保留。
SDK 和源码根目录使用与 TF-A 相同的环境变量覆盖方式。此入口只构建和整理文件，不进行 FIP 打包或烧录。

## U-Boot 构建

准备好 SDK 和 U-Boot `v2023.10-stm32mp-r3.1` 组件包后，在项目根目录执行：

```bash
make uboot
```

`scripts/build-uboot.sh` 自动加载 SDK、解压源码并应用补丁，使用官方
`stm32mp25_defconfig` 和 DDG 外部设备树构建。每次重新生成已知配置并将
`CONFIG_DEFAULT_DEVICE_TREE` 设为 `stm32mp257d-ddg`，已有目标文件用于增量编译。
因此不要依赖构建目录内手工修改的 `.config`；要持久化配置变更，应修改构建流程或保存配置片段。
脚本保留 SDK 的 sysroot 参数，并设置 `LANG=C`，避免 SDK 主机工具的 locale 警告。

- 板级文件：`boards/ddg-stm32mp257/u-boot/`。
- 外部设备树副本及中间文件：`build/ddg-stm32mp257/u-boot/external-dt/`。
- 构建目录：`build/ddg-stm32mp257/u-boot/runtime/`，含 `prepare.log` 和 `build.log`。
- 部署目录：`deploy/ddg-stm32mp257/u-boot/runtime/`，含 `u-boot.bin`、`u-boot-nodtb.bin`、`u-boot.dtb`。
- 调试 ELF：部署目录中的 `debug/u-boot`。

可以从 Bash 或 Zsh 调用，也可从任意目录执行 `bash /项目路径/scripts/build-uboot.sh`。
脚本在复制产物前检查 DTB 的 DDG 板卡标识。准备、配置或编译失败都会停止并跳过部署；
之前的部署文件会保留。此入口不执行 FIP 打包或烧录。

## FIP 打包

三个组件已成功构建并部署后，在项目根目录执行：

```bash
make fip
```

`scripts/pack-fip.sh` 自动加载 SDK，使用其 `fiptool` 打包已有部署产物，不触发组件重编译。
输入为 TF-A 的 DDR 固件、BL31、BL31 DTB、FW_CONFIG，OP-TEE 的三个 v2 BIN，
以及 U-Boot 的 `u-boot-nodtb.bin` 和 `u-boot.dtb`。
`tf-a-stm32mp257d-ddg.stm32` 独立供 BootROM 加载，不放入此 FIP。

输出位于 `deploy/ddg-stm32mp257/fip/emmc/`：`fip.bin` 和条目信息 `fip-info.txt`。
脚本先在临时目录打包，解包并逐项比对非空输入，全部通过后才替换正式 FIP。
缺少输入、打包或验证失败时返回非零并保留旧 FIP；空的 OP-TEE pageable 文件允许存在。
也可从其他目录执行 `bash /项目路径/scripts/pack-fip.sh`。

这个入口生成未签名、未加密的 eMMC 运行时 FIP，不创建分区、FWU 元数据或执行烧录。
需先分别运行组件构建入口，确保部署目录包含希望打包的最新产物。

## FWU 元数据

在项目根目录执行 `make metadata`，由 `scripts/gen-metadata.sh` 加载 SDK 和
`boards/ddg-stm32mp257/flash/fwu-metadata.conf`，调用 SDK 的 `mkfwumdata`。
当前布局固定使用 FWU v2、一个镜像类型和两个槽位；配置文件指定活动槽位、前一槽位、
两个槽位状态及 GUID。默认 A 槽位启动，A/B 均为已接受状态。

脚本先生成临时文件，再校验 120 字节结构、版本、CRC32、描述符、槽位状态、GUID 和接受标志，
成功后更新 `deploy/ddg-stm32mp257/flash/emmc/metadata.bin`。生成或校验失败保留旧文件。
可从任意目录执行 `bash /项目路径/scripts/gen-metadata.sh`，无需提前加载 SDK。

此入口只生成本机元数据，不重编译固件、不改写 eMMC。后续布局中的 `fip-a`、`fip-b`
分区唯一 GUID 必须与配置一致；`metadata1`、`metadata2` 初次写入同一份元数据。

## 源码准备与项目补丁

三个构建入口通过 `scripts/prepare-source.sh` 准备组件源码。每台开发机仍需自行安装 SDK，
并解开最外层 Developer Package，保留各组件目录内的源码压缩包、ST 补丁及 `series`；
OP-TEE 还需要 `fonts.tar.gz`，TF-A 需要 DDR PHY 组件包。脚本不下载软件包。

准备顺序为：解压组件源码 → 解压附加资源 → 按 ST `series` 应用官方补丁 →
按 `patches/tf-a/series`、`patches/optee/series` 或 `patches/u-boot/series` 应用项目补丁。
项目 `series` 支持空行、`#` 注释，以及每行一个相对补丁文件名（可带 `-p1`）；
补丁路径相对于该 `series`，按列出顺序应用。项目补丁及 `series` 应提交 Git。
当前 TF-A 和 OP-TEE 的项目 series 只有注释，U-Boot 暂无项目补丁；新增 U-Boot 补丁时创建
`patches/u-boot/series` 并列出补丁。板级 DTS 仍直接保存在 `boards/`，无需转成补丁。

首次准备在临时目录完成，全部成功后才放入最终源码目录。源码内的 `.ddg-source-state`
记录输入文件摘要；再次构建时输入一致则复用源码，不重复解压或打补丁。
已有手工准备的源码会与重新生成的基线逐文件比对，通过后记录状态，额外的构建文件允许保留。
状态记录不是源码完整性校验，后续本地源码修改会保留；需要共享的修改仍应导出为项目补丁。

压缩包、补丁或 series 变化时，脚本停止而不覆盖源码。先保存修改、将旧源码目录和对应组件
构建目录移到备份位置，再运行构建入口重新准备。没有状态记录且源码与基线不一致时也会停止，
避免覆盖未导出的修改。不要仅删除状态文件来强行重复应用补丁。

源码准备日志位于各组件构建目录的 `prepare.log`，编译日志仍为 `build.log`。
准备失败时不会进入编译或部署阶段。

## A35 与 M33 开发约定

- Linux 和 M33 应用分别放入 `apps/linux/<应用名>/` 与 `apps/m33/<应用名>/`。
- M33 编译中间文件放入 `build/ddg-stm32mp257/m33/<应用名>/<debug或release>/`；最终 ELF、BIN、MAP 等产物放入 `deploy/ddg-stm32mp257/m33/<应用名>/`。
- Linux 应用中间文件和产物分别放入对应的 `build/.../apps-linux/` 与 `deploy/.../apps-linux/`；`build/.../linux/` 仍用于内核。
- 尚未创建示例应用，应用名和 debug/release 子目录在实际创建工程时建立。
- 保留 CubeMX/CubeIDE 工程生成的原生结构，不强制搬动 Core/Drivers 等文件。工程实际引用的 `.ioc`、链接脚本、必要的生成代码和构建描述应提交；不要忽略整份 IDE 工程。
- `shared/ipc/` 保存协议约定；各核具体通信实现放在各自应用中。
- `docs/linux/` 与 `docs/m33/` 分别保存两侧开发说明。通用安装说明仍位于 `docs/setup.md`。
- Cube 包和 M33 工具链版本待选定；选定后记录版本、来源及校验值。对被忽略第三方依赖的修改必须保存补丁，或改用独立仓库管理。
- M33 环境目录目前为空；OpenSTLinux A35 SDK 的检查结果不代表 M33 开发环境已配置。
