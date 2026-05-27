#!/bin/bash
#
# =============================================================================
# Linux 内核源码编译安装脚本 —— RTX 3080 + Ryzen 5 3500X 专用优化版
# =============================================================================
#
# 【硬件环境】
#   - CPU: AMD Ryzen 5 3500X (Zen2, 6核6线程, 无SMT)
#   - 显卡: NVIDIA GeForce RTX 3080 (GA102, Ampere架构)
#   - 存储: Samsung 238GB NVMe SSD + 931GB SATA SSD
#   - 内存: 建议 16GB+
#   - 网络: 有线千兆网卡
#   - 系统: Ubuntu 24.04 LTS (Noble Numbat)
#   - 内核: 6.8.0-117-generic (原始)
#
# 【编译目标】
#   - 源码: linux-6.8.12.tar.xz
#   - 版本: 6.8.12-rtx3080-$(date +%Y%m%d)
#   - 位置: /opt/linux/src/linux-6.8.12/
#
# 【配置文件】
#   - 编译配置: /home/quqiufeng/my-shell/config-6.8.12-rtx3080-current
#   - 说明: 此文件为当前实际编译用的 .config 备份，包含所有针对本机的优化选项
#   - 使用方法:
#       cp ~/my-shell/config-6.8.12-rtx3080-current /opt/linux/src/linux-6.8.12/.config
#       cd /opt/linux/src/linux-6.8.12 && make olddefconfig
#   - 每次编译后脚本会自动更新此备份文件
#
# 【NVIDIA 驱动注意事项】
#   - 本脚本关闭 nouveau，使用 NVIDIA 官方专有驱动
#   - 编译前请确保已安装 nvidia-driver-xxx 并重启验证可正常工作
#   - NVIDIA 驱动通过 DKMS 自动编译内核模块
#   - 注意：如果 make install 时 DKMS 自动构建失败，需要手动运行：
#       sudo dkms build nvidia/$(nvidia-smi | grep "Driver Version" | awk '{print $3}') -k $(make kernelrelease)
#       sudo dkms install nvidia/$(nvidia-smi | grep "Driver Version" | awk '{print $3}') -k $(make kernelrelease)
#       sudo update-initramfs -u -k $(make kernelrelease)
#   - 但需保留 CONFIG_MODULES, CONFIG_PCI, CONFIG_ACPI 等基础支持
#
# 【6.8.12 内核特殊说明】
#   - CONFIG_DM_LINEAR 在 6.8.x 中已不存在，功能内置在 dm-mod 中
#   - 只需确保 CONFIG_BLK_DEV_DM=y 即可支持 LVM
#   - 之前误以为缺少 dm-linear 导致启动失败，实际是 NVIDIA DKMS 未编译成功
#
# 【使用方式】
#   cd /opt/linux/src/linux-6.8.12
#   setsid bash ~/my-shell/build_kernel_3080.sh > /tmp/build_kernel_3080.log 2>&1 < /dev/null &
#   tail -f /tmp/build_kernel_3080.log
#
# =============================================================================

set -e

SRC_DIR="/opt/linux/src/linux-6.8.12"
LOG_FILE="/tmp/build_kernel_3080_$(date +%Y%m%d_%H%M%S).log"
JOBS=$(nproc)
KERNEL_LOCALVERSION="-rtx3080-$(date +%Y%m%d)"
CONFIG_BACKUP_DIR="$HOME/.config/kernel-builds"
FORCE_FULL_REBUILD=false
FORCE_RECONFIGURE=false

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --rebuild)
            FORCE_FULL_REBUILD=true
            echo "强制完整重新编译（清除所有编译产物）"
            shift
            ;;
        --reconfig)
            FORCE_RECONFIGURE=true
            echo "强制重新配置内核选项"
            shift
            ;;
        --help|-h)
            echo "用法: $0 [选项]"
            echo "选项:"
            echo "  --rebuild    强制完整重新编译（清除所有编译产物）"
            echo "  --reconfig   强制重新配置内核选项（基于当前运行内核配置）"
            echo "  --help       显示此帮助"
            exit 0
            ;;
        *)
            echo "未知选项: $1"
            echo "使用 --help 查看帮助"
            exit 1
            ;;
    esac
done

# 确保在源码目录
if [ ! -d "$SRC_DIR" ]; then
    echo "错误: 内核源码目录 $SRC_DIR 不存在" | tee -a "$LOG_FILE"
    exit 1
fi

cd "$SRC_DIR"

echo "========================================" | tee -a "$LOG_FILE"
echo "开始编译内核 - $(date)" | tee -a "$LOG_FILE"
echo "源码目录: $SRC_DIR" | tee -a "$LOG_FILE"
echo "编译线程: $JOBS" | tee -a "$LOG_FILE"
echo "本地版本: $KERNEL_LOCALVERSION" | tee -a "$LOG_FILE"
echo "强制完整重建: $FORCE_FULL_REBUILD" | tee -a "$LOG_FILE"
echo "强制重新配置: $FORCE_RECONFIGURE" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"

# 1. 安装编译依赖
echo "[1/9] 检查编译依赖..." | tee -a "$LOG_FILE"
MISSING_DEPS=""
for pkg in build-essential libncurses-dev bison flex libssl-dev libelf-dev bc dwarves; do
    if ! dpkg -l | awk '{print $2}' | grep -qE "^${pkg}(:amd64|:all)?$"; then
        MISSING_DEPS="$MISSING_DEPS $pkg"
    fi
