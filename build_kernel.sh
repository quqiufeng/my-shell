#!/bin/bash
#
# =============================================================================
# Linux 内核源码编译安装脚本
# =============================================================================
#
# 本脚本记录了一次成功的从源码编译内核并加载的全过程，供下次重新编译参考。
#
# 【硬件环境】
#   - CPU: Intel Core i5-2400 (Sandy Bridge)
#   - 显卡: Intel HD Graphics 2000 (集成显卡)
#   - 存储: Samsung 128GB NVMe SSD
#   - 内存: 12GB DDR3
#   - 网络: Realtek RTL8111/8168 PCI-E 千兆网卡 (有线)
#   - 系统: Ubuntu 24.04 LTS (Noble Numbat)
#   - 内核: 6.8.0-117-generic (原始)
#
# 【编译目标】
#   - 源码: linux-6.8.12.tar.xz
#   - 版本: 6.8.12-custom-$(date +%Y%m%d)
#   - 位置: /opt/linux/src/linux-6.8.12/
#
# 【完整编译流程记录】
#
# 步骤1: 下载并解压内核源码
#   wget -c https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.8.12.tar.xz
#   sudo tar -xf linux-6.8.12.tar.xz -C /opt/linux/src/
#   sudo chown -R $(id -un):$(id -gn) /opt/linux/src/linux-6.8.12
#
# 步骤2: 安装编译依赖（必须预先安装，nohup后台运行sudo会卡住）
#   sudo apt install -y build-essential libncurses-dev bison flex \
#       libssl-dev libelf-dev bc dwarves
#
# 步骤3: 修复权限问题（sudo chown）
#   sudo chown -R $(id -un):$(id -gn) /opt/linux/src/linux-6.8.12
#
# 步骤4: 修复内核签名证书缺失问题
#   cd /opt/linux/src/linux-6.8.12
#   scripts/config --set-str CONFIG_SYSTEM_TRUSTED_KEYS ""
#   scripts/config --set-str CONFIG_SYSTEM_REVOCATION_KEYS ""
#   scripts/config --set-val CONFIG_MODULE_SIG_KEY ""
#   make olddefconfig
#
# 步骤5: 运行编译脚本（后台模式）
#   cd /opt/linux/src/linux-6.8.12
#   setsid bash ~/build_kernel.sh > /tmp/build_kernel_nohup.log 2>&1 < /dev/null &
#   echo $! > /tmp/build_kernel.pid
#
# 步骤6: 监控编译进度
#   tail -f /tmp/build_kernel_nohup.log
#   ls -lt /tmp/build_kernel_*.log
#
# 步骤7: 编译完成后检查安装
#   ls /boot/vmlinuz-*custom*
#   ls /lib/modules/*custom*/
#   uname -r  # 重启后确认
#
# 步骤8: 设置默认启动内核
#   sudo sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT="Advanced options for Ubuntu>Ubuntu, with Linux 6.8.12-custom-20260523"/' /etc/default/grub
#   sudo update-grub
#
# 步骤9: 重启验证
#   sudo reboot
#   uname -r  # 应显示 6.8.12-custom-20260523
#
# 【关键问题与解决方案】
#
# 问题1: nohup后台运行sudo需要密码
#   现象: "sudo: a terminal is required to read the password"
#   解决: 预先安装所有依赖，脚本中检测依赖并提示手动安装
#
# 问题2: 源码目录权限不足（cp: 无法创建普通文件 '.config'）
#   解决: sudo chown -R $(id -un):$(id -gn) /opt/linux/src/linux-6.8.12
#
# 问题3: 内核签名证书缺失导致编译失败
#   现象: "没有规则可制作目标 debian/canonical-certs.pem"
#   解决: 清除签名配置并重新生成配置
#   scripts/config --set-str CONFIG_SYSTEM_TRUSTED_KEYS ""
#   scripts/config --set-str CONFIG_SYSTEM_REVOCATION_KEYS ""
#   scripts/config --set-val CONFIG_MODULE_SIG_KEY ""
#   make olddefconfig
#
# 问题4: nohup会话终止导致编译中断
#   解决: 使用 setsid 启动独立会话，确保脱离终端后仍能继续
#   setsid bash ~/build_kernel.sh > /tmp/build_kernel_nohup.log 2>&1 < /dev/null &
#
# 【编译时间参考】
#   - 完整编译: 约 45-60 分钟 (4核 i5-2400)
#   - 增量编译: 约 5-15 分钟 (只编译变更部分)
#   - 安装阶段: 约 2-5 分钟
#
# 【编译优化项】
#   - 处理器架构: -march=sandybridge (Intel Sandy Bridge)
#   - 调度器: 桌面环境优化 (SCHED_MC=y, SCHED_SMT=n)
#   - 透明大页: 开启 (TRANSPARENT_HUGEPAGE=y)
#   - 显卡: 仅保留 Intel i915，禁用 AMD/NVIDIA/Virtio
#   - 存储: NVMe + SATA AHCI，禁用 SCSI/RAID
#   - 文件系统: ext4, btrfs, f2fs, ntfs3, exfat
#   - 网络: 仅保留 Intel e1000e, Realtek r8169, Intel igb
#   - 移除: KVM/Xen/VMware/Hyper-V 虚拟化
#   - 移除: Infiniband, FireWire, Thunderbolt, PCMCIA
#   - 移除: 蓝牙, NFC, Wi-Fi, 红外, CEC, TPM
#   - 移除: 大量嵌入式 SoC 驱动
#   - 压缩: zstd (KERNEL_ZSTD=y)
#
# 【安装位置】
#   - 内核镜像: /boot/vmlinuz-6.8.12-custom-*
#   - 配置文件: /boot/config-6.8.12-custom-*
#   - 模块目录: /lib/modules/6.8.12-custom-*/
#   - GRUB配置: /etc/default/grub
#
# 【备份】
#   - 源码备份: /opt/linux/backup/linux-6.8.12-custom-YYYYMMDD_HHMM/
#   - 配置备份: ~/.config/kernel-builds/config-*
#
# 【使用建议】
#   - 首次编译: ./build_kernel.sh --rebuild
#   - 修改配置后: ./build_kernel.sh --reconfig
#   - 日常更新: ./build_kernel.sh (增量编译)
#
# 【当前成功运行中的内核配置】
#
#   成功编译并加载的内核配置：
#   - 文件: config-6.8.12-custom-20260523
#   - 位置: /boot/config-6.8.12-custom-20260523
#   - 副本: ~/my-shell/config-6.8.12-custom-20260523
#
#   验证当前内核：
#     uname -r
#     # 输出: 6.8.12-custom-20260523
#
#   此配置文件是增量编译的基础，已包含所有针对本机硬件的优化设置。
#
# 【继续精简驱动并增量编译】
#
# 如果需要进一步精简驱动（例如发现系统更快），可以增量编译，
# 不需要从零开始重新编译。
#
# 前提：源码目录 /opt/linux/src/linux-6.8.12/ 中已有 .config 和编译产物
#
# 操作步骤：
#
# 步骤1: 进入源码目录
#   cd /opt/linux/src/linux-6.8.12
#
# 步骤2: 关闭不需要的驱动（示例）
#   # 关闭蓝牙（台式机无蓝牙设备）
#   scripts/config --set-val CONFIG_BT n
#   scripts/config --set-val CONFIG_BT_BREDR n
#   scripts/config --set-val CONFIG_BT_LE n
#   scripts/config --set-val CONFIG_BT_INTEL n
#   scripts/config --set-val CONFIG_BT_HCIBTUSB n
#   scripts/config --set-val CONFIG_BT_HCIUART n
#
#   # 关闭 NFC
#   scripts/config --set-val CONFIG_NFC n
#
#   # 关闭 Wi-Fi（台式机只有有线网卡）
#   scripts/config --set-val CONFIG_WLAN n
#   scripts/config --set-val CONFIG_CFG80211 n
#   scripts/config --set-val CONFIG_MAC80211 n
#   scripts/config --set-val CONFIG_IWLWIFI n
#   scripts/config --set-val CONFIG_IWLDVM n
#   scripts/config --set-val CONFIG_IWLMVM n
#
#   # 关闭红外
#   scripts/config --set-val CONFIG_RC_CORE n
#   scripts/config --set-val CONFIG_LIRC n
#
#   # 关闭 CEC（HDMI 设备控制）
#   scripts/config --set-val CONFIG_CEC_CORE n
#
#   # 关闭 TPM
#   scripts/config --set-val CONFIG_TCG_TPM n
#
#   # 关闭 Virtio（虚拟机用的，物理机不需要）
#   scripts/config --set-val CONFIG_VIRTIO_BLK n
#   scripts/config --set-val CONFIG_VIRTIO_NET n
#   scripts/config --set-val CONFIG_VIRTIO_PCI n
#   scripts/config --set-val CONFIG_VHOST_NET n
#
#   # 关闭 PCMCIA（笔记本用的）
#   scripts/config --set-val CONFIG_PCMCIA n
#
#   # 关闭古老网络协议
#   scripts/config --set-val CONFIG_TIPC n
#   scripts/config --set-val CONFIG_DECNET n
#   scripts/config --set-val CONFIG_IPX n
#   scripts/config --set-val CONFIG_ATALK n
#
#   # 关闭 9P 文件系统
#   scripts/config --set-val CONFIG_9P_FS n
#   scripts/config --set-val CONFIG_NET_9P n
#
# 步骤3: 更新配置（自动接受新选项默认值）
#   make olddefconfig
#
# 步骤4: 增量编译（只编译变化部分，5-15分钟）
#   make -j$(nproc)
#
# 步骤5: 安装模块
#   sudo make modules_install
#
# 步骤6: 安装内核并更新 GRUB
#   sudo make install
#   sudo update-grub
#
# 步骤7: 设置新内核为默认启动
#   sudo sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT="Advanced options for Ubuntu>Ubuntu, with Linux 6.8.12-custom-$(date +%Y%m%d)"/' /etc/default/grub
#   sudo update-grub
#
# 步骤8: 重启验证
#   sudo reboot
#   uname -r
#
# 【查看哪些驱动可以移除】
#
# 1. 查看当前启用的驱动：
#   grep "^CONFIG_.*=y" /opt/linux/src/linux-6.8.12/.config | wc -l
#   # 成功运行时约 2698 个，精简后会更少
#
# 2. 查看当前硬件实际使用的驱动：
#   lspci -k | grep "Kernel driver"
#   lsusb
#
# 3. 查看已加载的模块：
#   lsmod | sort
#
# 4. 对比配置和实际硬件，关闭未使用的驱动。
#
# 【注意事项】
#   - 增量编译不需要删除编译产物，make 会自动检测变更
#   - 如果修改了核心选项（如处理器架构），可能需要大范围重编
#   - 关闭驱动前建议确认硬件确实不需要（用 lspci / lsusb 确认）
#   - 如果不确定某个驱动是否需要，可以保留，后续再精简
#   - 每次修改后建议备份 .config 文件：
#       cp .config ~/my-shell/config-backup-$(date +%Y%m%d_%H%M%S)
#
# =============================================================================


