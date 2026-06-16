# bot-api-status 使用说明

本指南对应仓库技能 **`skills/bot-api-status`**（store skill：**BOT-API**，当前版本 **1.0.3**）。用途是在 SophClaw 中查看**当前 Agent** 的 Bot API 状态，并支持开启、关闭与重置 API 密钥。

| 场景 | 说明 |
| ---- | ---- |
| 查询状态 | 查看当前 Agent 的 bot-api 是否开启、对外聊天入口链接、API Secret 是否存在 |
| 开启 | 写入 bot-api 账号与插件配置，并生成或复用密钥 |
| 关闭 | 移除当前 Agent 对应的 bot-api 账号；若无其它账号则关闭 bot-api 插件 |
| 重置密钥 | 在已创建 bot-api 的前提下生成新的 API Secret，旧密钥立即失效 |

## 安装 **bot-api-status** skill

- 方式 1：在对话中输入 `安装 bot-api 管理 skill`，然后选择 `bot-api-status` 进行安装。
- 方式 2：在对话中输入 `安装 bot-api-status skill`。

## 对话中的快捷用语

在 SophClaw 对话中可使用下列说法触发同一技能（具体以产品侧路由为准）：

### 开启 bot-api

在对话中输入：`开启bot-api`

### 关闭 bot-api

在对话中输入：`关闭bot-api`

### 重置 bot-api 密钥

在对话中输入：`重置bot-api密钥`

### 查看 bot-api 状态

在对话中输入：`使用bot-api-status 查询bot-api状态`

## 脚本调用（与 SKILL 一致）

在已安装该技能的 Agent 环境中，`{baseDir}` 表示与本技能 `SKILL.md` 同级的安装根目录（通常包含 `scripts/`）。推荐使用：

```bash
uv run {baseDir}/scripts/secret.py <command> [--json] [--config PATH]
```

| 子命令 | 说明 |
| ------ | ---- |
| `status` | 查询当前 Agent 的 bot-api 状态 |
| `get` | 与 `status` 等价（兼容别名） |
| `create` | 开启（创建或更新账号与插件配置） |
| `delete` | 关闭并移除当前 Agent 对应账号 |
| `reset` | 重置密钥 |

常用参数：

| 参数 | 说明 |
| ---- | ---- |
| `--json` | 输出 JSON（便于脚本解析）；省略时为人类可读文本 |
| `--config` | 指定 OpenClaw 全局配置文件路径；默认取自环境变量 `OPENCLAW_CONFIG_PATH`，未设置时为 `~/.openclaw/openclaw.json` |

示例（查询，JSON）：

```bash
uv run {baseDir}/scripts/secret.py status --json
```

脚本在组装聊天入口链接时需要可用的「站点 Base URL」。若在容器/SophClaw 环境中无法读取对应 Base URL，会得到错误提示：**获取BASEURL失败，刷新页面或者重新登录后重试。**（与 `--json` 模式下返回的 `error` 文案一致。）

## 链接形态与输出模板

开启或查询成功后，一般会给出两种 bot-api 入口（占位符含义与脚本、`openclaw.json` 一致）：

- 非流式：`{{BASEURL}}/bot-api/v2/<account_id>/chat`
- 流式：`{{BASEURL}}/bot-api/v2/<account_id>/chat-stream`

其中 `<account_id>` 与 OpenClaw 配置里 **`channels.bot-api.accounts`** 下当前 Agent 所用账号 id 一致。

![image](./assets/bot-api-status-01.jpg)

### Agent 面向用户的输出示例（SKILL 模板）

下列为技能文档约定的展示结构；查询、开启、重置成功时会包含 **Agent 展示名** 与 **Agent ID（source_agent_id）**，便于区分多个 Agent。

**查询**

```text
📋 🤖 bot-api 状态：<🟢 开启 / ⚪ 关闭>

📛 Agent 名字：<display_name>
🆔 Agent ID：<source_agent_id>

🔗 非流式链接：{{BASEURL}}/bot-api/v2/<account_id>/chat
🔗 流式链接：{{BASEURL}}/bot-api/v2/<account_id>/chat-stream
🔑 密钥：<api_secret 或 📭 暂无>
```

