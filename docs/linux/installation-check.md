# 本机 SDK/source 检查记录

检查日期：2026-09-23。仅记录此次本机检查，不代表其他机器或目标板的状态。

- SDK 安装位置：项目内 `openstlinux/sdk-installed/`。
- SDK 版本文件：`5.0.17-openstlinux-6.6-yocto-scarthgap-mpu-v26.06.10`。
- 成功在 Bash 中加载 `environment-setup-cortexa35-ostl-linux`。
- 编译器：`aarch64-ostl-linux-gcc (GCC) 13.4.0`；sysroot 指向本项目安装目录。
- 使用 SDK 的 CC、CFLAGS、LDFLAGS 编译并链接包含 stdio.h 和 puts 的最小 C 程序，成功生成 64 位 ARM AArch64 ELF，解释器为 `/lib/ld-linux-aarch64.so.1`。测试文件仅放在 `/tmp`，未写入应用目录。
- 将下载的 SOURCES v26.06.10 压缩包内 91 个普通文件，与 `openstlinux/sources/ostl-linux/` 中对应文件逐字节比较，全部一致。此检查验证解压一致性，不验证下载来源真实性。
- 源码目前为外层开发包解压状态：内部组件仍是 tarball、补丁和说明文件，尚未展开并应用补丁。
- 未编译内核、启动链或 M33 固件，未在目标板运行程序；板上系统与 SDK 的兼容性尚未验证。
- 新增 M33 工具链与 Cube 包目录仅为占位，未安装 M33 环境。
