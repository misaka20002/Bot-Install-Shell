cd $HOME
export red="\033[31m"
export green="\033[32m"
export yellow="\033[33m"
export blue="\033[34m"
export purple="\033[35m"
export cyan="\033[36m"
export white="\033[37m"
export background="\033[0m"

if [ -d /usr/local/node/bin ];then
    PATH=$PATH:/usr/local/node/bin
    if [ ! -d $HOME/.local/share/pnpm ];then
        mkdir -p $HOME/.local/share/pnpm
    fi
    PATH=$PATH:/root/.local/share/pnpm
    PNPM_HOME=/root/.local/share/pnpm
fi
##############################
if [ -x "$(command -v whiptail)" ];then
    DialogWhiptail=whiptail
elif [ -x "$(command -v dialog)" ];then
    DialogWhiptail=dialog
fi
##############################
function BotPathCheck(){
if [ -d "/root/${BotName}/node_modules" ];then
    BotPath="/root/${BotName}"
    return 0
elif [ -d "/root/.fox@bot/${BotName}/node_modules" ];then
    BotPath="/root/.fox@bot/${BotName}"
    return 0
elif [ -d "/home/lighthouse/ubuntu/${BotName}/node_modules" ];then
    BotPath="/home/lighthouse/ubuntu/${BotName}"
    return 0
elif [ -d "/home/lighthouse/centos/${BotName}/node_modules" ];then
    BotPath="/home/lighthouse/centos/${BotName}"
    return 0
elif [ -d "/home/lighthouse/debian/${BotName}/node_modules" ];then
    BotPath="/home/lighthouse/debian/${BotName}"
    return 0
elif [ -d "/root/TRSS_AllBot/${BotName}/node_modules" ];then
    BotPath="/root/TRSS_AllBot/${BotName}"
    return 0
elif [ -d "${BotPath}" ];then
    echo -e ${cyan}自定义路径: ${BotPath} ${green}判断通过${background}
    return 0
else
    return 1
fi
}
function MirrorCheck(){
URL="https://ipinfo.io"
# 设置超时时间为10秒，如果连接失败或超时则使用备用镜像
Address=$(timeout 5 curl -sL ${URL} 2>/dev/null | sed -n 's/.*"country": "\(.*\)",.*/\1/p')

# 检查curl命令是否成功执行且返回了有效的国家代码
if [ $? -eq 0 ] && [ ! -z "${Address}" ] && [ "${Address}" = "CN" ]
then
    # echo -e ${cyan}检测到中国大陆地区，使用国内镜像源${background}
    export GitMirror="https://gitee.com/Misaka21011/Yunzai-Bot-Shell"
    export Git_proxy="https://ghfast.top/"
elif [ $? -eq 0 ] && [ ! -z "${Address}" ] && [ "${Address}" != "CN" ]
then
    # echo -e ${cyan}检测到海外地区，使用GitHub源${background}
    export GitMirror="https://github.com/misaka20002/Bot-Install-Shell"
    export Git_proxy=""
else
    # 连接失败、超时或返回空值时使用备用镜像
    # echo -e ${yellow}网络检测失败或超时，使用备用镜像源${background}
    export GitMirror="https://gitee.com/Misaka21011/Yunzai-Bot-Shell"
    export Git_proxy="https://ghfast.top/"
fi
}
##############################
Runing(){
if $(pnpm pm2 show ${BotName} 2>&1 | grep -q online)
then
  echo -e ${red}程序进入后台运行 ${cyan}正在转为前台${background}
  pnpm pm2 stop ${BotName}
  pnpm pm2 delete ${BotName}
  node app
  Runing
fi
}
RedisServerStart(){
PedisCliPing(){
if [ "$(redis-cli ping 2>&1)" == "PONG" ]
then
  return 0
else
  return 1
fi
}
if $(PedisCliPing)
then
  echo -e ${cyan}Redis-Server${green} 已启动${background}
else
  $(nohup redis-server > /dev/null 2>&1 &)
  echo -e ${cyan}等待Redis-Server启动中${background}
  until PedisCliPing
  do
    sleep 0.5s
  done
  echo -e ${cyan}Redis-Server${green} 启动成功${background}
fi
}
function TmuxLs(){
Tmux_Name="$1"
TmuxWindows=$(tmux ls 2>&1)
if echo ${TmuxWindows} | grep -q ${Tmux_Name}
then
    return 0
else
    return 1
fi
}

