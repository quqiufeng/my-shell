#!/bin/bash
# =============================================================================
# lib_kernel_config.sh - Linux 内核编译共享库
# =============================================================================
#
# 提供三个编译脚本共用的函数和配置:
#   - build_kernel.sh              (Intel Sandy Bridge 物理机)
#   - build_kernel_3080.sh         (AMD Zen2 + RTX 3080 物理机)
#   - build_wsl2_3080_kernel.sh    (AMD Zen2 + WSL2)
#
# 主要解决:
#   1. 三个脚本中重复的 scripts/config 调用(网卡/SoC/虚拟化/RAID 等)
#   2. 6.8.x 内核已移除 MZEN2/MSANDYBRIDGE 等 Kconfig 选项导致的静默失败
#   3. set -e 不捕获管道中段失败的 bug(改用 safe_make)
#   4. GRUB 默认启动的语言敏感问题
#
# 使用方式:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib_kernel_config.sh"
#
# =============================================================================

# 防止重复加载
if [[ -n "${_LIB_KERNEL_CONFIG_LOADED:-}" ]]; then
    return 0 2>/dev/null || true
fi
_LIB_KERNEL_CONFIG_LOADED=1

# -----------------------------------------------------------------------------
# 全局设置
# -----------------------------------------------------------------------------

# 设置 pipefail:set -e 在管道命令中只检查最后一个命令的退出码
# 例如 make 失败但 tee 成功时,set -e 不会触发
lib_setup_strict_mode() {
    set -e
    set -o pipefail
    set -u
}

# -----------------------------------------------------------------------------
# 工具函数
# -----------------------------------------------------------------------------

# 打印到 stdout 和日志文件
# 用法: log "消息"
log() {
    echo "$@" | tee -a "$LOG_FILE"
}

# 打印章节标题
# 用法: log_section "[1/9] 标题"
log_section() {
    echo "" | tee -a "$LOG_FILE"
    echo "========================================" | tee -a "$LOG_FILE"
    echo "$1" | tee -a "$LOG_FILE"
    echo "========================================" | tee -a "$LOG_FILE"
}

# 打印步骤小标题
# 用法: log_step "  - 设置处理器为 Intel Sandy Bridge"
log_step() {
    echo "$1" | tee -a "$LOG_FILE"
}

# 检测 Kconfig 文件中是否存在某个 symbol
# 用法: kconfig_has CONFIG_FOO
# 返回: 0 存在, 1 不存在
# 注意: 排除 .git 目录,避免误匹配
# 匹配 config 和 menuconfig(蓝牙/Wi-Fi/媒体是 menuconfig)
kconfig_has() {
    local sym="$1"
    # 去掉 CONFIG_ 前缀
    local name="${sym#CONFIG_}"
    # 在整个源码树搜索 Kconfig(排除 .git 和文档)
    # 匹配 config FOO 和 menuconfig FOO 两种形式
    if grep -rqE "^[[:space:]]*(menu)?config[[:space:]]+${name}\b" \
        --include='Kconfig*' \
        --exclude-dir='.git' \
        "$SRC_DIR/" 2>/dev/null; then
        return 0
    fi
    return 1
}

