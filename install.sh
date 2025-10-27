#!/bin/bash

# SSL Bot 一键安装脚本
# 使用方法: wget -qO- https://raw.githubusercontent.com/MeDeity/ssl-bot/refs/heads/master/install.sh | bash

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
        apt-get install -y python3 python3-pip nginx curl wget
         # 安装 certbot 和 nginx 插件
        apt-get install -y certbot python3-certbot-nginx

    elif command -v yum >/dev/null 2>&1; then
        # CentOS/RHEL
        yum install -y python3 python3-pip certbot nginx curl wget
        # 安装 EPEL 仓库（包含 certbot）
        yum install -y epel-release
        yum install -y certbot python3-certbot-nginx

    elif command -v dnf >/dev/null 2>&1; then
        # Fedora
        dnf install -y python3 python3-pip nginx curl wget
        dnf install -y certbot python3-certbot-nginx
    else
        error "不支持的包管理器"
        exit 1
    fi
}

verify_certbot_installation() {
    log "验证 Certbot 安装..."
    
    # 检查 certbot 命令是否存在
    if ! command -v certbot >/dev/null 2>&1; then
        error "Certbot 未安装"
        return 1
    fi
    
    # 检查 nginx 插件
    if certbot plugins | grep -q nginx; then
        log "✓ Certbot Nginx 插件已安装"
        return 0
    else
        error "✗ Certbot Nginx 插件未安装"
        
        # 尝试修复安装
        warn "尝试安装 Certbot Nginx 插件..."
        if command -v apt-get >/dev/null 2>&1; then
            apt-get install -y python3-certbot-nginx
        elif command -v yum >/dev/null 2>&1; then
            yum install -y python3-certbot-nginx
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y python3-certbot-nginx
        fi
        
        # 再次验证
        if certbot plugins | grep -q nginx; then
            log "✓ Certbot Nginx 插件安装成功"
            return 0
        else
            error "✗ Certbot Nginx 插件安装失败"
            return 1
        fi
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
    echo "  $INSTALL_DIR/ssl-bot.py --add-domain example.com  # 添加新域名"
    echo "  $INSTALL_DIR/ssl-bot.py --list-domains      # 列出所有域名"
    echo ""
    echo "环境变量:"
    echo "  SSL_BOT_EMAIL=email@example.com    # 设置邮箱"
    echo "  SSL_BOT_DOMAINS=domain1.com,domain2.com  # 设置域名"
    echo ""
    echo "配置文件: $INSTALL_DIR/config.yaml"
    echo "日志文件: /var/log/ssl-bot.log"
}

