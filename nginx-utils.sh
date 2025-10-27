#!/bin/bash

# Nginx 工具函数

nginx_test() {
    if ! nginx -t > /dev/null 2>&1; then
        echo "Nginx 配置测试失败"
        return 1
    fi
    return 0
}

nginx_reload() {
    if nginx_test; then
        systemctl reload nginx
        echo "Nginx 重新加载成功"
    else
        echo "Nginx 配置有错误，请检查"
        return 1
    fi
}

nginx_restart() {
    if nginx_test; then
        systemctl restart nginx
        echo "Nginx 重启成功"
    else
        echo "Nginx 配置有错误，请检查"
        return 1
    fi
}

# 导出函数
export -f nginx_test
export -f nginx_reload
export -f nginx_restart