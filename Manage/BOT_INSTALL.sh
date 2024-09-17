#!/bin/env bash
if ping -c 1 gitee.com > /dev/null 2>&1
then
  URL="https://gitee.com/Misaka21011/Yunzai-Bot-Shell/raw/master/Linux/Bot-Install-"
elif ping -c 1 github.com > /dev/null 2>&1
then
  URL="https://raw.githubusercontent.com/Misaka21011/Yunzai-Bot-Shell/master/Linux/Bot-Install-"
fi
Arch_Script="${URL}ArchLinux.sh"
Kernel_Script="${URL}CentOS.sh"
Ubuntu_Script="${URL}Ubuntu.sh"
Debian_Script="${URL}Debian.sh"
if grep -q -E -i Arch /etc/issue && [ -x /usr/bin/pacman ];then
    bash <(curl -sL ${Arch_Script})
elif grep -q -E -i Kernel /etc/issue && [ -x /usr/bin/dnf ];then
    echo -e ${red}暂时放弃对centos的支持${background}
    exit
    bash <(curl -sL ${Kernel_Script})
elif grep -q -E -i Kernel /etc/issue && [ -x /usr/bin/yum ];then
    echo -e ${red}暂时放弃对centos的支持${background}
    exit
    bash <(curl -sL ${Kernel_Script})
elif grep -q -E -i Ubuntu /etc/issue && [ -x /usr/bin/apt ];then
    bash <(curl -sL ${Ubuntu_Script})
elif grep -q -E -i Debian /etc/issue && [ -x /usr/bin/apt ];then
    bash <(curl -sL ${Debian_Script})
elif grep -q -E -i Arch /etc/os-release && [ -x /usr/bin/pacman ];then
    bash <(curl -sL ${Arch_Script})
elif grep -q -E -i CentOS /etc/os-release && [ -x /usr/bin/dnf ];then
    echo -e ${red}暂时放弃对centos的支持${background}
    exit
    bash <(curl -sL ${Kernel_Script})
elif grep -q -E -i CentOS /etc/os-release && [ -x /usr/bin/yum ];then
    echo -e ${red}暂时放弃对centos的支持${background}
    exit
    bash <(curl -sL ${Kernel_Script})
elif grep -q -E -i Ubuntu /etc/os-release && [ -x /usr/bin/apt ];then
    bash <(curl -sL ${Ubuntu_Script})
elif grep -q -E -i Debian /etc/os-release && [ -x /usr/bin/apt ];then
    bash <(curl -sL ${Debian_Script})
fi