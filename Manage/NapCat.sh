#!/bin/env bash
export red="\033[31m"
export green="\033[32m"
export yellow="\033[33m"
export blue="\033[34m"
export purple="\033[35m"
export cyan="\033[36m"
export white="\033[37m"
export background="\033[0m"

cd $HOME
if [ "$(uname -o)" = "Android" ];then
echo -e ${red}你是大聪明吗?${background}
exit
fi
if [ ! "$(uname)" = "Linux" ]; then
	echo -e ${red}你是大聪明吗?${background}
    exit
fi
if [ ! "$(id -u)" = "0" ]; then
    echo -e ${red}请使用root用户${background}
    exit 0
fi

case $(uname -m) in
    x86_64|amd64)
    ARCH=x64
;;
    arm64|aarch64)
    ARCH=arm64   
;;
*)
    echo ${red}您的框架为${yellow}$(uname -m)${red},不支持该架构.${background}
    exit
;;
esac

# NapCat 安装和管理

INSTALL_SCRIPT="napcat.sh"
INSTALL_URL="https://nclatest.znin.net/NapNeko/NapCat-Installer/main/script/install.sh"
TMUX_NAME="napcat"
NAPCAT_CMD="xvfb-run -a qq --no-sandbox"
APP_NAME="NapCat"

# 检查 tmux 是否安装
check_tmux() {
    if ! command -v tmux &> /dev/null; then
        echo -e ${yellow}未检测到tmux，正在安装...${background}
        if [ $(command -v apt) ]; then
            apt update -y
            apt install -y tmux
        elif [ $(command -v yum) ]; then
            yum makecache -y
            yum install -y tmux
        elif [ $(command -v dnf) ]; then
            dnf makecache -y
            dnf install -y tmux
        elif [ $(command -v pacman) ]; then
            pacman -Syy --noconfirm --needed tmux
        else
            echo -e ${red}不支持的Linux发行版，无法安装tmux${background}
            exit 1
        fi
    fi
}

# 安装 NapCat
install_NapCat() {
    echo -e ${yellow}正在安装${APP_NAME}...${background}
    
    # 检查必要的工具
    if [ $(command -v apt) ];then
        apt update -y
        apt install -y curl wget
    elif [ $(command -v yum) ]; then
        yum makecache -y
        yum install -y curl wget
    elif [ $(command -v dnf) ];then
        dnf makecache -y
        dnf install -y curl wget
    elif [ $(command -v pacman) ]; then
        pacman -Syy --noconfirm --needed curl wget
    else
        echo -e ${red}不受支持的Linux发行版${background}
        exit 1
    fi
    
    # 下载安装脚本
    echo -e ${yellow}正在下载${APP_NAME}安装脚本...${background}
    if ! curl -o ${INSTALL_SCRIPT} ${INSTALL_URL}; then
        echo -e ${red}下载安装脚本失败，请检查网络连接${background}
        echo -en ${cyan}回车返回${background};read
        return 1
    fi
    
    # 执行安装脚本
    echo -e ${yellow}正在执行${APP_NAME}安装脚本...${background}
    chmod +x ${INSTALL_SCRIPT}
    bash ${INSTALL_SCRIPT}
    
    # 安装后清理
    rm -f ${INSTALL_SCRIPT}
    
    echo -e ${green}${APP_NAME}安装完成${background}
    echo -en ${yellow}是否启动${APP_NAME}? [Y/n]${background};read yn
    case ${yn} in
    Y|y)
        start_NapCat
        ;;
    esac
}

# 检查 NapCat 是否已安装
check_installed() {
    if ! command -v qq &> /dev/null; then
        return 1
    fi
    return 0
}

# 检查 NapCat 是否运行中
check_running() {
    if tmux list-sessions 2>/dev/null | grep -q ${TMUX_NAME}; then
        return 0
    fi
    return 1
}

# 启动 NapCat
start_NapCat() {
    if ! check_installed; then
        echo -e ${red}${APP_NAME}未安装，请先安装${background}
        echo -en ${cyan}回车返回${background};read
        return 1
    fi
    
    if check_running; then
        echo -e ${yellow}${APP_NAME}已经在运行中${background}
        echo -en ${cyan}回车返回${background};read
        return 0
    fi
    
    check_tmux
    
    echo -e ${yellow}正在准备启动${APP_NAME}...${background}
    
    # 选择登录方式
    echo -e ${cyan}请选择登录方式${background}
    echo -e ${green}1.  ${cyan}全新登录（直接启动）${background}
    echo -e ${green}2.  ${cyan}使用已登录的QQ账号${background}
    echo "========================="
    echo -en ${green}请输入您的选项: ${background};read login_option
    
    case ${login_option} in
        2)
            # 使用已登录的QQ账号
            # 检查配置目录是否存在
            CONFIG_DIR="/opt/QQ/resources/app/app_launcher/napcat/config"
            if [ ! -d "$CONFIG_DIR" ]; then
                echo -e ${red}配置目录不存在: ${CONFIG_DIR}${background}
                echo -e ${yellow}请先使用全新登录方式登录QQ账号${background}
                echo -en ${cyan}回车返回${background};read
                return 1
            fi
            
            # 查找已登录的QQ账号
            echo -e ${yellow}正在查找已登录的QQ账号...${background}
            account_files=$(find "$CONFIG_DIR" -name "napcat_*.json" 2>/dev/null)
            
            if [ -z "$account_files" ]; then
                echo -e ${red}未找到已登录的QQ账号${background}
                echo -e ${yellow}请先使用全新登录方式登录QQ账号${background}
                echo -en ${cyan}是否切换到全新登录? [Y/n]${background};read switch_yn
                case ${switch_yn} in
                    Y|y|"")
                        login_option=1
                        ;;
                    *)
                        echo -en ${cyan}回车返回${background};read
                        return 1
                        ;;
                esac
            else
                # 提取并显示QQ号码列表
                echo -e ${green}已找到以下QQ账号:${background}
                i=1
                declare -a qq_numbers
                
                while IFS= read -r file; do
                    qq_number=$(basename "$file" | sed -n 's/napcat_\([0-9]*\)\.json/\1/p')
                    if [ -n "$qq_number" ]; then
                        qq_numbers+=("$qq_number")
                        echo -e ${green}$i. ${cyan}$qq_number${background}
                        i=$((i+1))
                    fi
                done <<< "$account_files"
                
                echo -e ${green}0. ${cyan}返回并选择全新登录${background}
                echo
                
                # 让用户选择要登录的QQ账号
                echo -en ${yellow}请选择要登录的QQ账号编号: ${background};read choice
                
                if [ "$choice" = "0" ]; then
                    login_option=1
                elif ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#qq_numbers[@]} ]; then
                    echo -e ${red}无效的选择${background}
                    echo -en ${cyan}回车返回${background};read
                    return 1
                else
                    selected_qq=${qq_numbers[$((choice-1))]}
                    NAPCAT_CMD="xvfb-run -a qq --no-sandbox -q ${selected_qq}"
                    echo -e ${yellow}已选择QQ账号: ${cyan}${selected_qq}${background}
                    sleep 1
                fi
            fi
            ;;
        *)
            # 使用默认命令（全新登录）
            login_option=1
            ;;
    esac
    
    # 如果选择了全新登录或从其他选项回退到全新登录
    if [ "$login_option" = "1" ]; then
        NAPCAT_CMD="xvfb-run -a qq --no-sandbox"
    fi
    
    # 选择启动方式
    echo -e ${cyan}请选择启动方式${background}
    echo -e ${green}1.  ${cyan}前台启动（首次登录）${background}
    echo -e ${green}2.  ${cyan}后台启动（推荐）${background}
    echo "========================="
    echo -en ${green}请输入您的选项: ${background};read start_option
    
    case ${start_option} in
        1)
            # 前台启动
            echo -e ${yellow}正在前台启动${APP_NAME}...${background}
            echo -e ${cyan}提示: 退出请按 Ctrl+C${background}
            # 添加自动重启功能
            export Boolean=true
            while ${Boolean}
            do 
                ${NAPCAT_CMD}
                echo -e ${red}${APP_NAME}已关闭，正在重启...${background}
                sleep 2s
            done
            echo -en ${cyan}回车返回${background};read
            ;;
        2)
            # 后台启动
            echo -e ${yellow}正在后台启动${APP_NAME}...${background}
            # 使用循环确保自动重启
            tmux new-session -d -s ${TMUX_NAME} "export Boolean=true; while \${Boolean}; do ${NAPCAT_CMD}; echo -e '${red}${APP_NAME}已关闭，正在重启...${background}'; sleep 2s; done"
            
            # 检查是否成功启动
            sleep 2
            if check_running; then
                echo -e ${green}${APP_NAME}已成功在后台启动${background}
                echo -e ${cyan}提示: 使用 '查看日志' 功能可以访问${APP_NAME}界面${background}
                
                # 添加是否查看日志的选项
                echo -en ${green}是否立即查看日志（打开日志后退出请按 Ctrl+B 然后按 D）? [Y/n]:${background}; read view_log_yn
                case ${view_log_yn} in
                    Y|y|"")
                        tmux attach-session -t ${TMUX_NAME}
                        ;;
                    *)
                        echo -e ${green}您可以稍后通过 '查看日志' 选项进入${APP_NAME}界面${background}
                        ;;
                esac
            else
                echo -e ${red}${APP_NAME}启动失败，请检查错误信息${background}
            fi
            echo -en ${cyan}回车返回${background};read
            ;;
        *)
            echo -e ${red}输入错误${background}
            echo -en ${cyan}回车返回${background};read
            ;;
    esac
}

