#!/bin/bash
#
# =============================================================================
# WSL2 内核编译脚本 (AMD Ryzen 5 3500X)
# =============================================================================
#
# 基于微软官方 Microsoft/config-wsl 配置，仅精简具体硬件芯片驱动。
# 保留所有 WSL2 必需的核心基础设施。
#
# 【关键原则】
#   - 只关闭具体的物理芯片驱动（如 e1000e、r8169、i915 等）
#   - 不关闭核心基础设施（如 USB_SUPPORT、ATA、NVME_CORE、DRM 等）
#   - dxgkrnl GPU 驱动依赖 DRM 基础设施，全部保留
#
# 【使用步骤】
#   1. 获取源码:
#      git clone --depth 1 --branch linux-msft-wsl-6.6.y \
#        https://github.com/microsoft/WSL2-Linux-Kernel.git \
#        /opt/linux/src/linux-6.6.141
#
#   2. 安装依赖:
#      sudo apt install -y build-essential flex bison dwarves \
#        libssl-dev libelf-dev cpio lz4
#
#   3. 编译:
#      cd /opt/linux/src/linux-6.6.141
#      bash ~/my-shell/build_wsl2_3080_kernel.sh
#
#   4. 复制内核:
#      cp arch/x86/boot/bzImage /mnt/c/Users/Administrator/wsl2-kernel
#
#   5. 编辑 C:\Users\Administrator\.wslconfig:
#      [wsl2]
#      kernel=C:\\Users\\Administrator\\wsl2-kernel
#
#   6. 重启 WSL2:
#      wsl --shutdown
# =============================================================================

set -e

SRC_DIR="/opt/linux/src/linux-6.6.141"
JOBS=$(nproc)
KERNEL_LOCALVERSION="-3080-$(date +%Y%m%d)"

if [ ! -d "$SRC_DIR" ]; then
    echo "错误: 内核源码目录 $SRC_DIR 不存在"
    echo "请先克隆微软 WSL2 内核源码"
    exit 1
fi

cd "$SRC_DIR"

echo "========================================"
echo "开始编译 WSL2 内核"
echo "源码目录: $SRC_DIR"
echo "编译线程: $JOBS"
echo "========================================"

# 1. 检查依赖
echo "[1/5] 检查编译依赖..."
MISSING_DEPS=""
for pkg in build-essential flex bison dwarves libssl-dev libelf-dev cpio lz4; do
    if ! dpkg -l | awk '{print $2}' | grep -qE "^${pkg}(:amd64|:all)?$"; then
        MISSING_DEPS="$MISSING_DEPS $pkg"
    fi
done

if [ -n "$MISSING_DEPS" ]; then
    echo "缺少依赖:$MISSING_DEPS"
    echo "运行: sudo apt install -y$MISSING_DEPS"
    exit 1
fi
echo "依赖已安装"

# 2. 清理并复制官方配置
echo "[2/5] 准备官方配置..."
make clean 2>/dev/null || true

if [ ! -f Microsoft/config-wsl ]; then
    echo "错误: 找不到 Microsoft/config-wsl"
    exit 1
fi

cp Microsoft/config-wsl .config
echo "已复制 Microsoft/config-wsl"

# 3. 优化 CPU 架构
echo "[3/5] 优化 CPU 架构 (AMD Zen2)..."
scripts/config --set-val CONFIG_MZEN2 y
scripts/config --set-val CONFIG_GENERIC_CPU n
scripts/config --set-val CONFIG_MZEN n
scripts/config --set-val CONFIG_MZEN3 n
scripts/config --set-val CONFIG_MZEN4 n
scripts/config --set-str CONFIG_LOCALVERSION "$KERNEL_LOCALVERSION"

# 4. 精简具体硬件驱动（只关芯片驱动，不关核心基础设施）
echo "[4/5] 精简物理硬件芯片驱动..."

# ===== 物理以太网芯片驱动（WSL2 不需要，网络走 VirtIO/Hyper-V）=====
echo "  - 关闭物理网卡芯片驱动"
for nic in E1000E R8169 IGB IXGBE IXGBEVF I40E IAVF FM10K E1000; do
    scripts/config --set-val CONFIG_${nic} n 2>/dev/null || true
done

