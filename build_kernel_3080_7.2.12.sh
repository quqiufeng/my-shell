#!/bin/bash
# =============================================================================
# Linux 7.2.12 内核编译安装脚本 —— AMD Ryzen 5 3500X + RTX 3080 专用优化版
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
#   - 源码:   linux-7.2.12
#   - 版本:   7.2.12-rtx3080-$(date +%Y%m%d)
#   - 位置:   /opt/linux/src/linux-7.2.12/
#
# 7.2.12 说明:
#   - 7.2 稳定系列第 12 个补丁版本(2026-10-21), 只含 bug/安全修复
#   - 与运行中的 7.2.3 同系列, Kconfig/ABI 基本一致, 可直接复用 /boot/config
#   - 保留 CONFIG_X86_NATIVE_CPU(自动 -march=native)与 Rust 支持
#   - NVIDIA 595.99.02 DKMS 与 gpu_unlock 在 7.2 系列内已验证可重编
#
# NVIDIA 注意事项:
#   - 关闭 nouveau,使用 NVIDIA 专有驱动(通过 DKMS 编译)
#   - 脚本会自动重新编译 NVIDIA DKMS 模块(make install 时的自动构建不可靠)
#   - 改了 CONFIG_PREEMPT 后必须重编 DKMS(ABI 改变)
#
# =============================================================================
# GPU 解锁(gpu-unlock)
# =============================================================================
#
# 项目地址: https://github.com/Zagitta/gpu-unlock
#
# 作用:
#   把 GA102/GA103/GA104/GA106(含本机 RTX 3080 20GB)的 FP/BF16 指令
#   发射速率从 GeForce 的半速解锁到专业卡全速。社区实测(3080 20GB):
#     - 稠密 BF16 GEMM:约 +56~59%(3090 Ti 上 FP16 +35%, TF32 约翻倍)
#     - LLM prefill +14~36%,FlashAttention/扩散模型变快
#     - decode(显存带宽瓶颈)和 INT8 基本不变;输出比特级一致
#
# 本机实测收益(RTX 3080 20GB, 320W 功耗墙, 2026-10-25 严格 A/B):
#   方法: 同一负载分别跑两次启动 —— 一次带 gpu_unlock.targets=all,
#   一次在 grub.cfg 里临时去掉它; 固定 seed/参数/数据/缓存, 只差解不解锁。
#
#   1) 纯 GEMM (8192³, fp32 累加, 10 次中位):
#        BF16  59.6 -> 111.8 TFLOPS  (+88%)
#        FP16  60.9 -> 112.9 TFLOPS  (+85%)
#        TF32  30.2 ->  58.6 TFLOPS  (+94%)
#
#   2) LoRA 训练 (musubi-tuner, Z-Image Base bf16, 1024, rank16,
#      blocks_to_swap=2, 30 图, 60 步, seed 42):
#        3m39s (3.72 s/step) -> 2m35s (2.64 s/step)
#        耗时 -29.2%, 吞吐 +41.3%; 按 1600 步正式配方折算约 99min -> 70min
#        收益最大的真实场景: DiT 前向+反向都是 bf16 GEMM, 纯算力密集
#
#   3) stock RL 训练 (stock_rl_train, train_7y, 3500ep, bf16 autocast):
#        R1 1287s -> 1123s (-12.7%); 全链 R1-R9+G1: 3h52m -> 3h22m
#        收益被 CPU 侧摊薄: 每 ep 约 360ms, sim/数据/同步占大半,
#        训练时 GPU 利用率只有 ~11%(ppo 段 188->162ms, lstm_pre 87->82ms)
#
#   4) 出图推理 (sd.cpp, z_image_turbo-Q8_K GGUF, 2560x1440, EasyCache,
#      seed 25630): 218.7s vs 205.7/222.6s —— 在 ±8% 波动内, 基本无提升
#        原因: 每步要读 6.8GB 量化权重(~570GB/s, 接近 760GB/s 上限),
#        瓶颈是显存带宽/反量化, 不是 FP16 算力; 输出 PNG md5 完全一致
#
#   结论: 算力密集(GEMM / LoRA 训练 / LLM prefill)收益明显; 显存带宽受限
#   (量化推理)和 CPU 受限(股票 RL 的 sim)场景收益很小甚至没有。
#
# 原理:
#   1. 借鉴 CMP 矿卡解锁的 V67/PLM 手法,在 nvidia 驱动 bind 之前写入
#      速度选择器 SS0=0x88888888(全速 BF16)、SS1=0x8(IMLA4)
#   2. 加载 NVIDIA 官方 gsp/booter 固件,然后做一次 FLR 复位
#   3. 模块放在 initramfs 里且必须排在 nvidia 之前加载;不改 vBIOS、
#      不 patch 驱动,所以驱动更新不受影响,每次开机重新解锁
#   4. 睡眠时显卡掉电会清掉选择器,模块用 suspend notifier 在 nvidia
#      resume 之前再解锁一次(可用 gpu_unlock.resume=0 关闭)
#
# 安装流程(首次,一次性):
#   git clone https://github.com/Zagitta/gpu-unlock
#   cd gpu-unlock && sudo make install-deb
#   # 内核命令行需要 gpu_unlock.targets=all(本脚本会自动补齐)
#   # 手动方式: 编辑 /etc/default/grub 的 GRUB_CMDLINE_LINUX_DEFAULT
#   #           然后 sudo update-grub
#
# 加载顺序(Ubuntu 上很容易踩的坑):
#   initramfs-tools 的 /init 先跑 init-top/udev, 再跑 load_modules。
#   nvidia 模块被打进 initramfs 后, udev 会按 PCI modalias 在 load_modules
#   之前就把它加载并绑定显卡, 此时 gpu_unlock 再加载只能得到 -EBUSY。
#   所以需要 /etc/modprobe.d/gpu-unlock.conf:
#       softdep nvidia pre: gpu_unlock
#   让 libkmod 在加载 nvidia 之前先 modprobe gpu_unlock。
#   本脚本会自动写入该文件; 手工安装时如果 journalctl 看到
#   "nvidia 0000:xx:00.0: gpu_unlock: unlock failed (-16)" 就补上它。
#   注意: kmod 对同一条 softdep 只认第一个读到的文件,改前先确认没有别处
#   已经定义 `softdep nvidia`。
#
# 升级/换内核流程:
#   - 升级内核:直接跑本脚本。[9/9] 会为新内核重建 nvidia 和 gpu-unlock,
#     然后统一重建 initramfs。自编译内核没有 dpkg 的 kernel postinst 钩子,
#     DKMS 不会自动触发,必须靠这一步。
#   - 升级 gpu-unlock 项目本身:
#       cd gpu-unlock && git pull && sudo make install-deb
#     然后重跑本脚本(或手动 dkms install + update-initramfs -u -k)。
#
# 验证:
#   journalctl -k -b | grep gpu_unlock     # 应出现 "gpu_unlock: unlocked"
#   modinfo gpu_unlock                     # 确认已安装
#   lspci -nnk -s 26:00.0                  # 确认驱动仍是 nvidia
#
# 关闭/卸载:
#   临时关闭:去掉内核命令行的 gpu_unlock.targets=(改 GRUB 后 update-grub)
#   彻底卸载:sudo apt purge gpu-unlock-dkms gpu-unlock-firmware
#
# 注意:
#   - 本机 3080 是显示卡,解锁时屏幕会短暂黑屏约 1 秒,属正常现象
#   - 是 GPU 固件/寄存器级操作,只对支持列表内的消费级卡有效
#   - 装好后不要手动 rmmod nvidia;模块只在开机/唤醒时动作
#
# =============================================================================
# 故障修复: 外部模块与运行内核 ABI 不一致(DKMS 模块加载失败)
# =============================================================================
#
# 原理:
#   外部模块编出来的 .ko 必须和运行内核三样东西对上:
#     1. vermagic: CONFIG_LOCALVERSION + SMP/PREEMPT/MODULE_UNLOAD/MODVERSIONS
#     2. struct module 布局: CONFIG_MODULE_UNLOAD / KALLSYMS(_ALL) /
#        TRACEPOINTS / FTRACE / LIVEPATCH / JUMP_LABEL / KASAN / RANDSTRUCT 等
#     3. 导出符号 CRC: 内核构建时生成的 Module.symvers
#   自编译内核没有 linux-headers-<ver> deb,DKMS 只能通过
#   /lib/modules/<ver>/build 指向的源码树取头文件和符号表。一旦这棵树的
#   .config 被换成别的(误跑 menuconfig/defconfig、换成另一套精简配置等),
#   新编的模块加载时会报:
#     "module gpu_unlock: .gnu.linkonce.this_module section size must match
#      the kernel's built struct module size at run time"    (第 2 项不符)
#     "disagrees about version of symbol module_layout"      (第 3 项不符)
#   已经在用的 nvidia 老模块不受影响,因为它们是当初用正确的树编好的。
#
# 判断当前树是否匹配(脚本 [1/9] 会自动做这件事,不一致就自动转 --reconfig):
#   grep -E '^CONFIG_(LOCALVERSION|MODULE_UNLOAD|KASAN)=' \
#       /boot/config-$(uname -r) /opt/linux/src/linux-7.2.12/.config
#   cat /opt/linux/src/linux-7.2.12/include/config/kernel.release
#
# 干净源码从哪来(本机现状, 重要):
#   - DKMS 依赖 /opt/linux/src/linux-7.2.12(带 build 产物;
#     /lib/modules/$(uname -r)/build 指向它) => 这棵树不能 make mrproper,
#     否则以后 nvidia/gpu-unlock 重新编模块会找不到头文件和 Module.symvers。
#   - 但 make O=<dir> 要求源码树是干净的, 不能拿上面那棵带产物的树做 O= 构建
#     (会报 "source tree is not clean, please run 'make mrproper'")。
#   - 旧的 /opt/linux-7.2.3-clean 已删除。需要修 ABI 时, 先从源码包解压一份
#     干净副本(约 1.5G, 只做一次):
#        mkdir -p /opt/linux-7.2.12-clean
#        tar -xf /opt/linux/src/linux-7.2.12.tar.xz \
#            -C /opt/linux-7.2.12-clean --strip-components=1
#     或用 CLEAN_SRC=<其它干净目录> 指定(必须与运行内核版本一致)。
#
# 修复过程(不要改动 /opt/linux/src/linux-7.2.12 这棵带 build 产物的树):
#   1. 确认报错:
#        sudo journalctl -k -b | grep -E 'gpu_unlock|this_module|disagrees'
#        modinfo -F vermagic /lib/modules/$(uname -r)/updates/dkms/gpu_unlock.ko
#        readelf -SW .../gpu_unlock.ko | grep this_module    # 应为 0x500
#   2. 用干净源码 + 运行内核的 /boot/config 建独立 O= 构建目录
#      (下面按默认的 /opt/linux-7.2.12-clean 写):
#        mkdir -p /tmp/kb && cp /boot/config-$(uname -r) /tmp/kb/.config
#        make -C /opt/linux-7.2.12-clean O=/tmp/kb olddefconfig
#        make -C /opt/linux-7.2.12-clean O=/tmp/kb -j$(nproc) modules_prepare
#   3. 生成匹配的 Module.symvers:
#      CRC 只存在内核镜像的 __kcrctab(只读数据)里,System.map 只有地址,
#      所以从 /proc/kcore 读,再用 /proc/kallsyms 的 _text 校准 KASLR 偏移:
#        sudo python3 gpu_unlock_symvers.py $(uname -r) /tmp/kb/Module.symvers
#      可以拿 nvidia.ko 里 module_layout 的 CRC 校验提取结果。
#   4. 用这个目录编译并装回:
#        make -C /tmp/kb M=<gpu_unlock 源码> modules
#        装到 /lib/modules/$(uname -r)/updates/dkms/, 然后 depmod,
#        update-initramfs -u -k $(uname -r), 重启
#   5. 一条命令完成 2~4:
#        ./build_kernel_3080_7.2.12.sh --repair-gpu-unlock
#      默认 CLEAN_SRC=/opt/linux-7.2.12-clean; 目录不存在时脚本会直接打印
#      上面的解压命令并退出(不会拿带 build 产物的树硬编)。
#      显式指定:
#        CLEAN_SRC=/opt/linux-7.2.12-clean ./build_kernel_3080_7.2.12.sh --repair-gpu-unlock
#
# 预防: 脚本 [1/9] 会对比树 .config 与 /boot/config-$(uname -r) 的 ABI 关键项,
#   不一致时自动切到 --reconfig 模式(从运行内核的 config 重新生成),不会再
#   把错误的 .config 带进增量编译。
#
# 使用方式:
#   cd /opt/linux/src/linux-7.2.12
#   setsid bash ~/my-shell/build_kernel_3080_7.2.12.sh > /tmp/build_kernel_3080_7.2.12.log 2>&1 < /dev/null &
#   tail -f /tmp/build_kernel_3080_7.2.12.log
#
# 参数:
#   --rebuild     强制完整重新编译
#   --reconfig    强制重新配置内核选项
#   --no-nvidia   跳过 NVIDIA DKMS 编译(测试用)
#   --no-gpu-unlock 跳过 gpu-unlock DKMS 编译(调试用)
#   --repair-gpu-unlock 只修复 gpu-unlock 加载失败(不编译内核)
#   --help        显示帮助
# =============================================================================

