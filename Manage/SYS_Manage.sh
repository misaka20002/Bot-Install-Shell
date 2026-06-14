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
if [ "$(uname -o)" = "Android" ]; then
    echo -e "${red}不支持Android环境${background}"
    exit 1
fi
if [ ! "$(uname)" = "Linux" ]; then
    echo -e "${red}请在Linux系统上运行${background}"
    exit 1
fi
if [ ! "$(id -u)" = "0" ]; then
    echo -e "${red}请使用root用户${background}"
    exit 1
fi

URL="https://ipinfo.io"
Address=$(curl -sL ${URL} | sed -n 's/.*"country": "\(.*\)",.*/\1/p')
if [ "${Address}" = "CN" ]; then
    GitMirror="gitee.com"
    GithubMirror="https://ghfast.top/"
else
    GitMirror="github.com"
    GithubMirror=""
fi

# 按任意键继续函数
pause() {
    echo -en "${yellow}按回车键继续...${background}"
    read
}

# hosts文件管理函数
manage_hosts() {
    hosts_file="/etc/hosts"
    echo -e "${white}=====${green}系统管理-Hosts文件${white}=====${background}"
    echo -e "${green}1.  ${cyan}查看当前hosts文件${background}"
    echo -e "${green}2.  ${cyan}添加hosts条目${background}"
    echo -e "${green}3.  ${cyan}删除hosts条目${background}"
    echo -e "${green}4.  ${cyan}编辑hosts文件${background}"
    echo -e "${green}0.  ${cyan}返回主菜单${background}"
    echo "========================="
    echo -en "${green}请输入您的选项: ${background}";read num
    
    case ${num} in
    1)
        echo -e "${yellow}当前hosts文件内容:${background}"
        cat ${hosts_file}
        echo
        pause
        ;;
    2)
        echo -en "${cyan}请输入IP地址: ${background}";read ip
        echo -en "${cyan}请输入域名: ${background}";read domain
        if [ -z "${ip}" ] || [ -z "${domain}" ]; then
            echo -e "${red}IP或域名不能为空${background}"
        else
            echo "${ip} ${domain}" >> ${hosts_file}
            echo -e "${green}已添加: ${ip} ${domain}${background}"
        fi
        pause
        ;;
    3)
        echo -e "${yellow}当前hosts文件内容:${background}"
        cat -n ${hosts_file}
        echo -en "${cyan}请输入要删除的行号: ${background}";read line_num
        if [[ "${line_num}" =~ ^[0-9]+$ ]]; then
            sed -i "${line_num}d" ${hosts_file}
            echo -e "${green}已删除第 ${line_num} 行${background}"
        else
            echo -e "${red}请输入有效的行号${background}"
        fi
        pause
        ;;
    4)
        if command -v nano >/dev/null 2>&1; then
            nano ${hosts_file}
        elif command -v vim >/dev/null 2>&1; then
            vim ${hosts_file}
        else
            echo -e "${red}未找到编辑器，请安装nano或vim${background}"
        fi
        echo -e "${green}hosts文件已编辑完成${background}"
        pause
        ;;
    0) return ;;
    *) echo -e "${red}输入错误${background}"; pause ;;
    esac
}

# 虚拟内存管理函数
manage_swap() {
    echo -e "${white}=====${green}系统管理-虚拟内存${white}=====${background}"
    echo -e "${green}1.  ${cyan}查看当前虚拟内存状态${background}"
    echo -e "${green}2.  ${cyan}创建新的swap交换分区${background}"
    echo -e "${green}3.  ${cyan}调整swappiness参数${background}"
    echo -e "${green}4.  ${cyan}删除swap交换分区${background}"
    echo -e "${green}0.  ${cyan}返回主菜单${background}"
    echo "========================="
    echo -e "${green}说明: ${cyan}初次使用时建议 创建新的swap交换分区2GB 并 调整swappiness参数为20${background}"
    echo "========================="
    echo -en "${green}请输入您的选项: ${background}";read num
    
    case ${num} in
    1)
        echo -e "${yellow}当前虚拟内存状态:${background}"
        free -h
        echo
        swapon --show
        echo
        echo -e "${yellow}当前swappiness值:${background}"
        cat /proc/sys/vm/swappiness
        pause
        ;;
    2)
        echo -en "${cyan}请输入要创建的swap分区大小(GB) （建议：如果系统内存是 2GB 的话建议设置虚拟内存也为 2GB，输入 2 即可）: ${background}";read swap_size
        if [[ ! "${swap_size}" =~ ^[0-9]+$ ]] || [ ${swap_size} -le 0 ]; then
            echo -e "${red}请输入大于0的有效数字${background}"
            pause
            return
        fi
        
        available_space=$(df -BG --output=avail / | tail -n 1 | tr -d 'G' | tr -d ' ')
        if [ ${swap_size} -gt ${available_space} ]; then
            echo -e "${red}磁盘空间不足，可用空间: ${available_space}GB${background}"
            pause
            return
        fi
        
        if [ ${swap_size} -gt 64 ]; then
            echo -e "${yellow}警告: 创建过大的swap分区可能导致系统不稳定${background}"
            echo -en "${cyan}确定要创建${swap_size}GB的swap分区吗？[y/n]: ${background}";read confirm
            if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
                echo -e "${yellow}已取消创建swap分区${background}"
                pause
                return
            fi
        fi

        swap_file="/swapfile"
        if [ -f "${swap_file}" ]; then
            echo -e "${yellow}已存在swap文件${background}"
            echo -en "${cyan}是否删除现有swap文件并创建新的? [y/n]: ${background}";read confirm
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                if swapon --show | grep -q "/swapfile"; then
                    swapoff /swapfile
                    sed -i '/\/swapfile/d' /etc/fstab
                fi
                rm -f /swapfile
                echo -e "${green}已删除原有swap文件${background}"
            else
                echo -e "${yellow}已取消操作${background}"
                pause
                return
            fi
        fi
        
        echo -e "${yellow}正在创建${swap_size}GB的swap文件，请稍候...${background}"
        
        if command -v fallocate >/dev/null 2>&1; then
            echo -e "${cyan}使用fallocate创建swap文件...${background}"
            if ! fallocate -l ${swap_size}G ${swap_file}; then
                echo -e "${red}创建swap文件失败，尝试使用传统方法...${background}"
                create_swap_traditional=true
            fi
        else
            create_swap_traditional=true
        fi
        
        if [ "$create_swap_traditional" = true ]; then
            echo -e "${cyan}使用dd创建swap文件，这可能需要较长时间...${background}"
            for i in $(seq 1 ${swap_size}); do
                echo -e "${cyan}正在创建第 $i/${swap_size} GB...${background}"
                if ! dd if=/dev/zero of=${swap_file} bs=1G seek=$((i-1)) count=1 status=progress; then
                    echo -e "${red}创建swap文件失败${background}"
                    rm -f ${swap_file}
                    pause
                    return
                fi
            done
        fi
        
        chmod 600 ${swap_file}
        if ! mkswap ${swap_file}; then
            echo -e "${red}格式化swap文件失败${background}"
            rm -f ${swap_file}
            pause
            return
        fi
        
        if ! swapon ${swap_file}; then
            echo -e "${red}激活swap分区失败${background}"
            rm -f ${swap_file}
            pause
            return
        fi
        
        if ! grep -q "${swap_file}" /etc/fstab; then
            echo "${swap_file} none swap sw 0 0" >> /etc/fstab
        fi
        
        echo -e "${green}swap分区创建完成并已激活${background}"
        echo -e "${yellow}当前虚拟内存状态:${background}"
        free -h | grep -i swap
        pause
        ;;
    3)
        echo -e "${yellow}当前swappiness值:${background}"
        current_swappiness=$(cat /proc/sys/vm/swappiness)
        echo "${current_swappiness}"
        echo -e "${cyan}swappiness范围: 0-100${background}"
        echo -e "${cyan}较低的值减少swap使用，较高的值增加swap使用 （建议值为 20） ${background}"
        echo -en "${cyan}请输入新的swappiness值: ${background}";read new_swappiness
        
        if [[ "${new_swappiness}" =~ ^[0-9]+$ ]] && [ ${new_swappiness} -ge 0 ] && [ ${new_swappiness} -le 100 ]; then
            sysctl vm.swappiness=${new_swappiness}
            echo "vm.swappiness=${new_swappiness}" > /etc/sysctl.d/99-swappiness.conf
            echo -e "${green}swappiness已设置为${new_swappiness}${background}"
        else
            echo -e "${red}请输入0-100之间的有效数字${background}"
        fi
        pause
        ;;
    4)
        if swapon --show | grep -q "/swapfile"; then
            swapoff /swapfile
            sed -i '/\/swapfile/d' /etc/fstab
            rm -f /swapfile
            echo -e "${green}swap分区已删除${background}"
        else
            echo -e "${yellow}未找到活动的swap分区${background}"
        fi
        pause
        ;;
    0) return ;;
    *) echo -e "${red}输入错误${background}"; pause ;;
    esac
}

