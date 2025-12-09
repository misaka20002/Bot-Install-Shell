#!/bin/env bash
cd $HOME
export red="\033[31m"
export green="\033[32m"
export yellow="\033[33m"
export blue="\033[34m"
export purple="\033[35m"
export cyan="\033[36m"
export white="\033[37m"
export background="\033[0m"

if [ "$(uname -o)" = "Android" ]; then
	echo "看来你是大聪明 加Q群获取帮助吧 1022982073"
	exit 1
fi

if ! [ "$(uname)" == "Linux" ];then
    echo -e ${red}请使用linux!${background}
    exit 0
fi

if [ "$(id -u)" != "0" ]; then
    echo -e ${red} 请使用root用户!${background}
    exit 0
fi
function Dependency(){
InstallDependency(){
echo -e ${green}正在安装必要依赖 dialog${background}
if [ $(command -v apt) ];then
    apt install -y dialog curl
elif [ $(command -v dnf) ];then
    dnf install -y dialog curl
elif [ $(command -v yum) ];then
    yum install -y dialog curl
elif [ $(command -v pacman) ];then
    pacman -S --noconfirm --needed dialog curl
fi
}
if [ -x "$(command -v whiptail)" ];then
    dialog_whiptail=whiptail
elif [ -x "$(command -v dialog)" ];then
    dialog_whiptail=dialog
else
    dialog_whiptail=dialog
    InstallDependency
fi
if [ ! -x "$(command -v curl)" ];then
    InstallDependency
fi
}

