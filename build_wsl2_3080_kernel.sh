#!/bin/bash
#
# =============================================================================
# WSL2 内核编译脚本 (AMD Ryzen 5 3500X)
# =============================================================================
#
# 直接使用微软官方 WSL2 内核配置，仅做 CPU 架构优化。
#
# 【硬件环境】
#   - CPU: AMD Ryzen 5 3500X (Zen2)
#   - 显卡: NVIDIA RTX 3080
#   - 内存: 19 GB
#   - 系统: WSL2 Ubuntu
#
# 【编译目标】
#   - 源码: git clone --branch linux-msft-wsl-6.6.y \
#           https://github.com/microsoft/WSL2-Linux-Kernel.git
#   - 配置: Microsoft/config-wsl (微软官方 WSL2 配置)
#   - 输出: arch/x86/boot/bzImage
#
# 【使用步骤】
#   1. 获取源码:
#      git clone --depth 1 --branch linux-msft-wsl-6.6.y \
#        https://github.com/microsoft/WSL2-Linux-Kernel.git \
#        /opt/linux/src/linux-6.6.141
#
#   2. 安装依赖:
#      sudo apt install -y build-essential flex bison dwarves \
#        libssl-dev libelf-dev cpio lz4 qemu-utils
#
#   3. 编译:
#      cd /opt/linux/src/linux-6.6.141
#      bash ~/my-shell/build_wsl2_3080_kernel.sh
#
#   4. 复制内核到 Windows:
#      cp arch/x86/boot/bzImage /mnt/c/Users/Administrator/wsl2-kernel
#
#   5. 编辑 C:\Users\Administrator\.wslconfig:
#      [wsl2]
#      kernel=C:\\Users\\Administrator\\wsl2-kernel
#
#   6. 重启 WSL2:
#      wsl --shutdown
#
# =============================================================================

set -e

SRC_DIR="/opt/linux/src/linux-6.6.141"
JOBS=$(nproc)
KERNEL_LOCALVERSION="-3080-$(date +%Y%m%d)"

# 确保在源码目录
if [ ! -d "$SRC_DIR" ]; then
    echo "错误: 内核源码目录 $SRC_DIR 不存在"
    echo "请先克隆微软 WSL2 内核源码:"
    echo "  git clone --depth 1 --branch linux-msft-wsl-6.6.y \\"
    echo "    https://github.com/microsoft/WSL2-Linux-Kernel.git \\"
    echo "    $SRC_DIR"
    exit 1
fi

cd "$SRC_DIR"

echo "========================================"
echo "开始编译 WSL2 内核"
echo "源码目录: $SRC_DIR"
echo "编译线程: $JOBS"
echo "本地版本: $KERNEL_LOCALVERSION"
echo "========================================"

# 1. 检查编译依赖
echo "[1/4] 检查编译依赖..."
MISSING_DEPS=""
for pkg in build-essential flex bison dwarves libssl-dev libelf-dev cpio lz4; do
    if ! dpkg -l | awk '{print $2}' | grep -qE "^${pkg}(:amd64|:all)?$"; then
        MISSING_DEPS="$MISSING_DEPS $pkg"
    fi
done

if [ -n "$MISSING_DEPS" ]; then
    echo "缺少编译依赖:$MISSING_DEPS"
    echo "请运行: sudo apt install -y$MISSING_DEPS"
    exit 1
fi
echo "所有依赖已安装"

# 2. 清理并复制官方配置
echo "[2/4] 准备编译环境..."
make clean 2>/dev/null || true

if [ ! -f Microsoft/config-wsl ]; then
    echo "错误: 找不到 Microsoft/config-wsl"
    echo "请确保使用的是微软 WSL2 内核源码"
    exit 1
fi

cp Microsoft/config-wsl .config
echo "已复制微软官方配置 Microsoft/config-wsl"

# 3. 仅优化 CPU 架构和版本号
echo "[3/4] 优化配置 (AMD Zen2)..."

# 设置 AMD Zen2 架构
scripts/config --set-val CONFIG_MZEN2 y
scripts/config --set-val CONFIG_GENERIC_CPU n
scripts/config --set-val CONFIG_MZEN n
scripts/config --set-val CONFIG_MZEN3 n
scripts/config --set-val CONFIG_MZEN4 n

# 设置本地版本号
scripts/config --set-str CONFIG_LOCALVERSION "$KERNEL_LOCALVERSION"

# 接受新配置项的默认值
make olddefconfig >/dev/null 2>&1

echo "配置优化完成"

# 4. 编译内核
echo "[4/4] 编译内核 (使用 $JOBS 线程)..."
echo "    预计 15-30 分钟，请耐心等待..."

make KCONFIG_CONFIG=.config -j$JOBS

# 5. 安装模块到本地目录
echo "安装内核模块..."
make INSTALL_MOD_PATH="$PWD/modules" modules_install

echo ""
echo "========================================"
echo "内核编译完成"
echo "========================================"
echo "bzImage: $SRC_DIR/arch/x86/boot/bzImage"
echo "模块:    $SRC_DIR/modules/"
echo ""
echo "使用方法:"
echo "  cp arch/x86/boot/bzImage /mnt/c/Users/Administrator/wsl2-kernel"
echo ""
echo "然后编辑 Windows 的 .wslconfig:"
echo '  kernel=C:\\Users\\Administrator\\wsl2-kernel'
echo ""
echo "重启 WSL2: wsl --shutdown"
echo "========================================"
