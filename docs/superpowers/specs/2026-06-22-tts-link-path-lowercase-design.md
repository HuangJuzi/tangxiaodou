# TTS 链接/路径过滤与小写朗读 — 设计

日期：2026-06-22

## 背景

语音输出（TTS）存在两个问题：

1. **链接/路径碎片泄漏**：当 AI 回复里含 URL 或文件路径时，其中一部分会被读出来，听感很差。
   - 根因：流式 TTS 的分句切分（`chat_screen.dart` 的 `delimRe`，含 `.`）发生在 `TtsPlayer.sanitize` **之前**。URL/路径在 `.com` 的 `.`、`main.dart` 的 `.` 处被切成两块，逐块 `sanitize` 时已认不出完整 URL/路径，于是后半截碎片（如 `com/bar`、`dart`）被合成朗读。
2. **大写字母被逐字母拼读**：CosyVoice 对大写串逐字母念（`MEMORY` → M-E-M-O-R-Y）。期望按单词读，且文件名里的 `.` 读作「点」，例如 `MEMORY.MD` → `memory点md`。

## 已确认的行为决策

- http/https/ws 链接：**完全不读**。
- 文件路径（含斜杠，绝对或相对）：**完全不读**，连前导段（如 `lib/main.dart` 的 `lib`）一起去掉。
- 大写字母：TTS 文本里所有 ASCII 字母**统一转小写**。
- 无斜杠的文件名（如 `MEMORY.MD`）不算路径，要读出来，按「小写 + 点」朗读。

## 方案

采用方案 A：在切分前 hold-back 未结束的链接/路径，避免产生碎片；完整的链接/路径由 `sanitize` 整条删除。

### 1. `lib/services/tts_player.dart` — `sanitize`（静态）

在现有清洗基础上增改：

- **相对路径**：把路径正则扩展到含斜杠但无前导 `/` 的相对路径（`lib/main.dart`），整条（含前导段）删除。判定：含 `/` 的路径样 token。
- **文件名点号 → 点**：新增 `(?<=[A-Za-z0-9])\.(?=[A-Za-z0-9])` → `点`，须在「通用标点 → 逗号」步骤**之前**执行，避免 `.` 先被替换成逗号。例：`MEMORY.MD`→`MEMORY点MD`、`v2.0`→`v2点0`。
- **小写**：流程末尾 `.toLowerCase()`，全部 ASCII 字母转小写。

### 2. `lib/services/tts_player.dart` — 新增静态 `inProgressLinkTail(String) -> int`

- 返回「字符串末尾尚未结束的 URL/路径」的起始下标；无则返回 `-1`。
- 判定：最后一个 URL（`(?:https?|wss?)://…`）或斜杠路径 token，是否一直延伸到字符串结尾（其后还没出现空格 / 中文 / 句末标点等终结符）。延伸到结尾 ⇒ 可能还在增长 ⇒ 返回其起点；已被终结 ⇒ 返回 -1。
- 纯函数，便于单测。

### 3. `lib/screens/chat_screen.dart` — `_drainTtsBuffer`

- 在现有 `🛠️` 未闭合 hold-back 之后，调用 `TtsPlayer.inProgressLinkTail(text)`：若 `>=0`，把该尾段写回 `_ttsBuffer`、从本次返回值中截掉。
- 这样切分器永远拿不到半截链接/路径。链接/路径被空格/标点终结、或流结束时由 `finally` 兜底 drain，此时已完整，`sanitize` 整条删除。

### 4. 测试 `test/tts_player_test.dart`

- `sanitize`：
  - `https://foo.com/bar` 整条删除。
  - 绝对路径 `/mnt/b/lib/main.dart`、相对路径 `lib/main.dart` 整条删除。
  - `MEMORY.MD` → `memory点md`；`v2.0` → `v2点0`。
  - 大写 → 小写（`HELLO` → `hello`）。
  - 纯中文文本不受影响。
- `inProgressLinkTail`：
  - 尾部半截 URL（`见 https://foo.co`）返回该 URL 起点。
  - 尾部半截路径（`打开 /mnt/b/li`）返回起点。
  - 已被空格/标点终结的链接返回 -1。
  - 无链接返回 -1。

## 影响范围与权衡

- 仅影响 TTS 朗读文本；**不影响屏幕显示**（`sanitize` 仅用于 TTS 路径）。
- 含单斜杠的非路径词（如 `and/or`、日期 `6/22`）可能被当作路径处理而少读，属可接受的罕见副作用，后续如有需要再细化。
