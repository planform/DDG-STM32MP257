# DDG-STM32MP257

STM32MP257 板级开发工作区，OpenSTLinux 基线为 `v26.06.10`（Yocto Scarthgap，Linux 6.6.129）。

仓库提供 A35/Linux 与 M33 的目录骨架和 Git 忽略规则；每台开发机独立安装工具链及第三方源码。尚未创建统一构建脚本。

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
- 目前未创建 Makefile、board.conf 或构建脚本；未来统一入口可采用 `make kernel`、`make dtbs` 等。
- 板级设备树名称、芯片具体型号、启动介质和 BSP 基线尚待确认。

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
