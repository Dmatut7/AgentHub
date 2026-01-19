#!/bin/bash
# 一键启动 Codex Team - 启动 Router + 5个窗口
# 用法: ./start_team.sh [workspace] [roles]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# 默认值
WORKSPACE="${1:-$(pwd)}"
ROLES="${2:-MAIN,A,B,C,D}"
ROUTER_HOST="127.0.0.1"
ROUTER_PORT="8765"
ROUTER_URL="http://${ROUTER_HOST}:${ROUTER_PORT}"
CODEX_CMD="${CODEX_PATH:-codex}"
TERMINAL_ADAPTER="${TERMINAL_ADAPTER:-terminal}"  # terminal 或 iterm2

echo "============================================"
echo "   🚀 Codex Team 一键启动"
echo "============================================"
echo "工作目录: $WORKSPACE"
echo "角色: $ROLES"
echo "Router: $ROUTER_URL"
echo "终端: $TERMINAL_ADAPTER"
echo "============================================"
echo ""

# 检查 Router 是否已在运行
check_router() {
    curl -s "${ROUTER_URL}/health" > /dev/null 2>&1
    return $?
}

# 启动 Router
start_router() {
    if check_router; then
        echo "✓ Router 已在运行"
        return 0
    fi
    
    echo "⏳ 启动 Router..."
    mkdir -p ~/.codex_team
    python3 "${ROOT_DIR}/src/api/server.py" "$WORKSPACE" \
        --host "$ROUTER_HOST" \
        --port "$ROUTER_PORT" \
        > ~/.codex_team/router.log 2>&1 &
    
    ROUTER_PID=$!
    echo $ROUTER_PID > ~/.codex_team/router.pid
    
    # 等待 Router 启动
    for i in {1..30}; do
        if check_router; then
            echo "✓ Router 启动成功 (PID: $ROUTER_PID)"
            return 0
        fi
        sleep 0.5
    done
    
    echo "✗ Router 启动失败，请检查日志: ~/.codex_team/router.log"
    exit 1
}

# 获取 session 和 epoch
get_session_info() {
    RESPONSE=$(curl -s "${ROUTER_URL}/status")
    SESSION=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session',''))" 2>/dev/null || echo "")
    EPOCH=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('epoch',1))" 2>/dev/null || echo "1")
    
    if [ -z "$SESSION" ]; then
        SESSION="team-$(date +%s)"
    fi
    
    echo "Session: $SESSION"
    echo "Epoch: $EPOCH"
}

# 初始化标准文档（如果不存在）
init_docs() {
    TEMPLATE_DIR="${ROOT_DIR}/aidoc/docs"
    TARGET_DIR="${WORKSPACE}/docs"
    
    if [ -d "$TARGET_DIR" ]; then
        echo "✓ docs/ 目录已存在，跳过初始化"
        return 0
    fi
    
    if [ ! -d "$TEMPLATE_DIR" ]; then
        echo "⚠ 模板目录不存在: $TEMPLATE_DIR"
        return 0
    fi
    
    echo "⏳ 初始化标准文档..."
    
    # 复制模板
    cp -r "$TEMPLATE_DIR" "$TARGET_DIR"
    
    # 替换路径占位符
    find "$TARGET_DIR" -name "*.md" -exec sed -i '' "s|<PROJECT_ROOT>|${WORKSPACE}|g" {} \;
    
    echo "✓ 已生成标准文档到 ${TARGET_DIR}"
    echo "  - tech/tech-spec.md"
    echo "  - project/dev-master.md"
    echo "  - project/evaluation.md"
    echo "  - tasks/task-A.md ~ task-D.md"
}


# 启动窗口
start_windows() {
    echo ""
    echo "⏳ 启动 $ROLES 窗口..."
    
    # 使用 team.py start 命令
    cd "$ROOT_DIR"
    python3 src/cli/team.py start \
        --workspace "$WORKSPACE" \
        --roles "$ROLES" \
        --router-url "$ROUTER_URL" \
        --terminal-adapter "$TERMINAL_ADAPTER" \
        --codex-path "$CODEX_CMD"
    
    echo ""
    echo "✓ 所有窗口已启动"
}

# 主流程
main() {
    start_router
    echo ""
    get_session_info
    echo ""
    init_docs
    start_windows
    
    echo ""
    echo "============================================"
    echo "   ✅ Codex Team 启动完成!"
    echo "============================================"
    echo ""
    echo "📝 使用方法:"
    echo "  发送消息: python3 src/cli/team.py say --from MAIN --to A --text \"你的消息\""
    echo "  回复消息: python3 src/cli/team.py reply --from A --to MAIN --corr <msg_id> --text \"回复\""
    echo ""
    echo "📊 查看状态: ./scripts/status_team.sh"
    echo "📊 实时监控: ./scripts/status_team.sh --follow"
    echo "🛑 停止系统: ./scripts/stop_team.sh"
    echo ""
}

main