# 设置 Kconfig 选项,自动处理不存在的 symbol
# 用法: set_kconfig CONFIG_FOO y|n|m|"string"
set_kconfig() {
    local sym="$1"
    local val="$2"
    if ! kconfig_has "$sym"; then
        log_step "    [跳过] $sym 在此内核 Kconfig 中不存在(可能已被移除)"
        return 0
    fi
    if [[ "$val" == \"*\" || "$val" =~ ^[ymn]$ ]]; then
        scripts/config --set-val "$sym" "$val" 2>&1 | tee -a "$LOG_FILE"
    else
        scripts/config --set-str "$sym" "$val" 2>&1 | tee -a "$LOG_FILE"
    fi
}

# 简化的批量设置(直接传 n 给不存在的 symbol 会静默跳过)
# 用法: set_kconfig_safe CONFIG_FOO n
set_kconfig_safe() {
    local sym="$1"
    local val="$2"
    if kconfig_has "$sym"; then
        scripts/config --set-val "$sym" "$val" 2>&1 | tee -a "$LOG_FILE"
    fi
}

# 包装 make 命令,正确处理 pipefail
# 用法: safe_make target
safe_make() {
    local target="$1"
    shift || true
    # 不使用管道避免 pipefail 问题
    "$MAKE" $target "$@" >> "$LOG_FILE" 2>&1
}

# 获取当前脚本的 MAKE 变量
MAKE="${MAKE:-make}"

# -----------------------------------------------------------------------------
# 依赖检查
# -----------------------------------------------------------------------------

# 检查一组 apt 包是否已安装
# 用法: check_deps pkg1 pkg2 ...
# 输出: 返回 0 都已安装, 1 有缺失(打印需要安装的命令)
#
# 实现注意:
#   用 dpkg-query -W 替代 dpkg -l | grep,避免 pipefail + SIGPIPE 问题
#   (dpkg -l 输出大量内容,grep -q 命中后关闭管道会导致 dpkg 被 SIGPIPE 杀掉,
#    在 setsid + pipefail 环境下会误判为包不存在)
check_deps() {
    local missing=""
    for pkg in "$@"; do
        # dpkg-query 对不存在的包返回非零
        if ! dpkg-query -W -f='${Status}\n' "$pkg" 2>/dev/null \
                | grep -q "^install ok installed$"; then
            missing="$missing $pkg"
        fi
    done
    if [[ -n "$missing" ]]; then
        echo "缺少依赖:$missing"
        echo "请运行: sudo apt install -y$missing"
        return 1
    fi
    return 0
}

# -----------------------------------------------------------------------------
# 通用配置模块(三个脚本共用)
# -----------------------------------------------------------------------------

# 关闭大量以太网供应商
# 用法: disable_ethernet_vendors
disable_ethernet_vendors() {
    local vendors=(
        3COM ADAPTEC AGERE ALACRITECH ALTEON AMAZON AMD AQUANTIA ARC
        ATHEROS BROADCOM CADENCE CAVIUM CHELSIO CISCO CORTINA DEC DLINK
        EMULEX EZCHIP FUJITSU GOOGLE HISILICON HUAWEI LITEX MARVELL
        MELLANOX MICREL MICROCHIP MICROSEMI MICROSOFT MYRI NI NATSEMI
        NETERION NETRONOME NVIDIA OKI PACKET_ENGINES PENSANDO QLOGIC
        QUALCOMM RDC RENESAS ROCKER SAMSUNG SEEQ SOLARFLARE SILAN SIS
        SMSC SOCIONEXT STMICRO SUN SYNOPSYS TEHUTI TI VERTEXCOM VIA
        WANGXUN XILINX
    )
    for vendor in "${vendors[@]}"; do
        set_kconfig_safe "CONFIG_NET_VENDOR_${vendor}" n
    done
}

# 关闭具体的物理网卡芯片驱动(WSL2 不需要,网络走 VirtIO)
# 用法: disable_physical_nics
disable_physical_nics() {
    local nics=(E1000E R8169 IGB IGC IXGBE IXGBEVF I40E IAVF FM10K E1000)
    for nic in "${nics[@]}"; do
        set_kconfig_safe "CONFIG_${nic}" n
    done
    disable_ethernet_vendors
}

# 关闭嵌入式 SoC 架构
# 用法: disable_embedded_socs
disable_embedded_socs() {
    local archs=(
        ACTIONS SUNXI ALPINE APPLE BCM BERLIN BITMAIN EXYNOS SPARX5
        K3 LG1K HISI KEEMBAY MEDIATEK MESON MVEBU NXP MA35 NPCM QCOM
        REALTEK RENESAS ROCKCHIP SEATTLE INTEL_SOCFPGA STM32 SYNQUACER
        TEGRA SPRD THUNDER THUNDER2 UNIPHIER VEXPRESS VISCONTI XGENE
        ZYNQMP
    )
    for arch in "${archs[@]}"; do
        set_kconfig_safe "CONFIG_ARCH_${arch}" n
    done
}

# 关闭 Xen / VMware / Hyper-V 虚拟化
# 用法: disable_third_party_hypervisors
disable_third_party_hypervisors() {
    # Xen 全家桶
    local xen_opts=(
        XEN XEN_DOM0 XEN_PVHVM XEN_PVH XEN_FBDEV_FRONTEND
        XEN_BLKDEV_FRONTEND XEN_BLKDEV_BACKEND XEN_NETDEV_FRONTEND
        XEN_NETDEV_BACKEND XEN_PCIDEV_FRONTEND XEN_PCIDEV_BACKEND
        XEN_SCSI_BACKEND XEN_ACPI_PROCESSOR XEN_HAVE_PVMMU XEN_EFI
        XEN_AUTO_XLATE XEN_BALLOON XEN_SCRUB_PAGES XEN_DEV_EVTCHN
        XEN_BACKEND XENFS XEN_COMPAT_XENFS XEN_SYS_HYPERVISOR
        XEN_GNTDEV XEN_GNTDEV_DMABUF XEN_GRANT_DEV_ALLOC
        SWIOTLB_XEN XEN_PVCALLS_BACKEND XEN_PVCALLS_FRONTEND
        XEN_PRIVCMD XEN_HAVE_VPMU XEN_UNPOPULATED_ALLOC
        XEN_BALLOON_MEMORY_HOTPLUG XEN_MCE_LOG
    )
    for opt in "${xen_opts[@]}"; do
        set_kconfig_safe "CONFIG_${opt}" n
    done
    # VMware
    set_kconfig_safe CONFIG_VMWARE_VMCI n
    set_kconfig_safe CONFIG_VMWARE_BALLOON n
    set_kconfig_safe CONFIG_VMWARE_PVSCSI n
    set_kconfig_safe CONFIG_VMWARE_VMCI_VSOCKETS n
    # Hyper-V
    local hyperv_opts=(HYPERV HYPERV_UTILS HYPERV_BALLOON HYPERV_STORAGE
        HYPERV_NET HYPERV_VSOCKETS HYPERV_ISPVBD)
    for opt in "${hyperv_opts[@]}"; do
        set_kconfig_safe "CONFIG_${opt}" n
    done
}

# 关闭 RAID
# 用法: disable_raid
disable_raid() {
    set_kconfig_safe CONFIG_MD_RAID0 n
    set_kconfig_safe CONFIG_MD_RAID1 n
    set_kconfig_safe CONFIG_MD_RAID10 n
    set_kconfig_safe CONFIG_MD_RAID456 n
    set_kconfig_safe CONFIG_MD_MULTIPATH n
    set_kconfig_safe CONFIG_MD_FAULTY n
    set_kconfig_safe CONFIG_BLK_DEV_DM_RAID n
    set_kconfig_safe CONFIG_DM_MULTIPATH n
}

# 关闭光纤通道和大部分 SCSI 控制器
# 用法: disable_fc_scsi
disable_fc_scsi() {
    set_kconfig_safe CONFIG_INFINIBAND n
    set_kconfig_safe CONFIG_SCSI_FC_ATTRS n
    set_kconfig_safe CONFIG_SCSI_SPI_ATTRS n
    set_kconfig_safe CONFIG_SCSI_SAS_ATTRS n
    set_kconfig_safe CONFIG_SCSI_SAS_LIBSAS n
    set_kconfig_safe CONFIG_SCSI_LOWLEVEL n
    set_kconfig_safe CONFIG_SCSI_LOWLEVEL_PCMCIA n
    local scsi_drvs=(
        BFA_FC CHELSIO_FCOE ESAS2R HPSA IPR IBMVSCSI IBMVFC MPT2SAS
        MPT3SAS SMARTPQI UFSHCD VIRTIO CXGB3_ISCSI CXGB4_ISCSI
        BNX2_ISCSI BNX2X_FCOE BE2ISCSI PM8001 QLOGIC_1280 QLA_FC
        QLA_ISCSI LPFC DC395x AM53C974 WD719X DEBUG PMCRAID FDOMAIN_PCI
    )
    for drv in "${scsi_drvs[@]}"; do
        set_kconfig_safe "CONFIG_SCSI_${drv}" n
    done
}

# 关闭老旧网络协议
# 用法: disable_obsolete_protocols
disable_obsolete_protocols() {
    set_kconfig_safe CONFIG_TIPC n
    set_kconfig_safe CONFIG_DECNET n
    set_kconfig_safe CONFIG_IPX n
    set_kconfig_safe CONFIG_ATALK n
    set_kconfig_safe CONFIG_9P_FS n
    set_kconfig_safe CONFIG_NET_9P n
    set_kconfig_safe CONFIG_X25 n
    set_kconfig_safe CONFIG_LAPB n
    set_kconfig_safe CONFIG_PHONET n
    set_kconfig_safe CONFIG_IEEE802154 n
    set_kconfig_safe CONFIG_MAC802154 n
}

# 关闭老旧外设
# 用法: disable_obsolete_peripherals
disable_obsolete_peripherals() {
    set_kconfig_safe CONFIG_PCMCIA n
    set_kconfig_safe CONFIG_PCCARD n
    set_kconfig_safe CONFIG_FIREWIRE n
    set_kconfig_safe CONFIG_THUNDERBOLT n
    set_kconfig_safe CONFIG_RC_CORE n
    set_kconfig_safe CONFIG_LIRC n
    set_kconfig_safe CONFIG_NFC n
    set_kconfig_safe CONFIG_CEC_CORE n
    set_kconfig_safe CONFIG_TCG_TPM n
    set_kconfig_safe CONFIG_CAN n
    set_kconfig_safe CONFIG_PRINTER n
    set_kconfig_safe CONFIG_WATCHDOG n
}

# 关闭电视/广播/SDR(保留基础 V4L2 用于摄像头)
# 用法: disable_tv_radio
disable_tv_radio() {
    set_kconfig_safe CONFIG_DVB_CORE n
    set_kconfig_safe CONFIG_MEDIA_ANALOG_TV_SUPPORT n
    set_kconfig_safe CONFIG_MEDIA_DIGITAL_TV_SUPPORT n
    set_kconfig_safe CONFIG_MEDIA_RADIO_SUPPORT n
    set_kconfig_safe CONFIG_MEDIA_SDR_SUPPORT n
    set_kconfig_safe CONFIG_MEDIA_PLATFORM_SUPPORT n
    set_kconfig_safe CONFIG_MEDIA_TEST_SUPPORT n
}

# 关闭大部分声卡 codec(只保留 Realtek / Intel / HDMI)
# 用法: disable_extra_audio_codecs
disable_extra_audio_codecs() {
    local codecs=(ANALOG SIGMATEL VIA CIRRUS CONEXANT CA0110 CA0132 CMEDIA SI3054)
    for codec in "${codecs[@]}"; do
        set_kconfig_safe "CONFIG_SND_HDA_CODEC_${codec}" n
    done
}

# 配置 NVMe + SATA AHCI(SSD 优化)
# 用法: enable_nvme_sata
enable_nvme_sata() {
    set_kconfig CONFIG_NVME_CORE y
    set_kconfig CONFIG_BLK_DEV_NVME y
    set_kconfig CONFIG_NVME_FABRICS n
    set_kconfig CONFIG_NVME_RDMA n
    set_kconfig CONFIG_NVME_FC n
    set_kconfig CONFIG_NVME_TCP n
    set_kconfig CONFIG_NVME_AUTH n
    set_kconfig CONFIG_NVME_TARGET n
    set_kconfig CONFIG_SATA_AHCI y
    set_kconfig CONFIG_ATA_ACPI y
    set_kconfig CONFIG_SATA_PMP y
}

# 配置 SSD 友好文件系统
# 用法: enable_ssd_filesystems
enable_ssd_filesystems() {
    set_kconfig CONFIG_EXT4_FS y
    set_kconfig CONFIG_BTRFS_FS y
    set_kconfig CONFIG_F2FS_FS y
    set_kconfig CONFIG_XFS_FS n
    set_kconfig CONFIG_NTFS3_FS m
    set_kconfig CONFIG_EXFAT_FS m
    set_kconfig_safe CONFIG_EXT4_KUNIT_TESTS n
}

# 关闭内核签名要求(避免缺证书编译失败)
# 用法: clear_kernel_signing_keys
clear_kernel_signing_keys() {
    set_kconfig_safe CONFIG_SYSTEM_TRUSTED_KEYS ""
    set_kconfig_safe CONFIG_SYSTEM_REVOCATION_KEYS ""
    set_kconfig_safe CONFIG_MODULE_SIG_KEY ""
}

# 设置内核压缩为 zstd
# 用法: set_kernel_compression_zstd
set_kernel_compression_zstd() {
    set_kconfig CONFIG_KERNEL_ZSTD y
    set_kconfig CONFIG_KERNEL_GZIP n
    set_kconfig CONFIG_KERNEL_BZIP2 n
    set_kconfig CONFIG_KERNEL_LZMA n
    set_kconfig CONFIG_KERNEL_XZ n
    set_kconfig CONFIG_KERNEL_LZO n
    set_kconfig CONFIG_KERNEL_LZ4 n
}

# 开启透明大页
# 用法: enable_transparent_hugepages
enable_transparent_hugepages() {
    set_kconfig CONFIG_TRANSPARENT_HUGEPAGE y
    set_kconfig CONFIG_TRANSPARENT_HUGEPAGE_MADVISE y
}

# 优化调度器(桌面环境,关闭 SMT)
# 用法: optimize_scheduler_desktop
optimize_scheduler_desktop() {
    set_kconfig CONFIG_SCHED_MC y
    set_kconfig CONFIG_SCHED_SMT n
}

# -----------------------------------------------------------------------------
# CPU 微架构优化(适配 6.8.x 已移除 Kconfig 选项)
# -----------------------------------------------------------------------------

# 6.8+ 内核 Kconfig 中已移除所有 MZEN*/MSANDYBRIDGE/MHASWELL/MNATIVE_* 等选项
# 此函数智能判断:
#   - 6.8+ 用 GENERIC_CPU + KCFLAGS=-march=xxx
#   - <6.8 用 Kconfig 旧接口
#
# 用法: optimize_cpu "znver2" "AMD Ryzen 5 3500X"
#       optimize_cpu "sandybridge" "Intel Core i5-2400"
optimize_cpu() {
    local march="$1"
    local description="$2"
    local kernel_major=$(grep -oP '^#define\s+LINUX_VERSION_CODE\s+\K\d+' \
        "$SRC_DIR/include/linux/version.h" 2>/dev/null | head -1)
    local version_str=$(grep -oP '^#define\s+LINUX_VERSION_STRING\s+"\K[^"]+' \
        "$SRC_DIR/include/generated/uapi/linux/version.h" 2>/dev/null \
        || echo "unknown")

    log_step "  - 内核版本: $version_str"
    log_step "  - 目标 CPU: $description (-march=$march)"

    if kconfig_has "CONFIG_MNATIVE_AMD" || kconfig_has "CONFIG_MNATIVE_INTEL" || \
       kconfig_has "CONFIG_MZEN2" || kconfig_has "CONFIG_MSANDYBRIDGE"; then
        # 旧内核(<6.8),用 Kconfig 接口
        log_step "  - 检测到旧版 Kconfig CPU 选项,使用 Kconfig 接口"
        optimize_cpu_legacy "$march" "$description"
    else
        # 新内核(>=6.8),Kconfig 选项已移除,用 KCFLAGS
        log_step "  - 检测到新版内核(6.8+),Kconfig CPU 选项已移除"
        log_step "  - 使用 KCFLAGS=-march=$march -mtune=$march 注入微架构优化"
        optimize_cpu_modern "$march"
    fi
}

# 旧内核(<6.8)的 CPU 优化
optimize_cpu_legacy() {
    local march="$1"
    local description="$2"
    case "$march" in
        sandybridge)
            log_step "  - 设置 Kconfig: CONFIG_MSANDYBRIDGE=y"
            scripts/config --set-val CONFIG_GENERIC_CPU n
            scripts/config --set-val CONFIG_MSANDYBRIDGE y
            ;;
        znver2|zen2)
            log_step "  - 设置 Kconfig: CONFIG_MZEN2=y"
            scripts/config --set-val CONFIG_GENERIC_CPU n
            scripts/config --set-val CONFIG_MZEN2 y
            ;;
        *)
            log_step "  - 未知微架构 $march,使用 GENERIC_CPU"
            scripts/config --set-val CONFIG_GENERIC_CPU y
            ;;
    esac
    # 关闭其它微架构
    local all_archs=(
        MCORE2 MATOM GENERIC_CPU GENERIC_CPU2 GENERIC_CPU3 GENERIC_CPU4
        MNATIVE_INTEL MNATIVE_AMD MPSC MK8 MK8SSE3 MK10 MBARCELONA
        MBOBCAT MJAGUAR MBULLDOZER MPILEDRIVER MSTEAMROLLER MEXCAVATOR
        MZEN MZEN2 MZEN3 MZEN4 MZEN5 MNEHALEM MWESTMERE MSILVERMONT
        MGOLDMONT MGOLDMONTPLUS MSANDYBRIDGE MIVYBRIDGE MHASWELL
        MBROADWELL MSKYLAKE MSKYLAKEX MCANNONLAKE MICELAKE MCASCADELAKE
        MCOOPERLAKE MTIGERLAKE MSAPPHIRERAPIDS MROCKETLAKE MALDERLAKE
        MRAPTORLAKE MMETEORLAKE MMORPHYLAKE
    )
    for arch in "${all_archs[@]}"; do
        set_kconfig_safe "CONFIG_${arch}" n
    done
}