done

if [ -n "$MISSING_DEPS" ]; then
    echo "警告: 缺少编译依赖:$MISSING_DEPS" | tee -a "$LOG_FILE"
    echo "请手动运行: sudo apt install -y$MISSING_DEPS" | tee -a "$LOG_FILE"
    echo "安装完成后再重新运行此脚本" | tee -a "$LOG_FILE"
    exit 1
else
    echo "所有编译依赖已安装" | tee -a "$LOG_FILE"
fi

# 2. 判断是增量编译还是完整重建
INCREMENTAL=false
if [ -f .config ] && [ -d "arch/x86/boot" ] && [ "$FORCE_FULL_REBUILD" = false ]; then
    INCREMENTAL=true
    echo "[2/9] 检测到已有编译配置，启用增量编译模式" | tee -a "$LOG_FILE"
else
    echo "[2/9] 完整重建模式（清除所有编译产物）..." | tee -a "$LOG_FILE"
    make clean 2>&1 | tee -a "$LOG_FILE" || true
    make mrproper 2>&1 | tee -a "$LOG_FILE" || true
    INCREMENTAL=false
fi

# 3. 配置内核
mkdir -p "$CONFIG_BACKUP_DIR"
CONFIG_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CURRENT_CONFIG="$CONFIG_BACKUP_DIR/config-$(uname -r)-$CONFIG_TIMESTAMP"

if [ "$INCREMENTAL" = true ] && [ "$FORCE_RECONFIGURE" = false ]; then
    echo "  增量模式: 复用已有的 .config" | tee -a "$LOG_FILE"
    cp .config "$CURRENT_CONFIG"
    echo "  备份完成" | tee -a "$LOG_FILE"
