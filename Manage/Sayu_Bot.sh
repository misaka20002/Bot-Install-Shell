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

# 工具函数：检查 早柚核心 是否已安装
check_gscore_installed() {
    if [ ! -d "$GS_CORE_DIR" ]; then
        echo -e "${red}未检测到 早柚核心 (gsuid_core)！请先执行选项 [2] 进行安装。${background}"
        return 1
    fi
    return 0
}

# 1. 安装与配置 Napcat 适配器 (gscore-adapter)
handle_napcat_adapter() {
    local adapter_plugin_dir="$NC_PLUGIN_DIR/napcat-plugin-gscore-adapter"
    local adapter_conf_dir="$NC_CONFIG_DIR/plugins/napcat-plugin-gscore-adapter"
    local conf_file="$adapter_conf_dir/config.json"

    # 判断是否已经安装过适配器
    if [ ! -d "$adapter_plugin_dir" ]; then
        # 未安装则执行安装流程
        check_env
        check_github
        
        echo -e "${cyan}准备开始安装 napcat-plugin-gscore-adapter...${background}"
        mkdir -p "$NC_PLUGIN_DIR"
        cd "$NC_PLUGIN_DIR" || exit
        
        ZIP_FILE="napcat-plugin-gscore-adapter.zip"
        WGET_URL="${GH_PROXY}https://github.com/xiowo/napcat-plugin-gscore-adapter/releases/download/v1.2.2/$ZIP_FILE"
        
        wget "$WGET_URL" -O "$ZIP_FILE"
        unzip -o "$ZIP_FILE" -d "${ZIP_FILE%.zip}"
        rm "$ZIP_FILE"
        
        # 修改 plugins.json 启用插件
        mkdir -p "$NC_CONFIG_DIR"
        if [ ! -f "$NC_CONFIG_DIR/plugins.json" ]; then
            echo "{}" > "$NC_CONFIG_DIR/plugins.json"
        fi
        jq '."napcat-plugin-gscore-adapter" = true' "$NC_CONFIG_DIR/plugins.json" > tmp.json && mv tmp.json "$NC_CONFIG_DIR/plugins.json"
        
        echo -e "${green}插件下载并解压成功，已在 plugins.json 中启用！${background}"
    else
        echo -e "${green}已检测到 Napcat-早柚核心 适配器${background}"
    fi

    # 确保配置目录存在
    mkdir -p "$adapter_conf_dir"

    if [ ! -f "$conf_file" ]; then
        echo -e "${yellow}未找到配置文件，请先运行一次 NapCat${background}"
        return
    fi

    # 循环菜单：配置多项
    while true; do
        # 实时读取配置文件中的内容 (利用 jq 设置 fallback 默认值防止旧版配置缺少字段)
        local current_master=$(jq -r '.masterQQ // ""' "$conf_file" 2>/dev/null)
        local current_token=$(jq -r '.gscoreToken // ""' "$conf_file" 2>/dev/null)
        local current_silent=$(jq -r '.silentNoPermission // false' "$conf_file" 2>/dev/null)

        echo
        echo -e "${white}====== ${green}Napcat 适配器配置 ${white}======${background}"
        echo -e "${cyan}1. masterQQ (主人QQ): ${white}${current_master:-[为空]}${background}"
        echo -e "${cyan}2. gscoreToken (连接Token): ${white}${current_token:-[为空]}${background}"
        echo -e "${cyan}3. silentNoPermission (无权限静默): ${white}${current_silent}${background}"
        echo -e "${white}====== ${green}适配器指令${white}======${background}"
        echo -e "${cyan}适配器帮助: ${white}#早柚help${background}"
        echo -e "${cyan}开启群响应: ${white}#早柚群开启${background}"
        echo -e "${white}修改后重启 NatCat 生效${background}"
        echo -e "${white}==============================${background}"
        echo -en "${cyan}请输入数字修改对应项: ${background}"; read -r adapter_choice
        
        case $adapter_choice in
            1)
                echo -en "${cyan}请输入新的 masterQQ (多个QQ号用英文逗号隔开，直接回车清空): ${background}"
                read -r new_master
                jq --arg qq "$new_master" '.masterQQ = $qq' "$conf_file" > tmp.json && mv tmp.json "$conf_file"
                echo -e "${green}masterQQ 已成功修改！${background}"
                ;;
            2)
                echo -en "${cyan}请输入新的 gscoreToken (必须与早柚核心的 WS_TOKEN 一致，直接回车清空): ${background}"
                read -r new_token
                jq --arg tk "$new_token" '.gscoreToken = $tk' "$conf_file" > tmp.json && mv tmp.json "$conf_file"
                echo -e "${green}gscoreToken 已成功修改！${background}"
                ;;
            3)
                # 切换 silentNoPermission (true <=> false)
                if [ "$current_silent" = "true" ]; then
                    jq '.silentNoPermission = false' "$conf_file" > tmp.json && mv tmp.json "$conf_file"
                    echo -e "${green}silentNoPermission 已修改为 false！${background}"
                else
                    jq '.silentNoPermission = true' "$conf_file" > tmp.json && mv tmp.json "$conf_file"
                    echo -e "${green}silentNoPermission 已修改为 true！${background}"
                fi
                ;;
            *)
                break
                ;;
        esac
    done
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
    
    echo -e "${green}早柚核心环境安装完成！${background}"
    echo -e "${cyan}正在进入核心初始配置...${background}"
    config_and_info_gscore
}

