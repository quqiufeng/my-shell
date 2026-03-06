#!/bin/bash
# CosyVoice 测试脚本 - Fun-CosyVoice3-0.5B
# 测试各种语音合成功能

set -e

source ~/anaconda3/etc/profile.d/conda.sh
conda activate cosyvoice

cd ~/CosyVoice

echo "========================================"
echo "CosyVoice 功能测试 - Fun-CosyVoice3-0.5B"
echo "========================================"

# 测试1: zero_shot - 零样本语音克隆
# 原理: 使用参考音频的音色，生成新文本的语音
# 参数: text(要生成的文本), prompt_text(参考文本), prompt_wav(参考音频)
echo ""
echo "=== 测试1: zero_shot 零样本语音克隆 ==="
python -c "
import sys
sys.path.append('third_party/Matcha-TTS')
from cosyvoice.cli.cosyvoice import AutoModel
import torchaudio

cosyvoice = AutoModel(model_dir='pretrained_models/Fun-CosyVoice3-0.5B')
# 注意: prompt_text 需要包含 <|endofprompt|> 分隔符
for i, j in enumerate(cosyvoice.inference_zero_shot(
    '今天天气真不错，我们出去走走吧。',
    '希望你以后能够做的比我还好呦。<|endofprompt|>',  # prompt_text 需要足够长
    './asset/zero_shot_prompt.wav',
    stream=False)):
    torchaudio.save('/tmp/cosyvoice_test1_zero_shot.wav', j['tts_speech'], cosyvoice.sample_rate)
    print('Saved: /tmp/cosyvoice_test1_zero_shot.wav')
"

# 测试2: cross_lingual - 跨语言合成
# 原理: 使用语言标签 <|zh|><|en|><|ja|> 等指定语言，用参考音频的音色生成其他语言的语音
# 适用场景: 让中文音色说英文、日文等
echo ""
echo "=== 测试2: cross_lingual 跨语言合成 ==="
python -c "
import sys
sys.path.append('third_party/Matcha-TTS')
from cosyvoice.cli.cosyvoice import AutoModel
import torchaudio

cosyvoice = AutoModel(model_dir='pretrained_models/Fun-CosyVoice3-0.5B')
# 语言标签: <|zh|>中文 <|en|>英文 <|ja|>日文 <|yue|>粤语 <|ko|>韩文
# prompt 需要包含 <|endofprompt|>
for i, j in enumerate(cosyvoice.inference_cross_lingual(
    '<|en|>Hello, this is a test of cross-lingual speech synthesis.',
    './asset/zero_shot_prompt.wav',
    stream=False)):
    torchaudio.save('/tmp/cosyvoice_test2_cross_lingual.wav', j['tts_speech'], cosyvoice.sample_rate)
    print('Saved: /tmp/cosyvoice_test2_cross_lingual.wav')
"

# 测试3: instruct2 - 指令控制
# 原理: 通过自然语言指令控制语速、方言、情感等
# 支持指令: 请用XX话说、请慢/快说、大声/小声说等
echo ""
echo "=== 测试3: instruct2 指令控制 ==="
python -c "
import sys
sys.path.append('third_party/Matcha-TTS')
from cosyvoice.cli.cosyvoice import AutoModel
import torchaudio

cosyvoice = AutoModel(model_dir='pretrained_models/Fun-CosyVoice3-0.5B')
# 用自然语言指令控制: 方言、语速、情感等
for i, j in enumerate(cosyvoice.inference_instruct2(
    '今天天气真不错。',
    'You are a helpful assistant. 请用四川话表达。<|endofprompt|>',
    './asset/zero_shot_prompt.wav',
    stream=False)):
    torchaudio.save('/tmp/cosyvoice_test3_instruct_sichuan.wav', j['tts_speech'], cosyvoice.sample_rate)
    print('Saved: /tmp/cosyvoice_test3_instruct_sichuan.wav')

# 指令控制 - 语速
for i, j in enumerate(cosyvoice.inference_instruct2(
    '今天天气真不错。',
    'You are a helpful assistant. 请用尽可能快地语速说一句话。<|endofprompt|>',
    './asset/zero_shot_prompt.wav',
    stream=False)):
    torchaudio.save('/tmp/cosyvoice_test3_instruct_fast.wav', j['tts_speech'], cosyvoice.sample_rate)
    print('Saved: /tmp/cosyvoice_test3_instruct_fast.wav')
"

# 测试4: fine_grained_control - 细粒度控制
# 原理: 控制呼吸声 [breath]、笑声 <laughter></laughter>、重音 <strong></strong> 等
echo ""
echo "=== 测试4: fine_grained_control 细粒度控制 ==="
python -c "
import sys
sys.path.append('third_party/Matcha-TTS')
from cosyvoice.cli.cosyvoice import AutoModel
import torchaudio

cosyvoice = AutoModel(model_dir='pretrained_models/Fun-CosyVoice3-0.5B')
# 细粒度控制标记:
# [breath] - 呼吸声
# <laughter></laughter> - 笑声
# <strong></strong> - 重音
for i, j in enumerate(cosyvoice.inference_cross_lingual(
    '<|zh|>在他讲述那个故事的过程中，他突然[laughter]停下来，因为他自己也被逗笑了[laughter]。',
    './asset/zero_shot_prompt.wav',
    stream=False)):
    torchaudio.save('/tmp/cosyvoice_test4_laughter.wav', j['tts_speech'], cosyvoice.sample_rate)
    print('Saved: /tmp/cosyvoice_test4_laughter.wav')

for i, j in enumerate(cosyvoice.inference_cross_lingual(
    '<|zh|>因为他们那一辈人在乡里面住的要习惯一点，[breath]邻居都很活络，[breath]嗯，都很熟悉。[breath]',
    './asset/zero_shot_prompt.wav',
    stream=False)):
    torchaudio.save('/tmp/cosyvoice_test4_breath.wav', j['tts_speech'], cosyvoice.sample_rate)
    print('Saved: /tmp/cosyvoice_test4_breath.wav')
"

# 测试5: 保存音色供后续使用
# 原理: 将参考音频的音色特征保存为 ID，后续直接使用无需再提供音频
echo ""
echo "=== 测试5: 保存音色 (add_zero_shot_spk) ==="
python -c "
import sys
sys.path.append('third_party/Matcha-TTS')
from cosyvoice.cli.cosyvoice import AutoModel
import torchaudio

cosyvoice = AutoModel(model_dir='pretrained_models/Fun-CosyVoice3-0.5B')

# 保存音色到文件
result = cosyvoice.add_zero_shot_spk(
    '希望你以后能够做的比我还好呦。',
    './asset/zero_shot_prompt.wav',
    'my_saved_voice')
print(f'Save result: {result}')

# 使用保存的音色 (无需再提供音频文件)
for i, j in enumerate(cosyvoice.inference_zero_shot(
    '今天天气真好。',
    '',  # 不需要提供 prompt_text
    '',  # 不需要提供 prompt_wav
    zero_shot_spk_id='my_saved_voice',
    stream=False)):
    torchaudio.save('/tmp/cosyvoice_test5_saved_voice.wav', j['tts_speech'], cosyvoice.sample_rate)
    print('Saved: /tmp/cosyvoice_test5_saved_voice.wav')

# 保存到文件供后续使用
cosyvoice.save_spkinfo()
print('Speaker info saved!')
"

echo ""
echo "========================================"
echo "测试完成! 生成的文件在 /tmp/cosyvoice_test*.wav"
echo "========================================"
ls -lh /tmp/cosyvoice_test*.wav