# 安装常用字体函数
install_fonts() {
    fonts_dir="/usr/share/fonts/custom"
    echo -e "${white}=====${green}系统管理-安装字体${white}=====${background}"
    echo -e "${green}1.  ${cyan}查看已安装字体${background}"
    echo -e "${green}2.  ${cyan}安装中文字体包${background}"
    echo -e "${green}3.  ${cyan}安装编程字体${background}"
    echo -e "${green}4.  ${cyan}安装表情符号字体${background}"
    echo -e "${green}5.  ${cyan}刷新字体缓存${background}"
    echo -e "${green}0.  ${cyan}返回主菜单${background}"
    echo "========================="
    echo -en "${green}请输入您的选项: ${background}";read num
    
    case ${num} in
    1)
        echo -e "${yellow}系统已安装字体列表:${background}"
        fc-list : family | sort
        pause
        ;;
    2)
        echo -e "${yellow}正在安装中文字体包...${background}"
        if command -v apt >/dev/null 2>&1; then
            apt update && apt install -y wget unzip fontconfig
        elif command -v yum >/dev/null 2>&1; then
            yum install -y wget unzip fontconfig
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y wget unzip fontconfig
        elif command -v pacman >/dev/null 2>&1; then
            pacman -Sy --noconfirm wget unzip fontconfig
        fi
        
        mkdir -p ${fonts_dir}/chinese
        echo -e "${cyan}正在下载思源黑体...${background}"
        wget -q --show-progress ${GithubMirror}https://github.com/adobe-fonts/source-han-sans/releases/download/2.004R/SourceHanSansSC.zip -O /tmp/SourceHanSansSC.zip
        unzip -q /tmp/SourceHanSansSC.zip -d /tmp/SourceHanSansSC
        cp /tmp/SourceHanSansSC/SubsetOTF/SC/*.otf ${fonts_dir}/chinese/
        rm -rf /tmp/SourceHanSansSC /tmp/SourceHanSansSC.zip
        
        echo -e "${cyan}正在下载文泉驿字体...${background}"
        if command -v apt >/dev/null 2>&1; then
            apt install -y fonts-wqy-microhei fonts-wqy-zenhei
        elif command -v yum >/dev/null 2>&1; then
            yum install -y wqy-microhei-fonts wqy-zenhei-fonts
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y wqy-microhei-fonts wqy-zenhei-fonts
        elif command -v pacman >/dev/null 2>&1; then
            pacman -Sy --noconfirm wqy-microhei wqy-zenhei
        fi
        
        fc-cache -fv
        echo -e "${green}中文字体安装完成并已刷新字体缓存${background}"
        pause
        ;;
    3)
        echo -e "${yellow}正在安装编程字体...${background}"
        if command -v apt >/dev/null 2>&1; then
            apt update && apt install -y wget unzip fontconfig
        elif command -v yum >/dev/null 2>&1; then
            yum install -y wget unzip fontconfig
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y wget unzip fontconfig
        fi
        
        mkdir -p ${fonts_dir}/programming
        echo -e "${cyan}正在下载JetBrains Mono字体...${background}"
        wget -q --show-progress ${GithubMirror}https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip -O /tmp/JetBrainsMono.zip
        unzip -q /tmp/JetBrainsMono.zip -d /tmp/JetBrainsMono
        cp /tmp/JetBrainsMono/fonts/ttf/*.ttf ${fonts_dir}/programming/
        rm -rf /tmp/JetBrainsMono /tmp/JetBrainsMono.zip
        
        echo -e "${cyan}正在下载Fira Code字体...${background}"
        wget -q --show-progress ${GithubMirror}https://github.com/tonsky/FiraCode/releases/download/6.2/Fira_Code_v6.2.zip -O /tmp/FiraCode.zip
        unzip -q /tmp/FiraCode.zip -d /tmp/FiraCode
        cp /tmp/FiraCode/ttf/*.ttf ${fonts_dir}/programming/
        rm -rf /tmp/FiraCode /tmp/FiraCode.zip
        
        fc-cache -fv
        echo -e "${green}编程字体安装完成并已刷新字体缓存${background}"
        pause
        ;;
    4)
        echo -e "${yellow}正在安装表情符号字体...${background}"
        if command -v apt >/dev/null 2>&1; then
            apt update && apt install -y wget fontconfig
        elif command -v yum >/dev/null 2>&1; then
            yum install -y wget fontconfig
        fi
        
        mkdir -p ${fonts_dir}/emoji
        echo -e "${cyan}正在下载Noto Color Emoji字体...${background}"
        wget -q --show-progress ${GithubMirror}https://github.com/googlefonts/noto-emoji/raw/main/fonts/NotoColorEmoji.ttf -O ${fonts_dir}/emoji/NotoColorEmoji.ttf
        
        fc-cache -fv
        echo -e "${green}表情符号字体安装完成并已刷新字体缓存${background}"
        pause
        ;;
    5)
        echo -e "${yellow}正在刷新字体缓存...${background}"
        fc-cache -fv
        echo -e "${green}字体缓存刷新完成${background}"
        pause
        ;;
    0) return ;;
    *) echo -e "${red}输入错误${background}"; pause ;;
    esac
}

# 系统垃圾清理函数
clean_system() {
    echo -e "${white}=====${green}系统管理-清理垃圾${white}=====${background}"
    echo -e "${green}1.  ${cyan}常规清理 (系统日志、Redis日志、系统缓存)${background}"
    echo -e "${green}0.  ${cyan}返回主菜单${background}"
    echo "========================="
    echo -en "${green}请输入您的选项: ${background}";read num

    case ${num} in
    1)
        echo -e "${yellow}正在清理 systemd 日志 (保留最近100M)...${background}"
        journalctl --vacuum-size=100M

        echo -e "${yellow}正在清理暴力登录日志...${background}"
        [ -f /var/log/btmp ] && truncate -s 0 /var/log/btmp
        [ -f /var/log/btmp.1 ] && truncate -s 0 /var/log/btmp.1

        echo -e "${yellow}正在清理认证日志...${background}"
        [ -f /var/log/auth.log ] && truncate -s 0 /var/log/auth.log
        [ -f /var/log/auth.log.1 ] && truncate -s 0 /var/log/auth.log.1
        [ -f /var/log/secure ] && truncate -s 0 /var/log/secure

        echo -e "${yellow}正在清理 redis 日志...${background}"
        [ -f /var/log/redis/redis-server.log ] && truncate -s 0 /var/log/redis/redis-server.log

        echo -e "${yellow}正在清理包管理器缓存...${background}"
        if command -v apt >/dev/null 2>&1; then
            apt autoremove -y && apt clean
        elif command -v yum >/dev/null 2>&1; then
            yum autoremove -y && yum clean all
        elif command -v dnf >/dev/null 2>&1; then
            dnf autoremove -y && dnf clean all
        elif command -v pacman >/dev/null 2>&1; then
            pacman -Scc --noconfirm
        fi

        echo -e "${green}常规清理完成！${background}"
        pause
        ;;
    0) return ;;
    *) echo -e "${red}输入错误${background}"; pause ;;
    esac
}

# 一键开启 BBR 函数
manage_bbr() {
    echo -e "${white}=====${green}系统管理-开启BBR${white}=====${background}"
    echo -e "${yellow}正在检测当前BBR开启状态...${background}"
    
    current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    if [ "$current_cc" = "bbr" ]; then
        echo -e "${green}检测结果：当前系统已成功开启 BBR 加速！${background}"
        lsmod | grep bbr
    else
        echo -e "${yellow}当前系统未开启 BBR，正在为您自动配置并开启...${background}"
        
        if ! grep -q "net.core.default_qdisc" /etc/sysctl.conf; then
            echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        else
            sed -i 's/.*net.core.default_qdisc.*/net.core.default_qdisc=fq/g' /etc/sysctl.conf
        fi

        if ! grep -q "net.ipv4.tcp_congestion_control" /etc/sysctl.conf; then
            echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        else
            sed -i 's/.*net.ipv4.tcp_congestion_control.*/net.ipv4.tcp_congestion_control=bbr/g' /etc/sysctl.conf
        fi
        
        sysctl -p >/dev/null 2>&1
        
        new_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
        if [ "$new_cc" = "bbr" ]; then
            echo -e "${green}恭喜，BBR 开启成功！网络吞吐量已优化。${background}"
            lsmod | grep bbr
        else
            echo -e "${red}BBR 开启失败！请确认您的系统内核版本是否大于等于 4.9 。${background}"
        fi
    fi
    pause
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${yellow}未检测到 Docker，正在为您自动安装...${background}"
        
        echo -e "${red}呆毛注：${yellow}自己去问ai Docker 可用的 registry-mirrors 写入并刷新的指令${background}"
        
        # 尝试使用官方安装脚本（加入 10 秒超时限制，使用 Aliyun 镜像）
        if curl -fsSL --connect-timeout 10 https://get.docker.com -o get-docker.sh; then
            echo -e "${yellow}成功获取官方安装脚本，正在使用 Aliyun 镜像源进行安装...${background}"
            sh get-docker.sh --mirror Aliyun
        else
            echo -e "${red}官方源连接失败，正在尝试使用系统包管理器进行基础安装...${background}"
            # 备用方案：直接使用 apt 或 yum 安装系统默认的 docker
            if command -v apt-get &> /dev/null; then
                apt-get update -y && apt-get install -y docker.io
            elif command -v yum &> /dev/null; then
                yum install -y docker
            fi
        fi
        # 尝试设置开机自启并启动 Docker
        systemctl enable docker >/dev/null 2>&1
        systemctl start docker >/dev/null 2>&1
        # 严格的最终检查
        if ! command -v docker &> /dev/null; then
            echo -e "${red}====================================================${background}"
            echo -e "${red}严重错误: Docker 软件安装失败！${background}"
            echo -e "${red}原因: 您的服务器基础网络存在问题，无法下载安装包。${background}"
            echo -e "${red}建议: 1. 检查 DNS 配置 (修改 /etc/resolv.conf) ${background}"
            echo -e "${red}      2. 手动执行安装后再运行本脚本。${background}"
            echo -e "${red}====================================================${background}"
            return 1 # 返回上一层菜单而不是直接退出整个环境
        fi
        echo -e "${green}Docker 软件安装并启动成功！${background}"
    else
        # 如果已经安装了，确保服务是启动状态
        echo -e "${green}检测到已安装 Docker，正在确保服务启动...${background}"
        systemctl enable docker >/dev/null 2>&1
        systemctl start docker >/dev/null 2>&1
        echo -e "${green}Docker 服务当前运行正常！${background}"
    fi
}

