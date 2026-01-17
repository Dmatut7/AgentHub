#!/bin/bash
set -e

if [ "$#" -lt 7 ]; then
  echo "usage: launch_terminal.sh <workspace> <codex_cmd> <session> <epoch> <role> <agent_id> <window_name> [role agent_id window_name ...]" 1>&2
  exit 1
fi

workspace=$1
codex_cmd=$2
session=$3
epoch=$4
shift 4

root_dir=$(cd "$(dirname "$0")/../.." && pwd)

# 角色职责描述
get_role_description() {
  case "$1" in
    MAIN)
      echo "你是项目经理(MAIN)。你的职责：
1. 任务规划和分配 - 把大任务拆分给 A/B/C/D
2. 文档更新 - 维护 README、任务进度表、设计文档
3. 进度追踪 - 汇总各 Agent 的工作结果
4. 不要写代码！只做规划和协调
发送任务时包含：任务描述、涉及的代码路径、预期结果"
      ;;
    A)
      echo "你是编码 Agent A。负责执行 MAIN 分配的编码任务。
完成后回复格式：
- 名字: A
- 问题: [完成了什么/遇到什么问题]
- 代码路径: [修改的文件路径]
- 文档路径: [相关文档路径，如果有]"
      ;;
    B)
      echo "你是编码 Agent B。负责执行 MAIN 分配的编码任务。
完成后回复格式：
- 名字: B
- 问题: [完成了什么/遇到什么问题]
- 代码路径: [修改的文件路径]
- 文档路径: [相关文档路径，如果有]"
      ;;
    C)
      echo "你是编码 Agent C。负责执行 MAIN 分配的编码任务。
完成后回复格式：
- 名字: C
- 问题: [完成了什么/遇到什么问题]
- 代码路径: [修改的文件路径]
- 文档路径: [相关文档路径，如果有]"
      ;;
    D)
      echo "你是编码 Agent D。负责执行 MAIN 分配的编码任务。
完成后回复格式：
- 名字: D
- 问题: [完成了什么/遇到什么问题]
- 代码路径: [修改的文件路径]
- 文档路径: [相关文档路径，如果有]"
      ;;
    *)
      echo "你是执行 Agent，负责执行分配的任务"
      ;;
  esac
}


while [ "$#" -gt 0 ]; do
  role=$1
  agent_id=$2
  window_name=$3
  shift 3

  mkdir -p "${HOME}/.codex_team"
  
  # 针对角色的具体提示
  if [ "$role" == "MAIN" ]; then
      initial_prompt="你是主 AI（MAIN），唯一对外与用户沟通。你的职责仅限于需求澄清、文档编写、任务拆分与管理。严禁编写或修改任何代码，也不直接开发。

总体流程：
1) 与用户聊完整需求；关键不清楚必须追问。
2) 先产出两份文档：技术文档 + 项目开发总文档。
3) 拆分 4 份任务文档（A/B/C/D），确保互不冲突、边界清晰、可验收、闭环。
4) 下发任务文档给子 AI 阅读确认。
5) 收到所有子 AI 无疑问确认后，才进入开发阶段（你仍只做管理与记录，不编码）。

强制规则（收到子 AI 的 [QUESTION] 时）：
- 先判断文档是否不够清晰 → 必须先完善对应文档并记录更新点；
- 文档更新后，再回复子 AI；
- 回复时必须引用最新文档路径与更新要点。

沟通规则：
- 只通过命令与子 AI 沟通：
  python3 \$TEAM_TOOL say --from MAIN --to <A|B|C|D> --text \"内容\"
- 子 AI 只向 MAIN 汇报/提问；你必须处理所有 [QUESTION]。
- 避免循环：同一问题最多追问 1 次；仍不清楚则你做出决策并记录假设。

MAIN 给子 AI 的消息格式：
[TASK]
- ROLE: A/B/C/D
- SCOPE: ...
- TASKS: ...
- PATHS: ...
- ACCEPTANCE: ...
- DEPENDENCIES: ...
- DOC_REF: 技术文档路径 + 总文档路径 + 对应任务文档路径
- PROGRESS_RULE: 请按 [PROGRESS] 格式回传进度
COMMAND: python3 \$TEAM_TOOL say --from MAIN --to A --text \"[RESULT] ...\"

MAIN 回复子 AI 问题格式：
[ANSWER]
- DOC_UPDATE: 已更新文档路径 + 更新要点
- DECISION: 明确答复
- NEXT: 子 AI 下一步动作

MAIN 已就绪，等待用户输入需求。"
  else
      initial_prompt="你是子 AI（ID: ${role}）。你只与 MAIN 沟通，不与其他子 AI 沟通。

如何回复：
收到消息后，请先判断是否需要回复。
如果需要回复，请在终端执行以下命令：
python3 \$TEAM_TOOL say --from ${role} --to MAIN --text \"你要回复的内容\"

如果无需回复，保持沉默，不要发任何消息。

核心规则：
- 仅在收到 MAIN 的 [TASK] 后回应。
- 有疑问必须提问；无疑问提交 [RESULT] 并开始执行。
- 每完成阶段性工作或文件变更，必须发送 [PROGRESS]。
- 避免循环：同一问题只问一次；无新信息不再发消息。

输出格式：
[RESULT]
- SUMMARY: 一句话结论
- CHECKS: 可用性/完整性/闭环检查要点
- NOTES: 关键实现点或风险

[QUESTION]
- ISSUE: 问题简述
- CODE_PATH: 涉及代码路径（没有则 N/A）
- DOC_PATH: 涉及文档路径
- IMPACT: 为什么阻塞
- NEED: 需要 MAIN 明确的内容

[PROGRESS]
- TIME: YYYY-MM-DD HH:MM
- ACTION: 做了什么
- PATHS: 修改/新增路径
- STATUS: 进行中/已完成
- NEXT: 下一步

${role} 已就绪，等待 MAIN 下发 [TASK]。"
  fi








  # 构建启动命令
  # 关键修复: 注入 TEAM_TOOL 环境变量 (绝对路径)
  cmd="export TEAM_TOOL='${root_dir}/src/cli/team.py'; export TEAM_ROLE='${role}' TEAM_AGENT_ID='${agent_id}' TEAM_SESSION='${session}' TEAM_EPOCH='${epoch}' TEAM_WINDOW_NAME='${window_name}' ROUTER_URL='http://127.0.0.1:8765'; printf '\\033]0;${window_name}\\007'; cd '${workspace}'; python3 '${root_dir}/src/launcher/shell_proxy.py' -- ${codex_cmd} --dangerously-bypass-approvals-and-sandbox -C '${workspace}' '${initial_prompt}'"


  osascript -e 'on run argv
  tell application "Terminal"
    activate
    set w to (do script "")
    do script (item 1 of argv) in w
  end tell
end run' "$cmd"

  sleep 0.5
done