# 禁用大量网卡供应商（保留 VirtIO、Hyper-V、Microsoft）
for vendor in 3COM ADAPTEC ALTEON AMD AQUANTIA ATHEROS BROADCOM CADENCE CAVIUM CHELSIO CISCO CORTINA DEC DLINK EMULEX FUJITSU HISILICON HUAWEI JME LITEX MARVELL MELLANOX MICREL MICROCHIP MICROSEMI MYRI NATSEMI NETERION NETRONOME OKI PACKET_ENGINES PENSANDO QLOGIC QUALCOMM RDC RENESAS ROCKER SAMSUNG SEEQ SILAN SIS SMSC SOLARFLARE STMICRO SUN SYNOPSYS TEHUTI TI VERTEXCOM VIA WANGXUN XILINX; do
    scripts/config --set-val CONFIG_NET_VENDOR_${vendor} n 2>/dev/null || true
done

# ===== 物理 GPU 驱动（WSL2 通过 dxgkrnl 使用宿主机 GPU，不需要这些）=====
echo "  - 关闭物理 GPU 驱动 (amdgpu/nouveau/radeon/i915)"
# 关闭所有物理 GPU DRM 驱动
scripts/config --set-val CONFIG_DRM_AMDGPU n 2>/dev/null || true
scripts/config --set-val CONFIG_DRM_AMDGPU_CIK n 2>/dev/null || true
scripts/config --set-val CONFIG_DRM_AMDGPU_SI n 2>/dev/null || true
scripts/config --set-val CONFIG_DRM_AMDGPU_USERPTR n 2>/dev/null || true
scripts/config --set-val CONFIG_DRM_RADEON n 2>/dev/null || true
scripts/config --set-val CONFIG_DRM_NOUVEAU n 2>/dev/null || true
scripts/config --set-val CONFIG_NOUVEAU_LEGACY_CTX_SUPPORT n 2>/dev/null || true
scripts/config --set-val CONFIG_DRM_I915 n 2>/dev/null || true
scripts/config --set-val CONFIG_DRM_VIRTIO_GPU n 2>/dev/null || true
# 保留 CONFIG_DRM（dxgkrnl 依赖的基础 DRM 子系统）
# 保留 CONFIG_DRM_KMS_HELPER
# 保留 CONFIG_DRM_SIMPLEDRM（WSL2 虚拟显卡需要）

# ===== Wi-Fi / 蓝牙（WSL2 网络不走这些）=====
echo "  - 关闭 Wi-Fi / 蓝牙芯片驱动"
scripts/config --set-val CONFIG_IWLWIFI n 2>/dev/null || true
scripts/config --set-val CONFIG_IWLDVM n 2>/dev/null || true
scripts/config --set-val CONFIG_IWLMVM n 2>/dev/null || true
scripts/config --set-val CONFIG_RT2X00 n 2>/dev/null || true
scripts/config --set-val CONFIG_RTLWIFI n 2>/dev/null || true
scripts/config --set-val CONFIG_ATH10K n 2>/dev/null || true
scripts/config --set-val CONFIG_ATH9K n 2>/dev/null || true
scripts/config --set-val CONFIG_B43 n 2>/dev/null || true
scripts/config --set-val CONFIG_BRCMFMAC n 2>/dev/null || true
scripts/config --set-val CONFIG_MT76 n 2>/dev/null || true

# ===== 物理声卡驱动（WSL2 音频通过 WSLg/PulseAudio）=====
echo "  - 关闭物理声卡芯片驱动"
# 保留 CONFIG_SOUND 和 CONFIG_SND 基础设施（WSLg 需要）
# 只关闭具体的芯片驱动
scripts/config --set-val CONFIG_SND_HDA_INTEL n 2>/dev/null || true
scripts/config --set-val CONFIG_SND_HDA_CODEC_REALTEK n 2>/dev/null || true
scripts/config --set-val CONFIG_SND_HDA_CODEC_HDMI n 2>/dev/null || true
scripts/config --set-val CONFIG_SND_ENS1371 n 2>/dev/null || true
scripts/config --set-val CONFIG_SND_USB_AUDIO n 2>/dev/null || true
scripts/config --set-val CONFIG_SND_SOC_INTEL_SST_TOPLEVEL n 2>/dev/null || true

# ===== USB 物理主机控制器（WSL2 用 USBIP，不需要物理 HCI）=====
echo "  - 关闭 USB 物理主机控制器"
# 保留 CONFIG_USB_SUPPORT 核心（USBIP 需要）
# 只关闭具体的 HCI 驱动
scripts/config --set-val CONFIG_USB_XHCI_HCD n 2>/dev/null || true
scripts/config --set-val CONFIG_USB_EHCI_HCD n 2>/dev/null || true
scripts/config --set-val CONFIG_USB_OHCI_HCD n 2>/dev/null || true
scripts/config --set-val CONFIG_USB_UHCI_HCD n 2>/dev/null || true

