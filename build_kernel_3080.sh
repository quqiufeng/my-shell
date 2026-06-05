#!/bin/bash
# =============================================================================
# Linux 内核编译安装脚本 —— AMD Ryzen 5 3500X + RTX 3080 专用优化版
# =============================================================================
#
# 硬件环境:
#   - CPU:    AMD Ryzen 5 3500X (Zen2, 6核6线程, 无SMT)
#   - 显卡:   NVIDIA GeForce RTX 3080 (GA102, Ampere架构)
#   - 存储:   Samsung 238GB NVMe SSD + 931GB SATA SSD
#   - 内存:   16GB+
#   - 系统:   Ubuntu 24.04 LTS (LVM 根分区)
#
# 编译目标:
#   - 源码:   linux-6.8.12
#   - 版本:   6.8.12-rtx3080-$(date +%Y%m%d)
#   - 位置:   /opt/linux/src/linux-6.8.12/
#
# NVIDIA 注意事项:
#   - 关闭 nouveau,使用 NVIDIA 专有驱动(通过 DKMS 编译)
#   - 脚本会自动重新编译 NVIDIA DKMS 模块(make install 时的自动构建不可靠)
#   - 改了 CONFIG_PREEMPT 后必须重编 DKMS(ABI 改变)
#
# 6.8.12 内核特殊说明:
#   - CONFIG_DM_LINEAR 在 6.8.x 中已不存在,功能内置在 dm-mod 中
#   - 只需 CONFIG_BLK_DEV_DM=y 即可支持 LVM
#
# 使用方式:
#   cd /opt/linux/src/linux-6.8.12
#   setsid bash ~/my-shell/build_kernel_3080.sh > /tmp/build_kernel_3080.log 2>&1 < /dev/null &
#   tail -f /tmp/build_kernel_3080.log
#
# 参数:
#   --rebuild     强制完整重新编译
#   --reconfig    强制重新配置内核选项
#   --no-nvidia   跳过 NVIDIA DKMS 编译(测试用)
#   --help        显示帮助
#
# v2.0 重构要点:
#   - 修复 set -e + pipefail 缺失(原版 make 失败仍继续)
#   - 修复 NVIDIA 版本正则 grep 转义错误
#   - 修复双重 KERNEL_RELEASE 计算
#   - 修复 ~/my-shell 不存在导致脚本退出
#   - 通用配置抽到 lib_kernel_config.sh
#   - 6.8+ CPU 优化改用 KCFLAGS=-march=znver2
# =============================================================================

# 加载共享库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_kernel_config.sh
source "$SCRIPT_DIR/lib_kernel_config.sh"
lib_setup_strict_mode

# -----------------------------------------------------------------------------
# 全局变量
# -----------------------------------------------------------------------------
SRC_DIR="/opt/linux/src/linux-6.8.12"
KERNEL_LOCALVERSION="-rtx3080-$(date +%Y%m%d)"
CONFIG_BACKUP_DIR="$HOME/.config/kernel-builds"
MY_SHELL_CONFIG="$HOME/my-shell/config-6.8.12-rtx3080-current"
FORCE_FULL_REBUILD=false
FORCE_RECONFIGURE=false
SKIP_NVIDIA=false

# -----------------------------------------------------------------------------
# 参数解析
# -----------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case $1 in
        --rebuild)
            FORCE_FULL_REBUILD=true
            echo "[参数] 强制完整重新编译"
            shift
            ;;
        --reconfig)
            FORCE_RECONFIGURE=true
            echo "[参数] 强制重新配置内核选项"
            shift
            ;;
        --no-nvidia)
            SKIP_NVIDIA=true
            echo "[参数] 跳过 NVIDIA DKMS 编译"
            shift
            ;;
        --help|-h)
            cat <<EOF
用法: $0 [选项]

选项:
  --rebuild     强制完整重新编译(清除所有编译产物)
  --reconfig    强制重新配置内核选项
  --no-nvidia   跳过 NVIDIA DKMS 编译步骤
  --help        显示此帮助
