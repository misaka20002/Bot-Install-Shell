#!/bin/env bash

# 定义颜色变量
export red="\033[31m"
export green="\033[32m"
export yellow="\033[33m"
export blue="\033[34m"
export purple="\033[35m"
export cyan="\033[36m"
export white="\033[37m"
export background="\033[0m"

# 常量与路径定义
NC_BASE="$HOME/Napcat/opt/QQ/resources/app/app_launcher/napcat"
NC_PLUGIN_DIR="$NC_BASE/plugins"
NC_CONFIG_DIR="$NC_BASE/config"
GS_CORE_DIR="$HOME/gsuid_core"
GH_PROXY=""

# 插件库数组格式: "插件显示名称|Git仓库地址|分支"
# 你可以在此数组中方便地添加更多插件
GS_PLUGINS=(
    "原神(GenshinUID)|https://github.com/KimigaiiWuyi/GenshinUID.git|v4"
    "异环(NTEUID)|https://github.com/tyql688/NTEUID.git|main"
)

# 基础检查
cd "$HOME" || exit
if [ "$(uname -o)" = "Android" ]; then
    echo -e "${red}不支持Android环境${background}"
    exit
fi
if [ ! "$(uname)" = "Linux" ]; then
    echo -e "${red}仅支持Linux环境${background}"
    exit
fi
if [ ! "$(id -u)" = "0" ]; then
    echo -e "${red}请使用root用户执行本脚本${background}"
    exit 0
fi

case $(uname -m) in
    x86_64|amd64|arm64|aarch64)
        ;;
    *)
        echo -e "${red}您的框架为${yellow}$(uname -m)${red},不支持该架构.${background}"
        exit
        ;;
esac

# 检查网络并设置代理
check_github() {
    echo -e "${cyan}正在检测 GitHub 网络连通性...${background}"
    if curl -I -s -m 3 https://github.com | grep -q "HTTP"; then
        echo -e "${green}GitHub 直连成功！${background}"
        GH_PROXY=""
    else
        echo -e "${yellow}GitHub 直连超时或失败，已自动启用代理 (https://ghfast.top/)${background}"
        GH_PROXY="https://ghfast.top/"
    fi
}

# 基础环境及依赖检测
check_env() {
    echo -e "${cyan}正在检查系统基础环境...${background}"
    for cmd in python3 git curl wget unzip jq; do
        if ! command -v $cmd &> /dev/null; then
            echo -e "${yellow}未检测到 $cmd，正在自动安装...${background}"
            if command -v apt &> /dev/null; then apt update -y && apt install -y $cmd
            elif command -v yum &> /dev/null; then yum install -y $cmd
            elif command -v dnf &> /dev/null; then dnf install -y $cmd
            elif command -v pacman &> /dev/null; then pacman -S --noconfirm $cmd
            fi
        fi
    done

    if ! command -v pip &> /dev/null && ! command -v pip3 &> /dev/null; then
        echo -e "${yellow}未检测到 pip，正在安装...${background}"
        if command -v apt &> /dev/null; then apt install -y python3-pip; fi
    fi

    if ! command -v uv &> /dev/null; then
        echo -e "${yellow}未检测到 uv，正在安装...${background}"
        pip install uv --break-system-packages 2>/dev/null || pip install uv
    fi
    echo -e "${green}基础环境检查完成！${background}"
}

# 1. 安装 Napcat 插件 (gscore-adapter)
install_napcat_adapter() {
    check_env
    check_github
    
    echo -e "${cyan}开始安装 napcat-plugin-gscore-adapter...${background}"
    mkdir -p "$NC_PLUGIN_DIR"
    cd "$NC_PLUGIN_DIR" || exit
    
    ZIP_FILE="napcat-plugin-gscore-adapter.zip"
    WGET_URL="${GH_PROXY}https://github.com/xiowo/napcat-plugin-gscore-adapter/releases/download/v1.2.2/$ZIP_FILE"
    
    wget "$WGET_URL" -O "$ZIP_FILE"
    unzip -o "$ZIP_FILE" -d "${ZIP_FILE%.zip}"
    rm "$ZIP_FILE"
    
    # 修改 plugins.json
    mkdir -p "$NC_CONFIG_DIR"
    if [ ! -f "$NC_CONFIG_DIR/plugins.json" ]; then
        echo "{}" > "$NC_CONFIG_DIR/plugins.json"
    fi
    jq '."napcat-plugin-gscore-adapter" = true' "$NC_CONFIG_DIR/plugins.json" > tmp.json && mv tmp.json "$NC_CONFIG_DIR/plugins.json"
    
    echo -e "${green}插件下载并解压成功，已在 plugins.json 中启用！${background}"
    
    # 配置 masterQQ
    config_napcat_adapter
}