function backmain(){
echo
echo -en ${cyan}回车返回${background}
read
main
exit
}

function help(){
echo -e ${green}===============================${background}
echo -e ${yellow}"         "快捷方式${cyan}${background}
echo -e ${green}===============================${background}
echo -e ${cyan} xdm"        | "${blue}呆毛版脚本入口${background}
# echo -e ${cyan} xdm help"   | "${blue}呆毛版脚本帮助${background}
echo -e ${cyan} xdm lag"    | "${blue}拉格朗日脚本${background}
echo -e ${cyan} xdm nap"    | "${blue}NapCat 脚本${background}
echo -e ${cyan} xdm plugin" | "${blue}插件管理脚本${background}
echo -e ${cyan} xdm meme"   | "${blue}meme 管理脚本${background}
echo -e ${green}===============================${background}
echo -e ${cyan} xdm mz ${blue}Miao-Yunzai根目录${background}
echo -e ${cyan} xdm tz ${blue}TRSS-Yunzai根目录${background}
echo -e ${green}===============================${background}
echo -e ${yellow} Bot-Shell ${cyan}呆毛版-QQ群: 285744328${background}
echo -e ${green}=============================${background}
}
case $1 in
help)
help
exit
;;
plugin)
MirrorCheck
bash <(curl -sL ${Git_proxy}https://raw.githubusercontent.com/misaka20002/yunzai-LoliconAPI-paimonV2/main/psign/PaimonPluginsManage.sh)
exit
;;
meme)
MirrorCheck
URL="${GitMirror}/raw/master/Manage"
bash <(curl -sL ${URL}/meme_generator.sh)
exit
;;
SWPKG)
MirrorCheck
URL="${GitMirror}/raw/master/Manage"
bash <(curl -sL ${URL}/BOT_INSTALL.sh)
exit
;;
lag)
MirrorCheck
URL="${GitMirror}/raw/master/Manage"
bash <(curl -sL ${URL}/Lagrange_OneBot.sh)
exit
;;
nap)
MirrorCheck
URL="${GitMirror}/raw/master/Manage"
bash <(curl -sL ${URL}/NapCat.sh)
exit
;;
YZ|Yunzai|Yunzai-Bot)
if [ -z "${Bot_Name}" ]; then
    Bot_Name=Yunzai-Bot
    Quick_Command="true"
fi
BotPathCheck
cd ${BotPath}
;;
MZ|Miao-Yunzai)
if [ -z "${BotName}" ]; then
    BotName=Miao-Yunzai
    Quick_Command="true"
fi
BotPathCheck
cd ${BotPath}
;;
TZ|TRSS-Yunzai)
if [ -z "${BotName}" ]; then
    BotName=TRSS-Yunzai
    Quick_Command="true"
fi
BotPathCheck
cd ${BotPath}
;;
yz)
if [ -z "${BotName}" ]; then
    BotName=Yunzai-Bot
fi
BotPathCheck
cd ${BotPath} && exec bash -i
exit
;;
mz)
if [ -z "${BotName}" ]; then
    BotName=Miao-Yunzai
fi
BotPathCheck
cd ${BotPath} && exec bash -i
exit
;;
tz)
if [ -z "${BotName}" ]; then
    BotName=TRSS-Yunzai
fi
BotPathCheck
cd ${BotPath} && exec bash -i
exit
;;
help)
help
exit
;;
unup)
export up="false"
;;
esac

case $2 in
n)
RedisServerStart
node app
Runing
;;
esac
##############################
function UPDATE(){
    version_date=$(curl -sL ${VersionURL})
    new_version="$(echo "${version_date}" | grep 'version:' | awk '{print $2}')"
    help_message="$(echo "${version_date}" | grep 'help:' | sed 's/help: //')"
    
    if [ "${new_version}" != "${old_version}" ];then
        echo -e ${cyan}正在更新${background}
        curl -o xdm ${URL}
        
        if bash xdm help; then
            if [ -f "/usr/local/bin/bh" ]; then
                rm -f /usr/local/bin/bh
            fi
            rm -f /usr/local/bin/xdm
            mv xdm /usr/local/bin/xdm
            chmod +x /usr/local/bin/xdm
            echo -en "${cyan}版本${new_version} 更新完成 ${help_message}${background}";read
            exit
        else
            echo -en "${red}版本${new_version} 更新出现错误 跳过更新 ${help_message} ${cyan}回车继续${background}";read
            rm xdm
        fi
    fi
}
old_version="1.1.60"
if ping -c 1 gitee.com > /dev/null 2>&1
then
  VersionURL="https://gitee.com/Misaka21011/Yunzai-Bot-Shell/raw/master/version"
  URL="https://gitee.com/Misaka21011/Yunzai-Bot-Shell/raw/master/Manage/Main.sh"
  UPDATE
