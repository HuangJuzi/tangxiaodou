# 设置页与配置持久化设计

**日期**：2026-06-23
**分支**：feature/tts-avatar-messages

## 背景与动机

当前 `main.dart` 把 Bot-API 的 URL、accountId、apiSecret 与 ASR/TTS 的 apiKey 全部硬编码：
```dart
const _llmUrl = 'https://moltbot-0014c62b7c7947c3.sophnet.com';
const _llmAccountId = 'parent-toddler';
const _llmSecret = 'oz8hIK-...';
const _apiKey = 'WGT8fpUL1g0kJkyZ-...';
```
只有 TTS voice 已通过 `voice_config.json` 持久化。换 bot、换 key 都要改源码重新编译，无法在运行时配置。

需求：
1. 设置页可配置 Bot-API 的 streamUrl + apiSecret，支持粘贴 base64 或扫二维码（扫码结果也是 base64）。
2. 设置 ASR/TTS/OSS 共用的 apiKey。
3. 把音色选择合并进设置页（移除现有 AppBar 里的音色入口）。
4. 持久化，App 重启后不丢。

base64 样例解码结果：
```json
{"agentId":"dept-token","apiSecret":"7849cc4e...","streamUrl":"https://moltbot-0014c62b7c7947c3.sophnet.com/bot-api/v2/dept-token/chat-stream"}
```
注意 base64 给的是**完整 streamUrl**，不是 baseUrl + accountId 拆分。

## 决策

| 维度 | 决策 |
|---|---|
| 首启行为 | 无默认值；首次启动若配置不完整，强制进入 SettingsScreen |
| 保存后生效 | 热替换 service、不重启 App（重建 widget 子树） |
| 状态管理 | 顶层 StatefulWidget + `SettingsService extends ChangeNotifier`，不引入 Provider |
| 持久化 | `flutter_secure_storage`（加密，避免明文存 apiSecret/apiKey） |
| 二维码扫描 | `mobile_scanner` |
| LlmConfig 重构 | 从 `(baseUrl, accountId, apiSecret)` → `(streamUrl, apiSecret)`，与 base64 一致 |
| 保存后聊天历史 | 清空、重建 ChatScreen（换 bot 后旧会话无法接续） |

## 数据模型

```dart
class AppConfig {
  final String botApiStreamUrl;   // 完整 streamUrl，来自 base64
  final String botApiSecret;       // bot-api 的 apiSecret
  final String asrTtsApiKey;       // ASR + TTS + OSS 共用的 apiKey
  final String ttsVoice;           // 默认 'longyumi_v2'

  bool get isComplete =>
    botApiStreamUrl.isNotEmpty &&
    botApiSecret.isNotEmpty &&
    asrTtsApiKey.isNotEmpty;

  Map<String, dynamic> toJson();
  factory AppConfig.fromJson(Map<String, dynamic> json);
}
```

`agentId` 字段在 base64 中已嵌入 streamUrl 路径，忽略不单独存储。

## 架构与组件

```
lib/
├── main.dart                      # 改为 stateful，订阅 SettingsService，重建 services
├── services/
│   ├── settings_service.dart      # NEW: ChangeNotifier，load/save via flutter_secure_storage
│   ├── llm_service.dart           # LlmConfig 改为 (streamUrl, apiSecret)
│   ├── asr_service.dart           # 不变
│   ├── tts_service.dart           # 不变
│   └── oss_service.dart           # 不变
└── screens/
    ├── chat_screen.dart           # AppBar actions 加齿轮，移除原音色入口
    └── settings_screen.dart       # NEW: 3 段式表单
```

### SettingsService

```dart
class SettingsService extends ChangeNotifier {
  static const _storageKey = 'app_config';
  final _secure = const FlutterSecureStorage();
  AppConfig? _config;
  AppConfig? get config => _config;

  Future<void> load() async {
    final raw = await _secure.read(key: _storageKey);
    if (raw != null) _config = AppConfig.fromJson(jsonDecode(raw));
    notifyListeners();
  }

  Future<void> save(AppConfig cfg) async {
    _config = cfg;
    await _secure.write(key: _storageKey, jsonEncode(cfg.toJson()));
    notifyListeners();
  }
}
```

### main.dart 启动流程

1. `main()` 创建 `SettingsService`，`await load()`
2. `BellaApp` 为 StatefulWidget，订阅 settings 变化
3. `build()`：若 `config == null || !config.isComplete` → 返回 `SettingsScreen`（强制首启）；否则 → 用 config 构造 4 个 service，传给 `ChatScreen`
4. `SettingsService.notifyListeners()` 触发 `setState` → rebuild，新 service 替换旧的（旧的 dispose）