# 3. 安装 早柚核心 插件
manage_gscore_plugins() {
    if ! check_gscore_installed; then return; fi
    check_env
    check_github
    
    mkdir -p "$GS_CORE_DIR/plugins"
    
    echo -e "${cyan}请选择要安装的插件：${background}"
    local i=1
    for plugin in "${GS_PLUGINS[@]}"; do
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
        
        echo -e "${cyan}正在安装/更新 $p_name 插件...${background}"
        cd "$GS_CORE_DIR/plugins" || exit
        
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

# 4. 配置 与 查看 早柚核心基础配置 (HOST/masters/Token等)
config_and_info_gscore() {
    if ! check_gscore_installed; then return; fi

    local conf_dir="$GS_CORE_DIR/data"
    local conf_file="$conf_dir/config.json"
    
    mkdir -p "$conf_dir"
    if [ ! -f "$conf_file" ]; then
        echo -e "${red}未找到核心配置文件，请先启动一次 早柚核心${background}"
        return
    fi

    # 获取本机公网IP (超时3秒防止卡顿)
    local ip=$(curl -s -m 3 ifconfig.me || echo "你的服务器IP")

    while true; do
        # 动态读取最新配置
        local host=$(jq -r '.HOST // "127.0.0.1"' "$conf_file" 2>/dev/null)
        local port=$(jq -r '.PORT // "8765"' "$conf_file" 2>/dev/null)
        local token=$(jq -r '.WS_TOKEN | if . == null or . == "" then "[未设置]" else . end' "$conf_file" 2>/dev/null)
        local code=$(jq -r '.REGISTER_CODE | if . == null or . == "" then "未生成(需先启动核心)" else . end' "$conf_file" 2>/dev/null)
        local masters=$(jq -r '(.masters // []) | join(",")' "$conf_file" 2>/dev/null)
        [ -z "$masters" ] && masters="[未设置]"

        echo
        echo -e "${white}====== ${green}早柚核心 配置与状态 ${white}======${background}"
        echo -e "${cyan}1. 绑定地址 (HOST): ${white}$host ${yellow}(提示: 若需外网或其他主机访问WebUI，请修改为 0.0.0.0)${background}"
        echo -e "${cyan}2. 运行端口 (PORT): ${white}$port${background}"
        echo -e "${cyan}3. 连接Token (WS_TOKEN): ${white}$token${background}"
        echo -e "${cyan}4. 主人QQ (masters): ${white}$masters${background}"
        echo -e "${cyan}5. 配置 异环 强制前缀 (#nte)${background}"
        echo -e "${white}------------------------------${background}"
        echo -e "${cyan}控制台注册码: ${white}$code${background}"
        echo -e "${cyan}网页控制台地址: ${yellow}http://$ip:$port/app${background}"
        echo -e "${white}==============================${background}"
        
        echo -e "${white}修改后重启 早柚核心 生效${background}"
        echo -e "${green}0. 返回主菜单${background}"
        echo -en "${cyan}请输入数字修改对应项，或输入 0 返回: ${background}"; read -r choice
        
        case $choice in
            1)
                echo -en "${cyan}请输入新的 HOST (例如 0.0.0.0 或 127.0.0.1): ${background}"; read -r new_host
                if [ -n "$new_host" ]; then
                    jq --arg v "$new_host" '.HOST = $v' "$conf_file" > tmp.json && mv tmp.json "$conf_file"
                    echo -e "${green}HOST 已修改为 $new_host ！${background}"
                fi
                ;;
            2)
                echo -en "${cyan}请输入新的 PORT (例如 8765): ${background}"; read -r new_port
                if [ -n "$new_port" ]; then
                    # 保存为字符串或整数形式，使用字符串能保障兼容性
                    jq --arg v "$new_port" '.PORT = $v' "$conf_file" > tmp.json && mv tmp.json "$conf_file"
                    echo -e "${green}PORT 已修改为 $new_port ！${background}"
                fi
                ;;
            3)
                echo -en "${cyan}请输入新的 WS_TOKEN (直接回车清空): ${background}"; read -r new_token
                jq --arg v "$new_token" '.WS_TOKEN = $v' "$conf_file" > tmp.json && mv tmp.json "$conf_file"
                echo -e "${green}WS_TOKEN 修改成功！${background}"
                ;;
            4)
                echo -en "${cyan}请输入主人QQ (多个用英文逗号分隔，直接回车清空): ${background}"; read -r new_masters
                if [ -z "$new_masters" ]; then
                    jq '.masters =[]' "$conf_file" > tmp.json && mv tmp.json "$conf_file"
                else
                    jq --arg m "$new_masters" '.masters = ($m | split(","))' "$conf_file" > tmp.json && mv tmp.json "$conf_file"
                fi
                echo -e "${green}masters 修改成功！${background}"
                ;;
            5) echo; config_nte_prefix ;;
            *)
                break
                ;;
        esac
    done
}

