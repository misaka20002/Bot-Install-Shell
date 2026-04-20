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
    echo -e "${red}请在Linux系统上运行${background}"
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
    echo -e ${white}"====="${green}系统管理-Hosts文件${white}"====="${background}
    echo -e  ${green}1.  ${cyan}查看当前hosts文件${background}
    echo -e  ${green}2.  ${cyan}添加hosts条目${background}
    echo -e  ${green}3.  ${cyan}删除hosts条目${background}
    echo -e  ${green}4.  ${cyan}编辑hosts文件${background}
    echo -e  ${green}0.  ${cyan}返回主菜单${background}
    echo "========================="
    echo -en ${green}请输入您的选项: ${background};read num
    
    case ${num} in
    1)
        echo -e ${yellow}当前hosts文件内容:${background}
        cat ${hosts_file}
        echo
        pause
        ;;
    2)
        echo -en ${cyan}请输入IP地址: ${background};read ip
        echo -en ${cyan}请输入域名: ${background};read domain
        if [ -z "${ip}" ] || [ -z "${domain}" ]; then
            echo -e ${red}IP或域名不能为空${background}
        else
            echo "${ip} ${domain}" >> ${hosts_file}
            echo -e ${green}已添加: ${ip} ${domain}${background}
        fi
        pause
        ;;
    3)
        echo -e ${yellow}当前hosts文件内容:${background}
        cat -n ${hosts_file}
        echo -en ${cyan}请输入要删除的行号: ${background};read line_num
        if [[ "${line_num}" =~ ^[0-9]+$ ]]; then
            sed -i "${line_num}d" ${hosts_file}
            echo -e ${green}已删除第 ${line_num} 行${background}
        else
            echo -e ${red}请输入有效的行号${background}
        fi
        pause
        ;;
    4)
        if command -v nano >/dev/null 2>&1; then
            nano ${hosts_file}
        elif command -v vim >/dev/null 2>&1; then
            vim ${hosts_file}
        else
            echo -e ${red}未找到编辑器，请安装nano或vim${background}
        fi
        echo -e ${green}hosts文件已编辑完成${background}
        pause
        ;;
    0) return ;;
    *) echo -e ${red}输入错误${background}; pause ;;
    esac
}