# 停止 NapCat
stop_NapCat() {
    if ! check_running; then
        echo -e ${yellow}${APP_NAME}未运行${background}
        echo -en ${cyan}回车返回${background};read
        return 0
    fi
    
    echo -e ${yellow}正在停止${APP_NAME}...${background}
    # 将Boolean设置为false以退出自动重启循环
    tmux send-keys -t ${TMUX_NAME} "Boolean=false" C-m
    sleep 1
    tmux kill-session -t ${TMUX_NAME}
    
    # 检查是否成功停止
    sleep 2
    if ! check_running; then
        echo -e ${green}${APP_NAME}已成功停止${background}
    else
        echo -e ${red}${APP_NAME}停止失败，尝试强制终止进程${background}
        pkill -f "${NAPCAT_CMD}"
        sleep 1
        if ! check_running; then
            echo -e ${green}${APP_NAME}已成功停止${background}
        else
            echo -e ${red}无法停止${APP_NAME}，请手动检查进程${background}
        fi
    fi
    
    echo -en ${cyan}回车返回${background};read
}

# 重启 NapCat
restart_NapCat() {
    if check_running; then
        echo -e ${yellow}正在重启${APP_NAME}...${background}
        stop_NapCat
        start_NapCat
    else
        echo -e ${yellow}${APP_NAME}未运行，正在启动...${background}
        start_NapCat
    fi
}

# 查看 NapCat 日志/界面
view_log() {
    if ! check_running; then
        echo -e ${yellow}${APP_NAME}未运行，无法查看日志${background}
        echo -en ${cyan}回车返回${background};read
        return 1
    fi
    
    echo -e ${yellow}正在连接到${APP_NAME}界面...${background}
    echo -e ${cyan}提示: 退出请按 Ctrl+B 然后按 D${background}
    echo -e ${cyan}按回车键继续${background};read
    sleep 1
    
    tmux attach-session -t ${TMUX_NAME}
}

# 卸载 NapCat
uninstall_NapCat() {
    echo -e ${yellow}是否确认卸载${APP_NAME}? [y/N]${background};read yn
    case ${yn} in
        Y|y)
            if check_running; then
                echo -e ${yellow}正在停止${APP_NAME}...${background}
                stop_NapCat > /dev/null 2>&1
            fi
            
            echo -e ${yellow}正在卸载${APP_NAME}...${background}
            
            # 删除NapCat安装目录
            if [ -d "/QQ/resources/app/app_launcher/napcat" ]; then
                echo -e ${yellow}正在删除NapCat安装目录...${background}
                rm -rf /QQ/resources/app/app_launcher/napcat
            fi
            
            # 检查并删除QQ主目录
            if [ -d "/QQ" ]; then
                echo -e ${yellow}是否删除完整的QQ目录? [y/N]${background};read delqq
                case ${delqq} in
                    Y|y)
                        echo -e ${yellow}正在删除QQ目录...${background}
                        rm -rf /QQ
                        ;;
                    *)
                        echo -e ${yellow}保留QQ主目录${background}
                        ;;
                esac
            fi
            
            # 因为NapCat没有提供卸载脚本，所以我们尝试移除已知的文件和包
            if [ $(command -v apt) ]; then
                apt remove -y qq*
                apt autoremove -y
            elif [ $(command -v yum) ]; then
                yum remove -y qq*
                yum autoremove -y
            elif [ $(command -v dnf) ]; then
                dnf remove -y qq*
                dnf autoremove -y
            elif [ $(command -v pacman) ]; then
                pacman -Rns --noconfirm qq
            fi
            
            # 清理配置文件
            rm -rf ~/.config/qq
            
            # 清理可能的桌面和应用程序入口
            rm -f /usr/share/applications/qq.desktop
            rm -f ~/Desktop/qq.desktop

            # 清理命令行工具
            rm -f /usr/local/bin/napcat
            
            echo -e ${green}${APP_NAME}卸载完成${background}
            echo -en ${cyan}回车返回${background};read
            ;;
        *)
            echo -e ${yellow}已取消卸载${background}
            echo -en ${cyan}回车返回${background};read
            ;;
    esac
}