# 配置 Napcat 适配器 masterQQ
config_napcat_adapter() {
    local adapter_conf_dir="$NC_CONFIG_DIR/plugins/napcat-plugin-gscore-adapter"
    mkdir -p "$adapter_conf_dir"
    local conf_file="$adapter_conf_dir/config.json"
    
    if [ ! -f "$conf_file" ]; then
        echo '{"masterQQ": ""}' > "$conf_file"
    fi
    
    echo -e "${cyan}请输入 masterQQ (多个QQ号用英文逗号隔开，直接回车跳过):${background}"
    read -r master_qq
    if [ -n "$master_qq" ]; then
        jq --arg qq "$master_qq" '.masterQQ = $qq' "$conf_file" > tmp.json && mv tmp.json "$conf_file"
        echo -e "${green}masterQQ 已修改为: $master_qq${background}"
        echo -e "${yellow}注意：Napcat配置修改后需重启 Napcat 生效。${background}"
    fi
}

# 2. 安装 早柚核心 (gsuid_core)
install_gscore() {
    check_env
    check_github
    
    echo -e "${cyan}开始安装 早柚核心 (gsuid_core)...${background}"
    cd "$HOME" || exit
    
    if [ -d "$GS_CORE_DIR" ]; then
        echo -e "${yellow}早柚核心文件夹已存在，如果需要重新安装请先卸载！${background}"
        return
    fi
    
    git clone --depth=1 --single-branch "${GH_PROXY}https://github.com/Genshin-bots/gsuid_core.git"
    
    cd "$GS_CORE_DIR" || exit
    echo -e "${cyan}正在配置 Python 环境与依赖 (uv)...${background}"
    uv python install 3.13
    uv sync --python 3.13
    uv run python -m ensurepip
    
    echo -e "${green}早柚核心安装完成！${background}"
    echo -e "${cyan}正在进行初始核心配置...${background}"
    config_gscore
}

# 3. 配置 早柚核心 (gsuid_core)
config_gscore() {
    local conf_dir="$GS_CORE_DIR/data"
    local conf_file="$conf_dir/config.json"
    
    mkdir -p "$conf_dir"
    if [ ! -f "$conf_file" ]; then
        # 预设一个基础骨架
        echo '{"HOST": "localhost", "PORT": "8765", "masters":[], "WS_TOKEN": ""}' > "$conf_file"
    fi
    
    echo -e "${cyan}--- 开始配置 早柚核心 ---${background}"
    
    # 强制修改 HOST 为 0.0.0.0
    jq '.HOST = "0.0.0.0"' "$conf_file" > tmp.json && mv tmp.json "$conf_file"
    echo -e "${green}已自动将 HOST 修改为 0.0.0.0${background}"
    
    # 配置 masters
    echo -e "${cyan}请输入 masters (主人QQ，多个QQ用英文逗号隔开，回车跳过):${background}"
    read -r gs_masters
    if [ -n "$gs_masters" ]; then
        jq --arg m "$gs_masters" '.masters = ($m | split(","))' "$conf_file" > tmp.json && mv tmp.json "$conf_file"
        echo -e "${green}masters 配置完成！${background}"
    fi
    
    # 配置 WS_TOKEN
    echo -e "${cyan}请输入 WS_TOKEN (连接Token，需与Napcat侧一致，回车跳过):${background}"
    read -r ws_token
    if [ -n "$ws_token" ]; then
        jq --arg t "$ws_token" '.WS_TOKEN = $t' "$conf_file" > tmp.json && mv tmp.json "$conf_file"
        echo -e "${green}WS_TOKEN 配置完成！${background}"
    fi
    
    echo -e "${yellow}核心配置修改后，需重启 早柚核心 才能生效！${background}"
}

# 4. 显示 早柚核心配置 与 帮助
show_gscore_info() {
    local conf_file="$GS_CORE_DIR/data/config.json"
    if [ ! -f "$conf_file" ]; then
        echo -e "${red}暂无配置文件，请先安装或启动一次核心！${background}"
        return
    fi
    
    local host=$(jq -r '.HOST' "$conf_file")
    local port=$(jq -r '.PORT' "$conf_file")
    local token=$(jq -r '.WS_TOKEN' "$conf_file")
    local code=$(jq -r '.REGISTER_CODE' "$conf_file")
    
    # 获取本机IP
    local ip=$(curl -s ifconfig.me || echo "你的服务器IP")
    
    echo -e "${white}====== ${green}早柚核心配置信息 ${white}======${background}"
    echo -e "${cyan}绑定地址 (HOST): ${white}$host${background}"
    echo -e "${cyan}运行端口 (PORT): ${white}$port${background}"
    echo -e "${cyan}连接Token (WS_TOKEN): ${white}$token${background}"
    echo -e "${cyan}控制台注册码: ${white}$code${background}"
    echo -e "${cyan}网页控制台地址: ${yellow}http://$ip:$port/app${background}"
    echo -e "${white}==============================${background}"
    
    echo -e "${white}====== ${green}常用 Bot 指令帮助 ${white}======${background}"
    echo -e "${cyan}适配器帮助: ${white}#早柚help${background}"
    echo -e "${cyan}开启群响应: ${white}#早柚群开启${background}"
    echo -e "${white}==============================${background}"
    
    echo -e "${cyan}按回车键继续...${background}"; read -r
}