set -e

SRC_DIR="/opt/linux/src/linux-6.8.12"
LOG_FILE="/tmp/build_kernel_$(date +%Y%m%d_%H%M%S).log"
JOBS=$(nproc)
KERNEL_LOCALVERSION="-custom-$(date +%Y%m%d)"
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

# 1. 安装编译依赖（如果缺少）
# 注意：如果后台运行(nohup)，sudo 需要密码管道或预先安装依赖
echo "[1/9] 检查编译依赖..." | tee -a "$LOG_FILE"
MISSING_DEPS=""
for pkg in build-essential libncurses-dev bison flex libssl-dev libelf-dev bc dwarves; do
    # 宽松匹配：包名可能带 :amd64 后缀
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
    make clean >> "$LOG_FILE" 2>&1 || true
    make mrproper >> "$LOG_FILE" 2>&1 || true
    INCREMENTAL=false
fi

# 3. 配置内核（使用标准配置保存机制）
echo "[3/9] 配置内核选项..." | tee -a "$LOG_FILE"

mkdir -p "$CONFIG_BACKUP_DIR"
CONFIG_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CURRENT_CONFIG="$CONFIG_BACKUP_DIR/config-$(uname -r)-$CONFIG_TIMESTAMP"

if [ "$INCREMENTAL" = true ] && [ "$FORCE_RECONFIGURE" = false ]; then
    echo "  增量模式: 复用已有的 .config" | tee -a "$LOG_FILE"
    echo "  当前配置备份: $CURRENT_CONFIG" | tee -a "$LOG_FILE"
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
    
    # 备份原始配置
    cp .config "$CURRENT_CONFIG"
    echo "  原始配置已备份到: $CURRENT_CONFIG" | tee -a "$LOG_FILE"
    
    # 4. 根据本机硬件优化内核配置
    echo "[4/9] 根据本机硬件优化内核配置..." | tee -a "$LOG_FILE"
    
    # 处理器优化: Intel Sandy Bridge (Core i5-2400)
    echo "  - 设置处理器为 Intel Sandy Bridge" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_MCORE2 n
    scripts/config --set-val CONFIG_MATOM n
    scripts/config --set-val CONFIG_GENERIC_CPU n
    scripts/config --set-val CONFIG_MNATIVE_INTEL n
    scripts/config --set-val CONFIG_MNATIVE_AMD n
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
    scripts/config --set-val CONFIG_MZEN2 n
    scripts/config --set-val CONFIG_MZEN3 n
    scripts/config --set-val CONFIG_MZEN4 n
    scripts/config --set-val CONFIG_MNEHALEM n
    scripts/config --set-val CONFIG_MWESTMERE n
    scripts/config --set-val CONFIG_MSILVERMONT n
    scripts/config --set-val CONFIG_MGOLDMONT n
    scripts/config --set-val CONFIG_MGOLDMONTPLUS n
    scripts/config --set-val CONFIG_MSANDYBRIDGE y
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
    
    # CPU 核心数: 4核4线程
    echo "  - 优化调度器为桌面环境" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_SCHED_MC y
    scripts/config --set-val CONFIG_SCHED_SMT n
    
    # 内存: 12GB，开启大页和透明大页
    echo "  - 开启透明大页" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_TRANSPARENT_HUGEPAGE y
    scripts/config --set-val CONFIG_TRANSPARENT_HUGEPAGE_MADVISE y
    
    # 显卡: Intel HD Graphics 2000 (Sandy Bridge GT1)
    echo "  - 配置 Intel i915 显卡驱动" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_DRM_I915 y
    scripts/config --set-val CONFIG_DRM_I915_GVT n
    scripts/config --set-val CONFIG_DRM_AMDGPU n
    scripts/config --set-val CONFIG_DRM_RADEON n
    scripts/config --set-val CONFIG_DRM_NOUVEAU n
    scripts/config --set-val CONFIG_DRM_VIRTIO_GPU n
    scripts/config --set-val CONFIG_DRM_QXL n
    scripts/config --set-val CONFIG_DRM_VGEM n
    scripts/config --set-val CONFIG_DRM_VKMS n
    scripts/config --set-val CONFIG_DRM_UDL n
    scripts/config --set-val CONFIG_DRM_AST n
    scripts/config --set-val CONFIG_DRM_MGAG200 n
    
    # 存储: NVMe SSD
    echo "  - 配置 NVMe SSD 支持" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_NVME_CORE y
    scripts/config --set-val CONFIG_BLK_DEV_NVME y
    scripts/config --set-val CONFIG_NVME_FABRICS n
    scripts/config --set-val CONFIG_NVME_RDMA n
    scripts/config --set-val CONFIG_NVME_FC n
    scripts/config --set-val CONFIG_NVME_TCP n
    scripts/config --set-val CONFIG_NVME_AUTH n
    scripts/config --set-val CONFIG_NVME_TARGET n
    
    # SATA/AHCI
    scripts/config --set-val CONFIG_SATA_AHCI y
    scripts/config --set-val CONFIG_SATA_NV y
    scripts/config --set-val CONFIG_SATA_SIL y
    scripts/config --set-val CONFIG_SATA_SIL24 y
    
    # 文件系统优化: SSD 友好
    echo "  - 优化文件系统配置" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_EXT4_FS y
    scripts/config --set-val CONFIG_BTRFS_FS y
    scripts/config --set-val CONFIG_XFS_FS n
    scripts/config --set-val CONFIG_F2FS_FS y
    scripts/config --set-val CONFIG_NTFS3_FS m
    scripts/config --set-val CONFIG_EXFAT_FS m
    
    # 网络: 通用以太网和 Wi-Fi
    echo "  - 配置网络驱动" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_E1000E y
    scripts/config --set-val CONFIG_R8169 y
    scripts/config --set-val CONFIG_IGB y
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
    scripts/config --set-val CONFIG_IGC n
    scripts/config --set-val CONFIG_JME n
    scripts/config --set-val CONFIG_LAN743X n
    scripts/config --set-val CONFIG_LPC_ENET n
    scripts/config --set-val CONFIG_MACB n
    
    # 禁用大量网卡供应商
    for vendor in 3COM ADAPTEC AGERE ALACRITECH ALTEON AMAZON AMD AQUANTIA ARC ATHEROS BROADCOM CADENCE CAVIUM CHELSIO CISCO CORTINA DEC DLINK EMULEX EZCHIP FUJITSU GOOGLE HISILICON HUAWEI LITEX MARVELL MELLANOX MICREL MICROCHIP MICROSEMI MICROSOFT MYRI NI NATSEMI NETERION NETRONOME NVIDIA OKI PACKET_ENGINES PENSANDO QLOGIC QUALCOMM RDC RENESAS ROCKER SAMSUNG SEEQ SOLARFLARE SILAN SIS SMSC SOCIONEXT STMICRO SUN SYNOPSYS TEHUTI TI VERTEXCOM VIA WANGXUN XILINX; do
        scripts/config --set-val CONFIG_NET_VENDOR_${vendor} n 2>/dev/null || true
    done
    
    # Wi-Fi: Intel 常见型号
    echo "  - 保留 Intel Wi-Fi 驱动" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_IWLWIFI y
    scripts/config --set-val CONFIG_IWLDVM y
    scripts/config --set-val CONFIG_IWLMVM y
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
    
    # 蓝牙
    echo "  - 配置蓝牙支持" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_BT y
    scripts/config --set-val CONFIG_BT_BREDR y
    scripts/config --set-val CONFIG_BT_LE y
    scripts/config --set-val CONFIG_BT_INTEL y
    scripts/config --set-val CONFIG_BT_HCIBTUSB y
    
    # 声音: Intel HD Audio
    echo "  - 配置 Intel HD Audio" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_SND_HDA_INTEL y
    scripts/config --set-val CONFIG_SND_HDA_CODEC_REALTEK y
    scripts/config --set-val CONFIG_SND_HDA_CODEC_ANALOG n
    scripts/config --set-val CONFIG_SND_HDA_CODEC_SIGMATEL n
    scripts/config --set-val CONFIG_SND_HDA_CODEC_VIA n
    scripts/config --set-val CONFIG_SND_HDA_CODEC_HDMI y
    scripts/config --set-val CONFIG_SND_HDA_CODEC_CIRRUS n
    scripts/config --set-val CONFIG_SND_HDA_CODEC_CONEXANT n
    scripts/config --set-val CONFIG_SND_HDA_CODEC_CA0110 n
    scripts/config --set-val CONFIG_SND_HDA_CODEC_CA0132 n
    scripts/config --set-val CONFIG_SND_HDA_CODEC_CMEDIA n
    scripts/config --set-val CONFIG_SND_HDA_CODEC_SI3054 n
    
    # 移除大量不需要的驱动以加速编译
    echo "  - 移除不需要的服务器/嵌入式驱动..." | tee -a "$LOG_FILE"
    
    # 移除 Infiniband
    scripts/config --set-val CONFIG_INFINIBAND n
    
    # 移除光纤通道
    scripts/config --set-val CONFIG_SCSI_FC_ATTRS n
    scripts/config --set-val CONFIG_SCSI_SPI_ATTRS n
    scripts/config --set-val CONFIG_SCSI_SAS_ATTRS n
    scripts/config --set-val CONFIG_SCSI_SAS_LIBSAS n
    
    # 移除 RAID
    scripts/config --set-val CONFIG_MD_RAID0 n
    scripts/config --set-val CONFIG_MD_RAID1 n
    scripts/config --set-val CONFIG_MD_RAID10 n
    scripts/config --set-val CONFIG_MD_RAID456 n
    scripts/config --set-val CONFIG_MD_MULTIPATH n
    scripts/config --set-val CONFIG_MD_FAULTY n
    scripts/config --set-val CONFIG_BLK_DEV_DM_RAID n
    scripts/config --set-val CONFIG_DM_MULTIPATH n
    
    # 移除大量 SCSI 控制器
    scripts/config --set-val CONFIG_SCSI_LOWLEVEL n
    scripts/config --set-val CONFIG_SCSI_LOWLEVEL_PCMCIA n
    for scsi_drv in BFA_FC CHELSIO_FCOE ESAS2R HPSA IPR IBMVSCSI IBMVFC MPT2SAS MPT3SAS SMARTPQI UFSHCD VIRTIO CXGB3_ISCSI CXGB4_ISCSI BNX2_ISCSI BNX2X_FCOE BE2ISCSI PM8001 QLOGIC_1280 QLA_FC QLA_ISCSI LPFC DC395x AM53C974 WD719X DEBUG PMCRAID FDOMAIN_PCI; do
        scripts/config --set-val CONFIG_SCSI_${scsi_drv} n 2>/dev/null || true
    done
    
    # 移除 KVM/虚拟化
    scripts/config --set-val CONFIG_KVM n
    scripts/config --set-val CONFIG_KVM_INTEL n
    scripts/config --set-val CONFIG_KVM_AMD n
    scripts/config --set-val CONFIG_VHOST_NET n
    scripts/config --set-val CONFIG_VHOST_VSOCK n
    scripts/config --set-val CONFIG_VHOST_CROSS_ENDIAN_LEGACY n
    
    # 移除 Xen/VMware/Hyper-V
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
    
    # 移除大量嵌入式/SoC 驱动
    echo "  - 移除嵌入式 SoC 驱动..." | tee -a "$LOG_FILE"
    for arch in ACTIONS SUNXI ALPINE APPLE BCM BERLIN BITMAIN EXYNOS SPARX5 K3 LG1K HISI KEEMBAY MEDIATEK MESON MVEBU NXP MA35 NPCM QCOM REALTEK RENESAS ROCKCHIP SEATTLE INTEL_SOCFPGA STM32 SYNQUACER TEGRA SPRD THUNDER THUNDER2 UNIPHIER VEXPRESS VISCONTI XGENE ZYNQMP; do
        scripts/config --set-val CONFIG_ARCH_${arch} n 2>/dev/null || true
    done
    
    # 移除 CAN 总线
    scripts/config --set-val CONFIG_CAN n
    
    # 移除大量的媒体/摄像头/电视驱动
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
    
    # 设置压缩格式为 zstd（快速解压）
    echo "  - 设置内核压缩为 zstd" | tee -a "$LOG_FILE"
    scripts/config --set-val CONFIG_KERNEL_ZSTD y
    scripts/config --set-val CONFIG_KERNEL_GZIP n
    scripts/config --set-val CONFIG_KERNEL_BZIP2 n
    scripts/config --set-val CONFIG_KERNEL_LZMA n
    scripts/config --set-val CONFIG_KERNEL_XZ n
    scripts/config --set-val CONFIG_KERNEL_LZO n
    scripts/config --set-val CONFIG_KERNEL_LZ4 n
    
    # 接受新配置项的默认值
    echo "[5/9] 更新配置（自动接受新选项默认值）..." | tee -a "$LOG_FILE"
    make olddefconfig >> "$LOG_FILE" 2>&1
    
    # 保存优化后的配置到标准位置
    OPTIMIZED_CONFIG="$CONFIG_BACKUP_DIR/config-optimized-$CONFIG_TIMESTAMP"
    cp .config "$OPTIMIZED_CONFIG"
    echo "  优化后的配置已保存到: $OPTIMIZED_CONFIG" | tee -a "$LOG_FILE"
