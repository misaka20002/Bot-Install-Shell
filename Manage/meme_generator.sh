#!/bin/env bash
SCRIPT_VERSION="1.0.01"

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

URL="https://ipinfo.io"
Address=$(curl -sL ${URL} | sed -n 's/.*"country": "\(.*\)",.*/\1/p')
if [ "${Address}" = "CN" ]
then
  GitMirror="gitee.com"
  GithubMirror_1="https://ghfast.top/"
  GithubMirror_2="https://git.ppp.ac.cn/"
  GithubMirror_3="https://gh-proxy.com/"
else
  GitMirror="github.com"
  GithubMirror_1=""
  GithubMirror_2=""
  GithubMirror_3=""
fi

config=$HOME/.config/meme_generator/config.toml
install_path=$HOME/memeGenerator
SCRIPT_LOCAL_PATH="$HOME/.config/meme_generator/update_script.sh"

function tmux_new(){
Tmux_Name="$1"
Shell_Command="$2"
if ! tmux new -s ${Tmux_Name} -d "${Shell_Command}"
then
    echo -e ${yellow}meme生成器启动错误"\n"错误原因:${red}${tmux_new_error}${background}
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

function meme_curl(){
Port=$(grep -E "port" ${config} | awk '{print $3}')
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
until meme_curl
do
    sleep 1s
    i=$((${i}+10)) # 每次步进10，
    a="${a}#"
    echo -ne "\r${i}% ${a}\r"
    if [[ ${i} == 100 ]];then
        echo
        return 1 # 10秒后超时，返回错误码 1
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
    echo -e ${yellow}meme生成器打开错误"\n"错误原因:${red}${tmux_windows_attach_error}${background}
    echo
    echo -en ${yellow}回车返回${background};read
fi
}

# 添加git操作函数，支持镜像自动切换
git_clone() {
  repo_url="$1"
  target_dir="$2"
  log_file="$3"
  
  # 先尝试使用主镜像
  if git clone ${GithubMirror_1}${repo_url} ${target_dir} >> ${log_file} 2>&1; then
    return 0
  else
    echo -e "${yellow}主镜像访问失败，尝试使用备用镜像...${background}" >> ${log_file}
    # 尝试使用备用镜像
    if git clone ${GithubMirror_2}${repo_url} ${target_dir} >> ${log_file} 2>&1; then
      return 0
    else
      # 都失败了，尝试直接访问
      echo -e "${yellow}备用镜像也失败，尝试直接访问...${background}" >> ${log_file}
      if git clone ${repo_url} ${target_dir} >> ${log_file} 2>&1; then
        return 0
      else
        return 1
      fi
    fi
  fi
}

# 添加git更新函数，支持镜像自动切换
git_update() {
  repo_dir="$1"
  log_file="$2"
  
  cd ${repo_dir}
  
  # 获取当前远程仓库URL
  remote_url=$(git remote get-url origin 2>/dev/null)
  
  # 尝试直接更新
  if git fetch --all >> ${log_file} 2>&1 && git reset --hard origin/main >> ${log_file} 2>&1 && git pull >> ${log_file} 2>&1; then
    return 0
  else
    echo -e "${yellow}更新失败，尝试修改远程URL使用备用镜像...${background}" >> ${log_file}
    
    # 提取原始URL
    original_url=${remote_url#*//*/}
    
    # 尝试使用主镜像
    git remote set-url origin ${GithubMirror_1}${original_url} >> ${log_file} 2>&1
    if git fetch --all >> ${log_file} 2>&1 && git reset --hard origin/main >> ${log_file} 2>&1 && git pull >> ${log_file} 2>&1; then
      return 0
    else
      echo -e "${yellow}主镜像失败，尝试使用备用镜像...${background}" >> ${log_file}
      
      # 尝试使用备用镜像
      git remote set-url origin ${GithubMirror_2}${original_url} >> ${log_file} 2>&1
      if git fetch --all >> ${log_file} 2>&1 && git reset --hard origin/main >> ${log_file} 2>&1 && git pull >> ${log_file} 2>&1; then
        return 0
      else
        echo -e "${red}所有镜像都失败，更新失败${background}" >> ${log_file}
        return 1
      fi
    fi
  fi
}

install_meme_generator(){
if [ -d ${install_path}/meme-generator ]; then
  echo -e ${yellow}您已安装meme生成器${background}
  echo -en ${yellow}回车返回${background};read
  return
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
  apt install -y git python3-pip python3-venv tmux fonts-noto-cjk fonts-noto-color-emoji python3-opengl
elif [ $(command -v yum) ];then
  yum makecache -y
  yum install -y git python3-pip python3-venv tmux
elif [ $(command -v dnf) ];then
  dnf makecache -y
  dnf install -y git python3-pip python3-venv tmux
elif [ $(command -v pacman) ];then
  pacman -Syy --noconfirm --needed git python-pip python-virtualenv tmux
else
  echo -e ${red}不受支持的Linux发行版${background}
  exit
fi

# 创建安装目录
mkdir -p ${install_path}
cd ${install_path}

# 克隆meme-generator仓库
echo -e ${green}克隆meme-generator仓库...${background}
if ! git_clone "https://github.com/MemeCrafters/meme-generator.git" "${install_path}/meme-generator" "/dev/null"; then
  echo -e ${red}克隆meme-generator仓库失败${background}
  echo -en ${yellow}回车返回${background};read
  return 1
fi

# 创建虚拟环境
cd ${install_path}/meme-generator
python3 -m venv venv
source venv/bin/activate
python -m pip install .

# 创建配置文件目录
mkdir -p $HOME/.config/meme_generator

# 写入配置文件
cat > ${config} << EOF
[meme]
load_builtin_memes = true  # 是否加载内置表情包
meme_dirs = ["${install_path}/meme-generator-contrib/memes", "${install_path}/meme_emoji/emoji"]  # 加载其他位置的表情包，填写文件夹路径
meme_disabled_list = []  # 禁用的表情包列表，填写表情的 \`key\`

[resource]
# 下载内置表情包图片时的资源链接，下载时选择最快的站点
resource_urls = [
  "https://raw.githubusercontent.com/MeetWq/meme-generator/",
  "https://ghproxy.com/https://raw.githubusercontent.com/MeetWq/meme-generator/",
  "https://fastly.jsdelivr.net/gh/MeetWq/meme-generator@",
  "https://raw.fastgit.org/MeetWq/meme-generator/",
  "https://raw.fgit.ml/MeetWq/meme-generator/",
  "https://raw.gitmirror.com/MeetWq/meme-generator/",
  "https://raw.kgithub.com/MeetWq/meme-generator/",
]

[gif]
gif_max_size = 10.0  # 限制生成的 gif 文件大小，单位为 Mb
gif_max_frames = 100  # 限制生成的 gif 文件帧数

[translate]
baidu_trans_appid = ""  # 百度翻译api相关，表情包 \`dianzhongdian\` 需要使用
baidu_trans_apikey = ""  # 可在 百度翻译开放平台 (http://api.fanyi.baidu.com) 申请

[server]
host = "0.0.0.0"  # web server 监听地址
port = 50835  # web server 端口

[log]
log_level = "INFO"  # 日志等级
EOF

# 下载默认图片
echo -e ${green}下载默认图片...${background}
cd ${install_path}/meme-generator
source venv/bin/activate
python -m meme_generator.cli meme download

# 下载额外图片 - 1
echo -e ${green}下载额外图片meme-generator-contrib...${background}
if ! git_clone "https://github.com/MemeCrafters/meme-generator-contrib.git" "${install_path}/meme-generator-contrib" "/dev/null"; then
  echo -e ${red}克隆meme-generator-contrib仓库失败${background}
  echo -e ${yellow}继续安装其他组件...${background}
fi

# 下载额外图片 - 2
echo -e ${green}下载额外图片meme_emoji...${background}
if ! git_clone "https://github.com/anyliew/meme_emoji.git" "${install_path}/meme_emoji" "/dev/null"; then
  echo -e ${red}克隆meme_emoji仓库失败${background}
  echo -e ${yellow}继续安装其他组件...${background}
fi

# 安装字体
echo -e ${green}安装字体...${background}
cp ${install_path}/meme-generator/resources/fonts/* /usr/share/fonts

# 提醒开放端口
echo -e ${yellow}请确保您的防火墙已开放50835端口${background}

echo -e ${green}安装完成！${background}
echo -en ${yellow}是否立即启动meme生成器? [Y/n]${background};read yn
case ${yn} in
Y|y)
    start_meme_generator
    ;;
esac
}

start_meme_generator(){
cd ${install_path}/meme-generator
Port=$(grep -E "port" ${config} | awk '{print $3}')
if meme_curl
then
    echo -en ${yellow}meme生成器已启动 ${cyan}回车返回${background};read
    echo
    return
fi

Foreground_Start(){
export Boolean=true
while ${Boolean}
do 
  cd ${install_path}/meme-generator
  source venv/bin/activate
  python -m meme_generator.app
  echo -e ${red}meme生成器关闭 正在重启${background}
  sleep 2s
done
echo -en ${cyan}回车返回${background}
read
echo
}

Tmux_Start(){
    Start_Stop_Restart="启动"
    export Boolean=true
    tmux_new meme_generator "cd ${install_path}/meme-generator && source venv/bin/activate && while ${Boolean}; do python -m meme_generator.app; echo -e ${red}meme生成器关闭 正在重启${background}; sleep 2s; done"
    if tmux_gauge meme_generator
    then
        echo
        echo -en ${green}${Start_Stop_Restart}成功 是否打开窗口 进入TMUX窗口后，退出请按 Ctrl+B 然后按 D [Y/N]:${background}
    else
        echo
        echo -en ${green}${Start_Stop_Restart}等待超时 是否打开窗口 进入TMUX窗口后，退出请按 Ctrl+B 然后按 D [Y/N]:${background}
    fi
    read YN
    case ${YN} in
    Y|y)
        bot_tmux_attach_log meme_generator
    ;;
    *)
        # 询问是否开启自动更新
        setup_auto_update
        echo -en ${cyan}回车返回${background}
        read
        echo
    ;;
    esac
}

Pm2_Start(){
if [ -x "$(command -v pm2)" ]
then
    if ! pm2 show meme_generator | grep -q online > /dev/null 2>&1
    then
        export Boolean=true
        pm2 start --name meme_generator "cd ${install_path}/meme-generator && source venv/bin/activate && python -m meme_generator.app"
        echo
        echo -en ${yellow}meme生成器已经启动,是否打开日志 [Y/n]${background}
        read YN
        case ${YN} in
        Y|y)
            pm2 log meme_generator
            echo
            ;;
        *)
            # 询问是否开启自动更新
            setup_auto_update
            ;;
        esac
    fi
else
    echo -e ${red}没有安装pm2，请先安装pm2！${background}
    echo -e ${green}可以使用命令: npm install -g pm2${background}
    echo -en ${yellow}回车返回${background};read
    return
fi
}

echo
echo -e ${white}"====="${green}呆毛版-meme生成器${white}"====="${background}
echo -e ${cyan}请选择启动方式${background}
echo -e  ${green}1.  ${cyan}前台启动${background}
echo -e  ${green}2.  ${cyan}TMUX后台启动（推荐）${background}
# echo -e  ${green}3.  ${cyan}PM2后台启动${background}
echo "========================="
echo -en ${green}请输入您的选项: ${background};read num
case ${num} in 
1)
Foreground_Start
;;
2)
Tmux_Start
;;
# 3)
# Pm2_Start # 因为自动更新重启后使用 tmux 所以关闭这个选项
# ;;
*)
echo
echo -e ${red}输入错误${background}
exit
;;
esac
}

stop_meme_generator(){
Port=$(grep -E "port" ${config} | awk '{print $3}')
if meme_curl
then
    echo -e ${yellow}正在停止meme生成器${background}
    export Boolean=false
    tmux_kill_session meme_generator > /dev/null 2>&1
    pm2 delete meme_generator > /dev/null 2>&1
    PID=$(ps aux | grep "meme_generator.app" | sed '/grep/d' | awk '{print $2}')
    if ! [ -z "${PID}" ];then
        kill ${PID}
    fi
    echo -en ${red}meme生成器停止成功 ${cyan}回车返回${background}
    read
    echo
    return
else
    echo -en ${red}meme生成器未启动 ${cyan}回车返回${background}
    read
    echo
    return
fi
}

restart_meme_generator(){
if tmux_ls meme_generator > /dev/null 2>&1 
then
    tmux_kill_session meme_generator
    export Start_Stop_Restart="重启"
    start_meme_generator
elif pm2 show meme_generator | grep -q online > /dev/null 2>&1
then
    pm2 delete meme_generator
    start_meme_generator
else
    echo -e ${red}meme生成器未启动或为后台运行${background}
    echo
    return
fi
}

update_meme_generator(){
Port=$(grep -E "port" ${config} | awk '{print $3}')
if meme_curl
then
    echo -e ${yellow}正在停止meme生成器${background}
    tmux_kill_session meme_generator > /dev/null 2>&1
    pm2 delete meme_generator > /dev/null 2>&1
    PID=$(ps aux | grep "meme_generator.app" | sed '/grep/d' | awk '{print $2}')
    if [ ! -z "${PID}" ];then
        kill -9 ${PID}
    fi
    echo
fi

echo -e ${yellow}正在更新meme生成器...${background}
cd ${install_path}/meme-generator
git fetch --all
git reset --hard origin/main
git pull

source venv/bin/activate
python -m pip install .

echo -e ${yellow}正在更新meme-generator-contrib...${background}
cd ${install_path}/meme-generator-contrib
git fetch --all
git reset --hard origin/main
git pull

echo -e ${yellow}正在更新meme_emoji...${background}
cd ${install_path}/meme_emoji
git fetch --all
git reset --hard origin/main
git pull

echo -e ${green}更新完成！${background}
echo -en ${yellow}是否重新启动meme生成器? [Y/n]${background};read yn
case ${yn} in
Y|y)
    start_meme_generator
    ;;
esac
}

uninstall_meme_generator(){
if [ ! -d ${install_path}/meme-generator ];then
    echo -en ${red}您还没有安装meme生成器! ${cyan}回车返回${background};read
    return
fi

echo -e ${yellow}正在停止meme生成器...${background}
tmux_kill_session meme_generator > /dev/null 2>&1
pm2 delete meme_generator > /dev/null 2>&1
PID=$(ps aux | grep "meme_generator.app" | sed '/grep/d' | awk '{print $2}')
if [ ! -z "${PID}" ];then
    kill -9 ${PID}
fi

echo -e ${yellow}是否保留配置文件? [Y/n]${background};read yn
case ${yn} in
N|n)
    rm -rf $HOME/.config/meme_generator
    ;;
esac

rm -rf ${install_path}
echo -e ${green}meme生成器卸载完成！${background}
echo -en ${yellow}回车返回${background};read
}

log_meme_generator(){
  echo -en ${yellow}进入TMUX窗口后，退出请按 Ctrl+B 然后按 D${background};read
  Port=$(grep -E "port" ${config} | awk '{print $3}')
  if ! meme_curl
  then
      echo -en ${red}meme生成器未启动 ${cyan}回车返回${background};read
      echo
      return
  fi
  if tmux_ls meme_generator > /dev/null 2>&1 
  then
      bot_tmux_attach_log meme_generator
  elif pm2 show meme_generator | grep -q online > /dev/null 2>&1
  then
      pm2 logs meme_generator
  fi
}

change_port(){
if [ ! -f ${config} ]; then
    echo -e ${red}配置文件不存在，请先安装meme生成器!${background}
    echo -en ${yellow}回车返回${background};read
    return
fi

OldPort=$(grep -E "port" ${config} | awk '{print $3}')
echo -e ${cyan}当前端口: ${green}${OldPort}${background}
echo -e ${cyan}请输入新端口号: ${background};read NewPort

if [[ ! ${NewPort} =~ ^[0-9]+$ ]]; then
    echo -e ${red}请输入有效的端口号!${background}
    echo -en ${yellow}回车返回${background};read
    return
fi

# 修改配置文件中的端口
sed -i "s/port = ${OldPort}/port = ${NewPort}/g" ${config}
echo -e ${green}端口已修改为: ${NewPort}${background}

echo -e ${yellow}是否重启meme生成器以应用新端口? [Y/n]${background};read yn
case ${yn} in
Y|y)
    restart_meme_generator
    ;;
*)
    echo -e ${yellow}请记得手动重启meme生成器以应用新端口${background}
    echo -en ${yellow}回车返回${background};read
    ;;
esac
}

ensure_script_saved() {
  script_dir="$(dirname "$SCRIPT_LOCAL_PATH")"
  mkdir -p "$script_dir"
  current_version=${SCRIPT_VERSION}
  # 检查本地脚本版本
  local_version=""
  if [[ -f "$SCRIPT_LOCAL_PATH" ]]; then
    local_version=$(grep "^SCRIPT_VERSION=" "$SCRIPT_LOCAL_PATH" | head -n 1 | cut -d'"' -f2)
  fi
  # 如果本地脚本不存在或版本不同，则需要更新
  if [[ ! -f "$SCRIPT_LOCAL_PATH" ]] || [[ -z "$local_version" ]] || [[ "$current_version" != "$local_version" ]]; then
    download_script() {
      # 如果当前脚本是从标准输入或临时文件运行的，则从远程下载
      curl -sL "https://gitee.com/Misaka21011/Yunzai-Bot-Shell/raw/master/Manage/meme_generator.sh" > "$SCRIPT_LOCAL_PATH"
      if [ $? -eq 0 ]; then
          chmod +x "$SCRIPT_LOCAL_PATH"
      else
          curl -sL "https://raw.githubusercontent.com/misaka20002/Bot-Install-Shell/refs/heads/master/Manage/meme_generator.sh" > "$SCRIPT_LOCAL_PATH"
          if [ $? -eq 0 ]; then
            chmod +x "$SCRIPT_LOCAL_PATH"
          else
            echo "警告: 脚本更新失败，meme服务器自动更新服务可能出错，请检查网络连接"
            return 1
          fi
      fi
      return 0
    }
    download_script
  else
    # 版本相同，不需要更新
    return 0
  fi
  return 0
}

log_file(){
  # 限制日志文件最大行数为1000行
  log_path="${HOME}/.config/meme_generator/auto_update.log"
  if [ -f "$log_path" ]; then
    line_count=$(wc -l < "$log_path")
    if [ "$line_count" -gt 1000 ]; then
      # 保留最后1000行
      tail -n 1000 "$log_path" > "${log_path}.tmp"
      mv "${log_path}.tmp" "$log_path"
      echo -e "${yellow}[$(date "+%Y-%m-%d %H:%M:%S")] 日志已截断至1000行${background}" >> "$log_path"
    fi
  fi
}

auto_update_meme_generator(){
  log_file="${HOME}/.config/meme_generator/auto_update.log"
  mkdir -p "${HOME}/.config/meme_generator"
  # 先检查并限制日志行数
  log_file
  
  echo -e "${yellow}[$(date "+%Y-%m-%d %H:%M:%S")] 开始自动更新meme生成器...${background}" >> ${log_file}
  
  # 检查meme生成器是否在运行
  was_running=false
  if meme_curl; then
    was_running=true
    echo -e "${yellow}[$(date "+%Y-%m-%d %H:%M:%S")] 正在停止meme生成器${background}" >> ${log_file}
    tmux_kill_session meme_generator > /dev/null 2>&1
    pm2 delete meme_generator > /dev/null 2>&1
    PID=$(ps aux | grep "meme_generator.app" | sed '/grep/d' | awk '{print $2}')
    if [ ! -z "${PID}" ]; then
      kill -9 ${PID}
    fi
  fi

  # 更新meme-generator
  echo -e "${yellow}[$(date "+%Y-%m-%d %H:%M:%S")] 正在更新meme生成器...${background}" >> ${log_file}
  if ! git_update "${install_path}/meme-generator" "${log_file}"; then
    echo -e "${red}[$(date "+%Y-%m-%d %H:%M:%S")] meme-generator更新失败${background}" >> ${log_file}
  else
    source venv/bin/activate
    python -m pip install . >> ${log_file} 2>&1
  fi

  source venv/bin/activate
  python -m pip install . >> ${log_file} 2>&1

  # 更新meme-generator-contrib
  echo -e "${yellow}[$(date "+%Y-%m-%d %H:%M:%S")] 正在更新meme-generator-contrib...${background}" >> ${log_file}
  if ! git_update "${install_path}/meme-generator-contrib" "${log_file}"; then
    echo -e "${red}[$(date "+%Y-%m-%d %H:%M:%S")] meme-generator-contrib更新失败${background}" >> ${log_file}
  fi

  # 更新meme_emoji
  echo -e "${yellow}[$(date "+%Y-%m-%d %H:%M:%S")] 正在更新meme_emoji...${background}" >> ${log_file}
  if ! git_update "${install_path}/meme_emoji" "${log_file}"; then
    echo -e "${red}[$(date "+%Y-%m-%d %H:%M:%S")] meme_emoji更新失败${background}" >> ${log_file}
  fi

  echo -e "${green}[$(date "+%Y-%m-%d %H:%M:%S")] 更新完成！${background}" >> ${log_file}
  
  # 如果之前在运行，则重新启动 - 修复启动部分
  if $was_running; then
    echo -e "${yellow}[$(date "+%Y-%m-%d %H:%M:%S")] 正在重新启动meme生成器...${background}" >> ${log_file}
    export Boolean=true
    # 将输出重定向从tmux_new命令中移出，确保tmux命令能正常执行
    tmux_new meme_generator "cd ${install_path}/meme-generator && source venv/bin/activate && while ${Boolean}; do python -m meme_generator.app; echo -e ${red}meme生成器关闭 正在重启${background}; sleep 2s; done"
    # 记录启动结果
    if tmux_ls meme_generator; then
      echo -e "${green}[$(date "+%Y-%m-%d %H:%M:%S")] meme生成器成功启动${background}" >> ${log_file}
    else
      echo -e "${red}[$(date "+%Y-%m-%d %H:%M:%S")] meme生成器启动失败${background}" >> ${log_file}
    fi
  fi
}

setup_auto_update(){
      # 禁用cron定时自动更新
      echo -en ${yellow}cron定时方案无法执行自动更新，已禁用cron定时自动更新功能，请自己有空的时候手动更新哦${background};read
      return


  echo -en ${yellow}是否开启meme生成器自动更新? [Y/n]:${background};read yn
  echo -e ${cyan}启动meme生成器之后将会在每天凌晨1点自动同步更新 meme GitHub 仓库并重启${background}
  case ${yn} in
  N|n)
    # 如果用户选择不开启自动更新，但已经存在cron任务，则删除它
    if crontab -l 2>/dev/null | grep -q "meme_generator_auto_update"; then
      crontab -l 2>/dev/null | grep -v "meme_generator_auto_update" | crontab -
      echo -e ${yellow}已关闭meme生成器的自动更新${background}
    fi
    ;;
  *)
    # 确保脚本已保存到固定位置
    ensure_script_saved
    
    # 检查是否已经存在相同的cron任务
    if ! crontab -l 2>/dev/null | grep -q "meme_generator_auto_update"; then
      (crontab -l 2>/dev/null; echo "0 1 * * * bash ${SCRIPT_LOCAL_PATH} auto_update # meme_generator_auto_update") | crontab -
      echo -e ${green}已设置每天凌晨1点自动更新meme生成器${background}
      echo -e ${cyan}自动更新日志位置: ${HOME}/.config/meme_generator/auto_update.log${background}
    fi
    ;;
  esac
}

toggle_auto_update(){
  # 确保脚本已保存到固定位置
  ensure_script_saved
  
  if crontab -l 2>/dev/null | grep -q "meme_generator_auto_update"; then
    # 如果已经存在，则删除自动更新的cron任务
    crontab -l 2>/dev/null | grep -v "meme_generator_auto_update" | crontab -
    echo -e ${yellow}已关闭meme生成器的自动更新${background}
  else
      # 禁用cron定时自动更新
      echo -en ${yellow}cron定时方案无法执行自动更新，已禁用cron定时自动更新功能，请自己有空的时候手动更新哦${background};read
      return


    # 如果不存在，则添加自动更新的cron任务
    (crontab -l 2>/dev/null; echo "0 1 * * * bash ${SCRIPT_LOCAL_PATH} auto_update # meme_generator_auto_update") | crontab -
    echo -e ${green}已开启meme生成器的自动更新${background}
    echo -e ${cyan}启动meme生成器之后将会在每天凌晨1点自动同步更新 meme GitHub 仓库并重启${background}
    echo -e ${cyan}自动更新日志位置: ${HOME}/.config/meme_generator/auto_update.log${background}
  fi
  echo -en ${yellow}回车返回${background};read
}

rewrite_config(){
    if [ ! -d ${install_path}/meme-generator ]; then
        echo -e ${red}您还没有安装meme生成器！${background}
        echo -en ${yellow}回车返回${background};read
        return
    fi
    
    echo -e ${yellow}此操作将重写meme生成器的配置文件${background}
    echo -e ${red}警告：您的自定义设置将会丢失${background}
    echo -en ${cyan}是否继续？[y/N]: ${background};read confirm
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo -e ${yellow}已取消操作${background}
        echo -en ${yellow}回车返回${background};read
        return
    fi
    
    # 检查是否需要先停止服务
    meme_was_running=false
    if meme_curl; then
        meme_was_running=true
        echo -e ${yellow}正在停止meme生成器...${background}
        tmux_kill_session meme_generator > /dev/null 2>&1
        pm2 delete meme_generator > /dev/null 2>&1
        PID=$(ps aux | grep "meme_generator.app" | sed '/grep/d' | awk '{print $2}')
        if [ ! -z "${PID}" ]; then
            kill -9 ${PID}
        fi
    fi
    
    # 备份当前配置
    if [ -f ${config} ]; then
        backup_file="${config}.backup.$(date +%Y%m%d%H%M%S)"
        cp ${config} ${backup_file}
        echo -e ${green}已备份原配置文件至: ${backup_file}${background}
    fi
    
    # 创建配置文件目录
    mkdir -p $HOME/.config/meme_generator
    
    # 重写配置文件
    cat > ${config} << EOF
[meme]
load_builtin_memes = true  # 是否加载内置表情包
meme_dirs = ["${install_path}/meme-generator-contrib/memes", "${install_path}/meme_emoji/emoji"]  # 加载其他位置的表情包，填写文件夹路径
meme_disabled_list = []  # 禁用的表情包列表，填写表情的 \`key\`

[resource]
# 下载内置表情包图片时的资源链接，下载时选择最快的站点
resource_urls = [
  "https://raw.githubusercontent.com/MeetWq/meme-generator/",
  "https://ghproxy.com/https://raw.githubusercontent.com/MeetWq/meme-generator/",
  "https://fastly.jsdelivr.net/gh/MeetWq/meme-generator@",
  "https://raw.fastgit.org/MeetWq/meme-generator/",
  "https://raw.fgit.ml/MeetWq/meme-generator/",
  "https://raw.gitmirror.com/MeetWq/meme-generator/",
  "https://raw.kgithub.com/MeetWq/meme-generator/",
]

[gif]
gif_max_size = 10.0  # 限制生成的 gif 文件大小，单位为 Mb
gif_max_frames = 100  # 限制生成的 gif 文件帧数

[translate]
baidu_trans_appid = ""  # 百度翻译api相关，表情包 \`dianzhongdian\` 需要使用
baidu_trans_apikey = ""  # 可在 百度翻译开放平台 (http://api.fanyi.baidu.com) 申请

[server]
host = "0.0.0.0"  # web server 监听地址
port = 50835  # web server 端口

[log]
log_level = "INFO"  # 日志等级
EOF

    echo -e ${green}配置文件已重写为默认设置${background}
    
    # 询问是否重启服务
    if [ "$meme_was_running" = true ]; then
        echo -en ${yellow}是否重新启动meme生成器? [Y/n]:${background};read yn
        case ${yn} in
        N|n)
            echo -e ${yellow}请记得手动重启meme生成器以应用新配置${background}
            ;;
        *)
            echo -e ${yellow}正在重启meme生成器...${background}
            export Boolean=true
            tmux_new meme_generator "cd ${install_path}/meme-generator && source venv/bin/activate && while ${Boolean}; do python -m meme_generator.app; echo -e ${red}meme生成器关闭 正在重启${background}; sleep 2s; done"
            if tmux_gauge meme_generator; then
                echo -e ${green}meme生成器已成功重启${background}
            else
                echo -e ${red}meme生成器重启超时，请手动检查${background}
            fi
            ;;
        esac
    fi
    
    echo -en ${yellow}回车返回${background};read
}

view_auto_update_log(){
  log_file="${HOME}/.config/meme_generator/auto_update.log"
  
  if [ ! -f "$log_file" ]; then
    echo -e ${red}日志文件不存在，可能自动更新尚未运行过${background}
    echo -en ${yellow}回车返回${background};read
    return
  fi
  
  echo -e ${yellow}正在查看自动更新服务日志内容（按q退出）:${background}
  echo -en ${yellow}回车继续${background};read
  less -R "$log_file"
  
  echo -en ${yellow}回车返回${background};read
}

# 添加更换Github代理的函数
change_github_proxy(){
    if [ ! -d ${install_path}/meme-generator ]; then
        echo -e ${red}您还没有安装meme生成器！${background}
        echo -en ${yellow}回车返回${background};read
        return
    fi

    echo -e ${white}"====="${green}更换GitHub代理${white}"====="${background}
    echo -e ${cyan}当前可用的GitHub代理:${background}
    echo -e ${green}1.${cyan} 无代理 \(直接访问github.com\)${background}
    echo -e ${green}2.${cyan} ghfast.top \(${GithubMirror_1:-"https://ghfast.top/"}\)${background}
    echo -e ${green}3.${cyan} git.ppp.ac.cn \(${GithubMirror_2:-"https://git.ppp.ac.cn/"}\)${background}
    echo -e ${green}4.${cyan} gh-proxy.com \(${GithubMirror_3:-"https://gh-proxy.com/"}\)${background}
    echo -e ${green}5.${cyan} 自定义代理${background}
    echo "========================="
    
    # 显示当前各仓库的远程URL
    echo -e ${cyan}当前仓库远程URL:${background}
    if [ -d "${install_path}/meme-generator" ]; then
        echo -n -e ${yellow}meme-generator: ${background}
        cd "${install_path}/meme-generator" && git remote get-url origin 2>/dev/null || echo -e ${red}未找到${background}
    fi
    if [ -d "${install_path}/meme-generator-contrib" ]; then
        echo -n -e ${yellow}meme-generator-contrib: ${background}
        cd "${install_path}/meme-generator-contrib" && git remote get-url origin 2>/dev/null || echo -e ${red}未找到${background}
    fi
    if [ -d "${install_path}/meme_emoji" ]; then
        echo -n -e ${yellow}meme_emoji: ${background}
        cd "${install_path}/meme_emoji" && git remote get-url origin 2>/dev/null || echo -e ${red}未找到${background}
    fi
    echo "========================="
    
    echo -en ${green}请选择要使用的GitHub代理 [1-5]: ${background};read proxy_choice
    
    case ${proxy_choice} in
    1)
        new_proxy=""
        proxy_name="无代理"
        ;;
    2)
        new_proxy="${GithubMirror_1:-"https://ghfast.top/"}"
        proxy_name="ghfast.top"
        ;;
    3)
        new_proxy="${GithubMirror_2:-"https://git.ppp.ac.cn/"}"
        proxy_name="git.ppp.ac.cn"
        ;;
    4)
        new_proxy="${GithubMirror_3:-"https://gh-proxy.com/"}"
        proxy_name="gh-proxy.com"
        ;;
    5)
        echo -en ${cyan}请输入自定义代理地址 \(如: https://mirror.example.com/\): ${background};read custom_proxy
        if [[ ! ${custom_proxy} =~ ^https?:// ]]; then
            echo -e ${red}代理地址格式错误，请以http://或https://开头${background}
            echo -en ${yellow}回车返回${background};read
            return
        fi
        new_proxy="${custom_proxy}"
        proxy_name="自定义代理"
        ;;
    *)
        echo -e ${red}选择无效${background}
        echo -en ${yellow}回车返回${background};read
        return
        ;;
    esac
    
    echo -e ${yellow}正在更换GitHub代理为: ${green}${proxy_name}${background}
    
    # 更新各个仓库的远程URL
    repos=(
        "${install_path}/meme-generator:https://github.com/MemeCrafters/meme-generator.git"
        "${install_path}/meme-generator-contrib:https://github.com/MemeCrafters/meme-generator-contrib.git"
        "${install_path}/meme_emoji:https://github.com/anyliew/meme_emoji.git"
    )
    
    success_count=0
    total_count=0
    
    for repo_info in "${repos[@]}"; do
        repo_path="${repo_info%%:*}"
        original_url="${repo_info##*:}"
        
        if [ -d "${repo_path}" ]; then
            total_count=$((total_count + 1))
            echo -e ${yellow}正在更新 $(basename ${repo_path}) 的远程URL...${background}
            
            cd "${repo_path}"
            if [ -z "${new_proxy}" ]; then
                # 无代理，使用原始URL
                new_url="${original_url}"
            else
                # 使用代理
                new_url="${new_proxy}${original_url}"
            fi
            
            if git remote set-url origin "${new_url}" 2>/dev/null; then
                echo -e ${green}✓ $(basename ${repo_path}): ${new_url}${background}
                success_count=$((success_count + 1))
            else
                echo -e ${red}✗ $(basename ${repo_path}): 更新失败${background}
            fi
        fi
    done
    
    echo "========================="
    if [ ${success_count} -eq ${total_count} ] && [ ${total_count} -gt 0 ]; then
        echo -e ${green}所有仓库的GitHub代理已成功更换为: ${proxy_name}${background}
        
        # 测试连接
        echo -e ${yellow}正在测试新代理的连接性...${background}
        cd "${install_path}/meme-generator"
        if git ls-remote origin >/dev/null 2>&1; then
            echo -e ${green}✓ 代理连接测试成功${background}
        else
            echo -e ${red}✗ 代理连接测试失败，您可能需要尝试其他代理${background}
        fi
        
        echo -en ${yellow}是否立即测试更新功能? [Y/n]: ${background};read test_update
        case ${test_update} in
        N|n)
            ;;
        *)
            echo -e ${yellow}正在测试更新meme-generator...${background}
            cd "${install_path}/meme-generator"
            if git fetch --dry-run 2>/dev/null; then
                echo -e ${green}✓ 更新测试成功，新代理工作正常${background}
            else
                echo -e ${red}✗ 更新测试失败，可能需要更换其他代理${background}
            fi
            ;;
        esac
    else
        echo -e ${red}部分仓库的代理更换失败 \(${success_count}/${total_count}\)${background}
    fi
    
    echo -en ${yellow}回车返回${background};read
}

main(){
# 如果是首次通过curl执行，确保先保存脚本
if [[ "$0" == *"/dev/fd/"* || "$0" == "bash" ]]; then
  ensure_script_saved
fi

if crontab -l 2>/dev/null | grep -q "meme_generator_auto_update"; then
    auto_update_condition="${green}[运行中]"
else
    auto_update_condition="${red}[未启动]"
fi

if [ -d ${install_path}/meme-generator ]; then
    Port=$(grep -E "port" ${config} | awk '{print $3}')
    if meme_curl
    then
        condition="${green}[运行中]"
    else
        condition="${red}[未启动]"
    fi
else
    condition="${red}[未安装]"
fi

echo -e ${white}"====="${green}呆毛版-meme生成器${white}"====="${background}
echo -e  ${green} 1.  ${cyan}安装meme生成器${background}
echo -e  ${green} 2.  ${cyan}启动meme生成器${background}
echo -e  ${green} 3.  ${cyan}关闭meme生成器${background}
echo -e  ${green} 4.  ${cyan}重启meme生成器${background}
echo -e  ${green} 5.  ${cyan}更新meme生成器${background}
echo -e  ${green} 6.  ${cyan}卸载meme生成器${background}
echo -e  ${green} 7.  ${cyan}meme生成器日志${background}
echo -e  ${green} 8.  ${cyan}查看自动更新服务日志${background}
echo -e  ${green} 9.  ${cyan}修改meme端口号${background}
echo -e  ${green} 10.  ${cyan}切换自动更新设置${background}
echo -e  ${green} 11.  ${cyan}重写配置文件${background}
echo -e  ${green} 12.  ${cyan}更换Github代理${background}
echo -e  ${green} 0.  ${cyan}退出${background}
echo "========================="
echo -e ${green}meme生成器状态: ${condition}${background}
echo -e ${green}meme自动更新服务: ${auto_update_condition}${background}
echo -e ${green}QQ群:${cyan}呆毛版-QQ群:285744328${background}
echo "========================="
echo
echo -en ${green}请输入您的选项: ${background};read number
case ${number} in
1)
echo
install_meme_generator
;;
2)
echo
start_meme_generator
;;
3)
echo
stop_meme_generator
;;
4)
echo
restart_meme_generator
;;
5)
echo
update_meme_generator
;;
6)
echo
uninstall_meme_generator
;;
7)
log_meme_generator
;;
8)
echo
view_auto_update_log
;;
9)
echo
change_port
;;
10)
echo
toggle_auto_update
;;
11)
echo
rewrite_config
;;
12)
echo
change_github_proxy
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

if [ "$1" = "auto_update" ]; then
  auto_update_meme_generator
  exit 0
else
  mainbak
fi