else
    echo "  从当前运行内核复制标准配置..." | tee -a "$LOG_FILE"
    if [ -f /boot/config-$(uname -r) ]; then
        cp /boot/config-$(uname -r) .config
        echo "  已复制 /boot/config-$(uname -r)" | tee -a "$LOG_FILE"
    else
        echo "  错误: 找不到当前内核配置文件" | tee -a "$LOG_FILE"
        exit 1
    fi
    
    cp .config "$CURRENT_CONFIG"
    echo "  原始配置已备份到: $CURRENT_CONFIG" | tee -a "$LOG_FILE"
    
    # 4. 根据本机硬件优化内核配置
    echo "[4/9] 根据 RTX 3080 + Ryzen 3500X 优化内核配置..." | tee -a "$LOG_FILE"
    
    # ========== CPU 优化: AMD Zen2 (Ryzen 5 3500X) ==========
    echo "  - 设置处理器为 AMD Zen2" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_GENERIC_CPU n
    scripts/config --set-val CONFIG_GENERIC_CPU2 n
    scripts/config --set-val CONFIG_GENERIC_CPU3 n
    scripts/config --set-val CONFIG_GENERIC_CPU4 n
    scripts/config --set-val CONFIG_MNATIVE_INTEL n
    scripts/config --set-val CONFIG_MNATIVE_AMD n
    scripts/config --set-val CONFIG_MCORE2 n
    scripts/config --set-val CONFIG_MATOM n
    scripts/config --set-val CONFIG_MPSC n
    scripts/config --set-val CONFIG_MK8 n
    scripts/config --set-val CONFIG_MK8SSE3 n
    scripts/config --set-val CONFIG_MK10 n
    scripts/config --set-val CONFIG_MBARCELONA n
    scripts/config --set-val CONFIG_MBOBCAT n
    scripts/config --set-val CONFIG_MJAGUAR n
    scripts/config --set-val CONFIG_MBULLDOZER n
    scripts/config --set-val CONFIG_MPILEDRIVER n
    scripts/config --set-val CONFIG_MSTEAMROLLER n
    scripts/config --set-val CONFIG_MEXCAVATOR n
    scripts/config --set-val CONFIG_MNEHALEM n
    scripts/config --set-val CONFIG_MWESTMERE n
    scripts/config --set-val CONFIG_MSILVERMONT n
    scripts/config --set-val CONFIG_MGOLDMONT n
    scripts/config --set-val CONFIG_MGOLDMONTPLUS n
    scripts/config --set-val CONFIG_MSANDYBRIDGE n
    scripts/config --set-val CONFIG_MIVYBRIDGE n
    scripts/config --set-val CONFIG_MHASWELL n
    scripts/config --set-val CONFIG_MBROADWELL n
    scripts/config --set-val CONFIG_MSKYLAKE n
    scripts/config --set-val CONFIG_MSKYLAKEX n
    scripts/config --set-val CONFIG_MCANNONLAKE n
    scripts/config --set-val CONFIG_MICELAKE n
    scripts/config --set-val CONFIG_MCASCADELAKE n
    scripts/config --set-val CONFIG_MCOOPERLAKE n
    scripts/config --set-val CONFIG_MTIGERLAKE n
    scripts/config --set-val CONFIG_MSAPPHIRERAPIDS n
    scripts/config --set-val CONFIG_MROCKETLAKE n
    scripts/config --set-val CONFIG_MALDERLAKE n
    scripts/config --set-val CONFIG_MRAPTORLAKE n
    scripts/config --set-val CONFIG_MMETEORLAKE n
    scripts/config --set-val CONFIG_MMORPHYLAKE n
    scripts/config --set-val CONFIG_MZEN n
    scripts/config --set-val CONFIG_MZEN2 y
    scripts/config --set-val CONFIG_MZEN3 n
    scripts/config --set-val CONFIG_MZEN4 n
    scripts/config --set-val CONFIG_MZEN5 n
    
    # Ryzen 5 3500X: 6核6线程，无SMT
    echo "  - 优化调度器 (6核6线程, 无SMT)" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_SCHED_MC y
    scripts/config --set-val CONFIG_SCHED_SMT n
    
    # 透明大页
    echo "  - 开启透明大页" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_TRANSPARENT_HUGEPAGE y
    scripts/config --set-val CONFIG_TRANSPARENT_HUGEPAGE_MADVISE y
    
    # ========== 显卡优化: NVIDIA RTX 3080 ==========
    echo "  - 配置 NVIDIA RTX 3080 (关闭 nouveau, 保留 DRM 基础框架)" | tee -a "$LOG_FILE"
    
    # 关闭 Intel 显卡驱动
    scripts/config --set-val CONFIG_DRM_I915 n
    scripts/config --set-val CONFIG_DRM_I915_GVT n
    
    # 关闭 AMD 显卡驱动
    scripts/config --set-val CONFIG_DRM_AMDGPU n
    scripts/config --set-val CONFIG_DRM_RADEON n
    scripts/config --set-val CONFIG_DRM_AMD_ACP n
    scripts/config --set-val CONFIG_DRM_AMD_DC n
    
    # 关闭 nouveau (NVIDIA 开源驱动，与官方驱动冲突)
    scripts/config --set-val CONFIG_DRM_NOUVEAU n
    scripts/config --set-val CONFIG_NOUVEAU_PLATFORM_DRIVER n
    
    # 关闭其他虚拟/嵌入式显卡
    scripts/config --set-val CONFIG_DRM_VIRTIO_GPU n
    scripts/config --set-val CONFIG_DRM_QXL n
    scripts/config --set-val CONFIG_DRM_VGEM n
    scripts/config --set-val CONFIG_DRM_VKMS n
    scripts/config --set-val CONFIG_DRM_UDL n
    scripts/config --set-val CONFIG_DRM_AST n
    scripts/config --set-val CONFIG_DRM_MGAG200 n
    scripts/config --set-val CONFIG_DRM_BOCHS n
    scripts/config --set-val CONFIG_DRM_CIRRUS_QEMU n
    scripts/config --set-val CONFIG_DRM_SIMPLEDRM n
    
    # 保留基础 DRM 和 fbdev（NVIDIA 驱动依赖的部分框架）
    scripts/config --set-val CONFIG_DRM y
    scripts/config --set-val CONFIG_DRM_KMS_HELPER y
    scripts/config --set-val CONFIG_FB y
    scripts/config --set-val CONFIG_FB_EFI y
    scripts/config --set-val CONFIG_FB_SIMPLE y
    
    # NVIDIA 专有驱动需要这些
    scripts/config --set-val CONFIG_PCI y
    scripts/config --set-val CONFIG_ACPI y
    scripts/config --set-val CONFIG_MODULES y
    scripts/config --set-val CONFIG_MODULE_UNLOAD y
    scripts/config --set-val CONFIG_MODVERSIONS y
    scripts/config --set-val CONFIG_MMU y
    
    # ========== 存储优化: NVMe + SATA SSD ==========
    echo "  - 配置 NVMe + SATA SSD 支持" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_NVME_CORE y
    scripts/config --set-val CONFIG_BLK_DEV_NVME y
    scripts/config --set-val CONFIG_NVME_FABRICS n
    scripts/config --set-val CONFIG_NVME_RDMA n
    scripts/config --set-val CONFIG_NVME_FC n
    scripts/config --set-val CONFIG_NVME_TCP n
    scripts/config --set-val CONFIG_NVME_AUTH n
    scripts/config --set-val CONFIG_NVME_TARGET n
    
    scripts/config --set-val CONFIG_SATA_AHCI y
    scripts/config --set-val CONFIG_SATA_MOBILE_LPM_POLICY 0
    scripts/config --set-val CONFIG_ATA_ACPI y
    scripts/config --set-val CONFIG_SATA_PMP y
    
    # LVM 根分区需要 device-mapper
    # 注意：6.8.x 内核中 CONFIG_DM_LINEAR 已不存在，功能内置在 dm-mod 中
    # 只需确保 CONFIG_BLK_DEV_DM=y 即可支持 LVM 根分区
    scripts/config --set-val CONFIG_BLK_DEV_DM y
    scripts/config --set-val CONFIG_BLK_DEV_DM_BUILTIN y
    
    # 禁用老旧 PATA/IDE
    scripts/config --set-val CONFIG_ATA_SFF n
    scripts/config --set-val CONFIG_PATA_AMD n
    scripts/config --set-val CONFIG_PATA_INTEL n
    scripts/config --set-val CONFIG_PATA_OLDPIIX n
    scripts/config --set-val CONFIG_PATA_SCH n
    
    # SSD 友好文件系统
    echo "  - 优化文件系统配置 (SSD 友好)" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_EXT4_FS y
    scripts/config --set-val CONFIG_BTRFS_FS y
    scripts/config --set-val CONFIG_F2FS_FS y
    scripts/config --set-val CONFIG_XFS_FS n
    scripts/config --set-val CONFIG_NTFS3_FS m
    scripts/config --set-val CONFIG_EXFAT_FS m
    scripts/config --set-val CONFIG_EXT4_KUNIT_TESTS n
    
    # ========== 网络优化 ==========
    echo "  - 配置网络驱动" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_E1000E y
    scripts/config --set-val CONFIG_R8169 y
    scripts/config --set-val CONFIG_IGB y
    scripts/config --set-val CONFIG_IGC y
    
    # 禁用大量不需要的网卡
    scripts/config --set-val CONFIG_IXGBE n
    scripts/config --set-val CONFIG_IXGBEVF n
    scripts/config --set-val CONFIG_MLX4_EN n
    scripts/config --set-val CONFIG_MLX5_CORE n
    scripts/config --set-val CONFIG_BNXT_EN n
    scripts/config --set-val CONFIG_CXGB4 n
    scripts/config --set-val CONFIG_CXGB3 n
    scripts/config --set-val CONFIG_QLCNIC n
    scripts/config --set-val CONFIG_QLGE n
    scripts/config --set-val CONFIG_NETXEN_NIC n
    scripts/config --set-val CONFIG_SFC n
    scripts/config --set-val CONFIG_SFC_FALCON n
    scripts/config --set-val CONFIG_SKY2 n
    scripts/config --set-val CONFIG_TIGON3 n
    scripts/config --set-val CONFIG_TYPHOON n
    scripts/config --set-val CONFIG_VIA_RHINE n
    scripts/config --set-val CONFIG_VIA_VELOCITY n
    scripts/config --set-val CONFIG_YELLOWFIN n
    scripts/config --set-val CONFIG_ALTERA_TSE n
    scripts/config --set-val CONFIG_AMD_XGBE n
    scripts/config --set-val CONFIG_ATL1 n
    scripts/config --set-val CONFIG_ATL1C n
    scripts/config --set-val CONFIG_ATL1E n
    scripts/config --set-val CONFIG_BNA n
    scripts/config --set-val CONFIG_BNX2 n
    scripts/config --set-val CONFIG_BNX2X n
    scripts/config --set-val CONFIG_CASSINI n
    scripts/config --set-val CONFIG_DL2K n
    scripts/config --set-val CONFIG_ENC28J60 n
    scripts/config --set-val CONFIG_FEALNX n
    scripts/config --set-val CONFIG_HAMACHI n
    scripts/config --set-val CONFIG_HAPPYMEAL n
    scripts/config --set-val CONFIG_HINIC n
    scripts/config --set-val CONFIG_JME n
    scripts/config --set-val CONFIG_LAN743X n
    scripts/config --set-val CONFIG_LPC_ENET n
    scripts/config --set-val CONFIG_MACB n
    
    for vendor in 3COM ADAPTEC AGERE ALACRITECH ALTEON AMAZON AQUANTIA ARC ATHEROS BROADCOM CADENCE CAVIUM CHELSIO CISCO CORTINA DEC DLINK EMULEX EZCHIP FUJITSU GOOGLE HISILICON HUAWEI LITEX MARVELL MELLANOX MICREL MICROCHIP MICROSEMI MICROSOFT MYRI NI NATSEMI NETERION NETRONOME NVIDIA OKI PACKET_ENGINES PENSANDO QLOGIC QUALCOMM RDC RENESAS ROCKER SAMSUNG SEEQ SOLARFLARE SILAN SIS SMSC SOCIONEXT STMICRO SUN SYNOPSYS TEHUTI TI VERTEXCOM VIA WANGXUN XILINX; do
        scripts/config --set-val CONFIG_NET_VENDOR_${vendor} n 2>/dev/null || true
    done
    
    # ========== 声音: 保留 HD Audio ==========
    echo "  - 配置 HD Audio" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_SND_HDA_INTEL y
    scripts/config --set-val CONFIG_SND_HDA_CODEC_REALTEK y
    scripts/config --set-val CONFIG_SND_HDA_CODEC_HDMI y
    scripts/config --set-val CONFIG_SND_HDA_CODEC_ANALOG n
    scripts/config --set-val CONFIG_SND_HDA_CODEC_SIGMATEL n
    scripts/config --set-val CONFIG_SND_HDA_CODEC_VIA n
    scripts/config --set-val CONFIG_SND_HDA_CODEC_CIRRUS n
    scripts/config --set-val CONFIG_SND_HDA_CODEC_CONEXANT n
    scripts/config --set-val CONFIG_SND_HDA_CODEC_CA0110 n
    scripts/config --set-val CONFIG_SND_HDA_CODEC_CA0132 n
    scripts/config --set-val CONFIG_SND_HDA_CODEC_CMEDIA n
    scripts/config --set-val CONFIG_SND_HDA_CODEC_SI3054 n
    scripts/config --set-val CONFIG_SND_SOC n
    scripts/config --set-val CONFIG_SND_USB_AUDIO y
    
    # ========== 多媒体: 保留基础视频/V4L2 (NVIDIA 硬件编解码需要) ==========
    echo "  - 保留基础多媒体支持 (NVIDIA NVENC/NVDEC)" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_MEDIA_SUPPORT y
    scripts/config --set-val CONFIG_MEDIA_CAMERA_SUPPORT y
    scripts/config --set-val CONFIG_MEDIA_USB_SUPPORT y
    scripts/config --set-val CONFIG_USB_VIDEO_CLASS y
    scripts/config --set-val CONFIG_DVB_CORE n
    scripts/config --set-val CONFIG_MEDIA_ANALOG_TV_SUPPORT n
    scripts/config --set-val CONFIG_MEDIA_DIGITAL_TV_SUPPORT n
    scripts/config --set-val CONFIG_MEDIA_RADIO_SUPPORT n
    scripts/config --set-val CONFIG_MEDIA_SDR_SUPPORT n
    scripts/config --set-val CONFIG_MEDIA_PLATFORM_SUPPORT n
    scripts/config --set-val CONFIG_MEDIA_TEST_SUPPORT n
    
    # 关闭大量不用的摄像头驱动
    for cam in OV2659 OV2680 OV2685 OV2740 OV5640 OV5645 OV5647 OV5670 OV5675 OV5693 OV5695 OV6650 OV7251 OV7640 OV7670 OV772X OV7740 OV8856 OV8865 OV9640 OV9650 ET8EK8 MIPI_CSI_2 MEDIATEK_MT9T112 MEDIATEK_MT9V032 PAS106B PAS6326 SR030PC30 SR200PC20 CE147 TW9910 S5C73M3 S5K5BAF S5K4ECGX S5K6A3 S5K6AA S5K4E1 S5K5CA S5K6AA HM2056 HM5065 DB8V61M NOON010PC30 S5K6AA; do
        scripts/config --set-val CONFIG_VIDEO_${cam} n 2>/dev/null || true
    done
    
    # ========== 蓝牙/Wi-Fi: 按需保留 ==========
    echo "  - 配置蓝牙支持" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_BT y
    scripts/config --set-val CONFIG_BT_BREDR y
    scripts/config --set-val CONFIG_BT_LE y
    scripts/config --set-val CONFIG_BT_INTEL y
    scripts/config --set-val CONFIG_BT_HCIBTUSB y
    scripts/config --set-val CONFIG_BT_HCIBTUSB_BCM y
    scripts/config --set-val CONFIG_BT_HCIBTUSB_RTL y
    
    scripts/config --set-val CONFIG_CFG80211 y
    scripts/config --set-val CONFIG_MAC80211 y
    scripts/config --set-val CONFIG_WLAN y
    scripts/config --set-val CONFIG_IWLWIFI y
    scripts/config --set-val CONFIG_IWLDVM y
    scripts/config --set-val CONFIG_IWLMVM y
    
    # 关闭大量其他 Wi-Fi 驱动
    scripts/config --set-val CONFIG_RT2X00 n
    scripts/config --set-val CONFIG_RTLWIFI n
    scripts/config --set-val CONFIG_ATH10K n
    scripts/config --set-val CONFIG_ATH11K n
    scripts/config --set-val CONFIG_ATH9K n
    scripts/config --set-val CONFIG_BRCMFMAC n
    scripts/config --set-val CONFIG_B43 n
    scripts/config --set-val CONFIG_B43LEGACY n
    scripts/config --set-val CONFIG_SSB n
    scripts/config --set-val CONFIG_BCMA n
    scripts/config --set-val CONFIG_MT76 n
    scripts/config --set-val CONFIG_MWLWIFI n
    scripts/config --set-val CONFIG_RSI_91X n
    scripts/config --set-val CONFIG_WL n
    
    # ========== 关闭不需要的驱动 ==========
    echo "  - 移除服务器/嵌入式/虚拟化驱动..." | tee -a "$LOG_FILE"
    
    # Infiniband
    scripts/config --set-val CONFIG_INFINIBAND n
    
    # 光纤通道
    scripts/config --set-val CONFIG_SCSI_FC_ATTRS n
    scripts/config --set-val CONFIG_SCSI_SPI_ATTRS n
    scripts/config --set-val CONFIG_SCSI_SAS_ATTRS n
    scripts/config --set-val CONFIG_SCSI_SAS_LIBSAS n
    
    # RAID (除非使用软RAID)
    scripts/config --set-val CONFIG_MD_RAID0 n
    scripts/config --set-val CONFIG_MD_RAID1 n
    scripts/config --set-val CONFIG_MD_RAID10 n
    scripts/config --set-val CONFIG_MD_RAID456 n
    scripts/config --set-val CONFIG_MD_MULTIPATH n
    scripts/config --set-val CONFIG_MD_FAULTY n
    scripts/config --set-val CONFIG_BLK_DEV_DM_RAID n
    scripts/config --set-val CONFIG_DM_MULTIPATH n
    
    # 大量 SCSI 控制器
    scripts/config --set-val CONFIG_SCSI_LOWLEVEL n
    scripts/config --set-val CONFIG_SCSI_LOWLEVEL_PCMCIA n
    for scsi_drv in BFA_FC CHELSIO_FCOE ESAS2R HPSA IPR IBMVSCSI IBMVFC MPT2SAS MPT3SAS SMARTPQI UFSHCD VIRTIO CXGB3_ISCSI CXGB4_ISCSI BNX2_ISCSI BNX2X_FCOE BE2ISCSI PM8001 QLOGIC_1280 QLA_FC QLA_ISCSI LPFC DC395x AM53C974 WD719X DEBUG PMCRAID FDOMAIN_PCI; do
        scripts/config --set-val CONFIG_SCSI_${scsi_drv} n 2>/dev/null || true
    done
    
    # 保留 KVM (用户可能需要用虚拟机)
    echo "  - 保留 KVM 虚拟化支持" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_KVM y
    scripts/config --set-val CONFIG_KVM_AMD y
    scripts/config --set-val CONFIG_KVM_INTEL n
    scripts/config --set-val CONFIG_VHOST_NET y
    scripts/config --set-val CONFIG_VHOST_VSOCK n
    scripts/config --set-val CONFIG_VHOST_CROSS_ENDIAN_LEGACY n
    
    # Xen/VMware/Hyper-V
    scripts/config --set-val CONFIG_XEN n
    scripts/config --set-val CONFIG_XEN_DOM0 n
    scripts/config --set-val CONFIG_XEN_PVHVM n
    scripts/config --set-val CONFIG_XEN_PVH n
    scripts/config --set-val CONFIG_XEN_FBDEV_FRONTEND n
    scripts/config --set-val CONFIG_XEN_BLKDEV_FRONTEND n
    scripts/config --set-val CONFIG_XEN_BLKDEV_BACKEND n
    scripts/config --set-val CONFIG_XEN_NETDEV_FRONTEND n
    scripts/config --set-val CONFIG_XEN_NETDEV_BACKEND n
    scripts/config --set-val CONFIG_XEN_PCIDEV_FRONTEND n
    scripts/config --set-val CONFIG_XEN_PCIDEV_BACKEND n
    scripts/config --set-val CONFIG_XEN_SCSI_BACKEND n
    scripts/config --set-val CONFIG_XEN_ACPI_PROCESSOR n
    scripts/config --set-val CONFIG_XEN_HAVE_PVMMU n
    scripts/config --set-val CONFIG_XEN_EFI n
    scripts/config --set-val CONFIG_XEN_AUTO_XLATE n
    scripts/config --set-val CONFIG_XEN_BALLOON n
    scripts/config --set-val CONFIG_XEN_SCRUB_PAGES n
    scripts/config --set-val CONFIG_XEN_DEV_EVTCHN n
    scripts/config --set-val CONFIG_XEN_BACKEND n
    scripts/config --set-val CONFIG_XENFS n
    scripts/config --set-val CONFIG_XEN_COMPAT_XENFS n
    scripts/config --set-val CONFIG_XEN_SYS_HYPERVISOR n
    scripts/config --set-val CONFIG_XEN_GNTDEV n
    scripts/config --set-val CONFIG_XEN_GNTDEV_DMABUF n
    scripts/config --set-val CONFIG_XEN_GRANT_DEV_ALLOC n
    scripts/config --set-val CONFIG_SWIOTLB_XEN n
    scripts/config --set-val CONFIG_XEN_PVCALLS_BACKEND n
    scripts/config --set-val CONFIG_XEN_PVCALLS_FRONTEND n
    scripts/config --set-val CONFIG_XEN_PRIVCMD n
    scripts/config --set-val CONFIG_XEN_HAVE_VPMU n
    scripts/config --set-val CONFIG_XEN_UNPOPULATED_ALLOC n
    scripts/config --set-val CONFIG_XEN_BALLOON_MEMORY_HOTPLUG n
    scripts/config --set-val CONFIG_XEN_MCE_LOG n
    
    scripts/config --set-val CONFIG_VMWARE_VMCI n
    scripts/config --set-val CONFIG_VMWARE_BALLOON n
    scripts/config --set-val CONFIG_VMWARE_PVSCSI n
    scripts/config --set-val CONFIG_VMWARE_VMCI_VSOCKETS n
    scripts/config --set-val CONFIG_HYPERV n
    scripts/config --set-val CONFIG_HYPERV_UTILS n
    scripts/config --set-val CONFIG_HYPERV_BALLOON n
    scripts/config --set-val CONFIG_HYPERV_STORAGE n
    scripts/config --set-val CONFIG_HYPERV_NET n
    scripts/config --set-val CONFIG_HYPERV_VSOCKETS n
    scripts/config --set-val CONFIG_HYPERV_ISPVBD n
    
    # 嵌入式 SoC
    for arch in ACTIONS SUNXI ALPINE APPLE BCM BERLIN BITMAIN EXYNOS SPARX5 K3 LG1K HISI KEEMBAY MEDIATEK MESON MVEBU NXP MA35 NPCM QCOM REALTEK RENESAS ROCKCHIP SEATTLE INTEL_SOCFPGA STM32 SYNQUACER TEGRA SPRD THUNDER THUNDER2 UNIPHIER VEXPRESS VISCONTI XGENE ZYNQMP; do
        scripts/config --set-val CONFIG_ARCH_${arch} n 2>/dev/null || true
    done
    
    # CAN 总线
    scripts/config --set-val CONFIG_CAN n
    
    # 关闭老旧协议
    scripts/config --set-val CONFIG_TIPC n
    scripts/config --set-val CONFIG_DECNET n
    scripts/config --set-val CONFIG_IPX n
    scripts/config --set-val CONFIG_ATALK n
    scripts/config --set-val CONFIG_9P_FS n
    scripts/config --set-val CONFIG_NET_9P n
    
    # PCMCIA
    scripts/config --set-val CONFIG_PCMCIA n
    
    # 红外/NFC/CEC/TPM
    scripts/config --set-val CONFIG_RC_CORE n
    scripts/config --set-val CONFIG_LIRC n
    scripts/config --set-val CONFIG_NFC n
    scripts/config --set-val CONFIG_CEC_CORE n
    scripts/config --set-val CONFIG_TCG_TPM n
    
    # 关闭 FireWire/Thunderbolt
    scripts/config --set-val CONFIG_FIREWIRE n
    scripts/config --set-val CONFIG_THUNDERBOLT n
    
    # ========== 内核压缩与版本 ==========
    echo "  - 设置内核压缩为 zstd" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_KERNEL_ZSTD y
    scripts/config --set-val CONFIG_KERNEL_GZIP n
    scripts/config --set-val CONFIG_KERNEL_BZIP2 n
    scripts/config --set-val CONFIG_KERNEL_LZMA n
    scripts/config --set-val CONFIG_KERNEL_XZ n
    scripts/config --set-val CONFIG_KERNEL_LZO n
    scripts/config --set-val CONFIG_KERNEL_LZ4 n
    
    # 设置本地版本号
    echo "  - 设置本地版本号: $KERNEL_LOCALVERSION" | tee -a "$LOG_FILE"
    scripts/config --set-str CONFIG_LOCALVERSION "$KERNEL_LOCALVERSION"
    
    # 修复签名证书缺失问题
    echo "  - 清除内核签名证书配置..." | tee -a "$LOG_FILE"
    scripts/config --set-str CONFIG_SYSTEM_TRUSTED_KEYS ""
    scripts/config --set-str CONFIG_SYSTEM_REVOCATION_KEYS ""
    scripts/config --set-val CONFIG_MODULE_SIG_KEY ""
    
    # 接受新配置项的默认值
    echo "[5/9] 更新配置（自动接受新选项默认值）..." | tee -a "$LOG_FILE"
    make olddefconfig 2>&1 | tee -a "$LOG_FILE"
    
    # 保存优化后的配置
    OPTIMIZED_CONFIG="$CONFIG_BACKUP_DIR/config-rtx3080-optimized-$CONFIG_TIMESTAMP"
    cp .config "$OPTIMIZED_CONFIG"
    echo "  优化后的配置已保存到: $OPTIMIZED_CONFIG" | tee -a "$LOG_FILE"