# 加载共享库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_kernel_config.sh
source "$SCRIPT_DIR/lib_kernel_config.sh"
lib_setup_strict_mode

# -----------------------------------------------------------------------------
# 全局变量
# -----------------------------------------------------------------------------
SRC_DIR="/opt/linux/src/linux-7.2.12"
KERNEL_LOCALVERSION="-rtx3080-$(date +%Y%m%d)"
CONFIG_BACKUP_DIR="$HOME/.config/kernel-builds"
MY_SHELL_CONFIG="$HOME/my-shell/config-7.2.12-rtx3080-current"
FORCE_FULL_REBUILD=false
FORCE_RECONFIGURE=false
SKIP_NVIDIA=false
SKIP_GPU_UNLOCK=false
REPAIR_GPU_UNLOCK=false

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
        --no-gpu-unlock)
            SKIP_GPU_UNLOCK=true
            echo "[参数] 跳过 gpu-unlock DKMS 编译"
            shift
            ;;
        --repair-gpu-unlock)
            REPAIR_GPU_UNLOCK=true
            echo "[参数] 修复 gpu-unlock 与运行内核的 ABI 不一致"
            shift
            ;;
        --help|-h)
            cat <<EOF
用法: $0 [选项]

选项:
  --rebuild     强制完整重新编译(清除所有编译产物)
  --reconfig    强制重新配置内核选项
  --no-nvidia   跳过 NVIDIA DKMS 编译步骤
  --no-gpu-unlock 跳过 gpu-unlock DKMS 编译步骤
  --repair-gpu-unlock 只修复 gpu-unlock(不编译内核),用运行内核的配置重编模块
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
# 只修复 gpu-unlock(不编译内核)
# -----------------------------------------------------------------------------
if [[ "$REPAIR_GPU_UNLOCK" == "true" ]]; then
    lib_init "repair_gpu_unlock" "$(uname -r)"
    clean_src="${CLEAN_SRC:-/opt/linux-7.2.12-clean}"
    if [[ ! -d "$clean_src" ]]; then
        log_step "  未找到干净源码树: $clean_src"
        log_step "  先解压一份干净源码(约 1.5G, 只做一次):"
        log_step "    mkdir -p /opt/linux-7.2.12-clean"
        log_step "    tar -xf /opt/linux/src/linux-7.2.12.tar.xz -C /opt/linux-7.2.12-clean --strip-components=1"
        log_step "  或用 CLEAN_SRC=<目录> 指定(必须与运行内核版本一致)"
        log_step "  注意: 不要用 /opt/linux/src/linux-7.2.12 本体(它带 build 产物,"
        log_step "        O= 构建会报 source tree is not clean, 且 mrproper 会破坏 DKMS)"
        exit 1
    fi
    repair_gpu_unlock_abi "$(uname -r)" "$clean_src" || exit 1
    exit 0