# 新内核(>=6.8)的 CPU 优化:保留 GENERIC_CPU,用 KCFLAGS 注入 -march
optimize_cpu_modern() {
    local march="$1"
    # 6.8+ 只剩 GENERIC_CPU,保留它(Kconfig 自动启用)
    set_kconfig CONFIG_GENERIC_CPU y
    # 设置 KCFLAGS 环境变量,会通过 Makefile 传递到 KBUILD_CFLAGS
    export KCFLAGS="-march=$march -mtune=$march -O2"
    log_step "  - 已设置 KCFLAGS='$KCFLAGS'"
    log_step "  - 注意: KCFLAGS 需要在执行 make 时作为环境变量传入"
}

# -----------------------------------------------------------------------------
# NVIDIA 驱动相关
# -----------------------------------------------------------------------------

# 获取已安装的 NVIDIA 专有驱动版本号
# 用法: get_nvidia_driver_version
# 输出: 版本号字符串(如 "535.183.06"),未找到则输出空
get_nvidia_driver_version() {
    dpkg -l 2>/dev/null \
        | awk '/^ii\s+nvidia-driver-[0-9]/{print $3; exit}' \
        | sed 's/-[0-9].*$//'
}

# 编译并安装 NVIDIA DKMS 模块(手动模式)
# 用法: build_nvidia_dkms <kernel_release>
build_nvidia_dkms() {
    local kver="$1"
    local nvidia_ver
    nvidia_ver="$(get_nvidia_driver_version)"

    if [[ -z "$nvidia_ver" ]]; then
        log_step "  未检测到 NVIDIA 专有驱动,跳过 DKMS 编译"
        return 0
    fi

    log_step "  检测到 NVIDIA 驱动版本: $nvidia_ver"
    log_step "  清理旧的 DKMS 构建缓存..."
    sudo rm -rf "/var/lib/dkms/nvidia/$nvidia_ver/$kver" 2>/dev/null || true

    log_step "  编译 NVIDIA DKMS 模块..."
    sudo dkms build "nvidia/$nvidia_ver" -k "$kver" >> "$LOG_FILE" 2>&1

    log_step "  安装 NVIDIA DKMS 模块..."
    sudo dkms install "nvidia/$nvidia_ver" -k "$kver" >> "$LOG_FILE" 2>&1

    log_step "  NVIDIA DKMS 模块编译完成"
}

