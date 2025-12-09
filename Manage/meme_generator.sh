#!/bin/env bash
SCRIPT_VERSION="1.0.22"

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

# 检查是否为 Debian 系系统
if [ ! -f /etc/debian_version ] && [ ! -f /etc/lsb-release ]; then
    if ! command -v apt >/dev/null 2>&1 && ! command -v apt-get >/dev/null 2>&1; then
        echo -e ${red}此脚本仅支持基于 Debian 的 Linux 发行版（如 Ubuntu、Debian 等）${background}
        echo -e ${red}检测到您的系统不是 Debian 系，程序将退出${background}
        exit 1
    fi
fi

URL="https://ipinfo.io"
Address=$(curl -sL ${URL} | sed -n 's/.*"country": "\(.*\)",.*/\1/p')
if [ "${Address}" = "CN" ]
then
  GitMirror="gitee.com"
  GithubMirror_1="https://ghfast.top/"
  GithubMirror_2="https://gh-proxy.com/"
  # GithubMirror_3="https://git.ppp.ac.cn/"
else
  GitMirror="github.com"
  GithubMirror_1=""
  GithubMirror_2=""
  # GithubMirror_3=""
fi

config=$HOME/.config/meme_generator/config.toml
install_path=$HOME/memeGenerator
SCRIPT_SYSTEM_PATH="/usr/local/bin/meme_generator.sh"

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
  
  # 检查是否需要显示进度（如果log_file是/dev/null则显示进度）
  show_progress=false
  if [ "$log_file" = "/dev/null" ]; then
    show_progress=true
  fi
  
  # 先尝试使用主镜像
  if [ "$show_progress" = true ]; then
    echo -e "${cyan}正在从主镜像克隆...${background}"
    if git clone --progress ${GithubMirror_1}${repo_url} ${target_dir} 2>&1 | tee -a ${log_file}; then
      return 0
    fi
  else
    if git clone ${GithubMirror_1}${repo_url} ${target_dir} >> ${log_file} 2>&1; then
      return 0
    fi
  fi
  
  echo -e "${yellow}主镜像访问失败，尝试使用备用镜像...${background}"
  [ "$show_progress" = false ] && echo -e "${yellow}主镜像访问失败，尝试使用备用镜像...${background}" >> ${log_file}
  
  # 尝试使用备用镜像
  if [ "$show_progress" = true ]; then
    echo -e "${cyan}正在从备用镜像克隆...${background}"
    if git clone --progress ${GithubMirror_2}${repo_url} ${target_dir} 2>&1 | tee -a ${log_file}; then
      return 0
    fi
  else
    if git clone ${GithubMirror_2}${repo_url} ${target_dir} >> ${log_file} 2>&1; then
      return 0
    fi
  fi
  
  # 都失败了，尝试直接访问
  echo -e "${yellow}备用镜像也失败，尝试直接访问...${background}"
  [ "$show_progress" = false ] && echo -e "${yellow}备用镜像也失败，尝试直接访问...${background}" >> ${log_file}
  
  if [ "$show_progress" = true ]; then
    echo -e "${cyan}正在从GitHub直接克隆...${background}"
    if git clone --progress ${repo_url} ${target_dir} 2>&1 | tee -a ${log_file}; then
      return 0
    else
      return 1
    fi
  else
    if git clone ${repo_url} ${target_dir} >> ${log_file} 2>&1; then
      return 0
    else
      return 1
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