elif ping -c 1 github.com > /dev/null 2>&1
then
  VersionURL="https://github.com/misaka20002/Bot-Install-Shell/raw/master/version"
  URL="https://github.com/misaka20002/Bot-Install-Shell/raw/master/Manage/Main.sh"
  UPDATE
fi
##############################
function feedback(){
if [ ! ${feedback} == "0" ];then
    exit
fi
}
function Main(){
RunningState(){
if TmuxLs ${TmuxName}
then
    return 1
elif ps all | sed /grep/d | grep -q "${BOT_COMMAND}"
then
    return 2
elif pnpm pm2 show ${BotName} 2>&1 | grep -q online
then
    return 3
else
    return 0
fi
}
ProgressBar(){
RunningState="$1"
start(){
until $(! RunningState)
do
  i=$((${i}+1))
  sleep 0.05s
  echo -e ${i}
  if [[ "${i}" == "100" ]];then
    echo -e "错误: 启动失败\n错误原因: $(node )"
    backmain
    return 1
  fi
done | ${DialogWhiptail} --title "呆毛版-script" \
--gauge "正在${RunningState}${BotName}" 8 50 0
return 0
}
if start
then
  AttachPage "在TMUX窗口启动" "窗口"
fi
}
TmuxAttach(){
#echo $TmuxName
if ! tmux attach -t ${TmuxName} > /dev/null 2>&1
then
  error=$(tmux attach -t ${TmuxName} 2>&1)
  ${DialogWhiptail} --title "呆毛版-Script" --msgbox "窗口打开错误\n原因: ${error}" 10 60
fi
}
AttachPage(){
RunningState="$1"
TWPL="$2"
RunningState
res=$?
if (${DialogWhiptail} --yesno "${BotName} [已"${RunningState}"] \n是否打开${BotName}${TWPL}" 8 50)
then
  if [ ${res} -eq 1 ];then
    TmuxAttach
  elif [ ${res} -eq 2 ];then
      ${DialogWhiptail} --title "呆毛版-Script" --msgbox "${BotName}已在前台运行" 10 60
  elif [ ${res} -eq 3 ];then
    pnpm pm2 log ${BotName}
  fi
fi
}

BOT(){
case $1 in
  start)
    RunningState
    res="$?"
    if [ ${res} -eq 1 ];then
      AttachPage "在TMUX窗口启动" "窗口"
    elif [ ${res} -eq 2 ];then
      ${DialogWhiptail} --title "呆毛版-Script" --msgbox "${BotName}已在前台运行" 10 60
    elif [ ${res} -eq 3 ];then
      AttachPage "在Pm2后台启动" "日志"
    else
      # 添加选择启动方式的对话框
      start_option=$(${DialogWhiptail} --title "呆毛版-Script" \
      --menu "请选择启动方式" 10 50 2 \
      "1" "在TMUX窗口启动" \
      "2" "在Pm2后台启动" \
      3>&1 1>&2 2>&3)
      
      case ${start_option} in
        1)
          if tmux new -s ${TmuxName} -d "xdm ${BotName} n"
          then
            ProgressBar "启动"
          else
            ${DialogWhiptail} --title "呆毛版-Script" --msgbox "${BotName} 启动失败" 10 60
          fi
          ;;
        2)
          pnpm pm2 stop ${BotName}
          pnpm pm2 delete ${BotName}
          RedisServerStart
          pnpm pm2 start
          if pnpm pm2 show ${BotName} 2>&1 | grep -q online
          then
            AttachPage "在Pm2后台启动" "日志"
          else
            ${DialogWhiptail} --title "呆毛版-Script" --msgbox "${BotName} 启动失败" 10 60
          fi
          ;;
        *)
          ${DialogWhiptail} --title "呆毛版-Script" --msgbox "已取消启动" 10 60
          ;;
      esac
    fi
    ;;
  ForegroundStart)
    RunningState
    res="$?"
    if [ ${res} -eq 1 ];then
      AttachPage "在TMUX窗口启动" "窗口"
    elif [ ${res} -eq 2 ];then
      ${DialogWhiptail} --title "呆毛版-Script" --msgbox "${BotName}已在前台运行" 10 60
    elif [ ${res} -eq 3 ];then
      AttachPage "在Pm2后台启动" "日志"
    else
      RedisServerStart
      node app
      Runing
    fi
    ;;
  stop)
    RunningState
    res="$?"
    if [ ${res} -eq 1 ];then
      if tmux kill-session -t ${TmuxName}
      then
        ${DialogWhiptail} --title "呆毛版-Script" --msgbox "停止成功" 10 60
      else
        ${DialogWhiptail} --title "呆毛版-Script" --msgbox "停止失败" 10 60
      fi
    elif [ ${res} -eq 2 ];then
      pnpm pm2 stop ${BotName}
      pnpm pm2 delete ${BotName}
      ${DialogWhiptail} --title "呆毛版-Script" --msgbox "停止成功" 10 60
    elif [ ${res} -eq 3 ];then
      PIDS=$(ps -ef | grep "${BOT_COMMAND}" | grep -v grep | awk '{print $2}')
      if [ -n "${PIDS}" ] && kill ${PIDS}
      then
        ${DialogWhiptail} --title "呆毛版-Script" --msgbox "停止成功" 10 60
      else
        ${DialogWhiptail} --title "呆毛版-Script" --msgbox "停止失败" 10 60
      fi
    else
      ${DialogWhiptail} --title "呆毛版-Script" --msgbox "${BotName} [未启动]" 10 60
    fi
    ;;
  restart)
    RunningState
    res="$?"
    if [ ${res} -eq 1 ];then
      if tmux kill-session -t ${TmuxName}
      then
        tmux new -s ${TmuxName} -d "xdm ${BotName} n"
        ProgressBar "启动"
        ${DialogWhiptail} --title "呆毛版-Script" --msgbox "重启成功" 10 60
      fi
    elif [ ${res} -eq 2 ];then
      pnpm pm2 stop ${BotName}
      pnpm pm2 delete ${BotName}
      RedisServerStart
      pnpm pm2 start
      ${DialogWhiptail} --title "呆毛版-Script" --msgbox "重启成功" 10 60
    elif [ ${res} -eq 3 ];then
      if kill $(ps all | sed /grep/d | grep -q "${BOT_COMMAND}")
      then
        xdm ${BotName} n
      fi
    else
      ${DialogWhiptail} --title "呆毛版-Script" --msgbox "${BotName} [未启动]" 10 60
    fi
    ;;
  log)
    RunningState
    res="$?"
    if [ ${res} -eq 1 ];then
      TmuxAttach
    elif [ ${res} -eq 2 ];then
      ${DialogWhiptail} --title "呆毛版-Script" --msgbox "${BotName} [前台运行]\n无法打开日志" 10 60
    elif [ ${res} -eq 3 ];then
      pnpm pm2 log ${BotName}
    else
      ${DialogWhiptail} --title "呆毛版-Script" --msgbox "${BotName} [未运行]" 10 60
    fi
    ;;
  plugin_1)
        bash <(curl -sL https://mirrors.chenby.cn/https://raw.githubusercontent.com/misaka20002/yunzai-LoliconAPI-paimonV2/main/psign/PaimonPluginsManage.sh)
        # bash <(curl -sL https://github.moeyy.xyz/https://raw.githubusercontent.com/misaka20002/yunzai-LoliconAPI-paimonV2/main/psign/PaimonPluginsManage.sh)
    ;;
  plugin_2)
        bash <(curl -sL https://ghfast.top/https://raw.githubusercontent.com/misaka20002/yunzai-LoliconAPI-paimonV2/main/psign/PaimonPluginsManage.sh)
    ;;
esac
}
GitUpdate(){
cd ${BotPath}
git_pull(){
echo -e ${yellow}正在更新 ${Name}${background}
if ! git pull -f
then
    echo -en ${red}${Name}更新失败 ${yellow}是否强制更新 [Y/N]${background};read YN
    case ${YN} in
    Y|y)
        remote=$(grep 'remote =' .git/config | sed 's/remote =//g')
        remote=$(echo ${remote})
        branch=$(grep branch .git/config | sed "s/\[branch \"//g" | sed 's/"//g' | sed "s/\]//g")
        branch=$(echo ${branch})
        git fetch --all
        git reset --hard ${remote}/${branch}
        git_pull
    esac
fi
}
Name=${BotName}
git_pull
for folder in $(ls plugins)
do
    if [ -d plugins/${folder}/.git ];then
        cd plugins/${folder}
        Name=${folder}
        git_pull
        cd ../../
    fi