fi

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

    # 树里的 .config 如果被换过,增量编译会把错误配置带进新内核,
    # 之后 DKMS 编出的外部模块(nvidia/gpu-unlock)会加载失败。
    # 这里对比 ABI 关键项,不一致就自动转成 --reconfig。
    if [[ "$FORCE_RECONFIGURE" == "false" ]] \
        && ! kernel_config_abi_matches .config "/boot/config-$(uname -r)"; then
        log_step "[1/9] 警告: 树里的 .config 与运行内核的 ABI 关键配置不一致:"
        kernel_abi_config_diff .config "/boot/config-$(uname -r)" | tee -a "$LOG_FILE"
        log_step "[1/9] 自动切换为 --reconfig(从 /boot/config-$(uname -r) 重新生成)"
        FORCE_RECONFIGURE=true
    fi

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
    else
        log_step "      错误: 找不到当前内核配置文件"
        exit 1
    fi
fi

# -----------------------------------------------------------------------------
# [2.5/9] CPU 微架构优化(总是执行,幂等)
# -----------------------------------------------------------------------------
# 必须在 Kconfig 调整之前做,因为它会改 arch/x86/Makefile 和 export KCFLAGS
# 这两步都影响 make 实际传给 gcc 的 flag
# 7.0+ 会自动启用 CONFIG_X86_NATIVE_CPU,效果 = -march=native (对 Zen2 = znver2)
optimize_cpu "znver2" "AMD Ryzen 5 3500X (Zen2) via X86_NATIVE_CPU"