# 创建 pip 配置文件，添加国内镜像源
echo -e ${green}配置pip国内镜像源...${background}
mkdir -p $HOME/.pip
cat > $HOME/.pip/pip.conf << EOF
[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple/
extra-index-url = https://pypi.mirrors.ustc.edu.cn/simple/
trusted-host = pypi.tuna.tsinghua.edu.cn
               pypi.mirrors.ustc.edu.cn
timeout = 120
retries = 5
EOF

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
meme_dirs = ["${install_path}/meme-generator-contrib/memes", "${install_path}/meme_emoji/emoji", "${install_path}/meme-generator-jj/memes", "${install_path}/meme_emoji_nsfw/emoji"]  # 加载其他位置的表情包，填写文件夹路径
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

# 下载额外图片 - 3
echo -e ${green}下载额外图片meme-generator-jj...${background}
if ! git_clone "https://github.com/jinjiao007/meme-generator-jj.git" "${install_path}/meme-generator-jj" "/dev/null"; then
  echo -e ${red}克隆meme-generator-jj仓库失败${background}
  echo -e ${yellow}继续安装其他组件...${background}
fi

# 下载额外图片 - 4
echo -e ${green}下载额外图片meme_emoji_nsfw...${background}
if ! git_clone "https://github.com/anyliew/meme_emoji_nsfw.git" "${install_path}/meme_emoji_nsfw" "/dev/null"; then
  echo -e ${red}克隆meme_emoji_nsfw仓库失败${background}
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
    if [ -n "${PID}" ];then
        kill -9 ${PID}
    fi
    echo
fi

echo -e ${yellow}正在更新meme生成器...${background}
if ! git_update "${install_path}/meme-generator" "/dev/null"; then
  echo -e ${red}更新meme-generator失败${background}
  echo -e ${yellow}继续更新其他组件...${background}
fi

cd ${install_path}/meme-generator
source venv/bin/activate
python -m pip install .

echo -e ${yellow}正在更新meme-generator-contrib...${background}
if ! git_update "${install_path}/meme-generator-contrib" "/dev/null"; then
  echo -e ${red}更新meme-generator-contrib失败${background}
  echo -e ${yellow}继续更新其他组件...${background}
fi

echo -e ${yellow}正在更新meme_emoji...${background}
if ! git_update "${install_path}/meme_emoji" "/dev/null"; then
  echo -e ${red}更新meme_emoji失败${background}
  echo -e ${yellow}继续更新其他组件...${background}
fi

echo -e ${yellow}正在更新meme-generator-jj...${background}
if ! git_update "${install_path}/meme-generator-jj" "/dev/null"; then
  echo -e ${red}更新meme-generator-jj失败${background}
  echo -e ${yellow}继续更新其他组件...${background}
fi

echo -e ${yellow}正在更新meme_emoji_nsfw...${background}
if ! git_update "${install_path}/meme_emoji_nsfw" "/dev/null"; then
  echo -e ${red}更新meme_emoji_nsfw失败${background}
  echo -e ${yellow}继续...${background}
fi

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
if [ -n "${PID}" ];then
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
echo -e ${cyan}请确保您的防火墙已开放端口: ${background}
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
echo -e ${yellow}请确保您的防火墙已开放${NewPort}端口${background}

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
  current_version=${SCRIPT_VERSION}
  # 检查系统脚本版本
  local_version=""
  if [[ -f "$SCRIPT_SYSTEM_PATH" ]]; then
    local_version=$(grep "^SCRIPT_VERSION=" "$SCRIPT_SYSTEM_PATH" | head -n 1 | cut -d'"' -f2)
  fi
  # 如果系统脚本不存在或版本不同，则需要更新
  if [[ ! -f "$SCRIPT_SYSTEM_PATH" ]] || [[ -z "$local_version" ]] || [[ "$current_version" != "$local_version" ]]; then
    download_script() {
      # 从远程下载脚本到系统目录
      if curl -sL "https://gitee.com/Misaka21011/Yunzai-Bot-Shell/raw/master/Manage/meme_generator.sh" > "$SCRIPT_SYSTEM_PATH"; then
        chmod +x "$SCRIPT_SYSTEM_PATH"
        return 0
      else
        if curl -sL "https://raw.githubusercontent.com/misaka20002/Bot-Install-Shell/refs/heads/master/Manage/meme_generator.sh" > "$SCRIPT_SYSTEM_PATH"; then
          chmod +x "$SCRIPT_SYSTEM_PATH"
          return 0
        else
          echo "警告: 脚本更新失败，meme服务器自动更新服务可能出错，请检查网络连接"
          return 1
        fi
      fi
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
  
  # 设置 cron 环境变量
  export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  export HOME="${HOME:-/root}"
  export SHELL="${SHELL:-/bin/bash}"
  
  echo -e "${yellow}[$(date "+%Y-%m-%d %H:%M:%S")] 开始自动更新meme生成器...${background}" >> ${log_file}
  echo -e "${yellow}[$(date "+%Y-%m-%d %H:%M:%S")] 当前PATH: $PATH${background}" >> ${log_file}
  echo -e "${yellow}[$(date "+%Y-%m-%d %H:%M:%S")] 当前HOME: $HOME${background}" >> ${log_file}
  
  # 检查关键命令是否可用
  if ! command -v tmux >/dev/null 2>&1; then
    echo -e "${red}[$(date "+%Y-%m-%d %H:%M:%S")] 错误: 找不到 tmux 命令${background}" >> ${log_file}
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo -e "${red}[$(date "+%Y-%m-%d %H:%M:%S")] 错误: 找不到 python3 命令${background}" >> ${log_file}
  fi
  
  # 检查meme生成器是否在运行
  was_running=false
  if meme_curl; then
    was_running=true
    echo -e "${yellow}[$(date "+%Y-%m-%d %H:%M:%S")] 正在停止meme生成器${background}" >> ${log_file}
    /usr/bin/tmux kill-session -t meme_generator > /dev/null 2>&1
    if command -v pm2 >/dev/null 2>&1; then
      pm2 delete meme_generator > /dev/null 2>&1
    fi
    PID=$(ps aux | grep "meme_generator.app" | sed '/grep/d' | awk '{print $2}')
    if [ -n "${PID}" ]; then
      kill -9 ${PID}
    fi
  fi

  # 更新meme-generator
  echo -e "${yellow}[$(date "+%Y-%m-%d %H:%M:%S")] 正在更新meme生成器...${background}" >> ${log_file}
  if ! git_update "${install_path}/meme-generator" "${log_file}"; then
    echo -e "${red}[$(date "+%Y-%m-%d %H:%M:%S")] meme-generator更新失败${background}" >> ${log_file}
  else
    cd "${install_path}/meme-generator"
    if [ -f "venv/bin/activate" ]; then
      source venv/bin/activate >> ${log_file} 2>&1
      python -m pip install . >> ${log_file} 2>&1
    else
      echo -e "${red}[$(date "+%Y-%m-%d %H:%M:%S")] 虚拟环境不存在${background}" >> ${log_file}
    fi
  fi

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

  # 更新meme-generator-jj
  echo -e "${yellow}[$(date "+%Y-%m-%d %H:%M:%S")] 正在更新meme-generator-jj...${background}" >> ${log_file}
  if ! git_update "${install_path}/meme-generator-jj" "${log_file}"; then
    echo -e "${red}[$(date "+%Y-%m-%d %H:%M:%S")] meme-generator-jj更新失败${background}" >> ${log_file}
  fi

  # 更新meme_emoji_nsfw
  echo -e "${yellow}[$(date "+%Y-%m-%d %H:%M:%S")] 正在更新meme_emoji_nsfw...${background}" >> ${log_file}
  if ! git_update "${install_path}/meme_emoji_nsfw" "${log_file}"; then
    echo -e "${red}[$(date "+%Y-%m-%d %H:%M:%S")] meme_emoji_nsfw更新失败${background}" >> ${log_file}
  fi

  echo -e "${green}[$(date "+%Y-%m-%d %H:%M:%S")] 更新完成！${background}" >> ${log_file}
  
  # 如果之前在运行，则重新启动 - 使用完整路径和环境变量
  if $was_running; then
    echo -e "${yellow}[$(date "+%Y-%m-%d %H:%M:%S")] 正在重新启动meme生成器...${background}" >> ${log_file}
    
    # 检查虚拟环境和必要文件
    if [ ! -f "${install_path}/meme-generator/venv/bin/activate" ]; then
      echo -e "${red}[$(date "+%Y-%m-%d %H:%M:%S")] 虚拟环境不存在，无法启动${background}" >> ${log_file}
      return 1
    fi
    
    # 创建启动脚本
    start_script="/tmp/meme_start.sh"
    cat > ${start_script} << 'EOF'
#!/bin/bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export HOME="/root"
cd /root/memeGenerator/meme-generator
source venv/bin/activate
while true; do
    python -m meme_generator.app
    echo "meme生成器关闭，2秒后重启..."
    sleep 2
done
EOF
    chmod +x ${start_script}
    
    # 使用完整路径启动 tmux
    if /usr/bin/tmux new -s meme_generator -d "/bin/bash ${start_script}" 2>>${log_file}; then
      echo -e "${green}[$(date "+%Y-%m-%d %H:%M:%S")] tmux 会话创建成功${background}" >> ${log_file}
      
      # 等待服务启动
      sleep 15
      if meme_curl; then
        echo -e "${green}[$(date "+%Y-%m-%d %H:%M:%S")] meme生成器成功启动${background}" >> ${log_file}
      else
        echo -e "${red}[$(date "+%Y-%m-%d %H:%M:%S")] meme生成器启动失败${background}" >> ${log_file}
      fi
    else
      echo -e "${red}[$(date "+%Y-%m-%d %H:%M:%S")] tmux 命令执行失败${background}" >> ${log_file}
    fi
    
    # 清理临时脚本
    rm -f ${start_script}
  fi
}

setup_auto_update(){
  echo -en ${yellow}是否开启meme生成器自动更新（启动meme生成器之后将会在每天凌晨1点到6点随机时间自动同步更新 meme GitHub 仓库并重启）? [Y/n]:${background};read yn
  case ${yn} in
  N|n)
    # 如果用户选择不开启自动更新，但已经存在cron任务，则删除它
    if crontab -l 2>/dev/null | grep -q "meme_generator_auto_update"; then
      crontab -l 2>/dev/null | grep -v "meme_generator_auto_update" | crontab -
      echo -e ${yellow}已关闭meme生成器的自动更新${background}
    fi
    ;;
  *)
    # 确保脚本已保存到系统位置
    ensure_script_saved
    
    # 检查是否已经存在相同的cron任务
    if ! crontab -l 2>/dev/null | grep -q "meme_generator_auto_update"; then
      # 生成随机时间：1-6点之间的随机小时，0-59分钟之间的随机分钟
      random_hour=$((1 + RANDOM % 6))
      random_minute=$((RANDOM % 60))
      (crontab -l 2>/dev/null; echo "${random_minute} ${random_hour} * * * /bin/bash -c 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; export HOME=/root; ${SCRIPT_SYSTEM_PATH} auto_update' # meme_generator_auto_update") | crontab -
      echo -e ${green}已设置每天凌晨${random_hour}:$(printf "%02d" ${random_minute})自动更新meme生成器${background}
      echo -e ${cyan}自动更新日志位置: ${HOME}/.config/meme_generator/auto_update.log${background}
    fi
    ;;
  esac
}

