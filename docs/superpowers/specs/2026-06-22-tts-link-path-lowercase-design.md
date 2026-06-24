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

采用方案 A：在切分前 hold-back 未结束的链接/路径/文件名，并对**已完整**的部分先删链接、把文件名的 `.` 转成 `点`，再交给切分器；这样切分器既拿不到半截链接，也拿不到可被拆开的 `.`。

> 实现细化（相对初版 spec）：仅靠 hold-back 不够——切分器会把**已完整**的链接/文件名再次按 `.` 拆开。因此 `_drainTtsBuffer` 在切分前要执行 `stripLinksAndPaths` + `protectDots`。另外 hold-back 在流末尾会卡住最后一个词，故 `_drainTtsBuffer` 增加 `flushAll` 模式：定时器与收尾流程用 `flushAll: true`，不再 hold-back。

### 1. `lib/services/tts_player.dart` — `sanitize`（静态）

在现有清洗基础上重构为可复用静态方法：

- **`stripLinksAndPaths(String)`**：去掉 `<image-url>`、`MEDIA/VIDEO:` 链接、Markdown 链接（保留文字）、裸 http/ws URL、绝对路径（`/`、`~/`、`C:\`）、以及含斜杠的相对路径（`lib/main.dart`，连前导段一起删）。
- **`protectDots(String)`**：`(?<=[A-Za-z0-9])\.(?=[A-Za-z0-9])` → `点`，让 `MEMORY.MD`→`MEMORY点MD`、`v2.0`→`v2点0`。
- **`sanitize`**：先 `stripLinksAndPaths` → `protectDots`，再做工具调用剥离、inline code、emoji、通用标点→逗号、折叠、trim，最后 `.toLowerCase()` 全部转小写。`点` 属 CJK，会被保留且不受小写影响。

### 2. `lib/services/tts_player.dart` — 新增静态 `inProgressTail(String) -> int`

- 返回「字符串末尾尚未结束」的起始下标；无则返回 `-1`。覆盖四类锚定到结尾的尾部：
  1. URL：`(?:https?|wss?)://…$`
  2. 绝对路径：`(?:[A-Za-z]:[\\/]|~/|/)…$`
  3. 含斜杠相对路径：`[\w.~-]+(?:[\\/][\w.~-]*)+$`
  4. 文件名进行中：`[A-Za-z0-9]+\.$`（末尾「词+点」，可能是 `memory.md` 还没收全）
- URL/路径用的字符类排除空格、中文与句末标点，所以一旦被这些字符终结即视为完整，返回 -1。
- 纯函数，便于单测。

### 3. `lib/screens/chat_screen.dart` — `_drainTtsBuffer`

- 改签名为 `_drainTtsBuffer({bool flushAll = false})`。
- **非 flushAll（流式中）**：先剥已闭合的 `🛠️…(agent)`；hold back 未闭合 `🛠️`；再 `inProgressTail` hold back 未结束的链接/路径/文件名；然后对安全前缀执行 `stripLinksAndPaths` + `protectDots` 返回。
- **flushAll（定时器 / 收尾）**：剥掉未闭合 `🛠️…` 尾巴（不朗读残缺工具调用），不再 hold-back，其余执行 `stripLinksAndPaths` + `protectDots` 后整体返回，避免末尾词被永久卡住。
- 把 2 秒定时器、循环后收尾、`finally` 处的 drain 调用都改为 `flushAll: true`。

### 4. 测试 `test/tts_player_test.dart`

- `sanitize`：
  - `https://foo.com/bar` 整条删除。
  - 绝对路径 `/mnt/b/lib/main.dart`、相对路径 `lib/main.dart` 整条删除。
  - `MEMORY.MD` → `memory点md`；`v2.0` → `v2点0`。
  - 大写 → 小写（`HELLO` → `hello`）。
  - 纯中文文本不受影响。
- `inProgressTail`：
  - 尾部半截 URL（`见 https://foo.co`）返回该 URL 起点。
  - 尾部半截路径（`打开 /mnt/b/li`）返回起点。
  - 尾部进行中文件名（`看 memory.`）返回起点。
  - 已被空格/标点终结的链接（`见 https://foo.com 了`）返回 -1。
  - 无链接（`你好世界`）返回 -1。

## 影响范围与权衡

- 仅影响 TTS 朗读文本；**不影响屏幕显示**（`sanitize` 仅用于 TTS 路径）。
- 含单斜杠的非路径词（如 `and/or`、日期 `6/22`）可能被当作路径处理而少读，属可接受的罕见副作用，后续如有需要再细化。
