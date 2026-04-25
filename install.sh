#!/usr/bin/env bash

set -e

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# 检查 root 权限
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

# 检测系统发行版
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
else
    echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}\n" && exit 1
fi

# 检测架构
arch=$(uname -m)
case $arch in
    x86_64|amd64|x64)
        arch="amd64"
        ;;
    aarch64|arm64)
        arch="arm64"
        ;;
    *)
        echo -e "${red}不支持的系统架构: ${arch}${plain}"
        exit 1
        ;;
esac
echo -e "${green}系统架构: ${arch}${plain}"

# 安装基础依赖
install_base() {
    echo -e "${green}安装基础依赖...${plain}"
    if [[ x"${release}" == x"centos" ]]; then
        # 检测包管理器
        if command -v dnf &>/dev/null; then
            dnf install -y wget curl tar jq unzip
        else
            yum install -y wget curl tar jq unzip
        fi
    else
        apt update
        apt install -y wget curl tar jq unzip
    fi
}

# 检查 glibc 版本，判断是否能够运行预编译二进制
check_glibc() {
    local glibc_version=$(ldd --version 2>&1 | head -n1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
    local major=$(echo $glibc_version | cut -d. -f1)
    local minor=$(echo $glibc_version | cut -d. -f2)
    if [[ $major -lt 2 ]] || ([[ $major -eq 2 ]] && [[ $minor -lt 28 ]]); then
        echo -e "${yellow}检测到 glibc 版本 ${glibc_version} < 2.28，预编译二进制无法运行，将使用本地编译安装${plain}"
        return 1
    fi
    return 0
}

# 本地编译 x-ui
compile_xui() {
    echo -e "${green}开始本地编译 x-ui (解决 glibc 兼容性问题)...${plain}"
    # 安装 Go
    if ! command -v go &>/dev/null; then
        echo -e "${green}安装 Go 1.21...${plain}"
        if [[ x"${release}" == x"centos" ]]; then
            # 从官方下载二进制包
            wget -q https://go.dev/dl/go1.21.5.linux-${arch}.tar.gz -O /tmp/go.tar.gz
            rm -rf /usr/local/go && tar -C /usr/local -xzf /tmp/go.tar.gz
            export PATH=$PATH:/usr/local/go/bin
            echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
        else
            apt install -y golang-go
            # 如果版本太低，也会手动安装新版
            if go version | grep -q "go1.1[0-9]"; then
                wget -q https://go.dev/dl/go1.21.5.linux-${arch}.tar.gz -O /tmp/go.tar.gz
                rm -rf /usr/local/go && tar -C /usr/local -xzf /tmp/go.tar.gz
                export PATH=$PATH:/usr/local/go/bin
                echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
            fi
        fi
    fi
    # 克隆你的仓库
    git clone https://github.com/gm-cx/x-ui.git /tmp/x-ui-src
    cd /tmp/x-ui-src
    CGO_ENABLED=1 GOOS=linux GOARCH=${arch} go build -o x-ui -v main.go
    # 准备目录
    mkdir -p /usr/local/x-ui/bin
    cp x-ui /usr/local/x-ui/x-ui
    chmod +x /usr/local/x-ui/x-ui
    # 复制辅助文件
    cp x-ui.service /etc/systemd/system/ 2>/dev/null
    cp x-ui.sh /usr/local/x-ui/ 2>/dev/null
    cp -r bin/* /usr/local/x-ui/bin/ 2>/dev/null || true
    cd /
    rm -rf /tmp/x-ui-src
    echo -e "${green}本地编译完成${plain}"
}

# 主安装函数
install_x-ui() {
    systemctl stop x-ui 2>/dev/null || true
    cd /usr/local/

    local last_version
    if [ $# == 0 ]; then
        echo -e "${green}未指定版本，尝试从 GitHub API 获取最新版本...${plain}"
        last_version=$(curl -Lsk "https://api.github.com/repos/gm-cx/x-ui/releases/latest" | grep -oP '"tag_name": "\K[^"]+')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}检测 x-ui 版本失败，可能是超出 Github API 限制，请稍后再试，或手动指定 x-ui 版本安装${plain}"
            exit 1
        fi
        echo -e "${green}检测到最新版本：${last_version}${plain}"
    else
        last_version=$1
        echo -e "${green}指定版本：${last_version}${plain}"
    fi

    local url="https://github.com/gm-cx/x-ui/releases/download/${last_version}/x-ui-linux-${arch}.tar.gz"
    echo -e "${green}下载预编译包: ${url}${plain}"
    wget -N --no-check-certificate -O "/usr/local/x-ui-linux-${arch}.tar.gz" "$url" && {
        # 解压并安装预编译版本
        tar zxvf x-ui-linux-${arch}.tar.gz
        rm -f x-ui-linux-${arch}.tar.gz
        cd x-ui
        chmod +x x-ui bin/xray-linux-${arch}
        cp -f x-ui.service /etc/systemd/system/
        cp x-ui.sh /usr/local/x-ui/ 2>/dev/null
        cd ..
        # 注意：这里需要确保目录结构正确
        if [[ -d x-ui ]]; then
            rm -rf /usr/local/x-ui
            mv x-ui /usr/local/
        fi
    } || {
        echo -e "${yellow}下载预编译包失败，将尝试本地编译安装${plain}"
        compile_xui
    }

    # 下载管理脚本（始终从你的仓库获取最新版本）
    wget --no-check-certificate -O /usr/bin/x-ui https://raw.githubusercontent.com/gm-cx/x-ui/main/x-ui.sh
    chmod +x /usr/bin/x-ui

    # 配置 systemd
    systemctl daemon-reload
    systemctl enable x-ui
    systemctl start x-ui

    # 安全配置提示
    config_after_install

    echo -e "${green}x-ui 安装完成！${plain}"
    echo -e "管理命令: x-ui {start|stop|restart|status|log|...}"
    echo -e "Web面板端口: 54321 (请自行修改用户名/密码)"
}

# 安全配置函数（可选）
config_after_install() {
    echo -e "${yellow}是否立即修改面板用户名/密码/端口？[y/n]${plain}"
    read -r choice
    if [[ $choice == "y" || $choice == "Y" ]]; then
        read -p "请输入用户名: " username
        read -p "请输入密码: " password
        read -p "请输入端口: " port
        /usr/local/x-ui/x-ui setting -username "$username" -password "$password"
        /usr/local/x-ui/x-ui setting -port "$port"
        systemctl restart x-ui
        echo -e "${green}配置已更新，请使用新端口访问面板${plain}"
    fi
}

# 脚本入口
echo -e "${green}开始安装 x-ui ...${plain}"
install_base
install_x-ui "$1"