EOF
            exit 0
            ;;
        *)
            echo "未知选项: $1"
            echo "使用 --help 查看帮助"
            exit 1
            ;;
    esac
done

# -----------------------------------------------------------------------------
# 初始化
# -----------------------------------------------------------------------------
if [[ ! -d "$SRC_DIR" ]]; then
    echo "错误: 内核源码目录 $SRC_DIR 不存在" >&2
    exit 1
fi
cd "$SRC_DIR"

# 安装依赖(apt-get 幂等)
install_deps build-essential libncurses-dev bison flex \
             libssl-dev libelf-dev bc dwarves

lib_init "build_kernel_3080" "$KERNEL_LOCALVERSION"

# -----------------------------------------------------------------------------
# [1/9] 判断增量/完整模式
# -----------------------------------------------------------------------------
INCREMENTAL=false
if [[ -f .config && -d arch/x86/boot && "$FORCE_FULL_REBUILD" == "false" ]]; then
    INCREMENTAL=true
    log_step "[1/9] 检测到已有编译配置,启用增量编译模式"
else
    log_step "[1/9] 完整重建模式(清除所有编译产物)..."
    make clean >> "$LOG_FILE" 2>&1 || true
    make mrproper >> "$LOG_FILE" 2>&1 || true
fi

# -----------------------------------------------------------------------------
# [2/9] 备份当前配置
# -----------------------------------------------------------------------------
CONFIG_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CURRENT_CONFIG="$CONFIG_BACKUP_DIR/config-$(uname -r)-$CONFIG_TIMESTAMP"

if [[ "$INCREMENTAL" == "true" && "$FORCE_RECONFIGURE" == "false" ]]; then
    log_step "[2/9] 增量模式:复用已有的 .config"
    cp .config "$CURRENT_CONFIG"
    log_step "      备份完成: $CURRENT_CONFIG"
else
    log_step "[2/9] 从当前运行内核复制标准配置"
    if [[ -f "/boot/config-$(uname -r)" ]]; then
        cp "/boot/config-$(uname -r)" .config
        cp .config "$CURRENT_CONFIG"
        log_step "      已复制 /boot/config-$(uname -r)"
    else
        log_step "      错误: 找不到当前内核配置文件"
        exit 1
    fi
fi