toggle_auto_update(){
  # 确保脚本已保存到系统位置
  ensure_script_saved
  
  if crontab -l 2>/dev/null | grep -q "meme_generator_auto_update"; then
    # 如果已经存在，则删除自动更新的cron任务
    crontab -l 2>/dev/null | grep -v "meme_generator_auto_update" | crontab -
    echo -e ${yellow}已关闭meme生成器的自动更新${background}
    
    # 询问是否删除相关文件
    echo -en ${cyan}是否删除系统脚本文件和日志文件? [Y/n]: ${background};read delete_files
    case ${delete_files} in
    N|n)
      echo -e ${yellow}保留了系统脚本文件和日志文件${background}
      ;;
    *)
      # 删除系统脚本文件
      if [ -f "$SCRIPT_SYSTEM_PATH" ]; then
        rm -f "$SCRIPT_SYSTEM_PATH"
        echo -e ${green}已删除系统脚本文件: $SCRIPT_SYSTEM_PATH${background}
      fi
      
      # 删除日志文件
      log_file="${HOME}/.config/meme_generator/auto_update.log"
      if [ -f "$log_file" ]; then
        rm -f "$log_file"
        echo -e ${green}已删除自动更新日志文件: $log_file${background}
      fi
      ;;
    esac
  else
    # 如果不存在，则添加自动更新的cron任务
    # 生成随机时间：1-6点之间的随机小时，0-59分钟之间的随机分钟
    random_hour=$((1 + RANDOM % 6))
    random_minute=$((RANDOM % 60))
    (crontab -l 2>/dev/null; echo "${random_minute} ${random_hour} * * * /bin/bash -c 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; export HOME=/root; ${SCRIPT_SYSTEM_PATH} auto_update' # meme_generator_auto_update") | crontab -
    echo -e ${green}已开启meme生成器的自动更新${background}
    echo -e ${cyan}将在每天凌晨${random_hour}:$(printf "%02d" ${random_minute})自动同步更新 meme GitHub 仓库并重启${background}
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
        if [ -n "${PID}" ]; then
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
meme_dirs = ["${install_path}/meme-generator-contrib/memes", "${install_path}/meme_emoji/emoji", "${install_path}/meme-generator-jj/memes", "${install_path}/meme_emoji_nsfw/emoji"]  # 加载其他位置的表情包，填写文件夹路径
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
    echo -e ${green}3.${cyan} gh-proxy.com \(${GithubMirror_2:-"https://gh-proxy.com/"}\)${background}
    # echo -e ${green}4.${cyan} git.ppp.ac.cn \(${GithubMirror_3:-"https://git.ppp.ac.cn/"}\)${background}
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
        new_proxy="${GithubMirror_2:-"https://gh-proxy.com/"}"
        proxy_name="gh-proxy.com"
        ;;
    # 4)
    #     new_proxy="${GithubMirror_3:-"https://git.ppp.ac.cn/"}"
    #     proxy_name="git.ppp.ac.cn"
    #     ;;
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