**开启**

```text
✨ 🤖 bot-api 已创建

📛 Agent 名字：<display_name>
🆔 Agent ID：<source_agent_id>

🔗 非流式链接：{{BASEURL}}/bot-api/v2/<account_id>/chat
🔗 流式链接：{{BASEURL}}/bot-api/v2/<account_id>/chat-stream
🔑 密钥：<api_secret>

🔒 请妥善保管，勿对外转发或截图。
```

**关闭**

```text
🛑 🤖 bot-api 已关闭

📴 当前 Agent 不再通过 bot-api 对外提供服务。
```

**重置密钥**

```text
🔄 🤖 bot-api 密钥已更新

📛 Agent 名字：<display_name>
🆔 Agent ID：<source_agent_id>

🔗 非流式链接：{{BASEURL}}/bot-api/v2/<account_id>/chat
🔗 流式链接：{{BASEURL}}/bot-api/v2/<account_id>/chat-stream
🔑 新密钥：<new_secret>

🔒 请妥善保管，勿对外转发或截图。
```

若在终端直接运行脚本且**未**加 `--json`，人类可读输出中行名略有缩写（例如「📛 名字」「🆔 source_agent_id」），字段含义与上表一致。

## bot-api 接口说明

以下接口均需在请求头中携带：

- `Content-Type: application/json`
- `Authorization: Bearer <API Secret>`（将创建机器人时保存的 API Secret 替换 `<API Secret>`）

**请求地址**

| 接口类型 | 请求地址 |
| -------- | -------- |
| 非流式 | `{{BASEURL}}/bot-api/v2/<account_id>/chat` |
| 流式 | `{{BASEURL}}/bot-api/v2/<account_id>/chat-stream` |

两种接口使用相同的请求头与 Body 参数，区别主要在返回方式：

- 非流式接口 `chat`：等待模型生成完成后，一次性返回完整结果。
- 流式接口 `chat-stream`：通过 SSE 增量返回结果，适合实时展示。

**Body 参数**

| 名称 | 类型 | 描述 |
| ---- | ---- | ---- |
| senderId | string | 用户 ID，用于标识发起对话的用户 |
| text | string | 用户发送的消息，不能为空；支持在文本中嵌入图片标签 |

#### 非流式接口响应说明

非流式接口会在一次 HTTP 响应中返回完整结果，适合普通问答、服务端转发、或不需要边生成边展示的场景。

**顶层响应参数**

| 名称 | 类型 | 描述 |
| ---- | ---- | ---- |
| reply | string | 机器人最终回复的完整文本 |
| stored | boolean | 是否已写入会话存储 |
| agentId | string | 客服机器人 ID |
| name | string | 客服机器人名称 |
| accountId | string | 客服机器人账号 ID |
| sessionKey | string | 会话密钥，可用于关联同一会话 |

### 非流式返回示例

```json
{
	"reply": "xxx",
	"stored": true,
	"agentId": "main",
	"name": "main",
	"accountId": "main",
	"sessionKey": "agent:main:bot-api:main:dm:user-126"
}
```

#### 流式接口响应说明

流式接口通过 Server-Sent Events (SSE) 返回，每行一条 JSON（`data: {...}`），格式与 OpenAI Chat Completions 流式接口兼容。

**顶层响应参数**

| 名称 | 类型 | 描述 |
| ---- | ---- | ---- |
| id | string | 本次对话的完成 ID，如 `chatcmpl-xxx` |
| object | string | 固定为 `chat.completion.chunk` |
| created | number | 创建时间戳（秒） |
| model | string | 模型/客服名称，如「算能智能客服」 |
| choices | array | 见下表 |
| x_meta | object | 仅**第一次返回**时存在，包含会话与客服信息 |

**choices[].delta 参数**

| 名称 | 类型 | 描述 |
| ---- | ---- | ---- |
| role | string | 仅首块可能出现，为 `assistant` |
| content | string | 本块对应的文本片段，可能为空（心跳） |

