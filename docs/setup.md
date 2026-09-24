# SDK 与源码准备

以下命令供新机器首次配置时手动执行；已完成安装的机器无需重复运行。使用 Bash；SDK 安装完成后尽量不要移动安装目录。

## 1. 进入项目并设置本次终端变量

```bash
bash
cd ~/Space/DDG-STM32MP257
PROJECT_ROOT="$PWD"
RELEASE="openstlinux-6.6-yocto-scarthgap-mpu-v26.06.10"
PACKAGE_DIR="$HOME/Space/STM32MP257/downloads/openstlinux"
```

`PACKAGE_DIR` 指向当前已下载的压缩包；换电脑时先下载同版本开发包，也可以放在本项目 `downloads/openstlinux/` 下，并调整此变量。不必为安装额外复制一份大文件。

本机现有文件：

- `SDK-x86_64-stm32mp2-openstlinux-6.6-yocto-scarthgap-mpu-v26.06.10.tar.gz`
- `SOURCES-stm32mp-openstlinux-6.6-yocto-scarthgap-mpu-v26.06.10.tar.gz`

本 SDK 安装包针对 x86_64 Linux 主机；其他主机架构需使用 ST 对应安装包。

## 2. 解开 SDK 安装包并安装

```bash
tar -xzf "$PACKAGE_DIR/SDK-x86_64-stm32mp2-$RELEASE.tar.gz" \
  -C "$PROJECT_ROOT/openstlinux" --strip-components=1

bash "$PROJECT_ROOT/openstlinux/sdk/st-image-weston-openstlinux-weston-stm32mp2.rootfs-x86_64-toolchain-5.0.17-$RELEASE.sh" \
  -d "$PROJECT_ROOT/openstlinux/sdk-installed"
```

解压时去掉 ST 压缩包最外层版本目录，得到约定的 `openstlinux/sdk/`。安装时按提示操作，不需要把安装路径设为系统目录。

加载 SDK 并检查：

```bash
source "$PROJECT_ROOT/openstlinux/sdk-installed/environment-setup-cortexa35-ostl-linux"
echo "$CC"
echo "$CROSS_COMPILE"
$CC --version
```

`CROSS_COMPILE` 应为 `aarch64-ostl-linux-`。每个新的 Bash 终端需要重新加载环境；不建议全局写入 `.bashrc`，以免影响其他项目。

## 3. 解开源码开发包

```bash
tar -xzf "$PACKAGE_DIR/SOURCES-stm32mp-$RELEASE.tar.gz" \
  -C "$PROJECT_ROOT/openstlinux" --strip-components=1

cd "$PROJECT_ROOT/openstlinux/sources/ostl-linux"
ls
```

此时各组件目录包含上游源码压缩包、ST 补丁、配置及 README；还没有编译，也不代表所有组件内部源码都已展开。

## 4. 查看 ST 的源码准备流程

```bash
cd "$PROJECT_ROOT/openstlinux/sources/ostl-linux"
less sdk-infos-1.1-r0/README.HOW_TO.txt.stm32mp2
less linux-stm32mp-6.6.129-stm32mp-r3.1-r0/README.HOW_TO.txt.stm32mp2
```

后续可以利用 ST 脚本生成器：

```bash
cd "$PROJECT_ROOT/openstlinux/sources/ostl-linux/sdk-infos-1.1-r0"
bash generated_build_script-stm32mpx.sh stm32mp2
```

它会在上一级生成构建脚本及配套文件。此步骤只生成脚本，不编译。

必须先配置 SDK 路径、设备树、板型、输出目录及启动介质，才能运行生成脚本的 `extract` 等动作。`extract` 会进一步解压组件源码并应用补丁；不要在已有本地修改后重复执行。

`stm32mp2` 是普通 A35 trusted-domain 流程示例；是否采用它，以及是否需要 M33 trusted-domain 流程，须结合板上现有 BSP 确认。不要把 ST 官方 DK/EV1 的板名直接当作 DDG 板硬件适配。

本次只准备目录，因此没有创建或配置任何生成脚本。

## 5. 首次提交并上传 GitHub

在项目根目录检查后自行提交：

```bash
cd ~/Space/DDG-STM32MP257
git status --short
git add .
git diff --cached --stat
git commit -m "Initialize DDG-STM32MP257 workspace"
```

在 GitHub 创建空仓库后，把下面的示例 URL 换成自己的地址：

```bash
git remote add origin git@github.com:YOUR_ACCOUNT/DDG-STM32MP257.git
git push -u origin main
```

其他机器 `git clone` 后，重新按本文准备 SDK 和第三方源码。自己的组件修改必须先保存为受跟踪的补丁或提交到独立源码仓库，再切换机器；仅提交顶层仓库不会同步被忽略的源码目录。
