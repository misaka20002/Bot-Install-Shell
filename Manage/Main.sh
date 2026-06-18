old_version="1.1.105"

cd $HOME

# ANSI 颜色定义 (用于 echo -e)
export ANSI_RESET="\033[0m"
export ANSI_BOLD="\033[1m"
export ANSI_RED="\033[31m"
export ANSI_GREEN="\033[32m"
export ANSI_YELLOW="\033[33m"
export ANSI_BLUE="\033[34m"
export ANSI_MAGENTA="\033[35m"
export ANSI_CYAN="\033[36m"
export ANSI_WHITE="\033[37m"

# Dialog 颜色定义 (用于 dialog/whiptail)
export RESET="\Zn"
export BOLD="\Zb"
export FG_BLACK="\Z0"
export FG_RED="\Z1"
export FG_GREEN="\Z2"
export FG_YELLOW="\Z3"
export FG_BLUE="\Z4"
export FG_MAGENTA="\Z5"
export FG_CYAN="\Z6"
export FG_WHITE="\Z7"

# 兼容旧变量名
export red="${ANSI_RED}"
export green="${ANSI_GREEN}"
export yellow="${ANSI_YELLOW}"
export blue="${ANSI_BLUE}"
export purple="${ANSI_MAGENTA}"
export cyan="${ANSI_CYAN}"
export white="${ANSI_WHITE}"
export background="${ANSI_RESET}"

if [ -d /usr/local/node/bin ];then
    PATH=$PATH:/usr/local/node/bin
    if [ ! -d "$HOME/.local/share/pnpm" ];then
        mkdir -p "$HOME/.local/share/pnpm"
    fi
    PATH=$PATH:/root/.local/share/pnpm
    PNPM_HOME=/root/.local/share/pnpm
fi
##############################
# 检查 dialog 或 whiptail
if [ -x "$(command -v dialog)" ];then
    DialogWhiptail=dialog
elif [ -x "$(command -v whiptail)" ];then
    DialogWhiptail=whiptail
else
    echo -e "${ANSI_RED}错误: 未找到 dialog 或 whiptail，请先安装！${ANSI_RESET}" >&2
    exit 1
fi

