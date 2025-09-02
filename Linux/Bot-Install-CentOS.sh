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

echo -e ${red}暂时放弃对centos的支持${background}
exit

if [ $(command -v dnf) ];then
    pkg_install="dnf"
elif [ $(command -v yum) ];then
    pkg_install="yum"
fi

bash <(curl -sL ${GitMirror}/raw/master/Manage/BOT-PKG.sh)

if ! ${pkg_install} list installed xz >/dev/null 2>&1
    then
        echo -e ${yellow}安装xz解压工具${background}
        until ${pkg_install} install -y xz
        do
            echo -e ${red}安装失败 3秒后重试${background}
            sleep 3s
        done
fi

if ! ${pkg_install} list installed chromium >/dev/null 2>&1
    then
        echo -e ${yellow}安装chromium浏览器${background}
        until ${pkg_install} install -y chromium
        do
            echo -e ${red}安装失败 3秒后重试${background}
            sleep 3s
        done    
fi

if ! ${pkg_install} list installed fonts >/dev/null 2>&1
    then
        echo -e ${yellow}安装中文字体${background}
        until ${pkg_install} groupinstall -y fonts
        do
            echo -e ${red}安装失败 3秒后重试${background}
            sleep 3s
        done    
fi

if [ -x "$(command -v node)" ]
then
    Nodsjs_Version=$(node -v | cut -d '.' -f1)
fi

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

function node_install(){
if [ "${GitMirror}" == "gitee.com" ]
then
    WebURL="https://registry.npmmirror.com/-/binary/node/latest-${version1}.x/"
    version3=$(curl -s ${WebURL} | grep -o '"name":"node-'${version2}'[^"]*-linux-'${ARCH}'.tar.xz"' | grep -o 'node-[^"]*' | head -n 1)
    if [ -z "$version3" ]; then
        # 如果没有找到精确版本，获取同系列最新版本
        version3=$(curl -s ${WebURL} | grep -o '"name":"node-v'$(echo ${version2} | cut -d'.' -f1-2)'[^"]*-linux-'${ARCH}'.tar.xz"' | grep -o 'node-[^"]*' | sort -V | tail -n 1)
    fi
    NodeJS_URL="${WebURL}${version3}"
elif [ "${GitMirror}" == "github.com" ]
then
    WebURL="https://nodejs.org/dist/latest-${version1}.x/"
    version3=$(curl ${WebURL} | grep ${version2} | grep -oP 'href=\K[^ ]+' | awk -F'"' '{print $2}' | grep pkg  | sed 's|node-||g' | sed 's|.pkg||g')
    NodeJS_URL="https://nodejs.org/dist/latest-${version1}.x/node-${version3}-linux-${ARCH}.tar.xz"
fi
until wget -O node.tar.xz -c ${NodeJS_URL}
do
    if [[ ${i} -eq 3 ]]
    then
        echo -e ${red}错误次数过多 退出${background}
        exit
    fi
    i=$((${i}+1))
    echo -e ${red}安装失败 3秒后重试${background}
    sleep 3s
done
}

if ! [[ "$Nodsjs_Version" == "v16" || "$Nodsjs_Version" == "v18" || "$Nodsjs_Version" == "v19" || "$Nodsjs_Version" == "v20" || "$Nodsjs_Version" == "v21"|| "$Nodsjs_Version" == "v22"|| "$Nodsjs_Version" == "v23"|| "$Nodsjs_Version" == "v24" || "$Nodsjs_Version" == "v25" ]];then
    echo -e ${yellow}安装软件 Node.JS${background}
        version1=v23
        version2=v23.11
        node_install
fi