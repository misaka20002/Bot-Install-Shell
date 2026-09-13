#!/usr/bin/env bash

# 更新版本号后 sh 会自动更新本地 sh 脚本（改动脚本后必须递增，旧安装才会自动拉取新版本）
SCRIPT_VERSION="1.0.31"

# 失败路径必须能被上层察觉：pipeline 的退出码默认只取最后一个命令（tee 恒为 0）
# 脚本不使用 set -e，错误恢复仍由各函数显式判断并用返回值向上传播
set -o pipefail

export red="\033[31m"
export green="\033[32m"
export yellow="\033[33m"
export blue="\033[34m"
export purple="\033[35m"
export cyan="\033[36m"
export white="\033[37m"
export background="\033[0m"

cd "${HOME}" || exit 1
if [ "$(uname -o)" = "Android" ];then
echo -e ${red}不支持Android环境${background}
exit
fi
if [ ! "$(uname)" = "Linux" ]; then
	echo -e ${red}仅支持Linux环境${background}
    exit
fi
if [ ! "$(id -u)" = "0" ]; then
    echo -e ${red}请使用root用户${background}
    # 拒绝运行属于失败状态，统一用非零退出码（原先的 exit 0 会让调用方误判为成功）
    exit 1
fi

# 检查是否为 Debian 系系统
if [ ! -f /etc/debian_version ] && [ ! -f /etc/lsb-release ]; then
    if ! command -v apt >/dev/null 2>&1 && ! command -v apt-get >/dev/null 2>&1; then
        echo -e ${red}此脚本仅支持基于 Debian 的 Linux 发行版（如 Ubuntu、Debian 等）${background}
        echo -e ${red}检测到您的系统不是 Debian 系，程序将退出${background}
        exit 1
    fi
fi

# 统一网络超时，避免异常网络下菜单/定时任务长时间挂起（供全文使用）
CURL_CONNECT_TIMEOUT="--connect-timeout 10"
CURL_MAX_TIME="--max-time 180"

URL="https://ipinfo.io"
# 极端网络下 ipinfo.io 半连接会让菜单/定时任务长期挂住，必须带超时
Address=$(curl -sL ${CURL_CONNECT_TIMEOUT} ${CURL_MAX_TIME} ${URL} 2>/dev/null | sed -n 's/.*"country": "\(.*\)",.*/\1/p')
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

# ================= 额外MEME仓库配置 =================
# 格式: "文件夹名|子目录名（该仓库表情包存放目录，用于 toggle_single_repo）|Git仓库地址|分支名"
EXTRA_REPOS=(
    "meme-generator-contrib|memes|https://github.com/MemeCrafters/meme-generator-contrib.git|main"
    "meme_emoji|emoji|https://github.com/anyliew/meme_emoji.git|main"
    "meme-generator-jj|memes|https://github.com/jinjiao007/meme-generator-jj.git|master"
    "meme_emoji_nsfw|emoji|https://github.com/anyliew/meme_emoji_nsfw.git|main"
    "tudou-meme|meme|https://github.com/LRZ9712/tudou-meme.git|main"
    "meme-generator-cute|memes|https://github.com/AIGC-Yunzai/meme-generator-cute|main"
)
# ===================================================

# 主仓库的权威地址：所有代理 URL 都由它派生，不再从当前 remote 反解析
MAIN_REPO_NAME="meme-generator"
MAIN_REPO_URL="https://github.com/MemeCrafters/meme-generator.git"
MAIN_REPO_BRANCH="main"

# 前台模式守护循环的 PID / 停止标志（让「停止」能真正停掉前台重启循环）
FOREGROUND_PID_FILE="${HOME}/.config/meme_generator/foreground.pid"
FOREGROUND_STOP_FLAG="${HOME}/.config/meme_generator/foreground.stop"

# 公网 IP 缓存：由后台任务一次性写入；主菜单重绘只读这个文件，绝不每次都发请求
PUBLIC_IP_CACHE="${HOME}/.config/meme_generator/public_ip.cache"
PUBLIC_IP_TTL=21600   # 缓存有效期（秒，6 小时）；过期后由下一次进入脚本时的后台任务刷新
PUBLIC_IP=""          # 当前进程展示用的公网 IP（load_public_ip_cache 填充）

# 辅助函数：生成 meme_dirs 配置字符串，仅包含本地实际已存在的额外仓库
# （原 get_default_meme_dirs 已删除：它会无条件写入全部 6 个路径，
#   克隆部分失败时就把不存在的路径写进配置，meme-generator 加载即报错）

# 辅助函数：生成 meme_dirs 配置字符串，仅包含本地实际已存在的额外仓库
# 避免把未安装/半成品仓库的路径写进配置（meme-generator 会因路径不存在而报错/警告）
# 注意：校验的是「表情包子目录」而非仓库根目录，这样残缺克隆也会被排除
get_installed_meme_dirs() {
    local dirs=""
    for repo_info in "${EXTRA_REPOS[@]}"; do
        IFS='|' read -r repo_name repo_subdir repo_url repo_branch <<< "$repo_info"
        if [ -d "${install_path}/${repo_name}/${repo_subdir}" ]; then
            if [ -n "$dirs" ]; then
                dirs="${dirs}, "
            fi
            dirs="${dirs}\"${install_path}/${repo_name}/${repo_subdir}\""
        fi
    done
    echo "[${dirs}]"
}

function tmux_new(){
local Tmux_Name="$1"
local Shell_Command="$2"
local tmux_output

# 尝试清理可能残留在默认 socket 中的旧会话（兼容老版本）
tmux kill-session -t ${Tmux_Name} >/dev/null 2>&1

# 彻底清理当前独立 socket 的残留进程和损坏文件，避免 socket 损坏导致启动失败
tmux -L ${Tmux_Name} kill-server >/dev/null 2>&1
rm -f /tmp/tmux-$(id -u)/${Tmux_Name} >/dev/null 2>&1

if ! tmux_output=$(tmux -L ${Tmux_Name} new -s ${Tmux_Name} -d "${Shell_Command}" 2>&1)
then
    echo -e ${yellow}meme生成器启动错误"\n"错误原因:${red}${tmux_output}${background}
    echo
    echo -en ${yellow}回车返回${background};read
    # 不再递归回主菜单（会形成栈里套菜单的诡异状态），交回调用方处理
    return 1
fi
return 0
}

# （原 tmux_attach 已删除：定义后无任何调用点，实际附着由 bot_tmux_attach_log 承担）

function tmux_kill_session(){
local Tmux_Name="$1"
# 清理可能存在的默认 socket 中的旧会话
tmux kill-session -t ${Tmux_Name} >/dev/null 2>&1

# 清理独立 socket 中的会话并销毁 server 进程，确保不留死进程
tmux -L ${Tmux_Name} kill-server >/dev/null 2>&1
rm -f /tmp/tmux-$(id -u)/${Tmux_Name} >/dev/null 2>&1
}

function tmux_ls(){
local Tmux_Name="$1"
if tmux -L ${Tmux_Name} ls 2>&1 | grep -q ${Tmux_Name}
then
    return 0
elif tmux ls 2>&1 | grep -q ${Tmux_Name}
then
    return 0
else
    return 1
fi
}

