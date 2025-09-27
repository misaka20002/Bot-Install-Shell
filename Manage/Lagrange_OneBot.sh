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
  GithubMirror="https://ghfast.top/"
else
  GithubMirror=""
fi

LAGRANGE_URL=${GithubMirror}https://github.com/misaka20002/Lagrange.Core/releases/download/nightly/Lagrange.OneBot_linux-${ARCH}_net9.0_SelfContained.tar.gz
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
mkdir -p $INSTALL_DIR/accounts

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
    # 复制可执行文件到安装目录
    cp $TMP_DIR/Lagrange.OneBot/bin/Release/net9.0/linux-${ARCH}/publish/Lagrange.OneBot $INSTALL_DIR/
    chmod +x $INSTALL_DIR/Lagrange.OneBot
    
    # 清理临时文件
    echo -e ${yellow}正在清理临时文件...${background}
    rm -f lagrange.tar.gz
    rm -rf $TMP_DIR
else
    echo -e ${red}未找到可执行文件，解压路径可能有变化${background}
    echo -e ${yellow}请检查解压后的文件结构${background}
    exit 1
fi

echo -e ${green}安装完成${background}
echo -en ${cyan}现在要创建一个QQ账号吗？[Y/n]${background};read yn
case ${yn} in
Y|y|"")
  manage_multi_qq
  ;;
*)
  echo -en ${cyan}回车返回主菜单${background};read
  ;;
esac
}

