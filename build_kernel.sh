#!/bin/bash
# =============================================================================
# Linux 内核编译安装脚本 —— Intel Core i5-2400 (Sandy Bridge) 优化版
# =============================================================================
#
# 硬件环境:
#   - CPU:    Intel Core i5-2400 (Sandy Bridge, 4核4线程)
#   - 显卡:   Intel HD Graphics 2000
#   - 存储:   Samsung 128GB NVMe SSD
#   - 内存:   12GB DDR3
#   - 网络:   Realtek RTL8111/8168 PCI-E 千兆网卡
#   - 系统:   Ubuntu 24.04 LTS
#
# 编译目标:
#   - 源码:   linux-6.8.12
#   - 版本:   6.8.12-custom-$(date +%Y%m%d)
#   - 位置:   /opt/linux/src/linux-6.8.12/
#
# 使用方式:
#   cd /opt/linux/src/linux-6.8.12
#   setsid bash ~/my-shell/build_kernel.sh > /tmp/build_kernel_nohup.log 2>&1 < /dev/null &
#   tail -f /tmp/build_kernel_nohup.log
#
# 参数:
#   --rebuild    强制完整重新编译(清除所有编译产物)
#   --reconfig   强制重新配置内核选项
#   --help       显示帮助
#
# v2.0 重构要点:
#   - 通用配置(网卡/SoC/虚拟化/RAID 等)抽到 lib_kernel_config.sh
#   - 修复 6.8.x Kconfig 中已移除 MSANDYBRIDGE 的问题,改用 KCFLAGS
#   - 修复 set -e 不捕获管道中段失败的 bug
#   - GRUB 默认启动改为语言无关的 sed 方式
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
KERNEL_LOCALVERSION="-custom-$(date +%Y%m%d)"
CONFIG_BACKUP_DIR="$HOME/.config/kernel-builds"
MY_SHELL_CONFIG="$HOME/my-shell/config-6.8.12-custom-current"
FORCE_FULL_REBUILD=false
FORCE_RECONFIGURE=false

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
        --help|-h)
            cat <<EOF
用法: $0 [选项]

选项:
  --rebuild    强制完整重新编译(清除所有编译产物)
  --reconfig   强制重新配置内核选项
  --help       显示此帮助

默认运行:增量编译(基于已有的 .config)
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

# 安装依赖(apt-get 幂等,已装的不会重装)
install_deps build-essential libncurses-dev bison flex \
             libssl-dev libelf-dev bc dwarves

lib_init "build_kernel" "$KERNEL_LOCALVERSION"

# -----------------------------------------------------------------------------
# [1/9] 判断增量/完整模式
# -----------------------------------------------------------------------------
INCREMENTAL=false
if [[ -f .config && -d arch/x86/boot && "$FORCE_FULL_REBUILD" == "false" ]]; then
    INCREMENTAL=true
    log_step "[1/9] 检测到已有编译配置,启用增量编译模式"
else
    log_step "[1/9] 完整重建模式(清除所有编译产物)..."
    make clean 2>&1 | tee -a "$LOG_FILE" || true
    make mrproper 2>&1 | tee -a "$LOG_FILE" || true
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
        log_step "      原始配置已备份到: $CURRENT_CONFIG"
    else
        log_step "      错误: 找不到当前内核配置文件"
        exit 1
    fi
fi

# -----------------------------------------------------------------------------
# [2.5/9] CPU 微架构优化(总是执行,幂等)
# -----------------------------------------------------------------------------
# 必须在 Kconfig 调整之前做,因为它会改 arch/x86/Makefile 和 export KCFLAGS
optimize_cpu "sandybridge" "Intel Core i5-2400"