# Sing-box 管理函数
manage_singbox() {
    CONF_DIR="/etc/sing-box"
    CONF_FILE="${CONF_DIR}/config.json"
    INFO_FILE="${CONF_DIR}/info.txt"
    CERT_FILE="${CONF_DIR}/cert.pem"
    KEY_FILE="${CONF_DIR}/private.key"

    # 获取节点角色信息 (从 info.txt 中提取)
    ROLE_INFO=""
    if [ -f "${INFO_FILE}" ]; then
        # 截取 "节点角色 : 服务端 (Server)" 后半部分
        ROLE_INFO=$(grep "节点角色" "${INFO_FILE}" | awk -F ' : ' '{print $2}')
    fi
    ROLE_DISPLAY=""
    if [ -n "$ROLE_INFO" ]; then
        ROLE_DISPLAY="[${ROLE_INFO}]"
    fi

    # 获取 docker 容器运行状态 (屏蔽报错输出)
    STATUS_CHECK=$(docker inspect -f '{{.State.Running}}' sing-box 2>/dev/null)
    MEM_USAGE="0.00MB"
    
    if [ "$STATUS_CHECK" == "true" ]; then
        SINGBOX_STATUS="${green}▶ 运行中${ROLE_DISPLAY}${background}"
        # 获取当前内存占用
        MEM_USAGE=$(docker stats --no-stream --format "{{.MemUsage}}" sing-box 2>/dev/null | awk '{print $1}')
    elif [ "$STATUS_CHECK" == "false" ]; then
        SINGBOX_STATUS="${red}■ 已停止${ROLE_DISPLAY}${background}"
    else
        SINGBOX_STATUS="${yellow}● 未安装${background}"
    fi

    echo -e "${white}=====${green}系统管理-Sing-box (Hysteria2)${white}=====${background}"
    echo -e "${green}1.  ${cyan}部署 服务端 (远程节点 / 接收外网访问)${background}"
    echo -e "${green}2.  ${cyan}部署 客户端 (本地设备 / 连接到服务端)${background}"
    echo -e "${green}3.  ${cyan}启动 Sing-box${background}"
    echo -e "${green}4.  ${cyan}停止 Sing-box${background}"
    echo -e "${green}5.  ${cyan}重启 Sing-box${background}"
    echo -e "${green}6.  ${cyan}查看连接信息及使用帮助${background}"
    echo -e "${green}7.  ${cyan}卸载 Sing-box${background}"
    echo -e "${green}0.  ${cyan}返回主菜单${background}"
    echo "========================="
    echo -e "  当前状态: ${SINGBOX_STATUS}"
    if [ "$STATUS_CHECK" == "true" ]; then
        echo -e "  内存占用: ${cyan}${MEM_USAGE}${background}"
    fi
    echo "========================="
    echo -en "${green}请输入您的选项: ${background}";read num

    case ${num} in
    1)
        check_docker
        
        if [ -f "${CONF_FILE}" ]; then
            echo -en "${yellow}检测到已存在配置文件，继续将覆盖原有配置！是否继续？[y/N]: ${background}"
            read overwrite
            if [[ "$overwrite" != "y" && "$overwrite" != "Y" ]]; then
                manage_singbox
                return
            fi
        fi

        echo -e "${purple}=== 配置 Hysteria2 服务端 ===${background}"
        echo -en "${cyan}请输入监听端口 (Hysteria2使用UDP, 默认 50846): ${background}"
        read PORT
        PORT=${PORT:-50846}

        RANDOM_PASS=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
        echo -en "${cyan}请输入密码 (默认随机生成: ${RANDOM_PASS}): ${background}"
        read PASSWORD
        PASSWORD=${PASSWORD:-$RANDOM_PASS}

        mkdir -p ${CONF_DIR}

        # Hysteria2 必须使用 TLS，这里自动生成自签名证书
        echo -e "${yellow}正在生成自签名 TLS 证书...${background}"
        openssl ecparam -genkey -name prime256v1 -out ${KEY_FILE}
        openssl req -new -x509 -days 36500 -key ${KEY_FILE} -out ${CERT_FILE} -subj "/CN=bing.com" >/dev/null 2>&1

        # 写入 服务端 config.json
        cat > ${CONF_FILE} << EOF
{
  "log": { "disabled": false, "level": "info", "timestamp": true },
  "inbounds":[
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": ${PORT},
      "users":[ { "password": "${PASSWORD}" } ],
      "tls": {
        "enabled": true,
        "certificate_path": "/etc/sing-box/cert.pem",
        "key_path": "/etc/sing-box/private.key"
      }
    }
  ],
  "outbounds": [ { "type": "direct", "tag": "direct" } ]
}
EOF
        
        PUBLIC_IP=$(curl -sL ipinfo.io/ip)
        cat > ${INFO_FILE} << EOF
======================================
      Sing-box Hysteria2 [服务端]     
======================================
节点角色 : 服务端 (Server)
服务器IP : ${PUBLIC_IP}
代理端口 : ${PORT} (UDP协议)
认证密码 : ${PASSWORD}
======================================
【连接帮助】: 
1. 服务端已就绪，请务必在防火墙/安全组放行 ${PORT} 的 UDP 端口！
2. 请在您的“本地设备(客户端)”上运行此脚本，选择 [选项2. 部署客户端]
3. 填入上方的 IP、端口 和 密码 即可建立连接。
4. 呆毛注：强烈建议设置 UDP:${PORT} 的 ip地址白名单
======================================
EOF
        start_singbox_docker "服务端"
        ;;
    2)
        check_docker

        if [ -f "${CONF_FILE}" ]; then
            echo -en "${yellow}检测到已存在配置文件，继续将覆盖原有配置！是否继续？[y/N]: ${background}"
            read overwrite
            if [[ "$overwrite" != "y" && "$overwrite" != "Y" ]]; then
                manage_singbox
                return
            fi
        fi

        echo -e "${purple}=== 配置 Hysteria2 客户端 ===${background}"
        echo -en "${cyan}请输入服务端(远程节点)的 IP 地址: ${background}"
        read SERVER_IP
        echo -en "${cyan}请输入服务端(远程节点)的 端口: ${background}"
        read SERVER_PORT
        echo -en "${cyan}请输入服务端(远程节点)的 密码: ${background}"
        read PASSWORD
        
        echo -en "${cyan}请设置本地局域网提供的 Mixed(HTTP/Socks5) 代理端口 (默认 2080): ${background}"
        read LOCAL_PORT
        LOCAL_PORT=${LOCAL_PORT:-2080}

        mkdir -p ${CONF_DIR}

        # 写入 客户端 config.json
        cat > ${CONF_FILE} << EOF
{
  "log": { "disabled": false, "level": "info", "timestamp": true },
  "inbounds":[
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "0.0.0.0",
      "listen_port": ${LOCAL_PORT}
    }
  ],
  "outbounds":[
    {
      "type": "hysteria2",
      "tag": "hy2-out",
      "server": "${SERVER_IP}",
      "server_port": ${SERVER_PORT},
      "password": "${PASSWORD}",
      "tls": {
        "enabled": true,
        "server_name": "bing.com",
        "insecure": true
      }
    }
  ]
}
EOF
        
        cat > ${INFO_FILE} << EOF
======================================
      Sing-box Hysteria2 [客户端]     
======================================
节点角色 : 客户端 (Client)
连接目标 : ${SERVER_IP}:${SERVER_PORT}
本地端口 : ${LOCAL_PORT} (HTTP/Socks5)
======================================
【使用帮助】: 
本地客户端已启动。您现在可以让本地的其他软件或设备，
通过 HTTP 或 Socks5 代理连接到本机:
代理地址: 127.0.0.1 (或本机的局域网IP)
代理端口: ${LOCAL_PORT}
流量将通过 Hysteria2 加密传输至服务端。
======================================
EOF
        start_singbox_docker "客户端"
        ;;
    3)
        if [ "$STATUS_CHECK" == "true" ]; then
            echo -e "${yellow}Sing-box 已经在运行中，无需重复启动。${background}"
        elif [ "$STATUS_CHECK" == "false" ]; then
            docker start sing-box
            echo -e "${green}Sing-box 容器已启动。${background}"
        else
            echo -e "${red}未找到 Sing-box 容器，请先部署。${background}"
        fi
        pause
        manage_singbox 
        ;;
    4)
        if [ "$STATUS_CHECK" == "false" ]; then
            echo -e "${yellow}Sing-box 已经是停止状态。${background}"
        elif [ "$STATUS_CHECK" == "true" ]; then
            docker stop sing-box
            echo -e "${green}Sing-box 容器已停止。${background}"
        else
            echo -e "${red}未找到 Sing-box 容器。${background}"
        fi
        pause
        manage_singbox
        ;;
    5)
        if [ "$STATUS_CHECK" == "" ]; then
            echo -e "${red}未找到 Sing-box 容器，请先部署。${background}"
        else
            echo -e "${yellow}正在重启 Sing-box...${background}"
            docker restart sing-box
            echo -e "${green}Sing-box 容器已重启。${background}"
        fi
        pause
        manage_singbox
        ;;
    6)
        if [ -f "${INFO_FILE}" ]; then
            cat "${INFO_FILE}"
        else
            echo -e "${red}未找到配置信息，请确认是否已安装。${background}"
        fi
        pause
        manage_singbox
        ;;
    7)
        echo -en "${yellow}确定要卸载 Sing-box 及其配置文件吗？[y/N]: ${background}"
        read rm_confirm
        if [[ "$rm_confirm" == "y" || "$rm_confirm" == "Y" ]]; then
            docker rm -f sing-box >/dev/null 2>&1
            rm -rf ${CONF_DIR}
            echo -e "${green}Sing-box 已完全卸载。${background}"
        else
            echo -e "${green}已取消卸载操作。${background}"
        fi
        pause
        manage_singbox
        ;;
    0) return ;;
    *) echo -e "${red}输入错误${background}"; pause; manage_singbox ;;
    esac
}

# 辅助函数：用于统一启动 Docker
start_singbox_docker() {
    local ROLE=$1
    echo -e "${yellow}正在拉取最新官方 Sing-box 镜像...${background}"
    docker pull ghcr.io/sagernet/sing-box:latest

    echo -e "${yellow}正在配置并启动容器...${background}"
    docker rm -f sing-box >/dev/null 2>&1
    
    docker run -d \
        --name sing-box \
        --restart unless-stopped \
        --network host \
        -v ${CONF_DIR}:/etc/sing-box \
        ghcr.io/sagernet/sing-box:latest run -c /etc/sing-box/config.json

    echo -e "${green}Sing-box Hysteria2 ${ROLE} 部署并启动完成！${background}"
    cat ${INFO_FILE}
    pause
    manage_singbox
}

# Hapi / Claude Code 管理辅助函数
HAPI_HUB_TMUX_NAME="hapi_hub"
HAPI_SELECTED_WORKSPACES=()
HAPI_HUB_URL=""

hapi_load_node_env() {
    if [ -d "/usr/local/node/bin" ]; then
        PATH="${PATH}:/usr/local/node/bin"
    fi
    if [ ! -d "${HOME}/.local/share/pnpm" ]; then
        mkdir -p "${HOME}/.local/share/pnpm"
    fi
    PATH="${PATH}:${HOME}/.local/share/pnpm:/root/.local/share/pnpm"
    PNPM_HOME="${HOME}/.local/share/pnpm"
    export PATH PNPM_HOME
    hash -r 2>/dev/null
}

hapi_ensure_pnpm() {
    hapi_load_node_env
    if command -v pnpm >/dev/null 2>&1; then
        return 0
    fi

    if command -v npm >/dev/null 2>&1; then
        echo -e "${yellow}未检测到 pnpm，正在使用 npm 安装 pnpm...${background}"
        npm install -g pnpm@latest
        hapi_load_node_env
    fi

    if ! command -v pnpm >/dev/null 2>&1; then
        echo -e "${red}未检测到 pnpm/npm，请先安装 Node.js 环境。${background}"
        return 1
    fi
}

hapi_ensure_command() {
    hapi_load_node_env
    if ! command -v hapi >/dev/null 2>&1; then
        echo -e "${red}未检测到 hapi 命令，请先安装/更新 Hapi。${background}"
        return 1
    fi
}

hapi_ensure_tmux() {
    if command -v tmux >/dev/null 2>&1; then
        return 0
    fi

    echo -e "${yellow}未检测到 tmux，正在尝试自动安装...${background}"
    if command -v apt >/dev/null 2>&1; then
        apt update && apt install -y tmux
    elif command -v apt-get >/dev/null 2>&1; then
        apt-get update -y && apt-get install -y tmux
    elif command -v yum >/dev/null 2>&1; then
        yum install -y tmux
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y tmux
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Sy --noconfirm --needed tmux
    fi

    if ! command -v tmux >/dev/null 2>&1; then
        echo -e "${red}tmux 安装失败，请手动安装后重试。${background}"
        return 1
    fi
}