update_Lagrange(){
  if ! is_lagrange_installed; then
    echo -e ${red}"Lagrange未安装，请先安装Lagrange"${background}
    echo -en ${cyan}"按回车返回主菜单"${background};read
    return
  fi

  echo -e ${yellow}正在下载最新版本...${background}
  rm -f lagrange.tar.gz
  until wget -O lagrange.tar.gz -c ${LAGRANGE_URL}
  do
    echo -e ${red}下载失败 ${green}正在重试${background}
  done

  # 创建临时目录进行解压
  TMP_DIR=$HOME/temp_lagrange
  rm -rf $TMP_DIR
  mkdir -p $TMP_DIR

  echo -e ${yellow}正在解压文件,请耐心等候${background}
  pv lagrange.tar.gz | tar -zxf - -C $TMP_DIR

  # 先检测并记录正在运行的账号
  running_accounts=()
  echo -e ${yellow}正在检测运行中的账号...${background}
  for acc_dir in "$INSTALL_DIR/accounts"/*; do
    if [ -d "$acc_dir" ]; then
      acc_name=$(basename "$acc_dir")
      tmux_name="lagrange_$acc_name"
      
      if tmux_ls $tmux_name > /dev/null 2>&1; then
        running_accounts+=("$acc_name")
        echo -e ${cyan}检测到运行中的账号: ${green}$acc_name${background}
      fi
    fi
  done

  # 停止所有账号的服务
  echo -e ${yellow}正在停止所有账号的服务...${background}
  for acc_dir in "$INSTALL_DIR/accounts"/*; do
    if [ -d "$acc_dir" ]; then
      acc_name=$(basename "$acc_dir")
      tmux_name="lagrange_$acc_name"
      
      if tmux_ls $tmux_name > /dev/null 2>&1; then
        echo -e ${yellow}停止账号 ${cyan}$acc_name${yellow} 的服务...${background}
        tmux_kill_session $tmux_name > /dev/null 2>&1
      fi
    fi
  done

  # 更新主程序
  echo -e ${yellow}正在更新主程序...${background}
  if [ -f $TMP_DIR/Lagrange.OneBot/bin/Release/net9.0/linux-${ARCH}/publish/Lagrange.OneBot ]; then
      # 备份原可执行文件
      if [ -f $INSTALL_DIR/Lagrange.OneBot ]; then
        mv $INSTALL_DIR/Lagrange.OneBot $INSTALL_DIR/Lagrange.OneBot.bak
      fi
      
      # 复制新的可执行文件
      cp $TMP_DIR/Lagrange.OneBot/bin/Release/net9.0/linux-${ARCH}/publish/Lagrange.OneBot $INSTALL_DIR/
      chmod +x $INSTALL_DIR/Lagrange.OneBot
      
      # 清理临时文件
      echo -e ${yellow}正在清理临时文件...${background}
      rm -f lagrange.tar.gz
      rm -rf $TMP_DIR
      
      echo -e ${green}更新完成${background}
  else
      echo -e ${red}未找到可执行文件，解压路径可能有变化${background}
      echo -e ${yellow}请检查解压后的文件结构${background}
      exit 1
  fi

  # 如果没有之前运行中的账号
  if [ ${#running_accounts[@]} -eq 0 ]; then
    echo -e ${yellow}没有检测到之前运行的账号${background}
    echo -en ${cyan}回车返回${background};read
    return
  fi
  
  # 显示之前运行的账号并询问是否重启
  echo -e ${yellow}检测到 ${cyan}${#running_accounts[@]}${yellow} 个之前运行的账号: ${green}${running_accounts[*]}${background}
  echo -en ${yellow}是否重新启动这些账号? [Y/n]:${background};read restart_all
  
  case $restart_all in
    n|N)
      echo -e ${yellow}请稍后手动启动账号${background}
      ;;
    *)
      # 重新启动之前运行的账号
      for acc_name in "${running_accounts[@]}"; do
        tmux_name="lagrange_$acc_name"
        
        echo -e ${yellow}重新启动账号 ${cyan}$acc_name${yellow} ...${background}
        local QQ_DIR="$INSTALL_DIR/accounts/$acc_name"
        tmux_new $tmux_name "cd \"$QQ_DIR\" && $INSTALL_DIR/Lagrange.OneBot; echo -e ${red}账号 $acc_name 已关闭，正在重启${background}; sleep 2"
      done
      echo -e ${green}已重新启动 ${cyan}${#running_accounts[@]}${green} 个账号${background}
      ;;
  esac
  
  echo -en ${cyan}回车返回${background};read
}

uninstall_Lagrange(){
  if [ ! -d $INSTALL_DIR ];then
    echo -en ${red}您还没有部署拉格朗日签名服务器!!! ${cyan}回车返回${background};read
    return
  fi

  echo -e ${white}"====="${red}卸载拉格朗日签名服务器${white}"====="${background}
  echo -e ${yellow}警告: 此操作将完全删除拉格朗日签名服务器${background}
  echo -e ${yellow}这将删除以下内容:${background}
  echo -e ${cyan}• 程序可执行文件${background}
  echo -e ${cyan}• 所有账号的数据文件${background}
  echo -e ${cyan}• 所有配置文件${background}
  echo
  echo -en ${red}您确定要卸载拉格朗日签名服务器吗? [输入DELETE确认]: ${background};read confirm_uninstall

  if [ "$confirm_uninstall" != "DELETE" ]; then
    echo -e ${green}已取消卸载操作${background}
    echo -en ${cyan}回车返回${background};read
    return
  fi

  echo -e ${yellow}正在停止所有账号的服务...${background}
  
  # 停止所有账号的服务
  for acc_dir in "$INSTALL_DIR/accounts"/*; do
    if [ -d "$acc_dir" ]; then
      acc_name=$(basename "$acc_dir")
      tmux_name="lagrange_$acc_name"
      
      if tmux_ls $tmux_name > /dev/null 2>&1; then
        echo -e ${yellow}停止账号 ${cyan}$acc_name${yellow} 的服务...${background}
        tmux_kill_session $tmux_name > /dev/null 2>&1
      fi
    fi
  done

  # 删除所有文件
  echo -e ${yellow}正在删除所有文件...${background}
  rm -rf $INSTALL_DIR

  echo -e ${green}拉格朗日签名服务器已完全卸载${background}
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

# 检查jq命令是否存在
check_jq() {
  if ! command -v jq &> /dev/null; then
    echo -e ${yellow}"检测到未安装jq命令"${background}
    echo -e ${cyan}"正在尝试安装jq..."${background}
    
    if [ $(command -v apt) ]; then
      apt update -y
      apt install -y jq
    elif [ $(command -v yum) ]; then
      yum install -y jq
    elif [ $(command -v dnf) ]; then
      dnf install -y jq
    elif [ $(command -v pacman) ]; then
      pacman -Sy --noconfirm jq
    else
      echo -e ${red}"无法自动安装jq，请手动安装后再使用此功能"${background}
      return 1
    fi
    
    # 再次检查jq是否已成功安装
    if ! command -v jq &> /dev/null; then
      echo -e ${red}"jq安装失败，请手动安装后再使用此功能"${background}
      return 1
    else
      echo -e ${green}"jq安装成功"${background}
      return 0
    fi
  fi
  return 0
}

# 同步AccessToken到TRSS-Yunzai配置
sync_token_to_trss() {
  local new_token="$1"
  local trss_config="$HOME/TRSS-Yunzai/config/config/server.yaml"
  
  echo -en ${cyan}是否同步修改本地TRSS-Yunzai的配置文件? [Y/n]: ${background};read sync_choice
  case $sync_choice in
    n|N)
      echo -e ${yellow}跳过修改TRSS-Yunzai配置${background}
      echo -en ${cyan}回车返回${background};read
      return
    ;;
  esac
  
  # 检查TRSS-Yunzai配置文件是否存在
  if [ ! -f "$trss_config" ]; then
    echo -e ${red}未找到TRSS-Yunzai配置文件: ${yellow}$trss_config${background}
    echo -e ${yellow}请检查TRSS-Yunzai是否已安装或配置路径是否正确${background}
    echo -en ${cyan}回车返回${background};read
    return
  fi
  
  # 备份原配置文件
  cp "$trss_config" "$trss_config.bak"
  echo -e ${yellow}已备份原配置至: ${cyan}$trss_config.bak${background}
  
  # 准备Bearer令牌格式
  bearer_token=""
  if [ ! -z "$new_token" ]; then
    bearer_token="Bearer $new_token"
  fi
  
  # 检查配置文件中是否有auth和authorization
  if grep -q "auth:" "$trss_config"; then
    if grep -q "authorization:" "$trss_config"; then
      # 更新已存在的authorization
      if [ -z "$bearer_token" ]; then
        # 如果token为空，则删除authorization行
        sed -i '/authorization:/d' "$trss_config"
        echo -e ${green}已删除authorization配置${background}
      else
        # 更新authorization值
        sed -i "s|authorization: *\".*\"|authorization: \"$bearer_token\"|" "$trss_config"
        echo -e ${green}已更新TRSS-Yunzai配置中的authorization${background}
      fi
    else
      # auth存在但authorization不存在，添加authorization
      if [ ! -z "$bearer_token" ]; then
        sed -i "/auth:/a\\  authorization: \"$bearer_token\"" "$trss_config"
        echo -e ${green}已在auth下添加authorization${background}
      fi
    fi
  else
    # 如果不存在auth部分，且有token需要添加，则添加完整配置
    if [ ! -z "$bearer_token" ] && grep -q "redirect:" "$trss_config"; then
      # 在redirect行后添加auth配置
      sed -i "/redirect:/a\\
# 服务器鉴权\\
auth:\\
  authorization: \"$bearer_token\"" "$trss_config"
      echo -e ${green}已添加auth配置到TRSS-Yunzai配置${background}
    elif [ ! -z "$bearer_token" ]; then
      # 没有找到redirect行，在文件末尾添加
      cat >> "$trss_config" << EOF
# 服务器鉴权
auth:
  authorization: "$bearer_token"
EOF
      echo -e ${green}已添加auth配置到TRSS-Yunzai配置文件末尾${background}
    fi
  fi
  
  # 检查文件中是否有重复的auth条目
  if [ $(grep -c "auth:" "$trss_config") -gt 1 ]; then
    echo -e ${yellow}警告：检测到重复的auth条目，尝试修复...${background}
    # 创建临时文件
    tmp_file=$(mktemp)
    
    # 标记是否已处理第一个auth条目
    processed_first_auth=false
    
    # 逐行读取并处理
    while IFS= read -r line; do
      if [[ "$line" =~ ^auth: ]]; then
        if [ "$processed_first_auth" = false ]; then
          # 保留第一个auth条目
          echo "$line" >> "$tmp_file"
          processed_first_auth=true
        fi
        # 跳过其他auth条目
      else
        echo "$line" >> "$tmp_file"
      fi
    done < "$trss_config"
    
    # 用临时文件替换原文件
    mv "$tmp_file" "$trss_config"
    echo -e ${green}已修复重复的auth条目${background}
  fi
  
  echo -e ${green}TRSS-Yunzai配置已同步更新${background}
  echo -en ${yellow}要记得重启 TRSS-Yunzai 哦~ ${cyan} 回车返回${background};read
}

start_lagrange_for_account(){
  local qq_name="$1"
  local QQ_DIR="$INSTALL_DIR/accounts/$qq_name"
  local tmux_name="lagrange_$qq_name"
  
  if tmux_ls $tmux_name > /dev/null 2>&1; then
    echo -en ${yellow}账号 ${cyan}$qq_name ${yellow}已启动 ${cyan}回车返回${background};read
    echo
    return
  fi
  
  echo -e ${white}"====="${green}启动账号: ${cyan}$qq_name${white}"====="${background}
  echo -e ${cyan}请选择启动方式${background}
  echo -e  ${green}1.  ${cyan}前台启动（首次登陆）${background}
  echo -e  ${green}2.  ${cyan}TMUX后台启动（推荐）${background}
  echo "========================="
  echo -en ${green}请输入您的选项: ${background};read start_mode
  
  case $start_mode in
    1)
      # 前台启动
      cd "$QQ_DIR"
      $INSTALL_DIR/Lagrange.OneBot
      echo -en ${cyan}操作已完成，按回车返回${background};read
      ;;
    2)
      # TMUX后台启动
      tmux_new $tmux_name "cd \"$QQ_DIR\" && $INSTALL_DIR/Lagrange.OneBot; echo -e ${red}账号 $qq_name 已关闭，正在重启${background}; sleep 2"
      
      echo -e ${green}新手说明：${background}
      echo -e ${cyan}1.首次启动需要打开窗口进行扫码登录；${background}
      echo -e ${cyan}2.进入TMUX窗口后，退出请按 Ctrl+B 然后按 D${background}
      echo -en ${green}启动成功 是否打开窗口 [Y/N]:${background};read yn
      
      case $yn in
        Y|y)
          bot_tmux_attach_log $tmux_name
          ;;
        *)
          echo -en ${cyan}回车返回${background};read
          ;;
      esac
      ;;
    *)
      echo -e ${red}输入错误${background}
      echo -en ${cyan}回车返回${background};read
      ;;
  esac
}

stop_lagrange_for_account(){
  local qq_name="$1"
  local tmux_name="lagrange_$qq_name"
  
  if tmux_ls $tmux_name > /dev/null 2>&1; then
    echo -e ${yellow}正在停止账号 ${cyan}$qq_name${yellow} 的服务...${background}
    tmux_kill_session $tmux_name > /dev/null 2>&1
    
    # 查找并杀死可能残留的进程
    local PID=$(ps aux | grep "cd \"$INSTALL_DIR/accounts/$qq_name\"" | grep Lagrange.OneBot | sed '/grep/d' | awk '{print $2}')
    if [ ! -z "$PID" ]; then
      kill -9 $PID
    fi
    
    echo -en ${green}账号 ${cyan}$qq_name ${green}已停止 ${cyan}回车返回${background};read
  else
    echo -en ${red}账号 ${cyan}$qq_name ${red}未启动 ${cyan}回车返回${background};read
  fi
}

restart_lagrange_for_account(){
  local qq_name="$1"
  local tmux_name="lagrange_$qq_name"
  
  if tmux_ls $tmux_name > /dev/null 2>&1; then
    echo -e ${yellow}正在重启账号 ${cyan}$qq_name${yellow} 的服务...${background}
    tmux_kill_session $tmux_name > /dev/null 2>&1
    
    # 短暂等待确保完全停止
    sleep 2
    
    # 重新启动
    local QQ_DIR="$INSTALL_DIR/accounts/$qq_name"
    tmux_new $tmux_name "cd \"$QQ_DIR\" && $INSTALL_DIR/Lagrange.OneBot; echo -e ${red}账号 $qq_name 已关闭，正在重启${background}; sleep 2"
    
    echo -en ${green}账号 ${cyan}$qq_name ${green}已重启 ${cyan}回车返回${background};read
  else
    echo -e ${red}账号 ${cyan}$qq_name ${red}未启动，正在启动...${background}
    start_lagrange_for_account "$qq_name"
  fi
}

view_log_for_account(){
  local qq_name="$1"
  local tmux_name="lagrange_$qq_name"
  
  if ! tmux_ls $tmux_name > /dev/null 2>&1; then
    echo -en ${red}账号 ${cyan}$qq_name ${red}未启动 ${cyan}回车返回${background};read
    return
  fi
  
  bot_tmux_attach_log $tmux_name
}

relogin_qq(){
  local qq_name="$1"
  local QQ_DIR="$INSTALL_DIR/accounts/$qq_name"
  local tmux_name="lagrange_$qq_name"
  
  echo -e ${yellow}重新登录将删除当前账号 ${cyan}$qq_name ${yellow}的登录信息${background}
  echo -en ${cyan}确认重新登录吗? [y/N]: ${background};read confirm
  
  case $confirm in
    y|Y)
      # 停止当前服务
      if tmux_ls $tmux_name > /dev/null 2>&1; then
        echo -e ${yellow}正在停止当前服务...${background}
        tmux_kill_session $tmux_name > /dev/null 2>&1
        sleep 2
      fi
      
      # 删除登录信息
      echo -e ${yellow}正在删除登录信息...${background}
      rm -f "$QQ_DIR/device.json" "$QQ_DIR/keystore.json"
      
      echo -e ${green}登录信息已删除${background}
      echo -en ${cyan}是否立即启动并重新登录? [Y/n]: ${background};read start_now
      
      case $start_now in
        n|N)
          return
          ;;
        *)
          start_lagrange_for_account "$qq_name"
          ;;
      esac
      ;;
    *)
      echo -e ${yellow}操作已取消${background}
      echo -en ${cyan}回车返回${background};read
      ;;
  esac
}

delete_qq(){
  local qq_name="$1"
  local QQ_DIR="$INSTALL_DIR/accounts/$qq_name"
  local tmux_name="lagrange_$qq_name"
  
  echo -e ${red}警告: 此操作将删除账号 ${cyan}$qq_name ${red}的所有数据，包括配置和登录信息${background}
  echo -en ${cyan}确认删除吗? [输入DELETE确认]: ${background};read confirm
  
  if [ "$confirm" != "DELETE" ]; then
    echo -e ${yellow}操作已取消${background}
    echo -en ${cyan}回车返回${background};read
    return
  fi
  
  # 停止当前服务
  if tmux_ls $tmux_name > /dev/null 2>&1; then
    echo -e ${yellow}正在停止服务...${background}
    tmux_kill_session $tmux_name > /dev/null 2>&1
    
    # 查找并杀死可能残留的进程
    local PID=$(ps aux | grep "cd \"$QQ_DIR\"" | grep Lagrange.OneBot | sed '/grep/d' | awk '{print $2}')
    if [ ! -z "$PID" ]; then
      kill -9 $PID
    fi
    
    sleep 2
  fi
  
  # 删除账号目录
  echo -e ${yellow}正在删除账号数据...${background}
  rm -rf "$QQ_DIR"
  
  echo -e ${green}账号 ${cyan}$qq_name ${green}已删除${background}
  echo -en ${cyan}按回车返回上级菜单${background};read
}

rewrite_config_for_account(){
  local qq_name="$1"
  local config_file="$INSTALL_DIR/accounts/$qq_name/appsettings.json"
  
  if [ -f "$config_file" ]; then
    echo -e ${yellow}警告: 这将覆盖账号 ${cyan}$qq_name ${yellow}的配置文件，恢复为默认的TRSS接口的配置文件。${background}
    echo -en ${cyan}是否继续重写配置文件? [y/N]:${background};read confirm
    case $confirm in
    y|Y)
        create_config_for_account "$qq_name"
        echo -en ${cyan}回车返回${background};read
        ;;
    *)
        echo -e ${yellow}操作已取消${background}
        echo -en ${cyan}回车返回${background};read
        ;;
    esac
  else
    create_config_for_account "$qq_name"
    echo -en ${cyan}回车返回${background};read
  fi
}

change_sign_version_for_account(){
  local qq_name="$1"
  local config_file="$INSTALL_DIR/accounts/$qq_name/appsettings.json"
  
  if [ ! -f "$config_file" ]; then
    echo -e ${red}配置文件不存在${background}
    echo -en ${cyan}回车返回${background};read
    return
  fi
  
  echo -e ${white}"====="${green}呆毛版-拉格朗日签名版本${white}"====="${background}
  
  # 读取当前版本号
  current_url=$(grep -E "SignServerUrl" "$config_file" | sed 's/.*"SignServerUrl": "\(.*\)",/\1/')
  current_version=$(echo $current_url | sed -E 's/.*\/([0-9]+)$/\1/')
  
  echo -e ${cyan}当前签名版本: ${green}${current_version}${background}
  echo -e ${cyan}请选择签名服务器版本${background}
  echo -e  ${green} 1.  ${cyan}版本: cn 30366 \(lagrangecore.org\)${background}
  echo -e  ${green} 2.  ${cyan}版本: hk 30366 \(0w0.ing\)${background}
  echo -e  ${green} 3.  ${cyan}版本: cn 39038 \(lagrangecore.org\)${background}
  echo -e  ${green} 4.  ${cyan}版本: hk 39038 \(0w0.ing\)${background}
  echo "========================="
  echo -en ${green}请输入您的选项: ${background};read num
  
  case ${num} in
  1)
      new_url="https://sign.lagrangecore.org/api/sign/30366"
      new_version="30366"
      ;;
  2)
      new_url="https://sign.0w0.ing/api/sign/30366"
      new_version="30366"
      ;;
  3)
      new_url="https://sign.lagrangecore.org/api/sign/39038"
      new_version="39038"
      ;;
  4)
      new_url="https://sign.0w0.ing/api/sign/39038"
      new_version="39038"
      ;;
  *)
      echo -e ${red}输入错误${background}
      echo -en ${cyan}回车返回${background};read
      return
      ;;
  esac
  
  # 替换 SignServerUrl
  sed -i "s|\"SignServerUrl\": \".*\"|\"SignServerUrl\": \"$new_url\"|" "$config_file"
  
  echo -e ${green}账号 ${cyan}$qq_name ${green}的签名版本已更改为: ${cyan}${new_version}${background}
  echo -en ${cyan}回车返回${background};read
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
mkdir -p $INSTALL_DIR/accounts

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
    # 复制可执行文件到安装目录
    cp $TMP_DIR/Lagrange.OneBot/bin/Release/net9.0/linux-${ARCH}/publish/Lagrange.OneBot $INSTALL_DIR/
    chmod +x $INSTALL_DIR/Lagrange.OneBot
    
    # 清理临时文件
    echo -e ${yellow}正在清理临时文件...${background}
    rm -f lagrange.tar.gz
    rm -rf $TMP_DIR
else
    echo -e ${red}未找到可执行文件，解压路径可能有变化${background}
    echo -e ${yellow}请检查解压后的文件结构${background}
    exit 1
fi

echo -e ${green}安装完成${background}
echo -en ${cyan}现在要创建一个QQ账号吗？[Y/n]${background};read yn
case ${yn} in
Y|y|"")
  manage_multi_qq
  ;;
*)
  echo -en ${cyan}回车返回主菜单${background};read
  ;;
esac
}

manage_implementations_with_path(){
  local custom_config_file="$1"
  local account_name="$2"
  local config_path="${custom_config_file:-$CONFIG_FILE}"
  
  if [ ! -f "$config_path" ]; then
    echo -e ${red}配置文件不存在，请先安装拉格朗日签名服务器${background}
    echo -en ${cyan}回车返回${background};read
    return
  fi
  
  # 检查jq是否安装
  if ! check_jq; then
    echo -en ${yellow}"由于缺少jq命令，无法使用此功能，按回车返回"${background};read
    return
  fi

  # 备份配置文件
  cp "$config_path" "$config_path.bak"

  while true; do
    # clear
    # 显示标题，如果有账号名则显示
    if [ -n "$account_name" ]; then
      echo -e ${white}"====="${green}账号 ${cyan}$account_name${green} 的OneBot连接管理${white}"====="${background}
    else
      echo -e ${white}"====="${green}拉格朗日OneBot连接管理${white}"====="${background}
    fi
    echo -e ${cyan}当前已配置的连接：${background}
    
    # 使用jq解析JSON
    implementations=$(jq -r '.Implementations | length' "$config_path" 2>/dev/null)
    
    # 如果jq命令失败，尝试使用grep和sed
    if [ $? -ne 0 ] || [ -z "$implementations" ]; then
      echo -e ${red}"解析JSON失败，请确保配置文件格式正确"${background}
      echo -en ${yellow}"按回车返回"${background};read
      return
    fi
    
    if [ "$implementations" == "null" ]; then
      implementations=0
    fi
    
    for (( i=0; i<$implementations; i++ )); do
      type=$(jq -r ".Implementations[$i].Type" "$config_path")
      host=$(jq -r ".Implementations[$i].Host" "$config_path")
      port=$(jq -r ".Implementations[$i].Port" "$config_path")
      suffix=$(jq -r ".Implementations[$i].Suffix // \"\"" "$config_path")
      echo -e ${green}$((i+1)). ${yellow}类型: ${cyan}$type${background}
      echo -e ${yellow}  地址: ${cyan}$host:$port$suffix${background}
    done
    
    echo "========================="
    echo -e ${green}1. ${cyan}添加新连接${background}
    echo -e ${green}2. ${cyan}删除现有连接${background}
    echo -e ${green}3. ${cyan}管理AccessToken${background}
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
                echo -en ${cyan}回车返回${background};read
                continue
                ;;
            esac
            ;;
          2) 
            conn_type="Http"
            # 对Http类型进行自定义配置
            echo -en ${cyan}请输入主机地址 \(默认: 0.0.0.0\): ${background};read host
            host=${host:-0.0.0.0}
            
            echo -en ${cyan}请输入端口 \(默认: 2956\): ${background};read port
            port=${port:-2956}
            
            echo -en ${cyan}请输入访问令牌 \(默认为空\): ${background};read token
            token=${token:-""}
            ;;
          3) 
            conn_type="HttpPost"
            # 对HttpPost类型进行自定义配置
            echo -en ${cyan}请输入主机地址 \(默认: 0.0.0.0\): ${background};read host
            host=${host:-0.0.0.0}
            
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
            echo -en ${cyan}请输入主机地址 \(默认: 0.0.0.0\): ${background};read host
            host=${host:-0.0.0.0}
            
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
            echo -en ${cyan}回车返回${background};read
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
                 "$config_path" > "$config_path.tmp" && mv "$config_path.tmp" "$config_path"
              ;;
            "Http")
              jq --arg type "$conn_type" \
                 --arg host "$host" \
                 --argjson port "$port" \
                 --arg token "$token" \
                 '.Implementations += [{"Type": $type, "Host": $host, "Port": $port, "AccessToken": $token}]' \
                 "$config_path" > "$config_path.tmp" && mv "$config_path.tmp" "$config_path"
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
                 "$config_path" > "$config_path.tmp" && mv "$config_path.tmp" "$config_path"
              ;;
            "ForwardWebSocket")
              jq --arg type "$conn_type" \
                 --arg host "$host" \
                 --argjson port "$port" \
                 --argjson heartbeat "$heartbeat" \
                 --argjson heartbeat_enable "$heartbeat_enable" \
                 --arg token "$token" \
                 '.Implementations += [{"Type": $type, "Host": $host, "Port": $port, "HeartBeatInterval": $heartbeat, "HeartBeatEnable": $heartbeat_enable, "AccessToken": $token}]' \
                 "$config_path" > "$config_path.tmp" && mv "$config_path.tmp" "$config_path"
              ;;
          esac
          
          echo -e ${green}成功添加新连接: ${cyan}$conn_type - $host:$port${background}
          echo -en ${cyan}回车返回${background};read
        fi
        ;;
        
      2)
        if [ $implementations -eq 0 ]; then
          echo -e ${red}没有可删除的连接${background}
          echo -en ${cyan}回车返回${background};read
          continue
        fi
        
        echo -en ${cyan}请输入要删除的连接编号 \(1-$implementations\): ${background};read del_num
        
        if ! [[ "$del_num" =~ ^[0-9]+$ ]] || [ $del_num -lt 1 ] || [ $del_num -gt $implementations ]; then
          echo -e ${red}无效的编号${background}
          echo -en ${cyan}回车返回${background};read
          continue
        fi
        
        idx=$((del_num-1))
        host=$(jq -r ".Implementations[$idx].Host" "$config_path")
        port=$(jq -r ".Implementations[$idx].Port" "$config_path")
        suffix=$(jq -r ".Implementations[$idx].Suffix" "$config_path")
        
        # 从配置中删除连接
        jq "del(.Implementations[$idx])" "$config_path" > "$config_path.tmp" && mv "$config_path.tmp" "$config_path"
        
        echo -e ${green}成功删除连接: ${cyan}$host:$port$suffix${background}
        echo -en ${cyan}回车返回${background};read
        ;;
      3)
        # 管理AccessToken
        if [ $implementations -eq 0 ]; then
          echo -e ${red}没有可用的连接配置${background}
          echo -en ${cyan}回车返回${background};read
          continue
        fi
        
        echo -en ${cyan}请输入要管理AccessToken的连接编号 \(1-$implementations\): ${background};read conn_num
        
        if ! [[ "$conn_num" =~ ^[0-9]+$ ]] || [ $conn_num -lt 1 ] || [ $conn_num -gt $implementations ]; then
          echo -e ${red}无效的编号${background}
          echo -en ${cyan}回车返回${background};read
          continue
        fi
        
        idx=$((conn_num-1))
        type=$(jq -r ".Implementations[$idx].Type" "$config_path")
        host=$(jq -r ".Implementations[$idx].Host" "$config_path")
        port=$(jq -r ".Implementations[$idx].Port" "$config_path")
        current_token=$(jq -r ".Implementations[$idx].AccessToken" "$config_path")
        
        echo -e ${cyan}已选择连接: ${yellow}$type - $host:$port${background}
        echo -e ${cyan}当前AccessToken: ${yellow}$current_token${background}
        echo
        echo -e ${green}1. ${cyan}修改AccessToken${background}
        echo -e ${green}2. ${cyan}删除AccessToken${background}
        echo -e ${green}3. ${cyan}从TRSS配置中导入AccessToken${background}
        echo -e ${green}0. ${cyan}返回${background}
        echo -en ${green}请输入您的选项: ${background};read token_option
        
        case $token_option in
          1)
            echo -en ${cyan}请输入新的AccessToken: ${background};read new_token
            # 更新AccessToken
            jq --argjson idx "$idx" --arg token "$new_token" \
              '.Implementations[$idx].AccessToken = $token' \
              "$config_path" > "$config_path.tmp" && mv "$config_path.tmp" "$config_path"
            
            echo -e ${green}AccessToken已更新${background}
            
            # 询问是否同步修改TRSS-Yunzai配置
            sync_token_to_trss "$new_token"
            
            # 提示需要重启并询问是否立即重启
            echo -e ${yellow}注意: 修改AccessToken后需要重启Lagrange才能生效${background}
            # 如果是特定账号的配置，需要重启该账号
            if [ -n "$account_name" ]; then
              local tmux_name="lagrange_$account_name"
              if tmux_ls $tmux_name > /dev/null 2>&1; then
                echo -en ${cyan}是否立即重启账号 $account_name? [Y/n]: ${background};read restart_now
                case ${restart_now} in
                  n|N)
                    echo -e ${yellow}请记得稍后手动重启该账号${background}
                    ;;
                  *)
                    echo -e ${yellow}正在重启账号 $account_name...${background}
                    restart_lagrange_for_account "$account_name"
                    ;;
                esac
              fi
            # 否则是全局配置，询问是否重启全局服务
            elif tmux_ls lagrangebot > /dev/null 2>&1; then
              echo -en ${cyan}是否立即重启Lagrange? [Y/n]: ${background};read restart_now
              case ${restart_now} in
                n|N)
                  echo -e ${yellow}请记得稍后手动重启Lagrange${background}
                  ;;
                *)
                  echo -e ${yellow}正在重启Lagrange...${background}
                  restart_Lagrange
                  ;;
              esac
            fi
            echo -en ${cyan}回车继续${background};read
          ;;
          2)
            # 删除AccessToken（设为空字符串）
            jq --argjson idx "$idx" \
              '.Implementations[$idx].AccessToken = ""' \
              "$config_path" > "$config_path.tmp" && mv "$config_path.tmp" "$config_path"
            
            echo -e ${green}AccessToken已删除${background}
            
            # 询问是否同步修改TRSS-Yunzai配置
            sync_token_to_trss ""
            
            # 提示需要重启并询问是否立即重启
            echo -e ${yellow}注意: 修改AccessToken后需要重启Lagrange才能生效${background}
            # 如果是特定账号的配置，需要重启该账号
            if [ -n "$account_name" ]; then
              local tmux_name="lagrange_$account_name"
              if tmux_ls $tmux_name > /dev/null 2>&1; then
                echo -en ${cyan}是否立即重启账号 $account_name? [Y/n]: ${background};read restart_now
                case ${restart_now} in
                  n|N)
                    echo -e ${yellow}请记得稍后手动重启该账号${background}
                    ;;
                  *)
                    echo -e ${yellow}正在重启账号 $account_name...${background}
                    restart_lagrange_for_account "$account_name"
                    ;;
                esac
              fi
            # 否则是全局配置，询问是否重启全局服务
            elif tmux_ls lagrangebot > /dev/null 2>&1; then
              echo -en ${cyan}是否立即重启Lagrange? [Y/n]: ${background};read restart_now
              case ${restart_now} in
                n|N)
                  echo -e ${yellow}请记得稍后手动重启Lagrange${background}
                  ;;
                *)
                  echo -e ${yellow}正在重启Lagrange...${background}
                  restart_Lagrange
                  ;;
              esac
            fi
          ;;
          3)
            # 从TRSS配置导入AccessToken
            local trss_config="$HOME/TRSS-Yunzai/config/config/server.yaml"
            
            # 检查TRSS-Yunzai配置文件是否存在
            if [ ! -f "$trss_config" ]; then
              echo -e ${red}未找到TRSS-Yunzai配置文件: ${yellow}$trss_config${background}
              echo -e ${yellow}请检查TRSS-Yunzai是否已安装或配置路径是否正确${background}
              echo -en ${cyan}回车返回${background};read
              continue
            fi
            
            echo -e ${yellow}正在从TRSS-Yunzai配置中读取AccessToken...${background}
            
            # 检查配置中是否有auth部分和authorization
            if grep -q "auth:" "$trss_config" && grep -q "authorization:" "$trss_config"; then
              # 提取authorization值，格式通常是"Bearer token"
              trss_auth=$(grep "authorization:" "$trss_config" | sed 's/.*authorization: *"\(.*\)".*/\1/')
              
              # 如果以Bearer开头，去掉Bearer和空格
              if [[ "$trss_auth" == Bearer* ]]; then
                import_token=$(echo "$trss_auth" | sed 's/Bearer *//')
                
                # 确认是否导入
                echo -e ${cyan}从TRSS配置中找到AccessToken: ${yellow}$import_token${background}
                echo -en ${cyan}是否导入此Token? [Y/n]: ${background};read confirm_import
                
                case $confirm_import in
                  n|N)
                    echo -e ${yellow}已取消导入${background}
                    ;;
                  *)
                    # 更新AccessToken
                    jq --argjson idx "$idx" --arg token "$import_token" \
                      '.Implementations[$idx].AccessToken = $token' \
                      "$config_path" > "$config_path.tmp" && mv "$config_path.tmp" "$config_path"
                    
                    echo -e ${green}AccessToken已从TRSS配置成功导入${background}
                    
                    # 提示需要重启并询问是否立即重启
                    echo -e ${yellow}注意: 修改AccessToken后需要重启Lagrange才能生效${background}
                    # 如果是特定账号的配置，需要重启该账号
                    if [ -n "$account_name" ]; then
                      local tmux_name="lagrange_$account_name"
                      if tmux_ls $tmux_name > /dev/null 2>&1; then
                        echo -en ${cyan}是否立即重启账号 $account_name? [Y/n]: ${background};read restart_now
                        case ${restart_now} in
                          n|N)
                            echo -e ${yellow}请记得稍后手动重启该账号${background}
                            ;;
                          *)
                            echo -e ${yellow}正在重启账号 $account_name...${background}
                            restart_lagrange_for_account "$account_name"
                            ;;
                        esac
                      fi
                    # 否则是全局配置，询问是否重启全局服务
                    elif tmux_ls lagrangebot > /dev/null 2>&1; then
                      echo -en ${cyan}是否立即重启Lagrange? [Y/n]: ${background};read restart_now
                      case ${restart_now} in
                        n|N)
                          echo -e ${yellow}请记得稍后手动重启Lagrange${background}
                          ;;
                        *)
                          echo -e ${yellow}正在重启Lagrange...${background}
                          restart_Lagrange
                          ;;
                      esac
                    fi
                    ;;
                esac
              else
                echo -e ${yellow}在TRSS配置中找到authorization，但格式不是"Bearer token"${background}
                echo -e ${yellow}找到的值: ${cyan}$trss_auth${background}
                echo -en ${cyan}是否还要导入此值? [y/N]: ${background};read force_import
                
                case $force_import in
                  y|Y)
                    # 更新AccessToken
                    jq --argjson idx "$idx" --arg token "$trss_auth" \
                      '.Implementations[$idx].AccessToken = $token' \
                      "$config_path" > "$config_path.tmp" && mv "$config_path.tmp" "$config_path"
                    
                    echo -e ${green}AccessToken已从TRSS配置成功导入${background}
                    
                    # 提示需要重启
                    echo -e ${yellow}注意: 修改AccessToken后需要重启Lagrange才能生效${background}
                    if [ -n "$account_name" ]; then
                      echo -en ${cyan}是否立即重启账号 $account_name? [Y/n]: ${background};read restart_now
                      case ${restart_now} in
                        n|N)
                          echo -e ${yellow}请记得稍后手动重启该账号${background}
                          ;;
                        *)
                          echo -e ${yellow}正在重启账号 $account_name...${background}
                          restart_lagrange_for_account "$account_name"
                          ;;
                      esac
                    fi
                    ;;
                  *)
                    echo -e ${yellow}已取消导入${background}
                    ;;
                esac
              fi
            else
              echo -e ${red}未在TRSS配置中找到AccessToken${background}
              echo -e ${yellow}请确保TRSS-Yunzai配置中包含auth.authorization配置项${background}
            fi
            echo -en ${cyan}回车返回${background};read
          ;;
          0)
            continue
          ;;
          *)
            echo -e ${red}无效选项${background}
            echo -en ${cyan}回车返回${background};read
          ;;
        esac
      ;;
      0)
        return
        ;;
        
      *)
        echo -e ${red}无效选项${background}
        echo -en ${cyan}回车返回${background};read
        ;;
    esac
  done
}