# -----------------------------------------------------------------------------
# [3/9] 硬件定制优化
# -----------------------------------------------------------------------------
if [[ "$INCREMENTAL" == "false" || "$FORCE_RECONFIGURE" == "true" ]]; then
    log_step "[3/9] 根据 RTX 3080 + Ryzen 3500X 优化内核配置"

    # CPU 优化(自动适配 6.8+)
    optimize_cpu "znver2" "AMD Ryzen 5 3500X (Zen2)"

    # 调度器
    optimize_scheduler_desktop

    # 透明大页
    enable_transparent_hugepages

    # 抢占模式: PREEMPT 获得更低延迟
    log_step "  - 设置低延迟抢占模式 (PREEMPT)"
    set_kconfig CONFIG_PREEMPT_NONE n
    set_kconfig CONFIG_PREEMPT_VOLUNTARY n
    set_kconfig CONFIG_PREEMPT y

    # 显卡: NVIDIA RTX 3080(关闭 nouveau,保留 DRM 基础框架)
    log_step "  - 配置 NVIDIA RTX 3080"
    set_kconfig CONFIG_DRM_I915 n
    set_kconfig CONFIG_DRM_I915_GVT n
    set_kconfig CONFIG_DRM_AMDGPU n
    set_kconfig CONFIG_DRM_RADEON n
    set_kconfig CONFIG_DRM_AMD_ACP n
    set_kconfig CONFIG_DRM_AMD_DC n
    set_kconfig CONFIG_DRM_NOUVEAU n
    set_kconfig CONFIG_NOUVEAU_PLATFORM_DRIVER n
    set_kconfig CONFIG_DRM_VIRTIO_GPU n
    set_kconfig CONFIG_DRM_QXL n
    set_kconfig CONFIG_DRM_VGEM n
    set_kconfig CONFIG_DRM_VKMS n
    set_kconfig CONFIG_DRM_UDL n
    set_kconfig CONFIG_DRM_AST n
    set_kconfig CONFIG_DRM_MGAG200 n
    set_kconfig CONFIG_DRM_BOCHS n
    set_kconfig CONFIG_DRM_CIRRUS_QEMU n
    set_kconfig CONFIG_DRM_SIMPLEDRM n
    # 保留基础 DRM 和 fbdev(NVIDIA 驱动依赖)
    set_kconfig CONFIG_DRM y
    set_kconfig CONFIG_DRM_KMS_HELPER y
    set_kconfig CONFIG_FB y
    set_kconfig CONFIG_FB_EFI y
    set_kconfig CONFIG_FB_SIMPLE y
    # NVIDIA 专有驱动需要这些
    set_kconfig CONFIG_PCI y
    set_kconfig CONFIG_ACPI y
    set_kconfig CONFIG_MODULES y
    set_kconfig CONFIG_MODULE_UNLOAD y
    set_kconfig CONFIG_MODVERSIONS y
    set_kconfig CONFIG_MMU y

    # 存储
    log_step "  - 配置 NVMe + SATA SSD"
    enable_nvme_sata
    # LVM 根分区需要 device-mapper(6.8.x 中 DM_LINEAR 已合并到 dm-mod)
    set_kconfig CONFIG_BLK_DEV_DM y
    set_kconfig CONFIG_BLK_DEV_DM_BUILTIN y
    # 禁用老旧 PATA/IDE
    set_kconfig_safe CONFIG_ATA_SFF n
    set_kconfig_safe CONFIG_PATA_AMD n
    set_kconfig_safe CONFIG_PATA_INTEL n
    set_kconfig_safe CONFIG_PATA_OLDPIIX n
    set_kconfig_safe CONFIG_PATA_SCH n

    # 文件系统
    enable_ssd_filesystems

    # 网络
    log_step "  - 配置网络驱动"
    set_kconfig CONFIG_E1000E y
    set_kconfig CONFIG_R8169 y
    set_kconfig CONFIG_IGB y
    set_kconfig CONFIG_IGC y
    disable_ethernet_vendors

    # 声卡
    log_step "  - 配置 HD Audio"
    set_kconfig CONFIG_SND_HDA_INTEL y
    set_kconfig CONFIG_SND_HDA_CODEC_REALTEK y
    set_kconfig CONFIG_SND_HDA_CODEC_HDMI y
    set_kconfig CONFIG_SND_SOC n
    set_kconfig CONFIG_SND_USB_AUDIO y
    disable_extra_audio_codecs

    # 媒体:保留基础 V4L2(NVIDIA 硬件编解码需要)
    log_step "  - 保留基础多媒体支持 (NVIDIA NVENC/NVDEC + USB 摄像头)"
    # 摄像头需要保持:MEDIA_SUPPORT / MEDIA_CAMERA_SUPPORT / MEDIA_USB_SUPPORT / USB_VIDEO_CLASS
    set_kconfig CONFIG_MEDIA_SUPPORT y
    set_kconfig CONFIG_MEDIA_CAMERA_SUPPORT y
    set_kconfig CONFIG_MEDIA_USB_SUPPORT y
    set_kconfig CONFIG_USB_VIDEO_CLASS y
    disable_tv_radio  # 关闭电视/广播/SDR(不影响摄像头)

    # 关闭特定型号的摄像头 sensor(只关具体芯片,保留 V4L2 框架)
    cams=(OV2659 OV2680 OV2685 OV2740 OV5640 OV5645 OV5647 OV5670
        OV5675 OV5693 OV5695 OV6650 OV7251 OV7640 OV7670 OV772X OV7740
        OV8856 OV8865 OV9640 OV9650 ET8EK8 MIPI_CSI_2)
    for cam in "${cams[@]}"; do
        set_kconfig_safe "CONFIG_VIDEO_${cam}" n
    done

    # 蓝牙 + Wi-Fi:必须保留(USB 蓝牙适配器、Wi-Fi 网卡等)
    log_step "  - 启用蓝牙 + Wi-Fi(保留 BT/WLAN/CFG80211/MAC80211 子系统)"
    set_kconfig CONFIG_BT y
    set_kconfig CONFIG_BT_BREDR y
    set_kconfig CONFIG_BT_LE y
    set_kconfig CONFIG_BT_INTEL y
    set_kconfig CONFIG_BT_HCIBTUSB y
    set_kconfig CONFIG_BT_HCIBTUSB_BCM y
    set_kconfig CONFIG_BT_HCIBTUSB_RTL y
    set_kconfig CONFIG_CFG80211 y
    set_kconfig CONFIG_MAC80211 y
    set_kconfig CONFIG_WLAN y
    set_kconfig CONFIG_IWLWIFI y
    set_kconfig CONFIG_IWLDVM y
    set_kconfig CONFIG_IWLMVM y
    # 关闭其他 Wi-Fi 驱动
    wifis=(RT2X00 RTLWIFI ATH10K ATH11K ATH9K BRCMFMAC B43 B43LEGACY
        SSB BCMA MT76 MWLWIFI RSI_91X WL)
    for wf in "${wifis[@]}"; do
        set_kconfig_safe "CONFIG_${wf}" n
    done

    # 虚拟化
    log_step "  - 配置虚拟化(保留 KVM/AMD,关闭其它)"
    set_kconfig CONFIG_KVM y
    set_kconfig CONFIG_KVM_AMD y
    set_kconfig CONFIG_KVM_INTEL n
    set_kconfig CONFIG_VHOST_NET y
    set_kconfig_safe CONFIG_VHOST_VSOCK n
    set_kconfig_safe CONFIG_VHOST_CROSS_ENDIAN_LEGACY n
    disable_third_party_hypervisors

    # 其它精简
    log_step "  - 移除嵌入式/老旧驱动"
    disable_fc_scsi
    disable_raid
    disable_embedded_socs
    disable_obsolete_protocols
    disable_obsolete_peripherals
    set_kconfig_safe CONFIG_NET_SCHED n
    set_kconfig_safe CONFIG_IIO n
    set_kconfig_safe CONFIG_HWMON n

    # 签名证书
    clear_kernel_signing_keys

    # 压缩
    set_kernel_compression_zstd

    # 本地版本
    set_kconfig CONFIG_LOCALVERSION "$KERNEL_LOCALVERSION"

    # -----------------------------------------------------------------------------
    # [4/9] 更新配置
    # -----------------------------------------------------------------------------
    log_step "[4/9] 更新配置(自动接受新选项默认值)..."
    make olddefconfig >> "$LOG_FILE" 2>&1

    OPTIMIZED_CONFIG="$CONFIG_BACKUP_DIR/config-rtx3080-optimized-$CONFIG_TIMESTAMP"
    cp .config "$OPTIMIZED_CONFIG"
    log_step "      优化后的配置已保存到: $OPTIMIZED_CONFIG"
