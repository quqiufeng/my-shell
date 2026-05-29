#!/bin/bash
# nvcc wrapper: 过滤掉 gcc-13 不兼容的 math flags + 允许不支持的编译器
args=()
for arg in "$@"; do
    case "$arg" in
        -fno-finite-math-only|-fno-unsafe-math-optimizations|-fno-math-errno) continue ;;
        *) args+=("$arg") ;;
    esac
done
exec /data/cuda/bin/nvcc --allow-unsupported-compiler "${args[@]}"