manage_implementations_for_account(){
  local qq_name="$1"
  local config_file="$INSTALL_DIR/accounts/$qq_name/appsettings.json"
  
  if [ ! -f "$config_file" ]; then
    echo -e ${red}配置文件不存在${background}
    echo -en ${cyan}回车返回${background};read
    return
  fi
  
  # 检查jq是否安装
  if ! check_jq; then
    echo -en ${yellow}"由于缺少jq命令，无法使用此功能，按回车返回"${background};read
    return
  fi

  # 备份配置文件
  cp "$config_file" "$config_file.bak"

  # 调用原来的管理实现函数，但传入自定义的配置文件路径
  manage_implementations_with_path "$config_file" "$qq_name"
}

change_log_level_for_account(){
  local qq_name="$1"
  local config_file="$INSTALL_DIR/accounts/$qq_name/appsettings.json"
  
  if [ ! -f "$config_file" ]; then
    echo -e ${red}配置文件不存在，请先创建配置文件${background}
    echo -en ${cyan}回车返回${background};read
    return
  fi
  
  # 检查jq是否安装
  if ! check_jq; then
    echo -en ${yellow}"由于缺少jq命令，无法使用此功能，按回车返回"${background};read
    return
  fi

  # 读取当前日志等级
  current_level=$(jq -r '.Logging.LogLevel.Default' "$config_file")
  
  echo -e ${white}"====="${green}修改日志等级${white}"====="${background}
  echo -e ${cyan}当前账号: ${yellow}$qq_name${background}
  echo -e ${cyan}当前日志等级: ${green}${current_level}${background}
  echo -e ${cyan}请选择新的日志等级:${background}
  echo -e  ${green}1. ${cyan}Trace（最详细）${background}
  echo -e  ${green}2. ${cyan}Debug${background}
  echo -e  ${green}3. ${cyan}Information（默认）${background}
  echo -e  ${green}4. ${cyan}Warning${background}
  echo -e  ${green}5. ${cyan}Error${background}
  echo -e  ${green}6. ${cyan}Critical${background}
  echo -e  ${green}7. ${cyan}None（不输出日志）${background}
  echo -e  ${green}0. ${cyan}取消${background}
  echo "========================="
  echo -en ${green}请输入您的选项: ${background};read num
  
  case $num in
    1) new_level="Trace" ;;
    2) new_level="Debug" ;;
    3) new_level="Information" ;;
    4) new_level="Warning" ;;
    5) new_level="Error" ;;
    6) new_level="Critical" ;;
    7) new_level="None" ;;
    0) return ;;
    *) 
      echo -e ${red}输入错误${background}
      echo -en ${cyan}回车返回${background};read
      return ;;
  esac
  
  # 备份配置文件
  cp "$config_file" "$config_file.bak"
  
  # 更新日志等级
  jq --arg level "$new_level" '.Logging.LogLevel.Default = $level' "$config_file" > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"
  
  echo -e ${green}账号 ${cyan}$qq_name ${green}的日志等级已更新为: ${cyan}${new_level}${background}
  echo -en ${cyan}回车返回${background};read
}

