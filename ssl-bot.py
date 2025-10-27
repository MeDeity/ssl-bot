#!/usr/bin/env python3
"""
SSL Bot - 自动 SSL 证书管理工具
自动嗅探 Nginx 配置，申请和续签 Let's Encrypt SSL 证书
"""

import os
import re
import sys
import yaml
import logging
import subprocess
import argparse
from pathlib import Path
from typing import List, Dict, Optional

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/ssl-bot.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

class NginxConfigParser:
    """Nginx 配置解析器"""
    
    def __init__(self, config_path: str = "/etc/nginx"):
        self.config_path = config_path
        self.sites_available = os.path.join(config_path, "sites-available")
        self.sites_enabled = os.path.join(config_path, "sites-enabled")
    
    def find_nginx_configs(self) -> List[str]:
        """查找所有 Nginx 配置文件"""
        configs = []
        
        # 检查 sites-available 和 sites-enabled
        for directory in [self.sites_available, self.sites_enabled]:
            if os.path.exists(directory):
                for file in os.listdir(directory):
                    if file.endswith('.conf') or not '.' in file:
                        configs.append(os.path.join(directory, file))
        
        # 检查 nginx.conf
        main_conf = os.path.join(self.config_path, "nginx.conf")
        if os.path.exists(main_conf):
            configs.append(main_conf)
        
        logger.info(f"找到以下 Nginx 配置文件: {configs}")
        return configs
    
    def parse_server_blocks(self, config_file: str) -> List[Dict]:
        """解析 server 块配置"""
        server_blocks = []
        
        try:
            with open(config_file, 'r') as f:
                content = f.read()
            
            # 使用正则表达式匹配 server 块
            server_pattern = r'server\s*\{([^}]+)\}'
            servers = re.findall(server_pattern, content, re.DOTALL)
            
            for server_content in servers:
                server_info = self._parse_server_content(server_content, config_file)
                if server_info:
                    server_blocks.append(server_info)
                    
        except Exception as e:
            logger.error(f"解析配置文件 {config_file} 失败: {e}")
            
        return server_blocks
    
    def _parse_server_content(self, content: str, config_file: str) -> Optional[Dict]:
        """解析 server 块内容"""
        try:
            # 提取 server_name
            server_name_match = re.search(r'server_name\s+([^;]+);', content)
            if not server_name_match:
                return None
                
            server_names = server_name_match.group(1).strip().split()
            
            # 过滤掉无效域名
            valid_domains = []
            for domain in server_names:
                if domain not in ['_', 'localhost', 'default_server'] and not domain.startswith('~'):
                    valid_domains.append(domain)
            
            if not valid_domains:
                return None
            
            # 提取 root 路径
            root_match = re.search(r'root\s+([^;]+);', content)
            root_path = root_match.group(1) if root_match else "/var/www/html"
            
            # 检查是否已有 SSL 配置
            has_ssl = bool(re.search(r'listen\s+443', content)) or bool(re.search(r'ssl_certificate', content))
            
            return {
                'config_file': config_file,
                'server_names': valid_domains,
                'root_path': root_path,
                'has_ssl': has_ssl,
                'content': content
            }
            
        except Exception as e:
            logger.error(f"解析 server 块失败: {e}")
            return None

class SSLCertManager:
    """SSL 证书管理器"""
    
    def __init__(self, config: Dict):
        self.config = config
        self.email = config.get('email', 'admin@example.com')
    
    def needs_ssl(self, server_block: Dict) -> bool:
        """检查服务器块是否需要 SSL"""
        # 如果已有 SSL，跳过
        if server_block['has_ssl']:
            return False
        
        # 检查域名是否在排除列表中
        exclude_domains = self.config.get('exclude_domains', [])
        for domain in server_block['server_names']:
            if any(excluded in domain for excluded in exclude_domains):
                return False
                
        return True
    
    def apply_ssl(self, server_block: Dict) -> bool:
        """为服务器块申请 SSL 证书"""
        try:
            domains = server_block['server_names']
            primary_domain = domains[0]
            
            logger.info(f"为域名 {', '.join(domains)} 申请 SSL 证书...")
            
            # 构建 certbot 命令
            cmd = [
                'certbot', '--nginx', '--non-interactive', '--agree-tos',
                '--email', self.email, '--redirect', '--hsts'
            ]
            
            # 添加所有域名
            for domain in domains:
                cmd.extend(['-d', domain])
            
            # 执行 certbot 命令
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
            
            if result.returncode == 0:
                logger.info(f"成功为 {primary_domain} 申请 SSL 证书")
                return True
            else:
                logger.error(f"申请 SSL 证书失败: {result.stderr}")
                return False
                
        except subprocess.CalledProcessError as e:
            logger.error(f"Certbot 执行失败: {e.stderr}")
            return False
        except Exception as e:
            logger.error(f"申请 SSL 证书时发生错误: {e}")
            return False
    
    def renew_certificates(self) -> bool:
        """续签所有证书"""
        try:
            logger.info("开始续签 SSL 证书...")
            
            # 测试续签（dry run）
            test_cmd = ['certbot', 'renew', '--dry-run']
            test_result = subprocess.run(test_cmd, capture_output=True, text=True)
            
            if test_result.returncode == 0:
                # 实际续签
                renew_cmd = ['certbot', 'renew', '--quiet']
                renew_result = subprocess.run(renew_cmd, capture_output=True, text=True, check=True)
                
                if renew_result.returncode == 0:
                    logger.info("SSL 证书续签成功")
                    
                    # 重新加载 Nginx
                    subprocess.run(['systemctl', 'reload', 'nginx'], check=True)
                    logger.info("Nginx 重新加载配置")
                    
                    return True
            else:
                logger.error("续签测试失败，跳过实际续签")
                return False
                
        except Exception as e:
            logger.error(f"续签证书失败: {e}")
            return False
    
    def get_certificate_status(self) -> Dict:
        """获取证书状态"""
        try:
            cmd = ['certbot', 'certificates']
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
            
            certificates = {}
            lines = result.stdout.split('\n')
            
            current_domain = None
            for line in lines:
                if 'Certificate Name:' in line:
                    current_domain = line.split(':')[1].strip()
                    certificates[current_domain] = {}
                elif 'Domains:' in line and current_domain:
                    domains = line.split(':')[1].strip()
                    certificates[current_domain]['domains'] = domains
                elif 'Expiry Date:' in line and current_domain:
                    expiry = line.split(':')[1].strip()
                    certificates[current_domain]['expiry'] = expiry
                elif 'Certificate Path:' in line and current_domain:
                    path = line.split(':')[1].strip()
                    certificates[current_domain]['path'] = path
            
            return certificates
            
        except Exception as e:
            logger.error(f"获取证书状态失败: {e}")
            return {}