# 设置 dialog 淡粉红色背景主题
export DIALOGRC="/tmp/.dialogrc_pink"
cat > "$DIALOGRC" << 'EOF'
# 淡粉红色主题配置
screen_color = (WHITE,MAGENTA,OFF)
shadow_color = (BLACK,BLACK,OFF)
dialog_color = (BLACK,WHITE,OFF)
title_color = (MAGENTA,WHITE,ON)
border_color = (MAGENTA,WHITE,OFF)
button_active_color = (WHITE,MAGENTA,ON)
button_inactive_color = (BLACK,WHITE,OFF)
button_key_active_color = (WHITE,MAGENTA,ON)
button_key_inactive_color = (RED,WHITE,OFF)
button_label_active_color = (WHITE,MAGENTA,ON)
button_label_inactive_color = (BLACK,WHITE,OFF)
inputbox_color = (BLACK,WHITE,OFF)
inputbox_border_color = (MAGENTA,WHITE,OFF)
searchbox_color = (BLACK,WHITE,OFF)
searchbox_title_color = (MAGENTA,WHITE,ON)
searchbox_border_color = (MAGENTA,WHITE,OFF)
position_indicator_color = (MAGENTA,WHITE,ON)
menubox_color = (BLACK,WHITE,OFF)
menubox_border_color = (MAGENTA,WHITE,OFF)
item_color = (BLACK,WHITE,OFF)
item_selected_color = (WHITE,MAGENTA,ON)
tag_color = (MAGENTA,WHITE,ON)
tag_selected_color = (WHITE,MAGENTA,ON)
tag_key_color = (MAGENTA,WHITE,ON)
tag_key_selected_color = (WHITE,MAGENTA,ON)
check_color = (BLACK,WHITE,OFF)
check_selected_color = (WHITE,MAGENTA,ON)
uarrow_color = (MAGENTA,WHITE,ON)
darrow_color = (MAGENTA,WHITE,ON)
EOF
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
    echo -e "${ANSI_CYAN}自定义路径: ${BotPath} ${ANSI_GREEN}判断通过${ANSI_RESET}"
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
            echo -e "${ANSI_RED}Tmux会话 ${tmux_name} 不存在${ANSI_RESET}"
            return 1
        fi

        echo -e "${ANSI_CYAN}正在打开 ${bot_name} 日志（滚动模式）...${ANSI_RESET}"
        # attach到tmux会话并进入复制模式（滚动模式）
        if tmux attach -t ${tmux_name} \; copy-mode 2>/dev/null
        then
            return 0
        else
            # 如果进入复制模式失败，尝试普通attach
            echo -e "${ANSI_YELLOW}进入滚动模式失败，使用普通模式${ANSI_RESET}"
            tmux attach -t ${tmux_name}
        fi
    elif ps all | sed /grep/d | grep -q "${bot_command}"
    then
        # 在前台运行
        echo -e "${ANSI_RED}${bot_name} 在前台运行，无法打开日志${ANSI_RESET}"
        return 1
    else
        # 检查PM2状态需要在正确的工作目录下进行
        if BotPathCheck
        then
            cd ${BotPath}
            if pnpm pm2 show ${bot_name} 2>&1 | grep -q online
            then
                # 在pm2后台运行
                echo -e "${ANSI_CYAN}正在打开 ${bot_name} PM2日志...${ANSI_RESET}"
                pnpm pm2 log ${bot_name} --lines 1000
                return 0
            else
                echo -e "${ANSI_RED}${bot_name} 未运行${ANSI_RESET}"
                return 1
            fi
        else
            echo -e "${ANSI_RED}无法找到 ${bot_name} 的安装路径${ANSI_RESET}"
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
echo -e "${ANSI_GREEN}===============================${ANSI_RESET}"
echo -e "${ANSI_YELLOW}         快捷方式${ANSI_RESET}"
echo -e "${ANSI_GREEN}===============================${ANSI_RESET}"
echo -e "${ANSI_CYAN} xdm        | ${ANSI_BLUE}呆毛版脚本入口${ANSI_RESET}"
# echo -e "${ANSI_CYAN} xdm help   | ${ANSI_BLUE}呆毛版脚本帮助${ANSI_RESET}"
# echo -e "${ANSI_CYAN} xdm lag    | ${ANSI_BLUE}拉格朗日脚本${ANSI_RESET}"
echo -e "${ANSI_CYAN} xdm nap    | ${ANSI_BLUE}NapCat 脚本${ANSI_RESET}"
echo -e "${ANSI_CYAN} xdm plugin | ${ANSI_BLUE}插件管理脚本${ANSI_RESET}"
echo -e "${ANSI_CYAN} xdm meme   | ${ANSI_BLUE}meme 管理脚本${ANSI_RESET}"
echo -e "${ANSI_CYAN} xdm sayu   | ${ANSI_BLUE}早柚核心管理${ANSI_RESET}"
echo -e "${ANSI_CYAN} xdm sys    | ${ANSI_BLUE}系统管理脚本${ANSI_RESET}"
echo -e "${ANSI_CYAN} xdm cc     | ${ANSI_BLUE}Hapi/Claude 管理${ANSI_RESET}"
echo -e "${ANSI_GREEN}===============================${ANSI_RESET}"
echo -e "${ANSI_CYAN} xdm mz ${ANSI_BLUE}Miao-Yunzai根目录${ANSI_RESET}"
echo -e "${ANSI_CYAN} xdm tz ${ANSI_BLUE}TRSS-Yunzai根目录${ANSI_RESET}"
echo -e "${ANSI_CYAN} xdm mzlog ${ANSI_BLUE}打开 Miao 运行日志${ANSI_RESET}"
echo -e "${ANSI_CYAN} xdm tzlog ${ANSI_BLUE}打开 TRSS 运行日志${ANSI_RESET}"
echo -e "${ANSI_GREEN}===============================${ANSI_RESET}"
echo -e "${ANSI_YELLOW} Bot-Shell ${ANSI_CYAN}呆毛版-QQ群: 1022982073${ANSI_RESET}"
echo -e "${ANSI_GREEN}=============================${ANSI_RESET}"
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
cc)
MirrorCheck
URL="${GitMirror}/raw/master/Manage"
bash <(curl -sL ${URL}/Hapi_Claude_Manage.sh)
exit
;;
SWPKG)
MirrorCheck
URL="${GitMirror}/raw/master/Manage"
bash <(curl -sL ${URL}/BOT_INSTALL.sh)
exit
;;
sayu)
MirrorCheck
URL="${GitMirror}/raw/master/Manage"
bash <(curl -sL ${URL}/Sayu_Bot.sh)
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
    echo -e "${ANSI_RED}Miao-Yunzai 未安装${ANSI_RESET}"
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
    echo -e "${ANSI_RED}TRSS-Yunzai 未安装${ANSI_RESET}"
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
    version_date=$(curl -sL "${VersionURL}")
    new_version="$(echo "${version_date}" | grep 'version:' | awk '{print $2}')"
    help_message="$(echo "${version_date}" | grep 'help:' | sed 's/help: //')"

    # 获取不到新版本号时直接跳过更新
    if [ -z "${new_version}" ]; then
        echo -en "${ANSI_RED}获取新版本号时失败 ${ANSI_CYAN}回车继续${ANSI_RESET}"
        read
        return
    fi

    # 需要验证更新后文档的正确性才覆盖，用于修复垃圾 Gitee 下载到空文件
    if [ "${new_version}" != "${old_version}" ];then
        echo -e "${ANSI_CYAN}检测到新版本: ${new_version}，正在更新${ANSI_RESET}"
        HTTP_CODE=$(curl -sL -w "%{http_code}" -o xdm_update_temp "${URL}")
        CURL_RET=$?

        HELP_OUTPUT=$(bash xdm_update_temp help 2>&1)
        HELP_RET=$?

        if [ ${CURL_RET} -eq 0 ] && [ "${HTTP_CODE}" = "200" ] && [ -s xdm_update_temp ] && grep -q "old_version=" xdm_update_temp && [ ${HELP_RET} -eq 0 ] && echo "${HELP_OUTPUT}" | grep -q "呆毛版"; then
            echo "${HELP_OUTPUT}"

            mv -f xdm_update_temp /usr/local/bin/xdm
            chmod +x /usr/local/bin/xdm
            echo -en "${ANSI_CYAN}版本 ${new_version} 更新完成 ${help_message}${ANSI_RESET}"
            read
            exit
        else
            echo -e "${ANSI_RED}下载更新文件失败，或文件校验未通过！(HTTP状态码: ${HTTP_CODE}，Curl返回码: ${CURL_RET})${ANSI_RESET}"
            echo -e "${ANSI_YELLOW}可能是网络拥堵导致拉取到了空文件、不完整文件或服务器拒绝访问。${ANSI_RESET}"
            echo -en "${ANSI_RED}版本 ${new_version} 更新失败，已跳过更新并保留当前旧版本运行 ${help_message} ${ANSI_CYAN}回车继续${ANSI_RESET}"
            read
            rm -f xdm_update_temp
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
echo -e "${ANSI_CYAN}正在查找并清理 ${BotName} 孤立进程...${ANSI_RESET}"

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
    echo -e "${ANSI_YELLOW}发现孤立进程[${pattern}]: ${PIDS}${ANSI_RESET}"
    for pid in ${PIDS}; do
      echo -e "${ANSI_RED}正在终止孤立进程: ${pid}${ANSI_RESET}"
      # 先尝试优雅终止
      if kill -TERM ${pid} 2>/dev/null; then
        echo -e "${ANSI_CYAN}已发送TERM信号到进程: ${pid}${ANSI_RESET}"
        sleep 2
        # 检查进程是否还存在
        if kill -0 ${pid} 2>/dev/null; then
          echo -e "${ANSI_RED}进程 ${pid} 未响应，强制终止${ANSI_RESET}"
          kill -KILL ${pid} 2>/dev/null && echo -e "${ANSI_GREEN}强制终止成功: ${pid}${ANSI_RESET}"
        else
          echo -e "${ANSI_GREEN}进程已正常终止: ${pid}${ANSI_RESET}"
        fi
      else
        echo -e "${ANSI_YELLOW}进程 ${pid} 可能已经不存在${ANSI_RESET}"
      fi
    done
  fi
