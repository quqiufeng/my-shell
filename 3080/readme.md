# 3080 安卓虚拟机（Waydroid）部署记录

> 记录在 RTX 3080 主机上安装 Waydroid（LXC 容器化 Android）的完整过程：
> 内核编译（启用 Binder + legacy iptables）、Waydroid 安装、窗口系统适配（Weston 嵌套）、
> 以及 Google Play / libndk 扩展。

## 环境

| 项目 | 值 |
|------|-----|
| CPU | AMD Ryzen 5 3500X (Zen2, 6C6T) |
| GPU | NVIDIA GeForce RTX 3080 20GB |
| 驱动 | NVIDIA 595.91.07 (DKMS) |
| 系统 | Ubuntu 24.04 LTS |
| 桌面 | Lubuntu / LXQt —— **X11 会话**（非 Wayland） |
| 内核 | 自编译 `7.2.3-rtx3080-*`，源码 `/opt/linux/src/linux-7.2.3` |
| 内核脚本 | `/opt/my-shell/build_kernel_3080_7.0.sh` + `lib_kernel_config.sh` |

## 方案概览

| 组件 | 作用 |
|------|------|
| Waydroid | 基于 LXC 的容器化 Android（共享宿主内核，性能接近原生） |
| 内核 Binder | Waydroid 依赖 Android Binder IPC，自编译内核需显式开启 |
| legacy iptables | `waydroid-net.sh` 默认走 `iptables-legacy` 的 nat/mangle 表 |
| Weston (X11 backend) | LXQt 是 X11，Waydroid 需要 Wayland，用嵌套 Weston 提供 |
| waydroid_script | 一键装 Google Play (OpenGApps) + libndk（ARM 翻译，跑 ARM 应用/手游） |

---

## 一、编译内核：启用 Android Binder 与容器网络

### 1.1 问题诊断

自编译的 `7.2.3-rtx3080` 内核在精简配置时把 Android/legacy netfilter 都关掉了：

```bash
# 修改前（源码树 .config）
# CONFIG_ANDROID_BINDER_IPC is not set
# CONFIG_NETFILTER_XTABLES_LEGACY is not set
```

这会导致：

- Waydroid 容器无法启动（找不到 `/dev/binderfs`、`binder`）
- 容器网络初始化失败（`waydroid-net.sh` 优先调用 `iptables-legacy`，而内核只有 nftables 后端）

> 参考：Ubuntu 官方 `6.8.0-generic` 内核同时开启了两者，本机 `/boot/config-6.8.0-142-generic` 可对照。

### 1.2 代码改动

**（1）`lib_kernel_config.sh` 新增两个函数**（放在 `optimize_scheduler_desktop` 之后）：

```bash
# 启用 Android Binder(供 Waydroid 容器化 Android 使用)
enable_waydroid_binder() {
    log_step "  - 启用 Android Binder IPC(Waydroid)"
    set_kconfig CONFIG_ANDROID_BINDER_IPC y
    set_kconfig CONFIG_ANDROID_BINDERFS y
    set_kconfig CONFIG_ANDROID_BINDER_DEVICES ""
}

# 启用 legacy iptables NAT(Waydroid 网络依赖)
enable_waydroid_netfilter() {
    log_step "  - 启用 legacy iptables NAT(Waydroid 网络)"
    set_kconfig CONFIG_NETFILTER_XTABLES_LEGACY y
    set_kconfig CONFIG_IP_NF_IPTABLES_LEGACY m
    set_kconfig CONFIG_IP_NF_FILTER m
    set_kconfig CONFIG_IP_NF_NAT m
    set_kconfig CONFIG_IP_NF_TARGET_MASQUERADE m
    set_kconfig CONFIG_IP_NF_MANGLE m
}
```

**（2）`build_kernel_3080_7.0.sh` 在 `[3/9]` 段调用**（虚拟化配置之后）：

```bash
    # Waydroid 容器化 Android 支持(Binder + legacy iptables NAT)
    log_step "  - 启用 Waydroid 支持"
    enable_waydroid_binder
    enable_waydroid_netfilter
```

### 1.3 关键配置项说明