# 重新使用 pip 安装依赖
reinstall_pip_dependencies(){
    if [ ! -d ${install_path}/meme-generator ]; then
        echo -e ${red}您还没有安装meme生成器！${background}
        echo -en ${yellow}回车返回${background};read
        return
    fi

    echo -e ${white}"====="${green}重新使用pip安装依赖${white}"====="${background}
    echo -e ${yellow}此操作将重新安装meme生成器的所有Python依赖包${background}
    echo -e ${cyan}适用于以下情况：${background}
    echo -e ${cyan}- 依赖包损坏或缺失${background}
    echo -e ${cyan}- Python环境出现问题${background}
    echo -e ${cyan}- 需要更新到最新版本的依赖${background}
    echo -e ${cyan}- pip安装失败需要重试${background}
    echo "========================="
    
    echo -en ${yellow}是否继续重新安装依赖包？[Y/n]: ${background};read confirm
    case ${confirm} in
    N|n)
        echo -e ${yellow}已取消操作${background}
        echo -en ${yellow}回车返回${background};read
        return
        ;;
    esac

    # 检查是否需要先停止服务
    meme_was_running=false
    if meme_curl; then
        meme_was_running=true
        echo -e ${yellow}检测到meme生成器正在运行，需要先停止服务${background}
        echo -e ${yellow}正在停止meme生成器...${background}
        tmux_kill_session meme_generator > /dev/null 2>&1
        pm2 delete meme_generator > /dev/null 2>&1
        PID=$(ps aux | grep "meme_generator.app" | sed '/grep/d' | awk '{print $2}')
        if [ -n "${PID}" ]; then
            kill -9 ${PID}
        fi
        sleep 2
        echo -e ${green}meme生成器已停止${background}
    fi

    # 确保pip配置文件存在
    echo -e ${yellow}检查pip配置文件...${background}
    if [ ! -f "$HOME/.pip/pip.conf" ]; then
        echo -e ${yellow}pip配置文件不存在，正在创建...${background}
        mkdir -p $HOME/.pip
        cat > $HOME/.pip/pip.conf << EOF