fi

# 5. 编译内核
if [ "$INCREMENTAL" = true ]; then
    echo "[6/9] 增量编译内核（只编译变化部分，使用 $JOBS 线程）..." | tee -a "$LOG_FILE"
    echo "    首次编译可能需要 20-40 分钟，增量编译会快很多..." | tee -a "$LOG_FILE"
else
    echo "[6/9] 完整编译内核（使用 $JOBS 线程）..." | tee -a "$LOG_FILE"
    echo "    这可能需要 20-40 分钟 (Ryzen 5 3500X 6核)，请耐心等待..." | tee -a "$LOG_FILE"
fi

make -j$JOBS 2>&1 | tee -a "$LOG_FILE"

# 6. 安装内核模块
echo "[7/9] 安装内核模块..." | tee -a "$LOG_FILE"
sudo make modules_install 2>&1 | tee -a "$LOG_FILE"

# 7. 安装内核镜像
echo "[8/9] 安装内核镜像..." | tee -a "$LOG_FILE"
sudo make install 2>&1 | tee -a "$LOG_FILE"

# 获取内核版本号用于后续操作
KERNEL_RELEASE=$(make kernelrelease 2>/dev/null || echo "")

# **关键修复**: 显式生成 initramfs（LVM根分区必须）
if [ -n "$KERNEL_RELEASE" ]; then
    INITRAMFS="/boot/initrd.img-$KERNEL_RELEASE"
    echo "检查 initramfs..." | tee -a "$LOG_FILE"
    
    if [ ! -f "$INITRAMFS" ]; then
        echo "  initramfs 缺失，正在生成..." | tee -a "$LOG_FILE"
        sudo update-initramfs -c -k "$KERNEL_RELEASE" 2>&1 | tee -a "$LOG_FILE"
        
        if [ -f "$INITRAMFS" ]; then
            echo "  initramfs 生成成功: $INITRAMFS ($(ls -lh "$INITRAMFS" | awk '{print $5}'))" | tee -a "$LOG_FILE"
        else
            echo "  错误: initramfs 生成失败！无法启动新内核。" | tee -a "$LOG_FILE"
            echo "  请检查: sudo update-initramfs -c -k $KERNEL_RELEASE" | tee -a "$LOG_FILE"
            exit 1
        fi
    else
        echo "  initramfs 已存在: $INITRAMFS" | tee -a "$LOG_FILE"
    fi