hapi_json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

hapi_install_claude_code() {
    hapi_ensure_pnpm || return
    echo -e "${yellow}正在安装/更新 Claude Code...${background}"
    pnpm add -g @anthropic-ai/claude-code --allow-build=@anthropic-ai/claude-code
    if command -v claude >/dev/null 2>&1; then
        claude --version
    fi
}

hapi_install_hapi() {
    hapi_ensure_pnpm || return
    echo -e "${yellow}正在安装/更新 Hapi...${background}"
    pnpm add -g @twsxtd/hapi
    if command -v hapi >/dev/null 2>&1; then
        hapi --version
    fi
}

hapi_show_claude_config() {
    local settings_file="${1:-${HOME}/.claude/settings.json}"

    echo -e "${white}=====${green}当前 Claude Code 配置${white}=====${background}"
    if [ ! -f "${settings_file}" ]; then
        echo -e "${yellow}未找到配置文件: ${settings_file}${background}"
        return 1
    fi

    sed -E 's#("(ANTHROPIC_AUTH_TOKEN|ANTHROPIC_API_KEY|CLAUDE_CODE_OAUTH_TOKEN)"[[:space:]]*:[[:space:]]*")[^"]*#\1******#g' "${settings_file}"
}

hapi_write_claude_settings_file() {
    local output_file="$1"
    local auth_token base_url haiku_model sonnet_model opus_model enable_max_effort
    local reasoning_suffix effort_line
    local auth_token_json base_url_json haiku_json sonnet_json opus_json
    local default_haiku_model="claude-haiku-4-5-20251001"
    local default_sonnet_model="claude-sonnet-4-5-20250929"
    local default_opus_model="claude-opus-4-8[1M]"

    while [ -z "${auth_token}" ]; do
        echo -en "${cyan}请输入 ANTHROPIC_AUTH_TOKEN（已隐藏输入）: ${background}"
        read -rs auth_token
        echo
        if [ -z "${auth_token}" ]; then
            echo -e "${red}ANTHROPIC_AUTH_TOKEN 不能为空。${background}"
        fi
    done

    echo -en "${cyan}请输入 ANTHROPIC_BASE_URL (默认 https://api.deepseek.com/anthropic): ${background}"
        read -r base_url
    base_url=${base_url:-https://api.deepseek.com/anthropic}

    echo -e "${yellow}如需开启 [1m] 或 [1M] 上下文，请自行在模型名后添加。${background}"
    echo -e "${yellow}示例: claude-opus-4-8[1M] 或 claude-opus-4-8[1m]${background}"

    echo -en "${cyan}请输入 HAIKU_MODEL (默认 ${default_haiku_model}): ${background}"
    read -r haiku_model
    haiku_model=${haiku_model:-${default_haiku_model}}

    echo -en "${cyan}请输入 SONNET_MODEL (默认 ${default_sonnet_model}): ${background}"
    read -r sonnet_model
    sonnet_model=${sonnet_model:-${default_sonnet_model}}

    echo -en "${cyan}请输入 OPUS_MODEL (默认 ${default_opus_model}): ${background}"
    read -r opus_model
    opus_model=${opus_model:-${default_opus_model}}

    echo -en "${cyan}是否开启最大强度思考？[y/N]: ${background}"
    read -r enable_max_effort
    reasoning_suffix=""
    effort_line=""
    if [[ "${enable_max_effort}" == "y" || "${enable_max_effort}" == "Y" ]]; then
        reasoning_suffix=","
        effort_line='    "CLAUDE_CODE_EFFORT_LEVEL": "max"'
    fi

    auth_token_json=$(hapi_json_escape "${auth_token}")
    base_url_json=$(hapi_json_escape "${base_url}")
    haiku_json=$(hapi_json_escape "${haiku_model}")
    sonnet_json=$(hapi_json_escape "${sonnet_model}")
    opus_json=$(hapi_json_escape "${opus_model}")

    cat > "${output_file}" << EOF
{
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "${auth_token_json}",
    "ANTHROPIC_BASE_URL": "${base_url_json}",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "${haiku_json}",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "${opus_json}",
    "ANTHROPIC_DEFAULT_OPUS_MODEL_NAME": "${opus_json}",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "${sonnet_json}",
    "ANTHROPIC_DEFAULT_SONNET_MODEL_NAME": "${sonnet_json}",
    "ANTHROPIC_MODEL": "${sonnet_json}",
    "ANTHROPIC_REASONING_MODEL": "${opus_json}"${reasoning_suffix}
${effort_line}
  },
  "includeCoAuthoredBy": false
}
EOF
}

hapi_config_claude() {
    local config_dir="${HOME}/.claude"
    local settings_file="${config_dir}/settings.json"
    local backup_file

    hapi_show_claude_config "${settings_file}" || true

    if [ -f "${settings_file}" ]; then
        echo -en "${yellow}检测到已存在 Claude Code 配置，继续将覆盖原有配置！是否继续？[y/N]: ${background}"
        read -r overwrite
        if [[ "${overwrite}" != "y" && "${overwrite}" != "Y" ]]; then
            echo -e "${yellow}已取消配置。${background}"
            return
        fi
        backup_file="${settings_file}.bak"
        cp -a "${settings_file}" "${backup_file}"
        echo -e "${green}已备份原配置到: ${backup_file}${background}"
    fi

    mkdir -p "${config_dir}"
    hapi_write_claude_settings_file "${settings_file}" || return
    chmod 600 "${settings_file}"
    echo -e "${green}Claude Code 配置已写入: ${settings_file}${background}"
}

hapi_ensure_node_json() {
    if ! command -v node >/dev/null 2>&1; then
        echo -e "${red}未检测到 node，无法管理 Claude 配置库。${background}"
        return 1
    fi
}

hapi_claude_profile_store_file() {
    printf '%s' "${HOME}/.claude/hapi_config_profiles.json"
}

hapi_save_claude_profile_from_file() {
    local profile_name="$1"
    local source_file="$2"
    local store_file
    store_file=$(hapi_claude_profile_store_file)

    hapi_ensure_node_json || return
    mkdir -p "$(dirname "${store_file}")"
    node -e 'const fs = require("fs"); const path = require("path"); const storeFile = process.argv[1]; const name = process.argv[2]; const sourceFile = process.argv[3]; const config = JSON.parse(fs.readFileSync(sourceFile, "utf8")); let store = { profiles: [] }; if (fs.existsSync(storeFile)) { try { store = JSON.parse(fs.readFileSync(storeFile, "utf8")); } catch {} } if (!Array.isArray(store.profiles)) store.profiles = []; const now = new Date().toISOString(); const idx = store.profiles.findIndex((item) => item && item.name === name); if (idx >= 0) { store.profiles[idx] = { ...store.profiles[idx], name, updatedAt: now, config }; } else { store.profiles.push({ name, createdAt: now, updatedAt: now, config }); } fs.mkdirSync(path.dirname(storeFile), { recursive: true }); fs.writeFileSync(storeFile, JSON.stringify(store, null, 2) + "\n");' "${store_file}" "${profile_name}" "${source_file}" || return
    chmod 600 "${store_file}" 2>/dev/null
    echo -e "${green}配置已保存到配置库: ${profile_name}${background}"
}

hapi_list_claude_profiles() {
    local store_file
    store_file=$(hapi_claude_profile_store_file)

    hapi_ensure_node_json || return
    if [ ! -f "${store_file}" ]; then
        echo -e "${yellow}暂无已储存的 Claude Code 配置。${background}"
        return 1
    fi
    node -e 'const fs = require("fs"); const storeFile = process.argv[1]; let store = { profiles: [] }; try { store = JSON.parse(fs.readFileSync(storeFile, "utf8")); } catch {} const profiles = Array.isArray(store.profiles) ? store.profiles : []; if (profiles.length === 0) process.exit(1); profiles.forEach((item, index) => { console.log(`${index + 1}. ${item.name}    更新: ${item.updatedAt || "-"}`); });' "${store_file}" || {
        echo -e "${yellow}暂无已储存的 Claude Code 配置。${background}"
        return 1
    }
}

hapi_show_claude_profile_by_index() {
    local profile_index="$1"
    local store_file
    store_file=$(hapi_claude_profile_store_file)

    hapi_ensure_node_json || return
    node -e 'const fs = require("fs"); const storeFile = process.argv[1]; const index = Number(process.argv[2]) - 1; const store = JSON.parse(fs.readFileSync(storeFile, "utf8")); const profiles = Array.isArray(store.profiles) ? store.profiles : []; const profile = profiles[index]; if (!profile || !profile.config) { console.error("配置序号不存在"); process.exit(1); } const config = JSON.parse(JSON.stringify(profile.config)); if (config.env) { for (const key of ["ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_API_KEY", "CLAUDE_CODE_OAUTH_TOKEN"]) { if (config.env[key]) config.env[key] = "******"; } } console.log(`名称: ${profile.name}`); console.log(JSON.stringify(config, null, 2));' "${store_file}" "${profile_index}"
}

hapi_store_current_claude_config() {
    local settings_file="${HOME}/.claude/settings.json"
    local profile_name

    if [ ! -f "${settings_file}" ]; then
        echo -e "${yellow}当前没有 Claude Code 配置可储存: ${settings_file}${background}"
        return 1
    fi
    echo -en "${cyan}请输入配置名称: ${background}"
    read -r profile_name
    if [ -z "${profile_name}" ]; then
        echo -e "${red}配置名称不能为空。${background}"
        return 1
    fi
    hapi_save_claude_profile_from_file "${profile_name}" "${settings_file}"
}

hapi_create_claude_profile() {
    local profile_name tmp_file

    echo -en "${cyan}请输入新配置名称: ${background}"
    read -r profile_name
    if [ -z "${profile_name}" ]; then
        echo -e "${red}配置名称不能为空。${background}"
        return 1
    fi

    tmp_file="${TMPDIR:-/tmp}/hapi_claude_settings_$$.json"
    if ! hapi_write_claude_settings_file "${tmp_file}"; then
        rm -f "${tmp_file}"
        return 1
    fi
    if ! hapi_save_claude_profile_from_file "${profile_name}" "${tmp_file}"; then
        rm -f "${tmp_file}"
        return 1
    fi
    rm -f "${tmp_file}"
    echo -e "${yellow}新配置已保存，但未切换当前 Claude Code 配置。${background}"
}

