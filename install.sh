#!/usr/bin/env bash

set -e

# 颜色定义
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# 检查 root 权限
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

# 检测操作系统及版本（略，保持原有逻辑）
# ...

# 检测系统架构
get_arch() {
    local arch=$(uname -m)
    case $arch in
        x86_64|amd64| x64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        i386|i686) echo "386" ;;
        armv7l) echo "armv7" ;;
        *) echo "unsupported" ;;
    esac
}

# 安装基础依赖
install_base() {
    echo -e "${green}正在安装基础依赖...${plain}"
    if [[ x"${release}" == x"centos" ]]; then
        yum install wget curl tar unzip -y
    else
        apt update
        apt install wget curl tar unzip -y
    fi
}

# 主安装函数
install_x-ui() {
    systemctl stop x-ui 2>/dev/null || true
    cd /usr/local/
    local arch=$(get_arch)
    if [[ $arch == "unsupported" ]]; then
        echo -e "${red}错误：不支持的系统架构 $(uname -m)${plain}"
        exit 1
    fi

    local last_version
    if [[ $# -eq 0 ]]; then
        echo -e "${green}未指定版本，正在获取最新版本...${plain}"
        last_version=$(curl -Lsk "https://api.github.com/repos/gm-cx/x-ui/releases/latest" | grep -oP '"tag_name": "\K[^"]+')
        if [[ -z "$last_version" ]]; then
            echo -e "${red}检测 x-ui 版本失败，可能是超出 Github API 限制，请稍后再试，或手动指定 x-ui 版本安装${plain}"
            exit 1
        fi
        echo -e "${green}检测到最新版本：${last_version}，开始安装${plain}"
    else
        last_version=$1
        echo -e "${green}开始安装指定版本：${last_version}${plain}"
    fi

    local url="https://github.com/gm-cx/x-ui/releases/download/${last_version}/x-ui-linux-${arch}.tar.gz"
    wget -N --no-check-certificate -O "/usr/local/x-ui-linux-${arch}.tar.gz" "$url"
    if [[ $? -ne 0 ]]; then
        echo -e "${red}下载 x-ui 失败，请确保版本 ${last_version} 存在${plain}"
        exit 1
    fi

    # 解压安装（略，保持原有逻辑）
    # ...
    
    # 下载 Xray 核心（略，保持原有逻辑）
    # ...
    
    # 下载 geoip.dat 和 geosite.dat（略，保持原有逻辑）
    # ...
}

# 脚本入口
echo -e "${green}开始安装/更新 x-ui...${plain}"
install_base
install_x-ui "$1"
