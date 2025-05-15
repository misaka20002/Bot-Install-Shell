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

URL="https://ipinfo.io"
Address=$(curl -sL ${URL} | sed -n 's/.*"country": "\(.*\)",.*/\1/p')
if [ "${Address}" = "CN" ]
then
  GithubMirror="https://github.moeyy.xyz/"
else
  GithubMirror=""
fi

LAGRANGE_URL=${GithubMirror}https://github.com/LagrangeDev/Lagrange.Core/releases/download/nightly/Lagrange.OneBot_linux-${ARCH}_net9.0_SelfContained.tar.gz
INSTALL_DIR=$HOME/Lagrange.OneBot
CONFIG_FILE=$INSTALL_DIR/appsettings.json

function tmux_new(){
Tmux_Name="$1"
Shell_Command="$2"
if ! tmux new -s ${Tmux_Name} -d "${Shell_Command}"
then
    echo -e ${yellow}Lagrange.OneBot启动错误"\n"错误原因:${red}${tmux_new_error}${background}
    echo
    echo -en ${yellow}回车返回${background};read
    main
    exit
fi
}

function tmux_attach(){
Tmux_Name="$1"
tmux attach -t ${Tmux_Name} > /dev/null 2>&1
}

function tmux_kill_session(){
Tmux_Name="$1"
tmux kill-session -t ${Tmux_Name}
}

function tmux_ls(){
Tmux_Name="$1"
tmux_windows=$(tmux ls 2>&1)
if echo ${tmux_windows} | grep -q ${Tmux_Name}
then
    return 0
else
    return 1
fi
}

function lagrange_curl(){
Port=2536
if curl -sL 127.0.0.1:${Port} > /dev/null 2>&1
then
    return 0
else
    return 1
fi
}

function tmux_gauge(){
i=0
Tmux_Name="$1"
tmux_ls ${Tmux_Name} & > /dev/null 2>&1
until lagrange_curl
do
    i=$((${i}+1))
    a="${a}#"
    echo -ne "\r${i}% ${a}\r"
    if [[ ${i} == 40 ]];then
        echo
        return 1
    fi
done
echo
}

bot_tmux_attach_log(){
Tmux_Name="$1"
if ! tmux attach -t ${Tmux_Name} > /dev/null 2>&1
then
    tmux_windows_attach_error=$(tmux attach -t ${Tmux_Name} 2>&1 > /dev/null)
    echo
    echo -e ${yellow}Lagrange.OneBot打开错误"\n"错误原因:${red}${tmux_windows_attach_error}${background}
    echo
    echo -en ${yellow}回车返回${background};read
fi
}

install_Lagrange(){
if [ -d $INSTALL_DIR ];then
  echo -e ${yellow}您已安装拉格朗日签名服务器${background}
  echo -en ${cyan}是否重新安装? [Y/n]${background};read yn
  case ${yn} in
  Y|y)
    rm -rf $INSTALL_DIR
    ;;
  *)
    return
    ;;
  esac
fi

if [ -e /etc/resolv.conf ]; then
  if ! grep -q "8.8.8.8" /etc/resolv.conf ;then
    cp -f /etc/resolv.conf /etc/resolv.conf.backup
    echo -e ${yellow}DNS已备份至 /etc/resolv.conf.backup${background}
    echo "nameserver 8.8.8.8" > /etc/resolv.conf
    echo -e ${yellow}DNS已修改为 8.8.8.8${background}
  fi
fi

if [ $(command -v apt) ];then
  apt update -y
  apt install -y tar gzip wget curl unzip git tmux pv jq
elif [ $(command -v yum) ];then
  yum makecache -y
  yum install -y tar gzip wget curl unzip git tmux pv jq
elif [ $(command -v dnf) ];then
  dnf makecache -y
  dnf install -y tar gzip wget curl unzip git tmux pv jq
elif [ $(command -v pacman) ];then
  pacman -Syy --noconfirm --needed tar gzip wget curl unzip git tmux pv jq
else
  echo -e ${red}不受支持的Linux发行版${background}
  exit
fi

mkdir -p $INSTALL_DIR

echo -e ${yellow}正在下载拉格朗日签名服务器...${background}
until wget -O lagrange.tar.gz -c ${LAGRANGE_URL}
do
  echo -e ${red}下载失败 ${green}正在重试${background}