manage_single_qq(){
  local qq_name="$1"
  local QQ_DIR="$INSTALL_DIR/accounts/$qq_name"
  
  # 检查目录是否存在
  if [ ! -d "$QQ_DIR" ]; then
    echo -e ${red}账号目录不存在${background}
    echo -en ${cyan}回车返回${background};read
    return
  fi
  
  # 检查QQ是否已启动
  local tmux_name="lagrange_$qq_name"
  if tmux_ls $tmux_name > /dev/null 2>&1; then
    local status="${green}[已启动]"
  else
    local status="${red}[未启动]"
  fi
  
  # clear
  echo -e ${white}"====="${green}账号管理: ${cyan}$qq_name ${status}${white}"====="${background}
  echo -e  ${green} 1.  ${cyan}启动Lagrange${background}
  echo -e  ${green} 2.  ${cyan}关闭Lagrange${background}
  echo -e  ${green} 3.  ${cyan}重启Lagrange${background}
  echo -e  ${green} 4.  ${cyan}查看日志${background}
  echo -e  ${green} 5.  ${cyan}重写配置文件${background}
  echo -e  ${green} 6.  ${cyan}更换签名版本${background}
  echo -e  ${green} 7.  ${cyan}管理OneBot连接配置${background}
  echo -e  ${green} 8.  ${cyan}修改日志等级${background}
  echo -e  ${green} 9.  ${cyan}重新授权登录QQ${background}
  echo -e  ${green} 10. ${cyan}删除此QQ全部配置${background}
  echo -e  ${green} 0.  ${cyan}返回上级菜单${background}
  echo "========================="
  echo -en ${green}请输入您的选项: ${background};read option
  
  case $option in
    1)
      start_lagrange_for_account "$qq_name"
      ;;
    2)
      stop_lagrange_for_account "$qq_name"
      ;;
    3)
      restart_lagrange_for_account "$qq_name"
      ;;
    4)
      view_log_for_account "$qq_name"
      ;;
    5)
      rewrite_config_for_account "$qq_name"
      ;;
    6)
      change_sign_version_for_account "$qq_name"
      ;;
    7)
      manage_implementations_for_account "$qq_name"
      ;;
    8)
      change_log_level_for_account "$qq_name"
      ;;
    9)
      relogin_qq "$qq_name"
      ;;
    10)
      delete_qq "$qq_name"
      return  # 删除后返回上级菜单
      ;;
    0)
      return
      ;;
    *)
      echo -e ${red}输入错误${background}
      echo -en ${cyan}回车返回${background};read
      ;;
  esac
  
  # 返回到当前账号管理
  manage_single_qq "$qq_name"
}

