#!/bin/bash
# =============================================================================
# CCX Install Script
# =============================================================================
# 自动化安装 CCX AI API 代理网关 (https://github.com/BenedictKing/ccx)
#
# 功能:
#   1. 选择安装目录
#   2. 从 GitHub 克隆/更新仓库
#   3. 从 GitHub Releases 下载最新预编译二进制
#   4. 配置 .env（访问密码、端口、语言等）
#   5. 配置 macOS LaunchAgent 开机自启
#   6. 启动服务并验证
#
# 使用方法:
#   bash install_ccx.sh
# =============================================================================

set -e

# ---- 颜色定义 ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ---- 工具函数 ----
info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ---- 前置检查 ----
check_prerequisites() {
    echo ""
    echo "=========================================="
    echo "  CCX 安装脚本"
    echo "  版本: 1.0.0"
    echo "=========================================="
    echo ""

    # 检查 Git
    if ! command -v git &>/dev/null; then
        error "Git 未安装。请先安装 Git:"
        error "  brew install git"
        exit 1
    fi
    ok "Git 已安装: $(git --version)"

    # 检查 curl
    if ! command -v curl &>/dev/null; then
        error "curl 未安装"
        exit 1
    fi
    ok "curl 已安装"

    # 检查操作系统
    if [[ "$(uname)" != "Darwin" ]]; then
        error "此脚本仅支持 macOS"
        exit 1
    fi
    ok "操作系统: macOS $(sw_vers -productVersion)"

    # 检测架构
    ARCH="$(uname -m)"
    if [[ "$ARCH" == "arm64" ]]; then
        BINARY_ARCH="arm64"
        ok "架构: Apple Silicon (arm64)"
    elif [[ "$ARCH" == "x86_64" ]]; then
        BINARY_ARCH="amd64"
        ok "架构: Intel (x86_64)"
    else
        error "不支持的架构: $ARCH"
        exit 1
    fi

    echo ""
}

# ---- 选择安装目录 ----
choose_install_dir() {
    local default_dir="$HOME/Desktop/ccx"
    local user_dir

    info "CCX 将安装到哪个目录？"
    echo "  按 Enter 使用默认目录: ${default_dir}"
    read -r -p "  请输入安装路径: " user_dir

    if [[ -z "$user_dir" ]]; then
        INSTALL_DIR="$default_dir"
    else
        # 展开 ~ 为 $HOME
        INSTALL_DIR="${user_dir/#\~/$HOME}"
    fi

    # 转换为绝对路径
    INSTALL_DIR="$(cd "$(dirname "$INSTALL_DIR")" 2>/dev/null && pwd)/$(basename "$INSTALL_DIR")" 2>/dev/null || INSTALL_DIR="$INSTALL_DIR"

    echo ""
    info "安装目录: ${INSTALL_DIR}"

    # 检查目录是否已存在
    if [[ -d "$INSTALL_DIR" ]]; then
        if [[ -f "$INSTALL_DIR/backend-go/.env" ]]; then
            warn "检测到已有 CCX 安装。"
            echo "  选项:"
            echo "    1) 更新现有安装（保留配置）"
            echo "    2) 重新安装（备份后覆盖配置）"
            echo "    3) 取消"
            read -r -p "  请选择 [1/2/3]: " upgrade_choice

            case "$upgrade_choice" in
                1) INSTALL_MODE="update" ;;
                2) INSTALL_MODE="reinstall" ;;
                *) info "已取消安装" ; exit 0 ;;
            esac
        else
            warn "目录已存在但未检测到 CCX 安装。"
            read -r -p "  是否继续使用此目录？[Y/n] " continue_choice
            if [[ "$continue_choice" =~ ^[Nn] ]]; then
                info "已取消安装"
                exit 0
            fi
            INSTALL_MODE="fresh"
        fi
    else
        INSTALL_MODE="fresh"
    fi
    echo ""
}

