old_version="1.1.95"

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

# RedisServerStart(){
# PedisCliPing(){
# if [ "$(redis-cli ping 2>&1)" == "PONG" ]
# then
#   return 0
# else
#   return 1
# fi
# }
# if $(PedisCliPing)
# then
#   echo -e ${cyan}Redis-Server${green} 已启动${background}
# else
#   $(nohup redis-server > /dev/null 2>&1 &)
#   echo -e ${cyan}等待Redis-Server启动中${background}
#   until PedisCliPing
#   do
#     sleep 0.5s
#   done
#   echo -e ${cyan}Redis-Server${green} 启动成功${background}
# fi
# }
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

function QuickLog(){
    local bot_name="$1"
    local bot_command="$2" 
    local tmux_name="$3"
    
    # 检查运行状态
    if TmuxLs ${tmux_name}
    then
        # 在tmux中运行，进入滚动模式
        if ! tmux has-session -t ${tmux_name} 2>/dev/null
        then
            echo -e ${red}Tmux会话 ${tmux_name} 不存在${background}
            return 1
        fi
        
        echo -e ${cyan}正在打开 ${bot_name} 日志（滚动模式）...${background}
        # attach到tmux会话并进入复制模式（滚动模式）
        if tmux attach -t ${tmux_name} \; copy-mode 2>/dev/null
        then
            return 0
        else
            # 如果进入复制模式失败，尝试普通attach
            echo -e ${yellow}进入滚动模式失败，使用普通模式${background}
            tmux attach -t ${tmux_name}
        fi
    elif ps all | sed /grep/d | grep -q "${bot_command}"
    then
        # 在前台运行
        echo -e ${red}${bot_name} 在前台运行，无法打开日志${background}
        return 1
    else
        # 检查PM2状态需要在正确的工作目录下进行
        if BotPathCheck
        then
            cd ${BotPath}
            if pnpm pm2 show ${bot_name} 2>&1 | grep -q online
            then
                # 在pm2后台运行
                echo -e ${cyan}正在打开 ${bot_name} PM2日志...${background}
                pnpm pm2 log ${bot_name} --lines 1000
                return 0
            else
                echo -e ${red}${bot_name} 未运行${background}
                return 1
            fi
        else
            echo -e ${red}无法找到 ${bot_name} 的安装路径${background}
            return 1
        fi
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
echo -e ${cyan} xdm sys"   | "${blue}系统管理脚本${background}
echo -e ${green}===============================${background}
echo -e ${cyan} xdm mz ${blue}Miao-Yunzai根目录${background}
echo -e ${cyan} xdm tz ${blue}TRSS-Yunzai根目录${background}
echo -e ${cyan} xdm mzlog ${blue}打开 Miao 运行日志${background}
echo -e ${cyan} xdm tzlog ${blue}打开 TRSS 运行日志${background}
echo -e ${green}===============================${background}
echo -e ${yellow} Bot-Shell ${cyan}呆毛版-QQ群: 1022982073${background}
echo -e ${green}=============================${background}
}
##############################
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
sys)
MirrorCheck
URL="${GitMirror}/raw/master/Manage"
bash <(curl -sL ${URL}/SYS_Manage.sh)
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
mzlog)
export BotName=Miao-Yunzai
export BOT_COMMAND="Miao-Yun"
export TmuxName=MZ
if BotPathCheck
then
    QuickLog "Miao-Yunzai" "Miao-Yun" "MZ"
else
    echo -e ${red}Miao-Yunzai 未安装${background}
fi
exit
;;
tzlog)
export BotName=TRSS-Yunzai
export BOT_COMMAND="TRSS Yun" 
export TmuxName=TZ
if BotPathCheck
then
    QuickLog "TRSS-Yunzai" "TRSS Yun" "TZ"
else
    echo -e ${red}TRSS-Yunzai 未安装${background}
fi
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