fi

# -----------------------------------------------------------------------------
# [5/9] 编译内核
# -----------------------------------------------------------------------------
if [[ "$INCREMENTAL" == "true" ]]; then
    log_step "[5/9] 增量编译内核(使用 $JOBS 线程)"
    log_step "      首次编译 20-40 分钟,增量编译快很多"
else
    log_step "[5/9] 完整编译内核(使用 $JOBS 线程)"
    log_step "      预计 20-40 分钟(Ryzen 5 3500X 6核),请耐心等待"
fi

# 编译(6.8+ 时 KCFLAGS 已经在 optimize_cpu_modern 中 export)
make -j"$JOBS" 2>&1 | tee -a "$LOG_FILE"

# -----------------------------------------------------------------------------
# [6/9] 安装内核模块
# -----------------------------------------------------------------------------
log_step "[6/9] 安装内核模块"
sudo make modules_install >> "$LOG_FILE" 2>&1

# -----------------------------------------------------------------------------
# [7/9] 安装内核镜像
# -----------------------------------------------------------------------------
log_step "[7/9] 安装内核镜像"
sudo make install >> "$LOG_FILE" 2>&1

# 获取内核版本号(只需计算一次)
KERNEL_RELEASE=$(make kernelrelease 2>/dev/null || echo "")