# ---- 设置访问密码 ----
setup_password() {
    local password

    info "设置 CCX 访问密码"
    echo "  按 Enter 使用默认密码: 123456"
    read -r -p "  请输入访问密码: " password

    if [[ -z "$password" ]]; then
        ACCESS_PASSWORD="123456"
    else
        ACCESS_PASSWORD="$password"
    fi
    ok "访问密码已设置"
    echo ""
}

# ---- 克隆/更新仓库 ----
clone_repository() {
    local repo_url="https://github.com/BenedictKing/ccx.git"

    info "正在${INSTALL_MODE}仓库..."

    if [[ "$INSTALL_MODE" == "fresh" ]]; then
        # 创建父目录
        mkdir -p "$(dirname "$INSTALL_DIR")"
        git clone "$repo_url" "$INSTALL_DIR"
        ok "仓库已克隆到: ${INSTALL_DIR}"
    else
        cd "$INSTALL_DIR"
        # 备份配置
        if [[ -f "backend-go/.env" ]]; then
            local env_backup="backend-go/.env.bak.$(date +%Y%m%d%H%M%S)"
            cp "backend-go/.env" "$env_backup"
            ok "已备份 .env → ${env_backup}"
        fi
        if [[ -d "backend-go/.config" ]]; then
            local config_backup="backend-go/.config.bak.$(date +%Y%m%d%H%M%S)"
            cp -r "backend-go/.config" "$config_backup"
            ok "已备份 .config/ → ${config_backup}"
        fi

        # 拉取最新代码
        git fetch --all
        git reset --hard origin/main
        ok "仓库已更新到最新版本"
    fi
    echo ""
}

