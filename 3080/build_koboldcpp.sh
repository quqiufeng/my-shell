#!/bin/bash
set -e

echo "=== 编译 koboldcpp (CUDA 版本 for RTX 3080) ==="
echo ""

cd /opt/koboldcpp

echo "=== 清理旧的编译文件 ==="
make clean 2>/dev/null || true
rm -f *.so *.o

cat > /opt/koboldcpp/nvcc_wrapper.sh << 'WRAPPER'
#!/bin/bash
args=()
for arg in "$@"; do
    case "$arg" in
        -fno-finite-math-only|-fno-unsafe-math-optimizations|-fno-math-errno) continue ;;
        *) args+=("$arg") ;;
    esac
done
exec /usr/lib/nvidia-cuda-toolkit/bin/nvcc --allow-unsupported-compiler "${args[@]}"
WRAPPER
chmod +x /opt/koboldcpp/nvcc_wrapper.sh
mkdir -p /opt/koboldcpp_nvcc_path
ln -sf /opt/koboldcpp/nvcc_wrapper.sh /opt/koboldcpp_nvcc_path/nvcc

echo ""
echo "=== 开始编译 (CUDA/cuBLAS for RTX 3080) ==="
echo "架构: CUDA 8.6 (RTX 3080)"
echo "使用 CUDA 12 nvcc + wrapper (绕过 GCC 13 兼容性检查)"
echo "这可能需要 10-20 分钟..."
echo ""

PATH="/opt/koboldcpp_nvcc_path:$PATH" make -j$(nproc) LLAMA_CUBLAS=1 CUDA_ARCHITECTURES=86 koboldcpp_cublas

echo ""
echo "=== 编译完成 ==="
echo ""

if [ -f "koboldcpp_cublas.so" ]; then
    echo "✓ koboldcpp_cublas.so 生成成功 (CUDA 版本)"
    ls -lh koboldcpp_cublas.so
    echo ""
    echo "文件大小:"
    du -h koboldcpp_cublas.so
else
    echo "✗ 编译失败，未找到 koboldcpp_cublas.so"
    exit 1
fi

echo ""
echo "使用方法:"
echo "  cd /opt/koboldcpp"
echo "  /usr/bin/python3 koboldcpp.py --model /path/to/model.gguf --port 11434 --usecublas --nomodel"
echo ""
echo "或使用启动脚本:"
echo "  cd /opt/my-shell/3080"
echo "  ./run_qwen2.5-coder32b_koboldcpp.sh"