# -----------------------------------------------------------------------------
# [8/9] 显式生成 initramfs(LVM 根分区必须)
# -----------------------------------------------------------------------------
if [[ -n "$KERNEL_RELEASE" ]]; then
    INITRAMFS="/boot/initrd.img-$KERNEL_RELEASE"
    log_step "[8/9] 检查 initramfs"
    if [[ ! -f "$INITRAMFS" ]]; then
        log_step "      initramfs 缺失,正在生成..."
        sudo update-initramfs -c -k "$KERNEL_RELEASE" >> "$LOG_FILE" 2>&1
        if [[ -f "$INITRAMFS" ]]; then
            log_step "      initramfs 生成成功: $INITRAMFS"
        else
            log_step "      错误: initramfs 生成失败!"
            log_step "      请手动运行: sudo update-initramfs -c -k $KERNEL_RELEASE"
            exit 1
        fi
    else
        log_step "      initramfs 已存在: $INITRAMFS"
    fi
fi

# -----------------------------------------------------------------------------
# [9/9] NVIDIA DKMS 编译(自动 / 手动)
# -----------------------------------------------------------------------------
if [[ "$SKIP_NVIDIA" == "true" ]]; then
    log_step "[9/9] 跳过 NVIDIA DKMS 编译(--no-nvidia)"
else
    log_step "[9/9] 编译 NVIDIA DKMS 模块"
    if [[ -n "$KERNEL_RELEASE" ]]; then
        build_nvidia_dkms "$KERNEL_RELEASE"
        log_step "      重新生成 initramfs(包含 NVIDIA 模块)"
        sudo update-initramfs -u -k "$KERNEL_RELEASE" >> "$LOG_FILE" 2>&1
    else
        log_step "      警告: 内核版本号为空,跳过 NVIDIA DKMS"
    fi
fi

# -----------------------------------------------------------------------------
# 保存配置
# -----------------------------------------------------------------------------
log_step "[额外] 保存编译配置"
save_final_config "$KERNEL_RELEASE"
sync_config_to_my_shell "config-6.8.12-rtx3080-current"

# -----------------------------------------------------------------------------
# 更新 GRUB,默认启动新内核
# -----------------------------------------------------------------------------
log_step "[额外] 更新 GRUB"
sudo update-grub >> "$LOG_FILE" 2>&1
set_grub_default "$KERNEL_RELEASE" "new"

# -----------------------------------------------------------------------------
# 总结
# -----------------------------------------------------------------------------
print_summary "$KERNEL_RELEASE"
echo ""
echo "后续步骤:"
echo "  1. NVIDIA 驱动已自动通过 DKMS 重新编译"
echo "  2. 重启验证: nvidia-smi 应能正常显示"
echo "  3. 如有问题:在 GRUB 菜单选择旧内核启动排查"
echo ""
echo "增量编译提示:"
echo "  - ./build_kernel_3080.sh             增量编译"
echo "  - ./build_kernel_3080.sh --rebuild   强制完整重新编译"
echo "  - ./build_kernel_3080.sh --reconfig  重新配置内核选项"
echo "  - ./build_kernel_3080.sh --no-nvidia 跳过 NVIDIA DKMS"
echo "  - 所有内核配置保存在: $CONFIG_BACKUP_DIR/"