hapi_switch_claude_profile() {
    local store_file settings_file config_dir backup_file num confirm
    store_file=$(hapi_claude_profile_store_file)
    config_dir="${HOME}/.claude"
    settings_file="${config_dir}/settings.json"

    hapi_list_claude_profiles || return
    echo -en "${green}请输入要切换的配置序号: ${background}"
    read -r num
    if [[ ! "${num}" =~ ^[0-9]+$ ]] || [ "${num}" -lt 1 ]; then
        echo -e "${red}请输入有效的序号。${background}"
        return 1
    fi

    echo -e "${white}=====${green}即将切换到以下配置${white}=====${background}"
    hapi_show_claude_profile_by_index "${num}" || return
    echo -en "${yellow}确认切换到该配置吗？[y/N]: ${background}"
    read -r confirm
    if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
        echo -e "${yellow}已取消切换。${background}"
        return
    fi

    mkdir -p "${config_dir}"
    if [ -f "${settings_file}" ]; then
        backup_file="${settings_file}.bak"
        cp -a "${settings_file}" "${backup_file}"
        echo -e "${green}已备份原配置到: ${backup_file}${background}"
    fi
    hapi_ensure_node_json || return
    node -e 'const fs = require("fs"); const storeFile = process.argv[1]; const settingsFile = process.argv[2]; const index = Number(process.argv[3]) - 1; const store = JSON.parse(fs.readFileSync(storeFile, "utf8")); const profiles = Array.isArray(store.profiles) ? store.profiles : []; if (!profiles[index] || !profiles[index].config) { console.error("配置序号不存在"); process.exit(1); } fs.writeFileSync(settingsFile, JSON.stringify(profiles[index].config, null, 2) + "\n"); console.log(profiles[index].name);' "${store_file}" "${settings_file}" "${num}"
    local switch_status=$?
    if [ "${switch_status}" -ne 0 ]; then
        echo -e "${red}切换配置失败。${background}"
        return "${switch_status}"
    fi
    chmod 600 "${settings_file}"
    echo -e "${green}Claude Code 配置已切换: ${settings_file}${background}"
}

hapi_delete_claude_profile() {
    local store_file num confirm
    store_file=$(hapi_claude_profile_store_file)

    hapi_list_claude_profiles || return
    echo -en "${green}请输入要删除的配置序号: ${background}"
    read -r num
    if [[ ! "${num}" =~ ^[0-9]+$ ]] || [ "${num}" -lt 1 ]; then
        echo -e "${red}请输入有效的序号。${background}"
        return 1
    fi

    echo -e "${white}=====${green}即将删除以下配置${white}=====${background}"
    hapi_show_claude_profile_by_index "${num}" || return
    echo -en "${yellow}确认删除该配置吗？[y/N]: ${background}"
    read -r confirm
    if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
        echo -e "${yellow}已取消删除。${background}"
        return
    fi

    hapi_ensure_node_json || return
    node -e 'const fs = require("fs"); const storeFile = process.argv[1]; const index = Number(process.argv[2]) - 1; const store = JSON.parse(fs.readFileSync(storeFile, "utf8")); const profiles = Array.isArray(store.profiles) ? store.profiles : []; if (!profiles[index]) { console.error("配置序号不存在"); process.exit(1); } const removed = profiles.splice(index, 1)[0]; store.profiles = profiles; fs.writeFileSync(storeFile, JSON.stringify(store, null, 2) + "\n"); console.log(removed.name);' "${store_file}" "${num}"
    local delete_status=$?
    if [ "${delete_status}" -ne 0 ]; then
        echo -e "${red}删除配置失败。${background}"
        return "${delete_status}"
    fi
    chmod 600 "${store_file}" 2>/dev/null
    echo -e "${green}配置已删除。${background}"
}

hapi_claude_config_menu() {
    local num

    while true; do
        echo -e "${white}=====${green}Claude Code 配置${white}=====${background}"
        echo -e "${green}1.  ${cyan}查看/修改配置${background}"
        echo -e "${green}2.  ${cyan}储存当前配置${background}"
        echo -e "${green}3.  ${cyan}新建配置（不切换）${background}"
        echo -e "${green}4.  ${cyan}切换配置${background}"
        echo -e "${green}5.  ${cyan}删除配置${background}"
        echo -e "${green}0.  ${cyan}返回上一级${background}"
        echo "========================="
        echo -en "${green}请输入您的选项: ${background}"; read -r num

        case "${num}" in
        1) hapi_config_claude; pause ;;
        2) hapi_store_current_claude_config; pause ;;
        3) hapi_create_claude_profile; pause ;;
        4) hapi_switch_claude_profile; pause ;;
        5) hapi_delete_claude_profile; pause ;;
        0) return ;;
        *) echo -e "${red}输入错误${background}"; pause ;;
        esac
    done
}

hapi_prepare_workspace() {
    local workspace_root="$1"
    case "${workspace_root}" in
        "~")
            workspace_root="${HOME}"
            ;;
        "~/"*)
            workspace_root="${HOME}/${workspace_root#~/}"
            ;;
    esac

    if [ ! -d "${workspace_root}" ]; then
        echo -en "${yellow}目录不存在: ${workspace_root}，是否创建？[Y/n]: ${background}"
        read -r create_workspace
        if [[ "${create_workspace}" == "n" || "${create_workspace}" == "N" ]]; then
            echo -e "${yellow}已取消添加目录。${background}"
            return 1
        fi
        if ! mkdir -p "${workspace_root}"; then
            echo -e "${red}目录创建失败: ${workspace_root}${background}"
            return 1
        fi
        echo -e "${green}已创建目录: ${workspace_root}${background}"
    fi

    if [ ! -d "${workspace_root}" ]; then
        echo -e "${red}workspace-root 不是有效目录: ${workspace_root}${background}"
        return 1
    fi

    local existing_workspace
    for existing_workspace in "${HAPI_SELECTED_WORKSPACES[@]}"; do
        if [ "${existing_workspace}" = "${workspace_root}" ]; then
            echo -e "${yellow}目录已在列表中: ${workspace_root}${background}"
            return 0
        fi
    done

    HAPI_SELECTED_WORKSPACES+=("${workspace_root}")
    echo -e "${green}已添加工作目录: ${workspace_root}${background}"
}

hapi_select_workspaces() {
    local num custom_path
    HAPI_SELECTED_WORKSPACES=()

    while true; do
        echo -e "${white}=====${green}设置 Hapi 工作目录${white}=====${background}"
        if [ "${#HAPI_SELECTED_WORKSPACES[@]}" -gt 0 ]; then
            echo -e "${yellow}已选择:${background}"
            printf '  - %s\n' "${HAPI_SELECTED_WORKSPACES[@]}"
        fi
        echo -e "${green}1.  ${cyan}添加 ${HOME}/TRSS-Yunzai${background}"
        echo -e "${green}2.  ${cyan}添加 ${HOME}/AstrBot${background}"
        echo -e "${green}3.  ${cyan}添加 ${HOME}/myrepo${background}"
        echo -e "${green}4.  ${cyan}添加自定义目录${background}"
        echo -e "${green}5.  ${cyan}开始设置${background}"
        echo -e "${green}0.  ${cyan}取消${background}"
        echo "========================="
        echo -en "${green}请输入您的选项: ${background}"; read -r num

        case "${num}" in
        1) hapi_prepare_workspace "${HOME}/TRSS-Yunzai" ;;
        2) hapi_prepare_workspace "${HOME}/AstrBot" ;;
        3) hapi_prepare_workspace "${HOME}/myrepo" ;;
        4)
            echo -en "${cyan}请输入 workspace-root 路径: ${background}"
            read -r custom_path
            if [ -z "${custom_path}" ]; then
                echo -e "${red}workspace-root 不能为空。${background}"
                continue
            fi
            hapi_prepare_workspace "${custom_path}"
            ;;
        5)
            if [ "${#HAPI_SELECTED_WORKSPACES[@]}" -eq 0 ]; then
                echo -e "${red}请至少添加一个工作目录。${background}"
                continue
            fi
            return 0
            ;;
        0) return 1 ;;
        *) echo -e "${red}输入错误${background}" ;;
        esac
    done
}

hapi_start_runner() {
    local runner_args=()
    local workspace_root

    hapi_ensure_command || return
    echo -e "${yellow}提示1：Hapi runner 是全局单实例，新设置会覆盖当前 runner 的 workspace-root。${background}"
    echo -e "${yellow}提示2：Hapi runner 用于从聊天窗口远程创建 session。如果不启动 Runner，你仍然可以管理已有 session，但不能方便地让 HAPI 在指定机器上新建任务。${background}"
    hapi_select_workspaces || return

    for workspace_root in "${HAPI_SELECTED_WORKSPACES[@]}"; do
        runner_args+=(--workspace-root "${workspace_root}")
    done

    echo -e "${yellow}正在设置/运行 Hapi 工作目录:${background}"
    printf '  - %s\n' "${HAPI_SELECTED_WORKSPACES[@]}"
    hapi runner start "${runner_args[@]}"
}

hapi_runner_workspace_menu() {
    local num

    while true; do
        echo -e "${white}=====${green}Hapi runner 工作目录${white}=====${background}"
        echo -e "${green}1.  ${cyan}设置/运行 Hapi runner 工作目录${background}"
        echo -e "${green}2.  ${cyan}查看 Hapi runner 状态${background}"
        echo -e "${green}0.  ${cyan}返回上一级${background}"
        echo "========================="
        echo -en "${green}请输入您的选项: ${background}"; read -r num

        case "${num}" in
        1) hapi_start_runner; pause ;;
        2) if hapi_ensure_command; then hapi runner status; fi; pause ;;
        0) return ;;
        *) echo -e "${red}输入错误${background}"; pause ;;
        esac
    done
}

hapi_capture_hub_url() {
    local hub_output cli_token
    HAPI_HUB_URL=""
    if ! tmux has-session -t "${HAPI_HUB_TMUX_NAME}" 2>/dev/null; then
        return 1
    fi
    hub_output=$(tmux capture-pane -pt "${HAPI_HUB_TMUX_NAME}" -S -200 2>/dev/null)
    HAPI_HUB_URL=$(printf '%s\n' "${hub_output}" | grep -Eo 'https://app\.hapi\.run/[^[:space:]]*' | tail -n 1)
    if [[ "${HAPI_HUB_URL}" == *"token=" ]]; then
        cli_token=$(hapi_read_setting "cliApiToken" "")
        if [ -n "${cli_token}" ]; then
            HAPI_HUB_URL="${HAPI_HUB_URL}${cli_token}"
        fi
    fi
    [ -n "${HAPI_HUB_URL}" ]
}

hapi_show_hub_url() {
    if hapi_capture_hub_url; then
        echo -e "${red}重要：以下 URL 包含访问 token，不要发送给其他人！${background}"
        echo -e "${red}${HAPI_HUB_URL}${background}"
    else
        echo -e "${yellow}暂未提取到 Hapi Hub URL，请稍后重试或查看 tmux 日志。${background}"
        return 1
    fi
}

