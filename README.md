# AgentHub - 多 AI 协作开发框架

让多个 AI Agent 通过消息协议协同工作，像人类团队一样完成复杂软件开发任务。

## 核心特性

- **一键启动** - 一条命令启动完整的 AI 团队（1 主控 + 4 执行）
- **可靠通信** - ACK 确认、自动重试、超时处理
- **完整协议** - 审查→分配→执行→验收的全流程规范
- **状态持久** - 崩溃自动恢复，消息永不丢失
- **多终端支持** - 支持 macOS Terminal / iTerm2

## 快速开始

### 前置条件

- macOS 系统
- Python 3.8+
- Terminal.app 或 iTerm2
- AI CLI 工具（如 Codex、Claude Code 等）

### 安装

```bash
# 克隆仓库
git clone https://github.com/Dmatut7/AgentHub.git
cd AgentHub

# 配置快捷命令（可选）
export AGENTHUB_HOME="$(pwd)"
alias ah-start="$AGENTHUB_HOME/scripts/start_team.sh"
alias ah-status="$AGENTHUB_HOME/scripts/status_team.sh"
alias ah-stop="$AGENTHUB_HOME/scripts/stop_team.sh"
```

### 启动 AI 团队

```bash
# 在你的项目目录下启动
cd /your/project
./path/to/AgentHub/scripts/start_team.sh
```

系统会自动：
1. 启动 Router（消息中心）
2. 生成标准文档模板
3. 打开 5 个终端窗口（MAIN + A/B/C/D）

### 工作流程

```
用户需求 → MAIN 确认 → 编写文档 → 审查反馈
                ↓
        任务分配给 A/B/C/D
                ↓
        并行开发 + 问题沟通
                ↓
        验收完成 → 汇总结果
```

## 架构设计

```
┌─────────────────────────────────────────────────────┐
│                      Router                         │
│              (消息路由 / 状态管理)                    │
└─────────────┬───────────────────────────────────────┘
              │
    ┌─────────┼─────────┬─────────┬─────────┐
    │         │         │         │         │
┌───▼───┐ ┌──▼───┐ ┌──▼───┐ ┌──▼───┐ ┌──▼───┐
│ MAIN  │ │  A   │ │  B   │ │  C   │ │  D   │
│(主控) │ │(执行)│ │(执行)│ │(执行)│ │(执行)│
└───────┘ └──────┘ └──────┘ └──────┘ └──────┘
```

## 目录结构

```
AgentHub/
├── scripts/           # 启动脚本
├── src/
│   ├── api/          # HTTP 服务器
│   ├── cli/          # 命令行工具
│   ├── router/       # 消息路由
│   ├── protocol/     # 消息协议
│   ├── state/        # 状态管理
│   ├── storage/      # 持久化存储
│   └── launcher/     # 终端启动器
├── prompts/          # AI 提示词模板
├── docs/             # 设计文档
└── README.md
```

## 消息协议

AgentHub 定义了一套完整的 AI-to-AI 通信协议：

| 消息类型 | 方向 | 用途 |
|---------|------|------|
| `review` | MAIN→Members | 审查文档/代码 |
| `report` | Members→MAIN | 反馈审查结果 |
| `assign` | MAIN→Members | 分配任务 |
| `clarify` | Members→MAIN | 询问问题 |
| `answer` | MAIN→Members | 解答问题 |
| `verify` | MAIN→Members | 验证修改 |
| `done` | Members→MAIN | 任务完成 |
| `fail` | Members→MAIN | 任务失败 |

完整协议规范请参阅 [docs/main-members-workflow.md](docs/main-members-workflow.md)

## 常用命令

```bash
# 启动系统
./scripts/start_team.sh

# 查看状态
./scripts/status_team.sh

# 发送消息
python3 src/cli/team.py say --from MAIN --to A --text "开始任务"

# 查看消息队列
curl http://127.0.0.1:8765/status | python3 -m json.tool

# 停止系统
./scripts/stop_team.sh
```

## 配置选项

| 环境变量 | 说明 | 默认值 |
|---------|------|--------|
| `TERMINAL_ADAPTER` | 终端类型 | `terminal` |
| `CODEX_PATH` | AI CLI 路径 | `codex` |

## 文档

- [设计文档](docs/design.md) - 系统架构设计
- [协议规范](docs/main-members-workflow.md) - 消息协议详解

## License

MIT License

---

**AgentHub** - 让 AI 团队协作更简单。