get_user_email() {
    log "配置管理员邮箱..."
    
    # 读取当前配置中的邮箱
    CURRENT_EMAIL=$(grep -E '^email:' /opt/ssl-bot/config.yaml | cut -d ' ' -f 2 | tr -d '"' | tr -d "'" | tr -d ' ')
    
    log "当前读取到的邮箱: '$CURRENT_EMAIL'"
    
    # 首先检查环境变量
    if [ ! -z "$SSL_BOT_EMAIL" ]; then
        log "使用环境变量中的邮箱: $SSL_BOT_EMAIL"
        sed -i "s/email:.*/email: \"$SSL_BOT_EMAIL\"/" /opt/ssl-bot/config.yaml
        return 0
    fi
    
    # 如果已经是真实邮箱，跳过
    if [[ "$CURRENT_EMAIL" != "your-email@example.com" ]] && [[ "$CURRENT_EMAIL" != "admin@example.com" ]] && [[ ! -z "$CURRENT_EMAIL" ]]; then
        log "当前邮箱配置已经是真实邮箱: $CURRENT_EMAIL"
        return 0
    fi
    
    # 检查是否在终端中运行
    if [ ! -t 0 ]; then
        error "检测到非交互式终端，且未设置 SSL_BOT_EMAIL 环境变量"
        error "请使用以下方式之一设置邮箱:"
        error "1. 设置环境变量: export SSL_BOT_EMAIL='your-email@example.com'"
        error "2. 手动修改配置文件: nano /opt/ssl-bot/config.yaml"
        error "3. 重新运行: bash install.sh (不要使用管道)"
        return 1
    fi
    
    # 提示用户输入邮箱
    echo ""
    echo "=========================================="
    echo "SSL Bot 需要配置真实邮箱地址"
    echo "用于接收证书到期通知和 Let's Encrypt 注册"
    echo "=========================================="
    echo ""
    
    while true; do
        echo -n "请输入您的邮箱地址: "
        read USER_EMAIL < /dev/tty
        
        # 如果用户直接回车，重新提示
        if [[ -z "$USER_EMAIL" ]]; then
            error "邮箱地址不能为空，请重新输入"
            continue
        fi
        
        # 简单的邮箱格式验证
        if [[ "$USER_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            # 更新配置文件
            if sed -i "s/email:.*/email: \"$USER_EMAIL\"/" /opt/ssl-bot/config.yaml; then
                log "邮箱地址已更新为: $USER_EMAIL"
                break
            else
                error "更新配置文件失败"
                return 1
            fi
        else
            error "邮箱格式不正确，请重新输入"
        fi
    done
}

get_user_domains() {
    log "配置域名和服务类型..."
    
    # 检查是否在终端中运行
    if [ ! -t 0 ] && [ -z "$SSL_BOT_DOMAINS" ]; then
        warn "检测到非交互式终端，跳过域名配置"
        return 0
    fi
    
    # 检查环境变量
    if [ ! -z "$SSL_BOT_DOMAINS" ]; then
        log "使用环境变量中的域名: $SSL_BOT_DOMAINS"
        IFS=',' read -ra DOMAIN_ARRAY <<< "$SSL_BOT_DOMAINS"
        setup_domains "${DOMAIN_ARRAY[@]}"
        return 0
    fi
    
    echo ""
    echo "=========================================="
    echo "SSL Bot 域名配置"
    echo "支持多种服务类型：静态网站、PHP、反向代理"
    echo "=========================================="
    echo ""
    
    echo -n "是否要配置新域名？(y/N): "
    read response < /dev/tty
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo ""
        echo "请输入要配置的域名（多个域名用空格分隔）:"
        echo "例如: example.com www.example.com"
        echo -n "域名: "
        read user_domains < /dev/tty
        
        if [[ ! -z "$user_domains" ]]; then
            # 询问服务类型
            select_service_type "$user_domains"
        else
            log "未输入域名，跳过配置"
        fi
    else
        log "跳过域名配置"
    fi
}

select_service_type() {
    local domains=($1)
    
    echo ""
    echo "请选择服务类型:"
    echo "1) 静态网站 (HTML/CSS/JS)"
    echo "2) PHP 网站"
    echo "3) 反向代理 (Tomcat/Node.js/Python等)"
    echo "4) Tomcat 应用 (专用配置)"
    echo -n "请选择 [1-4]: "
    
    read service_choice < /dev/tty
    
    case $service_choice in
        1)
            setup_domains "static" "${domains[@]}"
            ;;
        2)
            setup_domains "php" "${domains[@]}"
            ;;
        3)
            setup_reverse_proxy "${domains[@]}"
            ;;
        4)
            setup_tomcat_proxy "${domains[@]}"
            ;;
        *)
            echo "使用默认配置: 静态网站"
            setup_domains "static" "${domains[@]}"
            ;;
    esac
}