# 5. 配置 异环(NTE) 插件前缀
config_nte_prefix() {
    if ! check_gscore_installed; then return; fi

    local conf_file="$GS_CORE_DIR/data/config.json"
    if [ ! -f "$conf_file" ]; then
        echo -e "${red}未找到核心配置文件，请先启动一次 早柚核心${background}"
        return
    fi
    
    # 提取当前状态
    local current_prefix=$(jq -r '.plugins.NTEUID.prefix[0] // "empty"' "$conf_file" 2>/dev/null)
    local current_disable=$(jq -r '.plugins.NTEUID.disable_force_prefix // "empty"' "$conf_file" 2>/dev/null)
    
    echo
    echo -e "${white}====== ${green}异环(NTE) 前缀配置 ${white}======${background}"
    if [ "$current_prefix" = "#nte" ] && [ "$current_disable" = "true" ]; then
        echo -e "${cyan}当前状态: ${yellow}已开启强制前缀 [#nte] (指令如: #nte帮助)${background}"
    else
        echo -e "${cyan}当前状态: ${green}默认配置 (使用全局核心前缀或自带默认前缀)${background}"
    fi
    echo -e "${white}==============================${background}"
    
    echo -e "${cyan}1. 开启强制前缀为 '#nte帮助'${background}"
    echo -e "${cyan}2. 恢复为默认配置  'nte帮助'${background}"
    echo -e "${green}0. 返回主菜单${background}"
    echo -en "${yellow}请选择操作: ${background}"; read -r choice
    
    case $choice in
        1)
            jq 'if .plugins == null then .plugins = {} else . end | 
                if .plugins.NTEUID == null then .plugins.NTEUID = {} else . end | 
                .plugins.NTEUID.prefix = ["#nte"] | 
                .plugins.NTEUID.disable_force_prefix = true' "$conf_file" > tmp.json && mv tmp.json "$conf_file"
            echo -e "${green}配置成功！需重启 早柚核心 才能生效。${background}"
            ;;
        2)
            jq 'if .plugins != null and .plugins.NTEUID != null then 
                    del(.plugins.NTEUID.prefix, .plugins.NTEUID.disable_force_prefix) 
                else . end' "$conf_file" > tmp.json && mv tmp.json "$conf_file"
            echo -e "${green}已恢复默认配置！需重启 早柚核心 才能生效。${background}"
            ;;
        0|"")
            return
            ;;
        *)
            echo -e "${red}无效的选择。${background}"
            ;;
    esac
}

# 6. 启动 早柚核心
start_gscore() {
    if ! check_gscore_installed; then return; fi

    echo -e "${cyan}正在后台启动 早柚核心...${background}"
    cd "$GS_CORE_DIR" || exit
    nohup uv run core > /dev/null 2>&1 &
    sleep 2
    echo -e "${green}启动指令已发送！(核心已在后台运行)${background}"
}

# 7. 停止 早柚核心
stop_gscore() {
    echo -e "${cyan}正在查找并关闭 早柚核心 进程...${background}"
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

# 8. 卸载功能
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
    echo -e "${green}3. ${cyan}安装 早柚核心插件${background}"
    echo -e "${green}4. ${cyan}配置 早柚核心${background}"
    echo -e "${white}-------------------------${background}"
    echo -e "${green}5. ${cyan}启动 早柚核心${background}"
    echo -e "${green}6. ${cyan}停止 早柚核心${background}"
    echo -e "${white}-------------------------${background}"
    echo -e "${green}7. ${cyan}卸载相关组件${background}"
    echo -e "${green}0. ${cyan}退出脚本${background}"
    echo -e "${white}============================================${background}"
    echo -e "${green}早柚核心状态: ${gs_status}"
    echo -e "${white}============================================${background}"
    echo -en "${green}请输入您的选项: ${background}"; read -r number
    
    case ${number} in
        1) echo; handle_napcat_adapter ;;
        2) echo; install_gscore ;;
        3) echo; manage_gscore_plugins ;;
        4) echo; config_and_info_gscore ;;
        5) echo; start_gscore ;;
        6) echo; stop_gscore ;;
        7) echo; uninstall_all ;;
        0) exit ;;
        *) echo; echo -e "${red}输入错误${background}"; sleep 1 ;;
    esac
}

# 循环体
while true
do
    main
done