#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
prompt.py - 调用 img.sh 生成图片并记录提示词

用法:
    python prompt.py [命令] [参数]

命令:
    add <提示词> [宽度] [高度]  - 添加新提示词到队列
    list                        - 查看所有已记录的提示词
    run [编号]                  - 运行指定编号或全部提示词生成图片
    del <编号>                  - 删除指定编号的提示词
    clear                       - 清空所有提示词
    export <文件>               - 导出提示词到文件

示例:
    python prompt.py add "A beautiful sunset" 1920 1080
    python prompt.py add "A cute cat" 512 512
    python prompt.py list
    python prompt.py run        # 运行所有
    python prompt.py run 1      # 运行编号1
"""

import json
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

# 配置文件路径
SCRIPT_DIR = Path(__file__).parent.resolve()
PROMPT_DB = SCRIPT_DIR / "prompts.json"
IMG_SH = SCRIPT_DIR / "3080" / "img.sh"
OUTPUT_DIR = Path.home() / "generated_images"


def load_prompts():
    """加载提示词数据库"""
    if PROMPT_DB.exists():
        with open(PROMPT_DB, "r", encoding="utf-8") as f:
            return json.load(f)
    return []


def save_prompts(prompts):
    """保存提示词数据库"""
    with open(PROMPT_DB, "w", encoding="utf-8") as f:
        json.dump(prompts, f, ensure_ascii=False, indent=2)


def add_prompt(prompt_text, width=None, height=None):
    """添加新提示词"""
    prompts = load_prompts()

    entry = {
        "id": len(prompts) + 1,
        "prompt": prompt_text,
        "width": width or 1280,
        "height": height or 720,
        "negative_prompt": "text, watermark, signature, caption, letters, words, typography, logo, brand name, copyright, subtitle, dialogue, speech bubble, menu, interface, UI, HUD, low quality, blurry, distorted, deformed, ugly, duplicate, bad anatomy, disfigured, poorly drawn face, mutation, mutated, extra limbs, extra fingers, malformed limbs, missing arms, missing legs, extra arms, extra legs, fused fingers, too many fingers, long neck, cross-eyed, mutated hands, polar lowres, bad face, cloned face, cropped, out of frame, oversaturated, overexposed",
        "created_at": datetime.now().isoformat(),
        "generated": False,
        "output_file": None,
    }

    prompts.append(entry)
    save_prompts(prompts)

    print(f"✅ 已添加提示词 #{entry['id']}")
    print(f"   提示词: {prompt_text}")
    print(f"   尺寸: {entry['width']}x{entry['height']}")
    return entry


def list_prompts():
    """列出所有提示词"""
    prompts = load_prompts()

    if not prompts:
        print("📭 提示词库为空")
        return

    print(f"\n{'=' * 80}")
    print(f"{'ID':<5}{'状态':<8}{'尺寸':<12}{'提示词':<50}")
    print(f"{'=' * 80}")

    for p in prompts:
        status = "✅" if p.get("generated") else "⏳"
        size = f"{p['width']}x{p['height']}"
        prompt_short = (
            p["prompt"][:47] + "..." if len(p["prompt"]) > 50 else p["prompt"]
        )
        print(f"{p['id']:<5}{status:<8}{size:<12}{prompt_short}")

    print(f"{'=' * 80}")
    print(f"总计: {len(prompts)} 条提示词")


def run_prompt(prompt_id=None):
    """运行提示词生成图片"""
    prompts = load_prompts()

    if not prompts:
        print("❌ 提示词库为空，请先添加提示词")
        return

    if prompt_id is not None:
        target = [p for p in prompts if p["id"] == prompt_id]
        if not target:
            print(f"❌ 找不到编号 {prompt_id} 的提示词")
            return
        to_run = target
    else:
        to_run = [p for p in prompts if not p.get("generated")]
        if not to_run:
            print("✅ 所有提示词都已生成完毕")
            return

    # 确保输出目录存在
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    for p in to_run:
        print(f"\n{'=' * 60}")
        print(f"🎨 正在生成图片 #{p['id']}")
        print(f"   提示词: {p['prompt']}")
        print(f"   尺寸: {p['width']}x{p['height']}")
        print(f"{'=' * 60}")

        # 生成输出文件名
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        safe_prompt = "".join(c if c.isalnum() else "_" for c in p["prompt"][:30])
        output_file = OUTPUT_DIR / f"{timestamp}_{p['id']}_{safe_prompt}.png"

        # 设置环境变量
        env = os.environ.copy()
        if p.get("negative_prompt"):
            env["NEGATIVE_PROMPT"] = p["negative_prompt"]

        # 调用 img.sh
        cmd = [
            "bash",
            str(IMG_SH),
            p["prompt"],
            str(output_file),
            str(p["width"]),
            str(p["height"]),
        ]

        try:
            result = subprocess.run(cmd, env=env, capture_output=False, text=True)

            if result.returncode == 0:
                p["generated"] = True
                p["output_file"] = str(output_file)
                p["generated_at"] = datetime.now().isoformat()
                save_prompts(prompts)
                print(f"✅ 图片 #{p['id']} 生成成功!")
                print(f"   保存至: {output_file}")
            else:
                print(f"❌ 图片 #{p['id']} 生成失败")

        except Exception as e:
            print(f"❌ 执行出错: {e}")


def delete_prompt(prompt_id):
    """删除提示词"""
    prompts = load_prompts()
    prompts = [p for p in prompts if p["id"] != prompt_id]

    # 重新编号
    for i, p in enumerate(prompts, 1):
        p["id"] = i

    save_prompts(prompts)
    print(f"✅ 已删除提示词 #{prompt_id}")


def clear_prompts():
    """清空所有提示词"""
    if PROMPT_DB.exists():
        PROMPT_DB.unlink()
    print("✅ 已清空所有提示词")


def export_prompts(filename):
    """导出提示词到文件"""
    prompts = load_prompts()

    export_path = Path(filename)
    with open(export_path, "w", encoding="utf-8") as f:
        for p in prompts:
            f.write(f"#{p['id']} [{p['width']}x{p['height']}]")
            if p.get("generated"):
                f.write(f" [已生成: {p.get('output_file', '')}]")
            f.write("\n")
            f.write(f"正向: {p['prompt']}\n")
            if p.get("negative_prompt"):
                f.write(f"负向: {p['negative_prompt']}\n")
            f.write(f"创建: {p['created_at']}\n")
            f.write("-" * 60 + "\n")

    print(f"✅ 已导出 {len(prompts)} 条提示词到: {export_path}")


def interactive_mode():
    """交互模式"""
    print("\n🎨 欢迎使用提示词管理工具")
    print("输入 'help' 查看帮助，'quit' 退出\n")

    while True:
        try:
            cmd = input("prompt> ").strip()
            if not cmd:
                continue

            parts = cmd.split(maxsplit=1)
            action = parts[0].lower()

            if action == "quit" or action == "exit":
                break
            elif action == "help":
                print(__doc__)
            elif action == "list":
                list_prompts()
            elif action == "add":
                if len(parts) < 2:
                    print("❌ 请提供提示词")
                    continue
                args = parts[1].split()
                prompt_text = args[0]
                width = int(args[1]) if len(args) > 1 else None
                height = int(args[2]) if len(args) > 2 else None
                add_prompt(prompt_text, width, height)
            elif action == "run":
                pid = int(parts[1]) if len(parts) > 1 else None
                run_prompt(pid)
            elif action == "del":
                if len(parts) < 2:
                    print("❌ 请提供编号")
                    continue
                delete_prompt(int(parts[1]))
            elif action == "clear":
                clear_prompts()
            elif action == "export":
                if len(parts) < 2:
                    print("❌ 请提供文件名")
                    continue
                export_prompts(parts[1])
            else:
                print(f"❌ 未知命令: {action}")

        except KeyboardInterrupt:
            print("\n👋 再见!")
            break
        except Exception as e:
            print(f"❌ 错误: {e}")


def main():
    if len(sys.argv) < 2:
        interactive_mode()
        return

    command = sys.argv[1].lower()

    if command == "add":
        if len(sys.argv) < 3:
            print("❌ 请提供提示词")
            print("用法: python prompt.py add <提示词> [宽度] [高度]")
            sys.exit(1)

        prompt_text = sys.argv[2]
        width = int(sys.argv[3]) if len(sys.argv) > 3 else None
        height = int(sys.argv[4]) if len(sys.argv) > 4 else None
        add_prompt(prompt_text, width, height)

    elif command == "list":
        list_prompts()

    elif command == "run":
        prompt_id = int(sys.argv[2]) if len(sys.argv) > 2 else None
        run_prompt(prompt_id)

    elif command == "del":
        if len(sys.argv) < 3:
            print("❌ 请提供编号")
            sys.exit(1)
        delete_prompt(int(sys.argv[2]))

    elif command == "clear":
        clear_prompts()

    elif command == "export":
        if len(sys.argv) < 3:
            print("❌ 请提供文件名")
            sys.exit(1)
        export_prompts(sys.argv[2])

    else:
        print(__doc__)


if __name__ == "__main__":
    main()