if [ "${up}" != "false" ]; then
  if ping -c 1 gitee.com > /dev/null 2>&1
  then
    VersionURL="https://gitee.com/Misaka21011/Yunzai-Bot-Shell/raw/master/version"
    URL="https://gitee.com/Misaka21011/Yunzai-Bot-Shell/raw/master/Manage/Main.sh"
    UPDATE
  elif ping -c 1 github.com > /dev/null 2>&1
  then
    VersionURL="https://raw.githubusercontent.com/misaka20002/Bot-Install-Shell/master/version"
    URL="https://raw.githubusercontent.com/misaka20002/Bot-Install-Shell/master/Manage/Main.sh"
    UPDATE
  fi
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
TmuxAttachWithScrollMode(){
#echo $TmuxName
# 首先检查tmux会话是否存在
if ! tmux has-session -t ${TmuxName} 2>/dev/null
then
  ${DialogWhiptail} --title "呆毛版-Script" --msgbox "Tmux会话 ${TmuxName} 不存在" 10 60
  return 1
fi

# 尝试attach到tmux会话并进入复制模式（滚动模式）
if tmux attach -t ${TmuxName} \; copy-mode 2>/dev/null
then
  return 0
else
  # 如果进入复制模式失败，尝试普通attach
  if ! tmux attach -t ${TmuxName} > /dev/null 2>&1
  then
    error=$(tmux attach -t ${TmuxName} 2>&1)
    ${DialogWhiptail} --title "呆毛版-Script" --msgbox "窗口打开错误\n原因: ${error}" 10 60
  fi
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
    pnpm pm2 log ${BotName} --lines 1000
  fi
fi
}

# 在启动前清理孤立进程
CleanupOrphanedProcesses(){
echo -e ${cyan}正在查找并清理 ${BotName} 孤立进程...${background}

declare -a process_patterns=()
case ${BotName} in
  "TRSS-Yunzai")
    process_patterns=("TRSS Yunzai" "TRSS-Yunzai")
    ;;
  "Miao-Yunzai")
    process_patterns=("Miao-Yunzai" "Miao Yunzai")
    ;;
  *)
    process_patterns=("${BotName}")
    ;;
esac

local found_processes=false
for pattern in "${process_patterns[@]}"; do
  # 查找不在tmux中运行的进程
  PIDS=$(ps -ef | grep "${pattern}" | grep -v grep | grep -v tmux | grep -v "$$" | awk '{print $2}')
  if [ -n "${PIDS}" ]; then
    found_processes=true
    echo -e ${yellow}发现孤立进程 [${pattern}]: ${PIDS}${background}
    for pid in ${PIDS}; do
      echo -e ${red}正在终止孤立进程: ${pid}${background}
      # 先尝试优雅终止
      if kill -TERM ${pid} 2>/dev/null; then
        echo -e ${cyan}已发送TERM信号到进程: ${pid}${background}
        sleep 2
        # 检查进程是否还存在
        if kill -0 ${pid} 2>/dev/null; then
          echo -e ${red}进程 ${pid} 未响应，强制终止${background}
          kill -KILL ${pid} 2>/dev/null && echo -e ${green}强制终止成功: ${pid}${background}
        else
          echo -e ${green}进程已正常终止: ${pid}${background}
        fi
      else
        echo -e ${yellow}进程 ${pid} 可能已经不存在${background}
      fi
    done
  fi
done