[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple/
extra-index-url = https://pypi.mirrors.ustc.edu.cn/simple/
trusted-host = pypi.tuna.tsinghua.edu.cn
               pypi.mirrors.ustc.edu.cn
timeout = 120
retries = 5
EOF
        echo -e ${green}pip配置文件已创建${background}
    else
        echo -e ${green}pip配置文件已存在，正在更新为最新配置...${background}
        # 更新配置文件为最新的稳定版本
        cat > $HOME/.pip/pip.conf << EOF
[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple/
extra-index-url = https://pypi.mirrors.ustc.edu.cn/simple/
trusted-host = pypi.tuna.tsinghua.edu.cn
               pypi.mirrors.ustc.edu.cn
timeout = 120
retries = 5
EOF
        echo -e ${green}pip配置文件已更新${background}
    fi

    # 进入meme-generator目录
    cd ${install_path}/meme-generator
    
    # 检查虚拟环境是否存在
    if [ ! -d "venv" ]; then
        echo -e ${red}虚拟环境不存在，正在创建新的虚拟环境...${background}
        python3 -m venv venv
        if [ $? -ne 0 ]; then
            echo -e ${red}创建虚拟环境失败！${background}
            echo -en ${yellow}回车返回${background};read
            return
        fi
        echo -e ${green}虚拟环境创建成功${background}
    else
        echo -e ${green}虚拟环境已存在${background}
    fi

    # 激活虚拟环境
    echo -e ${yellow}激活虚拟环境...${background}
    source venv/bin/activate
    if [ $? -ne 0 ]; then
        echo -e ${red}激活虚拟环境失败！${background}
        echo -en ${yellow}回车返回${background};read
        return
    fi

    # 升级pip本身
    echo -e ${yellow}升级pip到最新版本...${background}
    python -m pip install --upgrade pip
    if [ $? -eq 0 ]; then
        echo -e ${green}pip升级成功${background}
    else
        echo -e ${red}pip升级失败，但继续安装依赖${background}
    fi

    # 清除pip缓存
    echo -e ${yellow}清除pip缓存...${background}
    python -m pip cache purge 2>/dev/null || echo -e ${yellow}pip缓存清除完成${background}

    # 选择安装方式
    echo -e ${cyan}请选择安装方式：${background}
    echo -e ${green}1.${cyan} 快速安装（推荐）- 直接安装当前项目${background}
    echo -e ${green}2.${cyan} 完全重装 - 先卸载再重新安装${background}
    echo -e ${green}3.${cyan} 强制重装 - 忽略已安装的包，强制重新安装${background}
    echo -en ${green}请选择 [1-3]: ${background};read install_method

    case ${install_method} in
    2)
        echo -e ${yellow}正在卸载现有依赖包...${background}
        python -m pip uninstall -y meme-generator 2>/dev/null || echo -e ${yellow}未找到已安装的meme-generator${background}
        
        echo -e ${yellow}正在重新安装依赖包...${background}
        python -m pip install .
        ;;
    3)
        echo -e ${yellow}正在强制重新安装依赖包...${background}
        python -m pip install --force-reinstall .
        ;;
    *)
        echo -e ${yellow}正在安装依赖包...${background}
        python -m pip install .
        ;;
    esac

    # 检查安装结果
    if [ $? -eq 0 ]; then
        echo -e ${green}依赖包安装成功！${background}
        
        # 验证安装
        echo -e ${yellow}正在验证安装...${background}
        if python -c "import meme_generator; print('meme_generator模块验证成功')" 2>/dev/null; then
            echo -e ${green}✓ meme_generator模块验证成功${background}
        else
            echo -e ${red}✗ meme_generator模块验证失败${background}
        fi
        
        # 显示已安装的包
        echo -e ${cyan}当前虚拟环境中已安装的主要包：${background}
        python -m pip list | grep -E "(meme|PIL|numpy|requests)" 2>/dev/null || echo -e ${yellow}未找到相关包信息${background}
        
    else
        echo -e ${red}依赖包安装失败！${background}
        echo -e ${yellow}可能的解决方案：${background}
        echo -e ${cyan}- 检查网络连接${background}
        echo -e ${cyan}- 尝试更换GitHub代理（选项12）${background}
        echo -e ${cyan}- 检查系统是否有足够的磁盘空间${background}
        echo -e ${cyan}- 确保Python版本兼容（建议Python 3.8+）${background}
    fi

    # 询问是否重启服务
    if [ "$meme_was_running" = true ]; then
        echo -en ${yellow}检测到之前meme生成器在运行，是否重新启动？[Y/n]: ${background};read restart_choice
        case ${restart_choice} in
        N|n)
            echo -e ${yellow}请记得手动重启meme生成器${background}
            ;;
        *)
            echo -e ${yellow}正在重新启动meme生成器...${background}
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

# 开启/关闭额外meme仓库功能
toggle_extra_memes(){
    if [ ! -d ${install_path}/meme-generator ]; then
        echo -e ${red}meme生成器未安装，请先安装meme生成器!${background}
        echo -en ${yellow}回车返回${background};read
        return
    fi

    echo -e ${white}"====="${green}额外meme仓库管理${white}"====="${background}
    echo -e ${cyan}此功能可以开启或关闭额外的meme仓库${background}
    echo "========================="
    
    # 检查四个额外仓库的状态
    repo1_status="${red}[未安装]"
    repo2_status="${red}[未安装]"
    repo3_status="${red}[未安装]"
    repo4_status="${red}[未安装]"
    
    if [ -d ${install_path}/meme-generator-contrib ]; then
        repo1_status="${green}[已安装]"
    fi
    
    if [ -d ${install_path}/meme_emoji ]; then
        repo2_status="${green}[已安装]"
    fi
    
    if [ -d ${install_path}/meme-generator-jj ]; then
        repo3_status="${green}[已安装]"
    fi
    
    if [ -d ${install_path}/meme_emoji_nsfw ]; then
        repo4_status="${green}[已安装]"
    fi
    
    # 检查配置文件中的启用状态
    if [ -f ${config} ]; then
        current_config=$(grep -E "meme_dirs" ${config})
        
        if echo "${current_config}" | grep -q "meme-generator-contrib/memes"; then
            repo1_enabled="${green}[已启用]"
        else
            repo1_enabled="${yellow}[已禁用]"
        fi
        
        if echo "${current_config}" | grep -q "meme_emoji/emoji"; then
            repo2_enabled="${green}[已启用]"
        else
            repo2_enabled="${yellow}[已禁用]"
        fi
        
        if echo "${current_config}" | grep -q "meme-generator-jj/memes"; then
            repo3_enabled="${green}[已启用]"
        else
            repo3_enabled="${yellow}[已禁用]"
        fi
        
        if echo "${current_config}" | grep -q "meme_emoji_nsfw/emoji"; then
            repo4_enabled="${green}[已启用]"
        else
            repo4_enabled="${yellow}[已禁用]"
        fi
    fi
    
    echo -e ${green}1. meme-generator-contrib ${repo1_status} ${repo1_enabled}${background}
    echo -e ${green}2. meme_emoji ${repo2_status} ${repo2_enabled}${background}
    echo -e ${green}3. meme-generator-jj ${repo3_status} ${repo3_enabled}${background}
    echo -e ${green}4. meme_emoji_nsfw ${repo4_status} ${repo4_enabled}${background}
    echo -e ${green}5. 全部启用${background}
    echo -e ${green}6. 全部禁用${background}
    echo -e ${green}0. 返回${background}
    echo "========================="
    echo -en ${green}请选择要操作的仓库: ${background};read choice
    
    case ${choice} in
    1)
        toggle_single_repo "meme-generator-contrib" "memes" "https://github.com/MemeCrafters/meme-generator-contrib.git"
        ;;
    2)
        toggle_single_repo "meme_emoji" "emoji" "https://github.com/anyliew/meme_emoji.git"
        ;;
    3)
        toggle_single_repo "meme-generator-jj" "memes" "https://github.com/jinjiao007/meme-generator-jj.git"
        ;;
    4)
        toggle_single_repo "meme_emoji_nsfw" "emoji" "https://github.com/anyliew/meme_emoji_nsfw.git"
        ;;
    5)
        enable_all_repos
        ;;
    6)
        disable_all_repos
        ;;
    0)
        return
        ;;
    *)
        echo -e ${red}输入错误${background}
        echo -en ${yellow}回车返回${background};read
        ;;
    esac
}

