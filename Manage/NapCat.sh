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
    
    # 第二个参数为force_start，如果为true则强制启动新实例
    force_start=${2:-false}
    
    if [ -n "$1" ]; then
        # 如果提供了QQ号作为参数，检查该QQ号是否已在运行
        specific_qq="$1"
        if is_qq_running "$specific_qq"; then
            echo -e ${yellow}QQ号 ${cyan}${specific_qq}${yellow} 已经在运行中${background}
            echo -en ${cyan}回车返回${background};read
            return 0
        fi
        echo -e ${yellow}正在准备启动QQ号: ${cyan}${specific_qq}${background}
    elif check_running && [ "$force_start" != "true" ]; then
        # 如果非强制启动模式，且已有实例在运行，则提示并返回
        echo -e ${yellow}${APP_NAME}已经在运行中${background}
        echo -en ${cyan}回车返回${background};read
        return 0
    fi
    
    if [ -n "$1" ]; then
        # 如果提供了QQ号作为参数，检查该QQ号是否已在运行
        specific_qq="$1"
        if is_qq_running "$specific_qq"; then
            echo -e ${yellow}QQ号 ${cyan}${specific_qq}${yellow} 已经在运行中${background}
            echo -en ${cyan}回车返回${background};read
            return 0
        fi
        echo -e ${yellow}正在准备启动QQ号: ${cyan}${specific_qq}${background}
    elif check_running; then
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
                        # 如果指定了特定QQ号，只选择该QQ号
                        if [ -n "$specific_qq" ] && [ "$qq_number" != "$specific_qq" ]; then
                            continue
                        fi
                        qq_numbers+=("$qq_number")
                        echo -e ${green}$i. ${cyan}$qq_number${background}
                        i=$((i+1))
                    fi
                done <<< "$account_files"
                
                if [ ${#qq_numbers[@]} -eq 0 ]; then
                    echo -e ${red}未找到${specific_qq:+指定的QQ号: $specific_qq}${background}
                    echo -en ${cyan}回车返回${background};read
                    return 1
                fi
                
                # 如果只有一个匹配项且提供了特定QQ号，自动选择该QQ号
                if [ ${#qq_numbers[@]} -eq 1 ] && [ -n "$specific_qq" ]; then
                    selected_qq=${qq_numbers[0]}
                    NAPCAT_CMD="xvfb-run -a qq --no-sandbox -q ${selected_qq}"
                    echo -e ${yellow}已自动选择QQ账号: ${cyan}${selected_qq}${background}
                    sleep 1
                else
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
    
    # 如果已经选择或指定了QQ账号，为该QQ号设置唯一的tmux会话名
    if [ -n "$selected_qq" ]; then
        session_name="${TMUX_NAME}_${selected_qq}"
    else
        session_name="${TMUX_NAME}"
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
            tmux new-session -d -s ${session_name} "export Boolean=true; while \${Boolean}; do ${NAPCAT_CMD}; echo -e '${red}${APP_NAME}已关闭，正在重启...${background}'; sleep 2s; done"
            
            # 检查是否成功启动
            sleep 2
            if tmux list-sessions 2>/dev/null | grep -q ${session_name}; then
                echo -e ${green}${APP_NAME}${selected_qq:+ \(QQ: $selected_qq\)}已成功在后台启动${background}
                echo -e ${cyan}提示: 使用 '查看日志' 功能可以访问${APP_NAME}界面${background}
                
                # 添加是否查看日志的选项
                echo -en ${green}是否立即查看日志（打开日志后退出请按 Ctrl+B 然后按 D）? [Y/n]:${background}; read view_log_yn
                case ${view_log_yn} in
                    Y|y|"")
                        tmux attach-session -t ${session_name}
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
    # 如果提供了QQ号作为参数，只停止该QQ号
    if [ -n "$1" ]; then
        specific_qq="$1"
        session_name="${TMUX_NAME}_${specific_qq}"
        
        if ! tmux list-sessions 2>/dev/null | grep -q ${session_name}; then
            echo -e ${yellow}QQ号 ${cyan}${specific_qq}${yellow} 未在运行${background}
            echo -en ${cyan}回车返回${background};read
            return 0
        fi
        
        echo -e ${yellow}正在停止QQ号 ${cyan}${specific_qq}${yellow}...${background}
        # 将Boolean设置为false以退出自动重启循环
        tmux send-keys -t ${session_name} "Boolean=false" C-m
        sleep 1
        tmux kill-session -t ${session_name}
        
        # 检查是否成功停止
        sleep 2
        if ! tmux list-sessions 2>/dev/null | grep -q ${session_name}; then
            echo -e ${green}QQ号 ${cyan}${specific_qq}${green} 已成功停止${background}
        else
            echo -e ${red}QQ号 ${cyan}${specific_qq}${red} 停止失败，尝试强制终止进程${background}
            pkill -f "qq --no-sandbox -q ${specific_qq}"
            sleep 1
            if ! tmux list-sessions 2>/dev/null | grep -q ${session_name}; then
                echo -e ${green}QQ号 ${cyan}${specific_qq}${green} 已成功停止${background}
            else
                echo -e ${red}无法停止QQ号 ${cyan}${specific_qq}${red}，请手动检查进程${background}
            fi
        fi
        
        echo -en ${cyan}回车返回${background};read
        return 0
    fi
    
    # 无参数时，检查是否有基本会话在运行
    if ! check_running; then
        # 检查是否有任何QQ实例在运行
        if ! list_running_instances >/dev/null; then
            echo -e ${yellow}${APP_NAME}未运行${background}
            echo -en ${cyan}回车返回${background};read
            return 0
        else
            # 如果有QQ实例在运行，显示停止所有实例的选项
            echo -e ${yellow}发现以下QQ实例正在运行:${background}
            list_running_instances
            echo -en ${yellow}是否停止所有QQ实例? [y/N]${background};read stop_all
            case ${stop_all} in
                Y|y)
                    # 停止所有QQ实例
                    for session in $(tmux list-sessions 2>/dev/null | grep "^${TMUX_NAME}_" | cut -d: -f1); do
                        qq_number=${session#${TMUX_NAME}_}
                        echo -e ${yellow}正在停止QQ号 ${cyan}${qq_number}${yellow}...${background}
                        tmux send-keys -t ${session} "Boolean=false" C-m
                        sleep 1
                        tmux kill-session -t ${session}
                    done
                    echo -e ${green}已停止所有QQ实例${background}
                    ;;
                *)
                    echo -e ${yellow}操作已取消${background}
                    ;;
            esac
            echo -en ${cyan}回车返回${background};read
            return 0
        fi
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

# 检查特定QQ号是否在运行
is_qq_running() {
    local qq_number="$1"
    if tmux list-sessions 2>/dev/null | grep -q "${TMUX_NAME}_${qq_number}"; then
        return 0  # 正在运行
    fi
    return 1  # 未运行
}

# 列出所有运行中的QQ实例
list_running_instances() {
    # 检查是否有tmux会话
    if ! command -v tmux &> /dev/null || ! tmux list-sessions &> /dev/null; then
        return 1
    fi
    
    # 获取所有napcat相关的tmux会话
    local sessions=$(tmux list-sessions 2>/dev/null | grep "^${TMUX_NAME}\|^${TMUX_NAME}_" | cut -d: -f1)
    
    if [ -z "$sessions" ]; then
        return 1
    fi
    
    local found=false
    
    # 遍历所有会话，提取QQ号
    for session in $sessions; do
        if [[ "$session" == "${TMUX_NAME}" ]]; then
            echo -e ${green}[*] ${cyan}主实例 ${yellow}- ${purple}会话: ${session}${background}
            found=true
        elif [[ "$session" =~ ^${TMUX_NAME}_([0-9]+)$ ]]; then
            local qq_number=${BASH_REMATCH[1]}
            echo -e ${green}[*] ${cyan}QQ号: ${qq_number} ${yellow}- ${purple}会话: ${session}${background}
            found=true
        fi
    done
    
    if $found; then
        return 0
    else
        return 1
    fi
}

# 查看 NapCat 日志/界面
view_log() {
    if ! check_running && ! list_running_instances >/dev/null; then
        echo -e ${yellow}${APP_NAME}未运行，无法查看日志${background}
        echo -en ${cyan}回车返回${background};read
        return 1
    fi
    
    # 如果有多个实例，让用户选择
    if list_running_instances >/dev/null; then
        # 显示QQ实例列表
        echo -e ${yellow}当前运行的QQ实例:${background}
        list_running_instances
        
        # 创建会话名数组
        declare -a sessions
        declare -a display_names
        
        # 填充数组
        i=0
        while read -r line; do
            if [[ "$line" =~ QQ号:\ ([0-9]+).*会话:\ (${TMUX_NAME}_[0-9]+) ]]; then
                qq_number="${BASH_REMATCH[1]}"
                session="${BASH_REMATCH[2]}"
                sessions+=("$session")
                display_names+=("QQ号: $qq_number")
                i=$((i+1))
            elif [[ "$line" =~ 主实例.*会话:\ (${TMUX_NAME}) ]]; then
                session="${BASH_REMATCH[1]}"
                sessions+=("$session")
                display_names+=("主实例")
                i=$((i+1))
            fi
        done < <(list_running_instances)
        
        # 如果只有一个实例，直接连接
        if [ ${#sessions[@]} -eq 1 ]; then
            echo -e ${yellow}正在连接到唯一的实例: ${cyan}${display_names[0]}${background}
            echo -e ${cyan}提示: 退出请按 Ctrl+B 然后按 D${background}
            echo -en ${cyan}按回车键继续${background};read
            sleep 1
            
            tmux attach-session -t ${sessions[0]}
            return 0
        fi
        
        # 打印选项
        echo -e ${yellow}请选择要查看的实例:${background}
        for ((j=0; j<${#sessions[@]}; j++)); do
            echo -e ${green}$((j+1)). ${cyan}${display_names[$j]}${background}
        done
        
        echo -e ${green}0. ${cyan}返回${background}
        echo
        
        # 让用户选择要查看的实例
        echo -en ${yellow}请选择要查看的实例编号: ${background};read choice
        
        if [ "$choice" = "0" ]; then
            return 0
        fi
        
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#sessions[@]} ]; then
            echo -e ${red}无效的选择${background}
            echo -en ${cyan}回车返回${background};read
            return 1
        fi
        
        selected_session=${sessions[$((choice-1))]}
        
        echo -e ${yellow}正在连接到 ${cyan}${display_names[$((choice-1))]}${yellow} 的界面...${background}
        echo -e ${cyan}提示: 退出请按 Ctrl+B 然后按 D${background}
        echo -en ${cyan}按回车键继续${background};read
        sleep 1
        
        tmux attach-session -t $selected_session
        return 0
    fi
    
    # 默认连接到主实例
    echo -e ${yellow}正在连接到${APP_NAME}界面...${background}
    echo -e ${cyan}提示: 退出请按 Ctrl+B 然后按 D${background}
    sleep 1
    
    tmux attach-session -t ${TMUX_NAME}
}

# 卸载 NapCat
uninstall_NapCat() {
    echo -e ${yellow}是否确认卸载${APP_NAME}? [y/N]${background};read yn
    case ${yn} in
        Y|y)
            # 停止所有运行中的实例
            echo -e ${yellow}正在停止所有运行中的${APP_NAME}实例...${background}
            
            # 停止主实例（如果存在）
            if check_running; then
                tmux send-keys -t ${TMUX_NAME} "Boolean=false" C-m
                sleep 1
                tmux kill-session -t ${TMUX_NAME}
            fi
            
            # 停止所有QQ号实例
            for session in $(tmux list-sessions 2>/dev/null | grep "^${TMUX_NAME}_" | cut -d: -f1); do
                qq_number=${session#${TMUX_NAME}_}
                echo -e ${yellow}正在停止QQ号 ${cyan}${qq_number}${yellow}...${background}
                tmux send-keys -t ${session} "Boolean=false" C-m
                sleep 1
                tmux kill-session -t ${session}
            done
            
            echo -e ${yellow}正在卸载${APP_NAME}...${background}
            
            # 使用包管理器卸载QQ（Ubuntu方式）
            if [ $(command -v apt) ]; then
                echo -e ${yellow}使用apt卸载QQ...${background}
                apt purge -y qq* linuxqq* 2>/dev/null
                apt autoremove -y
            elif [ $(command -v yum) ]; then
                echo -e ${yellow}使用yum卸载QQ...${background}
                yum remove -y qq* linuxqq* 2>/dev/null
                yum autoremove -y
            elif [ $(command -v dnf) ]; then
                echo -e ${yellow}使用dnf卸载QQ...${background}
                dnf remove -y qq* linuxqq* 2>/dev/null
                dnf autoremove -y
            elif [ $(command -v pacman) ]; then
                echo -e ${yellow}使用pacman卸载QQ...${background}
                pacman -Rns --noconfirm qq linuxqq 2>/dev/null
            else
                echo -e ${red}不支持的Linux发行版，尝试手动删除文件${background}
            fi
            
            # 彻底删除所有相关目录和文件
            echo -e ${yellow}正在删除所有QQ相关文件和数据...${background}
            
            # 删除NapCat和QQ主目录
            rm -rf /opt/QQ
            rm -rf /QQ
            
            # 删除所有用户的QQ配置和数据
            rm -rf /root/.config/qq
            rm -rf /home/*/.config/qq
            
            # 删除所有用户的NapCat配置和数据
            rm -rf /root/.config/napcat
            rm -rf /home/*/.config/napcat
            
            # 删除所有用户的QQ数据目录
            rm -rf /root/.linuxqq
            rm -rf /home/*/.linuxqq
            
            # 删除系统级别的QQ配置和数据
            rm -rf /etc/QQ
            rm -rf /etc/napcat
            
            # 删除应用程序快捷方式和菜单项
            rm -f /usr/share/applications/qq*.desktop
            rm -f /usr/share/applications/linuxqq*.desktop
            rm -f /usr/local/share/applications/qq*.desktop
            
            # 删除桌面快捷方式
            rm -f /root/Desktop/qq*.desktop
            rm -f /home/*/Desktop/qq*.desktop
            
            # 删除可执行文件
            rm -f /usr/bin/qq
            rm -f /usr/local/bin/qq
            rm -f /usr/bin/napcat
            rm -f /usr/local/bin/napcat
            
            echo -e ${green}${APP_NAME}及所有相关数据已彻底卸载完成${background}
            echo -e ${yellow}若要重新安装，请重新运行安装命令${background}
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
        echo -en ${green}WebUI 访问地址: ${cyan}http://${HOST}:${PORT}${background}
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
    
    if [ -z "$account_files" ];then
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
        if [ -n "$qq_number" ];then
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
    
    if [ "$choice" = "0" ];then
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
                echo -e ${yellow}当前配置的WebSocket接口 \(${WS_COUNT}个\):${background}
                for ((i=0; i<$WS_COUNT; i++)); do
                    WS_NAME=$(jq -r ".network.websocketClients[$i].name // \"未命名\"" "$CONFIG_FILE")
                    WS_URL=$(jq -r ".network.websocketClients[$i].url // \"未设置\"" "$CONFIG_FILE")
                    WS_ENABLE=$(jq -r ".network.websocketClients[$i].enable // false" "$CONFIG_FILE")
                    WS_TOKEN=$(jq -r ".network.websocketClients[$i].token // \"\"" "$CONFIG_FILE")
                    
                    if [ "$WS_ENABLE" = "true" ]; then
                        status="${green}已启用"
                    else
                        status="${red}已禁用"
                    fi
                    
                    token_status=""
                    if [ -n "$WS_TOKEN" ]; then
                        token_status="${green}[已设置token]"
                    fi
                    
                    echo -e ${green}[$((i+1))] ${cyan}${WS_NAME} ${yellow}- ${cyan}${WS_URL} ${yellow}- ${status} ${token_status}${background}
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
        echo -e ${green}6. ${cyan}管理WebSocket Token${background}
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
                
                # 如果修改了token，询问是否要同步到TRSS
                if [ "$ws_token" != "$current_token" ] && [ -n "$ws_token" ]; then
                    echo -e ${yellow}检测到Token已修改${background}
                    sync_token_to_trss "$ws_token"
                fi
                
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
                
                echo -en ${yellow}确认删除WebSocket接口 "${WS_NAME}"? [y/N]: ${background};read confirm
                
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
                
                echo -en ${yellow}确认${action} WebSocket接口 "${WS_NAME}"? [Y/n]: ${background};read confirm
                
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
            6)
                # 管理WebSocket Token
                WS_COUNT=$(jq '.network.websocketClients | length // 0' "$CONFIG_FILE")
                
                if [ "$WS_COUNT" -eq 0 ]; then
                    echo -e ${red}没有可管理的WebSocket接口${background}
                    sleep 1
                    continue
                fi
                
                echo -e ${yellow}请选择要管理Token的WebSocket接口:${background}
                for ((i=0; i<$WS_COUNT; i++)); do
                    WS_NAME=$(jq -r ".network.websocketClients[$i].name // \"未命名\"" "$CONFIG_FILE")
                    WS_URL=$(jq -r ".network.websocketClients[$i].url // \"未设置\"" "$CONFIG_FILE")
                    WS_TOKEN=$(jq -r ".network.websocketClients[$i].token // \"\"" "$CONFIG_FILE")
                    
                    token_status=""
                    if [ -n "$WS_TOKEN" ]; then
                        token_status="${green}[已设置token]"
                    else
                        token_status="${red}[未设置token]"
                    fi
                    
                    echo -e ${green}$((i+1)). ${cyan}${WS_NAME} - ${WS_URL} ${token_status}${background}
                done
                echo -e ${green}0. ${cyan}返回${background}
                
                echo -en ${green}请输入编号: ${background};read token_choice
                
                if [ "$token_choice" = "0" ]; then
                    continue
                fi
                
                if ! [[ "$token_choice" =~ ^[0-9]+$ ]] || [ "$token_choice" -lt 1 ] || [ "$token_choice" -gt "$WS_COUNT" ]; then
                    echo -e ${red}无效的选择${background}
                    sleep 1
                    continue
                fi
                
                token_index=$((token_choice-1))
                WS_NAME=$(jq -r ".network.websocketClients[$token_index].name // \"未命名\"" "$CONFIG_FILE")
                current_token=$(jq -r ".network.websocketClients[$token_index].token // \"\"" "$CONFIG_FILE")
                
                echo -e ${yellow}管理 "${WS_NAME}" 的Token${background}
                echo -e ${cyan}当前Token: ${yellow}${current_token:-"未设置"}${background}
                echo
                echo -e ${green}1. ${cyan}修改Token${background}
                echo -e ${green}2. ${cyan}清除Token${background}
                echo -e ${green}0. ${cyan}返回${background}
                
                echo -en ${green}请选择操作: ${background};read token_op
                
                case $token_op in
                    1)
                        echo -en ${cyan}请输入新的Token: ${background};read new_token
                        
                        if [ -n "$new_token" ]; then
                            # 更新Token
                            jq --argjson idx "$token_index" --arg token "$new_token" \
                                '.network.websocketClients[$idx].token = $token' \
                                "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
                            
                            echo -e ${green}Token已更新${background}
                            
                            # 询问是否同步到TRSS-Yunzai配置
                            sync_token_to_trss "$new_token"
                        else
                            echo -e ${yellow}Token未修改${background}
                        fi
                        sleep 1
                        ;;
                    2)
                        echo -en ${yellow}确认清除Token? [y/N]: ${background};read confirm
                        
                        if [[ "$confirm" =~ ^[Yy]$ ]]; then
                            # 清除Token
                            jq --argjson idx "$token_index" \
                                '.network.websocketClients[$idx].token = ""' \
                                "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
                            
                            echo -e ${green}Token已清除${background}
                            
                            # 询问是否同步到TRSS-Yunzai配置
                            sync_token_to_trss ""
                        else
                            echo -e ${yellow}操作已取消${background}
                        fi
                        sleep 1
                        ;;
                    0)
                        continue
                        ;;
                    *)
                        echo -e ${red}无效选项${background}
                        sleep 1
                        ;;
                esac
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

# 同步AccessToken到TRSS-Yunzai配置
sync_token_to_trss() {
    local new_token="$1"
    local trss_config="$HOME/TRSS-Yunzai/config/config/server.yaml"
    
    echo -en ${cyan}是否同步修改TRSS-Yunzai的配置文件? [Y/n]: ${background};read sync_choice
    case $sync_choice in
        n|N)
            echo -e ${yellow}跳过修改TRSS-Yunzai配置${background}
            echo -en ${cyan}回车返回${background};read
            return
            ;;
    esac
    
    # 检查TRSS-Yunzai配置文件是否存在
    if [ ! -f "$trss_config" ]; then
        echo -e ${red}未找到TRSS-Yunzai配置文件: ${yellow}$trss_config${background}
        echo -e ${yellow}请检查TRSS-Yunzai是否已安装或配置路径是否正确${background}
        echo -en ${cyan}请输入TRSS-Yunzai配置文件路径 \(留空跳过\): ${background};read custom_path
        
        if [ -z "$custom_path" ]; then
            echo -e ${yellow}已跳过配置同步${background}
            sleep 2
            return
        elif [ -f "$custom_path" ]; then
            trss_config="$custom_path"
            echo -e ${green}已使用自定义路径: ${cyan}$trss_config${background}
        else
            echo -e ${red}指定的文件不存在: ${yellow}$custom_path${background}
            echo -e ${yellow}已跳过配置同步${background}
            sleep 2
            return
        fi
    fi
    
    # 备份原配置文件
    cp "$trss_config" "$trss_config.bak"
    echo -e ${yellow}已备份原配置至: ${cyan}$trss_config.bak${background}
    
    # 准备Bearer令牌格式
    bearer_token=""
    if [ ! -z "$new_token" ]; then
        bearer_token="Bearer $new_token"
    fi
    
    # 检查配置文件中是否有auth和authorization
    if grep -q "auth:" "$trss_config"; then
        if grep -q "authorization:" "$trss_config"; then
            # 更新已存在的authorization
            if [ -z "$bearer_token" ]; then
                # 如果token为空，则删除authorization行
                sed -i '/authorization:/d' "$trss_config"
                echo -e ${green}已删除authorization配置${background}
            else
                # 更新authorization值
                sed -i "s|authorization: *\".*\"|authorization: \"$bearer_token\"|" "$trss_config"
                echo -e ${green}已更新TRSS-Yunzai配置中的authorization${background}
            fi
        else
            # auth存在但authorization不存在，添加authorization
            if [ ! -z "$bearer_token" ]; then
                sed -i "/auth:/a\\  authorization: \"$bearer_token\"" "$trss_config"
                echo -e ${green}已在auth下添加authorization${background}
            fi
        fi
    else
        # 如果不存在auth部分，且有token需要添加，则添加完整配置
        if [ ! -z "$bearer_token" ] && grep -q "redirect:" "$trss_config"; then
            # 在redirect行后添加auth配置
            sed -i "/redirect:/a\\
# 服务器鉴权\\
auth:\\
  authorization: \"$bearer_token\"" "$trss_config"
            echo -e ${green}已添加auth配置到TRSS-Yunzai配置${background}
        elif [ ! -z "$bearer_token" ]; then
            # 没有找到redirect行，在文件末尾添加
            cat >> "$trss_config" << EOF
# 服务器鉴权
auth:
  authorization: "$bearer_token"
EOF
            echo -e ${green}已添加auth配置到TRSS-Yunzai配置文件末尾${background}
        fi
    fi
    
    # 检查文件中是否有重复的auth条目
    if [ $(grep -c "auth:" "$trss_config") -gt 1 ]; then
        echo -e ${yellow}警告：检测到重复的auth条目，尝试修复...${background}
        # 创建临时文件
        tmp_file=$(mktemp)
        
        # 标记是否已处理第一个auth条目
        processed_first_auth=false
        
        # 逐行读取并处理
        while IFS= read -r line; do
            if [[ "$line" =~ ^auth: ]]; then
                if [ "$processed_first_auth" = false ]; then
                    # 保留第一个auth条目
                    echo "$line" >> "$tmp_file"
                    processed_first_auth=true
                fi
                # 跳过其他auth条目
            else
                echo "$line" >> "$tmp_file"
            fi
        done < "$trss_config"
        
        # 用临时文件替换原文件
        mv "$tmp_file" "$trss_config"
        echo -e ${green}已修复重复的auth条目${background}
    fi
    
    echo -e ${green}TRSS-Yunzai配置已同步更新${background}
    echo -en ${yellow}请记得重启 TRSS-Yunzai 以应用新配置 ${cyan}回车返回${background};read
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
                cp "$selected_config" "${selected_config}.bak"}
                
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

# 管理多开实例
manage_multi_instances() {
    while true; do
        clear
        echo -e ${white}"====="${green}QQ多开实例管理${white}"====="${background}
        
        # 显示当前运行的QQ实例
        echo -e ${yellow}当前运行的QQ实例:${background}
        if ! list_running_instances; then
            echo -e ${red}没有运行中的QQ实例${background}
        fi
        
        echo -e ${yellow}"==========================="${background}
        echo -e ${green}1. ${cyan}启动新的QQ实例${background}
        echo -e ${green}2. ${cyan}启动指定QQ号${background}
        echo -e ${green}3. ${cyan}停止指定QQ实例${background}
        echo -e ${green}4. ${cyan}停止所有QQ实例${background}
        echo -e ${green}5. ${cyan}查看指定QQ实例日志${background}
        echo -e ${green}0. ${cyan}返回主菜单${background}
        echo -e ${yellow}"==========================="${background}
        
        echo -en ${green}请选择操作: ${background};read option
        
        case $option in
            1)
                # 启动新的QQ实例，使用force_start=true强制启动新实例
                start_NapCat true
                ;;
            2)
                # 启动指定QQ号
                # 查找已登录的QQ账号列表
                CONFIG_DIR="/opt/QQ/resources/app/app_launcher/napcat/config"
                if [ ! -d "$CONFIG_DIR" ]; then
                    echo -e ${red}配置目录不存在: ${CONFIG_DIR}${background}
                    echo -e ${yellow}请先使用前台启动方式登录QQ账号${background}
                    echo -en ${cyan}回车返回${background};read
                    continue
                fi
                
                echo -e ${yellow}正在查找已登录的QQ账号...${background}
                account_files=$(find "$CONFIG_DIR" -name "napcat_*.json" 2>/dev/null)
                
                if [ -z "$account_files" ]; then
                    echo -e ${red}未找到已登录的QQ账号${background}
                    echo -e ${yellow}请先使用前台启动方式登录QQ账号${background}
                    echo -en ${cyan}回车返回${background};read
                    continue
                fi
                
                # 提取并显示QQ号码列表
                echo -e ${green}已找到以下QQ账号:${background}
                i=1
                declare -a qq_numbers
                
                while IFS= read -r file; do
                    qq_number=$(basename "$file" | sed -n 's/napcat_\([0-9]*\)\.json/\1/p')
                    if [ -n "$qq_number" ]; then
                        qq_numbers+=("$qq_number")
                        
                        # 检查该QQ号是否已在运行
                        if is_qq_running "$qq_number"; then
                            status="${green}[已启动]"
                        else
                            status="${red}[未启动]"
                        fi
                        
                        echo -e ${green}$i. ${cyan}$qq_number ${status}${background}
                        i=$((i+1))
                    fi
                done <<< "$account_files"
                
                echo -e ${green}0. ${cyan}返回${background}
                echo
                
                # 让用户选择要启动的QQ账号
                echo -en ${yellow}请选择要启动的QQ账号编号: ${background};read choice
                
                if [ "$choice" = "0" ]; then
                    continue
                fi
                
                if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#qq_numbers[@]} ]; then
                    echo -e ${red}无效的选择${background}
                    echo -en ${cyan}回车返回${background};read
                    continue
                fi
                
                selected_qq=${qq_numbers[$((choice-1))]}
                
                # 检查该QQ号是否已在运行
                if is_qq_running "$selected_qq"; then
                    echo -e ${yellow}QQ号 ${cyan}${selected_qq}${yellow} 已经在运行中${background}
                    echo -en ${cyan}回车返回${background};read
                    continue
                fi
                
                # 启动选定的QQ号
                start_NapCat "$selected_qq"
                ;;
            3)
                # 停止指定QQ实例
                # 显示当前运行的QQ实例
                echo -e ${yellow}当前运行的QQ实例:${background}
                if ! list_running_instances; then
                    echo -e ${red}没有运行中的QQ实例${background}
                    echo -en ${cyan}回车返回${background};read
                    continue
                fi
                
                # 创建QQ号数组
                declare -a running_qq
                declare -a running_sessions
                
                # 填充数组并重新显示带编号的列表
                echo -e ${yellow}请选择要停止的QQ实例:${background}
                i=1
                while read -r line; do
                    if [[ "$line" =~ QQ号:\ ([0-9]+).*会话:\ (${TMUX_NAME}_[0-9]+) ]]; then
                        qq_number="${BASH_REMATCH[1]}"
                        session="${BASH_REMATCH[2]}"
                        running_qq+=("$qq_number")
                        running_sessions+=("$session")
                        echo -e ${green}$i. ${cyan}QQ号: $qq_number${background}
                        i=$((i+1))
                    elif [[ "$line" =~ 主实例.*会话:\ (${TMUX_NAME}) ]]; then
                        session="${BASH_REMATCH[1]}"
                        running_qq+=("main")
                        running_sessions+=("$session")
                        echo -e ${green}$i. ${cyan}主实例${background}
                        i=$((i+1))
                    fi
                done < <(list_running_instances)
                
                echo -e ${green}0. ${cyan}返回${background}
                echo
                
                # 让用户选择要停止的QQ实例
                echo -en ${yellow}请选择要停止的QQ实例编号: ${background};read choice
                
                if [ "$choice" = "0" ]; then
                    continue
                fi
                
                if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#running_qq[@]} ]; then
                    echo -e ${red}无效的选择${background}
                    echo -en ${cyan}回车返回${background};read
                    continue
                fi
                
                selected_instance=${running_qq[$((choice-1))]}
                selected_session=${running_sessions[$((choice-1))]}
                
                if [ "$selected_instance" = "main" ]; then
                    # 停止主实例
                    echo -e ${yellow}正在停止主实例...${background}
                    tmux send-keys -t ${selected_session} "Boolean=false" C-m
                    sleep 1
                    tmux kill-session -t ${selected_session}
                    echo -e ${green}主实例已停止${background}
                else
                    # 停止特定QQ号
                    stop_NapCat "$selected_instance"
                fi
                # echo -en ${cyan}回车返回${background};read
                ;;
            4)
                # 停止所有QQ实例
                echo -e ${yellow}是否确认停止所有QQ实例? [y/N]${background};read confirm
                
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    echo -e ${yellow}正在停止所有QQ实例...${background}
                    
                    # 停止主实例（如果存在）
                    if check_running; then
                        tmux send-keys -t ${TMUX_NAME} "Boolean=false" C-m
                        sleep 1
                        tmux kill-session -t ${TMUX_NAME}
                    fi
                    
                    # 停止所有QQ号实例
                    for session in $(tmux list-sessions 2>/dev/null | grep "^${TMUX_NAME}_" | cut -d: -f1); do
                        qq_number=${session#${TMUX_NAME}_}
                        echo -e ${yellow}正在停止QQ号 ${cyan}${qq_number}${yellow}...${background}
                        tmux send-keys -t ${session} "Boolean=false" C-m
                        sleep 1
                        tmux kill-session -t ${session}
                    done
                    
                    echo -e ${green}已停止所有QQ实例${background}
                else
                    echo -e ${yellow}操作已取消${background}
                fi
                
                echo -en ${cyan}回车返回${background};read
                ;;
            5)
                # 查看指定QQ实例日志
                # 显示当前运行的QQ实例
                echo -e ${yellow}当前运行的QQ实例:${background}
                if ! list_running_instances; then
                    echo -e ${red}没有运行中的QQ实例${background}
                    echo -en ${cyan}回车返回${background};read
                    continue
                fi
                
                # 创建会话名数组
                declare -a sessions
                declare -a display_names
                
                # 填充数组
                i=0
                while read -r line; do
                    if [[ "$line" =~ QQ号:\ ([0-9]+).*会话:\ (${TMUX_NAME}_[0-9]+) ]]; then
                        qq_number="${BASH_REMATCH[1]}"
                        session="${BASH_REMATCH[2]}"
                        sessions+=("$session")
                        display_names+=("QQ号: $qq_number")
                        i=$((i+1))
                    elif [[ "$line" =~ 主实例.*会话:\ (${TMUX_NAME}) ]]; then
                        session="${BASH_REMATCH[1]}"
                        sessions+=("$session")
                        display_names+=("主实例")
                        i=$((i+1))
                    fi
                done < <(list_running_instances)
                
                # 打印选项
                for ((j=0; j<${#sessions[@]}; j++)); do
                    echo -e ${green}$((j+1)). ${cyan}${display_names[$j]}${background}
                done
                
                echo -e ${green}0. ${cyan}返回${background}
                echo
                
                # 让用户选择要查看的实例
                echo -en ${yellow}请选择要查看的实例编号: ${background};read choice
                
                if [ "$choice" = "0" ]; then
                    continue
                fi
                
                if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#sessions[@]} ]; then
                    echo -e ${red}无效的选择${background}
                    echo -en ${cyan}回车返回${background};read
                    continue
                fi
                
                selected_session=${sessions[$((choice-1))]}
                
                echo -e ${yellow}正在连接到 ${cyan}${display_names[$((choice-1))]}${yellow} 的界面...${background}
                echo -e ${cyan}提示: 退出请按 Ctrl+B 然后按 D${background}
                echo -en ${cyan}按回车键继续${background};read
                sleep 1
                
                tmux attach-session -t $selected_session
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

# 主菜单
main() {
    if check_installed; then
        if check_running; then
            condition="${green}[已启动]"
        else
            # 检查是否有其他实例运行
            if list_running_instances >/dev/null; then
                condition="${green}[多实例运行中]"
            else
                condition="${red}[未启动]"
            fi
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
    echo -e ${green}10. ${cyan}多开QQ管理${background}
    echo -e ${green}11. ${cyan}配置反向WebSocket${background}
    echo -e ${green}12. ${cyan}音乐签名配置${background}
    echo -e ${green}0.  ${cyan}退出${background}
    echo "========================="
    echo -e ${green}${APP_NAME}状态: ${condition}${background}
    
    # 如果有实例在运行，显示实例信息
    if list_running_instances >/dev/null; then
        echo -e ${green}运行中的实例:${background}
        list_running_instances
        echo "========================="
    fi
    
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
            manage_multi_instances
            ;;
        11)
            echo
            configure_ws
            ;;
        12)
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