| 配置项 | 值 | 说明 |
|--------|----|------|
| `CONFIG_ANDROID_BINDER_IPC` | `y` | 7.x 中为 **bool**，只能填 `y`（不能 `m`） |
| `CONFIG_ANDROID_BINDERFS` | `y` | binderfs，按 IPC namespace 动态分配 `/dev/binder*`，Waydroid 依赖 |
| `CONFIG_ANDROID_BINDER_DEVICES` | `""` | 留空统一走 binderfs（与 Ubuntu 官方内核一致，避免静态节点冲突） |
| `CONFIG_NETFILTER_XTABLES_LEGACY` | `y` | **bool**，legacy x_tables 总开关（依赖 `!PREEMPT_RT`，本机为 `PREEMPT` 可开） |
| `CONFIG_IP_NF_IPTABLES_LEGACY` | `m` | legacy IPv4 iptables 核心（`filter`/`nat` 表的前提） |
| `CONFIG_IP_NF_FILTER` | `m` | `-A INPUT/FORWARD -j ACCEPT` 所需的 `filter` 表 |
| `CONFIG_IP_NF_NAT` | `m` | iptables `nat` 表 |
| `CONFIG_IP_NF_TARGET_MASQUERADE` | `m` | `-j MASQUERADE`（容器出网 SNAT） |
| `CONFIG_IP_NF_MANGLE` | `m` | `-t mangle ... -j CHECKSUM`（DHCP 校验和修复） |

Waydroid 还需要的下述项本机配置**已具备**，无需改动：
`CONFIG_PSI`、`CONFIG_CGROUPS`/`MEMCG`、各 namespace、`CONFIG_MEMFD_CREATE`、
`CONFIG_NF_NAT`、`CONFIG_NETFILTER_XT_TARGET_MASQUERADE`、`CONFIG_VETH`、`CONFIG_BRIDGE`、
`CONFIG_NF_TABLES`/`NFT_COMPAT`、`CONFIG_FUSE_FS`、`CONFIG_TMPFS`。
（新内核已移除 `CONFIG_ASHMEM`，Waydroid 改用 memfd，无需配置。）

### 1.4 编译

```bash
# 修改内核配置后需带 --reconfig 才会重跑 [3/9] 段
cd /opt/linux/src/linux-7.2.3
setsid bash /opt/my-shell/build_kernel_3080_7.0.sh --reconfig \
    > /tmp/build_kernel_3080_7.0.log 2>&1 < /dev/null &
tail -f /tmp/build_kernel_3080_7.0.log
```

脚本流程：复制当前内核 config → 重新定制 → `make olddefconfig` → `make -j6` →
`modules_install` → `make install` → initramfs → 重编 NVIDIA DKMS → `update-grub` → 设为默认启动。

- 产出内核版本：`7.2.3-rtx3080-<日期>`，构建于 GRUB，旧内核保留。
- 增量编译约 20–40 分钟（Ryzen 5 3500X 6 线程）。

### 1.5 重启与验证

```bash
sudo reboot
uname -r    # 应为 7.2.3-rtx3080-<新日期>

# 配置项确认
grep -E 'ANDROID_BINDER|NETFILTER_XTABLES_LEGACY|IP_NF_(IPTABLES_LEGACY|FILTER|NAT|TARGET_MASQUERADE|MANGLE)' \
    /boot/config-$(uname -r)

# binderfs 已注册
cat /proc/filesystems | grep binderfs

# legacy iptables 可用（先装 iptables）
sudo apt install -y iptables
sudo modprobe ip_tables iptable_nat iptable_filter iptable_mangle
sudo iptables-legacy -t nat -L -n
```

---

## 二、安装 Waydroid

Ubuntu 24.04 (noble) 不在官方仓库中，需先加第三方源：

```bash
sudo apt install -y curl ca-certificates
curl -s https://repo.waydro.id | sudo bash            # 自动识别失败时追加 -s noble
sudo apt update
sudo apt install -y waydroid
```

初始化（下载 System / Vendor 镜像，约 1GB+）：

```bash
sudo waydroid init                 # vanilla 镜像（本方案用 waydroid_script 装 GApps）
# 或者直接带 GApps： sudo waydroid init -s GAPPS
```