# 虚拟内存管理函数
manage_swap() {
    echo -e ${white}"====="${green}系统管理-虚拟内存${white}"====="${background}
    echo -e  ${green}1.  ${cyan}查看当前虚拟内存状态${background}
    echo -e  ${green}2.  ${cyan}创建新的swap交换分区${background}
    echo -e  ${green}3.  ${cyan}调整swappiness参数${background}
    echo -e  ${green}4.  ${cyan}删除swap交换分区${background}
    echo -e  ${green}0.  ${cyan}返回主菜单${background}
    echo "========================="
    echo -e ${green}说明: ${cyan}初次使用时建议 创建新的swap交换分区2GB 并 调整swappiness参数为20${background}
    echo "========================="
    echo -en ${green}请输入您的选项: ${background};read num
    
    case ${num} in
    1)
        echo -e ${yellow}当前虚拟内存状态:${background}
        free -h
        echo
        swapon --show
        echo
        echo -e ${yellow}当前swappiness值:${background}
        cat /proc/sys/vm/swappiness
        pause
        ;;
    2)
        echo -en ${cyan}请输入要创建的swap分区大小\(GB\) （建议：如果系统内存是 2GB 的话建议设置虚拟内存也为 2GB，输入 2 即可）: ${background};read swap_size
        if [[ ! "${swap_size}" =~ ^[0-9]+$ ]] || [ ${swap_size} -le 0 ]; then
            echo -e ${red}请输入大于0的有效数字${background}
            pause
            return
        fi
        
        available_space=$(df -BG --output=avail / | tail -n 1 | tr -d 'G' | tr -d ' ')
        if [ ${swap_size} -gt ${available_space} ]; then
            echo -e ${red}磁盘空间不足，可用空间: ${available_space}GB${background}
            pause
            return
        fi
        
        if [ ${swap_size} -gt 64 ]; then
            echo -e ${yellow}警告: 创建过大的swap分区可能导致系统不稳定${background}
            echo -en ${cyan}确定要创建${swap_size}GB的swap分区吗？[y/n]: ${background};read confirm
            if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
                echo -e ${yellow}已取消创建swap分区${background}
                pause
                return
            fi
        fi

        swap_file="/swapfile"
        if [ -f "${swap_file}" ]; then
            echo -e ${yellow}已存在swap文件${background}
            echo -en ${cyan}是否删除现有swap文件并创建新的? [y/n]: ${background};read confirm
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                if swapon --show | grep -q "/swapfile"; then
                    swapoff /swapfile
                    sed -i '/\/swapfile/d' /etc/fstab
                fi
                rm -f /swapfile
                echo -e ${green}已删除原有swap文件${background}
            else
                echo -e ${yellow}已取消操作${background}
                pause
                return
            fi
        fi
        
        echo -e ${yellow}正在创建${swap_size}GB的swap文件，请稍候...${background}
        
        if command -v fallocate >/dev/null 2>&1; then
            echo -e ${cyan}使用fallocate创建swap文件...${background}
            if ! fallocate -l ${swap_size}G ${swap_file}; then
                echo -e ${red}创建swap文件失败，尝试使用传统方法...${background}
                create_swap_traditional=true
            fi
        else
            create_swap_traditional=true
        fi
        
        if [ "$create_swap_traditional" = true ]; then
            echo -e ${cyan}使用dd创建swap文件，这可能需要较长时间...${background}
            for i in $(seq 1 ${swap_size}); do
                echo -e ${cyan}正在创建第 $i/${swap_size} GB...${background}
                if ! dd if=/dev/zero of=${swap_file} bs=1G seek=$((i-1)) count=1 status=progress; then
                    echo -e ${red}创建swap文件失败${background}
                    rm -f ${swap_file}
                    pause
                    return
                fi
            done
        fi
        
        chmod 600 ${swap_file}
        if ! mkswap ${swap_file}; then
            echo -e ${red}格式化swap文件失败${background}
            rm -f ${swap_file}
            pause
            return
        fi
        
        if ! swapon ${swap_file}; then
            echo -e ${red}激活swap分区失败${background}
            rm -f ${swap_file}
            pause
            return
        fi
        
        if ! grep -q "${swap_file}" /etc/fstab; then
            echo "${swap_file} none swap sw 0 0" >> /etc/fstab
        fi
        
        echo -e ${green}swap分区创建完成并已激活${background}
        echo -e ${yellow}当前虚拟内存状态:${background}
        free -h | grep -i swap
        pause
        ;;
    3)
        echo -e ${yellow}当前swappiness值:${background}
        current_swappiness=$(cat /proc/sys/vm/swappiness)
        echo ${current_swappiness}
        echo -e ${cyan}swappiness范围: 0-100${background}
        echo -e ${cyan}较低的值减少swap使用，较高的值增加swap使用 （建议值为 20） ${background}
        echo -en ${cyan}请输入新的swappiness值: ${background};read new_swappiness
        
        if [[ "${new_swappiness}" =~ ^[0-9]+$ ]] && [ ${new_swappiness} -ge 0 ] && [ ${new_swappiness} -le 100 ]; then
            sysctl vm.swappiness=${new_swappiness}
            echo "vm.swappiness=${new_swappiness}" > /etc/sysctl.d/99-swappiness.conf
            echo -e ${green}swappiness已设置为${new_swappiness}${background}
        else
            echo -e ${red}请输入0-100之间的有效数字${background}
        fi
        pause
        ;;
    4)
        if swapon --show | grep -q "/swapfile"; then
            swapoff /swapfile
            sed -i '/\/swapfile/d' /etc/fstab
            rm -f /swapfile
            echo -e ${green}swap分区已删除${background}
        else
            echo -e ${yellow}未找到活动的swap分区${background}
        fi
        pause
        ;;
    0) return ;;
    *) echo -e ${red}输入错误${background}; pause ;;
    esac
}

