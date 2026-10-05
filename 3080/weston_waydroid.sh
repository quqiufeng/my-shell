#!/bin/sh
# 在 X11 (LXQt) 中开一个 Weston 嵌套窗口运行 Waydroid
# 用法: ./weston_waydroid.sh
set -u

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DISPLAY="${DISPLAY:-:0}"
SOCK="wayland-waydroid"

# 清理残留
pkill -x weston 2>/dev/null || true
waydroid session stop 2>/dev/null || true
sleep 1

# 嵌套 Weston(X11 backend + GL 渲染);黑屏/崩溃可改 --renderer=pixman
weston --backend=x11 --shell=kiosk \
       --width=1280 --height=1024 --socket="$SOCK" --renderer=gl &
WPID=$!
sleep 2

export WAYLAND_DISPLAY="$SOCK"
waydroid session start &
sleep 3
waydroid show-full-ui

wait "$WPID"