# 管理 WebUI 配置
manage_webui_config() {
    # 检查 NapCat 是否已安装
    if ! check_installed; then
        echo -e ${red}${APP_NAME}未安装，无法管理 WebUI 配置${background}
        echo -en ${cyan}回车返回${background};read
        return 1
    fi
    
    # 检查配置文件是否存在
    WEB_UI_CONFIG="/opt/QQ/resources/app/app_launcher/napcat/config/webui.json"
    if [ ! -f "$WEB_UI_CONFIG" ]; then
        echo -e ${red}WebUI 配置文件不存在: ${WEB_UI_CONFIG}${background}
        echo -en ${cyan}回车返回${background};read
        return 1
    fi
    
    # 检查 jq 是否安装
    if ! command -v jq &> /dev/null; then
        echo -e ${yellow}需要安装 jq 来管理 JSON 配置文件${background}
        if [ $(command -v apt) ]; then
            apt update -y
            apt install -y jq
        elif [ $(command -v yum) ]; then
            yum makecache -y
            yum install -y jq
        elif [ $(command -v dnf) ]; then
            dnf makecache -y
            dnf install -y jq
        elif [ $(command -v pacman) ]; then
            pacman -Syy --noconfirm --needed jq
        else
            echo -e ${red}不支持的Linux发行版，无法安装jq${background}
            echo -en ${cyan}回车返回${background};read
            return 1
        fi
    fi
    
    # 备份原配置文件
    cp "$WEB_UI_CONFIG" "${WEB_UI_CONFIG}.bak"
    
    while true; do
        clear
        echo -e ${white}"====="${green}WebUI 配置管理${white}"====="${background}
        
        # 读取当前配置
        HOST=$(jq -r '.host // "0.0.0.0"' "$WEB_UI_CONFIG")
        PORT=$(jq -r '.port // 6099' "$WEB_UI_CONFIG")
        TOKEN=$(jq -r '.token // "napcat"' "$WEB_UI_CONFIG")
        LOGIN_RATE=$(jq -r '.loginRate // 10' "$WEB_UI_CONFIG")
        AUTO_LOGIN=$(jq -r '.autoLoginAccount // ""' "$WEB_UI_CONFIG")
        
        # 显示当前配置
        echo -e ${yellow}当前 WebUI 配置信息:${background}
        echo -e ${green}1. ${cyan}WebUI 监听地址 \(host\): ${yellow}${HOST}${background}
        echo -e ${green}2. ${cyan}WebUI 端口 \(port\): ${yellow}${PORT}${background}
        echo -e ${green}3. ${cyan}登录密钥 \(token\): ${yellow}${TOKEN}${background}
        echo -e ${green}4. ${cyan}每分钟登录次数限制 \(loginRate\): ${yellow}${LOGIN_RATE}${background}
        echo -e ${green}5. ${cyan}自动登录账号 \(autoLoginAccount\): ${yellow}${AUTO_LOGIN}${background}
        echo -e ${green}6. ${cyan}保存并重启服务${background}
        echo -e ${green}0. ${cyan}返回主菜单${background}
        echo "========================="
        echo -e ${green}WebUI 访问地址: ${cyan}http://${HOST}:${PORT}${background}
        echo -e ${green}登录密钥: ${cyan}${TOKEN}${background}
        echo "========================="
        
        echo -en ${green}请输入选项: ${background};read option
        
        case $option in
            1)
                echo -en ${cyan}请输入新的主机地址 \(当前: ${HOST}\): ${background};read new_host
                if [ -n "$new_host" ]; then
                    jq --arg host "$new_host" '.host = $host' "$WEB_UI_CONFIG" > "${WEB_UI_CONFIG}.tmp" && mv "${WEB_UI_CONFIG}.tmp" "$WEB_UI_CONFIG"
                    echo -e ${green}主机地址已修改为: ${cyan}${new_host}${background}
                    sleep 1
                fi
                ;;
            2)
                echo -en ${cyan}请输入新的端口 \(当前: ${PORT}\): ${background};read new_port
                if [[ "$new_port" =~ ^[0-9]+$ ]] && [ "$new_port" -ge 1 ] && [ "$new_port" -le 65535 ]; then
                    jq --argjson port "$new_port" '.port = $port' "$WEB_UI_CONFIG" > "${WEB_UI_CONFIG}.tmp" && mv "${WEB_UI_CONFIG}.tmp" "$WEB_UI_CONFIG"
                    echo -e ${green}端口已修改为: ${cyan}${new_port}${background}
                    sleep 1
                else
                    echo -e ${red}端口必须是1-65535之间的数字${background}
                    sleep 2
                fi
                ;;
            3)
                echo -en ${cyan}请输入新的访问令牌 \(当前: ${TOKEN}\): ${background};read new_token
                if [ -n "$new_token" ]; then
                    jq --arg token "$new_token" '.token = $token' "$WEB_UI_CONFIG" > "${WEB_UI_CONFIG}.tmp" && mv "${WEB_UI_CONFIG}.tmp" "$WEB_UI_CONFIG"
                    echo -e ${green}访问令牌已修改为: ${cyan}${new_token}${background}
                    sleep 1
                fi
                ;;
            4)
                echo -en ${cyan}请输入新的每分钟登录次数限制 \(当前: ${LOGIN_RATE}\): ${background};read new_rate
                if [[ "$new_rate" =~ ^[0-9]+$ ]]; then
                    jq --argjson rate "$new_rate" '.loginRate = $rate' "$WEB_UI_CONFIG" > "${WEB_UI_CONFIG}.tmp" && mv "${WEB_UI_CONFIG}.tmp" "$WEB_UI_CONFIG"
                    echo -e ${green}每分钟登录次数限制已修改为: ${cyan}${new_rate}${background}
                    sleep 1
                else
                    echo -e ${red}每分钟登录次数限制必须是数字${background}
                    sleep 2
                fi
                ;;
            5)
                echo -en ${cyan}请输入新的自动登录账号 \(当前: ${AUTO_LOGIN}\): ${background};read new_auto_login
                jq --arg auto "$new_auto_login" '.autoLoginAccount = $auto' "$WEB_UI_CONFIG" > "${WEB_UI_CONFIG}.tmp" && mv "${WEB_UI_CONFIG}.tmp" "$WEB_UI_CONFIG"
                echo -e ${green}自动登录账号已修改为: ${cyan}${new_auto_login}${background}
                sleep 1
                ;;
            6)
                echo -e ${yellow}配置已保存，是否重启 ${APP_NAME} 服务? [Y/n]${background};read restart_yn
                case ${restart_yn} in
                    Y|y|"")
                        if check_running; then
                            echo -e ${yellow}正在重启 ${APP_NAME}...${background}
                            stop_NapCat > /dev/null 2>&1
                            sleep 2
                            start_NapCat
                        else
                            echo -e ${yellow}${APP_NAME} 未运行，是否启动? [Y/n]${background};read start_yn
                            case ${start_yn} in
                                Y|y|"")
                                    start_NapCat
                                    ;;
                            esac
                        fi
                        return 0
                        ;;
                    *)
                        echo -e ${yellow}配置已保存，但服务未重启${background}
                        sleep 1
                        ;;
                esac
                ;;
            0)
                return 0
                ;;
            *)
                echo -e ${red}无效选项${background}
                sleep 1
                ;;
        esac
    done
}