done

if ! ${found_processes}; then
  echo -e "${ANSI_GREEN}未发现 ${BotName} 孤立进程${ANSI_RESET}"
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
            echo -e "${ANSI_CYAN}已创建tmux会话: ${TmuxName}${ANSI_RESET}"
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
    echo -e "${ANSI_CYAN}正在停止 ${BotName}...${ANSI_RESET}"

    RunningState
    res="$?"

    # 先尝试正常停止方式
    if [ ${res} -eq 1 ];then
      echo -e "${ANSI_CYAN}正在停止tmux会话...${ANSI_RESET}"
      if tmux kill-session -t ${TmuxName}
      then
        echo -e "${ANSI_GREEN}Tmux会话已终止${ANSI_RESET}"
        stop_success=true
      else
        echo -e "${ANSI_YELLOW}Tmux会话终止失败${ANSI_RESET}"
        stop_success=false
      fi
    elif [ ${res} -eq 2 ];then
      echo -e "${ANSI_CYAN}正在停止前台进程...${ANSI_RESET}"
      PIDS=$(ps -ef | grep "${BOT_COMMAND}" | grep -v grep | awk '{print $2}')
      if [ -n "${PIDS}" ] && kill ${PIDS}
      then
        echo -e "${ANSI_GREEN}前台进程已终止${ANSI_RESET}"
        stop_success=true
      else
        echo -e "${ANSI_YELLOW}前台进程终止失败${ANSI_RESET}"
        stop_success=false
      fi
    elif [ ${res} -eq 3 ];then
      echo -e "${ANSI_CYAN}正在停止PM2进程...${ANSI_RESET}"
      cd ${BotPath}
      pnpm run stop
      if pnpm pm2 show ${BotName} 2>&1 | grep -q online
      then
        echo -e "${ANSI_YELLOW}PM2停止失败，尝试强制删除${ANSI_RESET}"
        pnpm pm2 delete ${BotName} 2>/dev/null
        stop_success=false
      else
        echo -e "${ANSI_GREEN}PM2进程已停止${ANSI_RESET}"
        stop_success=true
      fi
    else
      echo -e "${ANSI_YELLOW}${BotName} 未在运行${ANSI_RESET}"
      stop_success=true
    fi

    # 无论正常停止是否成功，都执行深度清理
    echo -e "${ANSI_CYAN}执行深度进程清理...${ANSI_RESET}"
    CleanupOrphanedProcesses

    # 显示最终结果
    if ${stop_success}; then
      ${DialogWhiptail} --title "呆毛版-Script" --msgbox "${BotName} 停止成功\n已清理所有相关进程" 10 60
    else
      ${DialogWhiptail} --title "呆毛版-Script" --msgbox "${BotName} 强制停止完成\n已清理所有相关进程" 10 60
    fi
    ;;
  restart)
    echo -e "${ANSI_CYAN}正在重启 ${BotName}...${ANSI_RESET}"

    # 先执行完整的停止流程
    BOT stop

    # 等待一下确保进程完全清理
    sleep 2

    # 再执行启动流程
    echo -e "${ANSI_CYAN}正在启动 ${BotName}...${ANSI_RESET}"
    BOT start
    ;;
  log)
    RunningState
    res="$?"
    if [ ${res} -eq 1 ];then
      TmuxAttachWithScrollMode
    elif [ ${res} -eq 2 ];then
      ${DialogWhiptail} --title "呆毛版-Script" --msgbox "${BotName}[前台运行]\n无法打开日志" 10 60
    elif [ ${res} -eq 3 ];then
      pnpm pm2 log ${BotName} --lines 1000
    else
      ${DialogWhiptail} --title "呆毛版-Script" --msgbox "${BotName}[未运行]" 10 60
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
echo -e "${ANSI_YELLOW}正在更新 ${Name}${ANSI_RESET}"
if ! git pull -f
then
    echo -en "${ANSI_RED}${Name}更新失败 ${ANSI_YELLOW}是否强制更新 [Y/N]${ANSI_RESET}";read YN
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
echo -e "${ANSI_YELLOW}正在更新NPM${ANSI_RESET}"
npm install -g npm@latest
echo -e "${ANSI_YELLOW}正在更新PNPM${ANSI_RESET}"
pnpm install -g pnpm@latest
echo -en "${ANSI_CYAN}更新完成 回车返回${ANSI_RESET}";read
}