setup_domains() {
    local service_type="$1"
    shift
    local domains=("$@")
    
    log "开始配置域名 (服务类型: $service_type): ${domains[*]}"
    
    # 确保 Nginx 服务状态正常
    if ! ensure_nginx_service; then
        error "Nginx 服务状态异常，无法继续配置域名"
        return 1
    fi
    
    for domain in "${domains[@]}"; do
        if validate_domain "$domain"; then
            case $service_type in
                "static")
                    create_nginx_static_config "$domain"
                    create_web_directory "$domain"
                    ;;
                "php")
                    create_nginx_php_config "$domain"
                    create_web_directory "$domain"
                    ;;
                *)
                    create_nginx_static_config "$domain"
                    create_web_directory "$domain"
                    ;;
            esac
        else
            error "域名格式无效: $domain"
        fi
    done
    
    # 重新加载 Nginx 配置
    if ! reload_nginx_config; then
        error "Nginx 配置重载失败"
        return 1
    fi
    
    log "域名配置完成"
}

setup_reverse_proxy() {
    local domains=("$@")
    
    log "配置反向代理域名: ${domains[*]}"
    
    # 获取后端服务信息
    echo ""
    echo "请输入后端服务信息:"
    echo -n "后端服务地址 (例如: http://localhost:8080 或 http://192.168.1.100:3000): "
    read backend_url < /dev/tty
    
    if [[ -z "$backend_url" ]]; then
        error "后端服务地址不能为空"
        return 1
    fi
    
    echo -n "应用路径 (可选，默认: /): "
    read app_path < /dev/tty
    app_path=${app_path:-"/"}
    
    # 确保 Nginx 服务状态正常
    if ! ensure_nginx_service; then
        error "Nginx 服务状态异常，无法继续配置域名"
        return 1
    fi
    
    for domain in "${domains[@]}"; do
        if validate_domain "$domain"; then
            create_nginx_proxy_config "$domain" "$backend_url" "$app_path"
        else
            error "域名格式无效: $domain"
        fi
    done
    
    # 重新加载 Nginx 配置
    if ! reload_nginx_config; then
        error "Nginx 配置重载失败"
        return 1
    fi
    
    log "反向代理配置完成"
}

setup_tomcat_proxy() {
    local domains=("$@")
    
    log "配置 Tomcat 代理域名: ${domains[*]}"
    
    # 获取 Tomcat 服务信息
    echo ""
    echo "请输入 Tomcat 服务信息:"
    echo -n "Tomcat 地址 (默认: http://localhost:8080): "
    read tomcat_url < /dev/tty
    tomcat_url=${tomcat_url:-"http://localhost:8080"}
    
    echo -n "应用路径 (例如: /demo 或 /myapp): "
    read app_path < /dev/tty
    app_path=${app_path:-"/"}
    
    # 确保 Nginx 服务状态正常
    if ! ensure_nginx_service; then
        error "Nginx 服务状态异常，无法继续配置域名"
        return 1
    fi
    
    for domain in "${domains[@]}"; do
        if validate_domain "$domain"; then
            create_nginx_tomcat_config "$domain" "$tomcat_url" "$app_path"
        else
            error "域名格式无效: $domain"
        fi
    done
    
    # 重新加载 Nginx 配置
    if ! reload_nginx_config; then
        error "Nginx 配置重载失败"
        return 1
    fi
    
    log "Tomcat 代理配置完成"
}