**choices[] 其他字段**

| 名称 | 类型 | 描述 |
| ---- | ---- | ---- |
| index | number | 选项索引，通常为 0 |
| finish_reason | string \| null | 未结束为 `null`，结束时为停止原因 |

**x_meta 参数（仅首块）**

| 名称 | 类型 | 描述 |
| ---- | ---- | ---- |
| agentId | string | 客服机器人 ID |
| sessionKey | string | 会话密钥，可用于关联同一会话 |
| name | string | 客服机器人名称 |
| accountId | string | 客服机器人账号 ID |

**流式过程说明**

- **第一次返回**：带 `x_meta`，`delta` 中通常为 `role: "assistant"`、`content: ""`。
- **流式返回**：后续每块为 `delta.content` 的增量文本，无 `x_meta`。
- **结束后返回**：单行 `data: "[DONE]"` 表示流结束。
- **心跳**：中间可能收到 `content` 为空的 chunk，用于保活，可忽略。

**text 字段图片标签**

- 可在 `text` 中嵌入图片标签（可与普通文本混用）：
  - `<image-url>https://...</image-url>`
  - `<image-base64>...</image-base64>`
- 示例：`请分析图片内容：<image-url>https://example.com/demo.jpg</image-url>`
- 建议优先使用 `<image-url>`，避免 Base64 导致请求体过大。

### 第一次返回示例

```json
{
	"id": "chatcmpl-1773719635980-qtvzml",
	"object": "chat.completion.chunk",
	"created": 1773719635,
	"model": "智能客服",
	"choices": [
		{
			"index": 0,
			"delta": {
				"role": "assistant",
				"content": ""
			},
			"finish_reason": null
		}
	],
	"x_meta": {
		"agentId": "qa-agent",
		"sessionKey": "agent:qa-agent:bot-api:qa-agent:dm:user-126",
		"name": "智能客服",
		"accountId": "qa-agent"
	}
}
```

### 流式返回示例

```json
{
	"id": "chatcmpl-1773719635980-qtvzml",
	"object": "chat.completion.chunk",
	"created": 1773719635,
	"model": "智能客服",
	"choices": [
		{
			"index": 0,
			"delta": {
				"content": "模型框架和格式"
			},
			"finish_reason": null
		}
	]
}
```

### 结束后返回示例

```
data: "[DONE]"
```

### 中间可能出现空消息（心跳）

流式过程中可能收到空消息，用于保持连接，可忽略不处理。

**Python 示例（流式对话）**

```python
import json
import requests

STREAM_URL = "{{STREAM_URL}}"  # 替换为实际流式接口地址
API_SECRET = "<API Secret>"       # 替换为创建机器人时保存的 API Secret


def chat_stream(sender_id: str, text: str):
    """与客服机器人流式对话，逐块打印返回内容。"""
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {API_SECRET}",
    }
    payload = {"senderId": sender_id, "text": text}

    with requests.post(STREAM_URL, headers=headers, json=payload, stream=True) as r:
        r.raise_for_status()
        for line in r.iter_lines(decode_unicode=True):
            if not line or not line.startswith("data: "):
                continue
            data = line[6:].strip()
            if data == "[DONE]":
                print("\n[流结束]")
                break
            try:
                chunk = json.loads(data)
            except json.JSONDecodeError:
                continue
            choices = chunk.get("choices") or []
            for c in choices:
                delta = c.get("delta") or {}
                content = delta.get("content") or ""
                if content:
                    print(content, end="", flush=True)
            # 首块可在此读取 x_meta（agentId、sessionKey 等）
            if "x_meta" in chunk:
                meta = chunk["x_meta"]
                print(f"\n[会话] sessionKey={meta.get('sessionKey', '')}")


if __name__ == "__main__":
    # 新会话可先发 "/new"
    chat_stream("user-001", "/new")
    # 等有回复之后再发实际问题
    chat_stream("user-001", "你好，请问营业时间是什么？")
```
