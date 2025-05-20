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
echo -e ${red}请在Linux系统上运行${background}
exit
fi
if [ ! "$(uname)" = "Linux" ]; then
	echo -e ${red}请在Linux系统上运行${background}
    exit
fi
if [ ! "$(id -u)" = "0" ]; then
    echo -e ${red}请使用root用户${background}
    exit 0
fi


URL="https://ipinfo.io"
Address=$(curl -sL ${URL} | sed -n 's/.*"country": "\(.*\)",.*/\1/p')
if [ "${Address}" = "CN" ]
then
  GitMirror="gitee.com"
  GithubMirror="https://github.moeyy.xyz/"
else
  GitMirror="github.com"
  GithubMirror=""
fi

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
        echo -en ${yellow}回车返回${background};read
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
        echo -en ${yellow}回车返回${background};read
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
        echo -en ${yellow}回车返回${background};read
        ;;
    4)
        if [ -x "$(command -v nano)" ]; then
            nano ${hosts_file}
        elif [ -x "$(command -v vim)" ]; then
            vim ${hosts_file}
        else
            echo -e ${red}未找到编辑器，请安装nano或vim${background}
        fi
        echo -e ${green}hosts文件已编辑完成${background}
        echo -en ${yellow}回车返回${background};read
        ;;
    0)
        return
        ;;
    *)
        echo -e ${red}输入错误${background}
        echo -en ${yellow}回车返回${background};read
        ;;
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
        echo -en ${yellow}回车返回${background};read
        ;;
    2)
    echo -en ${cyan}请输入要创建的swap分区大小\(GB\) （建议：如果系统内存是 2GB 的话建议设置虚拟内存也为 2GB，输入 2 即可）: ${background};read swap_size
    if [[ ! "${swap_size}" =~ ^[0-9]+$ ]]; then
        echo -e ${red}请输入有效的数字${background}
        echo -en ${yellow}回车返回${background};read
        return
    fi
    
    # 检查swap大小是否合理
    if [ ${swap_size} -le 0 ]; then
        echo -e ${red}swap大小必须大于0GB${background}
        echo -en ${yellow}回车返回${background};read
        return
    fi
    
    # 获取可用磁盘空间(GB)
    available_space=$(df -BG --output=avail / | tail -n 1 | tr -d 'G')
    if [ ${swap_size} -gt ${available_space} ]; then
        echo -e ${red}磁盘空间不足，可用空间: ${available_space}GB${background}
        echo -en ${yellow}回车返回${background};read
        return
    fi
    
    # 检查大小是否过大（建议限制最大值）
    if [ ${swap_size} -gt 64 ]; then
        echo -e ${yellow}警告: 创建过大的swap分区可能导致系统不稳定${background}
        echo -en ${cyan}确定要创建${swap_size}GB的swap分区吗？[y/n]: ${background};read confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            echo -e ${yellow}已取消创建swap分区${background}
            echo -en ${yellow}回车返回${background};read
            return
        fi
    fi

    swap_file="/swapfile"
    if [ -f "${swap_file}" ]; then
        echo -e ${yellow}已存在swap文件${background}
        echo -en ${cyan}是否删除现有swap文件并创建新的? [y/n]: ${background};read confirm
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
            # 先尝试关闭并删除已激活的swap
            if swapon --show | grep -q "/swapfile"; then
                swapoff /swapfile
                sed -i '/\/swapfile/d' /etc/fstab
            fi
            rm -f /swapfile
            echo -e ${green}已删除原有swap文件${background}
        else
            echo -e ${yellow}已取消操作${background}
            echo -en ${yellow}回车返回${background};read
            return
        fi
    fi
    
    echo -e ${yellow}正在创建${swap_size}GB的swap文件，请稍候...${background}
    
    # 使用fallocate创建稀疏文件（更快、更节省内存）
    if command -v fallocate >/dev/null 2>&1; then
        echo -e ${cyan}使用fallocate创建swap文件...${background}
        if ! fallocate -l ${swap_size}G ${swap_file}; then
            echo -e ${red}创建swap文件失败，尝试使用传统方法...${background}
            create_swap_traditional=true
        fi
    else
        create_swap_traditional=true
    fi
    
    # 如果fallocate不可用或失败，使用传统的dd方法分块创建
    if [ "$create_swap_traditional" = true ]; then
        echo -e ${cyan}使用dd创建swap文件，这可能需要较长时间...${background}
        # 分块创建大文件，每次创建1GB
        for i in $(seq 1 ${swap_size}); do
            echo -e ${cyan}正在创建第 $i/${swap_size} GB...${background}
            if ! dd if=/dev/zero of=${swap_file} bs=1G seek=$((i-1)) count=1 status=progress; then
                echo -e ${red}创建swap文件失败${background}
                rm -f ${swap_file}
                echo -en ${yellow}回车返回${background};read
                return
            fi
        done
    fi
    
    # 设置权限并格式化为swap
    chmod 600 ${swap_file}
    if ! mkswap ${swap_file}; then
        echo -e ${red}格式化swap文件失败${background}
        rm -f ${swap_file}
        echo -en ${yellow}回车返回${background};read
        return
    fi
    
    # 激活swap
    if ! swapon ${swap_file}; then
        echo -e ${red}激活swap分区失败${background}
        rm -f ${swap_file}
        echo -en ${yellow}回车返回${background};read
        return
    fi
    
    # 添加到fstab以便开机自动挂载
    if ! grep -q "${swap_file}" /etc/fstab; then
        echo "${swap_file} none swap sw 0 0" >> /etc/fstab
    fi
    
    echo -e ${green}swap分区创建完成并已激活${background}
    echo -e ${yellow}当前虚拟内存状态:${background}
    free -h | grep -i swap
    echo -en ${yellow}回车返回${background};read
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
        echo -en ${yellow}回车返回${background};read
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
        echo -en ${yellow}回车返回${background};read
        ;;
    0)
        return
        ;;
    *)
        echo -e ${red}输入错误${background}
        echo -en ${yellow}回车返回${background};read
        ;;
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
        echo -en ${yellow}回车返回${background};read
        ;;
    2)
        echo -e ${yellow}正在安装中文字体包...${background}
        
        # 安装依赖
        if [ $(command -v apt) ]; then
            apt update
            apt install -y wget unzip fontconfig
        elif [ $(command -v yum) ]; then
            yum install -y wget unzip fontconfig
        elif [ $(command -v dnf) ]; then
            dnf install -y wget unzip fontconfig
        elif [ $(command -v pacman) ]; then
            pacman -Sy --noconfirm wget unzip fontconfig
        fi
        
        # 创建字体目录
        mkdir -p ${fonts_dir}/chinese
        
        # 下载并安装思源黑体
        echo -e ${cyan}正在下载思源黑体...${background}
        wget -q --show-progress ${GithubMirror}https://github.com/adobe-fonts/source-han-sans/releases/download/2.004R/SourceHanSansSC.zip -O /tmp/SourceHanSansSC.zip
        unzip -q /tmp/SourceHanSansSC.zip -d /tmp/SourceHanSansSC
        cp /tmp/SourceHanSansSC/SubsetOTF/SC/*.otf ${fonts_dir}/chinese/
        rm -rf /tmp/SourceHanSansSC /tmp/SourceHanSansSC.zip
        
        # 下载并安装文泉驿字体
        echo -e ${cyan}正在下载文泉驿字体...${background}
        if [ $(command -v apt) ]; then
            apt install -y fonts-wqy-microhei fonts-wqy-zenhei
        elif [ $(command -v yum) ]; then
            yum install -y wqy-microhei-fonts wqy-zenhei-fonts
        elif [ $(command -v dnf) ]; then
            dnf install -y wqy-microhei-fonts wqy-zenhei-fonts
        elif [ $(command -v pacman) ]; then
            pacman -Sy --noconfirm wqy-microhei wqy-zenhei
        fi
        
        # 刷新字体缓存
        fc-cache -fv
        
        echo -e ${green}中文字体安装完成并已刷新字体缓存${background}
        echo -en ${yellow}回车返回${background};read
        ;;
    3)
        echo -e ${yellow}正在安装编程字体...${background}
        
        # 安装依赖
        if [ $(command -v apt) ]; then
            apt update
            apt install -y wget unzip fontconfig
        elif [ $(command -v yum) ]; then
            yum install -y wget unzip fontconfig
        elif [ $(command -v dnf) ]; then
            dnf install -y wget unzip fontconfig
        elif [ $(command -v pacman) ]; then
            pacman -Sy --noconfirm wget unzip fontconfig
        fi
        
        # 创建字体目录
        mkdir -p ${fonts_dir}/programming
        
        # 下载并安装JetBrains Mono字体
        echo -e ${cyan}正在下载JetBrains Mono字体...${background}
        wget -q --show-progress ${GithubMirror}https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip -O /tmp/JetBrainsMono.zip
        unzip -q /tmp/JetBrainsMono.zip -d /tmp/JetBrainsMono
        cp /tmp/JetBrainsMono/fonts/ttf/*.ttf ${fonts_dir}/programming/
        rm -rf /tmp/JetBrainsMono /tmp/JetBrainsMono.zip
        
        # 下载并安装Fira Code字体
        echo -e ${cyan}正在下载Fira Code字体...${background}
        wget -q --show-progress ${GithubMirror}https://github.com/tonsky/FiraCode/releases/download/6.2/Fira_Code_v6.2.zip -O /tmp/FiraCode.zip
        unzip -q /tmp/FiraCode.zip -d /tmp/FiraCode
        cp /tmp/FiraCode/ttf/*.ttf ${fonts_dir}/programming/
        rm -rf /tmp/FiraCode /tmp/FiraCode.zip
        
        # 刷新字体缓存
        fc-cache -fv
        
        echo -e ${green}编程字体安装完成并已刷新字体缓存${background}
        echo -en ${yellow}回车返回${background};read
        ;;
    4)
        echo -e ${yellow}正在安装表情符号字体...${background}
        
        # 安装依赖
        if [ $(command -v apt) ]; then
            apt update
            apt install -y wget fontconfig
        elif [ $(command -v yum) ]; then
            yum install -y wget fontconfig
        elif [ $(command -v dnf) ]; then
            dnf install -y wget fontconfig
        elif [ $(command -v pacman) ]; then
            pacman -Sy --noconfirm wget fontconfig
        fi
        
        # 创建字体目录
        mkdir -p ${fonts_dir}/emoji
        
        # 下载并安装Noto Color Emoji字体
        echo -e ${cyan}正在下载Noto Color Emoji字体...${background}
        wget -q --show-progress ${GithubMirror}https://github.com/googlefonts/noto-emoji/raw/main/fonts/NotoColorEmoji.ttf -O ${fonts_dir}/emoji/NotoColorEmoji.ttf
        
        # 刷新字体缓存
        fc-cache -fv
        
        echo -e ${green}表情符号字体安装完成并已刷新字体缓存${background}
        echo -en ${yellow}回车返回${background};read
        ;;
    5)
        echo -e ${yellow}正在刷新字体缓存...${background}
        fc-cache -fv
        echo -e ${green}字体缓存刷新完成${background}
        echo -en ${yellow}回车返回${background};read
        ;;
    0)
        return
        ;;
    *)
        echo -e ${red}输入错误${background}
        echo -en ${yellow}回车返回${background};read
        ;;
    esac
}

# 主菜单函数
main() {
    echo -e ${white}"====="${green}呆毛版-系统管理${white}"====="${background}
    echo -e  ${green}1.  ${cyan}Hosts文件管理${background}
    echo -e  ${green}2.  ${cyan}虚拟内存管理${background}
    echo -e  ${green}3.  ${cyan}安装常用字体${background}
    echo -e  ${green}0.  ${cyan}退出${background}
    echo "========================="
    echo -e ${green}系统信息: $(uname -s) $(uname -r) $(uname -m)${background}
    echo -e ${green}内存状态: $(free -h | grep Mem | awk '{print $3"/"$2" 使用"}')${background}
    echo -e ${green}QQ群: ${cyan}呆毛版-QQ群:285744328${background}
    echo "========================="
    echo
    echo -en ${green}请输入您的选项: ${background};read number
    case ${number} in
    1)
        echo
        manage_hosts
        ;;
    2)
        echo
        manage_swap
        ;;
    3)
        echo
        install_fonts
        ;;
    0)
        exit
        ;;
    *)
        echo
        echo -e ${red}输入错误${background}
        echo -en ${yellow}回车返回${background};read
        ;;
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