hapi_start_hub() {
    hapi_ensure_command || return
    hapi_ensure_tmux || return

    if tmux has-session -t "${HAPI_HUB_TMUX_NAME}" 2>/dev/null; then
        echo -e "${green}Hapi Hub 已在后台运行。${background}"
        if hapi_show_hub_url; then
            return
        fi
        echo -e "${yellow}现有 Hapi Hub 未提取到 URL，准备重启后重试。${background}"
        tmux kill-session -t "${HAPI_HUB_TMUX_NAME}" >/dev/null 2>&1
    fi

    local attempt wait_count
    attempt=1
    while [ "${attempt}" -le 3 ]; do
        echo -e "${yellow}正在启动 Hapi Hub (第 ${attempt}/3 次)...${background}"
        tmux kill-session -t "${HAPI_HUB_TMUX_NAME}" >/dev/null 2>&1
        if ! tmux new-session -d -s "${HAPI_HUB_TMUX_NAME}" "export PATH=\"${PATH}\"; export PNPM_HOME=\"${PNPM_HOME}\"; hapi hub --relay"; then
            echo -e "${red}Hapi Hub tmux 会话创建失败。${background}"
            return 1
        fi

        wait_count=0
        while [ "${wait_count}" -lt 20 ]; do
            sleep 1
            if hapi_capture_hub_url; then
                hapi_show_hub_url
                echo -e "${green}Hapi Hub 已在 tmux 会话 ${HAPI_HUB_TMUX_NAME} 中后台运行。${background}"
                return 0
            fi
            wait_count=$((wait_count + 1))
        done

        echo -e "${yellow}本次未提取到 Hapi Hub URL，正在重启重试...${background}"
        tmux kill-session -t "${HAPI_HUB_TMUX_NAME}" >/dev/null 2>&1
        attempt=$((attempt + 1))
    done

    echo -e "${red}连续 3 次未提取到 Hapi Hub URL，请稍后重新选择“启动/查看 Hapi hub URL”或检查 tmux 日志。${background}"
}

hapi_stop_all() {
    hapi_load_node_env
    if command -v tmux >/dev/null 2>&1 && tmux has-session -t "${HAPI_HUB_TMUX_NAME}" 2>/dev/null; then
        tmux kill-session -t "${HAPI_HUB_TMUX_NAME}" >/dev/null 2>&1
        echo -e "${green}已停止 Hapi Hub tmux 会话。${background}"
    else
        echo -e "${yellow}未检测到正在运行的 Hapi Hub tmux 会话。${background}"
    fi

    if command -v hapi >/dev/null 2>&1; then
        echo -e "${yellow}正在执行 hapi doctor clean 清理 runner 与相关进程...${background}"
        hapi doctor clean
    else
        echo -e "${yellow}未检测到 hapi 命令，跳过 runner 清理。${background}"
    fi
}

hapi_read_setting() {
    local key="$1"
    local default_value="$2"
    local settings_file="${HOME}/.hapi/settings.json"
    local value

    if [ -f "${settings_file}" ] && command -v node >/dev/null 2>&1; then
        value=$(node -e 'const fs = require("fs"); const file = process.argv[1]; const key = process.argv[2]; try { const data = JSON.parse(fs.readFileSync(file, "utf8")); const value = data[key]; if (value !== undefined && value !== null && value !== "") process.stdout.write(String(value)); } catch {}' "${settings_file}" "${key}" 2>/dev/null)
    fi

    if [ -n "${value}" ]; then
        printf '%s' "${value}"
    else
        printf '%s' "${default_value}"
    fi
}

hapi_check_listen_host() {
    local listen_host
    listen_host=$(hapi_read_setting "listenHost" "127.0.0.1")

    if [ "${listen_host}" = "0.0.0.0" ]; then
        # echo -e "${green}检查通过：listenHost -> 0.0.0.0${background}"
        echo -en ""
    else
        echo -e "${green}当前 listenHost -> ${listen_host}，Docker 或局域网访问前建议设置为 0.0.0.0。${background}"
    fi
}

hapi_set_listen_config() {
    local settings_dir="${HOME}/.hapi"
    local settings_file="${settings_dir}/settings.json"
    local current_host current_port listen_host listen_port backup_file

    if ! command -v node >/dev/null 2>&1; then
        echo -e "${red}未检测到 node，无法安全写入 Hapi JSON 配置。${background}"
        return 1
    fi

    current_host=$(hapi_read_setting "listenHost" "127.0.0.1")
    current_port=$(hapi_read_setting "listenPort" "3006")
    echo -e "${white}=====${green}设置 Hapi listenHost / listenPort${white}=====${background}"
    echo -e "${yellow}当前 listenHost: ${current_host}${background}"
    echo -e "${yellow}当前 listenPort: ${current_port}${background}"
    echo -en "${cyan}请输入 listenHost (默认 ${current_host}，Docker/局域网建议 0.0.0.0): ${background}"
    read -r listen_host
    listen_host=${listen_host:-${current_host}}
    echo -en "${cyan}请输入 listenPort (默认 ${current_port}): ${background}"
    read -r listen_port
    listen_port=${listen_port:-${current_port}}

    if [ -z "${listen_host}" ]; then
        echo -e "${red}listenHost 不能为空。${background}"
        return 1
    fi
    if [[ ! "${listen_port}" =~ ^[0-9]+$ ]] || [ "${listen_port}" -lt 1 ] || [ "${listen_port}" -gt 65535 ]; then
        echo -e "${red}listenPort 必须是 1-65535 之间的数字。${background}"
        return 1
    fi

    mkdir -p "${settings_dir}"
    if [ -f "${settings_file}" ]; then
        backup_file="${settings_file}.bak"
        cp -a "${settings_file}" "${backup_file}"
        echo -e "${green}已备份原配置到: ${backup_file}${background}"
    fi
    if ! node -e 'const fs = require("fs"); const path = require("path"); const file = process.argv[1]; const host = process.argv[2]; const port = Number(process.argv[3]); let data = {}; if (fs.existsSync(file)) { try { data = JSON.parse(fs.readFileSync(file, "utf8")); } catch {} } data.listenHost = host; data.listenPort = port; fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, JSON.stringify(data, null, 2) + "\n");' "${settings_file}" "${listen_host}" "${listen_port}"; then
        echo -e "${red}Hapi 配置写入失败: ${settings_file}${background}"
        return 1
    fi
    chmod 600 "${settings_file}" 2>/dev/null
    echo -e "${green}已写入 Hapi 配置: ${settings_file}${background}"
    hapi_check_listen_host
    echo -e "${yellow}如果 Hapi Hub 正在运行，请重启 Hub 后让配置生效。${background}"
}

hapi_show_cli_api_token() {
    local settings_file="${HOME}/.hapi/settings.json"
    local token

    echo -e "${white}=====${green}Hapi cliApiToken${white}=====${background}"
    if [ ! -f "${settings_file}" ]; then
        echo -e "${yellow}未找到 Hapi 配置文件: ${settings_file}${background}"
        return 1
    fi

    if command -v node >/dev/null 2>&1; then
        token=$(node -e 'const fs = require("fs"); const file = process.argv[1]; const data = JSON.parse(fs.readFileSync(file, "utf8")); if (data.cliApiToken) process.stdout.write(data.cliApiToken);' "${settings_file}" 2>/dev/null)
    fi
    if [ -z "${token}" ]; then
        token=$(sed -nE 's/^[[:space:]]*"cliApiToken"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' "${settings_file}" | head -n 1)
    fi

    if [ -z "${token}" ]; then
        echo -e "${yellow}未在 ${settings_file} 中读取到 cliApiToken。${background}"
        return 1
    fi

    echo -e "${red}重要：cliApiToken 是敏感凭据，不要发送给其他人！${background}"
    echo -e "${red}${token}${background}"
}

hapi_set_cli_api_token() {
    local settings_dir="${HOME}/.hapi"
    local settings_file="${settings_dir}/settings.json"
    local token backup_file

    if ! command -v node >/dev/null 2>&1; then
        echo -e "${red}未检测到 node，无法安全写入 Hapi JSON 配置。${background}"
        return 1
    fi

    echo -en "${cyan}请输入新的 cliApiToken: ${background}"
    read -rs token
    echo
    if [ -z "${token}" ]; then
        echo -e "${red}cliApiToken 不能为空。${background}"
        return 1
    fi

    mkdir -p "${settings_dir}"
    if [ -f "${settings_file}" ]; then
        backup_file="${settings_file}.bak"
        cp -a "${settings_file}" "${backup_file}"
        echo -e "${green}已备份原配置到: ${backup_file}${background}"
    fi
    if ! node -e 'const fs = require("fs"); const path = require("path"); const file = process.argv[1]; const token = process.argv[2]; let data = {}; if (fs.existsSync(file)) { try { data = JSON.parse(fs.readFileSync(file, "utf8")); } catch {} } data.cliApiToken = token; fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, JSON.stringify(data, null, 2) + "\n");' "${settings_file}" "${token}"; then
        echo -e "${red}cliApiToken 写入失败: ${settings_file}${background}"
        return 1
    fi
    chmod 600 "${settings_file}" 2>/dev/null
    echo -e "${green}cliApiToken 已写入: ${settings_file}${background}"
}

hapi_manage_cli_api_token() {
    local confirm

    hapi_show_cli_api_token || true
    echo -en "${yellow}是否设置/更新 cliApiToken？[y/N]: ${background}"
    read -r confirm
    if [[ "${confirm}" == "y" || "${confirm}" == "Y" ]]; then
        hapi_set_cli_api_token
    else
        echo -e "${yellow}未修改 cliApiToken。${background}"
    fi
}

hapi_show_astrbot_plugin_config() {
    local listen_host listen_port token

    listen_host=$(hapi_read_setting "listenHost" "127.0.0.1")
    listen_port=$(hapi_read_setting "listenPort" "3006")
    token=$(hapi_read_setting "cliApiToken" "")

    echo -e "${white}=====${green}AstrBot 插件配置${white}=====${background}"
    echo -e "${yellow}当前 Hapi listenHost: ${listen_host}${background}"
    echo -e "${yellow}当前 Hapi listenPort: ${listen_port}${background}"
    echo -e "${green}在 AstrBot 管理面板的插件配置页填写以下必填字段:${background}"
    echo -e "${cyan}hapi_endpoint:${background}"
    echo -e "  同一宿主机（非 Docker）: http://localhost:${listen_port}"
    echo -e "  AstrBot/TRSS Docker（Linux 宿主机默认）: http://172.17.0.1:${listen_port}"
    echo -e "  AstrBot/TRSS Docker（Windows/macOS 宿主机）: http://host.docker.internal:${listen_port}"
    echo -e "  同一内网 / Tailscale: http://<HAPI机器IP>:${listen_port}"
    echo -e "  公共中继 / 自建隧道: 使用 Hub URL 或你的域名"
    echo -e "${cyan}access_token:${background}"
    if [ -n "${token}" ]; then
        echo -e "  ${red}${token}${background}"
    else
        echo -e "  ${yellow}未读取到 cliApiToken，请先启动 Hapi Hub 生成 ~/.hapi/settings.json。${background}"
    fi

    echo -e "${yellow}如果 AstrBot 是 Docker 启动，本脚本所在 Linux 宿主机通常填写: http://172.17.0.1:${listen_port}${background}"
    echo -e "${yellow}Docker 场景必须先让 Hapi 监听所有网卡，即 listenHost -> 0.0.0.0。${background}"
    hapi_check_listen_host
}