# 切换单个仓库的启用状态
toggle_single_repo(){
    repo_name="$1"
    repo_subdir="$2"
    repo_url="$3"
    repo_path="${install_path}/${repo_name}"
    
    # 如果仓库未安装，先安装
    if [ ! -d ${repo_path} ]; then
        echo -e ${yellow}检测到 ${repo_name} 未安装，正在安装...${background}
        if git_clone "${repo_url}" "${repo_path}" "/dev/null"; then
            echo -e ${green}${repo_name} 安装成功！${background}
        else
            echo -e ${red}${repo_name} 安装失败！${background}
            echo -en ${yellow}回车返回${background};read
            return
        fi
    fi
    
    # 读取当前配置
    current_dirs=$(grep -E "meme_dirs" ${config} | sed 's/meme_dirs = \[//g' | sed 's/\].*//g')
    repo_dir_path="${install_path}/${repo_name}/${repo_subdir}"
    
    # 检查是否已启用
    if echo "${current_dirs}" | grep -q "${repo_dir_path}"; then
        # 已启用，执行禁用操作
        echo -e ${yellow}正在禁用 ${repo_name}...${background}
        new_dirs=$(echo "${current_dirs}" | sed "s|, \"${repo_dir_path}\"|; s|\"${repo_dir_path}\", ||g; s|\"${repo_dir_path}\"||g")
        sed -i "s|meme_dirs = \[.*\]|meme_dirs = [${new_dirs}]|g" ${config}
        echo -e ${green}${repo_name} 已禁用${background}
    else
        # 未启用，执行启用操作
        echo -e ${yellow}正在启用 ${repo_name}...${background}
        if [ -z "${current_dirs}" ] || [ "${current_dirs}" = " " ]; then
            new_dirs="\"${repo_dir_path}\""
        else
            new_dirs="${current_dirs}, \"${repo_dir_path}\""
        fi
        sed -i "s|meme_dirs = \[.*\]|meme_dirs = [${new_dirs}]|g" ${config}
        echo -e ${green}${repo_name} 已启用${background}
    fi
    
    # 询问是否重启服务
    meme_was_running=false
    if meme_curl; then
        meme_was_running=true
    fi
    
    if [ "$meme_was_running" = true ]; then
        echo -en ${yellow}是否重启meme生成器以应用更改？[Y/n]: ${background};read restart_choice
        case ${restart_choice} in
        N|n)
            echo -e ${yellow}请记得手动重启meme生成器以应用更改${background}
            ;;
        *)
            restart_meme_generator
            ;;
        esac
    else
        echo -e ${yellow}配置已更新，下次启动时将生效${background}
    fi
    
    echo -en ${yellow}回车返回${background};read
}

# 启用所有仓库
enable_all_repos(){
    echo -e ${yellow}正在启用所有额外meme仓库...${background}
    
    # 确保所有仓库都已安装
    repos_to_install=(
        "meme-generator-contrib:memes:https://github.com/MemeCrafters/meme-generator-contrib.git"
        "meme_emoji:emoji:https://github.com/anyliew/meme_emoji.git"
        "meme-generator-jj:memes:https://github.com/jinjiao007/meme-generator-jj.git"
        "meme_emoji_nsfw:emoji:https://github.com/anyliew/meme_emoji_nsfw.git"
    )
    
    for repo_info in "${repos_to_install[@]}"; do
        IFS=':' read -r repo_name repo_subdir repo_url <<< "$repo_info"
        repo_path="${install_path}/${repo_name}"
        
        if [ ! -d ${repo_path} ]; then
            echo -e ${yellow}正在安装 ${repo_name}...${background}
            if git_clone "${repo_url}" "${repo_path}" "/dev/null"; then
                echo -e ${green}${repo_name} 安装成功！${background}
            else
                echo -e ${red}${repo_name} 安装失败！${background}
            fi
        fi
    done
    
    # 更新配置文件，启用所有仓库
    new_dirs="\"${install_path}/meme-generator-contrib/memes\", \"${install_path}/meme_emoji/emoji\", \"${install_path}/meme-generator-jj/memes\", \"${install_path}/meme_emoji_nsfw/emoji\""
    sed -i "s|meme_dirs = \[.*\]|meme_dirs = [${new_dirs}]|g" ${config}
    
    echo -e ${green}所有额外meme仓库已启用！${background}
    
    # 询问是否重启服务
    if meme_curl; then
        echo -en ${yellow}是否重启meme生成器以应用更改？[Y/n]: ${background};read restart_choice
        case ${restart_choice} in
        N|n)
            echo -e ${yellow}请记得手动重启meme生成器以应用更改${background}
            ;;
        *)
            restart_meme_generator
            ;;
        esac
    else
        echo -e ${yellow}配置已更新，下次启动时将生效${background}
    fi
    
    echo -en ${yellow}回车返回${background};read
}

