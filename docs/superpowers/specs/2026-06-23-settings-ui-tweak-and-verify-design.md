# Settings UI 微调 + 保存验证流程设计

**日期**：2026-06-23
**分支**：feature/tts-avatar-messages
**前置**：2026-06-23-settings-page-design.md 已实现（Task 1-8 完成，Task 9 验证中）

## 背景

设置页第一版可用，但需要三项改进：
1. Bot-API 凭证不应允许手动输入，避免用户拼错 streamUrl/apiSecret；只接受粘贴/扫码
2. API Key 需要明暗切换，避免肩窥
3. 保存时直接进聊天页风险大——配置错时用户要进聊天页才发现报错。保存时跑一次端到端验证，通过才进入。

## 决策

| 维度 | 决策 |
|---|---|
| Bot-API 输入方式 | 只能粘贴 base64 或扫二维码，不允许手输 |
| Bot-API 凭证显示 | 脱敏原始 base64：`first5***last5`（不分别显示 streamUrl/apiSecret） |
| API Key 显示 | TextField 可编辑、默认 obscure、小眼睛按下显示 |
| API Key 标题 | 去掉 "API Key" 小标题 |
| 验证触发 | 保存按钮按下时，先验证再保存 |
| 验证内容 | Bot-API（收到 token 即通过）、TTS（返回非空字节）、ASR（返回非空文本，依赖 TTS 音频） |
| 验证并行 | Bot-API 与 TTS 并行；ASR 在 TTS 通过后串行 |
| ASR 音频格式 | `format=mp3`（TTS 输出 MP3 16kHz mono 128kbps） |
| 验证失败 | 不保存，留在设置页，显示哪些项失败 |
| 超时 | Bot-API 15s、TTS 15s、ASR 10s |

## UI 改动

**Bot-API 段**
- 不可手动输入。只有 `粘贴凭证` 和 `扫描二维码` 两个按钮
- 成功后显示一行只读文本：`eyJhZ***ifQ==`（原始 base64 首5位 + `***` + 末5位）
- 未配置过则显示占位 `—`
- 凭证显示函数 `maskBase64(raw)`:
  - 长度 ≤ 13：直接 `***`（首5+末5=10位需要原始至少 13 位才有意义遮蔽中间）
  - 长度 > 13：`'${raw.substring(0,5)}***${raw.substring(raw.length-5)}'`

**ASR / TTS API Key 段**
- TextField 可编辑、默认 `obscureText: true`
- TextField `suffixIcon` 是一个 `GestureDetector` 包 `Icon(Icons.visibility_off)` / `Icons.visibility`
  - `onTapDown` → `setState(_apiKeyObscured = false)`
  - `onTapUp` / `onTapCancel` → `setState(_apiKeyObscured = true)`
- 去掉 "API Key" 小标题（直接 TextField）

**TTS 音色段、TTS 播放开关段**：保持不变。

## 保存验证流程

### 触发

用户点保存按钮 → `_save()` 重构：

```
1. setState(_busy = true, _verifyError = null)
2. 解析 _botApiBase64 得到 streamUrl + apiSecret
3. 构造 AppConfig(streamUrl, apiSecret, apiKey, voice, ttsEnabled)
4. 并行 Future.wait([_testBotApi(cfg), _testTts(cfg)])
5. 若 TTS 通过，串行 _testAsr(cfg, ttsBytes)
6. 收集失败项：
   - 全过：settingsService.save(cfg) → 现有"跳转或等待 BellaApp 重建"逻辑
   - 有失败：setState(_verifyError = 'X、Y 不可用') → SnackBar
7. setState(_busy = false)
```

### 测试函数

```dart
Future<bool> _testBotApi(AppConfig cfg);              // true=通过
Future<List<int>?> _testTts(AppConfig cfg);          // null=失败；非空=通过并返回 mp3 字节
Future<bool> _testAsr(AppConfig cfg, List<int> mp3);  // true=通过
```

**Bot-API 测试**
- 构造临时 `LlmService(config: LlmConfig(streamUrl, apiSecret))`
- 调 `chat(senderId='settings-verify', '你好')`，监听 Stream
- 收到第一个非空 content token → 立即调 `chat(senderId, '/hardstop')` 取消流，返回 `true`
- 用 `Future.timeout(Duration(seconds: 15))` 包裹；超时返回 `false`
- try/catch 捕获 HttpException/DioException，返回 `false`

**TTS 测试**
- 构造临时 `TtsService(apiKey: cfg.asrTtsApiKey, voice: cfg.ttsVoice)`
- 调 `synthesize('你好')`
- 返回字节列表非空 → 返回字节
- 异常或 `Future.timeout(15s)` → 返回 `null`

**ASR 测试**（仅在 TTS 通过后跑）
- 构造临时 `AsrService(apiKey: cfg.asrTtsApiKey)`
- 把 TTS 的 MP3 字节通过 `Stream.fromIterable([bytes])` 喂进 `recognize(stream, format: 'mp3')`
- ASR 返回非空字符串 → 返回 `true`
- 返回空或 `Future.timeout(10s)` → 返回 `false`

### 为什么用临时 service

`main.dart` 的 service 是用当前已保存的 cfg 构造的，但用户保存前的新 cfg 还没写入。验证时用临时 service 测，验证通过才 save。避免污染 ChatScreen 状态、也避免验证中调用挂掉正在跑的 ChatScreen 业务。

### 失败处理

| 情况 | 行为 |
|---|---|
| 全部通过 | 调 `settingsService.save(cfg)` → 现有"非首启则 pop，首启等重建"逻辑 |
| Bot-API 失败 | `_verifyError = 'Bot-API 不可用'` |
| TTS 失败 | `_verifyError = 'TTS 不可用'` |
| ASR 失败 | `_verifyError = 'ASR 不可用'` |
| 多个失败 | 全部用顿号分隔：`'Bot-API、TTS 不可用'` |

不保存，用户留在设置页可重粘/改 key 重试。

### UI 反馈

- 验证中：按钮文字变为 `正在验证接口，请稍后...` + 显示 spinner，按钮禁用，所有输入控件禁用
- 验证失败：按钮上方红色小字显示 `_verifyError`，SnackBar 也弹一次

## 测试

### 单元测试

- `maskBase64('1234567890abcde')` → `'12345***abcde'`
- `maskBase64('1234567890abc')` → `'12345***0abc'`（恰好 13 位）
- `maskBase64('1234567890ab')` → `'***'`（12 位，退化）
- `maskBase64('')` → `'***'`（空，退化）

### 手动验证（Task 9）

- 粘贴凭证 → Bot-API 段显示脱敏 base64
- API Key 默认 obscure，按下眼睛显示明文，抬起恢复
- 点保存 → 出现"正在验证接口，请稍后..."，并行跑三项测试
- 全部通过 → 进入 ChatScreen
- 故意把 API Key 改错一位 → 验证失败，显示 `TTS、ASR 不可用`，留在设置页
- 故意把 streamUrl 改错 → Bot-API 验证失败

## 不在范围内

- 验证过程中取消按钮（验证时间短，15s 顶天，不加）
- 详细错误信息（HTTP 状态码等），用户只需要知道哪一项没通
- 验证成功后保留验证状态显示（成功即进入下一页）