function SystemCheck(){
if grep -q -E -i Arch /etc/issue && [ -x /usr/bin/pacman ];then
    echo -e ${green}系统校验通过${background}
elif grep -q -E -i Kernel /etc/issue && [ -x /usr/bin/dnf ];then
    echo -e ${red}暂时放弃对centos的支持${background}
    exit
    echo -e ${green}系统校验通过${background}
elif grep -q -E -i Kernel /etc/issue && [ -x /usr/bin/yum ];then
    echo -e ${red}暂时放弃对centos的支持${background}
    exit
    echo -e ${green}系统校验通过${background}
elif grep -q -E -i Ubuntu /etc/issue && [ -x /usr/bin/apt ];then
    echo -e ${green}系统校验通过${background}
elif grep -q -E -i Debian /etc/issue && [ -x /usr/bin/apt ];then
    echo -e ${green}系统校验通过${background}
elif grep -q -E -i Kali /etc/issue && [ -x /usr/bin/apt ];then
    echo -e ${green}系统校验通过${background}
elif grep -q -E -i Alpine /etc/os-release && [ -x /sbin/apk ];then
    echo -e ${green}系统校验通过${background}
elif grep -q -E -i Arch /etc/os-release && [ -x /usr/bin/pacman ];then
    echo -e ${green}系统校验通过${background}
elif grep -q -E -i CentOS /etc/os-release && [ -x /usr/bin/dnf ];then
    echo -e ${red}暂时放弃对centos的支持${background}
    exit
    echo -e ${green}系统校验通过${background}
elif grep -q -E -i CentOS /etc/os-release && [ -x /usr/bin/yum ];then
    echo -e ${red}暂时放弃对centos的支持${background}
    exit
    echo -e ${green}系统校验通过${background}
elif grep -q -E -i Ubuntu /etc/os-release && [ -x /usr/bin/apt ];then
    echo -e ${green}系统校验通过${background}
elif grep -q -E -i Debian /etc/os-release && [ -x /usr/bin/apt ];then
    echo -e ${green}系统校验通过${background}
elif grep -q -E -i Kali /etc/os-release && [ -x /usr/bin/apt ];then
    echo -e ${green}系统校验通过${background}
else
    echo -e ${red}不受支持的系统${background}
    echo -e ${red}程序终止!! 脚本停止运行${background}
    exit
fi
}
function Script_Install(){
    echo -e ${green}正在获取版本信息${background}
    if [  -z  "${GitMirror}"  ];then
      URL="https://ipinfo.io"
      Address=$(curl ${URL} | sed -n 's/.*"country": "\(.*\)",.*/\1/p')
      if [ "${Address}" = "CN" ]
      then
          GitMirror="gitee.com"
          URL="https://gitee.com/Misaka21011/Yunzai-Bot-Shell/raw/master/version"
      else 
          GitMirror="github.com"
          URL="https://raw.githubusercontent.com/misaka20002/Bot-Install-Shell/master/version"
      fi
    fi
    version_date=$(curl -sL ${URL})
    version="$(echo "${version_date}" | grep 'version:' | awk '{print $2}')"
    date="$(echo "${version_date}" | grep 'date:' | awk '{print $2}')"
    echo -e ${cyan}获取成功${background}
    echo
    echo -e ${white}=========================${background}
    echo -e ${red}" "呆毛版 ${yellow}BOT ${green}Install ${cyan}Script ${background}
    echo -e "  "————"  "————"  "————"  "————"  "
    echo -e ${green}" "版本:" "v${version} ${cyan}\(date: ${date}\) ${background}
    echo -e ${green}" "作者:" "${cyan}小呆毛"   "\(Misaka21011\) ${background}
    echo -e ${green}" "镜像:" "${cyan}${GitMirror}${background}
    echo -e ${white}=========================${background}
    echo
    echo -e ${white}=========================${background}
    echo -e ${green}请选择安装途径${background}
    echo -e ${green}1${cyan}\) Gitee${background}
    echo -e ${green}2${cyan}\) Github${background}
    echo -e ${white}=========================${background}
    echo -en ${green}请选择: ${background};read Choice
    case ${Choice} in 
        1)
            URL="https://gitee.com/Misaka21011/Yunzai-Bot-Shell/raw/master/Manage/Main.sh"
            ;;
        2)
            URL="https://raw.githubusercontent.com/misaka20002/Bot-Install-Shell/master/Manage/Main.sh"
            ;;
        *)
            echo -e ${red}输入错误${background}
            exit
            ;;
    esac
    echo -e ${yellow} - ${cyan}正在安装${background}
    curl ${URL} > xdm
    if [ -f "/usr/local/bin/bh" ]; then
        rm -f /usr/local/bin/bh
    fi
    mv -f xdm /usr/local/bin/xdm
    chmod +x /usr/local/bin/xdm
    echo
    if ! /usr/local/bin/xdm help; then
        echo -e ${yellow} - ${red}安装失败，脚本无法正常运行${background}
        echo -e ${yellow} - ${cyan}正在尝试解决shebang问题${background}
        
        # 尝试修复shebang
        old_xdm_bash='#!/bin/env bash'
        new_xdm_bash=$(command -v bash)
        if [ -n "${new_xdm_bash}" ]; then
            sed -i "s|${old_xdm_bash}|#!${new_xdm_bash}|g" /usr/local/bin/xdm
            
            # 再次测试
            if /usr/local/bin/xdm help; then
                echo -e ${yellow} - ${green}shebang修复成功${background}
            else
                echo -e ${yellow} - ${red}修复失败，请手动检查脚本${background}
                echo -e ${yellow} - ${cyan}脚本位置: /usr/local/bin/xdm${background}
                exit 1
            fi
        else
            echo -e ${yellow} - ${red}无法找到bash路径，修复失败${background}
            exit 1
        fi
    fi
    echo -e ${yellow} - ${yellow}安装成功${background}
    echo -e ${yellow} - ${cyan}请使用 ${green}xdm ${cyan}命令 打开脚本${background}
}

echo -e ${white}"====="${green}呆毛版-Script${white}"====="${background}
echo -e ${cyan}呆毛版 Script ${green}是完全可信的。${background}
echo -e ${cyan}呆毛版 Script ${yellow}不会执行任何恶意命令${background}
echo -e ${cyan}呆毛版 Script ${yellow}不会执行任何恶意命令${background}
echo -e ${cyan}呆毛版 Script ${yellow}不会执行任何恶意命令${background}
echo -e ${cyan}如果您同意安装 请输入 ${green}同意安装${background}
echo -e ${cyan}注意：同意安装即同意本项目的用户协议${background}
echo -e ${cyan}用户协议链接: ${background}
echo -e ${cyan}https://gitee.com/Misaka21011/Yunzai-Bot-Shell/blob/master/Manage/用户协议.txt ${background}
echo -e ${white}"=========================="${background}
echo -en ${green}请输入:${background};read yn
if [  "${yn}" == "同意安装" ]
then
    echo -e ${green}2秒后开始安装${background}
    sleep 1s
    SystemCheck
    Dependency
    echo
    Script_Install
else
    echo -e ${red}程序终止!! 脚本停止运行${background}
fi
