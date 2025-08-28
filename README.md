# VLM-dev

一个视觉语言模型（VLM）项目，包含 iOS 本地演示与 Python 推理/服务。

## iOS 真机运行
1. 用 Xcode 打开 `ml-fastvlm/app/FastVLM.xcodeproj`
2. 选择你的 iPhone 设备，设置签名团队（Team）
3. 直接运行（Cmd+R）

## Python 推理（可选）
```bash
cd ml-fastvlm
python3 -m venv .venv && source .venv/bin/activate
pip install -e .
python predict.py
```

## 目录
- `ml-fastvlm/app/FastVLM App`: SwiftUI iOS/macOS 应用
- `ml-fastvlm/llava`: Python LLaVA 实现
- `.github/workflows`: CI/Release 配置（默认手动触发）