# ===== 物理 SATA/NVMe 控制器（WSL2 磁盘走 VirtIO）=====
echo "  - 关闭物理 SATA/NVMe 控制器"
# 保留 NVME_CORE（某些虚拟化场景需要）
# 关闭具体的芯片驱动
scripts/config --set-val CONFIG_SATA_AHCI n 2>/dev/null || true
scripts/config --set-val CONFIG_SATA_NV n 2>/dev/null || true
scripts/config --set-val CONFIG_SATA_SIL n 2>/dev/null || true
scripts/config --set-val CONFIG_SATA_MV n 2>/dev/null || true
scripts/config --set-val CONFIG_SATA_PIIX n 2>/dev/null || true
scripts/config --set-val CONFIG_ATA_PIIX n 2>/dev/null || true

# ===== 摄像头/媒体/电视 =====
echo "  - 关闭摄像头/媒体驱动"
scripts/config --set-val CONFIG_USB_GSPCA n 2>/dev/null || true
scripts/config --set-val CONFIG_USB_VIDEO_CLASS n 2>/dev/null || true
scripts/config --set-val CONFIG_MEDIA_SUPPORT n 2>/dev/null || true
scripts/config --set-val CONFIG_MEDIA_CAMERA_SUPPORT n 2>/dev/null || true
scripts/config --set-val CONFIG_MEDIA_ANALOG_TV_SUPPORT n 2>/dev/null || true
scripts/config --set-val CONFIG_MEDIA_DIGITAL_TV_SUPPORT n 2>/dev/null || true
scripts/config --set-val CONFIG_DVB_CORE n 2>/dev/null || true

# ===== 打印/看门狗/硬件监控 =====
echo "  - 关闭打印/看门狗/硬件监控"
scripts/config --set-val CONFIG_PRINTER n 2>/dev/null || true
scripts/config --set-val CONFIG_WATCHDOG n 2>/dev/null || true
scripts/config --set-val CONFIG_HWMON n 2>/dev/null || true
scripts/config --set-val CONFIG_SENSORS_CORETEMP n 2>/dev/null || true
scripts/config --set-val CONFIG_SENSORS_K10TEMP n 2>/dev/null || true

# ===== 嵌入式 SoC =====
echo "  - 关闭嵌入式 SoC 驱动"
for arch in ACTIONS SUNXI ALPINE APPLE BCM BERLIN BITMAIN EXYNOS SPARX5 K3 LG1K HISI KEEMBAY MEDIATEK MESON MVEBU NXP MA35 NPCM QCOM REALTEK RENESAS ROCKCHIP SEATTLE INTEL_SOCFPGA STM32 SYNQUACER TEGRA SPRD THUNDER THUNDER2 UNIPHIER VEXPRESS VISCONTI XGENE ZYNQMP; do
    scripts/config --set-val CONFIG_ARCH_${arch} n 2>/dev/null || true
done

# ===== 其他物理硬件 =====
echo "  - 关闭其他物理硬件驱动"
# PCMCIA/CardBus
scripts/config --set-val CONFIG_PCCARD n 2>/dev/null || true
scripts/config --set-val CONFIG_PCMCIA n 2>/dev/null || true
# FireWire
scripts/config --set-val CONFIG_FIREWIRE n 2>/dev/null || true
# Thunderbolt
scripts/config --set-val CONFIG_THUNDERBOLT n 2>/dev/null || true
# Infiniband
scripts/config --set-val CONFIG_INFINIBAND n 2>/dev/null || true
# 光纤通道
scripts/config --set-val CONFIG_SCSI_FC_ATTRS n 2>/dev/null || true
# RAID（WSL2 不需要）
scripts/config --set-val CONFIG_MD_RAID0 n 2>/dev/null || true
scripts/config --set-val CONFIG_MD_RAID1 n 2>/dev/null || true
scripts/config --set-val CONFIG_MD_RAID10 n 2>/dev/null || true
scripts/config --set-val CONFIG_MD_RAID456 n 2>/dev/null || true

# 更新配置，自动处理依赖
echo "  - 更新配置依赖..."
make olddefconfig > /dev/null 2>&1

echo "配置精简完成"

# 5. 编译内核
echo "[5/5] 编译内核 (使用 $JOBS 线程)..."
echo "    预计 15-25 分钟..."

make KCONFIG_CONFIG=.config -j$JOBS

# 6. 安装模块
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
echo '  .wslconfig 添加: kernel=C:\\Users\\Administrator\\wsl2-kernel'
echo ""
echo "  wsl --shutdown"
echo "========================================"
