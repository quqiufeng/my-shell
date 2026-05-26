#!/bin/bash
#
# =============================================================================
# Linux 内核源码编译脚本 (WSL2 + AMD Ryzen 5 3500X + RTX 3080)
# =============================================================================
#
# 本脚本用于在 WSL2 环境下编译自定义内核。
#
# 【硬件环境】
#   - CPU: AMD Ryzen 5 3500X 6-Core Processor (Zen2 架构)
#   - 显卡: NVIDIA GeForce RTX 3080 (20GB)
#   - 内存: 19 GB
#   - 系统: WSL2 Ubuntu
#   - 内核: 6.6.114.1-microsoft-standard-WSL2
#
# 【编译目标】
#   - 源码: Microsoft WSL2-Linux-Kernel (git clone)  【必须使用 WSL2 专用源码】
#   - 版本: 6.6.123.2-3080-$(date +%Y%m%d)
#   - 位置: /opt/linux/src/linux-6.6.141/
#   - 输出: arch/x86/boot/bzImage
#
# 【WSL2 专用源码说明 - 重要】
#
# 必须使用微软官方 WSL2 内核源码，不能直接用 kernel.org 的标准源码：
#
# 1. 为什么必须用微软源码：
#    - 标准 kernel.org 源码缺少 WSL2 专用补丁
#    - 缺少 dxgkrnl（GPU 直通驱动）
#    - 缺少 WSLg GUI 支持所需的特定补丁
#    - 9P 文件系统、Hyper-V 集成在微软源码中有针对 WSL2 的优化
#    - 标准源码编译的 bzImage 在 WSL2 中启动会直接失败（无错误提示，WSL2 无法启动）
#
# 2. 如何获取微软源码：
#    git clone --depth 1 --branch linux-msft-wsl-6.6.y \
#      https://github.com/microsoft/WSL2-Linux-Kernel.git \
#      /opt/linux/src/linux-6.6.141
#
# 3. 与标准源码的区别：
#    - 微软源码基于 kernel.org 6.6.x，但包含额外补丁
#    - 版本号格式: 6.6.123.2 (kernel + Microsoft patch level)
#    - 源码目录里有 Microsoft/、MSFT-Merge/ 等微软专用目录
#
# 4. 实测教训：
#    - 使用 linux-6.6.141.tar.xz（标准源码）编译 -> WSL2 无法启动
#    - 使用 WSL2-Linux-Kernel（微软源码）编译 -> 正常启动
#
# 【精简驱动注意事项】
#
# WSL2 是虚拟机，看不到物理硬件：
# - 不需要物理网卡驱动（e1000e/r8169/igb 等）
# - 不需要 SATA/NVMe 驱动（磁盘由 VirtIO 提供）
# - 不需要 USB/声卡/蓝牙/WiFi（WSL2 默认不支持）
# - 不需要硬件监控/看门狗/RTC（虚拟化环境）
#
# 但以下必须保留（WSL2 生存必需）：
# - VirtIO（blk, net, pci, console, scsi）
# - Hyper-V（net, storage, utils, balloon, vsockets）
# - 9P 文件系统（Windows 目录挂载）
# - ext4 + tmpfs/proc/sysfs/devtmpfs（基本文件系统）
# - TTY/PTY（终端必需）
#
# 【WSL2 使用方式】
#   1. 编译完成后复制 bzImage 到 Windows 目录
#      cp arch/x86/boot/bzImage /mnt/c/Users/Administrator/wsl2-kernel
#   
#   2. 编辑 Windows 用户目录下的 .wslconfig：
#      [wsl2]
#      kernel=C:\\Users\\Administrator\\wsl2-kernel
#   
#   3. 重启 WSL2：
#      wsl --shutdown
#
# 【完整编译流程】
#
# 步骤1: 获取 WSL2 专用内核源码（不要用 kernel.org 的标准源码！）
#   git clone --depth 1 --branch linux-msft-wsl-6.6.y \
#     https://github.com/microsoft/WSL2-Linux-Kernel.git \
#     /opt/linux/src/linux-6.6.141
#   
#   # 或者如果之前下载了标准源码，替换为微软源码：
#   # rm -rf /opt/linux/src/linux-6.6.141
#   # git clone --depth 1 --branch linux-msft-wsl-6.6.y \
#   #   https://github.com/microsoft/WSL2-Linux-Kernel.git \
#   #   /opt/linux/src/linux-6.6.141
#
# 步骤2: 安装编译依赖
#   sudo apt install -y build-essential libncurses-dev bison flex \
#       libssl-dev libelf-dev bc dwarves
#
# 步骤3: 修复内核签名证书缺失问题
#   cd /opt/linux/src/linux-6.6.141
#   scripts/config --set-str CONFIG_SYSTEM_TRUSTED_KEYS ""
#   scripts/config --set-str CONFIG_SYSTEM_REVOCATION_KEYS ""
#   scripts/config --set-val CONFIG_MODULE_SIG_KEY ""
#   make olddefconfig
#
# 步骤4: 运行编译脚本（后台模式）
#   cd /opt/linux/src/linux-6.6.141
#   setsid bash ~/my-shell/build_3080_kernel.sh > /tmp/build_kernel_nohup.log 2>&1 < /dev/null &
#   echo $! > /tmp/build_kernel.pid
#
# 步骤5: 监控编译进度
#   tail -f /tmp/build_kernel_nohup.log
#
# 步骤6: 编译完成后
#   ls -lh arch/x86/boot/bzImage
#   cp arch/x86/boot/bzImage /mnt/c/Users/Administrator/wsl2-kernel
#
# 【关键问题与解决方案】
#
# 问题1: 缺少编译依赖
#   解决: 预先运行 sudo apt install -y build-essential libncurses-dev bison flex \
#         libssl-dev libelf-dev bc dwarves
#
# 问题2: 内核签名证书缺失
#   解决: scripts/config --set-str CONFIG_SYSTEM_TRUSTED_KEYS ""
#         scripts/config --set-str CONFIG_SYSTEM_REVOCATION_KEYS ""
#         make olddefconfig
#
# 问题3: 编译中断
#   解决: 使用 setsid 启动独立会话
#
# 【编译优化项】
#   - 处理器架构: -march=znver2 (AMD Zen2)
#   - 调度器: 桌面环境优化 (SCHED_MC=y, SCHED_SMT=n, 6核)
#   - 透明大页: 开启 (TRANSPARENT_HUGEPAGE=y)
#   - 显卡: 无 (WSL2 GPU 由 Windows Host 提供)
#   - 存储: 仅 VirtIO_BLK (WSL2 虚拟磁盘)
#   - 文件系统: ext4 + 9P (WSL2 共享) + tmpfs/proc/sysfs/devtmpfs
#   - 网络: VirtIO_NET, Hyper-V (WSL2 网络)
#   - 保留: VirtIO, Hyper-V, 9P, basic TTY (WSL2 必需)
#   - 移除: SATA/NVMe, Wi-Fi, 蓝牙, 声卡, USB, 打印, RAID, SCSI(除VirtIO),
#           摄像头/媒体, 看门狗, 硬件监控, I2C/SPI/GPIO, TPM, 调试/ftrace,
#           KEXEC, 大量嵌入式 SoC, 各种杂项驱动
#   - 压缩: zstd (KERNEL_ZSTD=y)
#
# 【WSL2 注意事项】
#   - WSL2 不需要 GRUB，直接通过 .wslconfig 指定内核
#   - 不需要 make install / update-grub
#   - 需要保留 VirtIO、9P、Hyper-V 支持
#   - 模块安装到 /lib/modules/ 仍然有用
#
# =============================================================================


set -e

# 修改为你的内核源码目录
SRC_DIR="/opt/linux/src/linux-6.6.141"
LOG_FILE="/tmp/build_3080_kernel_$(date +%Y%m%d_%H%M%S).log"
JOBS=$(nproc)
KERNEL_LOCALVERSION="-3080-$(date +%Y%m%d)"
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
            echo "  --rebuild    强制完整重新编译"
            echo "  --reconfig   强制重新配置内核选项"
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

# 1. 检查编译依赖
echo "[1/7] 检查编译依赖..." | tee -a "$LOG_FILE"
MISSING_DEPS=""
for pkg in build-essential libncurses-dev bison flex libssl-dev libelf-dev bc dwarves cpio lz4; do
    if ! dpkg -l | awk '{print $2}' | grep -qE "^${pkg}(:amd64|:all)?$"; then
        MISSING_DEPS="$MISSING_DEPS $pkg"
    fi
done

if [ -n "$MISSING_DEPS" ]; then
    echo "警告: 缺少编译依赖:$MISSING_DEPS" | tee -a "$LOG_FILE"
    echo "请手动运行: sudo apt install -y$MISSING_DEPS" | tee -a "$LOG_FILE"
    exit 1
else
    echo "所有编译依赖已安装" | tee -a "$LOG_FILE"
fi

# 2. 判断是增量编译还是完整重建
INCREMENTAL=false
if [ -f .config ] && [ -d "arch/x86/boot" ] && [ "$FORCE_FULL_REBUILD" = false ]; then
    INCREMENTAL=true
    echo "[2/7] 检测到已有编译配置，启用增量编译模式" | tee -a "$LOG_FILE"
else
    echo "[2/7] 完整重建模式..." | tee -a "$LOG_FILE"
    make clean >> "$LOG_FILE" 2>&1 || true
    make mrproper >> "$LOG_FILE" 2>&1 || true
    INCREMENTAL=false
fi

# 3. 配置内核
echo "[3/7] 配置内核选项..." | tee -a "$LOG_FILE"

mkdir -p "$CONFIG_BACKUP_DIR"
CONFIG_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CURRENT_CONFIG="$CONFIG_BACKUP_DIR/config-$(uname -r)-$CONFIG_TIMESTAMP"

if [ "$INCREMENTAL" = true ] && [ "$FORCE_RECONFIGURE" = false ]; then
    echo "  增量模式: 复用已有的 .config" | tee -a "$LOG_FILE"
    cp .config "$CURRENT_CONFIG"
    echo "  备份完成" | tee -a "$LOG_FILE"