class SSLBot:
    """SSL Bot 主类"""
    
    def __init__(self):
        self.config = self.load_config()
        self.nginx_parser = NginxConfigParser()
        self.ssl_manager = SSLCertManager(self.config)
    
    def load_config(self) -> Dict:
        """加载配置文件"""
        config_path = "/opt/ssl-bot/config.yaml"
        default_config = {
            'email': 'admin@example.com',
            'exclude_domains': ['localhost', 'test', 'staging'],
            'auto_renew': True,
            'scan_interval': 86400  # 24小时
        }
        
        try:
            if os.path.exists(config_path):
                with open(config_path, 'r') as f:
                    user_config = yaml.safe_load(f) or {}
                # 合并配置
                default_config.update(user_config)
        except Exception as e:
            logger.error(f"加载配置文件失败: {e}")
            
        return default_config
    
    def scan_and_apply(self):
        """扫描 Nginx 配置并应用 SSL"""
        logger.info("开始扫描 Nginx 配置...")
        
        config_files = self.nginx_parser.find_nginx_configs()
        logger.info(f"找到 {len(config_files)} 个配置文件")
        
        ssl_applied = 0
        
        for config_file in config_files:
            server_blocks = self.nginx_parser.parse_server_blocks(config_file)
            
            for server_block in server_blocks:
                if self.ssl_manager.needs_ssl(server_block):
                    logger.info(f"发现需要 SSL 的配置: {server_block['server_names']}")
                    
                    if self.ssl_manager.apply_ssl(server_block):
                        ssl_applied += 1
        
        logger.info(f"扫描完成，共为 {ssl_applied} 个服务应用了 SSL")
        return ssl_applied
    
    def renew(self):
        """续签证书"""
        return self.ssl_manager.renew_certificates()
    
    def status(self):
        """显示状态"""
        certificates = self.ssl_manager.get_certificate_status()
        
        print("SSL Bot 状态报告")
        print("=" * 50)
        
        if certificates:
            for domain, info in certificates.items():
                print(f"域名: {domain}")
                print(f"  包含: {info.get('domains', 'N/A')}")
                print(f"  过期: {info.get('expiry', 'N/A')}")
                print(f"  路径: {info.get('path', 'N/A')}")
                print("-" * 30)
        else:
            print("未找到 SSL 证书")
        
        # 扫描当前需要 SSL 的配置
        config_files = self.nginx_parser.find_nginx_configs()
        needs_ssl = []
        
        for config_file in config_files:
            server_blocks = self.nginx_parser.parse_server_blocks(config_file)
            for server_block in server_blocks:
                if self.ssl_manager.needs_ssl(server_block):
                    needs_ssl.extend(server_block['server_names'])
        
        if needs_ssl:
            print(f"\n需要 SSL 的域名: {', '.join(set(needs_ssl))}")