if ! ${found_processes}; then
  echo -e ${green}未发现 ${BotName} 孤立进程${background}
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
      CleanupOrphanedProcesses
      # 添加选择启动方式的对话框
      start_option=$(${DialogWhiptail} --title "呆毛版-Script" \
      --menu "请选择启动方式" 10 50 2 \
      "1" "在TMUX窗口启动" \
      "2" "在Pm2后台启动" \
      3>&1 1>&2 2>&3)
      
      case ${start_option} in
        1)
          # 创建tmux会话并保持shell活跃
          if tmux new-session -s ${TmuxName} -d bash
          then
            echo -e ${cyan}已创建tmux会话: ${TmuxName}${background}
            # 创建自动重启循环脚本
            tmux send-keys -t ${TmuxName} "while true; do node app; echo -e '\033[33m${BotName} 已退出，2秒后自动重启...\033[0m'; sleep 2; done" Enter
            ProgressBar "启动"
          else
            ${DialogWhiptail} --title "呆毛版-Script" --msgbox "${BotName} 启动失败" 10 60
          fi
          ;;
        2)
          # RedisServerStart
          cd ${BotPath}
          pnpm run restart
          if pnpm pm2 show ${BotName} 2>&1 | grep -q online
          then
            AttachPage "在Pm2后台启动" "日志"
          else
            ${DialogWhiptail} --title "呆毛版-Script" --msgbox "${BotName} 启动失败" 10 60
          fi
          ;;
        *)
          ${DialogWhiptail} --title "呆毛版-Script" --msgbox "${BotName} 已取消启动" 10 60
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
      CleanupOrphanedProcesses
      # RedisServerStart
      node app
    fi
    ;;
  stop)
    echo -e ${cyan}正在停止 ${BotName}...${background}
    
    RunningState
    res="$?"
    
    # 先尝试正常停止方式
    if [ ${res} -eq 1 ];then
      echo -e ${cyan}正在停止tmux会话...${background}
      if tmux kill-session -t ${TmuxName}
      then
        echo -e ${green}Tmux会话已终止${background}
        stop_success=true
      else
        echo -e ${yellow}Tmux会话终止失败${background}
        stop_success=false
      fi
    elif [ ${res} -eq 2 ];then
      echo -e ${cyan}正在停止前台进程...${background}
      PIDS=$(ps -ef | grep "${BOT_COMMAND}" | grep -v grep | awk '{print $2}')
      if [ -n "${PIDS}" ] && kill ${PIDS}
      then
        echo -e ${green}前台进程已终止${background}
        stop_success=true
      else
        echo -e ${yellow}前台进程终止失败${background}
        stop_success=false
      fi
    elif [ ${res} -eq 3 ];then
      echo -e ${cyan}正在停止PM2进程...${background}
      cd ${BotPath}
      pnpm run stop
      if pnpm pm2 show ${BotName} 2>&1 | grep -q online
      then
        echo -e ${yellow}PM2停止失败，尝试强制删除${background}
        pnpm pm2 delete ${BotName} 2>/dev/null
        stop_success=false
      else
        echo -e ${green}PM2进程已停止${background}
        stop_success=true
      fi
    else
      echo -e ${yellow}${BotName} 未在运行${background}
      stop_success=true
    fi
    
    # 无论正常停止是否成功，都执行深度清理
    echo -e ${cyan}执行深度进程清理...${background}
    CleanupOrphanedProcesses
    
    # 显示最终结果
    if ${stop_success}; then
      ${DialogWhiptail} --title "呆毛版-Script" --msgbox "${BotName} 停止成功\n已清理所有相关进程" 10 60
    else
      ${DialogWhiptail} --title "呆毛版-Script" --msgbox "${BotName} 强制停止完成\n已清理所有相关进程" 10 60
    fi
    ;;
  restart)
    echo -e ${cyan}正在重启 ${BotName}...${background}
    
    # 先执行完整的停止流程
    BOT stop
    
    # 等待一下确保进程完全清理
    sleep 2
    
    # 再执行启动流程
    echo -e ${cyan}正在启动 ${BotName}...${background}
    BOT start
    ;;
  log)
    RunningState
    res="$?"
    if [ ${res} -eq 1 ];then
      TmuxAttachWithScrollMode
    elif [ ${res} -eq 2 ];then
      ${DialogWhiptail} --title "呆毛版-Script" --msgbox "${BotName} [前台运行]\n无法打开日志" 10 60
    elif [ ${res} -eq 3 ];then
      pnpm pm2 log ${BotName} --lines 1000
    else
      ${DialogWhiptail} --title "呆毛版-Script" --msgbox "${BotName} [未运行]" 10 60
    fi
    ;;
  plugin_1)
        bash <(curl -sL https://mirrors.chenby.cn/https://raw.githubusercontent.com/misaka20002/yunzai-LoliconAPI-paimonV2/main/psign/PaimonPluginsManage.sh)
        # bash <(curl -sL https://git.ppp.ac.cn/https://raw.githubusercontent.com/misaka20002/yunzai-LoliconAPI-paimonV2/main/psign/PaimonPluginsManage.sh)
        # bash <(curl -sL https://gh-proxy.com/https://raw.githubusercontent.com/misaka20002/yunzai-LoliconAPI-paimonV2/main/psign/PaimonPluginsManage.sh)
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

function ShowHelpDocument(){
    echo -e ${cyan}"========================================="${background}
    echo -e ${yellow}"           呆毛版脚本帮助文档"${background}
    echo -e ${cyan}"========================================="${background}
    echo -e ${green}"详细使用说明请查看以下链接:"${background}
    echo
    echo -e ${blue}"https://gitee.com/Misaka21011/Yunzai-Bot-Shell/blob/master/Markdown/Tmoe.md"${background}
    echo -e ${blue}"https://github.com/misaka20002/Bot-Install-Shell/blob/master/Markdown/Tmoe.md"${background}
    echo
    echo -e ${cyan}"========================================="${background}
    echo -e ${yellow}"说明:"${background}
    echo -e ${green}"- 安装教程和常见问题解答"${background}
    echo -e ${green}"- 各种功能的详细使用方法"${background}
    echo -e ${green}"- 故障排除和技术支持"${background}
    echo -e ${cyan}"========================================="${background}
    echo
    echo -en ${cyan}回车返回${background}
    read
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
    URL="https://raw.githubusercontent.com/misaka20002/Bot-Install-Shell/master/Manage"
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
--title "呆毛版 QQ群:1022982073" \
--menu "${BotName}管理" \
23 35 15 \
"1" "启动运行" \
"2" "前台启动" \
"3" "停止运行" \
"4" "重新启动" \
"5" "打开日志" \
"6" "插件管理" \
"7" "全部更新" \
"8" "重装环境" \
"9" "其他功能" \
"10" "帮助文档" \
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
    6)
        BOT plugin_2
        ;;
    7)
        GitUpdate
        ;;
    8)
        OperatingEnvironmentInstall
        ;;
    9)
        MirrorCheck
        bash <(curl -sL ${GitMirror}/raw/master/Manage/OtherFunctions.sh)
        ;;
    10)
        ShowHelpDocument
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
  URL="https://raw.githubusercontent.com/misaka20002/Bot-Install-Shell/master/Manage"
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
gotoBotPath
}
function gotoBotPath(){
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
--title "呆毛版 QQ群:1022982073" \
--menu "💡 提示: 发送 xdm help 获取更多快捷键" \
20 38 10 \
"1" "Miao-Yunzai" \
"2" "TRSS-Yunzai" \
"3" "拉格朗日管理" \
"4" "NapCat管理" \
"5" "部署meme服务器" \
"6" "操作系统管理" \
"0" "退出" \
3>&1 1>&2 2>&3)
feedback=$?
feedback
case ${Number} in
    1)
        export BotName="Miao-Yunzai"
        BOT_COMMAND="Miao-Yun"
        TmuxName=MZ
        unset BotPath
        gotoBotPath
        ;;
    2)
        export BotName="TRSS-Yunzai"
        BOT_COMMAND="TRSS Yun"
        TmuxName=TZ
        unset BotPath
        gotoBotPath
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
    done
}
mainbak