function ShowHelpDocument(){
    echo -e "${ANSI_CYAN}=========================================${ANSI_RESET}"
    echo -e "${ANSI_YELLOW}           呆毛版脚本帮助文档${ANSI_RESET}"
    echo -e "${ANSI_CYAN}=========================================${ANSI_RESET}"
    echo -e "${ANSI_GREEN}详细使用说明请查看以下链接:${ANSI_RESET}"
    echo
    echo -e "${ANSI_BLUE}https://gitee.com/Misaka21011/Yunzai-Bot-Shell/blob/master/Markdown/Tmoe.md${ANSI_RESET}"
    echo -e "${ANSI_BLUE}https://github.com/misaka20002/Bot-Install-Shell/blob/master/Markdown/Tmoe.md${ANSI_RESET}"
    echo
    echo -e "${ANSI_CYAN}=========================================${ANSI_RESET}"
    echo -e "${ANSI_YELLOW}说明:${ANSI_RESET}"
    echo -e "${ANSI_GREEN}- 安装教程和常见问题解答${ANSI_RESET}"
    echo -e "${ANSI_GREEN}- 各种功能的详细使用方法${ANSI_RESET}"
    echo -e "${ANSI_GREEN}- 故障排除和技术支持${ANSI_RESET}"
    echo -e "${ANSI_CYAN}=========================================${ANSI_RESET}"
    echo
    echo -en "${ANSI_CYAN}回车返回${ANSI_RESET}"
    read
}