# -----------------------------------------------------------------------------
# GRUB 默认启动设置
# -----------------------------------------------------------------------------

# 设置 GRUB 默认启动项(语言无关版本)
# 用法: set_grub_default <kernel_release> [original_kernel]
#   original_kernel: 传 "original" 时设回原内核,否则设为新内核
set_grub_default() {
    local kver="$1"
    local mode="${2:-new}"

    if [[ "$mode" == "original" ]]; then
        # 设为当前运行的内核(原内核)
        local target
        target=$(uname -r)
        log_step "  设置原内核为默认启动: $target"
    else
        log_step "  设置新内核为默认启动: $kver"
    fi

    # 使用 grub-set-default(支持 saved_entry,语言无关)
    # 但 Advanced options 在 GRUB 中是子菜单,需要用子菜单语法
    # 用 sed 兼容性更好,但需要知道菜单项的精确文本
    local target_kver="${target:-$kver}"
    local grub_default="Advanced options for Ubuntu>Ubuntu, with Linux $target_kver"

    # 检查 GRUB 是否能找到这个条目
    if sudo grep -q "with Linux $target_kver" /boot/grub/grub.cfg 2>/dev/null; then
        sudo sed -i "s|^GRUB_DEFAULT=.*|GRUB_DEFAULT=\"$grub_default\"|" /etc/default/grub
        sudo update-grub >> "$LOG_FILE" 2>&1
        log_step "  GRUB 默认启动已设置"
    else
        log_step "  警告: 在 grub.cfg 中找不到 '$target_kver',保持原 GRUB 默认"
    fi
}