hapi_attach_tmux() {
    hapi_ensure_tmux || return

    if ! tmux has-session -t "${HAPI_HUB_TMUX_NAME}" 2>/dev/null; then
        echo -e "${yellow}未检测到正在运行的 Hapi Hub tmux 会话: ${HAPI_HUB_TMUX_NAME}${background}"
        return 1
    fi

    echo -e "${yellow}即将打开 tmux 会话 ${HAPI_HUB_TMUX_NAME}。${background}"
    echo -e "${yellow}返回菜单请按 ctrl+b d。${background}"
    echo -en "${green}按回车键进入 tmux...${background}"
    read -r
    tmux attach-session -t "${HAPI_HUB_TMUX_NAME}"
}

hapi_restart_hub() {
    hapi_ensure_command || return
    hapi_ensure_tmux || return

    if tmux has-session -t "${HAPI_HUB_TMUX_NAME}" 2>/dev/null; then
        tmux kill-session -t "${HAPI_HUB_TMUX_NAME}" >/dev/null 2>&1
        echo -e "${green}已停止现有 Hapi Hub tmux 会话。${background}"
    else
        echo -e "${yellow}未检测到正在运行的 Hapi Hub tmux 会话，将直接启动。${background}"
    fi
    hapi_start_hub
}

hapi_hub_menu() {
    local num

    while true; do
        echo -e "${white}=====${green}Hapi hub${white}=====${background}"
        echo -e "${green}1.  ${cyan}启动/查看 Hapi hub URL${background}"
        echo -e "${green}2.  ${cyan}重启 Hapi hub${background}"
        echo -e "${green}3.  ${cyan}打开当前的 tmux${background}"
        echo -e "${green}0.  ${cyan}返回上一级${background}"
        echo "========================="
        echo -en "${green}请输入您的选项: ${background}"; read -r num

        case "${num}" in
        1) hapi_start_hub; pause ;;
        2) hapi_restart_hub; pause ;;
        3) hapi_attach_tmux; pause ;;
        0) return ;;
        *) echo -e "${red}输入错误${background}"; pause ;;
        esac
    done
}

hapi_show_versions() {
    hapi_load_node_env
    echo -e "${white}=====${green}Hapi / Claude Code 版本${white}=====${background}"
    if command -v claude >/dev/null 2>&1; then
        claude --version
    else
        echo -e "${yellow}未检测到 claude 命令。${background}"
    fi
    if command -v hapi >/dev/null 2>&1; then
        hapi --version
    else
        echo -e "${yellow}未检测到 hapi 命令。${background}"
    fi
}

hapi_uninstall() {
    local num confirm remove_status target_label stop_hapi
    local uninstall_packages=()

    hapi_show_versions
    echo -e "${white}=====${green}选择卸载目标${white}=====${background}"
    echo -e "${green}1.  ${cyan}卸载 Claude Code${background}"
    echo -e "${green}2.  ${cyan}卸载 Hapi${background}"
    echo -e "${green}3.  ${cyan}卸载 Claude Code 和 Hapi${background}"
    echo -e "${green}0.  ${cyan}取消${background}"
    echo "========================="
    echo -en "${green}请输入您的选项: ${background}"; read -r num

    case "${num}" in
    1)
        target_label="Claude Code"
        uninstall_packages=("@anthropic-ai/claude-code")
        stop_hapi="false"
        ;;
    2)
        target_label="Hapi"
        uninstall_packages=("@twsxtd/hapi")
        stop_hapi="true"
        ;;
    3)
        target_label="Claude Code 和 Hapi"
        uninstall_packages=("@anthropic-ai/claude-code" "@twsxtd/hapi")
        stop_hapi="true"
        ;;
    0)
        echo -e "${yellow}已取消卸载。${background}"
        return
        ;;
    *)
        echo -e "${red}输入错误${background}"
        return 1
        ;;
    esac

    echo -e "${yellow}卸载将移除全局安装的 ${target_label}，不会删除 ~/.claude 或 ~/.hapi 配置目录。${background}"
    echo -en "${yellow}确定要卸载 ${target_label} 吗？[y/N]: ${background}"
    read -r confirm
    if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
        echo -e "${yellow}已取消卸载。${background}"
        return
    fi

    if [ "${stop_hapi}" = "true" ]; then
        hapi_stop_all
    fi
    hapi_load_node_env
    if command -v pnpm >/dev/null 2>&1; then
        echo -e "${yellow}正在卸载 ${target_label}...${background}"
        pnpm remove -g "${uninstall_packages[@]}"
        remove_status=$?
    elif command -v npm >/dev/null 2>&1; then
        echo -e "${yellow}未检测到 pnpm，正在尝试使用 npm 卸载...${background}"
        npm uninstall -g "${uninstall_packages[@]}"
        remove_status=$?
    else
        echo -e "${red}未检测到 pnpm/npm，无法自动卸载。${background}"
        return 1
    fi

    if [ "${remove_status}" -eq 0 ]; then
        echo -e "${green}${target_label} 卸载完成。${background}"
    else
        echo -e "${red}卸载命令执行失败，请检查上方输出。${background}"
        return "${remove_status}"
    fi
}

hapi_config_menu() {
    local num

    while true; do
        echo -e "${white}=====${green}设置 Hapi 配置${white}=====${background}"
        echo -e "${green}1.  ${cyan}设置 listenHost 和端口号${background}"
        echo -e "${green}2.  ${cyan}查看/设置 cliApiToken${background}"
        echo -e "${green}3.  ${cyan}（额外） hapi_connector 插件配置帮助${background}"
        echo -e "${green}0.  ${cyan}返回上一级${background}"
        echo "========================="
        echo -en "${green}请输入您的选项: ${background}"; read -r num

        case "${num}" in
        1) hapi_set_listen_config; pause ;;
        2) hapi_manage_cli_api_token; pause ;;
        3) hapi_show_astrbot_plugin_config; pause ;;
        0) return ;;
        *) echo -e "${red}输入错误${background}"; pause ;;
        esac
    done
}

manage_hapi() {
    echo -e "${white}=====${green}系统管理-Hapi / Claude Code${white}=====${background}"
    echo -e "${green}1.  ${cyan}安装/更新 Claude Code${background}"
    echo -e "${green}2.  ${cyan}配置 Claude Code${background}"
    echo -e "${green}3.  ${cyan}安装/更新 Hapi${background}"
    echo -e "${green}4.  ${cyan}设置/运行 Hapi runner 工作目录${background}"
    echo -e "${green}5.  ${cyan}设置 Hapi CLI${background}"
    echo -e "${green}6.  ${cyan}运行 Hapi hub${background}"
    echo -e "${green}7.  ${cyan}停止 Hapi${background}"
    echo -e "${green}8.  ${cyan}卸载${background}"
    echo -e "${green}0.  ${cyan}返回主菜单${background}"
    echo "========================="
    echo -en "${green}请输入您的选项: ${background}"; read -r num

    case "${num}" in
    1) hapi_install_claude_code; pause; manage_hapi ;;
    2) hapi_claude_config_menu; manage_hapi ;;
    3) hapi_install_hapi; pause; manage_hapi ;;
    4) hapi_runner_workspace_menu; manage_hapi ;;
    5) hapi_config_menu; manage_hapi ;;
    6) hapi_hub_menu; manage_hapi ;;
    7) hapi_stop_all; pause; manage_hapi ;;
    8) hapi_uninstall; pause; manage_hapi ;;
    0) return ;;
    *) echo -e "${red}输入错误${background}"; pause; manage_hapi ;;
    esac
}

