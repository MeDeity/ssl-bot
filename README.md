
# 🔐 SSL Bot - 智能 SSL 证书管理机器人

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python](https://img.shields.io/badge/Python-3.6%2B-blue)](https://www.python.org/)
[![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20macOS%20%7C%20WSL-brightgreen)]()

> 一个强大的 Shell + Python 混合实现的 SSL 证书自动化管理工具，让 HTTPS 配置变得简单而优雅。[本项目由MeDeity&DeepSeek联合出品，旨在助力开发者轻松管理SSL证书。] 感谢强大的DeepSeek的支持！



## ✨ 核心特性

- 🚀 **全自动证书管理** - 从申请到续签，一键搞定
- 🛡️ **多服务类型支持** - 静态站点、PHP、代理、Tomcat 全覆盖
- 📊 **智能状态监控** - 实时掌握证书健康状况
- 🔄 **无缝续签机制** - 永不担心证书过期
- 🎯 **精准域名管理** - 轻松添加、配置和管理域名
- ⚡ **高性能代理** - 内置优化的 Nginx 配置模板

## 🎯 功能一览

| 功能 | 命令 | 描述 |
|------|------|------|
| 扫描并应用 | `--scan-and-apply` | 自动扫描并配置 SSL 证书 |
| 证书续签 | `--renew` | 一键续签所有证书 |
| 状态查看 | `--status` | 显示证书和域名状态 |
| 添加域名 | `--add-domain` | 添加新域名并配置 SSL |
| 域名列表 | `--list-domains` | 列出所有托管域名 |

## 🚀 快速开始

### 系统要求

- Ubuntu 16.04+ / CentOS 7+ / 其他主流 Linux 发行版
- Python 3.6+
- Nginx
- Certbot (Let's Encrypt)

### 📋 安装步骤

#### 📦 自动安装脚本
```bash
# Mothod 1：use curl
curl -sSL https://raw.githubusercontent.com/MeDeity/ssl-bot/refs/heads/master/install.sh | bash

# Mothod 2：use wget  
wget -qO- https://raw.githubusercontent.com/MeDeity/ssl-bot/refs/heads/master/install.sh | bash
```

#### 🛠️ 手动安装步骤
```bash
# 1. 克隆项目
git clone https://github.com/MeDeity/ssl-bot.git
cd ssl-bot

# 2. 安装依赖
sudo apt update
sudo apt install -y python3 python3-pip nginx certbot

# 3. 配置脚本权限
chmod +x ssl-bot
sudo cp ssl-bot /usr/local/bin/

# 4. 验证安装
ssl-bot --help
```

## 💡 使用指南

### 基础使用

```bash
# 查看所有域名状态
ssl-bot --status

# 列出所有托管域名
ssl-bot --list-domains

# 自动扫描并配置 SSL
ssl-bot --scan-and-apply

# 续签所有证书
ssl-bot --renew
```

### 添加新域名

#### 静态网站
```bash
ssl-bot --add-domain example.com --service-type static
```

#### PHP 应用
```bash
ssl-bot --add-domain app.example.com --service-type php --app-path /var/www/html
```

#### 反向代理
```bash
ssl-bot --add-domain api.example.com --service-type proxy \
    --backend-url http://localhost:8080 \
    --app-path /api/v1
```

#### Tomcat 应用
```bash
ssl-bot --add-domain java.example.com --service-type tomcat \
    --backend-url http://localhost:8080 \
    --app-path /myapp
```

## ⚙️ 配置详解

### 服务类型说明

| 服务类型 | 适用场景 | 关键参数 |
|----------|----------|----------|
| `static` | 静态网站、Vue/React 应用 | `app-path` (可选) |
| `php` | PHP 应用、WordPress | `app-path` (必需) |
| `proxy` | 反向代理、API 网关 | `backend-url`, `app-path` |
| `tomcat` | Java Web 应用 | `backend-url`, `app-path` |

### 高级配置

环境变量配置（可选）：
```bash
export SSL_BOT_EMAIL=admin@example.com  # 证书通知邮箱
export SSL_BOT_WEBROOT=/var/www/html    # 默认 Web 根目录
```

## 🛠️ 技术架构

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Shell 脚本    │───▶│   Python 核心    │───▶│   Certbot API   │
│   (用户接口)    │    │   (业务逻辑)     │    │   (证书操作)    │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                              │
                              ▼
                      ┌─────────────────┐
                      │   Nginx 配置    │
                      │   (服务代理)    │
                      └─────────────────┘
```

## 🔧 故障排除

### 常见问题

**Q: 证书申请失败**
```bash
# 检查域名解析
nslookup your-domain.com
# 检查端口开放
sudo netstat -tulpn | grep :80
```

**Q: Nginx 配置错误**
```bash
# 测试配置
sudo nginx -t
# 查看错误日志
sudo tail -f /var/log/nginx/error.log
```

**Q: 续签失败**
```bash
# 手动测试续签
sudo certbot renew --dry-run
```

### 调试模式

```bash
# 启用详细日志
SSL_BOT_DEBUG=1 ssl-bot --add-domain example.com --service-type static
```

## 📊 状态监控

集成状态检查功能，实时监控证书健康：

```bash
ssl-bot --status

# 输出示例：
# 🔐 域名状态报告
# ┌──────────────────────┬──────────────┬────────────┬──────────┐
# │       域名           │   证书状态   │  过期时间  │ 服务类型 │
# ├──────────────────────┼──────────────┼────────────┼──────────┤
# │ example.com         │ ✅ 有效      │ 90天后     │ static   │
# │ api.example.com     │ ⚠️ 即将过期  │ 15天后     │ proxy    │
# └──────────────────────┴──────────────┴────────────┴──────────┘
```

## 🤝 贡献指南

我们欢迎所有形式的贡献！请参阅 [CONTRIBUTING.md](CONTRIBUTING.md) 了解详情。

1. Fork 本项目
2. 创建功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启 Pull Request

## 📄 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。

## 🏆 致谢

感谢以下项目的支持：
- [Let's Encrypt](https://letsencrypt.org/) - 免费的 SSL/TLS 证书
- [Certbot](https://certbot.eff.org/) - 自动化证书管理
- [Nginx](https://nginx.org/) - 高性能 Web 服务器

---

**星星这个项目 ⭐** 如果你觉得这个工具对你有帮助！

---
*由 [MeDeity](https://github.com/MeDeity) 用 ❤️ 打造*