# 管理已登录QQ账号
manage_qq_accounts() {
    # 检查 NapCat 是否已安装
    if ! check_installed; then
        echo -e ${red}${APP_NAME}未安装，无法管理QQ账号${background}
        echo -en ${cyan}回车返回${background};read
        return 1
    fi
    
    # 检查配置目录是否存在
    CONFIG_DIR="/opt/QQ/resources/app/app_launcher/napcat/config"
    if [ ! -d "$CONFIG_DIR" ]; then
        echo -e ${red}配置目录不存在: ${CONFIG_DIR}${background}
        echo -en ${cyan}回车返回${background};read
        return 1
    fi
    
    # 查找已登录的QQ账号
    echo -e ${yellow}正在查找已登录的QQ账号...${background}
    account_files=$(find "$CONFIG_DIR" -name "napcat_*.json" 2>/dev/null)
    
    if [ -z "$account_files" ]; then
        echo -e ${red}未找到已登录的QQ账号${background}
        echo -e ${yellow}请先使用前台启动方式登录QQ账号${background}
        echo -en ${cyan}回车返回${background};read
        return 1
    fi
    
    # 提取并显示QQ号码列表
    echo -e ${green}已找到以下QQ账号:${background}
    i=1
    declare -a qq_numbers
    
    while IFS= read -r file; do
        qq_number=$(basename "$file" | sed -n 's/napcat_\([0-9]*\)\.json/\1/p')
        if [ -n "$qq_number" ]; then
            qq_numbers+=("$qq_number")
            echo -e ${green}$i. ${cyan}$qq_number${background}
            i=$((i+1))
        fi
    done <<< "$account_files"
    
    echo -e ${green}0. ${cyan}返回主菜单${background}
    echo
    
    # 让用户选择要登录的QQ账号
    echo -en ${yellow}请选择要登录的QQ账号编号: ${background};read choice
    
    if [ "$choice" = "0" ];then
        return 0
    fi
    
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#qq_numbers[@]} ]; then
        echo -e ${red}无效的选择${background}
        echo -en ${cyan}回车返回${background};read
        return 1
    fi
    
    selected_qq=${qq_numbers[$((choice-1))]}
    
    # 检查是否当前已有运行的NapCat实例
    if check_running; then
        echo -e ${yellow}已有${APP_NAME}实例在运行，是否停止并切换到选定的QQ账号? [Y/n]${background};read yn
        case ${yn} in
            Y|y|"")
                echo -e ${yellow}正在停止当前${APP_NAME}实例...${background}
                stop_NapCat > /dev/null 2>&1
                ;;
            *)
                echo -e ${yellow}操作已取消${background}
                echo -en ${cyan}回车返回${background};read
                return 0
                ;;
        esac
    fi
    
    # 启动选定的QQ账号
    echo -e ${yellow}正在启动QQ账号: ${cyan}${selected_qq}${background}
    check_tmux
    
    # 选择启动方式
    echo -e ${cyan}请选择启动方式${background}
    echo -e ${green}1. ${cyan}前台启动${background}
    echo -e ${green}2. ${cyan}后台启动（推荐）${background}
    echo "========================="
    echo -en ${green}请输入您的选项: ${background};read start_option
    
    case ${start_option} in
        1)
            # 前台启动特定QQ账号
            echo -e ${yellow}正在前台启动QQ账号: ${cyan}${selected_qq}${background}
            echo -e ${cyan}提示: 退出请按 Ctrl+C${background}
            xvfb-run -a qq --no-sandbox -q ${selected_qq}
            echo -en ${cyan}回车返回${background};read
            ;;
        2)
            # 后台启动特定QQ账号
            echo -e ${yellow}正在后台启动QQ账号: ${cyan}${selected_qq}${background}
            tmux new-session -d -s ${TMUX_NAME} "xvfb-run -a qq --no-sandbox -q ${selected_qq}"
            
            # 检查是否成功启动
            sleep 2
            if check_running; then
                echo -e ${green}QQ账号 ${selected_qq} 已成功在后台启动${background}
                echo -e ${cyan}提示: 使用 '查看日志' 功能可以访问${APP_NAME}界面${background}
            else
                echo -e ${red}QQ账号启动失败，请检查错误信息${background}
            fi
            echo -en ${cyan}回车返回${background};read
            ;;
        *)
            echo -e ${red}输入错误${background}
            echo -en ${cyan}回车返回${background};read
            ;;
    esac
}

