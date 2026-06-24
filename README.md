# 糖小豆

Flutter 语音 AI 聊天应用，面向亲子互动场景。支持语音/文字双模输入，AI 流式回复，TTS 语音播报。

## 功能

- **语音输入** — 按住说话，WebSocket 实时语音识别（ASR）
- **文字输入** — 键盘输入，语音/文字模式一键切换
- **流式对话** — SSE 流式接收 AI 回复，逐字渲染
- **语音播报** — TTS 语音合成，流式播放和整句复播
- **富文本** — Markdown 渲染，支持图片展示和视频播放

## 运行

```bash
# 安装依赖
flutter pub get

# 运行（需要连接设备或模拟器）
flutter run

# 测试
flutter test

# 静态分析
flutter analyze
```

## 架构

```
lib/
├── main.dart                  # 入口，服务初始化
├── theme.dart                 # Material 3 紫色主题
├── models/
│   └── message.dart           # 消息模型
├── screens/
│   └── chat_screen.dart       # 主聊天界面
├── services/
│   ├── llm_service.dart       # SSE 流式 LLM 对话
│   ├── asr_service.dart       # WebSocket 语音识别
│   ├── tts_service.dart       # HTTP TTS 语音合成
│   └── tts_player.dart        # 流式 TTS 播放队列
└── widgets/
    ├── chat_bubble.dart       # 聊天气泡（复制/保存/重播）
    ├── video_player_dialog.dart # 视频播放
    ├── typing_dots.dart       # 输入中动画
    └── voice_input_button.dart # 按住录音按钮
```

## 依赖服务

- **Sophclaw Bot API** — LLM 对话，SSE 流式返回
- **Sophnet** — 语音识别（ASR）和语音合成（TTS）

## 数据流

```
语音输入 → 录音(m4a) → ASR(WebSocket) → 识别文字
                                              ↓
                                     LLM(SSE流式) → 逐字渲染
                                              ↓
                                    TTS(流式合成) → 语音播报
```
