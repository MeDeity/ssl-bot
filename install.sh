#!/bin/bash

# SSL Bot 一键安装脚本
# 使用方法: wget -qO- https://raw.githubusercontent.com/yourname/ssl-bot/main/install.sh | bash

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 输出函数
log() {
    echo -e "${GREEN}[SSL-BOT]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查 root 权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "请使用 root 权限运行此脚本"
        exit 1
    fi
}

# 检测系统
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
    else
        OS=$(uname -s)
    fi
    log "检测到操作系统: $OS"
}

# 安装依赖
install_dependencies() {
    log "安装系统依赖..."
    
    if command -v apt-get >/dev/null 2>&1; then
        # Debian/Ubuntu
        apt-get update
        apt-get install -y python3 python3-pip certbot nginx curl wget
    elif command -v yum >/dev/null 2>&1; then
        # CentOS/RHEL
        yum install -y python3 python3-pip certbot nginx curl wget
    elif command -v dnf >/dev/null 2>&1; then
        # Fedora
        dnf install -y python3 python3-pip certbot nginx curl wget
    else
        error "不支持的包管理器"
        exit 1
    fi
}

# 安装 Python 依赖
install_python_deps() {
    log "安装 Python 依赖..."
    
    # 首先尝试使用系统包管理器
    if install_system_packages; then
        log "使用系统包管理器安装成功"
    else
        # 如果系统包安装失败，使用虚拟环境
        warn "系统包安装失败，使用虚拟环境..."
        install_with_venv
    fi
}

install_system_packages() {
    log "尝试使用系统包管理器安装..."
    
    if command -v apt-get >/dev/null 2>&1; then
        # Ubuntu/Debian - 更新包列表
        apt-get update
        
        # 首先尝试安装具体的 Python 包
        if apt-cache show python3-yaml >/dev/null 2>&1 && \
           apt-cache show python3-requests >/dev/null 2>&1 && \
           apt-cache show python3-cryptography >/dev/null 2>&1; then
            log "通过 apt 安装 Python 包..."
            if apt-get install -y python3-yaml python3-requests python3-cryptography; then
                return 0
            fi
        fi
        
        # 如果具体的包不存在或安装失败，安装 pip 然后使用 pip
        log "通过 pip 安装 Python 包..."
        if ! command -v pip3 >/dev/null 2>&1; then
            apt-get install -y python3-pip
        fi
        
        # 尝试使用 pip 安装（不使用 --break-system-packages）
        if pip3 install pyyaml requests cryptography; then
            return 0
        else
            # 如果普通 pip 安装失败，尝试使用 --user 模式
            warn "系统 pip 安装失败，尝试用户模式安装..."
            if pip3 install --user pyyaml requests cryptography; then
                log "用户模式安装成功"
                return 0
            fi
        fi
        
    elif command -v yum >/dev/null 2>&1; then
        # CentOS/RHEL
        yum install -y python3-pyyaml python3-requests python3-cryptography
        return $?
    elif command -v dnf >/dev/null 2>&1; then
        # Fedora
        dnf install -y python3-pyyaml python3-requests python3-cryptography
        return $?
    fi
    
    return 1
}

install_with_venv() {
    log "开始使用虚拟环境安装..."
    
    # 创建安装目录
    INSTALL_DIR="/opt/ssl-bot"
    VENV_DIR="$INSTALL_DIR/venv"
    
    # 确保安装了 python3-venv
    if ! python3 -c "import venv" 2>/dev/null; then
        log "安装 python3-venv 包..."
        if command -v apt-get >/dev/null 2>&1; then
            apt-get install -y python3-venv
        elif command -v yum >/dev/null 2>&1; then
            yum install -y python3-venv
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y python3-venv
        else
            error "无法安装 python3-venv，请手动安装"
            return 1
        fi
    fi
    
    # 创建虚拟环境
    log "创建虚拟环境: $VENV_DIR"
    if ! python3 -m venv "$VENV_DIR"; then
        error "创建虚拟环境失败"
        return 1
    fi
    
    # 升级 pip 并安装依赖
    log "安装 Python 依赖到虚拟环境..."
    if ! "$VENV_DIR/bin/pip" install --upgrade pip; then
        error "升级 pip 失败"
        return 1
    fi
    
    if "$VENV_DIR/bin/pip" install pyyaml requests cryptography; then
        log "虚拟环境依赖安装成功"
        
        # 更新脚本使用虚拟环境 Python
        update_scripts_for_venv "$VENV_DIR"
        
        return 0
    else
        error "虚拟环境依赖安装失败"
        return 1
    fi
}