# 配置WebSocket连接
configure_ws() {
    # 检查 NapCat 是否已安装
    if ! check_installed; then
        echo -e ${red}${APP_NAME}未安装，无法配置WebSocket${background}
        echo -en ${cyan}回车返回${background};read
        return 1
    fi
    
    # 检查配置目录是否存在
    CONFIG_DIR="/opt/QQ/resources/app/app_launcher/napcat/config"
    if [ ! -d "$CONFIG_DIR" ]; then
        echo -e ${red}配置目录不存在${background}
        echo -en ${cyan}回车返回${background};read
        return 1
    fi
    
    # 检查 jq 是否安装
    if ! command -v jq &> /dev/null; then
        echo -e ${yellow}需要安装 jq 来管理 JSON 配置文件${background}
        if [ $(command -v apt) ]; then
            apt update -y
            apt install -y jq
        elif [ $(command -v yum) ]; then
            yum makecache -y
            yum install -y jq
        elif [ $(command -v dnf) ]; then
            dnf makecache -y
            dnf install -y jq
        elif [ $(command -v pacman) ]; then
            pacman -Syy --noconfirm --needed jq
        else
            echo -e ${red}不支持的Linux发行版，无法安装jq${background}
            echo -en ${cyan}回车返回${background};read
            return 1
        fi
    fi
    
    # 查找已登录的QQ账号
    echo -e ${yellow}正在查找已登录的QQ账号...${background}
    account_files=$(find "$CONFIG_DIR" -name "onebot11_*.json" 2>/dev/null)
    
    if [ -z "$account_files" ]; then
        echo -e ${red}未找到已登录的QQ账号配置文件${background}
        echo -e ${yellow}请先使用前台启动方式登录QQ账号${background}
        echo -en ${cyan}回车返回${background};read
        return 1
    fi
    
    # 提取并显示QQ号码列表
    echo -e ${green}已找到以下QQ账号:${background}
    i=1
    declare -a qq_numbers
    
    while IFS= read -r file; do
        qq_number=$(basename "$file" | sed -n 's/onebot11_\([0-9]*\)\.json/\1/p')
        if [ -n "$qq_number" ]; then
            qq_numbers+=("$qq_number")
            echo -e ${green}$i. ${cyan}$qq_number${background}
            i=$((i+1))
        fi
    done <<< "$account_files"
    
    echo -e ${green}0. ${cyan}返回主菜单${background}
    echo
    
    # 让用户选择要配置的QQ账号
    echo -en ${yellow}请选择要配置WebSocket的QQ账号编号: ${background};read choice
    
    if [ "$choice" = "0" ]; then
        return 0
    fi
    
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#qq_numbers[@]} ]; then
        echo -e ${red}无效的选择${background}
        echo -en ${cyan}回车返回${background};read
        return 1
    fi
    
    selected_qq=${qq_numbers[$((choice-1))]}
    CONFIG_FILE="${CONFIG_DIR}/onebot11_${selected_qq}.json"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e ${red}配置文件不存在: ${CONFIG_FILE}${background}
        echo -en ${cyan}回车返回${background};read
        return 1
    fi
    
    # 备份原配置文件
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
    
    # 定义预置配置
    LAIN_CONFIG='{
  "network": {
    "httpServers": [],
    "httpSseServers": [],
    "httpClients": [],
    "websocketServers": [],
    "websocketClients": [
      {
        "enable": true,
        "name": "lain",
        "url": "ws://localhost:2956/onebot/v11/ws",
        "reportSelfMessage": false,
        "messagePostFormat": "array",
        "token": "",
        "debug": false,
        "heartInterval": 30000,
        "reconnectInterval": 30000
      }
    ],
    "plugins": []
  },
  "musicSignUrl": "https://oiapi.net/API/QQMusic/SONArk",
  "enableLocalFile2Url": false,
  "parseMultMsg": false
}'

    TRSS_CONFIG='{
  "network": {
    "httpServers": [],
    "httpSseServers": [],
    "httpClients": [],
    "websocketServers": [],
    "websocketClients": [
      {
        "enable": true,
        "name": "trss",
        "url": "ws://localhost:2536/OneBotv11",
        "reportSelfMessage": false,
        "messagePostFormat": "array",
        "token": "",
        "debug": false,
        "heartInterval": 30000,
        "reconnectInterval": 30000
      }
    ],
    "plugins": []
  },
  "musicSignUrl": "https://oiapi.net/API/QQMusic/SONArk",
  "enableLocalFile2Url": false,
  "parseMultMsg": false
}'

    # 管理WebSocket连接的主菜单
    while true; do
        clear
        echo -e ${white}"====="${green}WebSocket配置管理 - QQ: ${selected_qq}${white}"====="${background}
        
        # 检查当前配置
        if [ -f "$CONFIG_FILE" ]; then
            # 获取当前WebSocket客户端数量
            WS_COUNT=$(jq '.network.websocketClients | length // 0' "$CONFIG_FILE")
            
            if [ "$WS_COUNT" -gt 0 ]; then
                echo -e ${yellow}当前配置的WebSocket接口 (${WS_COUNT}个):${background}
                for ((i=0; i<$WS_COUNT; i++)); do
                    WS_NAME=$(jq -r ".network.websocketClients[$i].name // \"未命名\"" "$CONFIG_FILE")
                    WS_URL=$(jq -r ".network.websocketClients[$i].url // \"未设置\"" "$CONFIG_FILE")
                    WS_ENABLE=$(jq -r ".network.websocketClients[$i].enable // false" "$CONFIG_FILE")
                    
                    if [ "$WS_ENABLE" = "true" ]; then
                        status="${green}已启用"
                    else
                        status="${red}已禁用"
                    fi
                    
                    echo -e ${green}[$((i+1))] ${cyan}${WS_NAME} ${yellow}- ${cyan}${WS_URL} ${yellow}- ${status}${background}
                done
            else
                echo -e ${yellow}未配置任何WebSocket接口${background}
            fi
        else
            echo -e ${red}配置文件不存在或损坏${background}
        fi
        
        echo -e ${yellow}"==========================="${background}
        echo -e ${green}1. ${cyan}使用预设模板${background}
        echo -e ${green}2. ${cyan}添加新的WebSocket接口${background}
        echo -e ${green}3. ${cyan}编辑WebSocket接口${background}
        echo -e ${green}4. ${cyan}删除WebSocket接口${background}
        echo -e ${green}5. ${cyan}启用/禁用WebSocket接口${background}
        echo -e ${green}0. ${cyan}返回上级菜单${background}
        echo -e ${yellow}"==========================="${background}
        
        echo -en ${green}请选择操作: ${background};read option
        
        case $option in
            1)
                # 使用预设模板子菜单
                clear
                echo -e ${white}"====="${green}WebSocket预设模板${white}"====="${background}
                echo -e ${green}1. ${cyan}使用 lain 配置${background}
                echo -e ${green}2. ${cyan}使用 trss 配置${background}
                echo -e ${green}0. ${cyan}返回上级菜单${background}
                echo -e ${yellow}"==========================="${background}
                
                echo -en ${green}请选择模板: ${background};read template_option
                
                case $template_option in
                    1)
                        # 使用 lain 配置
                        echo -e ${yellow}正在应用 lain 配置...${background}
                        echo -e ${yellow}注意: 这将覆盖当前所有WebSocket配置!${background}
                        echo -en ${cyan}是否继续? [y/N]: ${background};read confirm
                        
                        if [[ "$confirm" =~ ^[Yy]$ ]]; then
                            echo "$LAIN_CONFIG" > "$CONFIG_FILE"
                            echo -e ${green}已应用 lain 配置${background}
                        else
                            echo -e ${yellow}已取消操作${background}
                        fi
                        sleep 1
                        ;;
                    2)
                        # 使用 trss 配置
                        echo -e ${yellow}正在应用 trss 配置...${background}
                        echo -e ${yellow}注意: 这将覆盖当前所有WebSocket配置!${background}
                        echo -en ${cyan}是否继续? [y/N]: ${background};read confirm
                        
                        if [[ "$confirm" =~ ^[Yy]$ ]]; then
                            echo "$TRSS_CONFIG" > "$CONFIG_FILE"
                            echo -e ${green}已应用 trss 配置${background}
                        else
                            echo -e ${yellow}已取消操作${background}
                        fi
                        sleep 1
                        ;;
                    0)
                        # 返回上级菜单
                        continue
                        ;;
                    *)
                        echo -e ${red}无效选项${background}
                        sleep 1
                        ;;
                esac
                ;;
            2)
                # 添加新的WebSocket接口
                echo -e ${yellow}添加新的WebSocket接口${background}
                
                echo -en ${cyan}请输入名称 \(默认: custom\): ${background};read ws_name
                ws_name=${ws_name:-custom}
                
                echo -en ${cyan}请输入WebSocket URL: ${background};read ws_url
                if [ -z "$ws_url" ]; then
                    echo -e ${red}URL不能为空${background}
                    sleep 1
                    continue
                fi
                
                echo -en ${cyan}请输入token \(可留空\): ${background};read ws_token
                
                echo -en ${cyan}是否启用该WebSocket连接? [Y/n]: ${background};read ws_enable
                if [[ "$ws_enable" =~ ^[Nn]$ ]]; then
                    enable_ws="false"
                else
                    enable_ws="true"
                fi
                
                # 创建新的WebSocket配置对象
                new_ws=$(cat << EOF
{
  "enable": ${enable_ws},
  "name": "${ws_name}",
  "url": "${ws_url}",
  "reportSelfMessage": false,
  "messagePostFormat": "array",
  "token": "${ws_token}",
  "debug": false,
  "heartInterval": 30000,
  "reconnectInterval": 30000
}
EOF
                )
                
                # 检查配置文件是否存在
                if [ ! -f "$CONFIG_FILE" ] || ! jq -e '.' "$CONFIG_FILE" &>/dev/null; then
                    # 如果配置文件不存在或无效，创建新配置文件
                    echo '{
  "network": {
    "httpServers": [],
    "httpSseServers": [],
    "httpClients": [],
    "websocketServers": [],
    "websocketClients": [],
    "plugins": []
  },
  "musicSignUrl": "https://oiapi.net/API/QQMusic/SONArk",
  "enableLocalFile2Url": false,
  "parseMultMsg": false
}' > "$CONFIG_FILE"
                fi
                
                # 添加新的WebSocket配置
                jq --argjson ws "$new_ws" '.network.websocketClients += [$ws]' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && 
                mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
                
                echo -e ${green}已添加新的WebSocket接口: ${cyan}${ws_name} - ${ws_url}${background}
                sleep 1
                ;;
            3)
                # 编辑WebSocket接口
                WS_COUNT=$(jq '.network.websocketClients | length // 0' "$CONFIG_FILE")
                
                if [ "$WS_COUNT" -eq 0 ]; then
                    echo -e ${red}没有可编辑的WebSocket接口${background}
                    sleep 1
                    continue
                fi
                
                echo -e ${yellow}请选择要编辑的WebSocket接口:${background}
                for ((i=0; i<$WS_COUNT; i++)); do
                    WS_NAME=$(jq -r ".network.websocketClients[$i].name // \"未命名\"" "$CONFIG_FILE")
                    WS_URL=$(jq -r ".network.websocketClients[$i].url // \"未设置\"" "$CONFIG_FILE")
                    echo -e ${green}$((i+1)). ${cyan}${WS_NAME} - ${WS_URL}${background}
                done
                echo -e ${green}0. ${cyan}返回${background}
                
                echo -en ${green}请输入编号: ${background};read edit_choice
                
                if [ "$edit_choice" = "0" ]; then
                    continue
                fi
                
                if ! [[ "$edit_choice" =~ ^[0-9]+$ ]] || [ "$edit_choice" -lt 1 ] || [ "$edit_choice" -gt "$WS_COUNT" ]; then
                    echo -e ${red}无效的选择${background}
                    sleep 1
                    continue
                fi
                
                edit_index=$((edit_choice-1))
                
                # 获取当前配置
                current_name=$(jq -r ".network.websocketClients[$edit_index].name // \"\"" "$CONFIG_FILE")
                current_url=$(jq -r ".network.websocketClients[$edit_index].url // \"\"" "$CONFIG_FILE")
                current_token=$(jq -r ".network.websocketClients[$edit_index].token // \"\"" "$CONFIG_FILE")
                current_enable=$(jq -r ".network.websocketClients[$edit_index].enable // false" "$CONFIG_FILE")
                
                # 编辑配置
                echo -e ${yellow}编辑WebSocket接口 ${edit_choice}:${background}
                
                echo -en ${cyan}请输入名称 \(当前: ${current_name}\): ${background};read ws_name
                ws_name=${ws_name:-$current_name}
                
                echo -en ${cyan}请输入WebSocket URL \(当前: ${current_url}\): ${background};read ws_url
                ws_url=${ws_url:-$current_url}
                
                echo -en ${cyan}请输入token \(当前: ${current_token}\): ${background};read ws_token
                ws_token=${ws_token:-$current_token}
                
                echo -en ${cyan}是否启用该WebSocket连接? [Y/n]: ${background};read ws_enable
                if [[ "$ws_enable" =~ ^[Nn]$ ]]; then
                    enable_ws="false"
                else
                    enable_ws="true"
                fi
                
                # 更新配置
                jq \
                --arg name "$ws_name" \
                --arg url "$ws_url" \
                --arg token "$ws_token" \
                --argjson enable "$enable_ws" \
                ".network.websocketClients[$edit_index].name = \$name | 
                 .network.websocketClients[$edit_index].url = \$url | 
                 .network.websocketClients[$edit_index].token = \$token | 
                 .network.websocketClients[$edit_index].enable = \$enable" \
                "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && 
                mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
                
                echo -e ${green}已更新WebSocket接口配置${background}
                sleep 1
                ;;
            4)
                # 删除WebSocket接口
                WS_COUNT=$(jq '.network.websocketClients | length // 0' "$CONFIG_FILE")
                
                if [ "$WS_COUNT" -eq 0 ]; then
                    echo -e ${red}没有可删除的WebSocket接口${background}
                    sleep 1
                    continue
                fi
                
                echo -e ${yellow}请选择要删除的WebSocket接口:${background}
                for ((i=0; i<$WS_COUNT; i++)); do
                    WS_NAME=$(jq -r ".network.websocketClients[$i].name // \"未命名\"" "$CONFIG_FILE")
                    WS_URL=$(jq -r ".network.websocketClients[$i].url // \"未设置\"" "$CONFIG_FILE")
                    echo -e ${green}$((i+1)). ${cyan}${WS_NAME} - ${WS_URL}${background}
                done
                echo -e ${green}0. ${cyan}返回${background}
                
                echo -en ${green}请输入编号: ${background};read del_choice
                
                if [ "$del_choice" = "0" ]; then
                    continue
                fi
                
                if ! [[ "$del_choice" =~ ^[0-9]+$ ]] || [ "$del_choice" -lt 1 ] || [ "$del_choice" -gt "$WS_COUNT" ]; then
                    echo -e ${red}无效的选择${background}
                    sleep 1
                    continue
                fi
                
                del_index=$((del_choice-1))
                WS_NAME=$(jq -r ".network.websocketClients[$del_index].name // \"未命名\"" "$CONFIG_FILE")
                
                echo -e ${yellow}确认删除WebSocket接口 "${WS_NAME}"? [y/N]: ${background};read confirm
                
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    # 删除指定索引的WebSocket配置
                    jq "del(.network.websocketClients[$del_index])" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && 
                    mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
                    
                    echo -e ${green}已删除WebSocket接口${background}
                else
                    echo -e ${yellow}已取消删除操作${background}
                fi
                sleep 1
                ;;
            5)
                # 启用/禁用WebSocket接口
                WS_COUNT=$(jq '.network.websocketClients | length // 0' "$CONFIG_FILE")
                
                if [ "$WS_COUNT" -eq 0 ]; then
                    echo -e ${red}没有可管理的WebSocket接口${background}
                    sleep 1
                    continue
                fi
                
                echo -e ${yellow}请选择要启用/禁用的WebSocket接口:${background}
                for ((i=0; i<$WS_COUNT; i++)); do
                    WS_NAME=$(jq -r ".network.websocketClients[$i].name // \"未命名\"" "$CONFIG_FILE")
                    WS_URL=$(jq -r ".network.websocketClients[$i].url // \"未设置\"" "$CONFIG_FILE")
                    WS_ENABLE=$(jq -r ".network.websocketClients[$i].enable // false" "$CONFIG_FILE")
                    
                    if [ "$WS_ENABLE" = "true" ]; then
                        status="${green}已启用"
                    else
                        status="${red}已禁用"
                    fi
                    
                    echo -e ${green}$((i+1)). ${cyan}${WS_NAME} - ${WS_URL} ${yellow}- ${status}${background}
                done
                echo -e ${green}0. ${cyan}返回${background}
                
                echo -en ${green}请输入编号: ${background};read toggle_choice
                
                if [ "$toggle_choice" = "0" ]; then
                    continue
                fi
                
                if ! [[ "$toggle_choice" =~ ^[0-9]+$ ]] || [ "$toggle_choice" -lt 1 ] || [ "$toggle_choice" -gt "$WS_COUNT" ]; then
                    echo -e ${red}无效的选择${background}
                    sleep 1
                    continue
                fi
                
                toggle_index=$((toggle_choice-1))
                WS_NAME=$(jq -r ".network.websocketClients[$toggle_index].name // \"未命名\"" "$CONFIG_FILE")
                current_enable=$(jq -r ".network.websocketClients[$toggle_index].enable // false" "$CONFIG_FILE")
                
                # 切换启用/禁用状态
                if [ "$current_enable" = "true" ]; then
                    new_enable="false"
                    action="禁用"
                else
                    new_enable="true"
                    action="启用"
                fi
                
                echo -e ${yellow}确认${action} WebSocket接口 "${WS_NAME}"? [Y/n]: ${background};read confirm
                
                if [[ ! "$confirm" =~ ^[Nn]$ ]]; then
                    # 更新启用/禁用状态
                    jq --argjson enable "$new_enable" ".network.websocketClients[$toggle_index].enable = \$enable" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && 
                    mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
                    
                    echo -e ${green}已${action} WebSocket接口 "${WS_NAME}"${background}
                else
                    echo -e ${yellow}已取消操作${background}
                fi
                sleep 1
                ;;
            0)
                # 返回上级菜单
                return 0
                ;;
            *)
                echo -e ${red}无效选项${background}
                sleep 1
                ;;
        esac
    done
}

