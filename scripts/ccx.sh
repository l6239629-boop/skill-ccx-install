#!/bin/bash
# =============================================================================
# CCX 管理脚本 - 启动 / 停止 / 重启 / 状态 / 日志
# =============================================================================
# 用法:
#   bash ccx.sh start     启动 CCX
#   bash ccx.sh stop      停止 CCX（通过标记文件防止 KeepAlive 重启）
#   bash ccx.sh restart   重启 CCX
#   bash ccx.sh status    查看运行状态
#   bash ccx.sh logs      查看日志
#   bash ccx.sh enable    启用开机自启
#   bash ccx.sh disable   禁用开机自启
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_DIR="${CCX_INSTALL_DIR:-$HOME/Desktop/ccx}"
PLIST_DEST="$HOME/Library/LaunchAgents/com.ccx.proxy.plist"
STOP_FLAG="/tmp/ccx.stop"

# ---- 颜色 ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

get_port() {
    local port
    port=$(grep "^PORT=" "$INSTALL_DIR/backend-go/.env" 2>/dev/null | cut -d= -f2)
    echo "${port:-3688}"
}

# ---- 启动 ----
cmd_start() {
    if [[ -f "$STOP_FLAG" ]]; then
        rm -f "$STOP_FLAG"
        info "已移除停止标记"
    fi

    if [[ -f "$PLIST_DEST" ]]; then
        launchctl load "$PLIST_DEST" 2>/dev/null || true
        launchctl start com.ccx.proxy 2>/dev/null || true
        ok "CCX 已通过 LaunchAgent 启动"
    else
        # 直接启动
        cd "$INSTALL_DIR/backend-go"
        nohup ./ccx > /tmp/ccx.stdout.log 2> /tmp/ccx.stderr.log &
        ok "CCX 已直接启动 (PID: $!)"
    fi

    # 验证
    local port
    port=$(get_port)
    sleep 2
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${port}/" 2>/dev/null || echo "000")
    if [[ "$http_code" == "200" ]]; then
        ok "CCX 运行正常 (HTTP ${http_code})"
    else
        warn "CCX 可能未就绪 (HTTP ${http_code})，请稍后检查"
    fi
}

# ---- 停止 ----
cmd_stop() {
    info "正在停止 CCX..."

    # 创建停止标记（供包装脚本检测）
    touch "$STOP_FLAG"

    if [[ -f "$PLIST_DEST" ]]; then
        # 卸载 LaunchAgent（停止服务且禁止 KeepAlive 重启）
        launchctl unload "$PLIST_DEST" 2>/dev/null || true
        ok "LaunchAgent 已卸载，CCX 已停止"
    fi

    # 确保所有 ccx 进程都被杀死
    local killed=0
    local pids
    pids=$(pgrep -f "backend-go/ccx" 2>/dev/null || true)
    if [[ -n "$pids" ]]; then
        kill $pids 2>/dev/null || true
        sleep 1
        # 再次检查
        pids=$(pgrep -f "backend-go/ccx" 2>/dev/null || true)
        if [[ -n "$pids" ]]; then
            kill -9 $pids 2>/dev/null || true
        fi
        killed=1
    fi

    # 验证
    local port
    port=$(get_port)
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${port}/" 2>/dev/null || echo "000")
    if [[ "$http_code" == "000" ]]; then
        ok "CCX 已完全停止"
    else
        warn "CCX 可能仍在运行 (HTTP ${http_code})"
    fi
}

# ---- 重启 ----
cmd_restart() {
    cmd_stop
    sleep 1
    cmd_start
}

# ---- 状态 ----
cmd_status() {
    local port
    port=$(get_port)

    echo "=== CCX 状态 ==="
    echo ""

    # LaunchAgent 状态
    if launchctl list | grep -q "com.ccx.proxy"; then
        echo -e "  LaunchAgent: ${GREEN}已加载${NC}"
    else
        echo -e "  LaunchAgent: ${RED}未加载${NC}"
    fi

    # 进程状态
    local pids
    pids=$(pgrep -f "backend-go/ccx" 2>/dev/null || true)
    if [[ -n "$pids" ]]; then
        echo -e "  进程:       ${GREEN}运行中${NC} (PID: $(echo $pids | tr '\n' ' '))"
    else
        echo -e "  进程:       ${RED}未运行${NC}"
    fi

    # 端口状态
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${port}/" 2>/dev/null || echo "000")
    if [[ "$http_code" == "200" ]]; then
        echo -e "  端口 ${port}: ${GREEN}正常 (HTTP ${http_code})${NC}"
    else
        echo -e "  端口 ${port}: ${RED}不可达 (HTTP ${http_code})${NC}"
    fi

    # 停止标记
    if [[ -f "$STOP_FLAG" ]]; then
        echo -e "  停止标记:   ${YELLOW}存在（下次启动前需清除）${NC}"
    fi

    echo ""
    echo "  安装目录: $INSTALL_DIR"
    echo "  管理界面: http://localhost:${port}"
}

# ---- 日志 ----
cmd_logs() {
    echo "=== CCX 标准输出日志 ==="
    if [[ -f /tmp/ccx.stdout.log ]]; then
        tail -n 50 /tmp/ccx.stdout.log
    else
        echo "(无日志)"
    fi
    echo ""
    echo "=== CCX 错误日志 ==="
    if [[ -f /tmp/ccx.stderr.log ]]; then
        tail -n 50 /tmp/ccx.stderr.log
    else
        echo "(无日志)"
    fi
    echo ""
    echo "=== CCX 应用日志 ==="
    if [[ -f "$INSTALL_DIR/backend-go/logs/app.log" ]]; then
        tail -n 50 "$INSTALL_DIR/backend-go/logs/app.log"
    else
        echo "(无日志)"
    fi
}

# ---- 启用开机自启 ----
cmd_enable() {
    if [[ ! -f "$PLIST_DEST" ]]; then
        error "未找到 LaunchAgent 配置: $PLIST_DEST"
        error "请先运行安装脚本"
        exit 1
    fi
    launchctl load "$PLIST_DEST" 2>/dev/null || true
    ok "开机自启已启用"
}

# ---- 禁用开机自启 ----
cmd_disable() {
    if [[ -f "$PLIST_DEST" ]]; then
        launchctl unload "$PLIST_DEST" 2>/dev/null || true
    fi
    ok "开机自启已禁用"
}

# ---- 主入口 ----
main() {
    case "${1:-}" in
        start)   cmd_start ;;
        stop)    cmd_stop ;;
        restart) cmd_restart ;;
        status)  cmd_status ;;
        logs)    cmd_logs ;;
        enable)  cmd_enable ;;
        disable) cmd_disable ;;
        *)
            echo "用法: bash ccx.sh <command>"
            echo ""
            echo "命令:"
            echo "  start     启动 CCX"
            echo "  stop      停止 CCX"
            echo "  restart   重启 CCX"
            echo "  status    查看状态"
            echo "  logs      查看日志"
            echo "  enable    启用开机自启"
            echo "  disable   禁用开机自启"
            ;;
    esac
}

main "$@"
