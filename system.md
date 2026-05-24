# Ubuntu 24.04 系统初始化配置文档

> **让老机器焕发生机** —— 这是一套为老旧台式机专门优化的配置方案。
>
> 通过定制内核（去掉无用驱动）、轻量级桌面环境（Lubuntu LXQt）以及精简的软件栈，让 Intel 第二代酷睿（i5-2400）+ 12GB DDR3 + 128GB NVMe 的十年老机，运行如飞。

本文档记录了系统安装完成后进行的所有初始化操作，包括中文环境配置、软件安装、卸载无用软件、开发环境搭建等。

---

## 1. 中文语言环境配置

### 1.1 安装中文语言包
```bash
sudo apt install -y language-pack-zh-hans language-pack-zh-hans-base
```

### 1.2 设置中文为系统默认语言
```bash
sudo update-locale LANG=zh_CN.UTF-8 LANGUAGE=zh_CN:zh
```
配置后重启生效。

---

## 2. 中文输入法（IBus）

### 2.1 安装 IBus 和拼音输入法
```bash
sudo apt install -y ibus ibus-libpinyin
```

---

## 3. 中文字体安装

### 3.1 安装中文字体包
```bash
sudo apt install -y fonts-noto-cjk fonts-wqy-zenhei fonts-wqy-microhei \
  xfonts-wqy fonts-arphic-uming fonts-arphic-ukai
```

### 3.2 设置默认字体为中文
创建配置文件 `~/.config/fontconfig/fonts.conf`，内容如下：
- 无衬线（sans-serif）：Noto Sans CJK SC → 文泉驿正黑 → 文泉驿微米黑
- 衬线（serif）：Noto Serif CJK SC → AR PL UMing → AR PL UKai
- 等宽（monospace）：Noto Sans Mono CJK SC → 文泉驿正黑 Mono

刷新字体缓存：
```bash
fc-cache -fv
```

### 3.3 安装更纱黑体（Sarasa Gothic）
等距更纱黑体是 Linux 下最适合编程的等宽中文字体，与 Fira Code 风格统一。

```bash
# 下载并解压到用户字体目录
wget -O /tmp/sarasa-gothic.7z \
  "https://github.com/be5invis/Sarasa-Gothic/releases/download/v1.0.37/Sarasa-TTC-1.0.37.7z"
7z x -o~/.local/share/fonts/sarasa-gothic /tmp/sarasa-gothic.7z
```

安装位置：`~/.local/share/fonts/sarasa-gothic/`

### 3.4 安装霞鹜文楷（LXGW WenKai）
文艺气质的屏幕阅读字体，适合电子书、笔记和长文档。

```bash
# 下载并解压
wget -O /tmp/lxgw-wenkai.tar.gz \
  "https://github.com/lxgw/LxgwWenKai/releases/download/v1.510/lxgw-wenkai-v1.510.tar.gz"
tar -xzf /tmp/lxgw-wenkai.tar.gz -C ~/.local/share/fonts/
```

安装位置：`~/.local/share/fonts/lxgw-wenkai-v1.510/`

### 3.5 设置新字体为系统默认
创建配置文件 `~/.config/fontconfig/conf.d/99-custom-fonts.conf`：

| 类型 | 默认字体 |
|------|----------|
| 无衬线 (sans-serif) | **更纱黑体 SC** — UI/界面 |
| 衬线 (serif) | **霞鹜文楷** — 阅读/文档 |
| 等宽 (monospace) | **等距更纱黑体 SC** — 编程/终端 |

刷新缓存生效：
```bash
rm -rf ~/.cache/fontconfig/* && fc-cache -rv
```

---

## 4. 安装 Lubuntu Desktop（可选）

Lubuntu 是基于 LXQt 的轻量级桌面环境，适合低配置机器。

```bash
sudo apt install -y lubuntu-desktop
```

安装过程中会提示选择**显示管理器**，保持默认的 **SDDM** 即可。

安装完成后重启生效：
```bash
sudo reboot
```

---

## 5. 安装 Google Chrome

```bash
wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo dpkg -i google-chrome-stable_current_amd64.deb
sudo apt --fix-broken install -y
```

---

## 6. 安装微信（WeChat）

```bash
wget https://dldir1.qq.com/weixin/Universal/Linux/WeChatLinux_x86_64.deb
sudo dpkg -i WeChatLinux_x86_64.deb
```

### 6.1 修复依赖问题
微信启动报错缺少 `libatomic.so.1`，需安装：
```bash
sudo apt install -y libatomic1
```

### 6.2 设置微信开机自启动
```bash
mkdir -p ~/.config/autostart
cp /usr/share/applications/wechat.desktop ~/.config/autostart/
```

---

## 7. 安装钉钉（DingTalk）