# -----------------------------------------------------------------------------
# [3/9] 硬件定制优化
# -----------------------------------------------------------------------------
if [[ "$INCREMENTAL" == "false" || "$FORCE_RECONFIGURE" == "true" ]]; then
    log_step "[3/9] 根据 RTX 3080 + Ryzen 3500X 优化内核配置"

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

    # Waydroid 容器化 Android 支持(Binder + legacy iptables NAT)
    log_step "  - 启用 Waydroid 支持"
    enable_waydroid_binder
    enable_waydroid_netfilter

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
    make olddefconfig 2>&1 | tee -a "$LOG_FILE"

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

# 编译(7.0+ 用 X86_NATIVE_CPU,KCFLAGS 可选)
make -j"$JOBS" 2>&1 | tee -a "$LOG_FILE"

# -----------------------------------------------------------------------------
# [6/9] 安装内核模块
# -----------------------------------------------------------------------------
log_step "[6/9] 安装内核模块"
sudo make modules_install 2>&1 | tee -a "$LOG_FILE"

# -----------------------------------------------------------------------------
# [7/9] 安装内核镜像
# -----------------------------------------------------------------------------
log_step "[7/9] 安装内核镜像"

# 临时禁用 dkms autoinstall
# 原因:make install 触发 /etc/kernel/postinst.d/dkms 自动构建 NVIDIA,
#       但新内核没有对应的 linux-headers-<ver> deb 包,dkms 找不到 header 会失败
#       (错误: kernel package linux-headers-<ver> is not supported)
#       我们在 [9/9] 手动用源码树 build/install,不依赖 dkms autoinstall
if [[ -f /etc/kernel/postinst.d/dkms ]]; then
    log_step "      临时禁用 dkms autoinstall(用源码树手动构建更可靠)"
    sudo mv /etc/kernel/postinst.d/dkms /etc/kernel/postinst.d/dkms.disabled
    DKMS_WAS_ENABLED=true