# ================= 配置文件读写（段内定位） =================
# config_get：读取指定 [section] 下 key 的值；只在该段内匹配，并剥掉行尾注释与引号。
# 不用 grep/sed 做段内定位，避免误匹配 resource_urls 等含同类字样的行。
function config_get(){
local section="$1"
local key="$2"
local file="$3"
awk -v want_section="[${section}]" -v want_key="${key}" '
  /^[[:space:]]*\[/ { section=$0; gsub(/[[:space:]]/,"",section); next }
  section==want_section {
    line=$0; sub(/#.*/,"",line)
    n=index(line,"=")
    if (n==0) next
    k=substr(line,1,n-1); gsub(/[[:space:]]/,"",k)
    if (k==want_key) {
      v=substr(line,n+1)
      gsub(/^[[:space:]]+|[[:space:]]+$/,"",v)
      # 只剥掉整体包裹的引号："0.0.0.0" -> 0.0.0.0。
      # 数组值的引号必须保留（["/a/b", "/c/d"]），否则按引号删除/追加路径的逻辑会失效。
      if (v ~ /^".*"$/) { v=substr(v,2,length(v)-2) }
      print v; exit
    }
  }' "${file}" 2>/dev/null
}

# config_set：在指定 [section] 内把 key 的值改写为 value，保留其余内容与该行原有注释。
# config_set：在指定 [section] 内把 key 的值改写为 value，保留其余内容与该行原有注释。
# ⚠️ value 是**完整的 TOML value 表达式**：字符串必须自带引号（用 config_set_string），
#    数组写 `["/a/b"]`，布尔写 true/false。本函数不做任何类型猜测。
# 值经 ENVIRON 传给 awk（不用 -v、更不用 sed），所以 / & \ | " 都不会破坏配置。
# 找不到目标 key 时返回 1（"什么都没改却说成功"会把界面提示变成假消息）。
function config_set(){
local section="$1"
local key="$2"
local value="$3"
local file="$4"
local tmp
[ -f "${file}" ] || return 1
# 临时文件放在目标文件同目录，mv 才是同文件系统内的原子替换
tmp=$(mktemp "${file}.tmp.XXXXXX") || return 1
if new_value="${value}" awk -v want_section="[${section}]" -v want_key="${key}" '
  BEGIN { nv = ENVIRON["new_value"]; found = 0 }
  /^[[:space:]]*\[/ { section=$0; gsub(/[[:space:]]/,"",section); print; next }
  {
    if (section==want_section) {
      line=$0; sub(/#.*/,"",line)
      n=index(line,"=")
      if (n>0) {
        k=substr(line,1,n-1); gsub(/[[:space:]]/,"",k)
        if (k==want_key) {
          tail=$0; sub(/^[^#]*/,"",tail)
          if (tail ~ /^[[:space:]]*#/) { print want_key" = "nv"  "tail }
          else { print want_key" = "nv }
          found++
          next
        }
      }
    }
    print
  }
  END { if (found==0) exit 42 }' "${file}" > "${tmp}"; then
  # mv 失败同样要如实返回（旧写法 mv 失败也 return 0）
  if mv -f "${tmp}" "${file}"; then
    return 0
  fi
fi
rm -f "${tmp}"
return 1
}

# config_set_string：写入 TOML 字符串值（自动加引号，并转义内部的 \ 与 "）。
# 两个入口的分工要记住：config_set 收「原始 TOML 值」，config_set_string 收「字符串内容」。
function config_set_string(){
local section="$1"
local key="$2"
local text="$3"
local file="$4"
local escaped="${text//\\/\\\\}"
escaped="${escaped//\"/\\\"}"
config_set "${section}" "${key}" "\"${escaped}\"" "${file}"
}

function meme_port(){
config_get server port "${config}"
}

function meme_host(){
config_get server host "${config}"
}

# ================= 公网 IP（后台获取 + 本地缓存） =================
# 需求：对外展示 http://<公网IP>:<port>；但绝不允许「每进一次主菜单就 POST 一次」。
# 分工：refresh_public_ip_bg 只在 init_public_ip（脚本启动一次）发现缓存缺失/过期时后台触发；
#       load_public_ip_cache 只读缓存文件（零网络），菜单每次重绘都调它，后台写完下一屏就能看到。
# is_valid_ipv4：校验「点分四段、每段 0-255」。探测响应可能是错误页/HTML/CDN 文案，
#                不校验就会把垃圾当 IP 存进缓存并展示给用户（写缓存前、读缓存后都过这一关）。
is_valid_ipv4(){
local ip="$1"
[[ "${ip}" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
local seg
for seg in "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}"; do
    if [ "${seg}" -gt 255 ] 2>/dev/null; then return 1; fi
done
return 0
}

# 只读缓存 → 填充 PUBLIC_IP；缓存缺失/为空/损坏/TTL 过期都返回 1（调用方据此决定是否后台补获取）
load_public_ip_cache(){
PUBLIC_IP=""
[ -s "${PUBLIC_IP_CACHE}" ] || return 1
local ts="" ip=""
read -r ts ip < "${PUBLIC_IP_CACHE}" 2>/dev/null || return 1
case "${ts}" in ''|*[!0-9]*) return 1 ;; esac
is_valid_ipv4 "${ip}" || return 1
if [ "$(( $(date +%s) - ts ))" -ge "${PUBLIC_IP_TTL}" ]; then return 1; fi
PUBLIC_IP="${ip}"
return 0
}

# 后台获取（不阻塞菜单）：主方式 POST ip.3322.net（国内服务器可达、POST 直接回纯 IP），
# 失败退回 GET api.ipify.org（海外服务器更稳）。只有校验通过的 IPv4 才原子写入缓存；
# 并发重入时最多多打一次请求、mv 原子覆盖，无一致性问题，不做加锁。
refresh_public_ip_bg(){
(
    mkdir -p "${PUBLIC_IP_CACHE%/*}" 2>/dev/null
    ip=$(curl -s -X POST --connect-timeout 3 --max-time 8 https://ip.3322.net 2>/dev/null | tr -d '[:space:]')
    if ! is_valid_ipv4 "${ip}"; then
        ip=$(curl -s --connect-timeout 3 --max-time 8 https://api.ipify.org 2>/dev/null | tr -d '[:space:]')
    fi
    if is_valid_ipv4 "${ip}"; then
        ip_tmp="${PUBLIC_IP_CACHE}.tmp.$$"
        if printf '%s %s\n' "$(date +%s)" "${ip}" > "${ip_tmp}"; then
            mv -f "${ip_tmp}" "${PUBLIC_IP_CACHE}" || rm -f "${ip_tmp}"
        fi
    fi
) >/dev/null 2>&1 &
}

# 交互入口（mainbak 前）调用一次；auto_update（cron）路径刻意不调——定时任务不需要它，也不该多发请求
init_public_ip(){
if load_public_ip_cache; then return 0; fi
refresh_public_ip_bg
}

# 读取 [meme] meme_dirs 的方括号内容（不含 [ ]）
function meme_dirs_value(){
local v
v=$(config_get meme meme_dirs "${config}")
v=${v#\[}
v=${v%\]}
echo "${v}"
}

# 从「逗号分隔的路径列表」里移除一项，其余项原样保留（引号、顺序都不动）。
# 之前这里用一行多段 sed 完成，表达式本身是畸形的（GNU sed 报 unknown option to `s'），
# 导致「单独禁用某个额外仓库」从来没生效——改成纯 bash 字符串处理，不依赖 sed 转义。
function remove_dir_from_list(){
local list="$1"
local item="$2"
local out=""
local part
local old_ifs="${IFS}"
IFS=','
for part in ${list}; do
    # 去掉首尾空白
    part="${part#"${part%%[![:space:]]*}"}"
    part="${part%"${part##*[![:space:]]}"}"
    [ -z "${part}" ] && continue
    [ "${part}" = "\"${item}\"" ] && continue
    if [ -n "${out}" ]; then out="${out}, "; fi
    out="${out}${part}"
done
IFS="${old_ifs}"
echo "${out}"
}

# ================= 默认配置写入（单一来源） =================
# 初次安装与「重写配置」共用这一份默认 TOML，避免两处 heredoc 各自漂移。
# 写入流程与自更新同一套标准：mkdir 失败即停 → 同目录 mktemp → 写入 → chmod 600 → 原子 mv。
# 绝不能用 `cat > "${config}"`：那条命令在写入内容之前就先截断了目标文件，
# 一旦随后写失败，用户可用（且可能含密钥）的配置当场变成 0 字节——
# 和自更新里已经被修掉的 `curl -sL url > 目标文件` 是同一类事故。
write_default_config(){
local dir tmp meme_dirs_str
dir="${config%/*}"
mkdir -p "${dir}" || return 1

# meme_dirs 只写本地实际已存在的额外仓库（未装/半成品仓库的路径写进配置会让应用报错）
meme_dirs_str=$(get_installed_meme_dirs)

tmp=$(mktemp "${config}.new.XXXXXX") || return 1
if ! cat > "${tmp}" << EOF
[meme]
load_builtin_memes = true  # 是否加载内置表情包
meme_dirs = ${meme_dirs_str}  # 加载其他位置的表情包，填写文件夹路径
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
then
    rm -f "${tmp}"
    return 1
fi

# 配置里可能含百度翻译密钥，先收紧权限再替换，避免「替换完成但权限还没收紧」的中间态
if ! chmod 600 "${tmp}"; then
    rm -f "${tmp}"
    return 1
fi
if ! mv -f "${tmp}" "${config}"; then
    rm -f "${tmp}"
    return 1
fi
return 0
}

# 「仓库已存在」的判据：只说明克隆过（失败的克隆会留下没有 .git 的空目录，所以不能只看目录）
function is_meme_repo_installed(){
[ -d "${install_path}/${MAIN_REPO_NAME}/.git" ]
}

# 「安装真正完成」的判据：仓库 + 可用 venv + 配置文件 + **包真的装进了 venv**。
# 只用 .git 会把「clone 成功但 venv/pip/配置失败」误报成"已安装"，用户再也进不了修复流程。
# 光看 venv/bin/activate 还不够：修复模式下 pip 失败时，.git + activate + config 三样都已在，
# 只按它们判断，用户再选一次「安装」就会被"您已安装"挡回去——必须确认 meme-generator 这个包
# 确实装在 venv 里（用 venv 自己的 python，`-x` 保证不会落到 root 的系统 Python 上）。
function is_meme_install_complete(){
local venv_python="${install_path}/${MAIN_REPO_NAME}/venv/bin/python"
is_meme_repo_installed || return 1
[ -f "${install_path}/${MAIN_REPO_NAME}/venv/bin/activate" ] || return 1
[ -f "${config}" ] || return 1
[ -x "${venv_python}" ] || return 1
"${venv_python}" -m pip show meme-generator > /dev/null 2>&1 || return 1
return 0
}

# 单个额外仓库是否已安装
function is_extra_repo_installed(){
[ -d "${install_path}/${1}/.git" ]
}

# 激活主仓库 venv。失败返回 1——调用方必须检查，否则 venv 缺失/损坏时，
# 后面的 python / pip 会落到 root 的系统 Python 上，污染系统环境。
function activate_meme_venv(){
local venv_activate="${install_path}/${MAIN_REPO_NAME}/venv/bin/activate"
[ -f "${venv_activate}" ] || return 1
# shellcheck source=/dev/null
. "${venv_activate}"
}

# HTTP 健康检查：只加超时，不加 -f —— 本函数回答的是「HTTP 端口是否已有服务应答」，
# 表情包服务根路径返回 404/500 也说明服务已起来，加 -f 会把它误判成未启动。
function meme_curl(){
local Port
Port=$(meme_port)
if [ -z "${Port}" ]; then
    return 1
fi
if curl -sL --connect-timeout 2 --max-time 3 "127.0.0.1:${Port}" > /dev/null 2>&1
then
    return 0
else
    return 1
fi
}

# ================= 服务状态判断 =================
# 「HTTP 健康」（meme_curl）与「进程是否存活」是两件事：服务死锁、端口改错、
# HTTP 未就绪时进程仍在。停止/更新/看日志/重装依赖都以「进程是否存活」为准，
# 不能因为 HTTP 不通就当作「没有启动」而拒绝操作。
# 找出 meme 生成器的 python 进程 PID。
# 收紧匹配：只认「python[3.x] ... -m meme_generator.app」这种命令行，
# 并在拿得到时校验进程 cwd 就是主仓库目录——避免某个无关进程命令行里恰好
# 出现 meme_generator.app，就在 stop 时被一起 kill。
function meme_pid(){
local pid cwd repo_real
repo_real=$(readlink -f "${install_path}/${MAIN_REPO_NAME}" 2>/dev/null)
ps aux 2>/dev/null | grep -E '[Pp]ython[0-9.]* .*-m +meme_generator\.app' | awk '{print $2}' | while read -r pid; do
    [ -n "${pid}" ] || continue
    cwd=$(readlink "/proc/${pid}/cwd" 2>/dev/null)
    if [ -z "${cwd}" ] \
       || [ "${cwd}" = "${install_path}/${MAIN_REPO_NAME}" ] \
       || { [ -n "${repo_real}" ] && [ "${cwd}" = "${repo_real}" ]; }; then
        echo "${pid}"
    fi
done
}

function is_meme_process_running(){
# 前台 watchdog 在「python 崩了 → sleep 2 → 再拉起」的间隙里，既没有 python PID 也没有 tmux 会话。
# 只查这两项会把这 2 秒误判成「未运行」，于是停止/更新就可能在 watchdog 眼皮底下改 Git/venv，
# 2 秒后旧 watchdog 又把 python 拉起来——正是这轮一直在防的「一边运行一边更新」。
# foreground_pid_alive 本身 fail-closed，拿它当判据是安全的。
if foreground_pid_alive; then
    return 0
fi
if [ -n "$(meme_pid)" ]; then
    return 0
fi
if tmux_ls meme_generator > /dev/null 2>&1; then
    return 0
fi
return 1
}

# HTTP 是否已经开始应答。注意：应用根路径返回 404/500 也算「有应答」，
# 所以不叫 healthy，也不给 curl 加 -f（加 -f 会把「服务已起来」误判成未启动）。
function is_meme_http_responding(){
meme_curl
}

# ================= 前台守护循环的进程身份 =================
# 只靠 PID 判断不安全：kill -9 / 掉电 / bash 异常退出都会留下 PID 文件，
# PID 被系统复用后 kill 可能打到完全无关的 root 进程。
# 因此 PID 文件同时记录 boot_id 与进程 starttime，三者全匹配才认作我们的守护循环。
function proc_boot_id(){
cat /proc/sys/kernel/random/boot_id 2>/dev/null
}

function proc_starttime(){
# /proc/<pid>/stat 第 22 字段 = 进程启动时刻（jiffies），同一 boot 内唯一标识该进程
awk '{print $22}' "/proc/$1/stat" 2>/dev/null
}

function foreground_pid(){
sed -n '1p' "${FOREGROUND_PID_FILE}" 2>/dev/null
}

function foreground_pid_alive(){
local fg_pid fg_boot fg_start cur_boot cur_start
[ -f "${FOREGROUND_PID_FILE}" ] || return 1
fg_pid=$(foreground_pid)
fg_boot=$(sed -n '2p' "${FOREGROUND_PID_FILE}" 2>/dev/null)
fg_start=$(sed -n '3p' "${FOREGROUND_PID_FILE}" 2>/dev/null)

# fail-closed：三项身份信息缺一不可。确认不了就绝不碰这个 PID——
# 宁可让调用方报「停止失败，请人工处理」，也不能猜着 kill 掉拿了同一 PID 的无关 root 进程。
# （旧的一行式 PID 文件在这里一律视为不可信。）
[ -n "${fg_pid}" ]   || return 1
[ -n "${fg_boot}" ]  || return 1
[ -n "${fg_start}" ] || return 1
kill -0 "${fg_pid}" 2>/dev/null || return 1

cur_boot=$(proc_boot_id)
cur_start=$(proc_starttime "${fg_pid}")
[ -n "${cur_boot}" ]  || return 1
[ -n "${cur_start}" ] || return 1
[ "${fg_boot}"  = "${cur_boot}" ]  || return 1
[ "${fg_start}" = "${cur_start}" ] || return 1
return 0
}

# 登记前台守护循环的身份（三行：PID / boot_id / starttime）。
# 这必须是**可失败的事务**：`foreground_pid_alive` 是 fail-closed 的，只要身份文件写得不完整
# （目录不可写、磁盘满、boot_id 读不到、starttime 拿不到），它就会永远判 false——
# 于是「watchdog 真活着却检测不到」，刚修好的「sleep 2 间隙算运行中」保护当场失效。
# 所以：身份信息先在变量里取全并校验非空，再写同目录临时文件，成功后原子 mv；
# 任一步失败都返回 1，调用方绝不能因此进入 watchdog 循环。
function register_foreground_watchdog(){
local dir boot_id start_time tmp
dir="${FOREGROUND_PID_FILE%/*}"
mkdir -p "${dir}" || return 1

# 身份信息取不全就不要登记——写一个不完整的三行文件比不写更危险
boot_id=$(proc_boot_id)
start_time=$(proc_starttime $$)
[ -n "${boot_id}" ]    || return 1
[ -n "${start_time}" ] || return 1

# 同目录 mktemp + mv：保证是同一文件系统内的原子替换，不会留下半写的身份文件
tmp=$(mktemp "${FOREGROUND_PID_FILE}.new.XXXXXX") || return 1
if ! printf '%s\n%s\n%s\n' "$$" "${boot_id}" "${start_time}" > "${tmp}"; then
    rm -f "${tmp}"
    return 1
fi
if ! mv -f "${tmp}" "${FOREGROUND_PID_FILE}"; then
    rm -f "${tmp}"
    return 1
fi
return 0
}

# 统一停止入口：先立停止标志并停掉前台守护循环，再停 tmux 会话，最后清理残留进程。
# 三步缺一不可：只杀 python 会被前台/tmux 的守护循环在 2 秒后重新拉起。
# 如实返回：仍有残留进程时返回 1，调用方（更新/重装/卸载）必须据此中止。
#
# 身份文件的生命周期同样要 fail-closed：
#   能确认身份 → kill，**等确认它真的退出**才删除 PID 文件；
#   身份校验不过、但文件里的 PID 仍活着（旧版一行式 / PID 被复用）→ 不 kill、**不删除**，最终返回失败。
# 绝不能在确认退出前就把身份文件删掉：删了 is_meme_process_running 就再也看不见这个 watchdog，
# 残留循环会在 2 秒后把 python 重新拉起来，而我们却已经宣告「停止成功」。
function stop_meme_service(){
local fg_pid
local pid
local raw_pid
local i
local fg_unverified=false

mkdir -p "${HOME}/.config/meme_generator"
# 0) 立停止标志：前台守护循环看到它就退出，不会再把 python 拉起来。
#    标志文件故意保留（由下次前台启动时清理），否则会与「循环还没来得及看就删掉」形成竞态。
touch "${FOREGROUND_STOP_FLAG}" > /dev/null 2>&1

# 1) 前台守护循环：先校验身份，确认是本脚本的循环才 kill
if [ -f "${FOREGROUND_PID_FILE}" ]; then
    if foreground_pid_alive; then
        fg_pid=$(foreground_pid)
        kill "${fg_pid}" > /dev/null 2>&1
        i=0
        while [ "${i}" -lt 10 ] && foreground_pid_alive; do
            sleep 1
            i=$((i + 1))
        done
        if ! foreground_pid_alive; then
            rm -f "${FOREGROUND_PID_FILE}"
        fi
    else
        # 身份校验不通过。分两种：陈旧的死 PID（可安全清理）与「PID 仍活着但身份对不上」
        # （不可信——可能是旧版一行式身份文件，也可能是 PID 被复用）。后者绝不 kill、绝不删除。
        raw_pid=$(foreground_pid)
        if [ -n "${raw_pid}" ] && kill -0 "${raw_pid}" 2> /dev/null; then
            fg_unverified=true
            echo -e ${yellow}检测到无法确认身份的守护身份文件（PID ${raw_pid} 仍存活），未终止也未删除${background}
            echo -e ${yellow}如确认没有残留进程，请手动删除: ${FOREGROUND_PID_FILE}${background}
        else
            rm -f "${FOREGROUND_PID_FILE}"
        fi
    fi
fi

# 2) 停 tmux 会话（后台模式的实际管理者）
tmux_kill_session meme_generator > /dev/null 2>&1

# 3) 清理残留 python 进程
pid=$(meme_pid)
if [ -n "${pid}" ]; then
    kill ${pid} > /dev/null 2>&1
    sleep 1
    pid=$(meme_pid)
    if [ -n "${pid}" ]; then
        kill -9 ${pid} > /dev/null 2>&1
        sleep 1
    fi
fi

# 4) 如实回报：身份不可信、或仍有残留进程，都算停止失败
if [ "${fg_unverified}" = true ]; then
    return 1
fi
if is_meme_process_running; then
    return 1
fi
# 确认没有活着的守护循环了，清掉可能残留的身份文件
rm -f "${FOREGROUND_PID_FILE}"
return 0
}

function tmux_gauge(){
local i=0
local a=""
local Tmux_Name="$1"
tmux_ls "${Tmux_Name}" > /dev/null 2>&1
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
if tmux -L ${Tmux_Name} ls 2>&1 | grep -q ${Tmux_Name}; then
    if ! tmux -L ${Tmux_Name} attach -t ${Tmux_Name} > /dev/null 2>&1
    then
        tmux_windows_attach_error=$(tmux -L ${Tmux_Name} attach -t ${Tmux_Name} 2>&1)
        echo
        echo -e ${yellow}meme生成器打开错误"\n"错误原因:${red}${tmux_windows_attach_error}${background}
        echo
        echo -en ${yellow}回车返回${background};read
    fi
else
    if ! tmux attach -t ${Tmux_Name} > /dev/null 2>&1
    then
        tmux_windows_attach_error=$(tmux attach -t ${Tmux_Name} 2>&1)
        echo
        echo -e ${yellow}meme生成器打开错误"\n"错误原因:${red}${tmux_windows_attach_error}${background}
        echo
        echo -en ${yellow}回车返回${background};read
    fi
fi
}

# 添加git操作函数，支持镜像自动切换
# 目录所有权约定：本函数只允许清理「本轮自己创建/接管」的目标目录。
# 进入时若目标已存在且非空，一律拒绝且不删除——否则会误删用户手工放在该目录里的文件。
git_clone() {
  local repo_url="$1"
  local target_dir="$2"
  local log_file="$3"
  local show_progress
  local cleanup_allowed=false
  local clone_rc=1

  if [ -e "${target_dir}" ]; then
    if [ -d "${target_dir}" ] && [ -z "$(ls -A "${target_dir}" 2>/dev/null)" ]; then
      # 空目录可以安全接管
      if ! rmdir "${target_dir}" 2>/dev/null; then
        echo -e "${red}目标目录已存在但无法接管（rmdir 失败），已跳过: ${target_dir}${background}"
        [ "$log_file" != "/dev/null" ] && echo "无法接管已存在的空目录: ${target_dir}" >> "${log_file}"
        return 1
      fi
      cleanup_allowed=true
    else
      echo -e "${red}目标目录已存在且非空，为避免误删已有文件，已跳过克隆: ${target_dir}${background}"
      echo -e "${yellow}如确认该目录可丢弃，请手动删除后重试${background}"
      [ "$log_file" != "/dev/null" ] && echo "跳过克隆：目标目录已存在且非空 ${target_dir}" >> "${log_file}"
      return 1
    fi
  else
    cleanup_allowed=true
  fi

  # 检查是否需要显示进度（如果log_file是/dev/null则显示进度）
  show_progress=false
  if [ "$log_file" = "/dev/null" ]; then
    show_progress=true
  fi

  # 先尝试使用主镜像
  if [ "$show_progress" = true ]; then
    echo -e "${cyan}正在从主镜像克隆...${background}"
    git clone --progress "${GithubMirror_1}${repo_url}" "${target_dir}" 2>&1 | tee -a "${log_file}"
    if [ "${PIPESTATUS[0]}" -eq 0 ]; then return 0; fi
  else
    if git clone "${GithubMirror_1}${repo_url}" "${target_dir}" >> "${log_file}" 2>&1; then return 0; fi
  fi

  echo -e "${yellow}主镜像访问失败，尝试使用备用镜像...${background}"
  [ "$show_progress" = false ] && echo -e "${yellow}主镜像访问失败，尝试使用备用镜像...${background}" >> "${log_file}"

  # 只清理由本轮创建/接管的目录：失败会留下半成品目录，不清掉下一个镜像会因「目录非空」直接失败
  if [ "${cleanup_allowed}" = true ] && [ -d "${target_dir}" ]; then rm -rf "${target_dir}"; fi

  # 尝试使用备用镜像
  if [ "$show_progress" = true ]; then
    echo -e "${cyan}正在从备用镜像克隆...${background}"
    git clone --progress "${GithubMirror_2}${repo_url}" "${target_dir}" 2>&1 | tee -a "${log_file}"
    if [ "${PIPESTATUS[0]}" -eq 0 ]; then return 0; fi
  else
    if git clone "${GithubMirror_2}${repo_url}" "${target_dir}" >> "${log_file}" 2>&1; then return 0; fi
  fi

  # 都失败了，尝试直接访问
  echo -e "${yellow}备用镜像也失败，尝试直接访问...${background}"
  [ "$show_progress" = false ] && echo -e "${yellow}备用镜像也失败，尝试直接访问...${background}" >> "${log_file}"

  # 同样只清理本轮创建的目录，保证最后一次直连有机会成功
  if [ "${cleanup_allowed}" = true ] && [ -d "${target_dir}" ]; then rm -rf "${target_dir}"; fi

  if [ "$show_progress" = true ]; then
    echo -e "${cyan}正在从GitHub直接克隆...${background}"
    git clone --progress "${repo_url}" "${target_dir}" 2>&1 | tee -a "${log_file}"
    clone_rc="${PIPESTATUS[0]}"
  else
    git clone "${repo_url}" "${target_dir}" >> "${log_file}" 2>&1
    clone_rc=$?
  fi

  if [ "${clone_rc}" -eq 0 ]; then return 0; fi

  # 最后一次失败也要清掉「本轮拥有」的残骸：残留 .git 会被下一轮误判成已安装，
  # 非空但无 .git 又会被 git_clone 自己拒绝接管，等于永久卡死这个仓库。
  if [ "${cleanup_allowed}" = true ] && [ -e "${target_dir}" ]; then rm -rf "${target_dir}"; fi
  return 1
}

# 添加git更新函数，支持镜像自动切换及指定分支
# 更新语义：本仓库一律「强制覆盖本地」。维护者经常 git push -f 改写历史，
# 本地必然与远端分叉，因此用 fetch --force --prune + reset --hard 直接对齐远端，
# 不做任何本地合并或保留。注意「未跟踪文件」的边界（已实测确认，勿写成"用户文件一定安全"）：
# 本函数不执行 git clean，所以与远端不冲突的未跟踪文件会保留；但若某个未跟踪路径在新版远端
# 变成了 tracked，reset --hard（退出码 0）会直接覆盖它，用户放在仓库目录里的内容就没了。
# 要放自定义表情包，请放到仓库外的目录并写进 meme_dirs。
git_update() {
  local repo_dir="$1"
  local log_file="$2"
  local branch="${3:-main}"   # 默认分支为 main
  local canonical_url="$4"    # 该仓库的权威地址，所有镜像 URL 都由它派生
  local remote_url original_url url
  local -a candidates=()

  # 目录不存在或不是 git 仓库时直接返回，避免 cd 失败后在错误的目录执行 git 操作
  if [ ! -d "${repo_dir}/.git" ]; then
    echo -e "${red}目录不存在或不是git仓库，跳过更新: ${repo_dir}${background}" >> "${log_file}"
    return 1
  fi

  cd "${repo_dir}" || return 1

  remote_url=$(git remote get-url origin 2>/dev/null)
  # 权威地址只取调用方传入的 canonical_url（没有则沿用当前 origin），
  # 绝不从任意 remote 反解析：`${url#*//*/}` 会把 https:// 吃掉，
  # 产出 //github.com/... 甚至相对路径，直接把 origin 写坏。
  original_url="${canonical_url:-${remote_url}}"
  if [ -z "${original_url}" ]; then
    echo -e "${red}无法确定仓库权威地址，跳过更新: ${repo_dir}${background}" >> "${log_file}"
    return 1
  fi

  # 候选顺序：当前 origin → 主镜像 → 备用镜像 → 直连权威地址
  [ -n "${remote_url}" ] && candidates+=("${remote_url}")
  [ -n "${GithubMirror_1}" ] && candidates+=("${GithubMirror_1}${original_url}")
  [ -n "${GithubMirror_2}" ] && candidates+=("${GithubMirror_2}${original_url}")
  candidates+=("${original_url}")

  for url in "${candidates[@]}"; do
    [ -z "${url}" ] && continue
    git remote set-url origin "${url}" >> "${log_file}" 2>&1
    # --force：远端被 force-push（历史改写 / tag 被覆盖）时照常更新引用
    # --prune：清掉远端已不存在的引用
    # reset --hard：工作区强制对齐 origin/<branch>，本地改动一律丢弃（期望行为）
    if git fetch --prune --force origin >> "${log_file}" 2>&1 \
       && git reset --hard "origin/${branch}" >> "${log_file}" 2>&1; then
      return 0
    fi
    echo -e "${yellow}从 ${url} 更新失败，尝试下一个地址...${background}" >> "${log_file}"
  done

  # 全部失败也要把 origin 恢复成权威地址，绝不留下相对路径/残缺 URL
  git remote set-url origin "${original_url}" >> "${log_file}" 2>&1
  echo -e "${red}所有地址都失败，更新失败${background}" >> "${log_file}"
  return 1
}

# ================= 额外仓库按需安装 =================
# 全局变量：本次安装所选的额外仓库在 EXTRA_REPOS 中的下标
INSTALL_EXTRA_REPOS=()

# 交互式选择本次要安装的额外表情包仓库
select_extra_repos_to_install(){
    INSTALL_EXTRA_REPOS=()
    local total=${#EXTRA_REPOS[@]}

    echo
    echo -e ${white}"====="${green}选择要安装的额外表情包仓库${white}"====="${background}
    echo -e ${cyan}主仓库 meme-generator 已安装，以下额外表情包仓库可按需选择${background}
    local i=1
    for repo_info in "${EXTRA_REPOS[@]}"; do
        IFS='|' read -r repo_name repo_subdir repo_url repo_branch <<< "$repo_info"
        echo -e "  ${green}${i}.${cyan} ${repo_name}${background}"
        ((i++))
    done
    echo "========================="
    echo -e ${cyan}多选请输入编号并以空格分隔（如: ${green}1 3 5${cyan}）${background}
    echo -e ${cyan}输入 ${green}all${cyan} 安装全部；输入 0 或直接回车则不安装任何额外仓库${background}
    echo -e ${yellow}未安装的仓库可稍后在主菜单「管理额外meme仓库」中按需安装${background}
    echo -en ${green}请选择: ${background};read extra_choice

    # 统一分隔符，并去掉首尾空格
    extra_choice=$(echo "${extra_choice}" | tr ',' ' ' | sed 's/^ *//; s/ *$//')

    if [ -z "${extra_choice}" ] || [ "${extra_choice}" = "0" ]; then
        echo -e ${yellow}已跳过额外仓库，本次仅安装主仓库${background}
        return
    fi

    if [ "$(echo "${extra_choice}" | tr 'A-Z' 'a-z')" = "all" ]; then
        INSTALL_EXTRA_REPOS=("${!EXTRA_REPOS[@]}")
        echo -e ${green}已选择全部额外仓库（共 ${total} 个）${background}
        return
    fi

    local idx
    for idx in ${extra_choice}; do
        if [[ "${idx}" =~ ^[0-9]+$ ]] && [ "${idx}" -ge 1 ] && [ "${idx}" -le "${total}" ]; then
            local pos=$((idx-1))
            local exists=false
            local sel
            for sel in "${INSTALL_EXTRA_REPOS[@]}"; do
                [ "${sel}" = "${pos}" ] && exists=true
            done
            if [ "${exists}" = false ]; then
                INSTALL_EXTRA_REPOS+=("${pos}")
                echo -e ${green}已选择: $(echo "${EXTRA_REPOS[$pos]}" | cut -d'|' -f1)${background}
            fi
        else
            echo -e ${yellow}忽略无效选项: ${idx}${background}
        fi
    done

    if [ "${#INSTALL_EXTRA_REPOS[@]}" -eq 0 ]; then
        echo -e ${yellow}没有选中任何有效仓库，本次仅安装主仓库${background}
    fi
}

# 克隆用户在安装阶段所选的额外仓库
clone_selected_extra_repos(){
    if [ "${#INSTALL_EXTRA_REPOS[@]}" -eq 0 ]; then
        echo -e ${yellow}可稍后在主菜单「管理额外meme仓库」中按需安装其他仓库${background}
        return 0
    fi

    local idx repo_info repo_name repo_subdir repo_url repo_branch
    for idx in "${INSTALL_EXTRA_REPOS[@]}"; do
        repo_info="${EXTRA_REPOS[$idx]}"
        IFS='|' read -r repo_name repo_subdir repo_url repo_branch <<< "$repo_info"
        echo -e ${green}下载额外图片 ${repo_name}...${background}
        if ! git_clone "${repo_url}" "${install_path}/${repo_name}" "/dev/null"; then
            echo -e ${red}克隆 ${repo_name} 仓库失败${background}
            echo -e ${yellow}继续安装其他组件...${background}
        fi
    done
}

install_meme_generator(){
# 区分「仓库已存在」与「安装已完成」：.git 只说明克隆过，venv / 配置可能还没建好
if is_meme_install_complete; then
  echo -e ${yellow}您已安装meme生成器${background}
  echo -en ${yellow}回车返回${background};read
  return
fi

resume_install=false
if is_meme_repo_installed; then
  # 上次安装中断（例如 pip 失败）：仓库没必要重新下载，进入修复/继续流程
  resume_install=true
  echo -e ${yellow}检测到 meme-generator 仓库已存在，但安装尚未完成${background}
  echo -e ${cyan}将跳过克隆，继续完成安装（修复模式）${background}
fi

# 说明：安装阶段不再改写 /etc/resolv.conf。为访问 GitHub 而永久替换系统 DNS
# 会破坏 systemd-resolved / Docker / 内网 DNS 等环境，且卸载时不会恢复；
# 国内环境已由上面的 GitMirror / GithubMirror 变量走代理解决。

echo -e ${green}安装系统依赖...${background}
if [ $(command -v apt) ];then
  apt update -y
  if ! apt install -y curl git cron python3-pip python3-venv tmux fonts-noto-cjk fonts-noto-color-emoji python3-opengl; then
    echo -e ${red}系统依赖安装失败，安装中止${background}
    echo -en ${yellow}回车返回${background};read
    return 1
  fi
elif [ $(command -v yum) ];then
  yum makecache -y
  if ! yum install -y curl git cronie python3-pip python3-venv tmux; then
    echo -e ${red}系统依赖安装失败，安装中止${background}
    echo -en ${yellow}回车返回${background};read
    return 1
  fi
elif [ $(command -v dnf) ];then
  dnf makecache -y
  if ! dnf install -y curl git cronie python3-pip python3-venv tmux; then
    echo -e ${red}系统依赖安装失败，安装中止${background}
    echo -en ${yellow}回车返回${background};read
    return 1
  fi
elif [ $(command -v pacman) ];then
  if ! pacman -Syy --noconfirm --needed curl git cronie python-pip python-virtualenv tmux; then
    echo -e ${red}系统依赖安装失败，安装中止${background}
    echo -en ${yellow}回车返回${background};read
    return 1
  fi
else
  echo -e ${red}不受支持的Linux发行版${background}
  exit
fi

# 创建安装目录
mkdir -p ${install_path}
cd ${install_path} || { echo -e ${red}创建安装目录失败${background}; echo -en ${yellow}回车返回${background};read; return 1; }

if [ "${resume_install}" = true ]; then
  echo -e ${cyan}跳过克隆，复用已有仓库${background}
else
  # 克隆meme-generator仓库
  echo -e ${green}克隆meme-generator仓库...${background}
  if ! git_clone "${MAIN_REPO_URL}" "${install_path}/${MAIN_REPO_NAME}" "/dev/null"; then
    echo -e ${red}克隆meme-generator仓库失败${background}
    echo -en ${yellow}回车返回${background};read
    return 1
  fi
fi

# 创建 / 修复虚拟环境：判据一律用 venv/bin/activate（有目录没 activate 的残缺 venv 必须重建）
cd "${install_path}/${MAIN_REPO_NAME}" || { echo -e ${red}进入安装目录失败${background}; echo -en ${yellow}回车返回${background};read; return 1; }
if [ ! -f venv/bin/activate ]; then
  if [ -d venv ]; then
    echo -e ${yellow}虚拟环境不完整，正在重建...${background}
    rm -rf venv
  fi
  if ! python3 -m venv venv; then
    echo -e ${red}创建虚拟环境失败，请检查 python3-venv 是否已安装${background}
    echo -en ${yellow}回车返回${background};read
    return 1
  fi
fi
if [ ! -f venv/bin/activate ]; then
  echo -e ${red}虚拟环境不完整（缺少 venv/bin/activate），安装中止${background}
  echo -en ${yellow}回车返回${background};read
  return 1
fi

# pip 国内镜像只写进本项目的 venv，不再覆盖 $HOME/.pip/pip.conf 等全局 pip 配置
cat > venv/pip.conf << EOF
[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple/
extra-index-url = https://pypi.mirrors.ustc.edu.cn/simple/
trusted-host = pypi.tuna.tsinghua.edu.cn
               pypi.mirrors.ustc.edu.cn
timeout = 120
retries = 5
EOF

if ! activate_meme_venv; then
  echo -e ${red}激活虚拟环境失败，安装中止（避免落到系统 Python）${background}
  echo -en ${yellow}回车返回${background};read
  return 1
fi
# 核心安装步骤：失败必须中止，不能只打印红字然后继续走到「安装完成」
if ! python -m pip install . ; then
  echo -e ${red}meme-generator 依赖安装失败，安装中止${background}
  echo -e ${yellow}排查后可重新执行本项安装${background}
  echo -en ${yellow}回车返回${background};read
  return 1
fi

# 交互式选择并下载额外表情包仓库（按需安装，可多选 / 全选 / 跳过）
select_extra_repos_to_install
clone_selected_extra_repos

# 写入配置：已有配置保留（修复模式不覆盖用户自定义设置），否则调用统一的默认配置写入器
# （write_default_config 走 temp → chmod 600 → 原子替换，失败会如实返回 1）
if [ -f "${config}" ]; then
  echo -e ${cyan}检测到已有配置文件，保留现有配置: ${config}${background}
  # 配置里可能含百度密钥，权限收紧失败必须说出来（这是安全约束，不是 best-effort）
  if ! chmod 600 "${config}"; then
    echo -e ${red}收紧配置文件权限失败（配置可能含密钥），请手动执行: chmod 600 ${config}${background}
  fi
else
  if ! write_default_config; then
    echo -e ${red}写入默认配置文件失败，安装中止${background}
    echo -en ${yellow}回车返回${background};read
    return 1
  fi
fi

# 下载默认图片（非核心步骤：失败只提示，不影响「核心安装成功」的结论）
echo -e ${green}下载默认图片...${background}
cd "${install_path}/${MAIN_REPO_NAME}" || { echo -e ${red}进入安装目录失败${background}; return 1; }
if activate_meme_venv; then
  if ! python -m meme_generator.cli meme download; then
    echo -e ${yellow}核心安装成功，但默认表情包资源下载失败，可稍后重新执行下载${background}
  fi
else
  echo -e ${yellow}核心安装成功，但激活虚拟环境失败，已跳过默认资源下载${background}
fi

# 安装字体（非核心步骤）
echo -e ${green}安装字体...${background}
mkdir -p /usr/share/fonts
if ! cp ${install_path}/${MAIN_REPO_NAME}/resources/fonts/* /usr/share/fonts 2>/dev/null; then
  echo -e ${yellow}字体复制失败（不影响运行，可手动复制 resources/fonts）${background}
fi
fc-cache -f > /dev/null 2>&1

# 提醒开放端口
echo -e ${yellow}请确保您的防火墙已开放50835端口${background}

echo -e ${green}安装完成！${background}
echo -en ${yellow}是否立即启动meme生成器? [Y/n]${background};read yn
case ${yn} in
N|n)
    ;;
*)
    start_meme_generator
    ;;
esac
}

start_meme_generator(){
# 显示用的动作名由调用方以参数传入（默认"启动"）。**不要用全局变量**：
# 一次 restart 把它设成"重启"后会粘住，同一个管理 Shell 里之后的普通启动都会显示"重启成功"。
# bash 是动态作用域，这里的 local 在嵌套定义的 Tmux_Start 里同样可见。
local Start_Stop_Restart="${1:-启动}"
# 安装未完成一律不许启动：只判「仓库在 + activate 在」会放过修复模式的半成品
# （venv 建好了但 pip 没装上），启动必然失败。让修复模式真正贯穿入口。
# cd 失败后留在错误目录继续执行，也是这里要提前拦住的原因。
if ! is_meme_install_complete; then
    if is_meme_repo_installed; then
        echo -e ${red}安装尚未完成，请先执行「安装meme生成器」进入修复模式${background}
    else
        echo -e ${red}尚未安装meme生成器，请先安装${background}
    fi
    echo -en ${yellow}回车返回${background};read
    return 1
fi

if is_meme_process_running; then
    echo -en ${yellow}meme生成器已启动 ${cyan}回车返回${background};read
    echo
    return
fi

Foreground_Start(){
# 先把「所有可能失败的准备」做完，再登记 watchdog 身份。
# PID 文件 + EXIT trap 必须放在 cd / venv 激活之后：否则 venv 损坏时这里会留下一个指向
# 「管理 Shell 自己」的有效身份文件，之后选「卸载」就会 kill 掉当前这个管理进程。
cd "${install_path}/${MAIN_REPO_NAME}" || return 1
if ! activate_meme_venv; then
    echo -e ${red}激活虚拟环境失败，无法前台启动${background}
    echo -en ${yellow}回车返回${background};read
    return 1
fi

# 走到这里才说明真要进入 watchdog：先清掉上次遗留的停止标志，再登记身份。
# 登记是「可失败的事务」（见 register_foreground_watchdog）：登记失败就不进入循环，
# 否则会出现「watchdog 真活着、但身份文件不可用」的检测黑洞。
rm -f "${FOREGROUND_STOP_FLAG}"
if ! register_foreground_watchdog; then
    echo -e ${red}登记守护进程身份失败，未前台启动${background}
    echo -e ${yellow}请检查 ${HOME}/.config/meme_generator 是否可写后重试${background}
    echo -en ${yellow}回车返回${background};read
    return 1
fi
trap 'rm -f "${FOREGROUND_PID_FILE}"' EXIT

while true
do
  if [ -f "${FOREGROUND_STOP_FLAG}" ]; then break; fi
  python -m meme_generator.app
  if [ -f "${FOREGROUND_STOP_FLAG}" ]; then break; fi
  echo -e ${red}meme生成器关闭 正在重启${background}
  sleep 2s
done
echo -en ${cyan}回车返回${background}
read
echo
}

Tmux_Start(){
    # 动作名由 start_meme_generator 的 local 传进来（bash 动态作用域）；这里只做兜底，
    # 并且写成 local —— 否则在别处被调用时又会生成一个粘性的全局值。
    local Start_Stop_Restart="${Start_Stop_Restart:-启动}"
    if ! tmux_new meme_generator "cd ${install_path}/${MAIN_REPO_NAME} && source venv/bin/activate && while true; do python -m meme_generator.app; echo -e ${red}meme生成器关闭 正在重启${background}; sleep 2s; done"; then
        return 1
    fi
    if tmux_gauge meme_generator
    then
        echo
        echo -en ${green}${Start_Stop_Restart}成功 是否打开窗口 进入TMUX窗口后，退出请按 Ctrl+B 然后按 D [y/N]:${background}
    else
        echo
        echo -en ${green}${Start_Stop_Restart}等待超时 是否打开窗口 进入TMUX窗口后，退出请按 Ctrl+B 然后按 D [y/N]:${background}
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

echo
echo -e ${white}"====="${green}呆毛版-meme生成器${white}"====="${background}
echo -e ${cyan}请选择启动方式${background}
echo -e  ${green}1.  ${cyan}前台启动${background}
echo -e  ${green}2.  ${cyan}TMUX后台启动（推荐）${background}
echo "========================="
echo -en ${green}请输入您的选项: ${background};read num
case ${num} in
1) Foreground_Start ;;
2) Tmux_Start ;;
*) echo; echo -e ${red}输入错误${background};return ;;
esac
}

stop_meme_generator(){
# 以「进程是否存活」为准：服务死锁 / 端口改错时 HTTP 不通，但进程仍在，必须允许停止
if ! is_meme_process_running; then
    echo -en ${red}meme生成器未启动 ${cyan}回车返回${background}
    read
    echo
    return
fi

echo -e ${yellow}正在停止meme生成器${background}
if stop_meme_service; then
    echo -en ${red}meme生成器停止成功 ${cyan}回车返回${background}
else
    echo -en ${red}meme生成器停止失败，仍有残留进程，请手动检查 ${cyan}回车返回${background}
fi
read
echo
}

restart_meme_generator(){
if ! is_meme_process_running; then
    echo -e ${red}meme生成器未启动，无法重启${background}
    echo
    return
fi
# 停不下来就不要继续，否则「重启」会变成「再起一份」
if ! stop_meme_service; then
    echo -e ${red}meme生成器停止失败，已中止重启（请先手动检查残留进程）${background}
    echo
    return 1
fi
# 这里已经安全停过一次，直接用 start_meme_generator（别用"要求服务当前在运行"的 restart）
start_meme_generator "重启"
}

update_meme_generator(){
# 增加安装状态 guard：主菜单允许直接按 5，未安装时必须在这里拦住
if ! is_meme_repo_installed; then
    echo -e ${red}尚未安装meme生成器，请先安装${background}
    echo -en ${yellow}回车返回${background};read
    return 1
fi

# 记录更新前是否在运行（按进程判断，不看 HTTP）
meme_was_running=false
if is_meme_process_running; then
    meme_was_running=true
    echo -e ${yellow}正在停止meme生成器${background}
    # 停不下来就不能继续改代码/依赖，否则会变成「一边运行一边更新」
    if ! stop_meme_service; then
        echo -e ${red}meme生成器停止失败，已中止更新（请先手动检查残留进程）${background}
        echo -en ${yellow}回车返回${background};read
        return 1
    fi
    echo
fi

# 任何一步失败都记为「部分更新失败」，最后如实汇报并返回非零
local update_rc=0

echo -e ${yellow}正在更新meme生成器核心...${background}
if ! git_update "${install_path}/${MAIN_REPO_NAME}" "/dev/null" "${MAIN_REPO_BRANCH}" "${MAIN_REPO_URL}"; then
  echo -e ${red}更新meme-generator失败${background}
  echo -e ${yellow}继续更新其他组件...${background}
  update_rc=1
fi

cd "${install_path}/${MAIN_REPO_NAME}" || { echo -e ${red}进入安装目录失败${background}; echo -en ${yellow}回车返回${background};read; return 1; }
if [ ! -f venv/bin/activate ]; then
  echo -e ${red}虚拟环境不存在，请先执行「重新安装依赖」${background}
  echo -en ${yellow}回车返回${background};read
  return 1
fi
if ! activate_meme_venv; then
    echo -e ${red}激活虚拟环境失败，已中止更新（避免落到系统 Python）${background}
    echo -en ${yellow}回车返回${background};read
    return 1
fi
if ! python -m pip install . ; then
  echo -e ${red}meme-generator 依赖更新失败${background}
  update_rc=1
fi

# 动态更新所有额外依赖仓库（仅更新已安装的仓库，未安装的不会被自动安装）
for repo_info in "${EXTRA_REPOS[@]}"; do
    IFS='|' read -r repo_name repo_subdir repo_url repo_branch <<< "$repo_info"
    repo_branch=${repo_branch:-main}
    if ! is_extra_repo_installed "${repo_name}"; then
        echo -e ${cyan}跳过未安装的仓库 ${repo_name}${background}
        continue
    fi
    echo -e ${yellow}正在更新 ${repo_name}...${background}
    if ! git_update "${install_path}/${repo_name}" "/dev/null" "${repo_branch}" "${repo_url}"; then
        echo -e ${red}更新 ${repo_name} 失败${background}
        update_rc=1
    fi
done

if [ "${update_rc}" -eq 0 ]; then
    echo -e ${green}更新完成！${background}
else
    echo -e ${red}部分组件更新失败，请查看上方提示${background}
fi

local Start_Label="启动"
if [ "${meme_was_running}" = true ]; then
    Start_Label="重启"
    echo -en ${yellow}是否重新启动meme生成器? [Y/n]${background};read yn
else
    echo -en ${yellow}是否启动meme生成器? [Y/n]${background};read yn
fi
case ${yn} in
N|n)
    echo -e ${yellow}请记得手动启动meme生成器${background}
    ;;
*)
    start_meme_generator "${Start_Label}"
    ;;
esac

return "${update_rc}"
}

confirm_action() {
    local operate_text="$1"
    echo -en "${yellow}是否确认${operate_text}？[y/N] ${background}";read user_input
    case "${user_input}" in
        Y|y) return 0 ;;
        *)   return 1 ;;
    esac
}

uninstall_meme_generator(){
if [ ! -d ${install_path}/meme-generator ];then
    echo -en ${red}您还没有安装meme生成器! ${cyan}回车返回${background};read
    return
fi

confirm_action "卸载meme生成器"
if [ $? -ne 0 ]; then
    echo -en "${yellow}操作已取消，回车返回${background}";read
    return
fi

echo -e ${yellow}正在停止meme生成器...${background}
# 停不下来就绝不继续删目录：一边运行一边被 rm -rf 是最糟的情况
if ! stop_meme_service; then
    echo -e ${red}meme生成器未能停止，已中止卸载（请先手动检查残留进程）${background}
    echo -en ${yellow}回车返回${background};read
    return 1
fi

# 同步移除自动更新定时任务：否则「卸载完成」后 root 的 cron 仍会每天跑
# **读取失败必须按"cron 可能仍在"处理**（cron_removed=false）：不能因为读不到就当成"没有该任务"，
# 否则下面会允许删除系统脚本，留下一个每天执行不存在脚本的 root 定时任务。
cron_removed=true
meme_cron_present
cron_state=$?
if [ "${cron_state}" -eq 0 ]; then
    if remove_meme_cron; then
        echo -e ${green}已移除自动更新定时任务${background}
    else
        cron_removed=false
        echo -e ${red}移除自动更新定时任务失败（cron 仍在），请手动执行 crontab -e 检查${background}
    fi
elif [ "${cron_state}" -eq 2 ]; then
    cron_removed=false
    echo -e ${red}无法读取当前 crontab，已按「自动更新任务可能仍在」处理${background}
    echo -e ${yellow}请先手动执行 crontab -e 检查${background}
fi

echo -e ${yellow}是否保留配置文件? [Y/n]${background};read yn
case ${yn} in
N|n)
    rm -rf $HOME/.config/meme_generator
    ;;
esac

rm -rf ${install_path}
echo -e ${green}meme生成器卸载完成！${background}

# 系统脚本只是自动更新入口，默认保留
echo -en ${yellow}是否同时删除系统脚本 ${SCRIPT_SYSTEM_PATH}? [y/N]${background};read yn
case ${yn} in
Y|y)
    if [ "${cron_removed}" = true ]; then
        rm -f "${SCRIPT_SYSTEM_PATH}"
        echo -e ${green}已删除 ${SCRIPT_SYSTEM_PATH}${background}
    else
        # cron 没清掉就把脚本删了，会留下一个每天执行不存在文件的 root 定时任务
        echo -e ${red}cron 清理未成功，已拒绝删除 ${SCRIPT_SYSTEM_PATH}${background}
        echo -e ${yellow}请先执行 crontab -e 删除 meme_generator_auto_update 那行，再手动删除该脚本${background}
    fi
    ;;
*)
    if [ "${cron_removed}" = true ]; then
        echo -e ${cyan}已保留 ${SCRIPT_SYSTEM_PATH}（自动更新定时任务已移除）${background}
    else
        echo -e ${yellow}卸载主体完成，但 cron 清理失败：${SCRIPT_SYSTEM_PATH} 与定时任务都还在${background}
    fi
    ;;
esac

echo -en ${yellow}回车返回${background};read
}

log_meme_generator(){
  # 看日志恰恰是在服务异常时最需要，所以只按 tmux 会话 / 进程判断，不再要求 HTTP 健康
  if tmux_ls meme_generator > /dev/null 2>&1
  then
      echo -en ${yellow}进入TMUX窗口后，退出请按 Ctrl+B 然后按 D${background};read
      bot_tmux_attach_log meme_generator
      return
  fi

  if is_meme_process_running; then
      echo -e ${yellow}meme生成器正在前台运行（没有 tmux 会话），无法在本窗口查看其输出${background}
      echo -e ${cyan}如需在 tmux 中查看日志，请先关闭后用「TMUX后台启动」重新启动${background}
      echo -en ${yellow}回车返回${background};read
      return
  fi

  echo -en ${red}meme生成器未启动 ${cyan}回车返回${background};read
  echo
}

change_port(){
if [ ! -f ${config} ]; then
    echo -e ${red}配置文件不存在，请先安装meme生成器!${background}
    echo -en ${yellow}回车返回${background};read
    return
fi

OldPort=$(meme_port)
if [ -z "${OldPort}" ]; then
    echo -e ${red}未能从配置文件的 [server] 段读到当前端口，请先用「重写配置文件」恢复配置${background}
    echo -en ${yellow}回车返回${background};read
    return
fi

echo -e ${cyan}请确保您的防火墙已开放端口: ${background}
echo -e ${cyan}当前端口: ${green}${OldPort}${background}
echo -e "${cyan}请输入新端口号 (1-65535): ${background}";read NewPort

# 端口必须落在 1..65535：旧逻辑只校验「纯数字」，0 / 65536 / 999999 都会通过
if [[ ! ${NewPort} =~ ^[0-9]+$ ]] || [ "${NewPort}" -lt 1 ] || [ "${NewPort}" -gt 65535 ]; then
    echo -e ${red}请输入 1-65535 之间的有效端口号!${background}
    echo -en ${yellow}回车返回${background};read
    return
fi

# 只在 [server] 段内改写 port，值不经 sed 替换（避免 / & \ 影响配置）
if ! config_set server port "${NewPort}" "${config}"; then
    echo -e ${red}写入端口失败，请检查配置文件权限${background}
    echo -en ${yellow}回车返回${background};read
    return 1
fi
echo -e ${green}端口已修改为: ${NewPort}${background}
echo -e ${yellow}请确保您的防火墙已开放${NewPort}端口${background}

echo -e ${yellow}是否重启meme生成器以应用新端口? [Y/n]${background};read yn
case ${yn} in
N|n)
    echo -e ${yellow}请记得手动重启meme生成器以应用新端口${background}
    echo -en ${yellow}回车返回${background};read
    ;;
*)
    restart_meme_generator
    ;;
esac
}

# 从远程下载脚本并原子替换到系统目录。
# 必须走「临时文件 → curl -f（HTTP 4xx/5xx 视为失败）→ 语法 + 版本一致性校验 → 原子替换」：
# 旧实现 `curl -sL ... > "$SCRIPT_SYSTEM_PATH"` 会在 curl 成功之前先截断目标文件，
# 断网时会把一个本来可用的系统脚本清空成 0 字节，并把 404/500 错误页当成脚本装上去。
#
# 版本一致性：镜像可能滞后。若下载到的版本 != 当前运行的 SCRIPT_VERSION，必须换下一个源，
# 否则会把旧版本当成功写回系统目录，甚至造成"越更新越旧"。
download_script() {
  local url tmp new_path downloaded_version
  tmp=$(mktemp /tmp/meme_generator_dl.XXXXXX) || return 1
  for url in \
    "https://gitee.com/Misaka21011/Yunzai-Bot-Shell/raw/master/Manage/meme_generator.sh" \
    "https://raw.githubusercontent.com/misaka20002/Bot-Install-Shell/refs/heads/master/Manage/meme_generator.sh"; do
    downloaded_version=""
    if curl -fL ${CURL_CONNECT_TIMEOUT} ${CURL_MAX_TIME} --retry 3 --retry-delay 1 -o "${tmp}" "${url}" 2>/dev/null \
       && [ -s "${tmp}" ] \
       && bash -n "${tmp}" > /dev/null 2>&1; then
      downloaded_version=$(grep -m 1 '^SCRIPT_VERSION=' "${tmp}" | cut -d'"' -f2)
    fi
    if [ "${downloaded_version}" != "${SCRIPT_VERSION}" ]; then
      echo "警告: ${url} 未返回当前版本 ${SCRIPT_VERSION}（实际: ${downloaded_version:-获取失败}），尝试下一个源" >&2
      continue
    fi
    new_path="${SCRIPT_SYSTEM_PATH}.new.$$"
    if cp -f "${tmp}" "${new_path}" && chmod 0755 "${new_path}" && mv -f "${new_path}" "${SCRIPT_SYSTEM_PATH}"; then
      rm -f "${tmp}"
      return 0
    fi
    rm -f "${new_path}"
  done
  rm -f "${tmp}"
  echo "警告: 脚本更新失败（下载失败或内容校验未通过），meme服务器自动更新服务可能出错，请检查网络连接" >&2
  return 1
}

ensure_script_saved() {
  local current_version="${SCRIPT_VERSION}"
  local local_version=""
  # 同版本 fast path 也必须确认「文件可用」：非空 + 可执行 + 语法通过。
  # 否则一个被截坏的 1.0.29 会被当成"已是最新"，cron 拿到坏脚本。
  if [ -s "$SCRIPT_SYSTEM_PATH" ] && [ -x "$SCRIPT_SYSTEM_PATH" ] \
     && bash -n "$SCRIPT_SYSTEM_PATH" > /dev/null 2>&1; then
    local_version=$(grep -m 1 '^SCRIPT_VERSION=' "$SCRIPT_SYSTEM_PATH" | cut -d'"' -f2)
    if [ "${current_version}" = "${local_version}" ]; then
      return 0
    fi
  fi
  # 关键：把下载结果如实返回，调用方必须据此决定要不要创建 / 保留 cron 任务
  download_script
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

  echo -e "${yellow}[$(date "+%Y-%m-%d %H:%M:%S")] 开始自动更新meme生成器...${background}" >> "${log_file}"

  # 尚未安装就什么都不做，避免在空目录上执行 git / pip
  if ! is_meme_repo_installed; then
    echo -e "${red}[$(date "+%Y-%m-%d %H:%M:%S")] 未安装meme生成器，跳过本次自动更新${background}" >> "${log_file}"
    return 1
  fi

  # 任何一步失败都记为失败，最终以非零退出码返回（cron 才能发现异常）
  local update_rc=0

  # 检查meme生成器是否在运行（按进程判断；HTTP 健康 ≠ 进程存在）
  was_running=false
  if is_meme_process_running; then
    was_running=true
    echo -e "${yellow}[$(date "+%Y-%m-%d %H:%M:%S")] 正在停止meme生成器${background}" >> "${log_file}"
    if ! stop_meme_service >> "${log_file}" 2>&1; then
      echo -e "${red}[$(date "+%Y-%m-%d %H:%M:%S")] meme生成器停止失败，中止本次更新${background}" >> "${log_file}"
      return 1
    fi
  fi

  # 更新meme-generator
  echo -e "${yellow}[$(date "+%Y-%m-%d %H:%M:%S")] 正在更新meme生成器...${background}" >> "${log_file}"
  if ! git_update "${install_path}/${MAIN_REPO_NAME}" "${log_file}" "${MAIN_REPO_BRANCH}" "${MAIN_REPO_URL}"; then
    echo -e "${red}[$(date "+%Y-%m-%d %H:%M:%S")] meme-generator更新失败${background}" >> "${log_file}"
    update_rc=1
  fi

  if cd "${install_path}/${MAIN_REPO_NAME}"; then
    if activate_meme_venv >> "${log_file}" 2>&1; then
      if ! python -m pip install . >> "${log_file}" 2>&1; then
        echo -e "${red}[$(date "+%Y-%m-%d %H:%M:%S")] 依赖安装失败${background}" >> "${log_file}"
        update_rc=1
      fi
    else
      echo -e "${red}[$(date "+%Y-%m-%d %H:%M:%S")] 虚拟环境缺失或损坏，跳过依赖安装${background}" >> "${log_file}"
      update_rc=1
    fi
  else
    echo -e "${red}[$(date "+%Y-%m-%d %H:%M:%S")] 进入安装目录失败${background}" >> "${log_file}"
    update_rc=1
  fi

  # 动态更新所有额外依赖仓库（仅更新已安装的仓库，未安装的不会被自动安装）
  for repo_info in "${EXTRA_REPOS[@]}"; do
      IFS='|' read -r repo_name repo_subdir repo_url repo_branch <<< "$repo_info"
      repo_branch=${repo_branch:-main}
      if ! is_extra_repo_installed "${repo_name}"; then
          echo -e "${cyan}[$(date "+%Y-%m-%d %H:%M:%S")] 跳过未安装的仓库${repo_name}${background}" >> "${log_file}"
          continue
      fi
      echo -e "${yellow}[$(date "+%Y-%m-%d %H:%M:%S")] 正在更新${repo_name}...${background}" >> "${log_file}"
      if ! git_update "${install_path}/${repo_name}" "${log_file}" "${repo_branch}" "${repo_url}"; then
          echo -e "${red}[$(date "+%Y-%m-%d %H:%M:%S")] ${repo_name}更新失败${background}" >> "${log_file}"
          update_rc=1
      fi
  done

  if [ "${update_rc}" -eq 0 ]; then
    echo -e "${green}[$(date "+%Y-%m-%d %H:%M:%S")] 更新完成！${background}" >> "${log_file}"
  else
    echo -e "${red}[$(date "+%Y-%m-%d %H:%M:%S")] 部分组件更新失败，请查看日志${background}" >> "${log_file}"
  fi

  # 如果之前在运行，则重新启动 - 使用完整路径和环境变量
  if [ "${was_running}" = true ]; then
    echo -e "${yellow}[$(date "+%Y-%m-%d %H:%M:%S")] 正在重新启动meme生成器...${background}" >> "${log_file}"

    # 检查虚拟环境和必要文件
    if [ ! -f "${install_path}/${MAIN_REPO_NAME}/venv/bin/activate" ]; then
      echo -e "${red}[$(date "+%Y-%m-%d %H:%M:%S")] 虚拟环境不存在，无法启动${background}" >> "${log_file}"
      return 1
    fi

    # 启动脚本改用 mktemp 独占文件：root 下用固定名 /tmp/meme_start.sh，
    # 其他本地用户可抢占该路径或构造符号链接，root 重定向时存在覆盖他人文件的风险
    start_script=$(mktemp /tmp/meme_start.XXXXXX) || {
      echo -e "${red}[$(date "+%Y-%m-%d %H:%M:%S")] 创建临时启动脚本失败${background}" >> "${log_file}"
      return 1
    }
    chmod 700 "${start_script}"
    cat > "${start_script}" << EOF
#!/bin/bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export HOME="${HOME}"
cd ${install_path}/${MAIN_REPO_NAME} || exit 1
source venv/bin/activate || exit 1
while true; do
    python -m meme_generator.app
    echo "meme生成器关闭，2秒后重启..."
    sleep 2
done
EOF

    # 使用完整路径启动 tmux
    if /usr/bin/tmux -L meme_generator new -s meme_generator -d "/bin/bash ${start_script}" 2>>"${log_file}"; then
      echo -e "${green}[$(date "+%Y-%m-%d %H:%M:%S")] tmux 会话创建成功${background}" >> "${log_file}"

      # 等待服务启动
      sleep 15
      if is_meme_http_responding; then
        echo -e "${green}[$(date "+%Y-%m-%d %H:%M:%S")] meme生成器成功启动${background}" >> "${log_file}"
      else
        echo -e "${red}[$(date "+%Y-%m-%d %H:%M:%S")] meme生成器启动失败或启动较慢，请查看日志${background}" >> "${log_file}"
        update_rc=1
      fi
    else
      echo -e "${red}[$(date "+%Y-%m-%d %H:%M:%S")] tmux 命令执行失败${background}" >> "${log_file}"
      update_rc=1
    fi

    # 清理临时脚本
    rm -f "${start_script}"
  fi

  return "${update_rc}"
}

# ================= crontab 读写（统一入口，fail-closed） =================
# 为什么必须统一：`crontab -l 2>/dev/null | grep -q ...` 这种各写一遍的判断，在"读取真的失败"时
# 会呈现为「非零 + stdout 为空」，于是被当成"用户没有 crontab / 没有该任务"。一旦如此：
#   · 卸载会认为 cron 已清掉，从而允许删除系统脚本 —— 留下一个每天执行不存在脚本的 root 任务；
#   · 开启自动更新会认为"尚无该任务"，接着用 `(crontab -l; echo 新行) | crontab -` 重建，
#     而那个 subshell 里 `crontab -l` 失败、`echo` 成功、退出码仍是 0，
#     **用户的整份 crontab 会被覆盖成只剩一行**。
#
# read_current_crontab <输出文件>：把"当前 crontab 内容"安全读到文件里。
#   返回 0 → 读到了（内容可能为空：确认没有 crontab，或 crontab 本身是空的）
#   返回 1 → 读取失败（内容不可信；调用方必须按失败处理，绝不能当成空表）
# 判据不是"stdout 是否为空"，而是**保留 stderr 后能否看到明确文案**：
#   非零 + stderr 含 "no crontab for" → 确认没有 crontab，返回 0、内容置空；
#   其它任何非零（含 stderr 为空、以及 permission denied 这类真错误）→ 返回 1。
read_current_crontab(){
local out="$1"
local err_tmp rc
err_tmp=$(mktemp) || return 1
LC_ALL=C crontab -l > "${out}" 2> "${err_tmp}"
rc=$?
if [ "${rc}" -eq 0 ]; then
    rm -f "${err_tmp}"
    return 0
fi
if [ -s "${err_tmp}" ] && grep -qi 'no crontab for' "${err_tmp}"; then
    : > "${out}"
    rm -f "${err_tmp}"
    return 0
fi
# stderr 为空、或不是"no crontab"→ 不能断言"没有 crontab"，保守失败
: > "${out}"
rm -f "${err_tmp}"
return 1
}

# 是否已存在自动更新任务。返回 0=存在；1=确认不存在；2=**读取失败**（调用方必须单独处理 2，不能当成 1）
meme_cron_present(){
local tmp
command -v crontab > /dev/null 2>&1 || return 2
tmp=$(mktemp) || return 2
if ! read_current_crontab "${tmp}"; then
    rm -f "${tmp}"
    return 2
fi
if grep -q "meme_generator_auto_update" "${tmp}"; then
    rm -f "${tmp}"
    return 0
fi
rm -f "${tmp}"
return 1
}

# 追加一条定时任务（保留原有条目）。读取失败绝不写入 —— 否则会把用户整份 crontab 覆盖掉。
append_meme_cron(){   # $1 = 要追加的整行
local tmp current
command -v crontab > /dev/null 2>&1 || return 1
tmp=$(mktemp) || return 1
if ! read_current_crontab "${tmp}"; then
    rm -f "${tmp}"
    return 1
fi
current=$(cat "${tmp}")
rm -f "${tmp}"
if [ -n "${current}" ]; then
    if printf '%s\n%s\n' "${current}" "$1" | crontab -; then return 0; fi
    return 1
fi
if printf '%s\n' "$1" | crontab -; then return 0; fi
return 1
}

# 移除自动更新定时任务的唯一入口（卸载 / 关闭自动更新都走这里）。
# 读取失败一律不碰 crontab 并返回 1：宁可让调用方报"没清掉"，也绝不拿不可信的内容去覆盖用户整份 crontab。
# 如实返回：确认没有该任务 / 删除成功 → 0；读取失败 / crontab 不可用 / 写入失败 → 1。
remove_meme_cron(){
local tmp current filtered
command -v crontab > /dev/null 2>&1 || return 1
tmp=$(mktemp) || return 1
if ! read_current_crontab "${tmp}"; then
    rm -f "${tmp}"
    return 1
fi
current=$(cat "${tmp}")
rm -f "${tmp}"
[ -n "${current}" ] || return 0     # 确认没有 crontab → 等价于"没有该任务"

# grep 在"一行都没匹配到"时返回 1，这是预期结果，所以只兜住它自己
filtered=$(printf '%s\n' "${current}" | grep -v "meme_generator_auto_update" || true)
[ "${filtered}" = "${current}" ] && return 0     # 本来就没有该任务，不写回

# 判据只有最后写入的结果；空内容写空，别写进一个只有换行的 crontab
if [ -n "${filtered}" ]; then
    if printf '%s\n' "${filtered}" | crontab -; then return 0; fi
    return 1
fi
if printf '' | crontab -; then return 0; fi
return 1
}

setup_auto_update(){
  echo -en ${yellow}是否开启meme生成器自动更新（每天凌晨1点到6点随机自动同步并重启）? [Y/n]:${background};read yn
  case ${yn} in
  N|n)
    # 用户选择不开启自动更新：若已存在 cron 任务就删掉。读取失败必须报出来，不能静默当成"没有该任务"
    meme_cron_present
    cron_state=$?
    if [ "${cron_state}" -eq 2 ]; then
      echo -e ${red}无法读取当前 crontab，未能确认自动更新任务是否已移除，请手动执行 crontab -e 检查${background}
      # 如实返回：只打印一句错误就返回 0，调用方会以为"这次真的清干净了"
      return 1
    elif [ "${cron_state}" -eq 0 ]; then
      if remove_meme_cron; then
        echo -e ${yellow}已关闭meme生成器的自动更新${background}
      else
        echo -e ${red}移除自动更新任务失败，请手动执行 crontab -e 检查${background}
        return 1
      fi
    fi
    return 0
    ;;
  *)
    # 自动更新依赖 crontab；不存在就直接说明，不要假装设置成功
    if ! command -v crontab > /dev/null 2>&1; then
      echo -e ${red}未找到 crontab，请先安装 cron 后再开启自动更新${background}
      echo -en ${yellow}回车返回${background};read
      return 1
    fi

    # 确保脚本已保存到系统位置；保存失败就不能建 cron，否则 cron 会指向缺失/损坏的脚本
    if ! ensure_script_saved; then
      echo -e ${red}脚本保存失败，未创建自动更新任务${background}
      echo -en ${yellow}回车返回${background};read
      return 1
    fi

    # 检查是否已经存在相同的cron任务。**读取失败必须中止**：否则会把"读不到"当成"没有"，
    # 接着追加一条，而原先那种 `(crontab -l; echo 新行) | crontab -` 在读取失败时
    # 会因为 subshell 里 echo 成功而返回 0 —— 用户的整份 crontab 会被覆盖成只剩一行。
    meme_cron_present
    cron_state=$?
    if [ "${cron_state}" -eq 2 ]; then
      echo -e ${red}无法读取当前 crontab，已中止（避免覆盖你已有的定时任务）${background}
      echo -e ${yellow}请先手动执行 crontab -l 检查${background}
      echo -en ${yellow}回车返回${background};read
      return 1
    fi
    if [ "${cron_state}" -eq 1 ]; then
      # 生成随机时间：1-6点之间的随机小时，0-59分钟之间的随机分钟
      random_hour=$((1 + RANDOM % 6))
      random_minute=$((RANDOM % 60))
      if ! append_meme_cron "${random_minute} ${random_hour} * * * /bin/bash -c 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; export HOME=${HOME}; ${SCRIPT_SYSTEM_PATH} auto_update' # meme_generator_auto_update"; then
        echo -e ${red}创建自动更新任务失败${background}
        echo -en ${yellow}回车返回${background};read
        return 1
      fi
      echo -e ${green}已设置每天凌晨${random_hour}:$(printf "%02d" ${random_minute})自动更新meme生成器${background}
      echo -e ${cyan}自动更新日志位置: ${HOME}/.config/meme_generator/auto_update.log${background}
    fi
    ;;
  esac
}

toggle_auto_update(){
  # 读取失败必须中止：不能猜"现在是关闭状态"，否则会走添加分支去覆盖用户的整份 crontab
  meme_cron_present
  cron_state=$?
  if [ "${cron_state}" -eq 2 ]; then
    echo -e ${red}无法读取当前 crontab，已中止（请先手动执行 crontab -l 检查）${background}
    echo -en ${yellow}回车返回${background};read
    return 1
  fi
  if [ "${cron_state}" -eq 0 ]; then
    # 已经存在 → 删除自动更新的cron任务
    if remove_meme_cron; then
      echo -e ${yellow}已关闭meme生成器的自动更新${background}
    else
      # cron 还在却把系统脚本删掉，会留下每天执行不存在脚本的 root 任务，这里必须中止
      echo -e ${red}移除自动更新任务失败，已中止（请先手动执行 crontab -e 检查）${background}
      echo -en ${yellow}回车返回${background};read
      return 1
    fi

    # 询问是否删除相关文件
    echo -en ${cyan}是否删除系统脚本文件和日志文件? [Y/n]: ${background};read delete_files
    case ${delete_files} in
    N|n) echo -e ${yellow}保留了系统脚本文件和日志文件${background} ;;
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
    if ! command -v crontab > /dev/null 2>&1; then
      echo -e ${red}未找到 crontab，请先安装 cron 后再开启自动更新${background}
      echo -en ${yellow}回车返回${background};read
      return 1
    fi
    # 开启前必须确保系统脚本可用，否则 cron 会指向缺失/损坏的脚本
    if ! ensure_script_saved; then
      echo -e ${red}脚本保存失败，未开启自动更新${background}
      echo -en ${yellow}回车返回${background};read
      return 1
    fi
    # 生成随机时间：1-6点之间的随机小时，0-59分钟之间的随机分钟
    random_hour=$((1 + RANDOM % 6))
    random_minute=$((RANDOM % 60))
    if ! append_meme_cron "${random_minute} ${random_hour} * * * /bin/bash -c 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; export HOME=${HOME}; ${SCRIPT_SYSTEM_PATH} auto_update' # meme_generator_auto_update"; then
      echo -e ${red}创建自动更新任务失败${background}
      echo -en ${yellow}回车返回${background};read
      return 1
    fi
    echo -e ${green}已开启meme生成器的自动更新${background}
    echo -e ${cyan}将在每天凌晨${random_hour}:$(printf "%02d" ${random_minute})自动同步更新 meme GitHub 仓库并重启${background}
    echo -e ${cyan}自动更新日志位置: ${HOME}/.config/meme_generator/auto_update.log${background}
  fi
  echo -en ${yellow}回车返回${background};read
}

rewrite_config(){
    if ! is_meme_repo_installed; then
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

    # 检查是否需要先停止服务（按进程判断；HTTP 不通也可能有进程在跑）
    meme_was_running=false
    if is_meme_process_running; then
        meme_was_running=true
        echo -e ${yellow}正在停止meme生成器...${background}
        if ! stop_meme_service; then
            echo -e ${red}meme生成器停止失败，已中止重写配置（请先手动检查残留进程）${background}
            echo -en ${yellow}回车返回${background};read
            return 1
        fi
    fi

    # 备份当前配置：备份失败绝不能继续覆盖——否则旧配置连同其中的密钥会一起丢
    if [ -f "${config}" ]; then
        backup_file="${config}.backup.$(date +%Y%m%d%H%M%S)"
        if ! cp "${config}" "${backup_file}"; then
            echo -e ${red}备份原配置失败，已中止重写（现有配置未被改动）${background}
            echo -en ${yellow}回车返回${background};read
            return 1
        fi
        # 备份同样含密钥，权限按原配置收紧；收紧失败绝不能只说"已备份"——
        # 原文件若是历史遗留的 644，这里失败就等于留下一份可读的密钥副本
        if ! chmod 600 "${backup_file}"; then
            rm -f "${backup_file}"
            echo -e ${red}备份文件权限收紧失败，已删除该备份并中止重写（现有配置未被改动）${background}
            echo -en ${yellow}回车返回${background};read
            return 1
        fi
        echo -e ${green}已备份原配置文件至: ${backup_file}${background}
    fi

    # 重写配置：与初次安装共用 write_default_config（mkdir 失败即停 → temp → chmod 600 → 原子替换）
    if ! write_default_config; then
        echo -e ${red}写入默认配置失败，原配置未被改动${background}
        echo -en ${yellow}回车返回${background};read
        return 1
    fi

    echo -e ${green}配置文件已重写为默认设置${background}

    # 询问是否重启服务
    if [ "$meme_was_running" = true ]; then
        echo -en ${yellow}是否重新启动meme生成器? [Y/n]:${background};read yn
        case ${yn} in
        N|n) echo -e ${yellow}请记得手动重启meme生成器以应用新配置${background} ;;
        *)
            echo -e ${yellow}正在重启meme生成器...${background}
            start_meme_generator "重启"
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
    if ! is_meme_repo_installed; then
        echo -e ${red}您还没有安装meme生成器！${background}
        echo -en ${yellow}回车返回${background};read
        return
    fi

    echo -e ${white}"====="${green}更换GitHub代理${white}"====="${background}
    echo -e ${cyan}当前可用的GitHub代理:${background}
    echo -e ${green}1.${cyan} 无代理 \(直接访问github.com\)${background}
    echo -e ${green}2.${cyan} ghfast.top \(${GithubMirror_1:-"https://ghfast.top/"}\)${background}
    echo -e ${green}3.${cyan} gh-proxy.com \(${GithubMirror_2:-"https://gh-proxy.com/"}\)${background}
    echo -e ${green}4.${cyan} 自定义代理${background}
    echo "========================="

    echo -e ${cyan}当前主仓库远程URL:${background}
    if is_meme_repo_installed; then
        echo -n -e ${yellow}meme-generator: ${background}
        # 只读展示：用 git -C 而不是先 cd（AGENTS：每个 cd 都不能裸奔，且不该为一行展示改动工作目录）
        git -C "${install_path}/${MAIN_REPO_NAME}" remote get-url origin 2>/dev/null || echo -e ${red}未找到${background}
    fi
    echo "========================="

    echo -en ${green}请选择要使用的GitHub代理: ${background};read proxy_choice

    case ${proxy_choice} in
    1) new_proxy=""; proxy_name="无代理" ;;
    2) new_proxy="${GithubMirror_1:-"https://ghfast.top/"}"; proxy_name="ghfast.top" ;;
    3) new_proxy="${GithubMirror_2:-"https://gh-proxy.com/"}"; proxy_name="gh-proxy.com" ;;
    4)
        echo -en ${cyan}请输入自定义代理地址 \(如: https://mirror.example.com/\): ${background};read custom_proxy
        if [[ ! ${custom_proxy} =~ ^https?:// ]]; then
            echo -e ${red}代理地址格式错误，请以http://或https://开头${background}
            echo -en ${yellow}回车返回${background};read
            return
        fi
        # 统一补齐结尾的 /，否则拼接会得到 https://proxy.example.comhttps://github.com/...
        custom_proxy="${custom_proxy%/}"
        new_proxy="${custom_proxy}/"
        proxy_name="自定义代理"
        ;;
    *) echo -e ${red}选择无效${background}; echo -en ${yellow}回车返回${background};read; return ;;
    esac

    echo -e ${yellow}正在更换GitHub代理为: ${green}${proxy_name}${background}

    # 动态构建仓库列表。字段分隔符统一用 `|`：不能用 `:`，因为 URL 本身含冒号，
    # `${repo_info##*:}` 取的是最后一个冒号之后，会把 https: 吃掉，
    # 进而写出 //github.com/... 或 https://ghfast.top///github.com/... 污染 origin。
    local repo_path original_url new_url repo_info
    local success_count=0
    local total_count=0
    local repos=()
    repos=("${install_path}/${MAIN_REPO_NAME}|${MAIN_REPO_URL}")
    for repo_info in "${EXTRA_REPOS[@]}"; do
        IFS='|' read -r repo_name repo_subdir repo_url repo_branch <<< "$repo_info"
        repos+=("${install_path}/${repo_name}|${repo_url}")
    done

    for repo_info in "${repos[@]}"; do
        IFS='|' read -r repo_path original_url <<< "$repo_info"

        if [ -d "${repo_path}/.git" ]; then
            total_count=$((total_count + 1))
            echo -e ${yellow}正在更新 $(basename ${repo_path}) 的远程URL...${background}

            cd "${repo_path}" || continue
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
        # 测试连接：用 git -C 取代裸 cd（cd 失败会留在原目录，把无关仓库的测试结果当成主仓库的）
        if git -C "${install_path}/${MAIN_REPO_NAME}" ls-remote origin >/dev/null 2>&1; then
            echo -e ${green}✓ 代理连接测试成功${background}
        else
            echo -e ${red}✗ 代理连接测试失败，您可能需要尝试其他代理${background}
        fi
    else
        echo -e ${red}部分仓库的代理更换失败 \(${success_count}/${total_count}\)${background}
    fi

    echo -en ${yellow}回车返回${background};read
}

# 重新使用 pip 安装依赖
reinstall_pip_dependencies(){
    if ! is_meme_repo_installed; then
        echo -e ${red}您还没有安装meme生成器！${background}
        echo -en ${yellow}回车返回${background};read
        return
    fi

    echo -e ${white}"====="${green}重新使用pip安装依赖${white}"====="${background}
    echo -e ${yellow}此操作将重新安装meme生成器的所有Python依赖包${background}
    echo "========================="

    echo -en ${yellow}是否继续重新安装依赖包？[Y/n]: ${background};read confirm
    case ${confirm} in
    N|n) echo -e ${yellow}已取消操作${background}; echo -en ${yellow}回车返回${background};read; return ;;
    esac

    # 检查是否需要先停止服务（按进程判断；HTTP 不通也可能有进程在跑）
    meme_was_running=false
    if is_meme_process_running; then
        meme_was_running=true
        echo -e ${yellow}正在停止meme生成器...${background}
        if ! stop_meme_service; then
            echo -e ${red}meme生成器停止失败，已中止重装（请先手动检查残留进程）${background}
            echo -en ${yellow}回车返回${background};read
            return 1
        fi
        sleep 1
    fi

    cd "${install_path}/${MAIN_REPO_NAME}" || { echo -e ${red}进入安装目录失败${background}; echo -en ${yellow}回车返回${background};read; return 1; }

    # 判据一律用 venv/bin/activate：残缺的 venv（有目录没 activate）必须重建，
    # 否则后面 source 失败后会落到 root 的系统 Python/pip 上，污染系统环境
    if [ ! -f "venv/bin/activate" ]; then
        echo -e ${yellow}虚拟环境不存在或已损坏，正在重新创建...${background}
        rm -rf venv
        if ! python3 -m venv venv; then
            echo -e ${red}创建虚拟环境失败，请检查 python3-venv 是否已安装${background}
            echo -en ${yellow}回车返回${background};read
            return 1
        fi
    fi

    if ! activate_meme_venv; then
        echo -e ${red}激活虚拟环境失败，已中止（避免误用系统 Python）${background}
        echo -en ${yellow}回车返回${background};read
        return 1
    fi
    python -m pip install --upgrade pip

    echo -e ${cyan}请选择安装方式：${background}
    echo -e ${green}1.${cyan} 快速安装（推荐）${background}
    echo -e ${green}2.${cyan} 完全重装 - 先卸载再重新安装${background}
    echo -e ${green}3.${cyan} 强制重装 - 忽略已安装的包，强制重新安装${background}
    echo -en ${green}请选择[1-3]: ${background};read install_method

    # 紧跟在 pip 之后收集返回码：旧写法在 esac 之后判断 $?，容易被中间命令冲掉
    local install_rc=0
    case ${install_method} in
    2)
        python -m pip uninstall -y meme-generator 2>/dev/null
        python -m pip install . || install_rc=1
        ;;
    3)
        python -m pip install --force-reinstall . || install_rc=1
        ;;
    *)
        python -m pip install . || install_rc=1
        ;;
    esac

    if [ "${install_rc}" -eq 0 ]; then
        echo -e ${green}依赖包安装成功！${background}
    else
        echo -e ${red}依赖包安装失败！未自动启动，请修复后重试${background}
        echo -en ${yellow}回车返回${background};read
        return 1
    fi

    # 询问是否重新启动服务
    # 这里**已经安全停止过**（上面 meme_was_running 分支），所以绝不能再调 restart_meme_generator：
    # 它的入口守卫是「当前没在运行就无法重启」，而服务此刻恰好没在运行 —— 结果就是"重启"其实没启动，
    # 用户以为恢复了、服务却仍是停的。直接走 start_meme_generator。
    if [ "$meme_was_running" = true ]; then
        echo -en ${yellow}检测到之前meme生成器在运行，是否重新启动？[Y/n]: ${background};read restart_choice
        case ${restart_choice} in
        N|n) echo -e ${yellow}请记得手动启动meme生成器${background} ;;
        *) start_meme_generator "重启" ;;
        esac
    fi

    echo -en ${yellow}回车返回${background};read
}

# 开启/关闭额外meme仓库功能
toggle_extra_memes(){
    if ! is_meme_repo_installed; then
        echo -e ${red}meme生成器未安装，请先安装meme生成器!${background}
        echo -en ${yellow}回车返回${background};read
        return
    fi

    echo -e ${white}"====="${green}额外meme仓库管理${white}"====="${background}
    echo -e ${cyan}此功能可以开启或关闭额外的meme仓库${background}
    echo "========================="
    
    # 动态检测所有额外仓库的状态
    local i=1
    for repo_info in "${EXTRA_REPOS[@]}"; do
        IFS='|' read -r repo_name repo_subdir repo_url repo_branch <<< "$repo_info"
        repo_path="${install_path}/${repo_name}"
        
        status="${red}[未安装]"
        if is_extra_repo_installed "${repo_name}"; then status="${green}[已安装]"; fi
        
        enabled="${yellow}[已禁用]"
        if [ -f ${config} ]; then
            current_config=$(config_get meme meme_dirs "${config}")
            if echo "${current_config}" | grep -q "${repo_name}/${repo_subdir}"; then
                enabled="${green}[已启用]"
            fi
        fi
        
        echo -e "${green}${i}. ${repo_name} ${status} ${enabled}${background}"
        ((i++))
    done

    echo -e "${green}${i}. 全部启用${background}"
    echo -e "${green}$((i+1)). 全部禁用${background}"
    echo -e "${green}0. 返回${background}"
    echo "========================="
    echo -en "${green}请选择要操作的选项: ${background}";read choice
    
    if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
        echo -e ${red}输入错误${background}; echo -en ${yellow}回车返回${background};read; return
    fi
    
    if [ "$choice" -eq 0 ]; then
        return
    elif [ "$choice" -eq "$i" ]; then
        enable_all_repos
    elif [ "$choice" -eq "$((i+1))" ]; then
        disable_all_repos
    elif [ "$choice" -ge 1 ] && [ "$choice" -lt "$i" ]; then
        local idx=$((choice-1))
        local repo_info="${EXTRA_REPOS[$idx]}"
        IFS='|' read -r repo_name repo_subdir repo_url repo_branch <<< "$repo_info"
        toggle_single_repo "$repo_name" "$repo_subdir" "$repo_url" "${repo_branch:-main}"
    else
        echo -e ${red}输入错误${background}
        echo -en ${yellow}回车返回${background};read
    fi
}

# 切换单个仓库的启用状态
toggle_single_repo(){
    local repo_name="$1"
    local repo_subdir="$2"
    local repo_url="$3"
    local repo_branch="${4:-main}"
    local repo_path="${install_path}/${repo_name}"
    local current_dirs repo_dir_path new_dirs restart_choice

    # 如果仓库未安装，先安装（用 .git 判断，失败克隆留下的空目录不算「已安装」）
    if ! is_extra_repo_installed "${repo_name}"; then
        echo -e ${yellow}检测到 ${repo_name} 未安装，正在安装...${background}
        if git_clone "${repo_url}" "${repo_path}" "/dev/null"; then
            echo -e ${green}${repo_name} 安装成功！${background}
        else
            echo -e ${red}${repo_name} 安装失败！${background}
            echo -en ${yellow}回车返回${background};read
            return 1
        fi
    fi

    # 克隆成功 ≠ 表情包目录存在：子目录缺失时写进配置会让 meme-generator 加载报错
    if [ ! -d "${repo_path}/${repo_subdir}" ]; then
        echo -e ${red}${repo_name} 的表情包目录不存在: ${repo_path}/${repo_subdir}${background}
        echo -e ${yellow}仓库可能不完整，已跳过启用${background}
        echo -en ${yellow}回车返回${background};read
        return 1
    fi

    if [ ! -f ${config} ]; then
        echo -e ${red}配置文件不存在，请先安装meme生成器!${background}
        echo -en ${yellow}回车返回${background};read
        return 1
    fi

    current_dirs=$(meme_dirs_value)
    repo_dir_path="${install_path}/${repo_name}/${repo_subdir}"

    # 检查是否已启用
    if echo "${current_dirs}" | grep -q "${repo_dir_path}"; then
        # 已启用，执行禁用操作
        echo -e ${yellow}正在禁用 ${repo_name}...${background}
        new_dirs=$(remove_dir_from_list "${current_dirs}" "${repo_dir_path}")
        if ! config_set meme meme_dirs "[${new_dirs}]" "${config}"; then
            echo -e ${red}写入配置失败，请检查配置文件权限${background}
            echo -en ${yellow}回车返回${background};read
            return 1
        fi
        echo -e ${green}${repo_name} 已禁用${background}
    else
        # 未启用，执行启用操作
        echo -e ${yellow}正在启用 ${repo_name}...${background}
        if [ -z "${current_dirs}" ] || [ "${current_dirs}" = " " ]; then
            new_dirs="\"${repo_dir_path}\""
        else
            new_dirs="${current_dirs}, \"${repo_dir_path}\""
        fi
        if ! config_set meme meme_dirs "[${new_dirs}]" "${config}"; then
            echo -e ${red}写入配置失败，请检查配置文件权限${background}
            echo -en ${yellow}回车返回${background};read
            return 1
        fi
        echo -e ${green}${repo_name} 已启用${background}
    fi

    if is_meme_process_running; then
        echo -en ${yellow}是否重启meme生成器以应用更改？[Y/n]: ${background};read restart_choice
        case ${restart_choice} in
        N|n) echo -e ${yellow}请记得手动重启meme生成器以应用更改${background} ;;
        *) restart_meme_generator ;;
        esac
    fi

    echo -en ${yellow}回车返回${background};read
}

# 启用所有仓库
enable_all_repos(){
    echo -e ${yellow}正在启用所有额外meme仓库...${background}

    local repo_info repo_name repo_subdir repo_url repo_branch repo_path
    local meme_dirs_str restart_choice
    local ready_count=0
    local missing_count=0

    for repo_info in "${EXTRA_REPOS[@]}"; do
        IFS='|' read -r repo_name repo_subdir repo_url repo_branch <<< "$repo_info"
        repo_path="${install_path}/${repo_name}"

        if ! is_extra_repo_installed "${repo_name}"; then
            echo -e ${yellow}正在安装 ${repo_name}...${background}
            if git_clone "${repo_url}" "${repo_path}" "/dev/null"; then
                echo -e ${green}${repo_name} 安装成功！${background}
            else
                echo -e ${red}${repo_name} 安装失败，不会写入配置${background}
            fi
        fi

        # 只统计「仓库 + 表情包子目录」都真实存在的仓库
        if [ -d "${repo_path}/${repo_subdir}" ]; then
            ready_count=$((ready_count + 1))
        else
            missing_count=$((missing_count + 1))
        fi
    done

    if [ ! -f ${config} ]; then
        echo -e ${red}配置文件不存在，请先安装meme生成器!${background}
        echo -en ${yellow}回车返回${background};read
        return 1
    fi

    # 只写入本地真实存在（含表情包子目录）的仓库路径。
    # 旧实现用 get_default_meme_dirs 会无条件写入全部 6 个路径，
    # 克隆部分失败时就把不存在的路径写进配置，meme-generator 加载即报错。
    meme_dirs_str=$(get_installed_meme_dirs)
    if ! config_set meme meme_dirs "${meme_dirs_str}" "${config}"; then
        echo -e ${red}写入配置失败，请检查配置文件权限${background}
        echo -en ${yellow}回车返回${background};read
        return 1
    fi

    if [ "${missing_count}" -eq 0 ]; then
        echo -e ${green}所有额外meme仓库已启用！${background}
    else
        echo -e ${yellow}已启用可用的 ${ready_count} 个仓库；${missing_count} 个未安装或不完整，未写入配置${background}
    fi

    if is_meme_process_running; then
        echo -en ${yellow}是否重启meme生成器以应用更改？[Y/n]: ${background};read restart_choice
        case ${restart_choice} in
        N|n) echo -e ${yellow}请记得手动重启meme生成器以应用更改${background} ;;
        *) restart_meme_generator ;;
        esac
    fi

    echo -en ${yellow}回车返回${background};read
}

# 禁用所有仓库
disable_all_repos(){
    echo -e ${yellow}正在禁用所有额外meme仓库...${background}

    local restart_choice
    if [ ! -f ${config} ]; then
        echo -e ${red}配置文件不存在，请先安装meme生成器!${background}
        echo -en ${yellow}回车返回${background};read
        return 1
    fi

    if ! config_set meme meme_dirs "[]" "${config}"; then
        echo -e ${red}写入配置失败，请检查配置文件权限${background}
        echo -en ${yellow}回车返回${background};read
        return 1
    fi
    echo -e ${green}所有额外meme仓库已禁用！${background}
    echo -e ${cyan}注意：仓库文件仍保留在系统中，仅禁用了加载${background}

    if is_meme_process_running; then
        echo -en ${yellow}是否重启meme生成器以应用更改？[Y/n]: ${background};read restart_choice
        case ${restart_choice} in
        N|n) echo -e ${yellow}请记得手动重启meme生成器以应用更改${background} ;;
        *) restart_meme_generator ;;
        esac
    fi

    echo -en ${yellow}回车返回${background};read
}

# 配置百度翻译API
configure_baidu_translate(){
    local choice new_appid new_apikey current_appid current_apikey
    local restart_choice response error_code test_text timestamp salt sign

    if ! is_meme_repo_installed; then
        echo -e ${red}meme生成器未安装，请先安装meme生成器!${background}; echo -en ${yellow}回车返回${background};read; return
    fi
    if [ ! -f ${config} ]; then
        echo -e ${red}配置文件不存在!${background}; echo -en ${yellow}回车返回${background};read; return
    fi

    echo -e ${white}"====="${green}配置百度翻译API${white}"====="${background}
    echo -e ${cyan}百度翻译API用于某些表情包的文字翻译功能${background}
    echo -e ${cyan}例如: dianzhongdian 表情包需要使用百度翻译${background}
    echo "========================="

    # 读取当前配置
    current_appid=$(config_get translate baidu_trans_appid "${config}")
    current_apikey=$(config_get translate baidu_trans_apikey "${config}")

    if [ -n "$current_appid" ] && [ "$current_appid" != "" ]; then echo -e ${yellow}当前已配置的APP ID: ${green}${current_appid}${background}
    else echo -e ${yellow}当前APP ID: ${red}未配置${background}; fi

    if [ -n "$current_apikey" ] && [ "$current_apikey" != "" ]; then echo -e ${yellow}当前已配置的API Key: ${green}${current_apikey:0:8}...${background}
    else echo -e ${yellow}当前API Key: ${red}未配置${background}; fi

    echo "========================="
    echo -e ${cyan}获取百度翻译API:${background}
    echo -e ${cyan}1. 访问: ${white}https://api.fanyi.baidu.com${background}
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
        echo -e ${yellow}请输入百度翻译APP ID:${background}; read -rp "APP ID: " new_appid
        if [ -z "$new_appid" ]; then echo -e ${red}APP ID不能为空！${background}; echo -en ${yellow}回车返回${background};read; return; fi
        if [[ ! ${new_appid} =~ ^[A-Za-z0-9]+$ ]]; then echo -e ${red}APP ID 只应包含字母和数字，请检查后重试${background}; echo -en ${yellow}回车返回${background};read; return; fi

        # 密钥输入不回显，避免明文留在终端与日志里
        echo -e ${yellow}请输入百度翻译API Key \(密钥\):${background}; read -rsp "API Key: " new_apikey; echo
        if [ -z "$new_apikey" ]; then echo -e ${red}API Key不能为空！${background}; echo -en ${yellow}回车返回${background};read; return; fi
        if [[ ! ${new_apikey} =~ ^[A-Za-z0-9]+$ ]]; then echo -e ${red}API Key 只应包含字母和数字，请检查后重试${background}; echo -en ${yellow}回车返回${background};read; return; fi

        # 写 TOML 字符串值：config_set_string 负责加引号并转义 \ 与 "，
        # 因此值里出现 / & \ | " 都不会破坏配置
        if ! config_set_string translate baidu_trans_appid "${new_appid}" "${config}" \
           || ! config_set_string translate baidu_trans_apikey "${new_apikey}" "${config}"; then
            echo -e ${red}写入配置文件失败，请检查配置文件权限${background}
            echo -en ${yellow}回车返回${background};read
            return 1
        fi
        chmod 600 ${config} || echo -e ${yellow}提示: 收紧配置文件权限失败，请手动执行 chmod 600 ${config}${background}
        echo -e ${green}✓ 百度翻译API配置成功！${background}
        echo -e ${cyan}APP ID: ${new_appid}${background}
        echo -e ${cyan}API Key: ${new_apikey:0:8}...${background}
        ;;
    2)
        if ! config_set_string translate baidu_trans_appid "" "${config}" \
           || ! config_set_string translate baidu_trans_apikey "" "${config}"; then
            echo -e ${red}写入配置文件失败，请检查配置文件权限${background}
            echo -en ${yellow}回车返回${background};read
            return 1
        fi
        chmod 600 ${config} || echo -e ${yellow}提示: 收紧配置文件权限失败，请手动执行 chmod 600 ${config}${background}
        echo -e ${green}✓ 百度翻译API配置已清除${background}
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

        # 走 HTTPS 并带超时
        response=$(curl -s ${CURL_CONNECT_TIMEOUT} ${CURL_MAX_TIME} "https://api.fanyi.baidu.com/api/trans/vip/translate?q=${test_text}&from=en&to=zh&appid=${current_appid}&salt=${salt}&sign=${sign}")

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
    0) return ;;
    esac

    if is_meme_process_running; then
        echo -en ${yellow}是否重启meme生成器以应用更改？[Y/n]: ${background};read restart_choice
        case ${restart_choice} in
        N|n) ;;
        *) restart_meme_generator ;;
        esac
    fi
    echo -en ${yellow}回车返回${background};read
}

main(){
# 如果是首次通过curl执行，确保先保存脚本到系统目录
# 一个会话内只试一次：用户在 toggle 关闭自动更新后会把系统脚本删掉，这里每屏重绘都会
# 再 download_script 下回来，造成数秒空档——空档里用户多按的回车会被下面的 read number
# 吃成空输入，落到 *) 输入错误（现已改 return，不再退出但会多刷一屏）。标记置位后本次会话不再重复下载，
# 系统脚本存不存在都不影响本次从内存运行（注释本就是「失败只提示，不影响本次使用」）
if [[ "$0" == *"/dev/fd/"* || "$0" == "bash" ]] && [ "${SCRIPT_SAVE_TRIED:-0}" != "1" ]; then
  SCRIPT_SAVE_TRIED=1
  # 首次执行先把自己保存到系统目录；失败只提示，不影响本次使用（cron 创建路径另有严格检查）
  if ! ensure_script_saved; then
    echo -e ${yellow}系统脚本暂未保存成功，自动更新功能需稍后重试${background}
  fi
fi

# 状态显示也走统一读取层：读取失败与"确实没有该任务"要分开显示，别把读不到说成「未启动」
meme_cron_present
cron_state=$?
case "${cron_state}" in
0) auto_update_condition="${green}[运行中]" ;;
2) auto_update_condition="${yellow}[无法读取 crontab]" ;;
*) auto_update_condition="${red}[未启动]" ;;
esac

local Port="" ShowHost="" IsWildcardHost=0
# 三态：别把「修复模式的半成品」显示成「未启动」——那会误导用户去点启动，而启动必然失败
if is_meme_install_complete; then
    Port=$(meme_port)
    # 状态按进程判断：HTTP 不通但进程还在（死锁/端口改错）时不该显示「未启动」
    if is_meme_process_running; then condition="${green}[运行中]"; else condition="${red}[未启动]"; fi
elif is_meme_repo_installed; then
    condition="${yellow}[安装未完成]"
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
echo -e  ${green} 7.  ${cyan}管理额外meme仓库${background}
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
    ShowHost=$(meme_host)
    # 0.0.0.0 是监听通配地址，不能当作客户端访问地址展示；用 127.0.0.1 提示本机访问
    if [ -z "${ShowHost}" ] || [ "${ShowHost}" = "0.0.0.0" ]; then ShowHost="127.0.0.1"; IsWildcardHost=1; fi
    echo -e ${green}MEME api: ${cyan}http://${ShowHost}:${Port}${background}
    # 只有通配监听时对外才有公网访问地址；这里只读本地缓存（后台任务负责写入），不发任何网络请求
    if [ "${IsWildcardHost}" = "1" ] && load_public_ip_cache; then
        echo -e ${green}MEME 公网: ${cyan}http://${PUBLIC_IP}:${Port}${background}
    fi
fi
echo -e ${green}QQ群:${cyan}呆毛版-QQ群:1022982073${background}
echo "========================="
echo
echo -en ${green}请输入您的选项: ${background};read number
case ${number} in
1) echo; install_meme_generator ;;
2) echo; start_meme_generator ;;
3) echo; stop_meme_generator ;;
4) echo; restart_meme_generator ;;
5) echo; update_meme_generator ;;
6) echo; uninstall_meme_generator ;;
7) echo; toggle_extra_memes ;;
8) log_meme_generator ;;
9) echo; toggle_auto_update ;;
10) echo; view_auto_update_log ;;
11) echo; change_port ;;
12) echo; rewrite_config ;;
13) echo; change_github_proxy ;;
14) echo; reinstall_pip_dependencies ;;
15) echo; configure_baidu_translate ;;
0) exit ;;
*) echo; echo -e ${red}输入错误${background}; return ;;
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
  exit $?
else
  # 交互入口补一次公网 IP：缓存有效就零网络请求；缺失/过期才后台获取（绝不阻塞菜单）
  init_public_ip
  mainbak
fi