# ---- 下载最新二进制 ----
download_binary() {
    local binary_path="$INSTALL_DIR/backend-go/ccx"
    local repo="BenedictKing/ccx"

    info "正在获取最新版本信息..."

    # 获取最新 release 信息
    local release_info
    release_info=$(curl -s "https://api.github.com/repos/${repo}/releases/latest" 2>&1) || true

    if [[ -z "$release_info" ]] || echo "$release_info" | grep -q "Not Found"; then
        warn "无法从 GitHub Releases 获取版本信息，尝试本地构建..."
        build_from_source
        return
    fi

    local version
    version=$(echo "$release_info" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": "\(.*\)",/\1/')
    if [[ -z "$version" ]]; then
        warn "无法解析版本号，尝试本地构建..."
        build_from_source
        return
    fi
    info "最新版本: ${version}"

    # 查找匹配的二进制文件
    local binary_name="ccx-darwin-${BINARY_ARCH}"
    local download_url
    download_url=$(echo "$release_info" | grep "browser_download_url" | grep "$binary_name" | head -1 | sed 's/.*"browser_download_url": "\(.*\)",/\1/' | sed 's/.*"browser_download_url": "\(.*\)"/\1/')

    if [[ -z "$download_url" ]]; then
        warn "未找到预编译二进制 (${binary_name})，尝试本地构建..."
        build_from_source
        return
    fi

    info "正在下载: ${binary_name}"
    info "下载地址: ${download_url}"

    # 下载二进制
    if curl -L -o "$binary_path" "$download_url" --progress-bar; then
        chmod +x "$binary_path"
        local file_size
        file_size=$(du -h "$binary_path" | cut -f1)
        ok "二进制已下载: ${binary_path} (${file_size})"
    else
        warn "下载失败，尝试本地构建..."
        rm -f "$binary_path"
        build_from_source
        return
    fi

    # 验证二进制
    if ! file "$binary_path" | grep -q "Mach-O"; then
        warn "下载的文件不是有效的 Mach-O 可执行文件，尝试本地构建..."
        build_from_source
        return
    fi

    ok "二进制验证通过: $(file "$binary_path" | sed 's/.*: //')"
    echo ""
}

# ---- 本地构建（回退方案） ----
build_from_source() {
    local binary_path="$INSTALL_DIR/backend-go/ccx"

    info "正在从源码构建..."

    # 检查 Go
    if ! command -v go &>/dev/null; then
        error "Go 未安装，无法本地构建。"
        error "请安装 Go: https://go.dev/dl/"
        error "或手动下载二进制: https://github.com/BenedictKing/ccx/releases"
        exit 1
    fi
    ok "Go 已安装: $(go version)"

    cd "$INSTALL_DIR"
    if make build 2>&1; then
        ok "本地构建成功"
    else
        error "本地构建失败"
        exit 1
    fi

    # 验证二进制
    if [[ ! -f "$binary_path" ]]; then
        error "构建后未找到二进制文件: ${binary_path}"
        exit 1
    fi

    chmod +x "$binary_path"
    ok "二进制已就绪: $(file "$binary_path" | sed 's/.*: //')"
    echo ""
}

# ---- 配置环境变量 ----
configure_env() {
    local env_file="$INSTALL_DIR/backend-go/.env"

    info "正在配置环境变量..."

    # 如果已存在 .env 且是更新模式，保留现有配置
    if [[ "$INSTALL_MODE" == "update" && -f "$env_file" ]]; then
        # 确保关键配置存在
        local need_update=false

        if ! grep -q "PROXY_ACCESS_KEY" "$env_file" 2>/dev/null; then
            echo "PROXY_ACCESS_KEY=${ACCESS_PASSWORD}" >> "$env_file"
            need_update=true
        fi
        if ! grep -q "PORT=" "$env_file" 2>/dev/null; then
            echo "PORT=3688" >> "$env_file"
            need_update=true
        fi

        if $need_update; then
            ok "已补充缺失的配置项"
        else
            ok "现有配置已保留"
        fi
    else
        # 创建新的 .env
        cat > "$env_file" << 'ENVEOF'
# 环境变量配置

# ============ 服务器配置 ============
PORT=3688
ENV=production

# ============ Web UI 配置 ============
ENABLE_WEB_UI=true
APP_UI_LANGUAGE=zh-CN

# ============ 访问控制 ============
ENVEOF
        echo "PROXY_ACCESS_KEY=${ACCESS_PASSWORD}" >> "$env_file"
        cat >> "$env_file" << 'ENVEOF'
# 管理 API 独立密钥（未设置时回退到 PROXY_ACCESS_KEY）
# ADMIN_ACCESS_KEY=your-admin-access-key-here

# ============ 日志配置 ============
LOG_LEVEL=info
ENABLE_REQUEST_LOGS=false
ENABLE_RESPONSE_LOGS=false
QUIET_POLLING_LOGS=true
RAW_LOG_OUTPUT=false
SSE_DEBUG_LEVEL=off
REWRITE_RESPONSE_MODEL=false

# ============ 性能配置 ============
REQUEST_TIMEOUT=300000
SERVER_READ_TIMEOUT=60000
MAX_REQUEST_BODY_SIZE_MB=50
RESPONSE_HEADER_TIMEOUT=60

# ============ CORS 配置 ============
ENABLE_CORS=false
CORS_ORIGIN=*

# ============ 熔断指标配置 ============
METRICS_WINDOW_SIZE=10
METRICS_FAILURE_THRESHOLD=0.5

# ============ 指标持久化配置 ============
METRICS_PERSISTENCE_ENABLED=true
METRICS_RETENTION_DAYS=30
ENVEOF
        ok "配置文件已创建: ${env_file}"
    fi

    # 显示配置摘要
    local port
    port=$(grep "^PORT=" "$env_file" | cut -d= -f2)
    info "端口: ${port}"
    info "访问密码: ${ACCESS_PASSWORD}"
    echo ""
}

# ---- 配置 LaunchAgent 开机自启 ----
setup_launchagent() {
    local plist_dest="$HOME/Library/LaunchAgents/com.ccx.proxy.plist"
    local binary_path="$INSTALL_DIR/backend-go/ccx"

    info "正在配置开机自启动..."

    # 创建 LaunchAgents 目录
    mkdir -p "$HOME/Library/LaunchAgents"

    # 如果已存在，先卸载
    if [[ -f "$plist_dest" ]]; then
        launchctl unload "$plist_dest" 2>/dev/null || true
        ok "已卸载现有 LaunchAgent"
    fi

    # 生成 plist 文件
    cat > "$plist_dest" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ccx.proxy</string>

    <key>ProgramArguments</key>
    <array>
        <string>${binary_path}</string>
    </array>

    <key>WorkingDirectory</key>
    <string>${INSTALL_DIR}/backend-go</string>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <key>StandardOutPath</key>
    <string>/tmp/ccx.stdout.log</string>

    <key>StandardErrorPath</key>
    <string>/tmp/ccx.stderr.log</string>
</dict>
</plist>
PLISTEOF

    ok "LaunchAgent 已创建: ${plist_dest}"

    # 加载服务
    if launchctl load "$plist_dest" 2>&1; then
        ok "LaunchAgent 已加载（开机自启已启用）"
    else
        warn "LaunchAgent 加载失败，请手动加载:"
        warn "  launchctl load ${plist_dest}"
    fi
    echo ""
}

# ---- 启动并验证服务 ----
start_and_verify() {
    local port
    port=$(grep "^PORT=" "$INSTALL_DIR/backend-go/.env" | cut -d= -f2)
    port="${port:-3688}"

    info "正在启动 CCX 服务..."

    # 通过 LaunchAgent 启动
    if launchctl start com.ccx.proxy 2>&1; then
        ok "服务已启动"
    else
        # 如果 LaunchAgent 启动失败，尝试直接运行
        warn "LaunchAgent 启动失败，尝试直接运行..."
        cd "$INSTALL_DIR/backend-go"
        nohup ./ccx > /tmp/ccx.stdout.log 2> /tmp/ccx.stderr.log &
        ok "服务已直接启动 (PID: $!)"
    fi

    # 等待服务就绪
    info "等待服务就绪..."
    local max_retries=10
    local retry=0
    while [[ $retry -lt $max_retries ]]; do
        sleep 1
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${port}/" 2>/dev/null || echo "000")
        if [[ "$http_code" == "200" ]]; then
            ok "服务已就绪！HTTP 状态码: ${http_code}"
            break
        fi
        retry=$((retry + 1))
        if [[ $retry -eq $max_retries ]]; then
            warn "服务启动超时，请手动检查:"
            warn "  cat /tmp/ccx.stderr.log"
            warn "  cat /tmp/ccx.stdout.log"
        fi
    done
    echo ""
}

# ---- 打印安装总结 ----
print_summary() {
    local port
    port=$(grep "^PORT=" "$INSTALL_DIR/backend-go/.env" | cut -d= -f2)
    port="${port:-3688}"

    echo ""
    echo "=========================================="
    echo -e "  ${GREEN}CCX 安装完成！${NC}"
    echo "=========================================="
    echo ""
    echo -e "  ${BLUE}安装目录:${NC}     ${INSTALL_DIR}"
    echo -e "  ${BLUE}管理界面:${NC}     http://localhost:${port}"
    echo -e "  ${BLUE}访问密码:${NC}     ${ACCESS_PASSWORD}"
    echo -e "  ${BLUE}API 地址:${NC}     http://localhost:${port}/v1"
    echo ""
    echo "  --- 常用命令 ---"
    echo -e "  ${YELLOW}启动服务:${NC}      launchctl start com.ccx.proxy"
    echo -e "  ${YELLOW}停止服务:${NC}      launchctl stop com.ccx.proxy"
    echo -e "  ${YELLOW}查看状态:${NC}      launchctl list | grep ccx"
    echo -e "  ${YELLOW}查看日志:${NC}      cat /tmp/ccx.stdout.log"
    echo -e "  ${YELLOW}错误日志:${NC}      cat /tmp/ccx.stderr.log"
    echo ""
    echo -e "  ${GREEN}现在可以在浏览器中打开 http://localhost:${port}${NC}"
    echo -e "  ${GREEN}输入密码 ${ACCESS_PASSWORD} 进入管理界面${NC}"
    echo ""
    echo "=========================================="
    echo ""
}

# ---- 主流程 ----
main() {
    check_prerequisites
    choose_install_dir
    setup_password
    clone_repository
    download_binary
    configure_env
    setup_launchagent
    start_and_verify
    print_summary
}

main "$@"