# 配置音乐签名URL
configure_music_sign() {
    # 检查 NapCat 是否已安装
    if ! check_installed; then
        echo -e ${red}${APP_NAME}未安装，无法配置音乐签名URL${background}
        echo -en ${cyan}回车返回${background};read
        return 1
    fi
    
    # 检查配置目录是否存在
    CONFIG_DIR="/opt/QQ/resources/app/app_launcher/napcat/config"
    if [ ! -d "$CONFIG_DIR" ]; then
        echo -e ${red}配置目录不存在${background}
        echo -en ${cyan}回车返回${background};read
        return 1
    fi
    
    # 检查 jq 是否安装
    if ! command -v jq &> /dev/null; then
        echo -e ${yellow}需要安装 jq 来管理 JSON 配置文件${background}
        if [ $(command -v apt) ];then
            apt update -y
            apt install -y jq
        elif [ $(command -v yum) ];then
            yum makecache -y
            yum install -y jq
        elif [ $(command -v dnf) ];then
            dnf makecache -y
            dnf install -y jq
        elif [ $(command -v pacman) ];then
            pacman -Syy --noconfirm --needed jq
        else
            echo -e ${red}不支持的Linux发行版，无法安装jq${background}
            echo -en ${cyan}回车返回${background};read
            return 1
        fi
    fi
    
    # 默认音乐签名URL
    DEFAULT_MUSIC_SIGN_URL="https://oiapi.net/API/QQMusic/SONArk"
    
    # 显示配置选项
    while true; do
        clear
        echo -e ${white}"====="${green}音乐签名URL配置${white}"====="${background}
        
        echo -e ${green}1. ${cyan}为所有QQ账号设置音乐签名URL${background}
        echo -e ${green}2. ${cyan}为指定QQ账号设置音乐签名URL${background}
        echo -e ${green}0. ${cyan}返回主菜单${background}
        echo -e ${yellow}"========================="${background}
        echo -e ${green}默认URL: ${cyan}${DEFAULT_MUSIC_SIGN_URL}${background}
        echo -e ${yellow}"========================="${background}
        
        echo -en ${green}请选择操作: ${background};read option
        
        case $option in
            1)
                # 为所有QQ账号设置
                echo -e ${yellow}即将为所有QQ账号设置音乐签名URL${background}
                echo -en ${cyan}输入URL \(默认: ${DEFAULT_MUSIC_SIGN_URL}\): ${background};read music_url
                music_url=${music_url:-$DEFAULT_MUSIC_SIGN_URL}
                
                # 查找所有配置文件
                config_files=$(find "$CONFIG_DIR" -name "onebot11_*.json" 2>/dev/null)
                
                if [ -z "$config_files" ];then
                    echo -e ${red}未找到任何QQ账号配置文件${background}
                    echo -e ${yellow}请先使用前台启动方式登录QQ账号${background}
                    echo -en ${cyan}回车返回${background};read
                    continue
                fi
                
                count=0
                while IFS= read -r file; do
                    # 备份原配置文件
                    cp "$file" "${file}.bak"
                    
                    # 更新音乐签名URL
                    if jq -e '.' "$file" &>/dev/null; then
                        jq --arg url "$music_url" '.musicSignUrl = $url' "$file" > "${file}.tmp" && 
                        mv "${file}.tmp" "$file"
                        count=$((count+1))
                    fi
                done <<< "$config_files"
                
                echo -e ${green}已为${count}个QQ账号设置音乐签名URL${background}
                echo -en ${cyan}回车返回${background};read
                ;;
            2)
                # 为指定QQ账号设置
                # 查找已登录的QQ账号
                echo -e ${yellow}正在查找已登录的QQ账号...${background}
                onebot_files=$(find "$CONFIG_DIR" -name "onebot11_*.json" 2>/dev/null)
                
                if [ -z "$onebot_files" ]; then
                    echo -e ${red}未找到已登录的QQ账号配置文件${background}
                    echo -e ${yellow}请先使用前台启动方式登录QQ账号${background}
                    echo -en ${cyan}回车返回${background};read
                    continue
                fi
                
                # 提取并显示QQ号码列表
                echo -e ${green}已找到以下QQ账号:${background}
                i=1
                declare -a qq_numbers
                declare -a config_paths
                
                # 处理 onebot11 配置文件
                while IFS= read -r file; do
                    qq_number=$(basename "$file" | sed -n 's/onebot11_\([0-9]*\)\.json/\1/p')
                    if [ -n "$qq_number" ]; then
                        qq_numbers+=("$qq_number")
                        config_paths+=("$file")
                        echo -e ${green}$i. ${cyan}$qq_number ${yellow}\(onebot11\)${background}
                        i=$((i+1))
                    fi
                done <<< "$onebot_files"
                
                echo -e ${green}0. ${cyan}返回上级菜单${background}
                echo
                
                # 让用户选择要配置的QQ账号
                echo -en ${yellow}请选择要配置音乐签名URL的QQ账号编号: ${background};read choice
                
                if [ "$choice" = "0" ];then
                    continue
                fi
                
                if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#qq_numbers[@]} ]; then
                    echo -e ${red}无效的选择${background}
                    echo -en ${cyan}回车返回${background};read
                    continue
                fi
                
                selected_qq=${qq_numbers[$((choice-1))]}
                selected_config=${config_paths[$((choice-1))]}
                
                if [ ! -f "$selected_config" ]; then
                    echo -e ${red}配置文件不存在: ${selected_config}${background}
                    echo -en ${cyan}回车返回${background};read
                    continue
                fi
                
                # 获取当前设置
                current_url=$(jq -r '.musicSignUrl // ""' "$selected_config")
                if [ -z "$current_url" ];then
                    current_url="未设置"
                fi
                
                echo -e ${yellow}QQ: ${cyan}${selected_qq}${background}
                echo -e ${yellow}当前音乐签名URL: ${cyan}${current_url}${background}
                echo -en ${cyan}输入新的URL \(默认: ${DEFAULT_MUSIC_SIGN_URL}\): ${background};read music_url
                music_url=${music_url:-$DEFAULT_MUSIC_SIGN_URL}
                
                # 备份原配置文件
                cp "$selected_config" "${selected_config}.bak"
                
                # 更新音乐签名URL
                jq --arg url "$music_url" '.musicSignUrl = $url' "$selected_config" > "${selected_config}.tmp" && 
                mv "${selected_config}.tmp" "$selected_config"
                
                echo -e ${green}已为 QQ ${selected_qq} 设置音乐签名URL: ${cyan}${music_url}${background}
                echo -en ${cyan}回车返回${background};read
                ;;
            0)
                return 0
                ;;
            *)
                echo -e ${red}无效选项${background}
                sleep 1
                ;;
        esac
    done
}