Service 是无状态工具对象，配置变了重建比"修改内部字段"更干净，避免半旧半新的状态。

### LlmConfig 重构

```dart
class LlmConfig {
  final String streamUrl;
  final String apiSecret;
  const LlmConfig({required this.streamUrl, required this.apiSecret});
}
```
`LlmService` 内的 `_config.streamUrl` 直接用，不再拼装。

## SettingsScreen UI

3 个 Section + 底部保存按钮：

```
┌──────────────────────────────┐
│  设置                          │ ← AppBar
├──────────────────────────────┤
│ Bot-API                       │
│ ┌──────────────────────────┐ │
│ │ Stream URL               │ │ ← TextField
│ │ https://moltbot-...       │ │
│ │ API Secret               │ │ ← TextField (obscure)
│ │ ********                  │ │
│ │ [粘贴 Base64] [扫描二维码] │ │ ← 解码后填充上面两字段
│ └──────────────────────────┘ │
│ ASR / TTS API Key             │
│ ┌──────────────────────────┐ │
│ │ API Key                  │ │ ← TextField (obscure)
│ └──────────────────────────┘ │
│ TTS 音色                       │
│ ┌──────────────────────────┐ │
│ ○ 呆萌机器人                │ │ ← RadioListTile
│ ● 正经青年女 (longyumi_v2)  │ │
│ ...                        │ │
│ └──────────────────────────┘ │
│       [   保存   ]            │
└──────────────────────────────┘
```

### Base64 解码

- "粘贴 Base64"：`Clipboard.getData` → base64 decode → `jsonDecode` → 填入 Stream URL + API Secret。
- "扫描二维码"：跳全屏 `MobileScannerView`，扫到字符串后同上解码填充并返回。
- 解码失败（非法 base64 / JSON 缺 `streamUrl` 或 `apiSecret`）→ SnackBar "无效的配置码"，不覆盖现有字段。

### 校验

3 个必填字段（streamUrl、apiSecret、apiKey）非空才允许保存。Voice 永远有默认值 `longyumi_v2`。

### 入口

ChatScreen AppBar actions 在 TTS toggle 右侧加 `Icons.settings` 齿轮图标，点击 `Navigator.push` 到 `SettingsScreen`。原 AppBar 中的音色选择入口移除（合并进设置页）。

## 数据流与错误处理

### 启动流
```
main()
  → SettingsService.load()
  → BellaApp.build()
       ├─ config 空/不完整 → SettingsScreen (强制首启)
       └─ config 完整 → 构造 4 个 service → ChatScreen
```

### 热替换流
```
用户改字段 → 点保存
  → SettingsService.save(newConfig)        # 写 secure storage + notifyListeners
  → BellaApp setState 触发 rebuild
       → 旧 service.dispose()
       → 用 newConfig 构造新 service
       → ChatScreen 重建（消息列表清空，视为新会话）
```

换了 bot-api 或 apiKey 后旧会话无法继续（流式响应挂在旧 URL 上），清空重开最干净。Voice 改动按统一处理，保存即重建。

### 错误处理（沿用现有 pattern，不引入新路径）

- Bot-API 调用失败（HttpException）→ bubble 显示错误文本
- ASR WebSocket 失败 → 返回空字符串
- TTS 失败 → 静默忽略
- 配置解码失败 → SnackBar 提示

## 测试

### 单元测试（`test/settings_service_test.dart`）

- `AppConfig.fromJson` / `toJson` 往返
- `AppConfig.isComplete` 边界（全空、缺一个、全满）
- Base64 解码：合法字符串 → 正确填充 streamUrl + apiSecret；非法 base64 / 缺字段 JSON → 抛错或返回 null
- `SettingsService.save` 触发 `notifyListeners`
- `SettingsService.load` 在 secure storage 为空时返回 null

mock `flutter_secure_storage` 使用其自带 `setMockInitialValues` API。

### 手动验证

- 首启（无配置）→ 直接显示 SettingsScreen，保存后切到 ChatScreen
- 已有配置 → 直接显示 ChatScreen，齿轮可打开设置
- 粘贴 base64 → 字段自动填充
- 扫码扫描 → 字段自动填充
- 保存后聊天页重建（旧消息清空，新 service 生效）

## 新增依赖

- `flutter_secure_storage` ^9.x
- `mobile_scanner` ^5.x

## 不在本次范围内

- 多 profile / 多账号切换
- 配置导入导出文件
- 加密存储之外的二次保护（PIN、生物识别）
- 服务端配置同步