done
echo -e ${yellow}正在更新NPM${background}
npm install -g npm@latest
echo -e ${yellow}正在更新PNPM${background}
pnpm install -g pnpm@latest
echo -en ${cyan}更新完成 回车返回${background};read
}

QSignAPIChange(){
if [ ${BotName} == "TRSS-Yunzai" ];then
    echo -e ${cyan}TRSS崽推荐使用 拉格朗日 或 NapCat 连接QQ； ${background}
    echo -e ${cyan}若打算继续使用ICQQ则前台启动后使用 ${yellow}"#QQ签名 + 签名服务器地址" ${background}
    echo -en ${cyan}回车返回${background};read
    return
fi
echo -e ${white}"====="${green}呆毛版-QSign${white}"====="${background}
echo -e ${green}1. 修改签名服务器链接${background}
echo -e ${green}2. 修改QQ版本号${background}
echo -en ${green}请选择要修改的内容 \(输入数字\): ${background};read choice

file=config/config/bot.yaml

if [ "$choice" == "1" ]; then
    echo -e ${green}请输入您的新签名服务器链接: ${background};read API
    old_sign_api_addr=$(grep sign_api_addr ${file})
    new_sign_api_addr="sign_api_addr: ${API}"
    sed -i "s|${old_sign_api_addr}|${new_sign_api_addr}|g" ${file}
    API=$(grep sign_api_addr ${file})
    API=$(echo ${API} | sed "s/sign_api_addr: //g")
    echo -e ${cyan}您的API链接已修改为:${green}${API}${background}
elif [ "$choice" == "2" ]; then
    echo -e ${green}请输入您的新QQ版本号 \(例如: 9.1.50\): ${background};read VER
    old_ver=$(grep "ver:" ${file})
    new_ver="ver: ${VER}"
    sed -i "s|${old_ver}|${new_ver}|g" ${file}
    VER=$(grep "ver:" ${file})
    VER=$(echo ${VER} | sed "s/ver: //g")
    echo -e ${cyan}您的QQ版本号已修改为:${green}${VER}${background}
else
    echo -e ${red}无效的选择，请重试${background}
fi

echo
echo -en ${cyan}回车返回${background};read
}