fi

# 手动编译 NVIDIA DKMS 模块（解决 make install 时 DKMS 自动构建失败问题）
# 经验：台式机无显示输出的真正原因是 NVIDIA 模块未编译，而非 LVM/dm-linear
if [ -n "$KERNEL_RELEASE" ]; then
    echo "编译 NVIDIA DKMS 模块..." | tee -a "$LOG_FILE"
    NVIDIA_VER=$(dpkg -l | grep "nvidia-driver-" | grep -v "nvidia-driver-\(open\|server" | awk '{print $3}' | head -1)
    if [ -n "$NVIDIA_VER" ]; then
        echo "  检测到 NVIDIA 驱动版本: $NVIDIA_VER" | tee -a "$LOG_FILE"
        # 清理之前失败的构建缓存
        sudo rm -rf "/var/lib/dkms/nvidia/$NVIDIA_VER/$KERNEL_RELEASE" 2>/dev/null || true
        sudo dkms build "nvidia/$NVIDIA_VER" -k "$KERNEL_RELEASE" 2>&1 | tee -a "$LOG_FILE"
        sudo dkms install "nvidia/$NVIDIA_VER" -k "$KERNEL_RELEASE" 2>&1 | tee -a "$LOG_FILE"
        echo "  NVIDIA 模块编译完成" | tee -a "$LOG_FILE"
    else
        echo "  未检测到 NVIDIA 驱动，跳过 DKMS 编译" | tee -a "$LOG_FILE"
    fi