# 安装常用字体函数
install_fonts() {
    fonts_dir="/usr/share/fonts/custom"
    echo -e ${white}"====="${green}系统管理-安装字体${white}"====="${background}
    echo -e  ${green}1.  ${cyan}查看已安装字体${background}
    echo -e  ${green}2.  ${cyan}安装中文字体包${background}
    echo -e  ${green}3.  ${cyan}安装编程字体${background}
    echo -e  ${green}4.  ${cyan}安装表情符号字体${background}
    echo -e  ${green}5.  ${cyan}刷新字体缓存${background}
    echo -e  ${green}0.  ${cyan}返回主菜单${background}
    echo "========================="
    echo -en ${green}请输入您的选项: ${background};read num
    
    case ${num} in
    1)
        echo -e ${yellow}系统已安装字体列表:${background}
        fc-list : family | sort
        pause
        ;;
    2)
        echo -e ${yellow}正在安装中文字体包...${background}
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
        echo -e ${cyan}正在下载思源黑体...${background}
        wget -q --show-progress ${GithubMirror}https://github.com/adobe-fonts/source-han-sans/releases/download/2.004R/SourceHanSansSC.zip -O /tmp/SourceHanSansSC.zip
        unzip -q /tmp/SourceHanSansSC.zip -d /tmp/SourceHanSansSC
        cp /tmp/SourceHanSansSC/SubsetOTF/SC/*.otf ${fonts_dir}/chinese/
        rm -rf /tmp/SourceHanSansSC /tmp/SourceHanSansSC.zip
        
        echo -e ${cyan}正在下载文泉驿字体...${background}
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
        echo -e ${green}中文字体安装完成并已刷新字体缓存${background}
        pause
        ;;
    3)
        echo -e ${yellow}正在安装编程字体...${background}
        if command -v apt >/dev/null 2>&1; then
            apt update && apt install -y wget unzip fontconfig
        elif command -v yum >/dev/null 2>&1; then
            yum install -y wget unzip fontconfig
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y wget unzip fontconfig
        fi
        
        mkdir -p ${fonts_dir}/programming
        echo -e ${cyan}正在下载JetBrains Mono字体...${background}
        wget -q --show-progress ${GithubMirror}https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip -O /tmp/JetBrainsMono.zip
        unzip -q /tmp/JetBrainsMono.zip -d /tmp/JetBrainsMono
        cp /tmp/JetBrainsMono/fonts/ttf/*.ttf ${fonts_dir}/programming/
        rm -rf /tmp/JetBrainsMono /tmp/JetBrainsMono.zip
        
        echo -e ${cyan}正在下载Fira Code字体...${background}
        wget -q --show-progress ${GithubMirror}https://github.com/tonsky/FiraCode/releases/download/6.2/Fira_Code_v6.2.zip -O /tmp/FiraCode.zip
        unzip -q /tmp/FiraCode.zip -d /tmp/FiraCode
        cp /tmp/FiraCode/ttf/*.ttf ${fonts_dir}/programming/
        rm -rf /tmp/FiraCode /tmp/FiraCode.zip
        
        fc-cache -fv
        echo -e ${green}编程字体安装完成并已刷新字体缓存${background}
        pause
        ;;
    4)
        echo -e ${yellow}正在安装表情符号字体...${background}
        if command -v apt >/dev/null 2>&1; then
            apt update && apt install -y wget fontconfig
        elif command -v yum >/dev/null 2>&1; then
            yum install -y wget fontconfig
        fi
        
        mkdir -p ${fonts_dir}/emoji
        echo -e ${cyan}正在下载Noto Color Emoji字体...${background}
        wget -q --show-progress ${GithubMirror}https://github.com/googlefonts/noto-emoji/raw/main/fonts/NotoColorEmoji.ttf -O ${fonts_dir}/emoji/NotoColorEmoji.ttf
        
        fc-cache -fv
        echo -e ${green}表情符号字体安装完成并已刷新字体缓存${background}
        pause
        ;;
    5)
        echo -e ${yellow}正在刷新字体缓存...${background}
        fc-cache -fv
        echo -e ${green}字体缓存刷新完成${background}
        pause
        ;;
    0) return ;;
    *) echo -e ${red}输入错误${background}; pause ;;
    esac
}

# 系统垃圾清理函数
clean_system() {
    echo -e ${white}"====="${green}系统管理-清理垃圾${white}"====="${background}
    echo -e  ${green}1.  ${cyan}常规清理 \(系统日志、Redis日志、系统缓存\)${background}
    echo -e  ${green}0.  ${cyan}返回主菜单${background}
    echo "========================="
    echo -en ${green}请输入您的选项: ${background};read num

    case ${num} in
    1)
        echo -e ${yellow}正在清理 systemd 日志 \(保留最近100M\)...${background}
        journalctl --vacuum-size=100M

        echo -e ${yellow}正在清理暴力登录日志...${background}
        [ -f /var/log/btmp ] && truncate -s 0 /var/log/btmp
        [ -f /var/log/btmp.1 ] && truncate -s 0 /var/log/btmp.1

        echo -e ${yellow}正在清理认证日志...${background}
        [ -f /var/log/auth.log ] && truncate -s 0 /var/log/auth.log
        [ -f /var/log/auth.log.1 ] && truncate -s 0 /var/log/auth.log.1
        [ -f /var/log/secure ] && truncate -s 0 /var/log/secure

        echo -e ${yellow}正在清理 redis 日志...${background}
        [ -f /var/log/redis/redis-server.log ] && truncate -s 0 /var/log/redis/redis-server.log

        echo -e ${yellow}正在清理包管理器缓存...${background}
        if command -v apt >/dev/null 2>&1; then
            apt autoremove -y && apt clean
        elif command -v yum >/dev/null 2>&1; then
            yum autoremove -y && yum clean all
        elif command -v dnf >/dev/null 2>&1; then
            dnf autoremove -y && dnf clean all
        elif command -v pacman >/dev/null 2>&1; then
            pacman -Scc --noconfirm
        fi

        echo -e ${green}常规清理完成！${background}
        pause
        ;;
    0) return ;;
    *) echo -e ${red}输入错误${background}; pause ;;
    esac
}

# 一键开启 BBR 函数
manage_bbr() {
    echo -e ${white}"====="${green}系统管理-开启BBR${white}"====="${background}
    echo -e ${yellow}正在检测当前BBR开启状态...${background}
    
    current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    if [ "$current_cc" = "bbr" ]; then
        echo -e ${green}检测结果：当前系统已成功开启 BBR 加速！${background}
        lsmod | grep bbr
    else
        echo -e ${yellow}当前系统未开启 BBR，正在为您自动配置并开启...${background}
        
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
            echo -e ${green}恭喜，BBR 开启成功！网络吞吐量已优化。${background}
            lsmod | grep bbr
        else
            echo -e ${red}BBR 开启失败！请确认您的系统内核版本是否大于等于 4.9 。${background}
        fi
    fi
    pause
}

# 检测并安装 Docker
check_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${yellow}未检测到 Docker，正在为您自动安装...${background}"
        curl -fsSL https://get.docker.com | bash
        systemctl enable --now docker
        echo -e "${green}Docker 安装并启动成功！${background}"
    else
        echo -e "${green}Docker 已安装。${background}"
    fi
}

# Sing-box 管理函数
manage_singbox() {
    CONF_DIR="/etc/sing-box"
    CONF_FILE="${CONF_DIR}/config.json"
    INFO_FILE="${CONF_DIR}/info.txt"
    CERT_FILE="${CONF_DIR}/cert.pem"
    KEY_FILE="${CONF_DIR}/private.key"

    # 获取 docker 容器运行状态 (屏蔽报错输出)
    STATUS_CHECK=$(docker inspect -f '{{.State.Running}}' sing-box 2>/dev/null)
    MEM_USAGE="0.00MB"
    
    if [ "$STATUS_CHECK" == "true" ]; then
        SINGBOX_STATUS="${green}▶ 运行中${background}"
        # 获取当前内存占用
        MEM_USAGE=$(docker stats --no-stream --format "{{.MemUsage}}" sing-box 2>/dev/null | awk '{print $1}')
    elif [ "$STATUS_CHECK" == "false" ]; then
        SINGBOX_STATUS="${red}■ 已停止${background}"
    else
        SINGBOX_STATUS="${yellow}● 未安装${background}"
    fi

    clear
    echo -e ${white}"====="${green}系统管理-Sing-box \(Hysteria2\)${white}"====="${background}
    echo -e  ${green}1.  ${cyan}部署 服务端 \(中转机 / 开放外网访问\)${background}
    echo -e  ${green}2.  ${cyan}部署 客户端 \(本地机 / 连接到中转机\)${background}
    echo -e  ${green}3.  ${cyan}启动 Sing-box${background}
    echo -e  ${green}4.  ${cyan}停止 Sing-box${background}
    echo -e  ${green}5.  ${cyan}重启 Sing-box${background}
    echo -e  ${green}6.  ${cyan}查看连接信息及使用帮助${background}
    echo -e  ${green}7.  ${cyan}卸载 Sing-box${background}
    echo -e  ${green}0.  ${cyan}返回主菜单${background}
    echo "========================="
    echo -e "  当前状态: ${SINGBOX_STATUS}"
    if [ "$STATUS_CHECK" == "true" ]; then
        echo -e "  内存占用: ${cyan}${MEM_USAGE}${background}"
    fi
    echo "========================="
    echo -en ${green}请输入您的选项: ${background};read num

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
节点角色 : 中转机 (Server)
服务器IP : ${PUBLIC_IP}
代理端口 : ${PORT} (UDP协议)
认证密码 : ${PASSWORD}
======================================
【连接帮助】: 
1. 服务端已就绪，请务必在防火墙/安全组放行 ${PORT} 的 UDP 端口！
2. 请在您的“本地机”上运行此脚本，选择 [选项2. 部署客户端]
3. 填入上方的 IP、端口 和 密码 即可建立连接。
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
        echo -en "${cyan}请输入中转机(服务端)的 IP 地址: ${background}"
        read SERVER_IP
        echo -en "${cyan}请输入中转机(服务端)的 端口: ${background}"
        read SERVER_PORT
        echo -en "${cyan}请输入中转机(服务端)的 密码: ${background}"
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
节点角色 : 本地机 (Client)
连接目标 : ${SERVER_IP}:${SERVER_PORT}
本地端口 : ${LOCAL_PORT} (HTTP/Socks5)
======================================
【使用帮助】: 
本地客户端已启动。您现在可以让本地的其他软件或设备，
通过 HTTP 或 Socks5 代理连接到本机:
代理地址: 127.0.0.1 (或本机的局域网IP)
代理端口: ${LOCAL_PORT}
流量将通过 Hysteria2 加密传输至中转机。
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
    *) echo -e ${red}输入错误${background}; pause; manage_singbox ;;
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

# 主菜单函数
main() {
    echo -e ${white}"====="${green}呆毛版-系统管理${white}"====="${background}
    echo -e  ${green}1.  ${cyan}Hosts文件管理${background}
    echo -e  ${green}2.  ${cyan}虚拟内存管理${background}
    echo -e  ${green}3.  ${cyan}安装常用字体${background}
    echo -e  ${green}4.  ${cyan}清理系统垃圾${background}
    echo -e  ${green}5.  ${cyan}开启BBR网络加速${background}
    echo -e  ${green}6.  ${cyan}Sing-box正向代理${background}
    echo -e  ${green}0.  ${cyan}退出${background}
    echo "========================="
    echo -e ${green}系统信息: $(uname -s) $(uname -r) $(uname -m)${background}
    echo -e ${green}内存状态: $(free -h | grep Mem | awk '{print $3"/"$2" 使用"}')${background}
    echo -e ${green}QQ群: ${cyan}呆毛版-QQ群:1022982073${background}
    echo "========================="
    echo
    echo -en ${green}请输入您的选项: ${background};read number
    case ${number} in
    1) manage_hosts ;;
    2) manage_swap ;;
    3) install_fonts ;;
    4) clean_system ;;
    5) manage_bbr ;;
    6) manage_singbox ;;
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