else
    DKMS_WAS_ENABLED=false
fi

# 异常退出时也要恢复 dkms
trap '[[ "$DKMS_WAS_ENABLED" == "true" ]] && sudo mv /etc/kernel/postinst.d/dkms.disabled /etc/kernel/postinst.d/dkms 2>/dev/null || true' EXIT

sudo make install 2>&1 | tee -a "$LOG_FILE"

# 恢复 dkms autoinstall(留给 apt 安装新内核时使用)
if [[ "$DKMS_WAS_ENABLED" == "true" ]]; then
    sudo mv /etc/kernel/postinst.d/dkms.disabled /etc/kernel/postinst.d/dkms
    trap - EXIT
    log_step "      已恢复 dkms autoinstall"
fi

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
        sudo update-initramfs -c -k "$KERNEL_RELEASE" 2>&1 | tee -a "$LOG_FILE"
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
# [9/9] DKMS 编译(自动 / 手动):NVIDIA + gpu-unlock
# -----------------------------------------------------------------------------
if [[ "$SKIP_NVIDIA" == "true" ]]; then
    log_step "[9/9] 跳过 NVIDIA DKMS 编译(--no-nvidia)"
else
    log_step "[9/9] 编译 NVIDIA DKMS 模块"
    if [[ -n "$KERNEL_RELEASE" ]]; then
        build_nvidia_dkms "$KERNEL_RELEASE"

        if [[ "$SKIP_GPU_UNLOCK" == "true" ]]; then
            log_step "      跳过 gpu-unlock DKMS 编译(--no-gpu-unlock)"
        else
            log_step "      编译 gpu-unlock DKMS 模块(需在 initramfs 中先于 nvidia)"
            build_gpu_unlock_dkms "$KERNEL_RELEASE"
        fi

        log_step "      重新生成 initramfs(包含 NVIDIA + gpu_unlock 模块)"
        sudo update-initramfs -u -k "$KERNEL_RELEASE" 2>&1 | tee -a "$LOG_FILE"
    else
        log_step "      警告: 内核版本号为空,跳过 DKMS 编译"
    fi