fi

# 5. 编译内核（增量编译）
if [ "$INCREMENTAL" = true ]; then
    echo "[6/9] 增量编译内核（只编译变化部分，使用 $JOBS 线程）..." | tee -a "$LOG_FILE"
    echo "    首次编译可能需要 30-60 分钟，增量编译会快很多..." | tee -a "$LOG_FILE"
else
    echo "[6/9] 完整编译内核（使用 $JOBS 线程）..." | tee -a "$LOG_FILE"
    echo "    这可能需要 30-60 分钟，请耐心等待..." | tee -a "$LOG_FILE"
fi

make -j$JOBS >> "$LOG_FILE" 2>&1

# 6. 安装内核模块
echo "[7/9] 安装内核模块..." | tee -a "$LOG_FILE"
sudo make modules_install >> "$LOG_FILE" 2>&1

# 7. 安装内核镜像
echo "[8/9] 安装内核镜像并更新 GRUB..." | tee -a "$LOG_FILE"
sudo make install >> "$LOG_FILE" 2>&1

# 保存最终配置到标准位置 (/boot/config-*)
KERNEL_RELEASE=$(make kernelrelease 2>/dev/null || echo "")
if [ -n "$KERNEL_RELEASE" ]; then
    FINAL_CONFIG="/boot/config-$KERNEL_RELEASE"
    echo "[9/9] 保存编译配置到标准位置..." | tee -a "$LOG_FILE"
    sudo cp .config "$FINAL_CONFIG"
    echo "  配置已保存到: $FINAL_CONFIG" | tee -a "$LOG_FILE"
    
    # 同时保存到用户配置目录
    USER_CONFIG="$CONFIG_BACKUP_DIR/config-$KERNEL_RELEASE"
    cp .config "$USER_CONFIG"
    echo "  配置已备份到: $USER_CONFIG" | tee -a "$LOG_FILE"