else
    echo "  从当前运行内核复制标准配置..." | tee -a "$LOG_FILE"
    if [ -f /proc/config.gz ]; then
        zcat /proc/config.gz > .config
        echo "  已从 /proc/config.gz 提取配置" | tee -a "$LOG_FILE"
    elif [ -f /boot/config-$(uname -r) ]; then
        cp /boot/config-$(uname -r) .config
        echo "  已复制 /boot/config-$(uname -r)" | tee -a "$LOG_FILE"
    else
        echo "  错误: 找不到当前内核配置文件" | tee -a "$LOG_FILE"
        echo "  请确保 /proc/config.gz 或 /boot/config-* 存在" | tee -a "$LOG_FILE"
        exit 1
    fi
    
    # 备份原始配置
    cp .config "$CURRENT_CONFIG"
    echo "  原始配置已备份到: $CURRENT_CONFIG" | tee -a "$LOG_FILE"
    
    # 4. 根据本机硬件优化内核配置
    echo "[4/7] 根据本机硬件优化内核配置..." | tee -a "$LOG_FILE"
    
    # ===== CPU 优化: AMD Ryzen 5 3500X (Zen2) =====
    echo "  - 设置处理器为 AMD Zen2" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_MCORE2 n
    scripts/config --set-val CONFIG_MATOM n
    scripts/config --set-val CONFIG_GENERIC_CPU n
    scripts/config --set-val CONFIG_MNATIVE_INTEL n
    scripts/config --set-val CONFIG_GENERIC_CPU3 n
    scripts/config --set-val CONFIG_GENERIC_CPU4 n
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
    scripts/config --set-val CONFIG_MZEN n
    scripts/config --set-val CONFIG_MZEN2 y          # Zen2 (3500X)
    scripts/config --set-val CONFIG_MZEN3 n
    scripts/config --set-val CONFIG_MZEN4 n
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
    
    # CPU 调度器优化: 6核6线程
    echo "  - 优化调度器 (6核6线程)" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_SCHED_MC y
    scripts/config --set-val CONFIG_SCHED_SMT n      # 3500X 不支持超线程
    
    # 内存: 19GB，开启透明大页
    echo "  - 开启透明大页 (19GB)" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_TRANSPARENT_HUGEPAGE y
    scripts/config --set-val CONFIG_TRANSPARENT_HUGEPAGE_MADVISE y
    
    # ===== 显卡: WSL2 由 Windows Host 提供 GPU 驱动 =====
    echo "  - WSL2 GPU 驱动由 Windows Host 提供 (dxgkrnl)" | tee -a "$LOG_FILE"
    echo "    Windows 侧安装 NVIDIA 驱动即可，Linux 内核不需要显卡驱动" | tee -a "$LOG_FILE"
    # 标准 kernel.org 源码不包含 dxgkrnl，如需 GPU 支持建议用微软 WSL2 内核源码:
    # git clone https://github.com/microsoft/WSL2-Linux-Kernel.git
    scripts/config --set-val CONFIG_DRM_NOUVEAU n    # 不需要开源 NVIDIA 驱动
    scripts/config --set-val CONFIG_DRM_I915 n       # 禁用 Intel
    scripts/config --set-val CONFIG_DRM_AMDGPU n     # 禁用 AMD
    scripts/config --set-val CONFIG_DRM_RADEON n
    scripts/config --set-val CONFIG_DRM_VIRTIO_GPU y # WSLg GUI 可能用到
    scripts/config --set-val CONFIG_DRM_QXL n
    scripts/config --set-val CONFIG_DRM_VGEM n
    scripts/config --set-val CONFIG_DRM_VKMS n
    scripts/config --set-val CONFIG_DRM_UDL n
    scripts/config --set-val CONFIG_DRM_AST n
    scripts/config --set-val CONFIG_DRM_MGAG200 n
    
    # ===== 存储: 仅 VirtIO (WSL2 虚拟磁盘) =====
    echo "  - 配置存储驱动 (仅 VirtIO)" | tee -a "$LOG_FILE"
    # WSL2 不需要物理 NVMe/SATA 驱动
    scripts/config --set-val CONFIG_NVME_CORE n
    scripts/config --set-val CONFIG_BLK_DEV_NVME n
    scripts/config --set-val CONFIG_NVME_FABRICS n
    scripts/config --set-val CONFIG_NVME_RDMA n
    scripts/config --set-val CONFIG_NVME_FC n
    scripts/config --set-val CONFIG_NVME_TCP n
    scripts/config --set-val CONFIG_NVME_AUTH n
    scripts/config --set-val CONFIG_NVME_TARGET n
    
    # WSL2 虚拟磁盘用 VirtIO_BLK
    scripts/config --set-val CONFIG_VIRTIO_BLK y
    scripts/config --set-val CONFIG_VIRTIO_NET y     # WSL2 网络
    scripts/config --set-val CONFIG_VIRTIO_PCI y
    scripts/config --set-val CONFIG_VIRTIO_MMIO y
    scripts/config --set-val CONFIG_VIRTIO_BALLOON n
    scripts/config --set-val CONFIG_VIRTIO_INPUT n
    scripts/config --set-val CONFIG_VIRTIO_CONSOLE y # WSL2 终端
    scripts/config --set-val CONFIG_VIRTIO_MEM n
    
    # 关闭 SATA/AHCI (WSL2 不需要物理 SATA)
    scripts/config --set-val CONFIG_SATA_AHCI n
    scripts/config --set-val CONFIG_SATA_NV n
    scripts/config --set-val CONFIG_SATA_SIL n
    scripts/config --set-val CONFIG_SATA_SIL24 n
    scripts/config --set-val CONFIG_ATA n
    scripts/config --set-val CONFIG_ATA_PIIX n
    scripts/config --set-val CONFIG_ATA_GENERIC n
    
    # 关闭多余的块设备
    scripts/config --set-val CONFIG_BLK_DEV_NVME n
    scripts/config --set-val CONFIG_BLK_DEV_SD n     # SCSI disk, 检查是否需要
    scripts/config --set-val CONFIG_BLK_DEV_SR n     # SCSI CD-ROM
    scripts/config --set-val CONFIG_BLK_DEV_LOOP y   # 保留 loop，docker/snap 常用
    scripts/config --set-val CONFIG_BLK_DEV_RAM n
    scripts/config --set-val CONFIG_BLK_DEV_NBD n
    scripts/config --set-val CONFIG_BLK_DEV_RBD n
    scripts/config --set-val CONFIG_BLK_DEV_RSXX n
    scripts/config --set-val CONFIG_BLK_DEV_NULL_BLK n
    
    # ===== 文件系统: 精简到 WSL2 必需 =====
    echo "  - 精简文件系统配置" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_EXT4_FS y
    scripts/config --set-val CONFIG_EXT4_FS_POSIX_ACL y
    scripts/config --set-val CONFIG_EXT4_FS_SECURITY y
    # 关闭不常用的文件系统以加速编译
    scripts/config --set-val CONFIG_BTRFS_FS n
    scripts/config --set-val CONFIG_XFS_FS n
    scripts/config --set-val CONFIG_F2FS_FS n
    scripts/config --set-val CONFIG_NTFS3_FS n
    scripts/config --set-val CONFIG_EXFAT_FS n
    scripts/config --set-val CONFIG_JFS_FS n
    scripts/config --set-val CONFIG_REISERFS_FS n
    scripts/config --set-val CONFIG_GFS2_FS n
    scripts/config --set-val CONFIG_OCFS2_FS n
    scripts/config --set-val CONFIG_MINIX_FS n
    scripts/config --set-val CONFIG_ROMFS_FS n
    scripts/config --set-val CONFIG_CRAMFS n
    scripts/config --set-val CONFIG_SQUASHFS n
    scripts/config --set-val CONFIG_HFS_FS n
    scripts/config --set-val CONFIG_HFSPLUS_FS n
    scripts/config --set-val CONFIG_JFFS2_FS n
    scripts/config --set-val CONFIG_UBIFS_FS n
    scripts/config --set-val CONFIG_AFS_FS n
    scripts/config --set-val CONFIG_ORANGEFS_FS n
    scripts/config --set-val CONFIG_AUFS_FS n
    scripts/config --set-val CONFIG_OVERLAY_FS y     # docker/podman 常用
    # 基本虚拟文件系统 (必需)
    scripts/config --set-val CONFIG_TMPFS y
    scripts/config --set-val CONFIG_TMPFS_POSIX_ACL y
    scripts/config --set-val CONFIG_DEVTMPFS y
    scripts/config --set-val CONFIG_PROC_FS y
    scripts/config --set-val CONFIG_SYSFS y
    scripts/config --set-val CONFIG_CGROUPS y        # 容器必需
    
    # WSL2 文件共享: 9P 文件系统 (必需)
    echo "  - 启用 9P 文件系统 (WSL2 共享)" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_NET_9P y
    scripts/config --set-val CONFIG_NET_9P_VIRTIO y
    scripts/config --set-val CONFIG_9P_FS y
    scripts/config --set-val CONFIG_9P_FS_POSIX_ACL y
    
    # ===== 网络: WSL2 虚拟网络 =====
    echo "  - 配置 WSL2 网络驱动" | tee -a "$LOG_FILE"
    # VirtIO 网络 (WSL2 主网络)
    scripts/config --set-val CONFIG_VIRTIO_NET y
    scripts/config --set-val CONFIG_VHOST_NET y
    
    # Hyper-V 网络 (WSL2 底层)
    scripts/config --set-val CONFIG_HYPERV_NET y
    scripts/config --set-val CONFIG_HYPERV_STORAGE y
    scripts/config --set-val CONFIG_HYPERV y
    scripts/config --set-val CONFIG_HYPERV_UTILS y
    scripts/config --set-val CONFIG_HYPERV_BALLOON y
    scripts/config --set-val CONFIG_HYPERV_VSOCKETS y
    scripts/config --set-val CONFIG_HYPERV_ISPVBD n
    
    # 关闭所有物理网卡 (WSL2 不需要)
    scripts/config --set-val CONFIG_E1000E n
    scripts/config --set-val CONFIG_E1000 n
    scripts/config --set-val CONFIG_R8169 n
    scripts/config --set-val CONFIG_IGB n
    scripts/config --set-val CONFIG_IXGBE n
    scripts/config --set-val CONFIG_IXGBEVF n
    scripts/config --set-val CONFIG_MLX4_EN n
    scripts/config --set-val CONFIG_MLX5_CORE n
    scripts/config --set-val CONFIG_TIGON3 n
    scripts/config --set-val CONFIG_BNX2 n
    scripts/config --set-val CONFIG_BNX2X n
    scripts/config --set-val CONFIG_BNXT_EN n
    scripts/config --set-val CONFIG_CXGB4 n
    scripts/config --set-val CONFIG_CXGB3 n
    scripts/config --set-val CONFIG_QLCNIC n
    scripts/config --set-val CONFIG_QLGE n
    
    # 禁用所有网卡供应商
    for vendor in 3COM ADAPTEC AGERE ALACRITECH ALTEON AMAZON AMD AQUANTIA ARC ATHEROS BROADCOM CADENCE CAVIUM CHELSIO CISCO CORTINA DEC DLINK EMULEX EZCHIP FUJITSU GOOGLE HISILICON HUAWEI LITEX MARVELL MELLANOX MICREL MICROCHIP MICROSEMI MICROSOFT MYRI NI NATSEMI NETERION NETRONOME NVIDIA OKI PACKET_ENGINES PENSANDO QLOGIC QUALCOMM RDC RENESAS ROCKER SAMSUNG SEEQ SOLARFLARE SILAN SIS SMSC SOCIONEXT STMICRO SUN SYNOPSYS TEHUTI TI VERTEXCOM VIA WANGXUN XILINX; do
        scripts/config --set-val CONFIG_NET_VENDOR_${vendor} n 2>/dev/null || true
    done
    
    # 精简网络协议栈 (保留基本 TCP/IP)
    echo "  - 精简网络协议栈" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_IP_FIB_TRIE_STATS n
    scripts/config --set-val CONFIG_NET_IPGRE n
    scripts/config --set-val CONFIG_NET_IPGRE_BROADCAST n
    scripts/config --set-val CONFIG_IP_MROUTE n
    scripts/config --set-val CONFIG_IP_PIMSM_V1 n
    scripts/config --set-val CONFIG_IP_PIMSM_V2 n
    scripts/config --set-val CONFIG_SYN_COOKIES y    # 基本安全
    scripts/config --set-val CONFIG_NET_IPIP n
    scripts/config --set-val CONFIG_NET_IPGRE_DEMUX n
    scripts/config --set-val CONFIG_NET_L3_MASTER_DEV n
    scripts/config --set-val CONFIG_IPV6 n           # 如果不需要 IPv6 可以关闭
    scripts/config --set-val CONFIG_NETFILTER n      # 如果不需要防火墙可以关闭
    scripts/config --set-val CONFIG_NF_CONNTRACK n
    scripts/config --set-val CONFIG_BRIDGE n         # docker 需要
    scripts/config --set-val CONFIG_VETH n           # docker 需要
    
    # ===== Wi-Fi / 蓝牙 (WSL2 不需要) =====
    echo "  - 关闭 Wi-Fi / 蓝牙" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_WLAN n
    scripts/config --set-val CONFIG_CFG80211 n
    scripts/config --set-val CONFIG_MAC80211 n
    scripts/config --set-val CONFIG_IWLWIFI n
    scripts/config --set-val CONFIG_BT n
    scripts/config --set-val CONFIG_BT_BREDR n
    scripts/config --set-val CONFIG_BT_LE n
    scripts/config --set-val CONFIG_BT_INTEL n
    scripts/config --set-val CONFIG_BT_HCIBTUSB n
    scripts/config --set-val CONFIG_BT_HCIUART n
    scripts/config --set-val CONFIG_BT_HCIBCM203X n
    scripts/config --set-val CONFIG_BT_HCIBPA10X n
    scripts/config --set-val CONFIG_BT_HCIBFUSB n
    scripts/config --set-val CONFIG_BT_HCIVHCI n
    scripts/config --set-val CONFIG_BT_MRVL n
    scripts/config --set-val CONFIG_BT_ATH3K n
    
    # ===== 声音 (WSL2 不需要) =====
    echo "  - 关闭声卡驱动" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_SND n
    scripts/config --set-val CONFIG_SND_HDA_INTEL n
    scripts/config --set-val CONFIG_SND_HDA_CODEC_REALTEK n
    scripts/config --set-val CONFIG_SND_HDA_CODEC_ANALOG n
    scripts/config --set-val CONFIG_SND_HDA_CODEC_SIGMATEL n
    scripts/config --set-val CONFIG_SND_HDA_CODEC_VIA n
    scripts/config --set-val CONFIG_SND_HDA_CODEC_HDMI n
    scripts/config --set-val CONFIG_SND_HDA_CODEC_CIRRUS n
    scripts/config --set-val CONFIG_SND_HDA_CODEC_CONEXANT n
    scripts/config --set-val CONFIG_SND_HDA_CODEC_CA0110 n
    scripts/config --set-val CONFIG_SND_HDA_CODEC_CA0132 n
    scripts/config --set-val CONFIG_SND_HDA_CODEC_CMEDIA n
    scripts/config --set-val CONFIG_SND_HDA_CODEC_SI3054 n
    scripts/config --set-val CONFIG_SND_USB_AUDIO n
    scripts/config --set-val CONFIG_SND_USB_UA101 n
    scripts/config --set-val CONFIG_SND_USB_USX2Y n
    scripts/config --set-val CONFIG_SND_USB_CAIAQ n
    scripts/config --set-val CONFIG_SND_USB_US122L n
    scripts/config --set-val CONFIG_SND_USB_6FIRE n
    scripts/config --set-val CONFIG_SND_USB_HIFACE n
    scripts/config --set-val CONFIG_SND_BCD2000 n
    scripts/config --set-val CONFIG_SND_FIREWIRE n
    scripts/config --set-val CONFIG_SND_SOC n
    
    # ===== USB (WSL2 默认不支持，关闭加速编译) =====
    echo "  - 关闭 USB 驱动" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_USB n
    scripts/config --set-val CONFIG_USB_SUPPORT n
    scripts/config --set-val CONFIG_USB_XHCI_HCD n
    scripts/config --set-val CONFIG_USB_EHCI_HCD n
    scripts/config --set-val CONFIG_USB_OHCI_HCD n
    scripts/config --set-val CONFIG_USB_UHCI_HCD n
    scripts/config --set-val CONFIG_USB_STORAGE n
    scripts/config --set-val CONFIG_USB_UAS n
    scripts/config --set-val CONFIG_USB_HID n
    scripts/config --set-val CONFIG_USB_SERIAL n
    scripts/config --set-val CONFIG_USB_ACM n
    scripts/config --set-val CONFIG_USB_PRINTER n
    scripts/config --set-val CONFIG_USB_WDM n
    scripts/config --set-val CONFIG_USB_NET_DRIVERS n
    scripts/config --set-val CONFIG_USB_IPHETH n
    scripts/config --set-val CONFIG_USB_RTL8150 n
    scripts/config --set-val CONFIG_USB_RTL8152 n
    scripts/config --set-val CONFIG_USB_LAN78XX n
    scripts/config --set-val CONFIG_USB_USBNET n
    scripts/config --set-val CONFIG_USB_NET_AX8817X n
    scripts/config --set-val CONFIG_USB_NET_AX88179_178A n
    scripts/config --set-val CONFIG_USB_NET_CDCETHER n
    scripts/config --set-val CONFIG_USB_NET_CDC_EEM n
    scripts/config --set-val CONFIG_USB_NET_CDC_NCM n
    scripts/config --set-val CONFIG_USB_NET_HUAWEI_CDC_NCM n
    scripts/config --set-val CONFIG_USB_NET_CDC_MBIM n
    scripts/config --set-val CONFIG_USB_NET_DM9601 n
    scripts/config --set-val CONFIG_USB_NET_SR9700 n
    scripts/config --set-val CONFIG_USB_NET_SR9800 n
    scripts/config --set-val CONFIG_USB_NET_SMSC75XX n
    scripts/config --set-val CONFIG_USB_NET_SMSC95XX n
    scripts/config --set-val CONFIG_USB_NET_GL620A n
    scripts/config --set-val CONFIG_USB_NET_NET1080 n
    scripts/config --set-val CONFIG_USB_NET_PLUSB n
    scripts/config --set-val CONFIG_USB_NET_MCS7830 n
    scripts/config --set-val CONFIG_USB_NET_RNDIS_HOST n
    scripts/config --set-val CONFIG_USB_NET_CDC_SUBSET n
    scripts/config --set-val CONFIG_USB_NET_ZAURUS n
    scripts/config --set-val CONFIG_USB_NET_CX82310_ETH n
    scripts/config --set-val CONFIG_USB_NET_KALMIA n
    scripts/config --set-val CONFIG_USB_NET_QMI_WWAN n
    scripts/config --set-val CONFIG_USB_HSO n
    scripts/config --set-val CONFIG_USB_NET_INT51X1 n
    scripts/config --set-val CONFIG_USB_CDC_PHONER n
    scripts/config --set-val CONFIG_USB_NET_KS8851 n
    scripts/config --set-val CONFIG_USB_NET_PEGASUS n
    
    # ===== 输入设备 (WSL2 精简) =====
    echo "  - 精简输入设备驱动" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_INPUT_KEYBOARD y # 保留基本键盘
    scripts/config --set-val CONFIG_INPUT_MOUSE y    # 保留基本鼠标
    scripts/config --set-val CONFIG_INPUT_JOYSTICK n
    scripts/config --set-val CONFIG_INPUT_TABLET n
    scripts/config --set-val CONFIG_INPUT_TOUCHSCREEN n
    scripts/config --set-val CONFIG_INPUT_MISC n
    scripts/config --set-val CONFIG_INPUT_ATLAS_BTNS n
    scripts/config --set-val CONFIG_INPUT_ATI_REMOTE2 n
    scripts/config --set-val CONFIG_INPUT_KEYSPAN_REMOTE n
    scripts/config --set-val CONFIG_INPUT_KXTJ9 n
    scripts/config --set-val CONFIG_INPUT_POWERMATE n
    scripts/config --set-val CONFIG_INPUT_YEALINK n
    scripts/config --set-val CONFIG_INPUT_CM109 n
    scripts/config --set-val CONFIG_INPUT_UINPUT n
    scripts/config --set-val CONFIG_INPUT_ADXL34X n
    scripts/config --set-val CONFIG_INPUT_CMA3000 n
    scripts/config --set-val CONFIG_INPUT_IDEAPAD_SLIDEBAR n
    scripts/config --set-val CONFIG_SERIO n
    scripts/config --set-val CONFIG_SERIO_I8042 y    # PS/2 键盘
    scripts/config --set-val CONFIG_SERIO_SERPORT n
    scripts/config --set-val CONFIG_SERIO_CT82C710 n
    scripts/config --set-val CONFIG_SERIO_PARKBD n
    scripts/config --set-val CONFIG_SERIO_PCIPS2 n
    scripts/config --set-val CONFIG_SERIO_LIBPS2 n
    scripts/config --set-val CONFIG_SERIO_RAW n
    scripts/config --set-val CONFIG_SERIO_ALTERA_PS2 n
    scripts/config --set-val CONFIG_SERIO_PS2MULT n
    scripts/config --set-val CONFIG_SERIO_ARC_PS2 n
    scripts/config --set-val CONFIG_SERIO_APBPS2 n
    scripts/config --set-val CONFIG_SERIO_GPIO_PS2 n
    scripts/config --set-val CONFIG_GAMEPORT n
    
    # ===== 硬件监控 (WSL2 不需要) =====
    echo "  - 关闭硬件监控" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_HWMON n
    scripts/config --set-val CONFIG_SENSORS_ACPI_POWER n
    scripts/config --set-val CONFIG_SENSORS_ATK0110 n
    scripts/config --set-val CONFIG_SENSORS_CORETEMP n
    scripts/config --set-val CONFIG_SENSORS_FAM15H_POWER n
    scripts/config --set-val CONFIG_SENSORS_K10TEMP n
    scripts/config --set-val CONFIG_SENSORS_VIA_CPUTEMP n
    scripts/config --set-val CONFIG_SENSORS_VIA686A n
    scripts/config --set-val CONFIG_SENSORS_VT1211 n
    scripts/config --set-val CONFIG_SENSORS_VT8231 n
    scripts/config --set-val CONFIG_SENSORS_XGENE n
    
    # ===== I2C/SPI/GPIO (WSL2 不需要) =====
    echo "  - 关闭 I2C/SPI/GPIO" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_I2C n
    scripts/config --set-val CONFIG_I2C_CHARDEV n
    scripts/config --set-val CONFIG_I2C_MUX n
    scripts/config --set-val CONFIG_SPI n
    scripts/config --set-val CONFIG_SPI_MEM n
    scripts/config --set-val CONFIG_GPIO_SYSFS n
    scripts/config --set-val CONFIG_GPIOLIB n
    scripts/config --set-val CONFIG_GPIO_ACPI n
    
    # ===== 打印 (WSL2 不需要) =====
    echo "  - 关闭打印支持" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_PRINTER n
    scripts/config --set-val CONFIG_LP_CONSOLE n
    scripts/config --set-val CONFIG_PPDEV n
    scripts/config --set-val CONFIG_PARPORT n
    scripts/config --set-val CONFIG_PARPORT_PC n
    scripts/config --set-val CONFIG_PARPORT_SERIAL n
    scripts/config --set-val CONFIG_PARPORT_PC_FIFO n
    scripts/config --set-val CONFIG_PARPORT_PC_SUPERIO n
    
    # ===== PCCARD/PCMCIA (WSL2 不需要) =====
    echo "  - 关闭 PCCARD/PCMCIA" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_PCCARD n
    scripts/config --set-val CONFIG_PCMCIA n
    scripts/config --set-val CONFIG_CARDBUS n
    
    # ===== DMA (WSL2 精简) =====
    echo "  - 关闭 DMA 引擎" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_DMADEVICES n
    scripts/config --set-val CONFIG_ASYNC_TX_DMA n
    scripts/config --set-val CONFIG_DMATEST n
    
    # ===== EDAC (内存错误检测，WSL2 不需要) =====
    echo "  - 关闭 EDAC" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_EDAC n
    scripts/config --set-val CONFIG_EDAC_LEGACY_SYSFS n
    scripts/config --set-val CONFIG_EDAC_AMD64 n
    scripts/config --set-val CONFIG_EDAC_E752X n
    scripts/config --set-val CONFIG_EDAC_I82975X n
    scripts/config --set-val CONFIG_EDAC_I3000 n
    scripts/config --set-val CONFIG_EDAC_I3200 n
    scripts/config --set-val CONFIG_EDAC_IE31200 n
    scripts/config --set-val CONFIG_EDAC_X38 n
    scripts/config --set-val CONFIG_EDAC_I5400 n
    scripts/config --set-val CONFIG_EDAC_I7CORE n
    scripts/config --set-val CONFIG_EDAC_I5000 n
    scripts/config --set-val CONFIG_EDAC_I5100 n
    scripts/config --set-val CONFIG_EDAC_PND2 n
    
    # ===== RTC (WSL2 精简) =====
    echo "  - 精简 RTC 驱动" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_RTC_CLASS n
    scripts/config --set-val CONFIG_RTC_HCTOSYS n
    scripts/config --set-val CONFIG_RTC_SYSTOHC n
    scripts/config --set-val CONFIG_RTC_INTF_SYSFS n
    scripts/config --set-val CONFIG_RTC_INTF_PROC n
    scripts/config --set-val CONFIG_RTC_INTF_DEV n
    scripts/config --set-val CONFIG_RTC_DRV_CMOS n
    scripts/config --set-val CONFIG_RTC_DRV_DS1307 n
    scripts/config --set-val CONFIG_RTC_DRV_DS1374 n
    scripts/config --set-val CONFIG_RTC_DRV_DS1672 n
    scripts/config --set-val CONFIG_RTC_DRV_DS3232 n
    scripts/config --set-val CONFIG_RTC_DRV_MAX6900 n
    scripts/config --set-val CONFIG_RTC_DRV_RS5C372 n
    scripts/config --set-val CONFIG_RTC_DRV_ISL1208 n
    scripts/config --set-val CONFIG_RTC_DRV_ISL12022 n
    scripts/config --set-val CONFIG_RTC_DRV_X1205 n
    scripts/config --set-val CONFIG_RTC_DRV_PCF2127 n
    scripts/config --set-val CONFIG_RTC_DRV_PCF8523 n
    scripts/config --set-val CONFIG_RTC_DRV_PCF85063 n
    scripts/config --set-val CONFIG_RTC_DRV_PCF8563 n
    scripts/config --set-val CONFIG_RTC_DRV_PCF8583 n
    scripts/config --set-val CONFIG_RTC_DRV_M41T80 n
    scripts/config --set-val CONFIG_RTC_DRV_BQ32K n
    scripts/config --set-val CONFIG_RTC_DRV_S35390A n
    scripts/config --set-val CONFIG_RTC_DRV_FM3130 n
    scripts/config --set-val CONFIG_RTC_DRV_RX8581 n
    scripts/config --set-val CONFIG_RTC_DRV_RX8025 n
    scripts/config --set-val CONFIG_RTC_DRV_EM3027 n
    scripts/config --set-val CONFIG_RTC_DRV_RV3029C2 n
    scripts/config --set-val CONFIG_RTC_DRV_RV8803 n
    scripts/config --set-val CONFIG_RTC_DRV_SD3078 n
    
    # ===== 调试/跟踪 (关闭加速编译) =====
    echo "  - 关闭调试/跟踪功能" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_DEBUG_KERNEL n
    scripts/config --set-val CONFIG_DEBUG_FS n
    scripts/config --set-val CONFIG_DEBUG_FS_ALLOW_ALL n
    scripts/config --set-val CONFIG_DYNAMIC_DEBUG n
    scripts/config --set-val CONFIG_DEBUG_MISC n
    scripts/config --set-val CONFIG_DEBUG_RODATA_TEST n
    scripts/config --set-val CONFIG_DEBUG_WX n
    scripts/config --set-val CONFIG_DEBUG_KMEMLEAK n
    scripts/config --set-val CONFIG_DEBUG_STACK_USAGE n
    scripts/config --set-val CONFIG_DEBUG_MEMORY_INIT n
    scripts/config --set-val CONFIG_DEBUG_PER_CPU_MAPS n
    scripts/config --set-val CONFIG_DEBUG_SHIRQ n
    scripts/config --set-val CONFIG_LOCKUP_DETECTOR n
    scripts/config --set-val CONFIG_SOFTLOCKUP_DETECTOR n
    scripts/config --set-val CONFIG_HARDLOCKUP_DETECTOR n
    scripts/config --set-val CONFIG_DETECT_HUNG_TASK n
    scripts/config --set-val CONFIG_WQ_WATCHDOG n
    scripts/config --set-val CONFIG_PANIC_ON_OOPS n
    scripts/config --set-val CONFIG_PANIC_TIMEOUT 0
    scripts/config --set-val CONFIG_SCHED_DEBUG n
    scripts/config --set-val CONFIG_SCHEDSTATS n
    scripts/config --set-val CONFIG_TIMER_STATS n
    scripts/config --set-val CONFIG_DEBUG_PREEMPT n
    scripts/config --set-val CONFIG_DEBUG_RT_MUTEXES n
    scripts/config --set-val CONFIG_DEBUG_SPINLOCK n
    scripts/config --set-val CONFIG_DEBUG_MUTEXES n
    scripts/config --set-val CONFIG_DEBUG_RWSEMS n
    scripts/config --set-val CONFIG_DEBUG_ATOMIC_SLEEP n
    scripts/config --set-val CONFIG_DEBUG_LOCKING_API_SELFTESTS n
    scripts/config --set-val CONFIG_LOCK_TORTURE_TEST n
    scripts/config --set-val CONFIG_DEBUG_KOBJECT n
    scripts/config --set-val CONFIG_DEBUG_BUGVERBOSE n
    scripts/config --set-val CONFIG_DEBUG_LIST n
    scripts/config --set-val CONFIG_DEBUG_PLIST n
    scripts/config --set-val CONFIG_DEBUG_SG n
    scripts/config --set-val CONFIG_DEBUG_NOTIFIERS n
    scripts/config --set-val CONFIG_DEBUG_CREDENTIALS n
    scripts/config --set-val CONFIG_RCU_CPU_STALL_TIMEOUT 60
    scripts/config --set-val CONFIG_RCU_TRACE n
    scripts/config --set-val CONFIG_RCU_EQS_DEBUG n
    scripts/config --set-val CONFIG_DEBUG_WQ_FORCE_RR_CPU n
    scripts/config --set-val CONFIG_CPU_HOTPLUG_STATE_CONTROL n
    scripts/config --set-val CONFIG_NOP_TRACER n
    scripts/config --set-val CONFIG_HAVE_FUNCTION_TRACER n
    scripts/config --set-val CONFIG_HAVE_FUNCTION_GRAPH_TRACER n
    scripts/config --set-val CONFIG_HAVE_DYNAMIC_FTRACE n
    scripts/config --set-val CONFIG_HAVE_FTRACE_MCOUNT_RECORD n
    scripts/config --set-val CONFIG_HAVE_SYSCALL_TRACEPOINTS n
    scripts/config --set-val CONFIG_HAVE_FENTRY n
    scripts/config --set-val CONFIG_HAVE_C_RECORDMCOUNT n
    scripts/config --set-val CONFIG_TRACER_MAX_TRACE n
    scripts/config --set-val CONFIG_TRACE_CLOCK n
    scripts/config --set-val CONFIG_RING_BUFFER n
    scripts/config --set-val CONFIG_EVENT_TRACING n
    scripts/config --set-val CONFIG_CONTEXT_SWITCH_TRACER n
    scripts/config --set-val CONFIG_RING_BUFFER_ALLOW_SWAP n
    scripts/config --set-val CONFIG_TRACING n
    scripts/config --set-val CONFIG_GENERIC_TRACER n
    scripts/config --set-val CONFIG_TRACING_SUPPORT n
    scripts/config --set-val CONFIG_FTRACE n
    scripts/config --set-val CONFIG_FUNCTION_TRACER n
    scripts/config --set-val CONFIG_FUNCTION_GRAPH_TRACER n
    scripts/config --set-val CONFIG_DYNAMIC_FTRACE n
    scripts/config --set-val CONFIG_DYNAMIC_FTRACE_WITH_REGS n
    scripts/config --set-val CONFIG_DYNAMIC_FTRACE_WITH_DIRECT_CALLS n
    scripts/config --set-val CONFIG_FUNCTION_PROFILER n
    scripts/config --set-val CONFIG_STACK_TRACER n
    scripts/config --set-val CONFIG_IRQSOFF_TRACER n
    scripts/config --set-val CONFIG_SCHED_TRACER n
    scripts/config --set-val CONFIG_HWLAT_TRACER n
    scripts/config --set-val CONFIG_OSNOISE_TRACER n
    scripts/config --set-val CONFIG_TIMERLAT_TRACER n
    scripts/config --set-val CONFIG_MMIOTRACE n
    scripts/config --set-val CONFIG_FTRACE_SYSCALLS n
    scripts/config --set-val CONFIG_TRACER_SNAPSHOT n
    scripts/config --set-val CONFIG_TRACER_SNAPSHOT_PER_CPU_SWAP n
    scripts/config --set-val CONFIG_BRANCH_PROFILE_NONE y
    scripts/config --set-val CONFIG_PROFILE_ANNOTATED_BRANCHES n
    scripts/config --set-val CONFIG_PROFILE_ALL_BRANCHES n
    scripts/config --set-val CONFIG_BLK_DEV_IO_TRACE n
    scripts/config --set-val CONFIG_KPROBE_EVENTS n
    scripts/config --set-val CONFIG_UPROBE_EVENTS n
    scripts/config --set-val CONFIG_BPF_EVENTS n
    scripts/config --set-val CONFIG_DYNAMIC_EVENTS n
    scripts/config --set-val CONFIG_PROBE_EVENTS n
    scripts/config --set-val CONFIG_BPF_KPROBE_OVERRIDE n
    scripts/config --set-val CONFIG_FTRACE_MCOUNT_RECORD n
    scripts/config --set-val CONFIG_FTRACE_MCOUNT_USE_CC n
    scripts/config --set-val CONFIG_SYNTH_EVENTS n
    scripts/config --set-val CONFIG_HIST_TRIGGERS n
    scripts/config --set-val CONFIG_TRACE_EVENT_INJECT n
    scripts/config --set-val CONFIG_TRACEPOINT_BENCHMARK n
    
    # ===== KEXEC / Kdump (WSL2 不需要) =====
    echo "  - 关闭 KEXEC/Kdump" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_KEXEC n
    scripts/config --set-val CONFIG_KEXEC_FILE n
    scripts/config --set-val CONFIG_CRASH_DUMP n
    scripts/config --set-val CONFIG_CRASH_RESERVE n
    scripts/config --set-val CONFIG_VMCORE_INFO n
    scripts/config --set-val CONFIG_PROC_VMCORE n
    scripts/config --set-val CONFIG_RELOCATABLE n
    
    # ===== 安全子系统 (精简) =====
    echo "  - 精简安全子系统" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_SECURITY_SELINUX n
    scripts/config --set-val CONFIG_SECURITY_SMACK n
    scripts/config --set-val CONFIG_SECURITY_TOMOYO n
    scripts/config --set-val CONFIG_SECURITY_APPARMOR y # Ubuntu 默认
    scripts/config --set-val CONFIG_SECURITY_YAMA n
    scripts/config --set-val CONFIG_SECURITY_SAFESETID n
    scripts/config --set-val CONFIG_SECURITY_LOCKDOWN_LSM n
    scripts/config --set-val CONFIG_SECURITY_LANDLOCK n
    scripts/config --set-val CONFIG_INTEGRITY n
    scripts/config --set-val CONFIG_IMA n
    scripts/config --set-val CONFIG_IMA_MEASURE_PCR_IDX 10
    scripts/config --set-val CONFIG_IMA_NG_TEMPLATE n
    scripts/config --set-val CONFIG_IMA_SIG_TEMPLATE n
    scripts/config --set-val CONFIG_IMA_DEFAULT_TEMPLATE ima-ng
    scripts/config --set-val CONFIG_IMA_DEFAULT_HASH_SHA1 n
    scripts/config --set-val CONFIG_IMA_DEFAULT_HASH_SHA256 y
    scripts/config --set-val CONFIG_IMA_DEFAULT_HASH_SHA512 n
    scripts/config --set-val CONFIG_IMA_DEFAULT_HASH_WP512 n
    scripts/config --set-val CONFIG_IMA_DEFAULT_HASH_SM3 n
    scripts/config --set-val CONFIG_IMA_WRITE_POLICY n
    scripts/config --set-val CONFIG_IMA_READ_POLICY n
    scripts/config --set-val CONFIG_IMA_APPRAISE n
    scripts/config --set-val CONFIG_IMA_APPRAISE_BOOTPARAM n
    scripts/config --set-val CONFIG_IMA_KEYRINGS_PERMIT_SIGNED_BY_BUILTIN_OR_SECONDARY n
    scripts/config --set-val CONFIG_IMA_BLACKLIST_KEYRING n
    scripts/config --set-val CONFIG_IMA_LOAD_X509 n
    scripts/config --set-val CONFIG_IMA_X509_PATH /etc/keys/x509_ima.der
    scripts/config --set-val CONFIG_IMA_APPRAISE_SIGNED_INIT n
    scripts/config --set-val CONFIG_IMA_MEASURE_ASYMMETRIC_KEYS n
    scripts/config --set-val CONFIG_IMA_QUEUE_EARLY_BOOT_KEYS n
    scripts/config --set-val CONFIG_IMA_SECURE_AND_OR_TRUSTED_BOOT n
    scripts/config --set-val CONFIG_EVM n
    scripts/config --set-val CONFIG_EVM_ATTR_FSUUID n
    scripts/config --set-val CONFIG_EVM_EXTRA_SMACK_XATTRS n
    scripts/config --set-val CONFIG_EVM_ADD_XATTRS n
    scripts/config --set-val CONFIG_EVM_LOAD_X509 n
    scripts/config --set-val CONFIG_EVM_X509_PATH /etc/keys/x509_evm.der
    scripts/config --set-val CONFIG_EVM_TRUSTED_KEYSOURCE n
    scripts/config --set-val CONFIG_LSM lockdown,yama,integrity,apparmor
    scripts/config --set-val CONFIG_DEFAULT_SECURITY apparmor
    
    # ===== 各种杂项驱动 (关闭) =====
    echo "  - 关闭杂项驱动" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_MISC_FILESYSTEMS n
    scripts/config --set-val CONFIG_AD525X_DPOT n
    scripts/config --set-val CONFIG_DUMMY_IRQ n
    scripts/config --set-val CONFIG_IBM_ASM n
    scripts/config --set-val CONFIG_PHANTOM n
    scripts/config --set-val CONFIG_SGI_IOC4 n
    scripts/config --set-val CONFIG_TIFM_CORE n
    scripts/config --set-val CONFIG_TIFM_7XX1 n
    scripts/config --set-val CONFIG_ICS932S401 n
    scripts/config --set-val CONFIG_ENCLOSURE_SERVICES n
    scripts/config --set-val CONFIG_HP_ILO n
    scripts/config --set-val CONFIG_APDS9802ALS n
    scripts/config --set-val CONFIG_ISL29003 n
    scripts/config --set-val CONFIG_ISL29020 n
    scripts/config --set-val CONFIG_SENSORS_TSL2550 n
    scripts/config --set-val CONFIG_SENSORS_BH1770 n
    scripts/config --set-val CONFIG_SENSORS_APDS990X n
    scripts/config --set-val CONFIG_HMC6352 n
    scripts/config --set-val CONFIG_DS1682 n
    scripts/config --set-val CONFIG_LATTICE_ECP3_CONFIG n
    scripts/config --set-val CONFIG_SRAM n
    scripts/config --set-val CONFIG_PCI_ENDPOINT_TEST n
    scripts/config --set-val CONFIG_XILINX_SDFEC n
    scripts/config --set-val CONFIG_PVPANIC n
    scripts/config --set-val CONFIG_C2PORT n
    
    # ===== ACPI (WSL2 精简) =====
    echo "  - 精简 ACPI 驱动" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_ACPI y           # 保留基本 ACPI
    scripts/config --set-val CONFIG_ACPI_AC n
    scripts/config --set-val CONFIG_ACPI_BATTERY n
    scripts/config --set-val CONFIG_ACPI_BUTTON y
    scripts/config --set-val CONFIG_ACPI_VIDEO n
    scripts/config --set-val CONFIG_ACPI_FAN n
    scripts/config --set-val CONFIG_ACPI_DOCK n
    scripts/config --set-val CONFIG_ACPI_PROCESSOR y
    scripts/config --set-val CONFIG_ACPI_IPMI n
    scripts/config --set-val CONFIG_ACPI_HOTPLUG_CPU n
    scripts/config --set-val CONFIG_ACPI_HOTPLUG_MEMORY n
    scripts/config --set-val CONFIG_ACPI_HOTPLUG_IOAPIC n
    scripts/config --set-val CONFIG_ACPI_SBS n
    scripts/config --set-val CONFIG_ACPI_HED n
    scripts/config --set-val CONFIG_ACPI_CUSTOM_METHOD n
    scripts/config --set-val CONFIG_ACPI_BGRT n
    scripts/config --set-val CONFIG_ACPI_REDUCED_HARDWARE_ONLY n
    scripts/config --set-val CONFIG_ACPI_NUMA n
    scripts/config --set-val CONFIG_ACPI_ADXL n
    scripts/config --set-val CONFIG_ACPI_CONFIGFS n
    scripts/config --set-val CONFIG_X86_PM_TIMER n
    
    # ===== 电源管理 (WSL2 精简) =====
    echo "  - 精简电源管理" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_CPU_FREQ y       # 保留 CPU 频率调节
    scripts/config --set-val CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE y
    scripts/config --set-val CONFIG_CPU_FREQ_GOV_PERFORMANCE y
    scripts/config --set-val CONFIG_CPU_FREQ_GOV_POWERSAVE n
    scripts/config --set-val CONFIG_CPU_FREQ_GOV_USERSPACE n
    scripts/config --set-val CONFIG_CPU_FREQ_GOV_ONDEMAND n
    scripts/config --set-val CONFIG_CPU_FREQ_GOV_CONSERVATIVE n
    scripts/config --set-val CONFIG_CPU_FREQ_GOV_SCHEDUTIL n
    scripts/config --set-val CONFIG_X86_INTEL_PSTATE n
    scripts/config --set-val CONFIG_X86_AMD_PSTATE y # AMD 频率调节
    scripts/config --set-val CONFIG_X86_AMD_FREQ_SENSITIVITY n
    scripts/config --set-val CONFIG_CPU_IDLE y
    scripts/config --set-val CONFIG_CPU_IDLE_GOV_LADDER n
    scripts/config --set-val CONFIG_CPU_IDLE_GOV_MENU y
    scripts/config --set-val CONFIG_CPU_IDLE_GOV_TEO n
    scripts/config --set-val CONFIG_INTEL_IDLE n
    scripts/config --set-val CONFIG_AMD_IDLE n
    scripts/config --set-val CONFIG_PM y
    scripts/config --set-val CONFIG_PM_DEBUG n
    scripts/config --set-val CONFIG_PM_ADVANCED_DEBUG n
    scripts/config --set-val CONFIG_PM_TEST_SUSPEND n
    scripts/config --set-val CONFIG_PM_SLEEP_DEBUG n
    scripts/config --set-val CONFIG_PM_TRACE n
    scripts/config --set-val CONFIG_PM_TRACE_RTC n
    scripts/config --set-val CONFIG_APM n
    scripts/config --set-val CONFIG_SUSPEND n
    scripts/config --set-val CONFIG_HIBERNATION n
    scripts/config --set-val CONFIG_HIBERNATION_SNAPSHOT_DEV n
    
    # ===== 看门狗 (WSL2 不需要) =====
    echo "  - 关闭看门狗" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_WATCHDOG n
    scripts/config --set-val CONFIG_WATCHDOG_CORE n
    scripts/config --set-val CONFIG_SOFT_WATCHDOG n
    scripts/config --set-val CONFIG_WDAT_WDT n
    scripts/config --set-val CONFIG_XILINX_WATCHDOG n
    scripts/config --set-val CONFIG_ZIIRAVE_WATCHDOG n
    scripts/config --set-val CONFIG_CADENCE_WATCHDOG n
    scripts/config --set-val CONFIG_DW_WATCHDOG n
    scripts/config --set-val CONFIG_MAX63XX_WATCHDOG n
    scripts/config --set-val CONFIG_RETU_WATCHDOG n
    scripts/config --set-val CONFIG_ACQUIRE_WDT n
    scripts/config --set-val CONFIG_ADVANTECH_WDT n
    scripts/config --set-val CONFIG_ALIM1535_WDT n
    scripts/config --set-val CONFIG_ALIM7101_WDT n
    scripts/config --set-val CONFIG_EBC_C384_WDT n
    scripts/config --set-val CONFIG_EXAR_WDT n
    scripts/config --set-val CONFIG_F71808E_WDT n
    scripts/config --set-val CONFIG_SP5100_TCO n
    scripts/config --set-val CONFIG_SBC_FITPC2_WATCHDOG n
    scripts/config --set-val CONFIG_EUROTECH_WDT n
    scripts/config --set-val CONFIG_IB700_WDT n
    scripts/config --set-val CONFIG_IBMASR n
    scripts/config --set-val CONFIG_WAFER_WDT n
    scripts/config --set-val CONFIG_I6300ESB_WDT n
    scripts/config --set-val CONFIG_IE6XX_WDT n
    scripts/config --set-val CONFIG_ITCO_WDT n
    scripts/config --set-val CONFIG_IT8712F_WDT n
    scripts/config --set-val CONFIG_IT87_WDT n
    scripts/config --set-val CONFIG_HP_WATCHDOG n
    scripts/config --set-val CONFIG_KEMPLD_WDT n
    scripts/config --set-val CONFIG_HIPPIE_WDT n
    scripts/config --set-val CONFIG_SC1200_WDT n
    scripts/config --set-val CONFIG_PC87413_WDT n
    scripts/config --set-val CONFIG_NV_TCO n
    scripts/config --set-val CONFIG_60XX_WDT n
    scripts/config --set-val CONFIG_CPU5_WDT n
    scripts/config --set-val CONFIG_SMSC_SCH311X_WDT n
    scripts/config --set-val CONFIG_SMSC37B787_WDT n
    scripts/config --set-val CONFIG_TQMX86_WDT n
    scripts/config --set-val CONFIG_VIA_WDT n
    scripts/config --set-val CONFIG_W83627HF_WDT n
    scripts/config --set-val CONFIG_W83877F_WDT n
    scripts/config --set-val CONFIG_W83977F_WDT n
    scripts/config --set-val CONFIG_MACHZ_WDT n
    scripts/config --set-val CONFIG_SBC_EPX_C3_WATCHDOG n
    scripts/config --set-val CONFIG_NI903X_WDT n
    scripts/config --set-val CONFIG_NIC7018_WDT n
    scripts/config --set-val CONFIG_MEN_A21_WDT n
    scripts/config --set-val CONFIG_XEN_WDT n
    
    # ===== 字符设备 (WSL2 精简) =====
    echo "  - 精简字符设备" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_TTY y
    scripts/config --set-val CONFIG_VT y
    scripts/config --set-val CONFIG_CONSOLE_TRANSLATIONS y
    scripts/config --set-val CONFIG_VT_CONSOLE y
    scripts/config --set-val CONFIG_VT_CONSOLE_SLEEP n
    scripts/config --set-val CONFIG_HW_CONSOLE y
    scripts/config --set-val CONFIG_VT_HW_CONSOLE_BINDING n
    scripts/config --set-val CONFIG_UNIX98_PTYS y
    scripts/config --set-val CONFIG_LEGACY_PTYS n
    scripts/config --set-val CONFIG_SERIAL_NONSTANDARD n
    scripts/config --set-val CONFIG_ROCKETPORT n
    scripts/config --set-val CONFIG_CYCLADES n
    scripts/config --set-val CONFIG_DIGIEPCA n
    scripts/config --set-val CONFIG_MOXA_INTELLIO n
    scripts/config --set-val CONFIG_MOXA_SMARTIO n
    scripts/config --set-val CONFIG_SYNCLINKMP n
    scripts/config --set-val CONFIG_SYNCLINK_GT n
    scripts/config --set-val CONFIG_ISI n
    scripts/config --set-val CONFIG_N_HDLC n
    scripts/config --set-val CONFIG_N_GSM n
    scripts/config --set-val CONFIG_NOZOMI n
    scripts/config --set-val CONFIG_NULL_TTY n
    scripts/config --set-val CONFIG_TRACE_SINK n
    scripts/config --set-val CONFIG_SERIAL_EARLYCON n
    scripts/config --set-val CONFIG_SERIAL_8250 y
    scripts/config --set-val CONFIG_SERIAL_8250_DEPRECATED_OPTIONS n
    scripts/config --set-val CONFIG_SERIAL_8250_PNP n
    scripts/config --set-val CONFIG_SERIAL_8250_16550A_VARIANTS y
    scripts/config --set-val CONFIG_SERIAL_8250_FINTEK n
    scripts/config --set-val CONFIG_SERIAL_8250_CONSOLE y
    scripts/config --set-val CONFIG_SERIAL_8250_DMA n
    scripts/config --set-val CONFIG_SERIAL_8250_PCI n
    scripts/config --set-val CONFIG_SERIAL_8250_EXAR n
    scripts/config --set-val CONFIG_SERIAL_8250_CS n
    scripts/config --set-val CONFIG_SERIAL_8250_MEN_MCB n
    scripts/config --set-val CONFIG_SERIAL_8250_NR_UARTS 4
    scripts/config --set-val CONFIG_SERIAL_8250_RUNTIME_UARTS 4
    scripts/config --set-val CONFIG_SERIAL_8250_EXTENDED n
    scripts/config --set-val CONFIG_SERIAL_8250_ASPEED_VUART n
    scripts/config --set-val CONFIG_SERIAL_8250_PERICOM n
    scripts/config --set-val CONFIG_SERIAL_ARC n
    scripts/config --set-val CONFIG_SERIAL_RP2 n
    scripts/config --set-val CONFIG_SERIAL_FSL_LPUART n
    scripts/config --set-val CONFIG_SERIAL_FSL_LINFLEXUART n
    scripts/config --set-val CONFIG_SERIAL_MEN_Z135 n
    scripts/config --set-val CONFIG_SERIAL_SPRD n
    scripts/config --set-val CONFIG_SERIAL_CORE y
    scripts/config --set-val CONFIG_SERIAL_CORE_CONSOLE y
    scripts/config --set-val CONFIG_SERIAL_JSM n
    scripts/config --set-val CONFIG_SERIAL_SCCNXP n
    scripts/config --set-val CONFIG_SERIAL_SC16IS7XX n
    scripts/config --set-val CONFIG_SERIAL_ALTERA_JTAGUART n
    scripts/config --set-val CONFIG_SERIAL_ALTERA_UART n
    scripts/config --set-val CONFIG_SERIAL_XILINX_PS_UART n
    scripts/config --set-val CONFIG_SERIAL_AR933X n
    scripts/config --set-val CONFIG_SERIAL_MESON n
    scripts/config --set-val CONFIG_SERIAL_MESON_CONSOLE n
    scripts/config --set-val CONFIG_SERIAL_MAX3100 n
    scripts/config --set-val CONFIG_SERIAL_MAX310X n
    scripts/config --set-val CONFIG_SERIAL_UARTLITE n
    scripts/config --set-val CONFIG_SERIAL_UARTLITE_CONSOLE n
    scripts/config --set-val CONFIG_SERIAL_SH_SCI n
    scripts/config --set-val CONFIG_SERIAL_SH_SCI_CONSOLE n
    scripts/config --set-val CONFIG_SERIAL_HS_LPC32XX n
    scripts/config --set-val CONFIG_SERIAL_QCOM_GENI n
    scripts/config --set-val CONFIG_SERIAL_QCOM_GENI_CONSOLE n
    scripts/config --set-val CONFIG_SERIAL_LANTIQ n
    scripts/config --set-val CONFIG_SERIAL_SIFIVE n
    scripts/config --set-val CONFIG_SERIAL_SIFIVE_CONSOLE n
    scripts/config --set-val CONFIG_SERIAL_LPSC n
    scripts/config --set-val CONFIG_SERIAL_MCTRL_GPIO n
    scripts/config --set-val CONFIG_SERIAL_DEV_BUS y
    scripts/config --set-val CONFIG_TCG_TPM n
    scripts/config --set-val CONFIG_TCG_TIS n
    scripts/config --set-val CONFIG_TCG_TIS_SPI n
    scripts/config --set-val CONFIG_TCG_TIS_I2C n
    scripts/config --set-val CONFIG_TCG_TIS_I2C_CR50 n
    scripts/config --set-val CONFIG_TCG_TIS_I2C_ATMEL n
    scripts/config --set-val CONFIG_TCG_TIS_I2C_INFINEON n
    scripts/config --set-val CONFIG_TCG_TIS_I2C_NUVOTON n
    scripts/config --set-val CONFIG_TCG_NSC n
    scripts/config --set-val CONFIG_TCG_ATMEL n
    scripts/config --set-val CONFIG_TCG_INFINEON n
    scripts/config --set-val CONFIG_TCG_XEN n
    scripts/config --set-val CONFIG_TCG_CRB n
    scripts/config --set-val CONFIG_TCG_VTPM_PROXY n
    scripts/config --set-val CONFIG_TCG_TIS_ST33ZP24 n
    scripts/config --set-val CONFIG_TCG_TIS_ST33ZP24_I2C n
    scripts/config --set-val CONFIG_TCG_TIS_ST33ZP24_SPI n
    scripts/config --set-val CONFIG_TCG_TIS_SYNQUACER n
    scripts/config --set-val CONFIG_TCG_TIS_I2C_HID n
    
    # ===== MISC (WSL2 不需要) =====
    echo "  - 关闭 MISC 设备" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_MWAVE n
    scripts/config --set-val CONFIG_HAVE_IDE n
    scripts/config --set-val CONFIG_IDE n
    scripts/config --set-val CONFIG_BLK_DEV_IDE n
    scripts/config --set-val CONFIG_BLK_DEV_IDECD n
    scripts/config --set-val CONFIG_BLK_DEV_IDETAPE n
    scripts/config --set-val CONFIG_BLK_DEV_IDEACPI n
    scripts/config --set-val CONFIG_BLK_DEV_IDE_PMAC n
    scripts/config --set-val CONFIG_BLK_DEV_IDE_PMAC_ATA100FIRST n
    scripts/config --set-val CONFIG_BLK_DEV_IDE_GENERIC n
    scripts/config --set-val CONFIG_BLK_DEV_PLATFORM n
    scripts/config --set-val CONFIG_BLK_DEV_CMD640 n
    scripts/config --set-val CONFIG_BLK_DEV_CMD640_ENHANCED n
    scripts/config --set-val CONFIG_BLK_DEV_IDEPNP n
    scripts/config --set-val CONFIG_BLK_DEV_IDEDMA_SFF n
    scripts/config --set-val CONFIG_BLK_DEV_IDEPCI n
    scripts/config --set-val CONFIG_IDEPCI_PCIBUS_ORDER n
    scripts/config --set-val CONFIG_BLK_DEV_OFFBOARD n
    scripts/config --set-val CONFIG_BLK_DEV_IDEDMA_PCI n
    scripts/config --set-val CONFIG_BLK_DEV_AEC62XX n
    scripts/config --set-val CONFIG_BLK_DEV_ALI15X3 n
    scripts/config --set-val CONFIG_BLK_DEV_AMD74XX n
    scripts/config --set-val CONFIG_BLK_DEV_ATIIXP n
    scripts/config --set-val CONFIG_BLK_DEV_CMD64X n
    scripts/config --set-val CONFIG_BLK_DEV_TRIFLEX n
    scripts/config --set-val CONFIG_BLK_DEV_CS5520 n
    scripts/config --set-val CONFIG_BLK_DEV_CS5530 n
    scripts/config --set-val CONFIG_BLK_DEV_CS5535 n
    scripts/config --set-val CONFIG_BLK_DEV_CS5536 n
    scripts/config --set-val CONFIG_BLK_DEV_HPT366 n
    scripts/config --set-val CONFIG_BLK_DEV_JMICRON n
    scripts/config --set-val CONFIG_BLK_DEV_SC1200 n
    scripts/config --set-val CONFIG_BLK_DEV_PIIX n
    scripts/config --set-val CONFIG_BLK_DEV_IT8172 n
    scripts/config --set-val CONFIG_BLK_DEV_IT8213 n
    scripts/config --set-val CONFIG_BLK_DEV_IT821X n
    scripts/config --set-val CONFIG_BLK_DEV_NS87415 n
    scripts/config --set-val CONFIG_BLK_DEV_PDC202XX_OLD n
    scripts/config --set-val CONFIG_BLK_DEV_PDC202XX_NEW n
    scripts/config --set-val CONFIG_BLK_DEV_RZ1000 n
    scripts/config --set-val CONFIG_BLK_DEV_SVWKS n
    scripts/config --set-val CONFIG_BLK_DEV_SIIMAGE n
    scripts/config --set-val CONFIG_BLK_DEV_SIS5513 n
    scripts/config --set-val CONFIG_BLK_DEV_SLC90E66 n
    scripts/config --set-val CONFIG_BLK_DEV_TRM290 n
    scripts/config --set-val CONFIG_BLK_DEV_VIA82CXXX n
    scripts/config --set-val CONFIG_BLK_DEV_TC86C001 n
    scripts/config --set-val CONFIG_BLK_DEV_IDE_PDC202XX n
    scripts/config --set-val CONFIG_BLK_DEV_IDE_SATA n
    scripts/config --set-val CONFIG_BLK_DEV_IDEDMA n
    scripts/config --set-val CONFIG_IDE_XFER_MODE n
    scripts/config --set-val CONFIG_IDE_TIMINGS n
    scripts/config --set-val CONFIG_IDE_ATAPI n
    scripts/config --set-val CONFIG_BLK_DEV_IDE_SATA y
    scripts/config --set-val CONFIG_SCSI n
    scripts/config --set-val CONFIG_BLK_DEV_SD n
    scripts/config --set-val CONFIG_BLK_DEV_SR n
    scripts/config --set-val CONFIG_CHR_DEV_SG n
    scripts/config --set-val CONFIG_CHR_DEV_SCH n
    scripts/config --set-val CONFIG_SCSI_ENCLOSURE n
    scripts/config --set-val CONFIG_SCSI_CONSTANTS n
    scripts/config --set-val CONFIG_SCSI_LOGGING n
    scripts/config --set-val CONFIG_SCSI_SCAN_ASYNC n
    scripts/config --set-val CONFIG_SCSI_SPI_ATTRS n
    scripts/config --set-val CONFIG_SCSI_FC_ATTRS n
    scripts/config --set-val CONFIG_SCSI_ISCSI_ATTRS n
    scripts/config --set-val CONFIG_SCSI_SAS_ATTRS n
    scripts/config --set-val CONFIG_SCSI_SAS_LIBSAS n
    scripts/config --set-val CONFIG_SCSI_SAS_ATA n
    scripts/config --set-val CONFIG_SCSI_SAS_HOST_SMP n
    scripts/config --set-val CONFIG_SCSI_SRP_ATTRS n
    scripts/config --set-val CONFIG_SCSI_LOWLEVEL n
    scripts/config --set-val CONFIG_ISCSI_TCP n
    scripts/config --set-val CONFIG_ISCSI_BOOT_SYSFS n
    scripts/config --set-val CONFIG_SCSI_CXGB3_ISCSI n
    scripts/config --set-val CONFIG_SCSI_CXGB4_ISCSI n
    scripts/config --set-val CONFIG_SCSI_BNX2_ISCSI n
    scripts/config --set-val CONFIG_SCSI_BNX2X_FCOE n
    scripts/config --set-val CONFIG_BE2ISCSI n
    scripts/config --set-val CONFIG_BLK_DEV_3W_XXXX_RAID n
    scripts/config --set-val CONFIG_SCSI_HPSA n
    scripts/config --set-val CONFIG_SCSI_3W_9XXX n
    scripts/config --set-val CONFIG_SCSI_3W_SAS n
    scripts/config --set-val CONFIG_SCSI_ACARD n
    scripts/config --set-val CONFIG_SCSI_AACRAID n
    scripts/config --set-val CONFIG_SCSI_AIC7XXX n
    scripts/config --set-val CONFIG_SCSI_AIC79XX n
    scripts/config --set-val CONFIG_SCSI_AIC94XX n
    scripts/config --set-val CONFIG_SCSI_MVSAS n
    scripts/config --set-val CONFIG_SCSI_MVSAS_DEBUG n
    scripts/config --set-val CONFIG_SCSI_MVSAS_TASKLET n
    scripts/config --set-val CONFIG_SCSI_MVUMI n
    scripts/config --set-val CONFIG_SCSI_ADVANSYS n
    scripts/config --set-val CONFIG_SCSI_ARCMSR n
    scripts/config --set-val CONFIG_SCSI_ESAS2R n
    scripts/config --set-val CONFIG_MEGARAID_NEWGEN n
    scripts/config --set-val CONFIG_MEGARAID_MM n
    scripts/config --set-val CONFIG_MEGARAID_MAILBOX n
    scripts/config --set-val CONFIG_MEGARAID_LEGACY n
    scripts/config --set-val CONFIG_MEGARAID_SAS n
    scripts/config --set-val CONFIG_SCSI_MPT3SAS n
    scripts/config --set-val CONFIG_SCSI_MPT2SAS n
    scripts/config --set-val CONFIG_SCSI_MPI3MR n
    scripts/config --set-val CONFIG_SCSI_SMARTPQI n
    scripts/config --set-val CONFIG_SCSI_HPTIOP n
    scripts/config --set-val CONFIG_SCSI_BUSLOGIC n
    scripts/config --set-val CONFIG_SCSI_FLASHPOINT n
    scripts/config --set-val CONFIG_SCSI_MYRB n
    scripts/config --set-val CONFIG_SCSI_MYRS n
    scripts/config --set-val CONFIG_VMWARE_PVSCSI n
    scripts/config --set-val CONFIG_HYPERV_STORAGE y
    scripts/config --set-val CONFIG_SCSI_SNIC n
    scripts/config --set-val CONFIG_SCSI_DMX3191D n
    scripts/config --set-val CONFIG_SCSI_FDOMAIN_PCI n
    scripts/config --set-val CONFIG_SCSI_FDOMAIN_ISA n
    scripts/config --set-val CONFIG_SCSI_GENERIC_NCR5380 n
    scripts/config --set-val CONFIG_SCSI_GENERIC_NCR5380_MMIO n
    scripts/config --set-val CONFIG_SCSI_IPS n
    scripts/config --set-val CONFIG_SCSI_INITIO n
    scripts/config --set-val CONFIG_SCSI_INIA100 n
    scripts/config --set-val CONFIG_SCSI_STEX n
    scripts/config --set-val CONFIG_SCSI_SYM53C8XX_2 n
    scripts/config --set-val CONFIG_SCSI_IPR n
    scripts/config --set-val CONFIG_SCSI_QLOGIC_1280 n
    scripts/config --set-val CONFIG_SCSI_QLA_FC n
    scripts/config --set-val CONFIG_TCM_QLA2XXX n
    scripts/config --set-val CONFIG_SCSI_QLA_ISCSI n
    scripts/config --set-val CONFIG_QEDI n
    scripts/config --set-val CONFIG_QEDF n
    scripts/config --set-val CONFIG_SCSI_LPFC n
    scripts/config --set-val CONFIG_SCSI_DC395x n
    scripts/config --set-val CONFIG_SCSI_AM53C974 n
    scripts/config --set-val CONFIG_SCSI_WD719X n
    scripts/config --set-val CONFIG_SCSI_DEBUG n
    scripts/config --set-val CONFIG_SCSI_PMCRAID n
    scripts/config --set-val CONFIG_SCSI_PM8001 n
    scripts/config --set-val CONFIG_SCSI_BFA_FC n
    scripts/config --set-val CONFIG_SCSI_VIRTIO y
    scripts/config --set-val CONFIG_SCSI_CHELSIO_FCOE n
    scripts/config --set-val CONFIG_SCSI_LOWLEVEL_PCMCIA n
    scripts/config --set-val CONFIG_SCSI_DH n
    scripts/config --set-val CONFIG_SCSI_DH_RDAC n
    scripts/config --set-val CONFIG_SCSI_DH_HP_SW n
    scripts/config --set-val CONFIG_SCSI_DH_EMC n
    scripts/config --set-val CONFIG_SCSI_DH_ALUA n
    
    # ===== 移除服务器/嵌入式驱动 =====
    echo "  - 移除服务器/嵌入式驱动..." | tee -a "$LOG_FILE"
    
    # Infiniband
    scripts/config --set-val CONFIG_INFINIBAND n
    
    # 光纤通道
    scripts/config --set-val CONFIG_SCSI_FC_ATTRS n
    scripts/config --set-val CONFIG_SCSI_SPI_ATTRS n
    scripts/config --set-val CONFIG_SCSI_SAS_ATTRS n
    scripts/config --set-val CONFIG_SCSI_SAS_LIBSAS n
    
    # RAID
    scripts/config --set-val CONFIG_MD_RAID0 n
    scripts/config --set-val CONFIG_MD_RAID1 n
    scripts/config --set-val CONFIG_MD_RAID10 n
    scripts/config --set-val CONFIG_MD_RAID456 n
    scripts/config --set-val CONFIG_MD_MULTIPATH n
    scripts/config --set-val CONFIG_MD_FAULTY n
    scripts/config --set-val CONFIG_BLK_DEV_DM_RAID n
    scripts/config --set-val CONFIG_DM_MULTIPATH n
    
    # SCSI 控制器 (保留 VirtIO_SCSI，其他关闭)
    scripts/config --set-val CONFIG_SCSI_LOWLEVEL n
    scripts/config --set-val CONFIG_SCSI_LOWLEVEL_PCMCIA n
    for scsi_drv in BFA_FC CHELSIO_FCOE ESAS2R HPSA IPR IBMVSCSI IBMVFC MPT2SAS MPT3SAS SMARTPQI UFSHCD CXGB3_ISCSI CXGB4_ISCSI BNX2_ISCSI BNX2X_FCOE BE2ISCSI PM8001 QLOGIC_1280 QLA_FC QLA_ISCSI LPFC DC395x AM53C974 WD719X DEBUG PMCRAID FDOMAIN_PCI; do
        scripts/config --set-val CONFIG_SCSI_${scsi_drv} n 2>/dev/null || true
    done
    # 注意: 不关闭 VIRTIO_SCSI，WSL2 可能用到
    scripts/config --set-val CONFIG_SCSI_VIRTIO y
    
    # KVM (WSL2 内不需要嵌套虚拟化)
    scripts/config --set-val CONFIG_KVM n
    scripts/config --set-val CONFIG_KVM_INTEL n
    scripts/config --set-val CONFIG_KVM_AMD n
    scripts/config --set-val CONFIG_VHOST_VSOCK n
    scripts/config --set-val CONFIG_VHOST_CROSS_ENDIAN_LEGACY n
    
    # Xen/VMware (不需要)
    scripts/config --set-val CONFIG_XEN n
    for xen_opt in DOM0 PVHVM PVH FBDEV_FRONTEND BLKDEV_FRONTEND BLKDEV_BACKEND NETDEV_FRONTEND NETDEV_BACKEND PCIDEV_FRONTEND PCIDEV_BACKEND SCSI_BACKEND ACPI_PROCESSOR HAVE_PVMMU EFI AUTO_XLATE BALLOON SCRUB_PAGES DEV_EVTCHN BACKEND XENFS COMPAT_XENFS SYS_HYPERVISOR GNTDEV GNTDEV_DMABUF GRANT_DEV_ALLOC SWIOTLB_XEN PVCALLS_BACKEND PVCALLS_FRONTEND PRIVCMD HAVE_VPMU UNPOPULATED_ALLOC BALLOON_MEMORY_HOTPLUG MCE_LOG; do
        scripts/config --set-val CONFIG_XEN_${xen_opt} n 2>/dev/null || true
    done
    
    scripts/config --set-val CONFIG_VMWARE_VMCI n
    scripts/config --set-val CONFIG_VMWARE_BALLOON n
    scripts/config --set-val CONFIG_VMWARE_PVSCSI n
    scripts/config --set-val CONFIG_VMWARE_VMCI_VSOCKETS n
    
    # 嵌入式 SoC
    echo "  - 移除嵌入式 SoC 驱动..." | tee -a "$LOG_FILE"
    for arch in ACTIONS SUNXI ALPINE APPLE BCM BERLIN BITMAIN EXYNOS SPARX5 K3 LG1K HISI KEEMBAY MEDIATEK MESON MVEBU NXP MA35 NPCM QCOM REALTEK RENESAS ROCKCHIP SEATTLE INTEL_SOCFPGA STM32 SYNQUACER TEGRA SPRD THUNDER THUNDER2 UNIPHIER VEXPRESS VISCONTI XGENE ZYNQMP; do
        scripts/config --set-val CONFIG_ARCH_${arch} n 2>/dev/null || true
    done
    
    # CAN 总线
    scripts/config --set-val CONFIG_CAN n
    
    # 媒体/摄像头/电视
    scripts/config --set-val CONFIG_MEDIA_SUPPORT n
    scripts/config --set-val CONFIG_MEDIA_CAMERA_SUPPORT n
    scripts/config --set-val CONFIG_MEDIA_ANALOG_TV_SUPPORT n
    scripts/config --set-val CONFIG_MEDIA_DIGITAL_TV_SUPPORT n
    scripts/config --set-val CONFIG_MEDIA_RADIO_SUPPORT n
    scripts/config --set-val CONFIG_MEDIA_SDR_SUPPORT n
    scripts/config --set-val CONFIG_MEDIA_PLATFORM_SUPPORT n
    scripts/config --set-val CONFIG_MEDIA_TEST_SUPPORT n
    scripts/config --set-val CONFIG_DVB_CORE n
    
    # 设置本地版本号
    echo "  - 设置本地版本号: $KERNEL_LOCALVERSION" | tee -a "$LOG_FILE"
    scripts/config --set-str CONFIG_LOCALVERSION "$KERNEL_LOCALVERSION"
    
    # 设置压缩格式为 zstd
    echo "  - 设置内核压缩为 zstd" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_KERNEL_ZSTD y
    scripts/config --set-val CONFIG_KERNEL_GZIP n
    scripts/config --set-val CONFIG_KERNEL_BZIP2 n
    scripts/config --set-val CONFIG_KERNEL_LZMA n
    scripts/config --set-val CONFIG_KERNEL_XZ n
    scripts/config --set-val CONFIG_KERNEL_LZO n
    scripts/config --set-val CONFIG_KERNEL_LZ4 n
    
    # 接受新配置项默认值
    echo "[5/7] 更新配置..." | tee -a "$LOG_FILE"
    make olddefconfig >> "$LOG_FILE" 2>&1
    
    # 保存优化配置
    OPTIMIZED_CONFIG="$CONFIG_BACKUP_DIR/config-3080-optimized-$CONFIG_TIMESTAMP"
    cp .config "$OPTIMIZED_CONFIG"
    echo "  优化配置已保存到: $OPTIMIZED_CONFIG" | tee -a "$LOG_FILE"