# -----------------------------------------------------------------------------
# [3/9] 硬件定制优化(只在新配置或强制 reconfig 时执行)
# -----------------------------------------------------------------------------
if [[ "$INCREMENTAL" == "false" || "$FORCE_RECONFIGURE" == "true" ]]; then
    log_step "[3/9] 根据本机硬件优化内核配置"

    # 调度器优化
    optimize_scheduler_desktop

    # 透明大页
    enable_transparent_hugepages

    # 显卡: Intel HD Graphics 2000
    log_step "  - 配置 Intel i915 显卡驱动"
    set_kconfig CONFIG_DRM_I915 y
    set_kconfig CONFIG_DRM_I915_GVT n
    set_kconfig CONFIG_DRM_AMDGPU n
    set_kconfig CONFIG_DRM_RADEON n
    set_kconfig CONFIG_DRM_NOUVEAU n
    set_kconfig CONFIG_DRM_VIRTIO_GPU n
    set_kconfig CONFIG_DRM_QXL n
    set_kconfig CONFIG_DRM_VGEM n
    set_kconfig CONFIG_DRM_VKMS n
    set_kconfig CONFIG_DRM_UDL n
    set_kconfig CONFIG_DRM_AST n
    set_kconfig CONFIG_DRM_MGAG200 n

    # 存储: NVMe + SATA AHCI
    log_step "  - 配置 NVMe + SATA SSD 支持"
    enable_nvme_sata

    # 文件系统
    enable_ssd_filesystems

    # 网络
    log_step "  - 配置网络驱动"
    set_kconfig CONFIG_E1000E y
    set_kconfig CONFIG_R8169 y
    set_kconfig CONFIG_IGB y
    disable_ethernet_vendors

    # Wi-Fi (Intel 常见型号)
    log_step "  - 保留 Intel Wi-Fi 驱动"
    set_kconfig CONFIG_IWLWIFI y
    set_kconfig CONFIG_IWLDVM y
    set_kconfig CONFIG_IWLMVM y

    # 蓝牙
    log_step "  - 配置蓝牙支持"
    set_kconfig CONFIG_BT y
    set_kconfig CONFIG_BT_BREDR y
    set_kconfig CONFIG_BT_LE y
    set_kconfig CONFIG_BT_INTEL y
    set_kconfig CONFIG_BT_HCIBTUSB y

    # 声卡
    log_step "  - 配置 Intel HD Audio"
    set_kconfig CONFIG_SND_HDA_INTEL y
    set_kconfig CONFIG_SND_HDA_CODEC_REALTEK y
    set_kconfig CONFIG_SND_HDA_CODEC_HDMI y
    disable_extra_audio_codecs

    # 移除不需要的驱动
    log_step "  - 移除服务器/虚拟化/嵌入式驱动"
    disable_third_party_hypervisors
    set_kconfig_safe CONFIG_KVM n
    set_kconfig_safe CONFIG_VHOST_NET n
    disable_fc_scsi
    disable_raid
    disable_embedded_socs
    disable_obsolete_protocols
    disable_obsolete_peripherals
    disable_tv_radio

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
    make olddefconfig 2>&1 | tee -a "$LOG_FILE"

    # 备份优化后的配置
    OPTIMIZED_CONFIG="$CONFIG_BACKUP_DIR/config-optimized-$CONFIG_TIMESTAMP"
    cp .config "$OPTIMIZED_CONFIG"
    log_step "      优化后的配置已保存到: $OPTIMIZED_CONFIG"
fi

# -----------------------------------------------------------------------------
# [5/9] 编译内核
# -----------------------------------------------------------------------------
if [[ "$INCREMENTAL" == "true" ]]; then
    log_step "[5/9] 增量编译内核(使用 $JOBS 线程)"
    log_step "      首次编译可能需要 30-60 分钟,增量编译快很多"
else
    log_step "[5/9] 完整编译内核(使用 $JOBS 线程)"
    log_step "      这可能需要 30-60 分钟,请耐心等待"
fi

# 编译(注意:6.8+ KCFLAGS 已经在 optimize_cpu_modern 中 export)
make -j"$JOBS" 2>&1 | tee -a "$LOG_FILE"

# -----------------------------------------------------------------------------
# [6/9] 安装内核模块
# -----------------------------------------------------------------------------
log_step "[6/9] 安装内核模块"
sudo make modules_install 2>&1 | tee -a "$LOG_FILE"

# -----------------------------------------------------------------------------
# [7/9] 安装内核镜像
# -----------------------------------------------------------------------------
log_step "[7/9] 安装内核镜像并更新 GRUB"

# 临时禁用 dkms autoinstall(避免对新内核找不到 headers 而失败)
if [[ -f /etc/kernel/postinst.d/dkms ]]; then
    sudo mv /etc/kernel/postinst.d/dkms /etc/kernel/postinst.d/dkms.disabled
    DKMS_DISABLED=true
    trap '[[ "${DKMS_DISABLED:-false}" == "true" ]] && sudo mv /etc/kernel/postinst.d/dkms.disabled /etc/kernel/postinst.d/dkms 2>/dev/null || true' EXIT
fi

sudo make install 2>&1 | tee -a "$LOG_FILE"

# 恢复
if [[ "${DKMS_DISABLED:-false}" == "true" ]]; then
    sudo mv /etc/kernel/postinst.d/dkms.disabled /etc/kernel/postinst.d/dkms
    unset DKMS_DISABLED
    trap - EXIT
fi

# -----------------------------------------------------------------------------
# [8/9] 保存配置
# -----------------------------------------------------------------------------
KERNEL_RELEASE=$(make kernelrelease 2>/dev/null || echo "")
log_step "[8/9] 保存编译配置"
save_final_config "$KERNEL_RELEASE"
sync_config_to_my_shell "config-6.8.12-custom-current"

# -----------------------------------------------------------------------------
# [9/9] 更新 GRUB,默认启动原内核(更安全)
# -----------------------------------------------------------------------------
log_step "[9/9] 更新 GRUB"
sudo update-grub 2>&1 | tee -a "$LOG_FILE"
set_grub_default "$KERNEL_RELEASE" "original"

# -----------------------------------------------------------------------------
# 总结
# -----------------------------------------------------------------------------
print_summary "$KERNEL_RELEASE"
echo ""
echo "后续步骤:"
echo "  - 重启后在 GRUB 菜单 → Advanced options → 选择新内核 6.8.12-custom-* 测试"
echo "  - 验证新内核稳定后可手动改为默认启动"
echo ""
echo "增量编译提示:"
echo "  - 再次运行此脚本会自动检测已有编译产物,只编译变化部分"
echo "  - ./build_kernel.sh --rebuild  强制完整重新编译"
echo "  - ./build_kernel.sh --reconfig 重新配置内核选项"
echo "  - 所有内核配置保存在: $CONFIG_BACKUP_DIR/"