> **坑：init 卡住不动**。`waydroid init` 会优先走 IPv6，而本机 IPv6 有默认路由但实际不通，
> 表现为进程 `SYN-SENT` 挂死（`ss -tnp` 可看到连 `2606:...`）。解决：让 glibc 优先 IPv4：
> ```bash
> echo 'precedence ::ffff:0:0/96  100' | sudo tee -a /etc/gai.conf
> ```
> 之后 `waydroid init` 正常走 IPv4（本机经 Clash TUN）。

启动：

```bash
sudo systemctl enable --now waydroid-container   # 容器服务
# Wayland 环境见第三节，随后：
waydroid session start
waydroid show-full-ui
```

---

## 三、窗口系统适配：Weston 嵌套（X11 → Wayland）

### 3.1 为什么需要

Waydroid 是 Wayland 客户端，**没有 Wayland 合成器就无法显示**。本机 LXQt 是 X11 会话
（`XDG_SESSION_TYPE=x11`，无 `wayland-*` socket）。

选择方案：**在 LXQt 里开一个 Weston 窗口**，Waydroid 显示在窗口内，不影响现有桌面、可随时关闭。

Weston 13（Ubuntu 24.04 仓库版）自带 `x11-backend.so`，可直接嵌套在 X11 中：

```bash
ls /usr/lib/x86_64-linux-gnu/libweston-13/x11-backend.so   # 存在即支持
```

### 3.2 NVIDIA DRM modeset

Waydroid 走 GBM 需要 `nvidia-drm.modeset=1`：

```bash
# /etc/default/grub
GRUB_CMDLINE_LINUX_DEFAULT="btusb.enable_autosuspend=0 nvidia-drm.modeset=1"
sudo update-grub && sudo reboot
cat /sys/module/nvidia_drm/parameters/modeset    # 期望 Y
```

### 3.3 安装 Weston 与启动脚本

```bash
sudo apt install -y weston
```

`/opt/my-shell/3080/weston_waydroid.sh`：

```bash
#!/bin/sh
# 在 X11 (LXQt) 中开一个 Weston 窗口运行 Waydroid
export XDG_RUNTIME_DIR=/run/user/$(id -u)
SOCK=wayland-waydroid

# GL 后端；若黑屏/崩溃改用 --renderer=pixman（软件渲染）
weston --backend=x11 --shell=kiosk \
       --width=1280 --height=1024 --socket="$SOCK" --renderer=gl &
WPID=$!
sleep 2

export WAYLAND_DISPLAY="$SOCK"
waydroid session start &
sleep 3
waydroid show-full-ui

wait $WPID
```

运行：

```bash
chmod +x /opt/my-shell/3080/weston_waydroid.sh
/opt/my-shell/3080/weston_waydroid.sh
```

### 3.4 NVIDIA 兼容性：硬件渲染 vs 软件渲染

Waydroid 官方把 **NVIDIA 列为“不支持的 GPU”**，推荐强制软件渲染。若硬件渲染异常
（黑屏、花屏、启动即崩），改 `/var/lib/waydroid/waydroid.cfg` 的 `[properties]`：

```ini
ro.hardware.gralloc=default
ro.hardware.egl=swiftshader
```

应用并重启：

```bash
sudo waydroid upgrade -o
waydroid session stop && waydroid session start
```

> 说明：本机 NVIDIA 595 + `modeset=1` 可先尝试硬件渲染（性能高）；
> 不稳定就退回 SwiftShader 软件渲染（能跑，但帧率低）。

---

## 四、Google Play + libndk（waydroid_script）

`waydroid_script`（casualsnek）可装 MindTheGapps/OpenGApps、Magisk 以及 libndk/libhoudini ARM 翻译层。

> 下载走外网，本机使用 Clash 混合端口代理：
> ```bash
> export PX=http://127.0.0.1:6880     # 同时支持 socks5h://127.0.0.1:6880
> ```

**准备（只需一次）：**