function OperatingEnvironmentInstall(){
  echo -e "${ANSI_YELLOW}确认要重新安装环境吗? 这将重新安装以下依赖( ffmpeg, gzip, redis, tmux, chromium, fonts-wqy-zenhei, node.JS ... ) [y/n]${ANSI_RESET}"
  read -p "" confirm
  case ${confirm} in
    y|Y)
      echo -e "${ANSI_CYAN}开始重新安装环境...${ANSI_RESET}"
      ;;
    n|N)
      echo -e "${ANSI_CYAN}已取消重新安装环境${ANSI_RESET}"
      Main
      return
      ;;
    *)
      echo -e "${ANSI_RED}无效的输入，请输入 y 或 n${ANSI_RESET}"
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
      echo -e "${ANSI_RED}您的框架为 ${ANSI_YELLOW}$(uname -m)${ANSI_RED}, 快提issue做适配.${ANSI_RESET}"
      exit
  ;;
  esac

    if sudo rm -f /usr/local/bin/ffmpeg; then
      echo -e "${ANSI_GREEN}Successfully removed /usr/local/bin/ffmpeg${ANSI_RESET}"
    else
      echo -e "${ANSI_RED}Failed to remove /usr/local/bin/ffmpeg${ANSI_RESET}"
      echo -e "${ANSI_YELLOW}You may need to manually remove it later${ANSI_RESET}"
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
    echo "执行url: ${URL}/${command}"
    until bash <(curl -sL ${URL}/${command})
    do
      if [ ${i} -eq 3 ]
      then
        echo -e "${ANSI_RED}错误次数过多 退出${ANSI_RESET}"
        exit
      fi
      i=$((${i}+1))
      echo -en "${ANSI_RED}命令执行失败 ${ANSI_GREEN}3秒后重试${ANSI_RESET}"
      sleep 3s
      echo
    done
  done
  Main
}

# Bot 管理主菜单
MENU_ITEMS=(
    "START" "启动运行"
    "FGRUN" "前台启动"
    "STOP" "停止运行"
    "RESTART" "重新启动"
    "LOG" "打开日志"
    "PLUGIN" "插件管理"
    "UPDATE" "全部更新"
    "REINSTALL" "重装环境"
    "OTHER" "其他功能"
    "HELP" "帮助文档"
)

# 显示菜单
CHOICE=$(${DialogWhiptail} --colors --clear \
--backtitle "呆毛版 QQ群:1022982073" \
--title "${BotName}管理" \
--ok-label "选择" \
--cancel-label "返回" \
--menu "\n请选择操作 (可按字母快捷键):\n" \
22 60 10 \
"${MENU_ITEMS[@]}" \
3>&1 1>&2 2>&3)

exit_status=$?
clear