create_config_for_account(){
  local qq_name="$1"
  local config_file="$INSTALL_DIR/accounts/$qq_name/appsettings.json"
  
  echo -e ${yellow}正在为账号 ${cyan}$qq_name ${yellow}创建配置文件...${background}
  
  cat > "$config_file" << EOF
{
    "\$schema": "https://raw.githubusercontent.com/LagrangeDev/Lagrange.Core/master/Lagrange.OneBot/Resources/appsettings_schema.json",
    "Logging": {
        "LogLevel": {
            "Default": "Information",
            "Microsoft": "Warning",
            "Microsoft.Hosting.Lifetime": "Information"
        }
    },
    "SignServerUrl": "https://sign.lagrangecore.org/api/sign/39038",
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
  echo -e ${green}配置文件创建完成${background}
}

create_new_qq(){
  # clear
  echo -e ${white}"====="${green}新增QQ账号${white}"====="${background}
  echo -en ${cyan}请输入QQ昵称或标识\(用于文件夹命名\): ${background};read qq_name
  
  if [ -z "$qq_name" ]; then
    echo -e ${red}昵称不能为空${background}
    echo -en ${cyan}回车返回${background};read
    return
  fi
  
  # 检查目录是否已存在
  QQ_DIR="$INSTALL_DIR/accounts/$qq_name"
  if [ -d "$QQ_DIR" ]; then
    echo -e ${red}该昵称已存在，请使用其他昵称${background}
    echo -en ${cyan}回车返回${background};read
    return
  fi
  
  # 创建账号目录
  mkdir -p "$QQ_DIR"
  
  # 创建配置文件
  create_config_for_account "$qq_name"
  
  echo -e ${green}账号 ${cyan}$qq_name ${green}创建成功${background}
  echo -e ${green}注意 ${red}为了您的账号安全，请优先配置 AccessToken: ${cyan}管理OneBot连接配置-管理AccessToken${background}
  echo -e ${green}注意 ${red}为了您的账号安全，请优先配置 AccessToken: ${cyan}管理OneBot连接配置-管理AccessToken${background}
  echo -e ${green}注意 ${red}为了您的账号安全，请优先配置 AccessToken: ${cyan}管理OneBot连接配置-管理AccessToken${background}
  echo -en ${cyan}是否立即进入该账号管理? [Y/n]: ${background};read start_now
  
  case $start_now in
    n|N)
      return
      ;;
    *)
      manage_single_qq "$qq_name"
      start_lagrange_for_account "$qq_name"
      ;;
  esac
}