function OperatingEnvironmentInstall(){
  echo -e ${yellow}"确认要重新安装环境吗? 这将重新安装以下依赖( ffmpeg, gzip, redis, tmux, chromium, fonts-wqy-zenhei, node.JS ... ) [y/n]"${background}
  read -p "" confirm
  case ${confirm} in
    y|Y)
      echo -e ${cyan}"开始重新安装环境..."${background}
      ;;
    n|N)
      echo -e ${cyan}"已取消重新安装环境"${background}
      Main
      return
      ;;
    *)
      echo -e ${red}"无效的输入，请输入 y 或 n"${background}
      Main
      return
      ;;
  esac
  BotPathCheck

  case $(uname -m) in
      x86_64|amd64)
      export ARCH=x64
  ;;
      arm64|aarch64)
      export ARCH=arm64
  ;;
  *)
      echo ${red}您的框架为${yellow}$(uname -m)${red},快提issue做适配.${background}
      exit
  ;;
  esac

    if sudo rm -f /usr/local/bin/ffmpeg; then
      echo -e ${green}"Successfully removed /usr/local/bin/ffmpeg"${background}
    else
      echo -e ${red}"Failed to remove /usr/local/bin/ffmpeg"${background}
      echo -e ${yellow}"You may need to manually remove it later"${background}
    fi

  command_all="BOT-PKG.sh BOT_INSTALL.sh BOT-NODE.JS.sh"
  i=1
  if ping -c 1 gitee.com > /dev/null 2>&1
  then
    URL="https://gitee.com/Misaka21011/Yunzai-Bot-Shell/raw/master/Manage"
  elif ping -c 1 github.com > /dev/null 2>&1
  then
    URL="https://github.com/misaka20002/Bot-Install-Shell/raw/master/Manage"
  fi
  for command in ${command_all}
  do
    echo 执行url: ${URL}/${command}
    until bash <(curl -sL ${URL}/${command})
    do
      if [ ${i} -eq 3 ]
      then
        echo -e ${red}错误次数过多 退出${background}
        exit
      fi
      i=$((${i}+1))
      echo -en ${red}命令执行失败 ${green}3秒后重试${background}
      sleep 3s
      echo
    done
  done
  Main
}

