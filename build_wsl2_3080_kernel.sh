#!/bin/bash
# =============================================================================
# WSL2 内核编译脚本 —— AMD Ryzen 5 3500X 优化版
# =============================================================================
#
# 基于微软官方 Microsoft/config-wsl 配置,只精简具体硬件芯片驱动。
# 保留所有 WSL2 必需的核心基础设施。
#
# 关键原则:
#   - 只关闭具体的物理芯片驱动(如 e1000e、r8169、i915 等)
#   - 不关闭核心基础设施(如 USB_SUPPORT、ATA、NVME_CORE、DRM 等)
#   - dxgkrnl GPU 驱动依赖 DRM 基础设施,全部保留
#
# 使用步骤:
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
#
# v2.0 重构要点:
#   - 通用精简(网卡/SoC/RAID/外设)抽到 lib_kernel_config.sh
#   - 修复 6.6+ Kconfig 中无 MZEN2 的问题,自动回退到 KCFLAGS
#   - 保留官方配置理念(只关物理驱动,保留基础设施)
# =============================================================================

# 加载共享库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_kernel_config.sh
source "$SCRIPT_DIR/lib_kernel_config.sh"
lib_setup_strict_mode

# -----------------------------------------------------------------------------
# 全局变量
# -----------------------------------------------------------------------------
SRC_DIR="/opt/linux/src/linux-6.6.141"
KERNEL_LOCALVERSION="-3080-$(date +%Y%m%d)"
LOG_FILE="/tmp/build_wsl2_3080_$(date +%Y%m%d_%H%M%S).log"

# -----------------------------------------------------------------------------
# 初始化
# -----------------------------------------------------------------------------
if [[ ! -d "$SRC_DIR" ]]; then
    echo "错误: 内核源码目录 $SRC_DIR 不存在" | tee -a "$LOG_FILE"
    echo "请先克隆微软 WSL2 内核源码:"
    echo "  git clone --depth 1 --branch linux-msft-wsl-6.6.y \\"
    echo "    https://github.com/microsoft/WSL2-Linux-Kernel.git \\"
    echo "    $SRC_DIR"
    exit 1
fi
cd "$SRC_DIR"

JOBS=$(nproc)
echo "========================================" | tee -a "$LOG_FILE"
echo "开始编译 WSL2 内核 - $(date)" | tee -a "$LOG_FILE"
echo "源码目录: $SRC_DIR" | tee -a "$LOG_FILE"
echo "编译线程: $JOBS" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"

# -----------------------------------------------------------------------------
# [1/5] 检查依赖
# -----------------------------------------------------------------------------
echo "[1/5] 检查编译依赖..." | tee -a "$LOG_FILE"
if ! check_deps build-essential flex bison dwarves \
                libssl-dev libelf-dev cpio lz4; then
    exit 1
fi
echo "依赖已安装" | tee -a "$LOG_FILE"

# -----------------------------------------------------------------------------
# [2/5] 清理并复制官方配置
# -----------------------------------------------------------------------------
echo "[2/5] 准备官方配置..." | tee -a "$LOG_FILE"
make clean >> "$LOG_FILE" 2>&1 || true

if [[ ! -f Microsoft/config-wsl ]]; then
    echo "错误: 找不到 Microsoft/config-wsl" | tee -a "$LOG_FILE"
    exit 1
fi
cp Microsoft/config-wsl .config
echo "已复制 Microsoft/config-wsl" | tee -a "$LOG_FILE"

# -----------------------------------------------------------------------------
# [3/5] 优化 CPU 架构
# -----------------------------------------------------------------------------
echo "[3/5] 优化 CPU 架构 (AMD Zen2)..." | tee -a "$LOG_FILE"
# 注意:6.6 内核还有 MZEN2 这个 Kconfig 选项,这里直接设置
# 库函数 optimize_cpu 会自动适配 6.8+ 的 KCFLAGS 方式
optimize_cpu "znver2" "AMD Ryzen 5 3500X (WSL2)"

set_kconfig CONFIG_LOCALVERSION "$KERNEL_LOCALVERSION"

# -----------------------------------------------------------------------------
# [4/5] 精简物理硬件芯片驱动
#   关键原则: 只关芯片驱动,不关核心基础设施
# -----------------------------------------------------------------------------
echo "[4/5] 精简物理硬件芯片驱动..." | tee -a "$LOG_FILE"

# 物理以太网芯片(WSL2 网络走 VirtIO/Hyper-V)
echo "  - 关闭物理网卡芯片驱动" | tee -a "$LOG_FILE"
disable_physical_nics

# 物理 GPU(WSL2 通过 dxgkrnl 使用宿主机 GPU)
echo "  - 关闭物理 GPU 驱动 (amdgpu/nouveau/radeon/i915)" | tee -a "$LOG_FILE"
# 保留 CONFIG_DRM(dxgkrnl 依赖)
# 保留 CONFIG_DRM_KMS_HELPER
# 保留 CONFIG_DRM_SIMPLEDRM(WSL2 虚拟显卡需要)
set_kconfig_safe CONFIG_DRM_AMDGPU n
set_kconfig_safe CONFIG_DRM_AMDGPU_CIK n
set_kconfig_safe CONFIG_DRM_AMDGPU_SI n
set_kconfig_safe CONFIG_DRM_AMDGPU_USERPTR n
set_kconfig_safe CONFIG_DRM_RADEON n
set_kconfig_safe CONFIG_DRM_NOUVEAU n
set_kconfig_safe CONFIG_NOUVEAU_LEGACY_CTX_SUPPORT n
set_kconfig_safe CONFIG_DRM_I915 n
set_kconfig_safe CONFIG_DRM_VIRTIO_GPU n