create_nginx_static_config() {
    local domain="$1"
    local config_file="/etc/nginx/sites-available/$domain"
    local webroot="/var/www/$domain/html"
    
    log "创建静态网站配置: $config_file"
    
    cat > "$config_file" << EOF
server {
    listen 80;
    listen [::]:80;
    
    server_name $domain;
    root $webroot;
    index index.html index.htm;
    
    # 安全头
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    
    # 静态文件缓存
    location ~* \.(jpg|jpeg|png|gif|ico|css|js)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # 隐藏点文件
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
    
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
    
    enable_nginx_site "$domain" "$config_file"
}

create_nginx_php_config() {
    local domain="$1"
    local config_file="/etc/nginx/sites-available/$domain"
    local webroot="/var/www/$domain/html"
    
    log "创建 PHP 网站配置: $config_file"
    
    cat > "$config_file" << EOF
server {
    listen 80;
    listen [::]:80;
    
    server_name $domain;
    root $webroot;
    index index.php index.html index.htm;
    
    # 安全头
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    
    # PHP 处理
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
    
    # 静态文件缓存
    location ~* \.(jpg|jpeg|png|gif|ico|css|js)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # 隐藏点文件
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
    
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
}
EOF
    
    enable_nginx_site "$domain" "$config_file"
}

create_nginx_proxy_config() {
    local domain="$1"
    local backend_url="$2"
    local app_path="$3"
    local config_file="/etc/nginx/sites-available/$domain"
    
    log "创建反向代理配置: $domain -> $backend_url$app_path"
    
    cat > "$config_file" << EOF
server {
    listen 80;
    listen [::]:80;
    
    server_name $domain;
    
    # 安全头
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    
    # 反向代理配置
    location $app_path {
        proxy_pass $backend_url;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # 超时设置
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # 缓冲区设置
        proxy_buffering on;
        proxy_buffer_size 4k;
        proxy_buffers 8 4k;
        
        # WebSocket 支持
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    
    # 可选的静态文件服务
    location /static/ {
        alias /var/www/$domain/static/;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # 根路径重定向到应用
    location = / {
        return 302 $app_path;
    }
}
EOF
    
    enable_nginx_site "$domain" "$config_file"
}

create_nginx_tomcat_config() {
    local domain="$1"
    local tomcat_url="$2"
    local app_path="$3"
    local config_file="/etc/nginx/sites-available/$domain"
    
    log "创建 Tomcat 代理配置: $domain -> $tomcat_url$app_path"
    
    # 确保 Tomcat URL 以 / 结尾
    if [[ "$tomcat_url" != */ ]]; then
        tomcat_url="$tomcat_url/"
    fi
    
    cat > "$config_file" << EOF
server {
    listen 80;
    listen [::]:80;
    
    server_name $domain;
    
    # 安全头
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    
    # Tomcat 应用代理
    location $app_path {
        proxy_pass $tomcat_url;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Tomcat 特定设置
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Server \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        
        # 超时设置
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # 缓冲区设置
        proxy_buffering on;
        proxy_buffer_size 16k;
        proxy_buffers 4 16k;
        
        # 禁用缓存，确保动态内容实时更新
        proxy_no_cache 1;
        proxy_cache_bypass 1;
    }
    
    # 静态资源缓存
    location ~* \.(jpg|jpeg|png|gif|ico|css|js)$ {
        proxy_pass $tomcat_url;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # 健康检查端点
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
EOF
    
    enable_nginx_site "$domain" "$config_file"
}

enable_nginx_site() {
    local domain="$1"
    local config_file="$2"
    
    # 启用站点
    if [ ! -f "/etc/nginx/sites-enabled/$domain" ]; then
        ln -s "$config_file" "/etc/nginx/sites-enabled/$domain"
        log "Nginx 站点已启用: $domain"
    else
        log "Nginx 站点已存在: $domain"
    fi
}

ensure_nginx_service() {
    log "检查 Nginx 服务状态..."
    
    # 检查 Nginx 是否安装
    if ! command -v nginx >/dev/null 2>&1; then
        error "Nginx 未安装"
        return 1
    fi
    
    # 检查 Nginx 服务状态
    if systemctl is-active nginx >/dev/null 2>&1; then
        log "Nginx 服务正在运行"
        return 0
    else
        warn "Nginx 服务未运行，尝试启动..."
        
        # 首先测试配置文件
        if ! nginx -t >/dev/null 2>&1; then
            error "Nginx 配置测试失败，请检查配置"
            return 1
        fi
        
        # 启动 Nginx 服务
        if systemctl start nginx; then
            log "Nginx 服务启动成功"
            
            # 启用开机自启
            if systemctl enable nginx >/dev/null 2>&1; then
                log "Nginx 服务已设置为开机自启"
            fi
            
            return 0
        else
            error "Nginx 服务启动失败"
            return 1
        fi
    fi
}

reload_nginx_config() {
    log "重新加载 Nginx 配置..."
    
    # 首先测试配置文件语法
    if ! nginx -t; then
        error "Nginx 配置测试失败，请检查配置文件"
        return 1
    fi
    
    # 检查 Nginx 是否正在运行
    if systemctl is-active nginx >/dev/null 2>&1; then
        # 如果正在运行，重新加载
        if systemctl reload nginx; then
            log "Nginx 配置重新加载成功"
            return 0
        else
            error "Nginx 重新加载失败"
            return 1
        fi
    else
        # 如果没有运行，启动服务
        warn "Nginx 服务未运行，尝试启动..."
        if systemctl start nginx; then
            log "Nginx 服务启动成功"
            return 0
        else
            error "Nginx 服务启动失败"
            return 1
        fi
    fi
}

validate_domain() {
    local domain="$1"
    
    # 基本域名格式验证
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 1
    fi
    
    # 检查是否在排除列表中
    local exclude_patterns=("localhost" "example.com" "test." "internal.")
    for pattern in "${exclude_patterns[@]}"; do
        if [[ "$domain" == *"$pattern"* ]]; then
            return 1
        fi
    done
    
    return 0
}

create_web_directory() {
    local domain="$1"
    local webroot="/var/www/$domain/html"
    
    log "创建网站目录: $webroot"
    
    mkdir -p "$webroot"
    
    # 创建默认首页
    cat > "$webroot/index.html" << EOF
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>欢迎来到 $domain</title>
    <style>
        body { 
            font-family: Arial, sans-serif; 
            max-width: 800px; 
            margin: 0 auto; 
            padding: 20px; 
            text-align: center;
        }
        .container { 
            margin-top: 50px; 
        }
        .success { 
            color: #28a745; 
            font-size: 24px; 
            margin-bottom: 20px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="success">✓ 网站配置成功</div>
        <h1>欢迎访问 $domain</h1>
        <p>此网站由 SSL Bot 自动配置</p>
        <p>接下来将自动配置 SSL 证书...</p>
    </div>
</body>
</html>
EOF
    
    # 设置目录权限
    chown -R www-data:www-data "/var/www/$domain"
    chmod -R 755 "/var/www/$domain"
    
    log "网站目录创建完成: $webroot"
}

create_nginx_config() {
    local domain="$1"
    local config_file="/etc/nginx/sites-available/$domain"
    
    log "创建 Nginx 配置: $config_file"
    
    # 创建 Nginx 配置
    cat > "$config_file" << EOF
server {
    listen 80;
    listen [::]:80;
    
    server_name $domain;
    root /var/www/$domain/html;
    index index.html index.htm;
    
    # 安全头
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    
    # 静态文件缓存
    location ~* \.(jpg|jpeg|png|gif|ico|css|js)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # 隐藏 .htaccess 等文件
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
    
    # 基础安全设置
    location = /favicon.ico {
        log_not_found off;
        access_log off;
    }
    
    location = /robots.txt {
        log_not_found off;
        access_log off;
    }
    
    # 主位置块
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
    
    # 启用站点
    if [ ! -f "/etc/nginx/sites-enabled/$domain" ]; then
        ln -s "$config_file" "/etc/nginx/sites-enabled/$domain"
        log "Nginx 站点已启用: $domain"
    fi
    
    log "Nginx 配置创建完成: $domain"
}

# 主函数
main() {
    log "开始安装 SSL Bot..."
    check_root
    detect_os
    install_dependencies
    # 验证 certbot 安装
    if ! verify_certbot_installation; then
        error "Certbot 验证失败，安装中止"
        exit 1
    fi
    install_python_deps
    download_ssl_bot
    get_user_email
    get_user_domains
    setup_service
    initial_scan
    show_usage
    log "安装完成！"
}

# 执行主函数
main "$@"