```bash
sudo apt install -y python3-venv python3-pip git
sudo git clone --depth 1 https://github.com/casualsnek/waydroid_script /opt/waydroid_script
cd /opt/waydroid_script
# root 下建 venv,pip 走代理
sudo env http_proxy=$PX https_proxy=$PX python3 -m venv venv
sudo env http_proxy=$PX https_proxy=$PX venv/bin/pip install -r requirements.txt
```

**安装（需先停会话 / 容器）：**

```bash
waydroid session stop
sudo waydroid container stop

cd /opt/waydroid_script
# -a 13 指定 Android 版本；libndk 为 ARM 翻译层（x86 跑 ARM 应用/手游）
sudo env http_proxy=$PX https_proxy=$PX ./venv/bin/python3 main.py -a 13 install libndk
# Google Play（MindTheGapps）
sudo env http_proxy=$PX https_proxy=$PX ./venv/bin/python3 main.py -a 13 install gapps
# 可选：Magisk root
sudo env http_proxy=$PX https_proxy=$PX ./venv/bin/python3 main.py -a 13 install magisk
```

完成标志：libndk 打印 `libndk installation finished`；gapps 打印 `MindTheGapps installation finished`。
验证（会话起来后）：

```bash
adb -s <IP>:5555 shell pm list packages | grep -E 'vending|gms'
adb -s <IP>:5555 shell getprop ro.dalvik.vm.native.bridge   # libndk_translation.so
```

### Google Play 认证（可选）

未认证设备无法装部分应用。先用 Android ID 在
<https://www.google.com/android/uncertified/> 注册：

```bash
sudo waydroid shell -- sqlite3 \
  /data/data/com.google.android.gsf/databases/gservices.db \
  "select * from main where name='android_id';"
```

---

## 五、ADB 控制 Android 容器

宿主机安装 adb：

```bash
sudo apt install -y adb          # Android Debug Bridge 34.0.4
```

连接（会话运行中才有 IP）：

```bash
# 方式一：官方便捷命令（自动读取容器 IP）
waydroid adb connect

# 方式二：手动
waydroid status | grep 'IP address'      # 例如 192.168.240.112
adb connect 192.168.240.112:5555
adb devices -l
```

首次连接会在 Android 端弹「允许 USB 调试」授权框，点允许即可；或直接点界面确认。
授权后验证：

```bash
adb -s 192.168.240.112:5555 shell getprop ro.build.version.release   # 13
adb -s 192.168.240.112:5555 shell getprop ro.product.model           # WayDroid x86_64 Device
adb -s 192.168.240.112:5555 shell ls /sdcard
adb -s 192.168.240.112:5555 install app.apk
```

> **旁加载 ARM APK**：Waydroid x86_64 靠 libndk 翻译运行 arm64/arm 应用，`adb install` 即可。
> 若报 `INSTALL_FAILED_VERIFICATION_FAILURE: Install not allowed`（Play Protect 包校验拦截），
> 先关校验再装：
> ```bash
> adb shell settings put global verifier_verify_adb_installs 0
> adb shell settings put global package_verifier_enable 0
> adb install -r app.apk
> ```
> 启动用显式 Activity 更可靠（`monkey` 有时不触发）：
> ```bash
> adb shell am start -W -n <包名>/<启动Activity>
> ```

无需 adb 的内置方式（直接进容器 shell / 看日志）：

```bash
sudo waydroid shell getprop ro.product.model
sudo waydroid logcat
```

> 注：`waydroid shell` 不接受 `-c`，多命令请用 `waydroid shell -- sh -c '...'`。

---

## 六、验证与故障排查

