#!/bin/env bash
if ping -c 1 github.com > /dev/null 2>&1
then
  GitMirror="https://ghfast.top/"
  URL="https://gitee.com/Misaka21011/Yunzai-Bot-Shell/raw/master/Manage"
elif ping -c 1 github.com > /dev/null 2>&1
then
  GitMirror=""
  URL="https://raw.githubusercontent.com/misaka20002/Bot-Install-Shell/master/Manage"
fi

install_Bot(){
  if [ "${BotName}" == "Miao-Yunzai" ]
  then
    Git=${GitMirror}https://github.com/misaka20002/Miao-Yunzai.git
  elif [ "${BotName}" == "TRSS-Yunzai" ]
  then
     Git=${GitMirror}https://github.com/AIGC-Yunzai/TRSS-Yunzai-Lagrange.git
  fi
  echo -e ${cyan}正在克隆${BotName}${background}
  if ! git clone --depth=1 ${Git} $HOME/${BotName};then
    echo -e ${red}克隆失败${background}
    exit
  fi
}
install_Miao_Plugin(){
  echo -e ${cyan}正在克隆喵喵插件${background}
  Git=${GitMirror}https://github.com/yoimiya-kokomi/miao-plugin.git
  if ! git clone --depth=1 ${Git} $HOME/${BotName}/plugins/miao-plugin;then
    echo -e ${red}克隆失败${background}
    exit
  fi
}
install_Genshin(){
  echo -e ${cyan}正在克隆原神组件${background}
  Git=${GitMirror}https://github.com/Misaka20002/Yunzai-genshin
  if ! git clone --depth=1 ${Git} $HOME/${BotName}/plugins/genshin;then
    echo -e ${red}克隆失败${background}
    exit
  fi
}
if [ "${BotName}" == "Miao-Yunzai" ];then
    if [ ! -e $HOME/${BotName}/package.json ];then
        install_Bot
    fi
    if [ ! -e $HOME/${BotName}/plugins/miao-plugin/index.js ];then
        install_Miao_Plugin
    fi
    if [ ! -d $HOME/${BotName}/node_modules ];then
        cd $HOME/${BotName}
        bash <(curl -sL ${URL}/BOT-PACKAGE.sh)
    fi
elif [ "${BotName}" == "TRSS-Yunzai" ];then
    if [ ! -e $HOME/${BotName}/package.json ];then
        install_Bot
    fi
    if [ ! -e $HOME/${BotName}/plugins/miao-plugin/index.js ];then
        install_Miao_Plugin
    fi
    if [ ! -e $HOME/${BotName}/plugins/genshin/index.js ];then
        install_Genshin
    fi
    if [ ! -d $HOME/${BotName}/node_modules ];then
        cd $HOME/${BotName}
        bash <(curl -sL ${URL}/BOT-PACKAGE.sh)
    fi
fi