# 禁用所有仓库
disable_all_repos(){
    echo -e ${yellow}正在禁用所有额外meme仓库...${background}
    
    # 清空meme_dirs配置
    sed -i "s|meme_dirs = \[.*\]|meme_dirs = []|g" ${config}
    
    echo -e ${green}所有额外meme仓库已禁用！${background}
    echo -e ${cyan}注意：仓库文件仍保留在系统中，仅禁用了加载${background}
    
    # 询问是否重启服务
    if meme_curl; then
        echo -en ${yellow}是否重启meme生成器以应用更改？[Y/n]: ${background};read restart_choice
        case ${restart_choice} in
        N|n)
            echo -e ${yellow}请记得手动重启meme生成器以应用更改${background}
            ;;
        *)
            restart_meme_generator
            ;;
        esac
    else
        echo -e ${yellow}配置已更新，下次启动时将生效${background}
    fi
    
    echo -en ${yellow}回车返回${background};read
}

# 配置百度翻译API
configure_baidu_translate(){
    if [ ! -d ${install_path}/meme-generator ]; then
        echo -e ${red}meme生成器未安装，请先安装meme生成器!${background}
        echo -en ${yellow}回车返回${background};read
        return
    fi

    if [ ! -f ${config} ]; then
        echo -e ${red}配置文件不存在!${background}
        echo -en ${yellow}回车返回${background};read
        return
    fi

    echo -e ${white}"====="${green}配置百度翻译API${white}"====="${background}
    echo -e ${cyan}百度翻译API用于某些表情包的文字翻译功能${background}
    echo -e ${cyan}例如: dianzhongdian 表情包需要使用百度翻译${background}
    echo "========================="
    
    # 读取当前配置
    current_appid=$(grep -E "baidu_trans_appid" ${config} | sed 's/.*"\(.*\)".*/\1/')
    current_apikey=$(grep -E "baidu_trans_apikey" ${config} | sed 's/.*"\(.*\)".*/\1/')
    
    if [ -n "$current_appid" ] && [ "$current_appid" != "" ]; then
        echo -e ${yellow}当前已配置的APP ID: ${green}${current_appid}${background}
    else
        echo -e ${yellow}当前APP ID: ${red}未配置${background}
    fi
    
    if [ -n "$current_apikey" ] && [ "$current_apikey" != "" ]; then
        echo -e ${yellow}当前已配置的API Key: ${green}${current_apikey:0:8}...${background}
    else
        echo -e ${yellow}当前API Key: ${red}未配置${background}
    fi
    
    echo "========================="
    echo -e ${cyan}获取百度翻译API:${background}
    echo -e ${cyan}1. 访问: ${white}http://api.fanyi.baidu.com${background}
    echo -e ${cyan}2. 注册/登录百度账号${background}
    echo -e ${cyan}3. 进入"管理控制台"${background}
    echo -e ${cyan}4. 选择"通用文本翻译"${background}
    echo -e ${cyan}5. 创建应用，获取APP ID和密钥${background}
    echo "========================="
    
    echo -e ${green}1.${cyan} 配置百度翻译API${background}
    echo -e ${green}2.${cyan} 清除当前配置${background}
    echo -e ${green}3.${cyan} 测试API连接${background}
    echo -e ${green}0.${cyan} 返回${background}
    echo "========================="
    echo -en ${green}请选择操作: ${background};read choice
    
    case ${choice} in
    1)
        # 配置API
        echo -e ${yellow}请输入百度翻译APP ID:${background}
        read -p "APP ID: " new_appid
        
        if [ -z "$new_appid" ]; then
            echo -e ${red}APP ID不能为空！${background}
            echo -en ${yellow}回车返回${background};read
            return
        fi
        
        echo -e ${yellow}请输入百度翻译API Key \(密钥\):${background}
        read -p "API Key: " new_apikey
        
        if [ -z "$new_apikey" ]; then
            echo -e ${red}API Key不能为空！${background}
            echo -en ${yellow}回车返回${background};read
            return
        fi
        
        # 更新配置文件
        echo -e ${yellow}正在更新配置文件...${background}
        sed -i "s/baidu_trans_appid = \".*\"/baidu_trans_appid = \"${new_appid}\"/" ${config}
        sed -i "s/baidu_trans_apikey = \".*\"/baidu_trans_apikey = \"${new_apikey}\"/" ${config}
        
        echo -e ${green}✓ 百度翻译API配置成功！${background}
        echo -e ${cyan}APP ID: ${new_appid}${background}
        echo -e ${cyan}API Key: ${new_apikey:0:8}...${background}
        
        # 询问是否重启服务
        if meme_curl; then
            echo -en ${yellow}检测到meme生成器正在运行，是否重启以应用配置？[Y/n]: ${background};read restart_choice
            case ${restart_choice} in
            N|n)
                echo -e ${yellow}请记得手动重启meme生成器以应用新配置${background}
                ;;
            *)
                restart_meme_generator
                ;;
            esac
        else
            echo -e ${yellow}配置已保存，下次启动时将生效${background}
        fi
        ;;
    2)
        # 清除配置
        echo -en ${yellow}确定要清除百度翻译API配置吗？[y/N]: ${background};read confirm
        case ${confirm} in
        Y|y)
            sed -i 's/baidu_trans_appid = ".*"/baidu_trans_appid = ""/' ${config}
            sed -i 's/baidu_trans_apikey = ".*"/baidu_trans_apikey = ""/' ${config}
            echo -e ${green}✓ 百度翻译API配置已清除${background}
            
            # 询问是否重启服务
            if meme_curl; then
                echo -en ${yellow}是否重启meme生成器以应用更改？[Y/n]: ${background};read restart_choice
                case ${restart_choice} in
                N|n)
                    echo -e ${yellow}请记得手动重启meme生成器${background}
                    ;;
                *)
                    restart_meme_generator
                    ;;
                esac
            fi
            ;;
        *)
            echo -e ${yellow}已取消操作${background}
            ;;
        esac
        ;;
    3)
        # 测试API
        if [ -z "$current_appid" ] || [ -z "$current_apikey" ]; then
            echo -e ${red}尚未配置百度翻译API，无法测试！${background}
            echo -en ${yellow}回车返回${background};read
            return
        fi
        
        echo -e ${yellow}正在测试百度翻译API连接...${background}
        
        # 测试翻译
        test_text="hello"
        timestamp=$(date +%s)
        salt=$RANDOM
        sign=$(echo -n "${current_appid}${test_text}${salt}${current_apikey}" | md5sum | cut -d' ' -f1)
        
        response=$(curl -s "http://api.fanyi.baidu.com/api/trans/vip/translate?q=${test_text}&from=en&to=zh&appid=${current_appid}&salt=${salt}&sign=${sign}")
        
        if echo "$response" | grep -q "trans_result"; then
            echo -e ${green}✓ API连接测试成功！${background}
            echo -e ${cyan}测试翻译: hello → $(echo "$response" | grep -o '"dst":"[^"]*"' | sed 's/"dst":"\(.*\)"/\1/')${background}
        else
            echo -e ${red}✗ API连接测试失败${background}
            if echo "$response" | grep -q "error_code"; then
                error_code=$(echo "$response" | grep -o '"error_code":"[^"]*"' | sed 's/"error_code":"\(.*\)"/\1/')
                echo -e ${red}错误代码: ${error_code}${background}
                case ${error_code} in
                52001)
                    echo -e ${yellow}原因: 请求超时，请检查网络连接${background}
                    ;;
                52002)
                    echo -e ${yellow}原因: 系统错误，请稍后重试${background}
                    ;;
                52003)
                    echo -e ${yellow}原因: APP ID或API Key错误${background}
                    ;;
                54000)
                    echo -e ${yellow}原因: 必填参数为空${background}
                    ;;
                54001)
                    echo -e ${yellow}原因: 签名错误，请检查APP ID和API Key${background}
                    ;;
                54003)
                    echo -e ${yellow}原因: 访问频率受限${background}
                    ;;
                54004)
                    echo -e ${yellow}原因: 账户余额不足${background}
                    ;;
                *)
                    echo -e ${yellow}详细信息: ${response}${background}
                    ;;
                esac
            else
                echo -e ${yellow}响应: ${response}${background}
            fi
        fi
        ;;
    0)
        return
        ;;
    *)
        echo -e ${red}输入错误${background}
        ;;
    esac
    
    echo -en ${yellow}回车返回${background};read
}