fi

# 更新 GRUB
echo "更新 GRUB 配置..." | tee -a "$LOG_FILE"
sudo update-grub >> "$LOG_FILE" 2>&1

# 设置原内核为默认启动
echo "设置原内核为默认启动..." | tee -a "$LOG_FILE"
DEFAULT_KERNEL=$(grep -oP 'menuentry.*?\Klinux-[0-9.-]+-generic' /boot/grub/grub.cfg | head -1)
if [ -n "$DEFAULT_KERNEL" ]; then
    echo "原默认内核: $DEFAULT_KERNEL" | tee -a "$LOG_FILE"
    sudo sed -i "s/^GRUB_DEFAULT=.*/GRUB_DEFAULT=\"Advanced options for Ubuntu>Ubuntu, with Linux $(uname -r)\"/" /etc/default/grub
    sudo update-grub >> "$LOG_FILE" 2>&1
    echo "已设置原内核 $(uname -r) 为默认启动项" | tee -a "$LOG_FILE"
else
    echo "警告: 无法确定原内核，GRUB 默认顺序保持不变" | tee -a "$LOG_FILE"
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
echo "默认启动: 原内核 $(uname -r)" | tee -a "$LOG_FILE"
echo "要切换到新内核请在 GRUB 菜单中选择" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo ""
echo "增量编译提示:"
echo "  - 再次运行此脚本会自动检测已有编译产物，只编译变化部分"
echo "  - 使用 ./build_kernel.sh --rebuild 强制完整重新编译"
echo "  - 使用 ./build_kernel.sh --reconfig 重新配置内核选项"
echo "  - 所有内核配置保存在: $CONFIG_BACKUP_DIR/"