fi

# 5. 编译内核
echo "[6/7] 编译内核 (使用 $JOBS 线程)..." | tee -a "$LOG_FILE"
if [ "$INCREMENTAL" = true ]; then
    echo "    增量编译模式..." | tee -a "$LOG_FILE"
else
    echo "    完整编译，预计 15-30 分钟 (6核 Ryzen)..." | tee -a "$LOG_FILE"
fi

make -j$JOBS 2>&1 | tee -a "$LOG_FILE"

# 6. 安装模块 (可选，WSL2 内有用)
echo "[7/7] 安装内核模块..." | tee -a "$LOG_FILE"
sudo make modules_install >> "$LOG_FILE" 2>&1 || true

# 获取内核版本
KERNEL_RELEASE=$(make kernelrelease 2>/dev/null || echo "")

# 保存最终配置
if [ -n "$KERNEL_RELEASE" ]; then
    FINAL_CONFIG="$CONFIG_BACKUP_DIR/config-$KERNEL_RELEASE"
    cp .config "$FINAL_CONFIG"
    echo "  配置已保存到: $FINAL_CONFIG" | tee -a "$LOG_FILE"
fi

# 输出结果
echo "" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "内核编译完成 - $(date)" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
if [ -n "$KERNEL_RELEASE" ]; then
    echo "内核版本: $KERNEL_RELEASE" | tee -a "$LOG_FILE"