# 5. 管理 早柚核心 插件
manage_gscore_plugins() {
    check_env
    check_github
    
    if [ ! -d "$GS_CORE_DIR/plugins" ]; then
        echo -e "${red}未找到早柚核心插件目录，请确保核心已正确安装！${background}"
        return
    fi
    
    echo -e "${cyan}请选择要安装的插件：${background}"
    local i=1
    for plugin in "${GS_PLUGINS[@]}"; do
        # IFS 分割字符串
        local name=$(echo "$plugin" | cut -d'|' -f1)
        echo -e "${green}$i. ${white}$name${background}"
        ((i++))
    done
    echo -e "${green}0. ${white}返回上级${background}"
    
    echo -en "${cyan}请输入选项: ${background}"; read -r choice
    if [ "$choice" == "0" ] || [ -z "$choice" ]; then return; fi
    
    local index=$((choice - 1))
    if [ $index -ge 0 ] && [ $index -lt ${#GS_PLUGINS[@]} ]; then
        local selected="${GS_PLUGINS[$index]}"
        local p_name=$(echo "$selected" | cut -d'|' -f1)
        local p_url=$(echo "$selected" | cut -d'|' -f2)
        local p_branch=$(echo "$selected" | cut -d'|' -f3)
        
        echo -e "${cyan}正在安装 $p_name 插件...${background}"
        cd "$GS_CORE_DIR/plugins" || exit
        
        # 提取仓库名称用于判断是否已安装
        local repo_name=$(basename "$p_url" .git)
        if [ -d "$repo_name" ]; then
            echo -e "${yellow}插件目录 $repo_name 已存在，尝试拉取更新...${background}"
            cd "$repo_name" || exit
            git pull
        else
            git clone -b "$p_branch" "${GH_PROXY}${p_url}" --depth=1 --single-branch
        fi
        echo -e "${green}$p_name 安装/更新完毕，重启早柚核心后生效！${background}"
    else
        echo -e "${red}无效的选择。${background}"
    fi
}

# 6. 配置 异环(NTE) 插件前缀
config_nte_prefix() {
    local conf_file="$GS_CORE_DIR/data/config.json"
    if [ ! -f "$conf_file" ]; then
        echo -e "${red}未找到核心配置文件，请先启动一次核心或确认配置是否存在！${background}"
        return
    fi
    
    echo -e "${cyan}是否配置异环插件(NTE)强制前缀为 '#nte' ？${background}"
    echo -e "${yellow}(配置后指令变为 '#nte帮助'，若不配置则默认指令为 'nte帮助')${background}"
    echo -en "${cyan}请输入 [Y/n]: ${background}"; read -r yn
    
    case $yn in
        [Yy]*|"")
            # 使用 jq 安全注入配置，防止原本没有 plugins 字段报错
            jq 'if .plugins == null then .plugins = {} else . end | 
                if .plugins.NTEUID == null then .plugins.NTEUID = {} else . end | 
                .plugins.NTEUID.prefix = ["#nte"] | 
                .plugins.NTEUID.disable_force_prefix = true' "$conf_file" > tmp.json && mv tmp.json "$conf_file"
            
            echo -e "${green}配置成功！需重启 早柚核心 生效。${background}"
            ;;
        *)
            echo -e "${yellow}已取消配置，保持默认。${background}"
            ;;
    esac
}

# 7. 启动 早柚核心
start_gscore() {
    if [ ! -d "$GS_CORE_DIR" ]; then
        echo -e "${red}未找到早柚核心目录！${background}"
        return
    fi
    echo -e "${cyan}正在后台启动 早柚核心...${background}"
    cd "$GS_CORE_DIR" || exit
    # 根据你的说明，执行后会自动运行在后台，这里我们为防止阻塞终端，加一个nohup/&保护
    nohup uv run core > /dev/null 2>&1 &
    sleep 2
    echo -e "${green}启动指令已发送！(核心已在后台运行)${background}"
}