# Wi-Fi/蓝牙
echo "  - 关闭 Wi-Fi/蓝牙芯片驱动" | tee -a "$LOG_FILE"
wifis=(IWLWIFI IWLDVM IWLMVM RT2X00 RTLWIFI ATH10K ATH9K B43 BRCMFMAC MT76)
for wf in "${wifis[@]}"; do
    set_kconfig_safe "CONFIG_${wf}" n
done

# 物理声卡(WSL2 音频通过 WSLg/PulseAudio)
# 保留 CONFIG_SOUND 和 CONFIG_SND 基础设施(WSLg 需要)
echo "  - 关闭物理声卡芯片驱动" | tee -a "$LOG_FILE"
set_kconfig_safe CONFIG_SND_HDA_INTEL n
set_kconfig_safe CONFIG_SND_HDA_CODEC_REALTEK n
set_kconfig_safe CONFIG_SND_HDA_CODEC_HDMI n
set_kconfig_safe CONFIG_SND_ENS1371 n
set_kconfig_safe CONFIG_SND_USB_AUDIO n
set_kconfig_safe CONFIG_SND_SOC_INTEL_SST_TOPLEVEL n

# USB 物理主机控制器(WSL2 用 USBIP)
# 保留 CONFIG_USB_SUPPORT 核心(USBIP 需要)
echo "  - 关闭 USB 物理主机控制器" | tee -a "$LOG_FILE"
hci=(USB_XHCI_HCD USB_EHCI_HCD USB_OHCI_HCD USB_UHCI_HCD)
for h in "${hci[@]}"; do
    set_kconfig_safe "CONFIG_${h}" n
done

# 物理 SATA 控制器(WSL2 磁盘走 VirtIO)
# 保留 NVME_CORE
echo "  - 关闭物理 SATA 控制器" | tee -a "$LOG_FILE"
sata=(SATA_AHCI SATA_NV SATA_SIL SATA_MV SATA_PIIX ATA_PIIX)
for s in "${sata[@]}"; do
    set_kconfig_safe "CONFIG_${s}" n
done

# 摄像头/媒体/电视
echo "  - 关闭摄像头/媒体驱动" | tee -a "$LOG_FILE"
set_kconfig_safe CONFIG_USB_GSPCA n
set_kconfig_safe CONFIG_USB_VIDEO_CLASS n
set_kconfig_safe CONFIG_MEDIA_SUPPORT n
set_kconfig_safe CONFIG_MEDIA_CAMERA_SUPPORT n
set_kconfig_safe CONFIG_MEDIA_ANALOG_TV_SUPPORT n
set_kconfig_safe CONFIG_MEDIA_DIGITAL_TV_SUPPORT n
set_kconfig_safe CONFIG_DVB_CORE n

# 打印/看门狗/硬件监控
echo "  - 关闭打印/看门狗/硬件监控" | tee -a "$LOG_FILE"
set_kconfig_safe CONFIG_PRINTER n
set_kconfig_safe CONFIG_WATCHDOG n
set_kconfig_safe CONFIG_HWMON n
set_kconfig_safe CONFIG_SENSORS_CORETEMP n
set_kconfig_safe CONFIG_SENSORS_K10TEMP n

# 嵌入式 SoC / 老旧外设
echo "  - 关闭嵌入式 SoC 驱动" | tee -a "$LOG_FILE"
disable_embedded_socs
disable_obsolete_peripherals
disable_fc_scsi
disable_raid

# 更新配置
echo "  - 更新配置依赖..." | tee -a "$LOG_FILE"
make olddefconfig >> "$LOG_FILE" 2>&1
echo "配置精简完成" | tee -a "$LOG_FILE"

# -----------------------------------------------------------------------------
# [5/5] 编译
# -----------------------------------------------------------------------------
echo "[5/5] 编译内核 (使用 $JOBS 线程)..." | tee -a "$LOG_FILE"
echo "    预计 15-25 分钟..." | tee -a "$LOG_FILE"

# 6.8+ 时 KCFLAGS 已经在 optimize_cpu_modern 中 export
make KCONFIG_CONFIG=.config -j"$JOBS" >> "$LOG_FILE" 2>&1

# -----------------------------------------------------------------------------
# 安装模块
# -----------------------------------------------------------------------------
echo "安装内核模块..." | tee -a "$LOG_FILE"
make INSTALL_MOD_PATH="$PWD/modules" modules_install >> "$LOG_FILE" 2>&1

# -----------------------------------------------------------------------------
# 总结
# -----------------------------------------------------------------------------
echo "" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "WSL2 内核编译完成 - $(date)" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "bzImage: $SRC_DIR/arch/x86/boot/bzImage" | tee -a "$LOG_FILE"
echo "模块:    $SRC_DIR/modules/" | tee -a "$LOG_FILE"
echo "日志:    $LOG_FILE" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "使用方法:" | tee -a "$LOG_FILE"
echo "  cp arch/x86/boot/bzImage /mnt/c/Users/Administrator/wsl2-kernel" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo '  .wslconfig 添加:' | tee -a "$LOG_FILE"
echo "    [wsl2]" | tee -a "$LOG_FILE"
echo "    kernel=C:\\\\Users\\\\Administrator\\\\wsl2-kernel" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "  wsl --shutdown" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