class DomainManager:
    """域名管理器"""
    
    def __init__(self, config: Dict):
        self.config = config
        self.nginx_parser = NginxConfigParser()
    
    def setup_domain(self, domain: str, webroot: str = None) -> bool:
        """设置新域名"""
        try:
            if not webroot:
                webroot = f"/var/www/{domain}/html"
            
            logger.info(f"设置域名: {domain} -> {webroot}")
            
            # 创建网站目录
            self.create_web_directory(domain, webroot)
            
            # 创建 Nginx 配置
            if self.create_nginx_config(domain, webroot):
                # 测试并重载 Nginx
                if self.reload_nginx():
                    logger.info(f"域名设置成功: {domain}")
                    return True
            
            return False
            
        except Exception as e:
            logger.error(f"设置域名失败 {domain}: {e}")
            return False
    
    def create_web_directory(self, domain: str, webroot: str):
        """创建网站目录"""
        os.makedirs(webroot, exist_ok=True)
        
        # 创建默认页面
        index_file = os.path.join(webroot, "index.html")
        with open(index_file, 'w') as f:
            f.write(f'''<!DOCTYPE html>
<html>
<head>
    <title>欢迎来到 {domain}</title>
    <meta charset="utf-8">
</head>
<body>
    <h1>欢迎访问 {domain}</h1>
    <p>此站点由 SSL Bot 自动配置</p>
    <p>SSL 证书将自动申请和安装</p>
</body>
</html>''')
        
        # 设置权限
        subprocess.run(["chown", "-R", "www-data:www-data", os.path.dirname(webroot)], check=True)
        subprocess.run(["chmod", "-R", "755", os.path.dirname(webroot)], check=True)
        
        logger.info(f"创建网站目录: {webroot}")
    
    def create_nginx_config(self, domain: str, webroot: str) -> bool:
        """创建 Nginx 配置"""
        try:
            config_content = fr'''
server {{
    listen 80;
    listen [::]:80;
    server_name {domain};
    root {webroot};
    index index.html index.htm;
    
    # 安全头
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    
    location / {{
        try_files $uri $uri/ =404;
    }}
    
    location ~* \.(jpg|jpeg|png|gif|ico|css|js)$ {{
        expires 1y;
        add_header Cache-Control "public, immutable";
    }}
    
    location ~ /\\. {{
        deny all;
    }}
}}
'''
            # 写入配置文件
            config_path = f"/etc/nginx/sites-available/{domain}"
            with open(config_path, 'w') as f:
                f.write(config_content)
            
            # 启用站点
            enabled_path = f"/etc/nginx/sites-enabled/{domain}"
            if not os.path.exists(enabled_path):
                os.symlink(config_path, enabled_path)
            
            logger.info(f"Nginx 配置创建成功: {domain}")
            return True
            
        except Exception as e:
            logger.error(f"创建 Nginx 配置失败: {e}")
            return False
    
    def reload_nginx(self) -> bool:
        """重载 Nginx 配置"""
        try:
            # 测试配置
            subprocess.run(["nginx", "-t"], check=True, capture_output=True)
            # 重载
            subprocess.run(["systemctl", "reload", "nginx"], check=True)
            logger.info("Nginx 重载成功")
            return True
        except subprocess.CalledProcessError as e:
            logger.error(f"Nginx 重载失败: {e}")
            return False
    
    def list_domains(self) -> List[Dict]:
        """列出所有已配置的域名"""
        domains = []
        sites_available = "/etc/nginx/sites-available"
        
        if os.path.exists(sites_available):
            for file in os.listdir(sites_available):
                if file not in ['default', '000-default']:
                    config_file = os.path.join(sites_available, file)
                    with open(config_file, 'r') as f:
                        content = f.read()
                        # 提取 server_name
                        import re
                        match = re.search(r'server_name\s+([^;]+);', content)
                        if match:
                            server_names = match.group(1).strip().split()
                            for name in server_names:
                                if name not in ['_', 'localhost'] and not name.startswith('~'):
                                    domains.append({
                                        'domain': name,
                                        'config_file': config_file,
                                        'enabled': os.path.exists(f"/etc/nginx/sites-enabled/{file}")
                                    })
        
        return domains
    
def main():
    parser = argparse.ArgumentParser(description='SSL Bot - 自动 SSL 证书管理')
    parser.add_argument('--scan-and-apply', action='store_true', help='扫描并应用 SSL')
    parser.add_argument('--renew', action='store_true', help='续签证书')
    parser.add_argument('--status', action='store_true', help='显示状态')
    parser.add_argument('--add-domain', type=str, help='添加新域名')
    parser.add_argument('--list-domains', action='store_true', help='列出所有域名')
    parser.add_argument('--webroot', type=str, help='网站根目录路径（与 --add-domain 一起使用）')
    args = parser.parse_args()
    
    bot = SSLBot()
    
    if args.scan_and_apply:
        bot.scan_and_apply()
    elif args.renew:
        bot.renew()
    elif args.status:
        bot.status()
    elif args.add_domain:
        webroot = args.webroot or f"/var/www/{args.add_domain}/html"
        domain_manager = DomainManager(bot.config)
        if domain_manager.setup_domain(args.add_domain, webroot):
            # 自动为新域名申请 SSL
            bot.scan_and_apply()
    elif args.list_domains:
        domain_manager = DomainManager(bot.config)
        domains = domain_manager.list_domains()
        print("已配置的域名:")
        for domain_info in domains:
            status = "已启用" if domain_info['enabled'] else "未启用"
            print(f"  - {domain_info['domain']} ({status})")
    else:
        parser.print_help()

if __name__ == '__main__':
    main()