fi

# 重新生成 initramfs（包含刚编译的 NVIDIA 模块）
if [ -n "$KERNEL_RELEASE" ]; then
    echo "更新 initramfs（包含 NVIDIA 模块）..." | tee -a "$LOG_FILE"
    sudo update-initramfs -u -k "$KERNEL_RELEASE" 2>&1 | tee -a "$LOG_FILE"
fi

# 保存最终配置
KERNEL_RELEASE=$(make kernelrelease 2>/dev/null || echo "")
if [ -n "$KERNEL_RELEASE" ]; then
    FINAL_CONFIG="/boot/config-$KERNEL_RELEASE"
    echo "[9/9] 保存编译配置到标准位置..." | tee -a "$LOG_FILE"
    sudo cp .config "$FINAL_CONFIG"
    echo "  配置已保存到: $FINAL_CONFIG" | tee -a "$LOG_FILE"
    
    USER_CONFIG="$CONFIG_BACKUP_DIR/config-$KERNEL_RELEASE"
    cp .config "$USER_CONFIG"
    echo "  配置已备份到: $USER_CONFIG" | tee -a "$LOG_FILE"
    
    # 复制到 my-shell 目录作为当前编译配置
    MY_SHELL_CONFIG="$HOME/my-shell/config-6.8.12-rtx3080-current"
    cp .config "$MY_SHELL_CONFIG"
    echo "  配置已同步到: $MY_SHELL_CONFIG" | tee -a "$LOG_FILE"