update_scripts_for_venv() {
    local venv_dir="$1"
    log "更新脚本使用虚拟环境: $venv_dir"
    
    # 更新 ssl-bot.py 使用虚拟环境 Python
    if [ -f "/opt/ssl-bot/ssl-bot.py" ]; then
        # 备份原文件
        cp "/opt/ssl-bot/ssl-bot.py" "/opt/ssl-bot/ssl-bot.py.backup"
        
        # 更新 shebang
        sed -i "1s|.*|#!$venv_dir/bin/python3|" "/opt/ssl-bot/ssl-bot.py"
        chmod +x "/opt/ssl-bot/ssl-bot.py"
        log "更新 ssl-bot.py 使用虚拟环境 Python"
    fi
    
    # 更新系统服务文件
    if [ -f "/etc/systemd/system/ssl-bot.service" ]; then
        # 备份原文件
        cp "/etc/systemd/system/ssl-bot.service" "/etc/systemd/system/ssl-bot.service.backup"
        
        # 更新 ExecStart
        sed -i "s|ExecStart=.*|ExecStart=$venv_dir/bin/python3 /opt/ssl-bot/ssl-bot.py --scan-and-apply|" "/etc/systemd/system/ssl-bot.service"
        systemctl daemon-reload
        log "更新系统服务配置"
    fi
    
    # 更新 cron 任务
    update_cron_for_venv "$venv_dir"
}

update_cron_for_venv() {
    local venv_dir="$1"
    
    # 删除旧的 cron 任务
    if [ -f "/etc/cron.d/ssl-bot-renew" ]; then
        rm -f "/etc/cron.d/ssl-bot-renew"
    fi
    
    # 创建新的 cron 任务
    cat > "/etc/cron.d/ssl-bot-renew" << EOF
# SSL Bot 自动续签 - 每天凌晨检查
0 2 * * * root $venv_dir/bin/python3 /opt/ssl-bot/ssl-bot.py --renew >> /var/log/ssl-bot-cron.log 2>&1

# SSL Bot 自动扫描 - 每周扫描新域名
0 3 * * 0 root $venv_dir/bin/python3 /opt/ssl-bot/ssl-bot.py --scan-and-apply >> /var/log/ssl-bot-cron.log 2>&1
EOF
    
    log "更新 cron 任务配置"
}

# 下载 SSL Bot
download_ssl_bot() {
    log "下载 SSL Bot..."
    
    # GitHub 仓库地址
    GITHUB_REPO="https://raw.githubusercontent.com/MeDeity/ssl-bot/refs/heads/master"
    
    # 创建安装目录
    INSTALL_DIR="/opt/ssl-bot"
    mkdir -p $INSTALL_DIR
    
    # 下载核心文件
    for file in ssl-bot.py nginx-utils.sh config.yaml; do
        if command -v curl >/dev/null 2>&1; then
            curl -sSL "$GITHUB_REPO/$file" -o "$INSTALL_DIR/$file"
        elif command -v wget >/dev/null 2>&1; then
            wget -q "$GITHUB_REPO/$file" -O "$INSTALL_DIR/$file"
        else
            error "需要 curl 或 wget"
            exit 1
        fi
        
        if [ -f "$INSTALL_DIR/$file" ]; then
            log "下载成功: $GITHUB_REPO/$file"
        else
            error "下载失败: $GITHUB_REPO/$file"
            exit 1
        fi
    done
    
    chmod +x $INSTALL_DIR/ssl-bot.py
    chmod +x $INSTALL_DIR/nginx-utils.sh
}

# 配置系统服务
setup_service() {
    log "配置系统服务..."
    
    cat > /etc/systemd/system/ssl-bot.service << EOF
[Unit]
Description=SSL Bot - Automatic SSL Certificate Manager
After=network.target nginx.service

[Service]
Type=oneshot
ExecStart=$INSTALL_DIR/ssl-bot.py --scan-and-apply
User=root
WorkingDirectory=$INSTALL_DIR

[Install]
WantedBy=multi-user.target
EOF

    # 创建定时任务自动续签
    cat > /etc/cron.d/ssl-bot-renew << EOF
# SSL Bot 自动续签 - 每天凌晨检查
0 2 * * * root $INSTALL_DIR/ssl-bot.py --renew > /dev/null 2>&1

# SSL Bot 自动扫描 - 每周扫描新域名
0 3 * * 0 root $INSTALL_DIR/ssl-bot.py --scan-and-apply > /dev/null 2>&1
EOF
}

# 初始扫描和配置
initial_scan() {
    log "执行初始 Nginx 配置扫描..."
    $INSTALL_DIR/ssl-bot.py --scan-and-apply
}

# 显示使用信息
show_usage() {
    log "安装完成！"
    echo ""
    echo "使用方法:"
    echo "  $INSTALL_DIR/ssl-bot.py --scan-and-apply    # 扫描并应用 SSL"
    echo "  $INSTALL_DIR/ssl-bot.py --renew             # 续签证书"
    echo "  $INSTALL_DIR/ssl-bot.py --status            # 查看状态"
    echo ""
    echo "配置文件: $INSTALL_DIR/config.yaml"
    echo "日志文件: /var/log/ssl-bot.log"
}

# 主函数
main() {
    log "开始安装 SSL Bot..."
    check_root
    detect_os
    install_dependencies
    install_python_deps
    download_ssl_bot
    setup_service
    initial_scan
    show_usage
    log "安装完成！"
}

# 执行主函数
main "$@"