done

echo -e ${yellow}正在解压文件,请耐心等候${background}
# 创建临时目录进行解压
TMP_DIR=$HOME/temp_lagrange
rm -rf $TMP_DIR
mkdir -p $TMP_DIR
pv lagrange.tar.gz | tar -zxf - -C $TMP_DIR

# 移动正确的文件到安装目录
echo -e ${yellow}正在移动可执行文件...${background}
if [ -f $TMP_DIR/Lagrange.OneBot/bin/Release/net9.0/linux-${ARCH}/publish/Lagrange.OneBot ]; then
    # 清空安装目录
    rm -rf $INSTALL_DIR/*
    
    # 复制所有文件到安装目录
    cp -r $TMP_DIR/Lagrange.OneBot/bin/Release/net9.0/linux-${ARCH}/publish/* $INSTALL_DIR/
    
    # 清理临时文件
    echo -e ${yellow}正在清理临时文件...${background}
    rm -f lagrange.tar.gz
    rm -rf $TMP_DIR
    
    chmod +x $INSTALL_DIR/Lagrange.OneBot
else
    echo -e ${red}未找到可执行文件，解压路径可能有变化${background}
    echo -e ${yellow}请检查解压后的文件结构${background}
    exit 1
fi

write_config

if [ ! "${install_Lagrange}" == "true" ]
then
    echo -en ${yellow}安装完成 是否启动?[Y/n]${background};read yn
    case ${yn} in
    Y|y)
    start_Lagrange
    ;;
    esac
fi
}

write_config(){
echo -e ${yellow}正在写入配置文件...${background}
cat > $CONFIG_FILE << EOF
{
    "\$schema": "https://raw.githubusercontent.com/LagrangeDev/Lagrange.Core/master/Lagrange.OneBot/Resources/appsettings_schema.json",
    "Logging": {
        "LogLevel": {
            "Default": "Information",
            "Microsoft": "Warning",
            "Microsoft.Hosting.Lifetime": "Information"
        }
    },
    "SignServerUrl": "https://sign.lagrangecore.org/api/sign/30366",
    "SignProxyUrl": "",
    "MusicSignServerUrl": "https://ss.xingzhige.com/music_card/card",
    "Account": {
        "Uin": 0,
        "Protocol": "Linux",
        "AutoReconnect": true,
        "GetOptimumServer": true
    },
    "Message": {
        "IgnoreSelf": true,
        "StringPost": false
    },
    "QrCode": {
        "ConsoleCompatibilityMode": false
    },
    "Implementations": [
        {
            "Type": "ReverseWebSocket",
            "Host": "127.0.0.1",
            "Port": 2536,
            "Suffix": "/OneBotv11",
            "ReconnectInterval": 5000,
            "HeartBeatInterval": 5000,
            "AccessToken": ""
        }
    ]
}
EOF
echo -e ${green}配置文件写入完成${background}
}

start_Lagrange(){
if tmux_ls lagrangebot > /dev/null 2>&1 
then
    echo -en ${yellow}拉格朗日签名服务器已启动 ${cyan}回车返回${background};read
    echo
    return
fi

Foreground_Start(){
export Boolean=true
while ${Boolean}
do 
  cd $INSTALL_DIR
  $INSTALL_DIR/Lagrange.OneBot
  echo -e ${red}拉格朗日签名服务器关闭 正在重启${background}
  sleep 2s
done
echo -en ${cyan}回车返回${background}
read
echo
}

Tmux_Start(){
Start_Stop_Restart="启动"
export Boolean=true
tmux_new lagrangebot "while ${Boolean}; do cd $INSTALL_DIR && $INSTALL_DIR/Lagrange.OneBot; echo -e ${red}拉格朗日签名服务器关闭 正在重启${background}; done"
echo
echo -e ${green}新手说明：${background}
echo -e ${cyan}1.首次启动需要打开窗口进行扫码登录；${background}
echo -e ${cyan}2.TMUX中让窗口进入后台运行的快捷键为: Ctrl+b d ${background}
echo -en ${green}${Start_Stop_Restart}成功 是否打开窗口 [Y/N]:${background}
read YN
case ${YN} in
Y|y)
    bot_tmux_attach_log lagrangebot
;;
*)
    echo -en ${cyan}回车返回${background}
    read
    echo
;;
esac
}

echo
echo -e ${white}"====="${green}呆毛版-拉格朗日签名服务器${white}"====="${background}
echo -e ${cyan}请选择启动方式${background}
echo -e  ${green}1.  ${cyan}前台启动（首次登陆）${background}
echo -e  ${green}2.  ${cyan}TMUX后台启动（推荐）${background}
echo "========================="
echo -en ${green}请输入您的选项: ${background};read num
case ${num} in 
1)
Foreground_Start
;;
2)
Tmux_Start
;;
*)
echo
echo -e ${red}输入错误${background}
exit
;;
esac
}

stop_Lagrange(){
if tmux_ls lagrangebot > /dev/null 2>&1 
then
    echo -e ${yellow}正在停止拉格朗日签名服务器${background}
    export Boolean=false
    tmux_kill_session lagrangebot > /dev/null 2>&1
    PID=$(ps aux | grep Lagrange.OneBot | sed '/grep/d' | awk '{print $2}')
    if ! [ -z ${PID} ];then
        kill ${PID}
    fi
    echo -en ${red}拉格朗日签名服务器停止成功 ${cyan}回车返回${background}
    read
    echo
    return
else
    echo -en ${red}拉格朗日签名服务器未启动 ${cyan}回车返回${background}
    read
    echo
    return
fi
}

restart_Lagrange(){
if tmux_ls lagrangebot > /dev/null 2>&1 
then
    tmux_kill_session lagrangebot
    export Start_Stop_Restart="重启"
    start_Lagrange
else
    echo -e ${red}拉格朗日签名服务器未启动${background}
    echo
    return
fi
}

update_Lagrange(){
if tmux_ls lagrangebot > /dev/null 2>&1 
then
    echo -e ${yellow}正在停止拉格朗日签名服务器${background}
    tmux_kill_session lagrangebot > /dev/null 2>&1
    PID=$(ps aux | grep Lagrange.OneBot | sed '/grep/d' | awk '{print $2}')
    if [ ! -z ${PID} ];then
        kill -9 ${PID}
    fi
    echo
fi

echo -e ${yellow}正在下载最新版本...${background}
rm -f lagrange.tar.gz
until wget -O lagrange.tar.gz -c ${LAGRANGE_URL}
do
  echo -e ${red}下载失败 ${green}正在重试${background}
done

echo -e ${yellow}正在备份配置文件...${background}
if [ -f $CONFIG_FILE ]; then
    cp $CONFIG_FILE $CONFIG_FILE.bak
fi

# 创建临时目录进行解压
TMP_DIR=$HOME/temp_lagrange
rm -rf $TMP_DIR
mkdir -p $TMP_DIR

echo -e ${yellow}正在解压文件,请耐心等候${background}
pv lagrange.tar.gz | tar -zxf - -C $TMP_DIR

# 删除特定文件和文件夹,保留其他文件
echo -e ${yellow}正在删除旧版本文件...${background}
rm -rf $INSTALL_DIR/lagrange-0-db
rm -f $INSTALL_DIR/Lagrange.OneBot

# 移动正确的文件到安装目录
echo -e ${yellow}正在移动可执行文件...${background}
if [ -f $TMP_DIR/Lagrange.OneBot/bin/Release/net9.0/linux-${ARCH}/publish/Lagrange.OneBot ]; then
    # 复制所有文件到安装目录,但不覆盖配置文件
    cp -r $TMP_DIR/Lagrange.OneBot/bin/Release/net9.0/linux-${ARCH}/publish/* $INSTALL_DIR/
    
    # 清理临时文件
    echo -e ${yellow}正在清理临时文件...${background}
    rm -f lagrange.tar.gz
    rm -rf $TMP_DIR
    
    chmod +x $INSTALL_DIR/Lagrange.OneBot
else
    echo -e ${red}未找到可执行文件，解压路径可能有变化${background}
    echo -e ${yellow}请检查解压后的文件结构${background}
    exit 1
fi

echo -e ${yellow}正在恢复配置文件...${background}
if [ -f $CONFIG_FILE.bak ]; then
    cp $CONFIG_FILE.bak $CONFIG_FILE
    rm -f $CONFIG_FILE.bak
else
    write_config
fi

echo -e ${green}更新完成${background}
echo -en ${yellow}是否启动服务器?[Y/n]${background};read yn
case ${yn} in
Y|y)
start_Lagrange
;;
esac
}

uninstall_Lagrange(){
if [ ! -d $INSTALL_DIR ];then
    echo -en ${red}您还没有部署拉格朗日签名服务器!!! ${cyan}回车返回${background};read
    return
fi

echo -e ${yellow}正在停止服务器运行${background}
tmux_kill_session lagrangebot > /dev/null 2>&1
PID=$(ps aux | grep Lagrange.OneBot | sed '/grep/d' | awk '{print $2}')
if [ ! -z ${PID} ];then
    kill -9 ${PID}
fi

echo -e ${yellow}正在删除核心文件...${background}
rm -rf $INSTALL_DIR/lagrange-0-db
rm -f $INSTALL_DIR/Lagrange.OneBot

echo -en ${yellow}是否保留配置文件? [Y/n]:${background};read keep_config
case ${keep_config} in
n|N)
    echo -e ${yellow}正在删除配置文件...${background}
    rm -f $CONFIG_FILE
    ;;
*)
    echo -e ${green}已保留配置文件${background}
    ;;
esac

echo -e ${green}卸载完成${background}
echo -en ${cyan}回车返回${background};read
}

log_Lagrange(){
if ! tmux_ls lagrangebot > /dev/null 2>&1 
then
    echo -en ${red}拉格朗日签名服务器 未启动 ${cyan}回车返回${background};read
    echo
    return
fi
bot_tmux_attach_log lagrangebot
}

change_lagrange_version(){
    echo -e ${white}"====="${green}呆毛版-拉格朗日签名版本${white}"====="${background}
    
    # 读取当前版本号
    current_url=$(grep -E "SignServerUrl" $CONFIG_FILE | sed 's/.*"SignServerUrl": "\(.*\)",/\1/')
    current_version=$(echo $current_url | sed -E 's/.*\/([0-9]+)$/\1/')
    
    echo -e ${cyan}当前签名版本: ${green}${current_version}${background}
    echo -e ${cyan}请选择签名服务器版本${background}
    echo -e  ${green} 1.  ${cyan}版本: 30366 \(lagrangecore.org\)${background}
    echo -e  ${green} 2.  ${cyan}版本: 25765 \(0w0.ing\)${background}
    echo "========================="
    echo -en ${green}请输入您的选项: ${background};read num
    
    case ${num} in
    1|30366)
        new_url="https://sign.lagrangecore.org/api/sign/30366"
        new_version="30366"
        ;;
    2|25765)
        new_url="https://sign.0w0.ing/api/sign/25765"
        new_version="25765"
        ;;
    *)
        echo -e ${red}输入错误${background}
        echo -en ${cyan}回车返回${background};read
        return
        ;;
    esac
    
    # 替换 SignServerUrl
    sed -i "s|\"SignServerUrl\": \".*\"|\"SignServerUrl\": \"$new_url\"|" $CONFIG_FILE
    
    echo -e ${green}签名版本已更改为: ${cyan}${new_version}${background}
    echo -en ${cyan}回车返回${background};read
}

manage_implementations(){
  if [ ! -f $CONFIG_FILE ]; then
    echo -e ${red}配置文件不存在，请先安装拉格朗日签名服务器${background}
    echo -en ${cyan}回车返回${background};read
    return
  fi

  # 备份配置文件
  cp $CONFIG_FILE $CONFIG_FILE.bak

  while true; do
    clear
    echo -e ${white}"====="${green}拉格朗日OneBot连接管理${white}"====="${background}
    echo -e ${cyan}当前已配置的连接：${background}
    
    # 显示当前配置的连接
    implementations=$(jq -r '.Implementations | length' $CONFIG_FILE)
    for (( i=0; i<$implementations; i++ )); do
      type=$(jq -r ".Implementations[$i].Type" $CONFIG_FILE)
      host=$(jq -r ".Implementations[$i].Host" $CONFIG_FILE)
      port=$(jq -r ".Implementations[$i].Port" $CONFIG_FILE)
      suffix=$(jq -r ".Implementations[$i].Suffix" $CONFIG_FILE)
      echo -e ${green}$((i+1)). ${yellow}类型: ${cyan}$type${background}
      echo -e ${yellow}  地址: ${cyan}$host:$port$suffix${background}
    done
    
    echo "========================="
    echo -e ${green}1. ${cyan}添加新连接${background}
    echo -e ${green}2. ${cyan}删除现有连接${background}
    echo -e ${green}0. ${cyan}返回${background}
    echo "========================="
    echo -en ${green}请输入您的选项: ${background};read option
    
    case $option in
      1)
        echo -e ${cyan}请选择连接类型:${background}
        echo -e ${green}1. ${cyan}WebSocket反向连接 \(ReverseWebSocket\) \(推荐\)${background}
        echo -e ${green}2. ${cyan}HTTP连接 \(Http\)${background}
        echo -e ${green}3. ${cyan}HTTP POST连接 \(HttpPost\)${background}
        echo -e ${green}4. ${cyan}WebSocket正向连接 \(ForwardWebSocket\)${background}
        echo -e ${green}0. ${cyan}取消${background}
        echo -en ${green}请输入选项: ${background};read type_option
        
        case $type_option in
          1) 
            conn_type="ReverseWebSocket"
            
            # 仅对ReverseWebSocket显示预设配置选项
            echo -e ${cyan}请选择配置方式:${background}
            echo -e ${green}1. ${cyan}默认trss配置: 127.0.0.1:2536/OneBotv11${background}
            echo -e ${green}2. ${cyan}默认lain配置: 127.0.0.1:2956/onebot/v11/ws${background}
            echo -e ${green}3. ${cyan}自定义配置${background}
            echo -e ${green}0. ${cyan}取消${background}
            echo -en ${green}请输入选项: ${background};read preset_option
            
            case $preset_option in
              1)
                host="127.0.0.1"
                port=2536
                suffix="/OneBotv11"
                reconnect=5000
                heartbeat=5000
                token=""
                ;;
              2)
                host="127.0.0.1"
                port=2956
                suffix="/onebot/v11/ws"
                reconnect=5000
                heartbeat=5000
                token=""
                ;;
              3)
                echo -en ${cyan}请输入主机地址 \(默认: 127.0.0.1\): ${background};read host
                host=${host:-127.0.0.1}
                
                echo -en ${cyan}请输入端口 \(默认: 2956\): ${background};read port
                port=${port:-2956}
                
                echo -en ${cyan}请输入路径后缀 \(默认: /onebot/v11/ws\): ${background};read suffix
                suffix=${suffix:-/onebot/v11/ws}
                
                echo -en ${cyan}请输入重连间隔\(ms\) \(默认: 5000\): ${background};read reconnect
                reconnect=${reconnect:-5000}
                
                echo -en ${cyan}请输入心跳间隔\(ms\) \(默认: 5000\): ${background};read heartbeat
                heartbeat=${heartbeat:-5000}
                
                echo -en ${cyan}请输入访问令牌 \(默认为空\): ${background};read token
                token=${token:-""}
                ;;
              0) continue ;;
              *)
                echo -e ${red}无效选项${background}
                sleep 2
                continue
                ;;
            esac
            ;;
          2) 
            conn_type="Http" 
            # 对Http类型进行自定义配置
            echo -en ${cyan}请输入主机地址 \(默认: 127.0.0.1\): ${background};read host
            host=${host:-127.0.0.1}
            
            echo -en ${cyan}请输入端口 \(默认: 2956\): ${background};read port
            port=${port:-2956}
            
            echo -en ${cyan}请输入访问令牌 \(默认为空\): ${background};read token
            token=${token:-""}
            ;;
          3) 
            conn_type="HttpPost" 
            # 对HttpPost类型进行自定义配置
            echo -en ${cyan}请输入主机地址 \(默认: 127.0.0.1\): ${background};read host
            host=${host:-127.0.0.1}
            
            echo -en ${cyan}请输入端口 \(默认: 2956\): ${background};read port
            port=${port:-2956}
            
            echo -en ${cyan}请输入路径后缀 \(默认: /onebot/v11/webhook\): ${background};read suffix
            suffix=${suffix:-/onebot/v11/webhook}
            
            echo -en ${cyan}请输入心跳间隔\(ms\) \(默认: 5000\): ${background};read heartbeat
            heartbeat=${heartbeat:-5000}
            
            echo -en ${cyan}请输入是否启用心跳 \(true/false\) \(默认: true\): ${background};read heart_enable
            if [ "$heart_enable" = "false" ]; then
              heartbeat_enable=false
            else
              heartbeat_enable=true
            fi
            
            echo -en ${cyan}请输入访问令牌 \(默认为空\): ${background};read token
            token=${token:-""}
            
            echo -en ${cyan}请输入Secret \(默认为空\): ${background};read secret
            secret=${secret:-""}
            ;;
          4) 
            conn_type="ForwardWebSocket" 
            # 对ForwardWebSocket类型进行自定义配置
            echo -en ${cyan}请输入主机地址 \(默认: 127.0.0.1\): ${background};read host
            host=${host:-127.0.0.1}
            
            echo -en ${cyan}请输入端口 \(默认: 2956\): ${background};read port
            port=${port:-2956}
            
            echo -en ${cyan}请输入心跳间隔\(ms\) \(默认: 5000\): ${background};read heartbeat
            heartbeat=${heartbeat:-5000}
            
            echo -en ${cyan}请输入是否启用心跳 \(true/false\) \(默认: true\): ${background};read heart_enable
            if [ "$heart_enable" = "false" ]; then
              heartbeat_enable=false
            else
              heartbeat_enable=true
            fi
            
            echo -en ${cyan}请输入访问令牌 \(默认为空\): ${background};read token
            token=${token:-""}
            ;;
          0) continue ;;
          *) 
            echo -e ${red}无效选项${background}
            sleep 2
            continue ;;
        esac
        
        # 根据不同类型添加不同的配置
        if [ -n "$host" ] && [ -n "$port" ]; then
          case $conn_type in
            "ReverseWebSocket")
              jq --arg type "$conn_type" \
                 --arg host "$host" \
                 --argjson port "$port" \
                 --arg suffix "$suffix" \
                 --argjson reconnect "$reconnect" \
                 --argjson heartbeat "$heartbeat" \
                 --arg token "$token" \
                 '.Implementations += [{"Type": $type, "Host": $host, "Port": $port, "Suffix": $suffix, "ReconnectInterval": $reconnect, "HeartBeatInterval": $heartbeat, "AccessToken": $token}]' \
                 $CONFIG_FILE > $CONFIG_FILE.tmp && mv $CONFIG_FILE.tmp $CONFIG_FILE
              ;;
            "Http")
              jq --arg type "$conn_type" \
                 --arg host "$host" \
                 --argjson port "$port" \
                 --arg token "$token" \
                 '.Implementations += [{"Type": $type, "Host": $host, "Port": $port, "AccessToken": $token}]' \
                 $CONFIG_FILE > $CONFIG_FILE.tmp && mv $CONFIG_FILE.tmp $CONFIG_FILE
              ;;
            "HttpPost")
              jq --arg type "$conn_type" \
                 --arg host "$host" \
                 --argjson port "$port" \
                 --arg suffix "$suffix" \
                 --argjson heartbeat "$heartbeat" \
                 --argjson heartbeat_enable "$heartbeat_enable" \
                 --arg token "$token" \
                 --arg secret "$secret" \
                 '.Implementations += [{"Type": $type, "Host": $host, "Port": $port, "Suffix": $suffix, "HeartBeatInterval": $heartbeat, "HeartBeatEnable": $heartbeat_enable, "AccessToken": $token, "Secret": $secret}]' \
                 $CONFIG_FILE > $CONFIG_FILE.tmp && mv $CONFIG_FILE.tmp $CONFIG_FILE
              ;;
            "ForwardWebSocket")
              jq --arg type "$conn_type" \
                 --arg host "$host" \
                 --argjson port "$port" \
                 --argjson heartbeat "$heartbeat" \
                 --argjson heartbeat_enable "$heartbeat_enable" \
                 --arg token "$token" \
                 '.Implementations += [{"Type": $type, "Host": $host, "Port": $port, "HeartBeatInterval": $heartbeat, "HeartBeatEnable": $heartbeat_enable, "AccessToken": $token}]' \
                 $CONFIG_FILE > $CONFIG_FILE.tmp && mv $CONFIG_FILE.tmp $CONFIG_FILE
              ;;
          esac
          
          echo -e ${green}成功添加新连接: ${cyan}$conn_type - $host:$port${background}
          sleep 2
        fi
        ;;
        
      2)
        if [ $implementations -eq 0 ]; then
          echo -e ${red}没有可删除的连接${background}
          sleep 2
          continue
        fi
        
        echo -en ${cyan}请输入要删除的连接编号 \(1-$implementations\): ${background};read del_num
        
        if ! [[ "$del_num" =~ ^[0-9]+$ ]] || [ $del_num -lt 1 ] || [ $del_num -gt $implementations ]; then
          echo -e ${red}无效的编号${background}
          sleep 2
          continue
        fi
        
        idx=$((del_num-1))
        host=$(jq -r ".Implementations[$idx].Host" $CONFIG_FILE)
        port=$(jq -r ".Implementations[$idx].Port" $CONFIG_FILE)
        suffix=$(jq -r ".Implementations[$idx].Suffix" $CONFIG_FILE)
        
        # 从配置中删除连接
        jq "del(.Implementations[$idx])" $CONFIG_FILE > $CONFIG_FILE.tmp && mv $CONFIG_FILE.tmp $CONFIG_FILE
        
        echo -e ${green}成功删除连接: ${cyan}$host:$port$suffix${background}
        sleep 2
        ;;
        
      0)
        return
        ;;
        
      *)
        echo -e ${red}无效选项${background}
        sleep 2
        ;;
    esac
  done
}

switch_account() {
  if [ ! -d $INSTALL_DIR ]; then
    echo -en ${red}您还没有部署拉格朗日签名服务器!!! ${cyan}回车返回${background};read
    return
  fi

  # 停止当前运行的服务
  if tmux_ls lagrangebot > /dev/null 2>&1; then
    echo -e ${yellow}正在停止拉格朗日签名服务器${background}
    tmux_kill_session lagrangebot > /dev/null 2>&1
    PID=$(ps aux | grep Lagrange.OneBot | sed '/grep/d' | awk '{print $2}')
    if [ ! -z ${PID} ]; then
      kill -9 ${PID}
    fi
  fi

  # 创建账号保存目录
  accounts_dir="$INSTALL_DIR/accounts"
  mkdir -p $accounts_dir
  
  # 询问用户要保存的文件夹名或QQ号
  echo -en ${cyan}请输入保存当前配置的文件夹名或QQ号\(留空则不保存\): ${background};read account_name
  
  if [ ! -z "$account_name" ]; then
    # 保存当前账号数据
    save_dir="$accounts_dir/$account_name"
    mkdir -p $save_dir
    
    echo -e ${yellow}正在保存当前账号数据...${background}
    
    # 拷贝相关文件到保存目录
    if [ -f "$INSTALL_DIR/device.json" ]; then
      cp "$INSTALL_DIR/device.json" "$save_dir/"
      echo -e ${green}已保存 device.json${background}
    fi
    
    if [ -f "$INSTALL_DIR/keystore.json" ]; then
      cp "$INSTALL_DIR/keystore.json" "$save_dir/"
      echo -e ${green}已保存 keystore.json${background}
    fi
    
    echo -e ${green}账号数据保存完成: ${yellow}$account_name${background}
  fi
  
  # 询问是否要切换到其他账号
  echo
  echo -e ${yellow}可用的账号列表:${background}
  
  # 列出所有保存的账号
  account_count=0
  for acc_dir in "$accounts_dir"/*; do
    if [ -d "$acc_dir" ];then
      acc_name=$(basename "$acc_dir")
      echo -e ${green}$((account_count+1)). ${cyan}$acc_name${background}
      account_count=$((account_count+1))
    fi
  done
  
  if [ $account_count -eq 0 ]; then
    echo -e ${yellow}没有找到保存的账号数据${background}
  fi
  
  echo -e ${green}0. ${cyan}全新登录${background}
  echo
  
  echo -en ${yellow}请选择要切换的账号\(输入编号\),或输入0重新登录: ${background};read switch_choice
  
  # 删除当前账号数据文件
  echo -e ${yellow}正在清除当前账号数据...${background}
  rm -f "$INSTALL_DIR/device.json"
  rm -f "$INSTALL_DIR/keystore.json"
  rm -rf "$INSTALL_DIR/lagrange-0-db"
  
  if [[ "$switch_choice" =~ ^[0-9]+$ ]] && [ $switch_choice -gt 0 ] && [ $switch_choice -le $account_count ]; then
    # 获取选择的账号名称
    selected_account=""
    count=0
    for acc_dir in "$accounts_dir"/*; do
      if [ -d "$acc_dir" ];then
        count=$((count+1))
        if [ $count -eq $switch_choice ]; then
          selected_account=$(basename "$acc_dir")
          break
        fi
      fi
    done
    
    if [ ! -z "$selected_account" ]; then
      echo -e ${yellow}正在恢复账号 ${cyan}$selected_account${yellow} 的数据...${background}
      
      # 恢复账号数据
      if [ -f "$accounts_dir/$selected_account/device.json" ]; then
        cp "$accounts_dir/$selected_account/device.json" "$INSTALL_DIR/"
        echo -e ${green}已恢复 device.json${background}
      fi
      
      if [ -f "$accounts_dir/$selected_account/keystore.json" ]; then
        cp "$accounts_dir/$selected_account/keystore.json" "$INSTALL_DIR/"
        echo -e ${green}已恢复 keystore.json${background}
      fi
      
      echo -e ${green}账号数据恢复完成${background}
    fi
  else
    echo -e ${yellow}将使用全新账号登录${background}
  fi
  
  # 前台启动
  echo -e ${yellow}启动前台模式进行登录...${background}
  echo -e ${cyan}提示: 登录完成后，可以按 Ctrl+C 退出，然后使用后台模式重新启动${background}
  sleep 2
  
  # 前台启动
  cd $INSTALL_DIR
  $INSTALL_DIR/Lagrange.OneBot
  
  echo -en ${cyan}登录操作已完成，按回车返回主菜单${background};read
}

main(){
if [ -d $INSTALL_DIR ];then
    if tmux_ls lagrangebot > /dev/null 2>&1 
    then
        condition="${green}[已启动]"
    else
        condition="${red}[未启动]"
    fi
else
    condition="${red}[未部署]"
fi

echo -e ${white}"====="${green}呆毛版-拉格朗日签名服务器${white}"====="${background}
echo -e  ${green} 1.  ${cyan}安装Lagrange${background}
echo -e  ${green} 2.  ${cyan}启动Lagrange${background}
echo -e  ${green} 3.  ${cyan}关闭Lagrange${background}
echo -e  ${green} 4.  ${cyan}重启Lagrange${background}
echo -e  ${green} 5.  ${cyan}更新Lagrange${background}
echo -e  ${green} 6.  ${cyan}卸载Lagrange${background}
echo -e  ${green} 7.  ${cyan}查看日志${background}
echo -e  ${green} 8.  ${cyan}重写签名配置${background}
echo -e  ${green} 9.  ${cyan}更换签名版本${background}
echo -e  ${green} 10. ${cyan}管理OneBot连接配置${background}
echo -e  ${green} 11. ${cyan}切换并备份QQ账号${background}
echo -e  ${green} 0.  ${cyan}退出${background}
echo "========================="
echo -e ${green}拉格朗日状态: ${condition}${background}
echo -e ${green}说明: ${cyan}安装后“管理OneBot连接配置”（已默认配置trss连接），启动-扫码登录-转后台运行，启动TRSS即可。${background}
echo -e ${green}呆毛版-QQ群: ${cyan}285744328${background}
echo "========================="
echo
echo -en ${green}请输入您的选项: ${background};read number
case ${number} in
1)
echo
install_Lagrange
;;
2)
echo
start_Lagrange
;;
3)
echo
stop_Lagrange
;;
4)
echo
restart_Lagrange
;;
5)
echo
update_Lagrange
;;
6)
echo
uninstall_Lagrange
;;
7)
log_Lagrange
;;
8)
echo
write_config
echo -en ${cyan}回车返回${background};read
;;
9)
echo
change_lagrange_version
;;
10)
echo
manage_implementations
;;
11)
echo
switch_account
;;
0)
exit
;;
*)
echo
echo -e ${red}输入错误${background}
exit
;;
esac
}

function mainbak()
{
    while true
    do
        main
        mainbak
    done
}
mainbak