Number=$(${DialogWhiptail} \
--title "呆毛版 QQ群:285744328" \
--menu "${BotName}管理" \
23 35 15 \
"1" "启动运行" \
"2" "前台启动" \
"3" "停止运行" \
"4" "重新启动" \
"5" "打开日志" \
"6.1" "插件管理_反代1" \
"6.2" "插件管理_反代2" \
"7" "全部更新" \
"8" "填写签名" \
"9" "重装ffmpeg等环境" \
"10" "其他功能" \
"0" "返回" \
3>&1 1>&2 2>&3)
feedback=$?
feedback
case ${Number} in
    1)
        BOT start
        ;;
    2)
        BOT ForegroundStart
        ;;
    3)
        BOT stop
        ;;
    4)
        BOT restart
        ;;
    5)
        BOT log
        ;;
    6.1)
        BOT plugin_1
        ;;
    6.2)
        BOT plugin_2
        ;;
    7)
        GitUpdate
        ;;
    8)
        QSignAPIChange
        ;;
    9)
        OperatingEnvironmentInstall
        ;;
    10)
        MirrorCheck
        bash <(curl -sL ${GitMirror}/raw/master/Manage/OtherFunctions.sh)
        ;;
    0)
        return
        ;;
esac
}
function BotInstall(){
case $(uname -m) in
    x86_64|amd64)
    export ARCH=x64
;;
    arm64|aarch64)
    export ARCH=arm64
;;
*)
    echo ${red}您的框架为${yellow}$(uname -m)${red},快提issue做适配.${background}
    exit
;;
esac
command_all="BOT-PKG.sh BOT_INSTALL.sh BOT-NODE.JS.sh GitBot.sh"
i=1
if ping -c 1 gitee.com > /dev/null 2>&1
then
  URL="https://gitee.com/Misaka21011/Yunzai-Bot-Shell/raw/master/Manage"
elif ping -c 1 github.com > /dev/null 2>&1
then
  URL="https://github.com/misaka20002/Bot-Install-Shell/raw/master/Manage"
fi
for command in ${command_all}
do
  echo 执行url: ${URL}/${command}
  until bash <(curl -sL ${URL}/${command})
  do
    if [ ${i} -eq 3 ]
    then
      echo -e ${red}错误次数过多 退出${background}
      exit
    fi
    i=$((${i}+1))
    echo -en ${red}命令执行失败 ${green}3秒后重试${background}
    sleep 3s
    echo
  done
done
BotPath
}
function BotPath(){
    if BotPathCheck
    then
        cd ${BotPath}
        Main
    else
        if ${DialogWhiptail} --title "呆毛版-Bot" \
        --yesno "${BotName}未安装 是否安装 ${BotName}" \
        8 50
        then
            BotInstall
        fi
    fi
}
function master(){
Number=$(${DialogWhiptail} \
--title "呆毛版 QQ群:285744328" \
--menu "💡 提示: 发送 xdm help 获取更多快捷键" \
20 38 10 \
"1" "Miao-Yunzai" \
"2" "TRSS-Yunzai" \
"3" "拉格朗日管理" \
"4" "NapCat管理" \
"5" "部署meme服务器" \
"6" "系统管理" \
"0" "退出" \
3>&1 1>&2 2>&3)
feedback=$?
feedback
case ${Number} in
    1)
        export BotName="Miao-Yunzai"
        BOT_COMMAND="Miao-Yun"
        TmuxName=MZ
        BotPath
        ;;
    2)
        export BotName="TRSS-Yunzai"
        BOT_COMMAND="TRSS Yun"
        TmuxName=TZ
        BotPath
        ;;
    3)
        MirrorCheck
        URL="${GitMirror}/raw/master/Manage"
        bash <(curl -sL ${URL}/Lagrange_OneBot.sh)
        ;;
    4)
        MirrorCheck
        URL="${GitMirror}/raw/master/Manage"
        bash <(curl -sL ${URL}/NapCat.sh)
        ;;
    5)
        MirrorCheck
        URL="${GitMirror}/raw/master/Manage"
        bash <(curl -sL ${URL}/meme_generator.sh)
        ;;
    6)
        MirrorCheck
        URL="${GitMirror}/raw/master/Manage"
        bash <(curl -sL ${URL}/SYS_Manage.sh)
        ;;
          0)
    	        exit 0
                ;;
esac
}
function mainbak()
{
    while true
    do
        master
        mainbak
    done
}
mainbak