# 检查更新（如果有 NapCat 更新机制的话）
check_update() {
    echo -e ${yellow}正在检查${APP_NAME}更新...${background}
    
    # 因为不知道 NapCat 的具体更新方式，这里只是简单地重新运行安装脚本
    echo -e ${yellow}将重新运行安装脚本以获取最新版本${background}
    echo -en ${cyan}是否继续? [Y/n]${background};read yn
    case ${yn} in
        Y|y|"")
            if check_running; then
                echo -e ${yellow}更新前需要停止${APP_NAME}${background}
                stop_NapCat > /dev/null 2>&1
            fi
            
            curl -o ${INSTALL_SCRIPT} ${INSTALL_URL} && bash ${INSTALL_SCRIPT}
            rm -f ${INSTALL_SCRIPT}
            
            echo -e ${green}${APP_NAME}更新完成${background}
            echo -en ${yellow}是否重新启动${APP_NAME}? [Y/n]${background};read restart_yn
            case ${restart_yn} in
                Y|y|"")
                    start_NapCat
                    ;;
            esac
            ;;
        *)
            echo -e ${yellow}已取消更新${background}
            echo -en ${cyan}回车返回${background};read
            ;;
    esac
}

# 主菜单
main() {
    if check_installed; then
        if check_running; then
            condition="${green}[已启动]"
        else
            condition="${red}[未启动]"
        fi
    else
        condition="${red}[未部署]"
    fi

    echo -e ${white}"====="${green}呆毛版-${APP_NAME}管理${white}"====="${background}
    echo -e ${green}1.  ${cyan}安装${APP_NAME}${background}
    echo -e ${green}2.  ${cyan}启动${APP_NAME}${background}
    echo -e ${green}3.  ${cyan}关闭${APP_NAME}${background}
    echo -e ${green}4.  ${cyan}重启${APP_NAME}${background}
    echo -e ${green}5.  ${cyan}更新${APP_NAME}${background}
    echo -e ${green}6.  ${cyan}卸载${APP_NAME}${background}
    echo -e ${green}7.  ${cyan}查看日志${background}
    echo -e ${green}8.  ${cyan}WebUI 配置${background}
    echo -e ${green}9.  ${cyan}切换QQ账号${background}
    echo -e ${green}10. ${cyan}配置反向WebSocket${background}
    echo -e ${green}11. ${cyan}音乐签名配置${background}
    echo -e ${green}0.  ${cyan}退出${background}
    echo "========================="
    echo -e ${green}${APP_NAME}状态: ${condition}${background}
    echo -e ${green}说明: ${cyan}安装后“配置反向WebSocket”（推荐trss或喵崽+lain），启动-扫码登录-转后台运行，启动云崽即可。${background}
    echo -e ${green}呆毛版-QQ群: ${cyan}285744328${background}
    echo "========================="
    echo
    echo -en ${green}请输入您的选项: ${background};read number
    case ${number} in
        1)
            echo
            install_NapCat
            ;;
        2)
            echo
            start_NapCat
            ;;
        3)
            echo
            stop_NapCat
            ;;
        4)
            echo
            restart_NapCat
            ;;
        5)
            echo
            check_update
            ;;
        6)
            echo
            uninstall_NapCat
            ;;
        7)
            view_log
            ;;
        8)
            echo
            manage_webui_config
            ;;
        9)
            echo
            manage_qq_accounts
            ;;
        10)
            echo
            configure_ws
            ;;
        11)
            echo
            configure_music_sign
            ;;
        0)
            exit
            ;;
        *)
            echo
            echo -e ${red}输入错误${background}
            sleep 1
            ;;
    esac
}

# 主循环
function mainbak() {
    while true
    do
        main
        mainbak
    done
}

mainbak