| 现象 | 排查 / 解决 |
|------|-------------|
| `Failed to get service 'binder'` / 容器起不来 | 未重启到新内核，或 binder 未生效；`cat /proc/filesystems \| grep binderfs`、`dmesg \| grep -i binder` |
| `waydroid container start` 失败 | `journalctl -u waydroid-container -e` |
| 容器无网络 / DNS 失败 | 确认 legacy iptables 模块已加载：`sudo modprobe ip_tables iptable_nat iptable_filter iptable_mangle`；`sudo iptables-legacy -t nat -L -n`；确认 `dnsmasq` 已装 |
| 虚拟机没声音 | **先查 Android 媒体音量**（最常见）：`adb shell settings get system volume_music_speaker`，过低就用音量键拉满 `for i in $(seq 1 15); do adb shell input keyevent 24; done`。再查宿主 `wpctl status`，播放时应有名为 **Waydroid** 的流且接到你实际在用的 sink。原理：HAL 连容器内 `/run/xdg/pulse/native`（bind 自宿主 `/run/user/1000/pulse/native`）。若 `adb shell getprop init.svc.vendor.audio-hal` 显示 `stopping`（HAL 卡死），`waydroid session stop && sudo waydroid container stop` 后重启会话即可恢复 |
| Wayland 连接失败 `failed to connect to display` | `XDG_RUNTIME_DIR=/run/user/$(id -u)`、`WAYLAND_DISPLAY` 与 Weston `--socket` 一致 |
| NVIDIA 黑屏/花屏 | 用第 3.4 节软件渲染，或 Weston 加 `--renderer=pixman` |
| 硬解/游戏性能差 | 优先硬件渲染；软件渲染仅保证兼容 |
| 日志 `/var/lib/waydroid/waydroid.log` | 详细运行日志 |

常用命令：

```bash
waydroid session start / stop
waydroid show-full-ui
waydroid prop set persist.waydroid.multi_windows true   # 多窗口模式（需重启 session）
sudo waydroid upgrade
```

---

## 附：改动文件与状态

### 改动文件

| 文件 | 改动 |
|------|------|
| `/opt/my-shell/lib_kernel_config.sh` | 新增 `enable_waydroid_binder` / `enable_waydroid_netfilter` |
| `/opt/my-shell/build_kernel_3080_7.0.sh` | `[3/9]` 段调用上述两个函数 |
| `/opt/my-shell/3080/readme.md` | 本文档 |

### 状态

| 步骤 | 状态 |
|------|------|
| 内核配置：Binder + legacy iptables NAT | ✅ 已写入脚本，验证 `.config` 生效 |
| 内核编译 `7.2.3-rtx3080-20261005` | ✅ 完成（2026-10-05 09:31），DKMS 已重编，GRUB 已设默认 |
| 重启并验证内核 | ✅ 新内核运行，binderfs 就绪，legacy iptables 模块可加载 |
| 安装 Waydroid + Weston | ✅ waydroid 1.6.2 + weston 13.0.0 |
| Weston 嵌套运行 Android UI | ✅ LineageOS 20 界面正常显示（GL 硬件渲染） |
| 容器网络 | ✅ IP 192.168.240.112，dnsmasq + waydroid0 正常 |
| ADB 控制 | ✅ adb 34.0.4，已授权，shell/pm/sdcard 可用 |
| 安装 Google Play + libndk | ✅ MindTheGapps + libndk（`ro.dalvik.vm.native.bridge=libndk_translation.so`），Play 可启动 |

> 下载经代理 `http://127.0.0.1:6880`（Clash 混合端口，HTTP/SOCKS 均可）。

> 新内核已验证安装：`/boot/vmlinuz-7.2.3-rtx3080-20261005`、`initrd.img-7.2.3-rtx3080-20261005`、
> `GRUB_DEFAULT="Advanced options for Ubuntu>Ubuntu, with Linux 7.2.3-rtx3080-20261005"`，
> `dkms status` 显示 `nvidia/595.91.07, 7.2.3-rtx3080-20261005: installed`。

### 相关路径

| 路径 | 说明 |
|------|------|
| `/opt/linux/src/linux-7.2.3` | 7.2.3 内核源码（已编译过，支持增量） |
| `/opt/my-shell/build_kernel_3080_7.0.sh` | 内核编译主脚本 |
| `/opt/my-shell/lib_kernel_config.sh` | 内核配置共享库 |
| `/opt/my-shell/3080/weston_waydroid.sh` | Weston 嵌套启动脚本（可执行） |
| `/opt/waydroid_script` | Google Play / libndk 安装脚本（已克隆） |
| `/var/lib/waydroid/waydroid.cfg` | Waydroid 配置（NVIDIA 渲染属性） |
| `/var/lib/waydroid/waydroid.log` | Waydroid 日志 |