fi

# 更新 GRUB
echo "更新 GRUB 配置..." | tee -a "$LOG_FILE"
sudo update-grub 2>&1 | tee -a "$LOG_FILE"

# 设置新内核为默认启动（需要sudo读取grub.cfg）
echo "设置新内核为默认启动..." | tee -a "$LOG_FILE"
if [ -n "$KERNEL_RELEASE" ]; then
    # 验证新内核在GRUB中
    if sudo grep -q "with Linux $KERNEL_RELEASE" /boot/grub/grub.cfg 2>/dev/null; then
        sudo sed -i "s/^GRUB_DEFAULT=.*/GRUB_DEFAULT=\"Advanced options for Ubuntu>Ubuntu, with Linux $KERNEL_RELEASE\"/" /etc/default/grub
        sudo update-grub 2>&1 | tee -a "$LOG_FILE"
        echo "已设置新内核 $KERNEL_RELEASE 为默认启动项" | tee -a "$LOG_FILE"
    else
        echo "警告: GRUB中找不到新内核条目，保持默认顺序" | tee -a "$LOG_FILE"
    fi
else
    echo "警告: 无法获取内核版本号，GRUB默认顺序保持不变" | tee -a "$LOG_FILE"
fi

echo "" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "内核编译安装完成 - $(date)" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
if [ -n "$KERNEL_RELEASE" ]; then
    echo "新内核版本: $KERNEL_RELEASE" | tee -a "$LOG_FILE"
fi
echo "安装的内核: /boot/vmlinuz-*$KERNEL_LOCALVERSION" | tee -a "$LOG_FILE"
echo "配置文件: $FINAL_CONFIG" | tee -a "$LOG_FILE"
echo "备份配置: $CONFIG_BACKUP_DIR/" | tee -a "$LOG_FILE"
echo "默认启动: 新内核 $KERNEL_RELEASE" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo ""
echo "后续步骤:"
echo "  1. NVIDIA 驱动会自动通过 DKMS 重新编译内核模块"
echo "  2. 重启后在 GRUB 菜单选择新内核启动"
echo "  3. 运行 nvidia-smi 验证 NVIDIA 驱动正常工作"
echo ""
echo "增量编译提示:"
echo "  - 再次运行此脚本会自动检测已有编译产物，只编译变化部分"
echo "  - 使用 ./build_kernel_3080.sh --rebuild 强制完整重新编译"
echo "  - 使用 ./build_kernel_3080.sh --reconfig 重新配置内核选项"
echo "  - 所有内核配置保存在: $CONFIG_BACKUP_DIR/"