```bash
wget https://dtapp-pub.dingtalk.com/dingtalk-desktop/xc_dingtalk_update/linux_deb/Release/com.alibabainc.dingtalk_8.1.0.6021101_amd64.deb
sudo dpkg -i com.alibabainc.dingtalk_8.1.0.6021101_amd64.deb
```

---

## 8. 安装 WPS Office

官网地址：[https://linux.wps.cn/](https://linux.wps.cn/)

```bash
wget "https://wps-linux-personal.wpscdn.cn/wps/download/ep/Linux2023/25882/wps-office_12.1.2.25882.AK.preread.sw.Personal_662820_amd64.deb" -O /tmp/wps-office.deb
sudo dpkg -i /tmp/wps-office.deb
sudo apt --fix-broken install -y
```

---

## 9. 安装梯子软件（DigiLink）

DigiLink 代理客户端，支持多种协议。

```bash
# 从官网下载 deb 包
wget https://ice521.com/linux.html -O /tmp/digilink.deb
sudo dpkg -i /tmp/digilink.deb
```

### 9.1 安装依赖库

首次启动可能报错缺少 `libwebkit2gtk-4.1.so.0`，需安装：

```bash
sudo apt install -y libwebkit2gtk-4.1-0 libayatana-appindicator3-1 libssl3
```

### 9.2 修复桌面启动器

安装后桌面文件名称异常，需修复：

```bash
sudo cp /usr/share/applications/.desktop /usr/share/applications/digilink.desktop
sudo rm /usr/share/applications/.desktop
sudo update-desktop-database /usr/share/applications
```

### 9.3 设置开机自启动

```bash
mkdir -p ~/.config/autostart
cp /usr/share/applications/digilink.desktop ~/.config/autostart/
```

### 9.4 启动方式

- 图形界面：在应用菜单搜索 "Digilink"
- 命令行：`digilink`

---

## 10. 卸载无用软件

### 10.1 卸载 Firefox
```bash
sudo apt autoremove -y firefox --purge
# 如为 snap 安装：
sudo snap remove firefox
```

### 10.2 卸载 LibreOffice
```bash
sudo apt autoremove -y libreoffice* --purge
```

---

## 11. 修复显示分辨率

当前分辨率被限制为 640x480，修改为 1920x1080：
```bash
xrandr --output HDMI-1 --mode 1920x1080
```

---

## 12. OpenCode 配置

官网：[https://opencode.ai/](https://opencode.ai/)

### 12.1 安装

```bash
curl -fsSL https://opencode.ai/install | bash
```

### 12.2 主题切换

运行 `/themes` 命令选择喜欢的主题。

推荐主题：**cobalt2** — 深蓝色调，对比度适中，适合长时间使用。

### 12.3 权限配置

参考官方文档：[https://opencode.ai/docs/permissions/](https://opencode.ai/docs/permissions/)

修改 `~/.config/opencode/opencode.jsonc`，放开所有权限（无需二次确认）：

```json
{
  "$schema": "https://opencode.ai/config.json",
  "permission": {
    "*": "allow",
    "external_directory": "allow"
  }
}
```

配置说明：
- `"*": "allow"` — 所有工具（read/edit/bash/grep/webfetch 等）自动执行，无需确认
- `"external_directory": "allow"` — 允许访问工作目录外的所有文件和文件夹，无需确认

**注意**：修改后需重启 opencode 生效。

---

## 13. 开发编译套件

### 13.1 基础编译工具
```bash
sudo apt install -y build-essential cmake make gcc g++ clang \
  gdb lldb git curl wget vim pkg-config autoconf automake libtool
```

### 13.2 Python 开发环境
```bash
sudo apt install -y python3-dev python3-pip python3-venv
```

### 13.3 常用开发库
```bash
sudo apt install -y libssl-dev libffi-dev zlib1g-dev libbz2-dev \
  liblzma-dev libzip-dev libpcre3-dev libpcre2-dev libonig-dev \
  libsqlite3-dev libpq-dev libmysqlclient-dev libcurl4-openssl-dev \
  libjpeg-dev libpng-dev libtiff-dev libwebp-dev libfreetype6-dev \
  libfontconfig1-dev libx11-dev libxext-dev libxrender-dev libxtst-dev \
  libxi-dev libgl1-mesa-dev libglu1-mesa-dev libglew-dev libsdl2-dev \
  libpulse-dev libasound2-dev libsndfile1-dev libavcodec-dev \
  libavformat-dev libavutil-dev libswscale-dev libswresample-dev \
  libopencv-dev libboost-all-dev libeigen3-dev libhdf5-dev \
  libnetcdf-dev libprotobuf-dev protobuf-compiler libgrpc++-dev \
  libnanomsg-dev libzmq3-dev libevent-dev libuv1-dev libnghttp2-dev \
  libidn2-dev librtmp-dev libssh2-1-dev libpsl-dev libbrotli-dev
```

---

## 14. 视频解码器安装

### 14.1 核心解码库
```bash
sudo apt install -y ffmpeg libavcodec-extra vlc libmpv2 mpv \
  gstreamer1.0-libav gstreamer1.0-plugins-good \
  gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly \
  gstreamer1.0-vaapi libdvdnav4 libdvdread8 libbluray2 libaacs0
```

### 14.2 视频下载工具
```bash
sudo apt install -y yt-dlp
```

---

## 15. 时间同步配置

### 15.1 设置时区为北京时间
```bash
sudo timedatectl set-timezone Asia/Shanghai
```

### 15.2 启用 NTP 自动同步
```bash
sudo timedatectl set-ntp true
```

### 15.3 配置国内 NTP 服务器
系统默认已启用 systemd-timesyncd，如需切换为国内 NTP 服务器：

```bash
sudo tee /etc/systemd/timesyncd.conf <<EOF
[Time]
NTP=ntp.aliyun.com ntp1.aliyun.com ntp.tencent.com time1.cloud.tencent.com
FallbackNTP=time.asia.apple.com time.windows.com
EOF
sudo systemctl restart systemd-timesyncd
```

验证时间同步状态：
```bash
timedatectl status
```

---

## 16. LVM 磁盘扩容

系统安装后，LVM 逻辑卷默认只使用了约一半磁盘空间。以下是将根分区扩展到使用全部可用空间的操作。

### 16.1 查看当前磁盘和 LVM 状态

```bash
# 查看物理卷
sudo pvs

# 查看卷组
sudo vgs

# 查看逻辑卷
sudo lvs

# 查看文件系统使用
sudo df -h /
```

**初始状态示例**：
```
PV 总容量:     116.19 GB
逻辑卷已分配:   58.09 GB  ← 根分区 /
空闲未分配:     58.09 GB  ← 还有一半没用到
```

### 16.2 扩展逻辑卷到全部空间

```bash
sudo lvextend -l +100%FREE -r /dev/mapper/ubuntu--vg-ubuntu--lv
```

参数说明：
- `-l +100%FREE`：使用卷组中所有剩余空闲空间
- `-r`：同时扩展文件系统（resize2fs/xfs_growfs）
- `/dev/mapper/ubuntu--vg-ubuntu--lv`：逻辑卷设备路径

### 16.3 验证扩容结果

```bash
sudo lvs
sudo df -h /
```

**扩容后状态**：
```
逻辑卷: 58 GB → 116 GB（使用卷组全部剩余空间）
文件系统: 在线调整完成，无需重启
根分区 /: 57 GB → 115 GB，可用 95 GB
```

### 16.4 操作前注意事项

- **先备份重要数据**：虽然 LVM 在线扩容风险很低，但建议先备份
- **确认卷组有空闲空间**：`sudo vgs` 查看 VFree 列
- **-r 参数很重要**：它会在扩展 LV 后自动扩展文件系统，否则需要手动运行 `resize2fs`
- **支持在线扩容**：无需卸载分区或重启系统

---

## 17. sudo 免密码配置

### 17.1 配置当前用户免密码 sudo

创建 sudoers 配置文件：

```bash
printf 'qqf332\n' | sudo -S bash -c 'echo "quqiufeng ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers.d/quqiufeng && chmod 440 /etc/sudoers.d/quqiufeng'
```

### 17.2 验证配置

```bash
sudo -n whoami
# 输出: root  （不提示密码即表示成功）
```

### 17.3 配置文件说明

- 文件位置：`/etc/sudoers.d/quqiufeng`
- 权限：`-r--r-----` (440)
- 内容：`quqiufeng ALL=(ALL:ALL) NOPASSWD:ALL`

**注意**：免密码 sudo 仅适用于当前用户 `quqiufeng`，其他用户仍需密码。

---

## 18. 系统清理

### 18.1 清理 apt 缓存
```bash
sudo apt-get clean
sudo apt-get autoclean
```

### 18.2 清理已下载的安装包
```bash
rm -f /tmp/google-chrome-stable_current_amd64.deb
rm -f /tmp/wechat.deb
```

---

## 19. 定制内核编译（可选）

根据本机硬件专门编译内核，去掉不需要的驱动，系统更轻量、响应更快。

### 19.1 本机硬件

- CPU: Intel Core i5-2400 (Sandy Bridge)
- 显卡: Intel HD Graphics 2000（集成显卡）
- 存储: Samsung 128GB NVMe SSD
- 内存: 12GB DDR3
- 网络: Realtek RTL8111/8168 PCI-E 千兆网卡（有线）

### 19.2 精简内容

- 移除所有无线驱动（Wi-Fi、蓝牙、NFC）
- 移除不需要的总线驱动（Infiniband、FireWire、Thunderbolt、PCMCIA）
- 移除嵌入式 SoC 驱动
- 开启 `PREEMPT_DYNAMIC` 动态抢占，提升桌面响应
- 使用 zstd 压缩内核

### 19.3 编译脚本

完整编译记录和脚本：`~/my-shell/build_kernel.sh`

```bash
# 查看当前内核版本
uname -r
# 输出: 6.8.12-custom-20260523
```

---

## 20. 已安装软件清单

| 类别 | 软件 |
|------|------|
| 浏览器 | Google Chrome |
| 输入法 | IBus + 智能拼音 |
| 桌面环境 | Lubuntu Desktop (LXQt) |
| 通讯 | 微信 (WeChat), 钉钉 (DingTalk) |
| 办公软件 | WPS Office |
| 网络工具 | DigiLink（梯子） |
| 视频播放 | VLC, MPV, FFmpeg |
| 编译器 | GCC 13, G++ 13, Clang 18 |
| 构建工具 | CMake 3.28, Make, Autotools |
| 调试器 | GDB 15.1, LLDB |
| 开发库 | Boost, OpenCV, Eigen3, HDF5, NetCDF, Protobuf, gRPC, ZeroMQ |
| 字体 | **更纱黑体 SC** (Sarasa Gothic), **霞鹜文楷** (LXGW WenKai), Noto CJK, 文泉驿, AR PL |

---

## 21. Snap 完全移除与桌面修复

### 21.1 系统调研

本机系统概况：
- **OS**: Ubuntu 24.04.4 LTS (Noble)
- **内核**: Linux 6.8.12-custom-20260523 (自定义编译)
- **桌面**: LXQt 1.4.0 (Lubuntu 24.04.10)
- **显示**: X11
- **硬件**: Intel Core i5-2400 / 12GB DDR3 / 115GB 根分区

当时已安装的 snap 包：
| 包名 | 类型 | 状态 |
|------|------|------|
| bare | 基础包 | 无应用使用 |
| core24 | Ubuntu 24.04 运行时 | 无应用使用 |
| gnome-46-2404 | GNOME 运行时 | 无应用使用 |
| gtk-common-themes | GTK 主题 | 无应用使用 |
| mesa-2404 | Mesa 图形驱动 | 无应用使用 |
| snapd | snap 守护进程 | 系统核心 |

**关键发现**：之前安装过 firefox snap，但已被移除（`snap changes` 确认）。当前无任何 snap 应用连接这些运行时，共占用约 150MB+ 空间但完全闲置。

### 21.2 卸载所有 snap 包

```bash
# 按依赖顺序逐个卸载（gtk-common-themes 依赖 bare）
sudo snap remove --purge gtk-common-themes
sudo snap remove --purge gnome-46-2404
sudo snap remove --purge mesa-2404
sudo snap remove --purge bare
sudo snap remove --purge core24
sudo snap remove --purge snapd
```

### 21.3 移除 snapd deb 包

```bash
# 停止 snapd 相关服务
sudo systemctl stop snapd.socket snapd.service snapd.seeded.service snapd.apparmor.service
sudo systemctl disable snapd.socket snapd.service snapd.seeded.service snapd.apparmor.service

# 通过 apt 移除
sudo apt remove --purge snapd -y
```

移除过程中连带卸载了 `ubuntu-server-minimal` 元包。

### 21.4 问题：分辨率回退到 640x480

移除 snapd 后重新登录，桌面分辨率从 1920x1080 回退到 **640x480**。

**根因分析**：
1. `snapd` 被 `ubuntu-server-minimal` 依赖，移除 snapd 连带移除了该元包
2. `ubuntu-server-minimal` 依赖 `ubuntu-drivers-common`（显卡驱动管理工具）
3. 移除后触发了显示配置的重新初始化
4. LXQt 显示器配置 (`~/.config/lxqt/lxqt-config-monitor.conf`) 原本就是空的，没有保存过分辨率设置
5. X11 回退到安全默认分辨率 640x480

### 21.5 修复：创建登录自动设置分辨率

**临时恢复**（立即生效）：
```bash
xrandr --output HDMI-1 --mode 1920x1080
```

**永久修复**（登录自动设置）：
```bash
mkdir -p ~/.config/autostart
cat > ~/.config/autostart/screen-resolution.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=Set Screen Resolution
Exec=xrandr --output HDMI-1 --mode 1920x1080
Hidden=false
X-LXQt-Need-Tray=false
NoDisplay=true
EOF
```

### 21.6 清理残留

```bash
# 清理不再需要的依赖
sudo apt autoremove -y

# 清理 apt 缓存
sudo apt-get clean
```

---

*文档更新：2026-05-24*