case $exit_status in
    0) # 用户选择了某项
        case "$CHOICE" in
            START)
                BOT start
                ;;
            FGRUN)
                BOT ForegroundStart
                ;;
            STOP)
                BOT stop
                ;;
            RESTART)
                BOT restart
                ;;
            LOG)
                BOT log
                ;;
            PLUGIN)
                BOT plugin_2
                ;;
            UPDATE)
                GitUpdate
                ;;
            REINSTALL)
                OperatingEnvironmentInstall
                ;;
            OTHER)
                MirrorCheck
                bash <(curl -sL ${GitMirror}/raw/master/Manage/OtherFunctions.sh)
                ;;
            HELP)
                ShowHelpDocument
                ;;
            *)
                ${DialogWhiptail} --title "错误" --msgbox "无效的选择: '$CHOICE'" 6 40
                ;;
        esac
        ;;
    1|255) # 用户选择返回或按ESC
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
    echo -e "${ANSI_RED}您的框架为 ${ANSI_YELLOW}$(uname -m)${ANSI_RED}, 快提issue做适配.${ANSI_RESET}"
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
  echo "执行url: ${URL}/${command}"
  until bash <(curl -sL ${URL}/${command})
  do
    if [ ${i} -eq 3 ]
    then
      echo -e "${ANSI_RED}错误次数过多 退出${ANSI_RESET}"
      exit
    fi
    i=$((${i}+1))
    echo -en "${ANSI_RED}命令执行失败 ${ANSI_GREEN}3秒后重试${ANSI_RESET}"
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
function MoreFunctions(){
CHOICE=$(${DialogWhiptail} --colors --clear \
--backtitle "呆毛版 QQ群:1022982073" \
--title "更多功能" \
--ok-label "选择" \
--cancel-label "返回" \
--menu "\n请选择功能:\n" \
12 55 2 \
"H" "Hapi/CC管理" \
"S" "操作系统管理" \
3>&1 1>&2 2>&3)

exit_status=$?
clear

case $exit_status in
    0) # 用户选择了某项
        case "$CHOICE" in
            H)
                MirrorCheck
                URL="${GitMirror}/raw/master/Manage"
                bash <(curl -sL ${URL}/Hapi_Claude_Manage.sh)
                ;;
            S)
                MirrorCheck
                URL="${GitMirror}/raw/master/Manage"
                bash <(curl -sL ${URL}/SYS_Manage.sh)
                ;;
            *)
                ${DialogWhiptail} --title "错误" --msgbox "无效的选择: '$CHOICE'" 6 40
                ;;
        esac
        ;;
    1|255) # 用户选择返回或按ESC
        return
        ;;
esac
}
function master(){
# 定义菜单项
MENU_ITEMS=(
    "M" "Miao-Yunzai"
    "T" "TRSS-Yunzai"
    "N" "NapCat管理"
    "E" "部署meme管理"
    "S" "早柚核心管理"
    "O" "更多功能"
)

# 显示菜单
CHOICE=$(${DialogWhiptail} --colors --clear \
--backtitle "呆毛版 QQ群:1022982073 | 快捷命令: xdm help" \
--title "呆毛版主菜单" \
--ok-label "选择" \
--cancel-label "退出" \
--menu "呆毛版 QQ群:1022982073 | 快捷命令: xdm help\n 请选择操作 (可按字母快捷键):\n" \
18 60 6 \
"${MENU_ITEMS[@]}" \
3>&1 1>&2 2>&3)

exit_status=$?
clear

case $exit_status in
    0) # 用户选择了某项
        case "$CHOICE" in
            M)
                export BotName="Miao-Yunzai"
                BOT_COMMAND="Miao-Yun"
                TmuxName=MZ
                unset BotPath
                gotoBotPath
                ;;
            T)
                export BotName="TRSS-Yunzai"
                BOT_COMMAND="TRSS Yun"
                TmuxName=TZ
                unset BotPath
                gotoBotPath
                ;;
            N)
                MirrorCheck
                URL="${GitMirror}/raw/master/Manage"
                bash <(curl -sL ${URL}/NapCat.sh)
                ;;
            E)
                MirrorCheck
                URL="${GitMirror}/raw/master/Manage"
                bash <(curl -sL ${URL}/meme_generator.sh)
                ;;
            S)
                MirrorCheck
                URL="${GitMirror}/raw/master/Manage"
                bash <(curl -sL ${URL}/Sayu_Bot.sh)
                ;;
            O)
                MoreFunctions
                ;;
            *)
                ${DialogWhiptail} --title "错误" --msgbox "无效的选择: '$CHOICE'" 6 40
                ;;
        esac
        ;;
    1|255) # 用户选择退出或按ESC
        echo -e "${ANSI_CYAN}已退出呆毛版脚本。${ANSI_RESET}"
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