fi

# -----------------------------------------------------------------------------
# 保存配置
# -----------------------------------------------------------------------------
log_step "[额外] 保存编译配置"
save_final_config "$KERNEL_RELEASE"
sync_config_to_my_shell "config-7.2.12-rtx3080-current"

# -----------------------------------------------------------------------------
# 更新 GRUB,默认启动新内核
# -----------------------------------------------------------------------------
log_step "[额外] 更新 GRUB"
if [[ "$SKIP_GPU_UNLOCK" != "true" && -n "$(get_gpu_unlock_version)" ]]; then
    ensure_gpu_unlock_softdep
    ensure_gpu_unlock_cmdline
fi
sudo update-grub 2>&1 | tee -a "$LOG_FILE"
set_grub_default "$KERNEL_RELEASE" "new"

# -----------------------------------------------------------------------------
# 总结
# -----------------------------------------------------------------------------
print_summary "$KERNEL_RELEASE"
echo ""
echo "后续步骤:"
echo "  1. Kernel 7.2.12-rtx3080-* 已编译, NVIDIA/gpu-unlock 已通过 DKMS 重新编译"
echo "  2. 重启验证: nvidia-smi 应能正常显示"
echo "  3. 解锁验证: journalctl -k -b | grep gpu_unlock (应出现 unlocked)"
echo "  4. 如有问题:在 GRUB 菜单选择旧内核启动排查"
echo ""
echo "增量编译提示:"
echo "  - ./build_kernel_3080_7.2.12.sh                  增量编译"
echo "  - ./build_kernel_3080_7.2.12.sh --rebuild        强制完整重新编译"
echo "  - ./build_kernel_3080_7.2.12.sh --reconfig       重新配置内核选项"
echo "  - ./build_kernel_3080_7.2.12.sh --no-nvidia      跳过 NVIDIA DKMS"
echo "  - ./build_kernel_3080_7.2.12.sh --no-gpu-unlock  跳过 gpu-unlock DKMS"
echo "  - ./build_kernel_3080_7.2.12.sh --repair-gpu-unlock 修复模块加载失败(不编译内核)"
echo "  - 所有内核配置保存在: $CONFIG_BACKUP_DIR/"
