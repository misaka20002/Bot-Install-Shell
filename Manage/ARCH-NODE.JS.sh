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

case $(uname -m) in
    x86_64|amd64)
    ARCH=x64
;;
    arm64|aarch64)
    ARCH=arm64
;;
*)
    echo ${red}您的框架为${yellow}$(uname -m)${red},快提issue做适配.${background}
    exit
;;
esac

if ping -c 1 google.com > /dev/null 2>&1
then
    NpmMirror="https://registry.npmjs.org"
    NodeJS_URL="https://nodejs.org/dist/latest-v18.x/node-v18.19.0-linux-${ARCH}.tar.xz"
elif ping -c 1 baidu.com > /dev/null 2>&1
then
    NpmMirror="https://registry.npmjs.org"
    NodeJS_URL="https://registry.npmmirror.com/-/binary/node/latest-v18.x/node-v18.19.0-linux-${ARCH}.tar.xz"
    NodeJS_URL=$(curl ${NodeJS_URL})
    NodeJS_URL=$(echo ${NodeJS_URL#*\"})
    NodeJS_URL=$(echo ${NodeJS_URL%\"*})
fi

if pacman -Qs nodejs > /dev/null 2>&1;then
    echo -e ${yellow}卸载软件 nodejs${background}
    pacman -Rcs --noconfirm nodejs
fi

pkg_list=("tar" "pv" "xz" "gzip" "wget")
for package in ${pkg_list[@]}
do
    if ! pacman -Qi "${package}" > /dev/null 2>&1;then
        echo -e ${yellow}安装软件 ${package}${background}
        pacman -Syy --noconfirm --needed ${package}
    fi
done
i=1
echo -e ${yellow}安装软件 Node.JS${background}
until wget -O node.tar.xz -c ${NodeJS_URL}
do
    if [ "${i}" == "3" ];then
        echo -e ${red}错误次数过多 退出${background}
        exit 
    fi
    i=$((${i}+1))
done
if [ ! -d node ];then
    mkdir node
fi
echo -e ${yellow}正在解压二进制文件压缩包${background}
pv node.tar.xz | tar -xJf - -C node
rm -rf /usr/local/node > /dev/null
rm -rf /usr/local/node > /dev/null
mv -f node/$(ls node) /usr/local/node
rm -rf node
if [ ! -d $HOME/.local/share/pnpm ];then
    mkdir -p $HOME/.local/share/pnpm
fi
export PATH=$PATH:/usr/local/node/bin
export PATH=$PATH:/root/.local/share/pnpm
export PNPM_HOME=/root/.local/share/pnpm
if [ -e /etc/fish/config.fish ];then
if ! grep -q '#Node.JS' /etc/fish/config.fish;then
echo '
#Node.JS
set -x PATH /root/.local/share/pnpm /usr/local/node/bin $PATH
set PNPM_HOME /root/.local/share/pnpm
' >> /etc/fish/config.fish
fi
source /etc/fish/config.fish
else
if ! grep -q '#Node.JS' /etc/profile;then
echo '
#Node.JS
export PATH=$PATH:/usr/local/node/bin
export PATH=$PATH:/root/.local/share/pnpm
export PNPM_HOME=/root/.local/share/pnpm
' >> /etc/profile
source /etc/profile
fi
fi
rm -rf node node.tar.xz > /dev/null
rm -rf node node.tar.xz > /dev/null
if [ ! -x "$(command -v pnpm)" ];then
    echo -e ${yellow}正在使用npm安装pnpm${background}
    a=0
    npm config set registry https://registry.npmmirror.com
    npm config set registry https://registry.npmmirror.com
    npm install -g npm@latest
    until npm install -g pnpm@latest
    do
      if [ "${a}" == "3" ];then
        echo -e ${red}错误次数过多 退出${background}
        exit
      fi
      echo -e ${red}pnpm安装失败 ${green}正在重试${background}
      a=$(($a+1))
    done
    echo
fi
echo -e ${yellow}正在为pnpm更换默认源${background}
pnpm config set registry https://registry.npmmirror.com
pnpm config set registry https://registry.npmmirror.com
pnpm config set node_sqlite3_binary_host_mirror https://npmmirror.com/mirrors/sqlite3
pnpm config set node_sqlite3_binary_host_mirror https://npmmirror.com/mirrors/sqlite3
