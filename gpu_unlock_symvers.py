#!/usr/bin/env python3
"""从正在运行的内核生成匹配的 Module.symvers。

外部模块(modpost)需要内核导出符号的 CRC 才能完成符号版本校验。自编译内核没有
linux-headers 包，内核树一旦被改过 .config，树里的 Module.symvers 就不可信。
这里直接读运行内核的 __ksymtab/__kcrctab(在 /proc/kcore 里，KASLR 偏移用
/proc/kallsyms 的 _text 与 System.map 校准)，导出全部 EXPORT_SYMBOL 的 CRC。

必须用 root 运行(读 /proc/kcore 和 /proc/kallsyms)。

用法: sudo gpu_unlock_symvers.py <kernel_release> <输出 Module.symvers>
"""

import os
import struct
import sys


def read_map(path):
    table = {}
    with open(path) as f:
        for line in f:
            parts = line.split()
            if len(parts) == 3:
                table[parts[2]] = int(parts[0], 16)
    return table


def main():
    if len(sys.argv) != 3:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2

    kver, out = sys.argv[1], sys.argv[2]
    smap = read_map(f"/boot/System.map-{kver}")

    runtime = {}
    with open("/proc/kallsyms") as f:
        for line in f:
            parts = line.split()
            if len(parts) == 3 and parts[2] in ("_text", "__start___ksymtab", "__stop___ksymtab"):
                runtime[parts[2]] = int(parts[0], 16)

    if not runtime.get("_text"):
        print("错误: /proc/kallsyms 里读不到 _text（需要 root，且 kptr_restrict 不能为 2）",
              file=sys.stderr)
        return 1

    shift = runtime["_text"] - smap["_text"]
    ks_start = runtime["__start___ksymtab"]
    ks_stop = runtime["__stop___ksymtab"]
    crc_start = smap["__start___kcrctab"] + shift
    count = (ks_stop - ks_start) // 12

    fh = open("/proc/kcore", "rb", buffering=0)
    hdr = fh.read(64)
    if hdr[:4] != b"\x7fELF":
        print("错误: /proc/kcore 不是 ELF", file=sys.stderr)
        return 1
    phoff = struct.unpack_from("<Q", hdr, 32)[0]
    phentsize = struct.unpack_from("<H", hdr, 54)[0]
    phnum = struct.unpack_from("<H", hdr, 56)[0]

    segments = []
    fh.seek(phoff)
    for _ in range(phnum):
        ph = fh.read(phentsize)
        p_type, _flags, p_offset, p_vaddr, _paddr, p_filesz, p_memsz, _align = \
            struct.unpack_from("<IIQQQQQQ", ph, 0)
        if p_type == 1 and p_memsz:
            segments.append((p_vaddr, p_memsz, p_offset, p_filesz))

    def read_bytes(addr, size):
        chunks = []
        while size > 0:
            for vaddr, memsz, offset, filesz in segments:
                if vaddr <= addr < vaddr + memsz:
                    avail = min(size, vaddr + memsz - addr, vaddr + filesz - addr)
                    if avail <= 0:
                        raise RuntimeError(f"{addr:#x} 所在页未映射")
                    chunks.append(os.pread(fh.fileno(), avail, offset + (addr - vaddr)))
                    addr += avail
                    size -= avail
                    break
            else:
                raise RuntimeError(f"没有覆盖 {addr:#x} 的 PT_LOAD 段")
        return b"".join(chunks)

    blob = read_bytes(ks_start, 0x400000)
    crc_offset = crc_start - ks_start

    lines = []
    module_layout = None
    for i in range(count):
        _value, name_off, _ns = struct.unpack_from("<iii", blob, i * 12)
        name_at = i * 12 + 4 + name_off
        end = blob.find(b"\x00", name_at)
        if end < 0:
            continue
        name = blob[name_at:end].decode(errors="replace")
        if not name:
            continue
        crc = struct.unpack_from("<I", blob, crc_offset + i * 4)[0]
        lines.append(f"0x{crc:08x}\t{name}\tvmlinux\tEXPORT_SYMBOL\t")
        if name == "module_layout":
            module_layout = crc

    if module_layout is None:
        print("错误: 没有读到 module_layout 的 CRC，提取结果不可信", file=sys.stderr)
        return 1

    with open(out, "w") as f:
        f.write("\n".join(lines) + "\n")

    print(f"已写入 {len(lines)} 个符号到 {out} (module_layout crc=0x{module_layout:08x})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