# 8. 停止 早柚核心
stop_gscore() {
    echo -e "${cyan}正在查找并关闭 早柚核心 进程...${background}"
    # 根据 ps aux 的输出定位特征
    local pids=$(ps aux | grep -E "uv run core|gsuid_core/.venv/bin/core" | grep -v grep | awk '{print $2}')
    
    if [ -n "$pids" ]; then
        for pid in $pids; do
            kill -9 "$pid" 2>/dev/null
            echo -e "${yellow}已终止进程 PID: $pid${background}"
        done
        echo -e "${green}早柚核心已成功停止！${background}"
    else
        echo -e "${cyan}当前未检测到运行中的 早柚核心。${background}"
    fi
}

# 9. 卸载功能
uninstall_all() {
    echo -e "${red}警告：此操作将删除相关文件！${background}"
    echo -e "${cyan}1. 仅卸载 Napcat 适配插件 (gscore-adapter)${background}"
    echo -e "${cyan}2. 仅卸载 早柚核心 (gsuid_core)${background}"
    echo -e "${cyan}3. 全部卸载${background}"
    echo -e "${cyan}0. 取消${background}"
    echo -en "${yellow}请选择: ${background}"; read -r choice
    
    case $choice in
        1)
            rm -rf "${NC_PLUGIN_DIR}/napcat-plugin-gscore-adapter"
            if [ -f "$NC_CONFIG_DIR/plugins.json" ]; then
                jq 'del(."napcat-plugin-gscore-adapter")' "$NC_CONFIG_DIR/plugins.json" > tmp.json && mv tmp.json "$NC_CONFIG_DIR/plugins.json"
            fi
            echo -e "${green}已卸载 Napcat 适配插件。${background}"
            ;;
        2)
            stop_gscore
            rm -rf "$GS_CORE_DIR"
            echo -e "${green}已卸载 早柚核心。${background}"
            ;;
        3)
            stop_gscore
            rm -rf "${NC_PLUGIN_DIR}/napcat-plugin-gscore-adapter"
            if [ -f "$NC_CONFIG_DIR/plugins.json" ]; then
                jq 'del(."napcat-plugin-gscore-adapter")' "$NC_CONFIG_DIR/plugins.json" > tmp.json && mv tmp.json "$NC_CONFIG_DIR/plugins.json"
            fi
            rm -rf "$GS_CORE_DIR"
            echo -e "${green}全部卸载完成。${background}"
            ;;
        0)
            echo -e "${green}已取消。${background}"
            ;;
        *)
            echo -e "${red}无效的选择。${background}"
            ;;
    esac
}

# 主菜单
main() {
    # 检测运行状态
    if ps aux | grep -E "uv run core|gsuid_core/.venv/bin/core" | grep -v grep > /dev/null; then
        gs_status="${green}[运行中]${background}"
    elif [ -d "$GS_CORE_DIR" ]; then
        gs_status="${red}[已停止]${background}"
    else
        gs_status="${yellow}[未安装]${background}"
    fi

    echo
    echo -e "${white}=====${green} 早柚核心 (gsuid_core) 综合管理 ${white}=====${background}"
    echo -e "${green}1. ${cyan}配置 Napcat-早柚核心 适配器${background}"
    echo -e "${green}2. ${cyan}安装 早柚核心${background}"
    echo -e "${green}3. ${cyan}安装 早柚核心插件管理${background}"
    echo -e "${white}-------------------------${background}"
    echo -e "${green}4. ${cyan}修改 早柚核心 基础配置 (HOST/masters/Token)${background}"
    echo -e "${green}5. ${cyan}配置 异环(NTE) 强制前缀 (#nte)${background}"
    echo -e "${green}6. ${cyan}查看 核心配置 与 帮助信息 (含WebUI地址)${background}"
    echo -e "${white}-------------------------${background}"
    echo -e "${green}7. ${cyan}启动 早柚核心${background}"
    echo -e "${green}8. ${cyan}停止 早柚核心${background}"
    echo -e "${green}9. ${cyan}卸载相关组件${background}"
    echo -e "${green}0. ${cyan}退出脚本${background}"
    echo -e "${white}============================================${background}"
    echo -e "${green}早柚核心状态: ${gs_status}"
    echo -e "${white}============================================${background}"
    echo -en "${green}请输入您的选项: ${background}"; read -r number
    
    case ${number} in
        1) echo; install_napcat_adapter ;;
        2) echo; install_gscore ;;
        3) echo; manage_gscore_plugins ;;
        4) echo; config_gscore ;;
        5) echo; config_nte_prefix ;;
        6) echo; show_gscore_info ;;
        7) echo; start_gscore ;;
        8) echo; stop_gscore ;;
        9) echo; uninstall_all ;;
        0) exit ;;
        *) echo; echo -e "${red}输入错误${background}"; sleep 1 ;;
    esac
}

# 循环体
while true
do
    main
done