main(){
# 如果是首次通过curl执行，确保先保存脚本到系统目录
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
echo -e  ${green} 7.  ${cyan}启用额外meme表情包${background}
echo -e  ${green} 8.  ${cyan}查看日志${background}
echo -e  ${green} 9.  ${cyan}切换自动更新设置${background}
echo -e  ${green} 10.  ${cyan}查看自动更新日志${background}
echo -e  ${green} 11.  ${cyan}修改meme端口号${background}
echo -e  ${green} 12.  ${cyan}重写配置文件${background}
echo -e  ${green} 13.  ${cyan}更换Github代理${background}
echo -e  ${green} 14.  ${cyan}重新安装依赖${background}
echo -e  ${green} 15.  ${cyan}配置百度翻译API${background}
echo -e  ${green} 0.  ${cyan}退出${background}
echo "========================="
echo -e ${green}meme生成器状态: ${condition}${background}
echo -e ${green}meme自动更新服务: ${auto_update_condition}${background}
if [ "${condition}" = "${green}[运行中]" ]; then
    echo -e ${green}MEME api: ${cyan}http://localhost:${Port}${background}
fi
echo -e ${green}QQ群:${cyan}呆毛版-QQ群:1022982073${background}
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
echo
toggle_extra_memes
;;
8)
log_meme_generator
;;
9)
echo
toggle_auto_update
;;
10)
echo
view_auto_update_log
;;
11)
echo
change_port
;;
12)
echo
rewrite_config
;;
13)
echo
change_github_proxy
;;
14)
echo
reinstall_pip_dependencies
;;
15)
echo
configure_baidu_translate
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
    done
}

if [ "$1" = "auto_update" ]; then
  auto_update_meme_generator
  exit 0
else
  mainbak
fi