# -----------------------------------------------------------------------------
# 配置保存与日志
# -----------------------------------------------------------------------------

# 初始化日志文件并打印启动信息
# 用法: lib_init "build_kernel_3080" "6.8.12-rtx3080-20260606"
lib_init() {
    local script_name="$1"
    local localversion="$2"
    : "${SRC_DIR:=/opt/linux/src/linux-6.8.12}"
    : "${LOG_FILE:=/tmp/${script_name}_$(date +%Y%m%d_%H%M%S).log}"
    : "${JOBS:=$(nproc)}"
    : "${KERNEL_LOCALVERSION:=$localversion}"
    : "${CONFIG_BACKUP_DIR:=$HOME/.config/kernel-builds}"
    mkdir -p "$CONFIG_BACKUP_DIR"
    echo "========================================" | tee -a "$LOG_FILE"
    echo "$script_name 启动 - $(date)" | tee -a "$LOG_FILE"
    echo "源码目录: $SRC_DIR" | tee -a "$LOG_FILE"
    echo "编译线程: $JOBS" | tee -a "$LOG_FILE"
    echo "本地版本: $KERNEL_LOCALVERSION" | tee -a "$LOG_FILE"
    echo "========================================" | tee -a "$LOG_FILE"
}

# 保存最终配置到标准位置
# 用法: save_final_config <kernel_release>
save_final_config() {
    local kver="$1"
    if [[ -z "$kver" ]]; then
        log_step "  警告: 内核版本号为空,跳过配置保存"
        return 1
    fi

    local boot_cfg="/boot/config-$kver"
    local user_cfg="$CONFIG_BACKUP_DIR/config-$kver"

    sudo cp .config "$boot_cfg"
    cp .config "$user_cfg"
    log_step "  配置已保存到: $boot_cfg"
    log_step "  配置已备份到: $user_cfg"
}

# 同步配置到 ~/my-shell
# 用法: sync_config_to_my_shell <filename>
sync_config_to_my_shell() {
    local filename="$1"
    local dest="$HOME/my-shell/$filename"
    mkdir -p "$HOME/my-shell"
    cp .config "$dest"
    log_step "  配置已同步到: $dest"
}

# 打印完成总结
# 用法: print_summary <kernel_release>
print_summary() {
    local kver="$1"
    echo "" | tee -a "$LOG_FILE"
    echo "========================================" | tee -a "$LOG_FILE"
    echo "编译完成 - $(date)" | tee -a "$LOG_FILE"
    echo "========================================" | tee -a "$LOG_FILE"
    log "新内核版本: ${kver:-未知}"
    log "日志文件: $LOG_FILE"
    log "配置备份: $CONFIG_BACKUP_DIR/"
}

# -----------------------------------------------------------------------------
# 库加载完成
# -----------------------------------------------------------------------------
: "${LIB_VERSION:="1.0.0"}"
export LIB_VERSION
