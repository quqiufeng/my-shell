#!/bin/bash
#
# =============================================================================
# WSL2 Ubuntu 系统初始化脚本
# 基于 system.md 适配，去掉物理机专属配置
# =============================================================================

set -e

echo "========================================"
echo "WSL2 Ubuntu 初始化部署"
echo "========================================"

# ============================================================================
# 1. 中文语言环境
# ============================================================================
echo "[1/10] 配置中文环境..."
sudo apt update
sudo apt install -y language-pack-zh-hans language-pack-zh-hans-base
sudo update-locale LANG=zh_CN.UTF-8 LANGUAGE=zh_CN:zh

# ============================================================================
# 2. 中文输入法 (IBus)
# ============================================================================
echo "[2/10] 安装中文输入法..."
sudo apt install -y ibus ibus-libpinyin

# ============================================================================
# 3. 中文字体
# ============================================================================
echo "[3/10] 安装中文字体..."
sudo apt install -y fonts-noto-cjk fonts-wqy-zenhei fonts-wqy-microhei \
  xfonts-wqy fonts-arphic-uming fonts-arphic-ukai

# 安装更纱黑体
if [ ! -d "$HOME/.local/share/fonts/sarasa-gothic" ]; then
    echo "  下载更纱黑体..."
    wget -q --show-progress -O /tmp/sarasa-gothic.7z \
      "https://github.com/be5invis/Sarasa-Gothic/releases/download/v1.0.37/Sarasa-TTC-1.0.37.7z"
    mkdir -p ~/.local/share/fonts/sarasa-gothic
    7z x -o~/.local/share/fonts/sarasa-gothic /tmp/sarasa-gothic.7z > /dev/null
fi

# 安装霞鹜文楷
if [ ! -d "$HOME/.local/share/fonts/lxgw-wenkai" ]; then
    echo "  下载霞鹜文楷..."
    wget -q --show-progress -O /tmp/lxgw-wenkai.tar.gz \
      "https://github.com/lxgw/LxgwWenKai/releases/download/v1.510/lxgw-wenkai-v1.510.tar.gz"
    mkdir -p ~/.local/share/fonts/lxgw-wenkai
    tar -xzf /tmp/lxgw-wenkai.tar.gz -C ~/.local/share/fonts/lxgw-wenkai --strip-components=1
fi

# 刷新字体缓存
rm -rf ~/.cache/fontconfig/* && fc-cache -rv > /dev/null 2>&1

# ============================================================================
# 4. Google Chrome
# ============================================================================
echo "[4/10] 安装 Google Chrome..."
if ! command -v google-chrome &> /dev/null; then
    wget -q --show-progress https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -O /tmp/chrome.deb
    sudo dpkg -i /tmp/chrome.deb || sudo apt --fix-broken install -y
    rm -f /tmp/chrome.deb
fi

# ============================================================================
# 5. 微信
# ============================================================================
echo "[5/10] 安装微信..."
if ! command -v wechat &> /dev/null; then
    wget -q --show-progress https://dldir1.qq.com/weixin/Universal/Linux/WeChatLinux_x86_64.deb -O /tmp/wechat.deb
    sudo dpkg -i /tmp/wechat.deb
    sudo apt install -y libatomic1
    rm -f /tmp/wechat.deb
fi

# ============================================================================
# 6. 钉钉
# ============================================================================
echo "[6/10] 安装钉钉..."
if ! command -v com.alibabainc.dingtalk &> /dev/null; then
    wget -q --show-progress \
      https://dtapp-pub.dingtalk.com/dingtalk-desktop/xc_dingtalk_update/linux_deb/Release/com.alibabainc.dingtalk_8.1.0.6021101_amd64.deb \
      -O /tmp/dingtalk.deb
    sudo dpkg -i /tmp/dingtalk.deb || sudo apt --fix-broken install -y
    rm -f /tmp/dingtalk.deb
fi

# ============================================================================
# 7. WPS Office
# ============================================================================
echo "[7/10] 安装 WPS Office..."
if ! command -v wps &> /dev/null; then
    wget -q --show-progress \
      "https://wps-linux-personal.wpscdn.cn/wps/download/ep/Linux2023/25882/wps-office_12.1.2.25882.AK.preread.sw.Personal_662820_amd64.deb" \
      -O /tmp/wps.deb
    sudo dpkg -i /tmp/wps.deb || sudo apt --fix-broken install -y
    rm -f /tmp/wps.deb
fi

# ============================================================================
# 8. 开发工具链
# ============================================================================
echo "[8/10] 安装开发工具链..."
sudo apt install -y \
  build-essential cmake make gcc g++ clang gdb lldb git curl wget vim \
  pkg-config autoconf automake libtool python3-dev python3-pip python3-venv \
  libssl-dev libffi-dev zlib1g-dev libbz2-dev liblzma-dev libzip-dev \
  libpcre3-dev libpcre2-dev libonig-dev libsqlite3-dev libpq-dev \
  libcurl4-openssl-dev libjpeg-dev libpng-dev libtiff-dev libwebp-dev \
  libfreetype6-dev libfontconfig1-dev libx11-dev libxext-dev libxrender-dev \
  libxtst-dev libxi-dev libgl1-mesa-dev libglu1-mesa-dev libglew-dev \
  libsdl2-dev libpulse-dev libasound2-dev libsndfile1-dev libvulkan-dev

# ============================================================================
# 9. 视频解码器
# ============================================================================
echo "[9/10] 安装视频解码器..."
sudo apt install -y \
  ffmpeg libavcodec-extra vlc libmpv2 mpv \
  gstreamer1.0-libav gstreamer1.0-plugins-good \
  gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly

# ============================================================================
# 10. 其他工具
# ============================================================================
echo "[10/10] 安装其他工具..."
sudo apt install -y yt-dlp htop neofetch tree

# 时区设置
sudo timedatectl set-timezone Asia/Shanghai
sudo timedatectl set-ntp true

echo ""
echo "========================================"
echo "部署完成！"
echo "========================================"
echo ""
echo "已安装："
echo "  浏览器: Google Chrome"
echo "  输入法: IBus + 拼音"
echo "  通讯: 微信, 钉钉"
echo "  办公: WPS Office"
echo "  开发: GCC, Clang, Python3, Git, CMake"
echo "  媒体: FFmpeg, VLC, MPV"
echo "  字体: 更纱黑体, 霞鹜文楷, Noto CJK"
echo ""
echo "需要重新登录或运行: source ~/.profile"
echo "GUI 程序将通过 WSLg 显示在 Windows 桌面上"
echo "========================================"
