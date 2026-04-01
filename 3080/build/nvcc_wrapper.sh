#!/bin/bash
args=()
for arg in "$@"; do
    case "$arg" in
        -fno-finite-math-only|-fno-unsafe-math-optimizations|-fno-math-errno) continue ;;
        *) args+=("$arg") ;;
    esac
done
exec /usr/lib/nvidia-cuda-toolkit/bin/nvcc --allow-unsupported-compiler "${args[@]}"