# 自动加载 Clash 环境变量辅助函数， 修复在非交互式脚本中“未检测到 clashctl”的问题
load_clash_env() {
    # 如果已经识别到命令，则直接返回
    if command -v clashctl >/dev/null 2>&1; then return 0; fi

    # 开启 alias 扩展，防止 clashctl 被定义为纯别名而无法解析
    shopt -s expand_aliases 2>/dev/null

    # 尝试从 ~/.bashrc 中提取加载语句并执行
    if [ -f ~/.bashrc ]; then
        local env_cmd
        env_cmd=$(grep -E '(source|\.) .*clashctl\.sh' ~/.bashrc | tail -n 1)
        if [ -n "$env_cmd" ]; then
            eval "$env_cmd" >/dev/null 2>&1
        fi
    fi

    # 如果依旧识别不到，尝试硬编码查找默认安装目录并强制加载
    if ! command -v clashctl >/dev/null 2>&1; then
        local p
        for p in /opt/clash /opt/clashctl ~/.local/share/clash ~/clashctl /usr/local/clash; do
            # 兼容旧版本路径结构
            if [ -f "$p/script/clashctl.sh" ]; then
                source "$p/script/common.sh" >/dev/null 2>&1
                source "$p/script/clashctl.sh" >/dev/null 2>&1
                break
            # 兼容新版本路径结构
            elif [ -f "$p/scripts/cmd/clashctl.sh" ]; then
                source "$p/scripts/core/common.sh" >/dev/null 2>&1
                source "$p/scripts/cmd/clashctl.sh" >/dev/null 2>&1
                break
            fi
        done
    fi
}
# Clash for Linux 管理函数
manage_clash() {
    # 每次进入菜单前，尝试自动加载环境
    load_clash_env

    echo -e "${white}=====${green}系统管理-Clash for Linux${white}=====${background}"
    if command -v clashctl >/dev/null 2>&1; then
        # --- 检测运行状态与模式 ---
        local proxy_status="${red}● 已关闭${background}"
        local mode_status="${yellow}未运行${background}"
        
        # 使用 systemctl 检测 mihomo 或 clash 服务进程是否在活跃状态
        if systemctl is-active --quiet mihomo 2>/dev/null || systemctl is-active --quiet clash 2>/dev/null; then
            proxy_status="${green}▶ 已开启${background}"
            
            # 进程开启时，判断当前是 Tun 模式还是系统代理模式
            # 通常 mihomo 内核在开启 Tun 模式时，会创建一个名为 Meta 的虚拟网卡（或 utun / clash）
            if ip link show 2>/dev/null | grep -iE "meta|utun|clash" >/dev/null 2>&1; then
                mode_status="${green}Tun 模式 (全局虚拟网卡)${background}"
            else
                mode_status="${cyan}系统代理模式 (环境变量)${background}"
            fi
        fi

        echo -e "  安装状态: ${green}已安装${background}"
        echo -e "  运行状态: ${proxy_status}"
        echo -e "  当前模式: ${mode_status}"
        echo -e "  ${yellow}CLI指令: clashctl${background}"
    else
        echo -e "  当前状态: ${yellow}未安装 或 环境变量未生效${background}"
    fi
    echo "========================="
    echo -e  "${green}1.  ${cyan}一键安装 / 更新 Clash 环境${background}"
    echo -e  "${green}2.  ${cyan}开启代理 (clashon)${background}"
    echo -e  "${green}3.  ${cyan}关闭代理 (clashoff)${background}"
    echo -e  "${green}4.  ${cyan}查看状况与升级 (status/upgrade)${background}"
    echo -e  "${green}5.  ${cyan}Web控制面板与密钥 (ui/secret)${background}"
    echo -e  "${green}6.  ${cyan}订阅管理 (sub)${background}"
    echo -e  "${green}7.  ${cyan}Tun模式管理 (tun)${background}"
    echo -e  "${green}8.  ${cyan}Mixin配置管理 (mixin)${background}"
    echo -e  "${green}9.  ${cyan}完全卸载${background}"
    echo -e  "${green}0.  ${cyan}返回主菜单${background}"
    echo "========================="
    echo -en "${green}请输入您的选项: ${background}"; read num

    case ${num} in
    1)
        echo -e "${yellow}正在准备安装 Clash for Linux...${background}"
        if ! command -v git >/dev/null 2>&1; then
            echo -e "${yellow}未检测到 git，尝试自动安装...${background}"
            if command -v apt >/dev/null 2>&1; then apt update && apt install -y git;
            elif command -v yum >/dev/null 2>&1; then yum install -y git;
            elif command -v dnf >/dev/null 2>&1; then dnf install -y git;
            elif command -v pacman >/dev/null 2>&1; then pacman -Sy --noconfirm git;
            fi
        fi
        
        cd $HOME
        rm -rf clash-for-linux-install
        if git clone --branch master --depth 1 https://gh-proxy.org/https://github.com/nelvko/clash-for-linux-install.git; then
            cd clash-for-linux-install
            bash install.sh
            cd $HOME
            
            # 安装后立刻加载环境变量，无需退出即可继续使用菜单
            load_clash_env

            echo -e "${green}======================================${background}"
            echo -e "${green}安装流程结束！${background}"
            echo -e "${yellow}提示：脚本已尝试自动加载环境。如后续功能仍提示'命令未找到'，请退出本脚本执行 ${cyan}source ~/.bashrc${yellow} 即可生效。${background}"
            echo -e "${green}======================================${background}"
        else
            echo -e "${red}克隆仓库失败，请检查网络或加速链接可用性。${background}"
            cd $HOME
        fi
        pause; manage_clash ;;
    2)
        if command -v clashctl >/dev/null 2>&1; then clashctl on; else echo -e "${red}未检测到 clashctl 命令，请先安装或重新加载环境变量。${background}"; fi
        pause; manage_clash ;;
    3)
        if command -v clashctl >/dev/null 2>&1; then clashctl off; else echo -e "${red}未检测到 clashctl 命令。${background}"; fi
        pause; manage_clash ;;
    4)
        if command -v clashctl >/dev/null 2>&1; then 
            echo -e "${white}==== 状态与内核 ====${background}"
            clashctl status
            echo "-------------------------"
            echo -en "${cyan}是否请求内核升级更新？[y/N]: ${background}"; read up_ans
            if [[ "$up_ans" == "y" || "$up_ans" == "Y" ]]; then
                clashctl upgrade
            fi
        else 
            echo -e "${red}未检测到 clashctl 命令。${background}"
        fi
        pause; manage_clash ;;
    5)
        if command -v clashctl >/dev/null 2>&1; then 
            clashctl ui
            echo "-------------------------"
            echo -en "${cyan}是否需要修改 Web 访问密钥？[y/N]: ${background}"; read set_sec
            if [[ "$set_sec" == "y" || "$set_sec" == "Y" ]]; then
                echo -en "${cyan}请输入新密钥: ${background}"; read new_sec
                if [ -n "$new_sec" ]; then
                    clashctl secret "$new_sec"
                fi
            else
                clashctl secret
            fi
        else 
            echo -e "${red}未检测到 clashctl 命令。${background}"
        fi
        pause; manage_clash ;;
    6)
        if command -v clashctl >/dev/null 2>&1; then 
            echo -e "${white}==== 订阅管理 ====${background}"
            echo -e "  [1] 查看当前订阅 (ls)"
            echo -e "  [2] 添加新订阅 (add)"
            echo -e "  [3] 更新所有订阅 (update)"
            echo -e "  [4] 切换使用订阅 (use)"
            echo -e "  [5] 删除指定订阅 (del)"
            echo -e "  [6] 查看订阅日志 (log)"
            echo -e "  [0] 取消并返回"
            echo "-------------------------"
            echo -en "${cyan}请选择操作: ${background}"; read sub_num
            case $sub_num in
                1) clashctl sub ls ;;
                2) 
                   echo -en "${cyan}请输入订阅链接 (建议用双引号包裹): ${background}"
                   read sub_url
                   if [ -n "$sub_url" ]; then clashctl sub add "$sub_url"; fi
                   ;;
                3) clashctl sub update ;;
                4)
                   clashctl sub ls
                   echo -en "${cyan}请输入要使用的订阅 ID: ${background}"
                   read sub_id
                   if [ -n "$sub_id" ]; then clashctl sub use "$sub_id"; fi
                   ;;
                5)
                   clashctl sub ls
                   echo -en "${cyan}请输入要删除的订阅 ID: ${background}"
                   read del_id
                   if [ -n "$del_id" ]; then clashctl sub del "$del_id"; fi
                   ;;
                6) clashctl sub log ;;
                0) ;;
                *) echo -e "${red}输入错误${background}" ;;
            esac
        else 
            echo -e "${red}未检测到 clashctl 命令。${background}"
        fi
        pause; manage_clash ;;
    7)
        if command -v clashctl >/dev/null 2>&1; then 
            clashctl tun
            echo "-------------------------"
            echo -en "${cyan}要改变Tun模式状态吗？[on 开启 / off 关闭 / 0 退出]: ${background}"; read tun_op
            if [[ "$tun_op" == "on" || "$tun_op" == "off" ]]; then
                clashctl tun "$tun_op"
                # --- 添加提示用户已自动重启开启代理 ---
                echo -e "\n${yellow}================ 提示 =================${background}"
                echo -e "${green}✔ Tun 模式已成功切换！${background}"
                echo -e "${yellow}=======================================${background}"
            fi
        else 
            echo -e "${red}未检测到 clashctl 命令。${background}"
        fi
        pause; manage_clash ;;
    8)
        if command -v clashctl >/dev/null 2>&1; then 
            echo -e "${white}==== Mixin配置管理 ====${background}"
            echo -e "  [1] 查看 Mixin 配置"
            echo -e "  [2] 编辑 Mixin 配置 (-e)"
            echo -e "  [3] 查看原始订阅配置 (-c)"
            echo -e "  [4] 查看运行时配置 (-r)"
            echo -e "  [0] 取消并返回"
            echo "-------------------------"
            echo -en "${cyan}请选择操作: ${background}"; read mix_num
            case $mix_num in
                1) clashctl mixin ;;
                2) clashctl mixin -e ;;
                3) clashctl mixin -c ;;
                4) clashctl mixin -r ;;
                0) ;;
                *) echo -e "${red}输入错误${background}" ;;
            esac
        else 
            echo -e "${red}未检测到 clashctl 命令。${background}"
        fi
        pause; manage_clash ;;
    9)
        echo -en "${yellow}确定要完全卸载 Clash for Linux 吗？[y/N]: ${background}"; read rm_clash
        if [[ "$rm_clash" == "y" || "$rm_clash" == "Y" ]]; then
            if [ -f "$HOME/clash-for-linux-install/uninstall.sh" ]; then
                cd $HOME/clash-for-linux-install && bash uninstall.sh
                cd $HOME
            else
                echo -e "${yellow}本地找不到卸载脚本，正在重新拉取...${background}"
                cd $HOME
                git clone --branch master --depth 1 https://gh-proxy.org/https://github.com/nelvko/clash-for-linux-install.git
                cd clash-for-linux-install && bash uninstall.sh
                cd $HOME
            fi
            # 卸载后从当前脚本进程中取消相关函数的定义，防止面板误判“已安装”
            unset -f clashctl 2>/dev/null
        fi
        pause; manage_clash ;;
    0) return ;;
    *) echo -e "${red}输入错误${background}"; pause; manage_clash ;;
    esac
}

# 主菜单函数
main() {
    local system_info
    local memory_info
    system_info="$(uname -s) $(uname -r) $(uname -m)"
    memory_info="$(free -h | grep Mem | awk '{print $3"/"$2" 使用"}')"

    echo
    echo -e "${white}=====${green}呆毛版-系统管理${white}=====${background}"
    echo -e "${green}1.  ${cyan}Hosts文件管理${background}"
    echo -e "${green}2.  ${cyan}虚拟内存管理${background}"
    echo -e "${green}3.  ${cyan}安装常用字体${background}"
    echo -e "${green}4.  ${cyan}清理系统垃圾${background}"
    echo -e "${green}5.  ${cyan}开启BBR网络加速${background}"
    echo -e "${green}6.  ${cyan}Sing-box正向代理${background}"
    echo -e "${green}7.  ${cyan}安装docker代理${background}"
    echo -e "${green}8.  ${cyan}Clash CLI${background}"
    echo -e "${green}9.  ${cyan}Hapi / Claude Code${background}"
    echo -e "${green}0.  ${cyan}退出${background}"
    echo "========================="
    echo -e "${green}系统信息: ${system_info}${background}"
    echo -e "${green}内存状态: ${memory_info}${background}"
    echo -e "${green}QQ群: ${cyan}呆毛版-QQ群:1022982073${background}"
    echo "========================="
    echo -en "${green}请输入您的选项: ${background}";read number
    echo
    case ${number} in
    1) manage_hosts ;;
    2) manage_swap ;;
    3) install_fonts ;;
    4) clean_system ;;
    5) manage_bbr ;;
    6) manage_singbox ;;
    7) check_docker ;;
    8) manage_clash ;;
    9) manage_hapi ;;
    0) exit 0 ;;
    *) echo -e "\n${red}输入错误${background}"; pause ;;
    esac
}

# 主循环函数
function mainloop() {
    while true
    do
        main
    done
}

# 启动主循环
mainloop