fi
echo "bzImage 路径: $SRC_DIR/arch/x86/boot/bzImage" | tee -a "$LOG_FILE"
echo "模块目录: /lib/modules/$KERNEL_RELEASE" | tee -a "$LOG_FILE"
echo "配置文件: $FINAL_CONFIG" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo ""
echo "【WSL2 使用方法】" | tee -a "$LOG_FILE"
echo "1. 复制内核到 Windows:" | tee -a "$LOG_FILE"
echo "   cp arch/x86/boot/bzImage /mnt/c/Users/Administrator/wsl2-kernel" | tee -a "$LOG_FILE"
echo ""
echo "2. 编辑 Windows 用户目录下的 .wslconfig:" | tee -a "$LOG_FILE"
echo "   [wsl2]" | tee -a "$LOG_FILE"
echo "   kernel=C:\\Users\\Administrator\\wsl2-kernel" | tee -a "$LOG_FILE"
echo ""
echo "3. 重启 WSL2:" | tee -a "$LOG_FILE"
echo "   wsl --shutdown" | tee -a "$LOG_FILE"
echo ""
echo "4. 验证新内核:" | tee -a "$LOG_FILE"
echo "   uname -r" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo ""
echo "增量编译提示:" | tee -a "$LOG_FILE"
echo "  - 再次运行此脚本会自动检测已有编译产物" | tee -a "$LOG_FILE"
echo "  - 使用 --rebuild 强制完整重新编译" | tee -a "$LOG_FILE"
echo "  - 使用 --reconfig 重新配置内核选项" | tee -a "$LOG_FILE"
echo "  - 所有配置保存在: $CONFIG_BACKUP_DIR/" | tee -a "$LOG_FILE"