manage_multi_qq(){
  if ! is_lagrange_installed; then
    echo -e ${red}"Lagrange未安装，请先安装Lagrange"${background}
    echo -en ${cyan}"按回车返回主菜单"${background};read
    return
  fi

  # clear
  # 创建账号保存主目录
  ACCOUNTS_DIR="$INSTALL_DIR/accounts"
  mkdir -p $ACCOUNTS_DIR
  
  echo -e ${white}"====="${green}多开QQ管理${white}"====="${background}  

  # 显示运行状态
  show_lagrange_status
  echo
  
  echo -e ${cyan}当前已创建的QQ账号:${background}
  
  # 列出所有账号文件夹
  account_count=0
  account_list=()
  for acc_dir in "$ACCOUNTS_DIR"/*; do
    if [ -d "$acc_dir" ]; then
      acc_name=$(basename "$acc_dir")
      account_list+=("$acc_name")

      # 检查该账号是否正在运行
      local tmux_name="lagrange_$acc_name"
      if tmux_ls $tmux_name &>/dev/null; then
        echo -e ${green}$((account_count+1)). ${cyan}$acc_name ${green}[运行中]${background}
      else
        echo -e ${green}$((account_count+1)). ${cyan}$acc_name ${red}[未运行]${background}
      fi

      account_count=$((account_count+1))
    fi
  done
  
  if [ $account_count -eq 0 ]; then
    echo -e ${yellow}还没有创建任何QQ账号${background}
  fi
  
  echo "========================="
  echo -e  ${green}N.  ${cyan}新增QQ账号${background}
  echo -e  ${green}0.  ${cyan}返回上级菜单${background}
  echo "========================="
  echo -en ${green}请输入选项\(数字或N\): ${background};read choice
  
  case $choice in
    [Nn])
      create_new_qq
      ;;
    0)
      return
      ;;
    *)
      if [[ "$choice" =~ ^[0-9]+$ ]] && [ $choice -ge 1 ] && [ $choice -le $account_count ]; then
        # 进入单个账号管理
        selected_account=${account_list[$((choice-1))]}
        manage_single_qq "$selected_account"
      else
        echo -e ${red}输入错误${background}
        echo -en ${cyan}回车返回${background};read
      fi
      ;;
  esac
  
  # 返回多开管理菜单
  manage_multi_qq
}

# 获取当前运行中的QQ账号数量
get_running_qq_count(){
  local count=0
  # 检查tmux会话列表
  if tmux ls &>/dev/null; then
    # 计算以lagrange_开头的tmux会话数量
    count=$(tmux ls 2>/dev/null | grep -c "^lagrange_")
  fi
  echo $count
}

# 显示当前运行状态
show_lagrange_status(){
  if ! is_lagrange_installed; then
    echo -e ${red}"● 拉格朗日状态: 未安装"${background}
    return
  fi
  
  local running_count=$(get_running_qq_count)
  local total_count=0
  
  # 计算总QQ数量
  if [ -d "$INSTALL_DIR/accounts" ]; then
    total_count=$(find "$INSTALL_DIR/accounts" -maxdepth 1 -type d | grep -v "^$INSTALL_DIR/accounts$" | wc -l)
  fi
  
  if [ $running_count -eq 0 ]; then
    echo -e ${yellow}"● 拉格朗日状态: 未运行"${background}
  else
    echo -e ${green}"● 拉格朗日状态: 运行中 (${cyan}${running_count}/${total_count}${green} 个QQ账号已启动)"${background}
  fi
}

# 检查Lagrange是否已安装
is_lagrange_installed() {
  if [ -d "$INSTALL_DIR" ] && [ -f "$INSTALL_DIR/Lagrange.OneBot" ]; then
    return 0  # 已安装
  else
    return 1  # 未安装
  fi
}

main(){
echo -e ${white}"====="${green}呆毛版-拉格朗日签名服务器${white}"====="${background}

# 显示运行状态
show_lagrange_status
echo

echo -e  ${green} 1.  ${cyan}安装Lagrange${background}
echo -e  ${green} 2.  ${cyan}更新Lagrange${background}
echo -e  ${green} 3.  ${cyan}卸载Lagrange${background}
echo -e  ${green} 4.  ${cyan}登陆/多开QQ管理${background}
echo -e  ${green} 0.  ${cyan}退出${background}
echo "========================="
echo -e ${green}说明: ${cyan}安装后（已默认配置trss连接），启动-扫码登录-转后台运行，启动TRSS即可。${background}
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
update_Lagrange
;;
3)
echo
uninstall_Lagrange
;;
4)
echo
manage_multi_qq
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
mainbak
