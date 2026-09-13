#!/usr/bin/env bash
# 回归测试：Manage/meme_generator.sh
#
#   bash tests/meme_generator/run.sh                      # 默认：A~F + H 断言（**跳过 G 组真实 git 测试**）
#   bash tests/meme_generator/run.sh --only A,B           # 只跑指定分组（排障 / 日常最常用）
#   bash tests/meme_generator/run.sh --log /tmp/x.log     # 指定进度日志（默认自动生成）
#   bash tests/meme_generator/run.sh --with-git           # 只有确实改了 git_clone / git_update 时才用
#
# ⚠️ **本仓库的测试范围已收窄**（2026-09-13，用户决定，见 AGENTS.md「验证方式」）：
#   - **不再跑 G 组**（真实 git 行为：造裸仓库 + 多次 push + force-push）。默认已跳过，要跑得显式 `--with-git`。
#     G 组因此处于**未维护**状态：下面的断言还在，但不再随日常回归执行。
#   - **不再跑变异验证**（`--mutate`：本机 ≈4 分钟/条 × 14 条 ≈ 1 小时）。参数保留（代码没删），但**不要跑**。
#   日常改动只需要：`bash tests/meme_generator/run.sh`，或按改动范围 `--only <涉及的组>`。
#
# 约定（见 AGENTS.md「验证方式」）：
#   - 从被测脚本**按内容**抽取函数，不硬编码行号（脚本会持续插入函数）；
#   - 只依赖 bash + 系统已有工具，不引入测试框架 / 第三方依赖；
#   - 变异验证已停用，所以**新断言必须另外拿一个反例自证**：手工改坏对应那处生产代码 → 跑一次看到它变红
#     → 再改回来（或加一条 `--only` 的临时用例）。别只写"看起来对"的断言。
#
# 「不会卡住」的三条硬保证（都踩过坑）：
#   1) harness 里执行 `exec 0</dev/null`：任何漏写重定向的 `read` 都立刻拿到 EOF，
#      不会因为 stdin 是没关闭的管道而永久阻塞；
#   2) 每次 harness 运行都套 `timeout`（HARNESS_TIMEOUT，默认 300s），死循环不会拖死整个套件；
#      本机没有可用的 `timeout` 时**直接失败退出**，不悄悄退化成"无限运行"；
#   3) 每条断言都即时追加到 `--log` 指定的文件（追加写 = 不缓冲），
#      即使进程被外部杀掉，也能从日志看出卡在哪一步。
set -o pipefail

RUN_GIT=0     # 默认跳过 G 组（真实 git 行为）。2026-09-13 用户决定不再日常跑 G：要跑加 --with-git
ONLY=""
DO_MUTATE=0
LOG=""
while [ $# -gt 0 ]; do
  case "$1" in
  --fast) RUN_GIT=0 ;;          # 兼容旧写法；现在与默认等价
  --with-git) RUN_GIT=1 ;;      # 显式开启 G 组（只在真的改了 git_clone / git_update 时用）
  --mutate) DO_MUTATE=1 ;;
  --only) ONLY="$2"; shift ;;
  --only=*) ONLY="${1#--only=}" ;;
  --log) LOG="$2"; shift ;;
  --log=*) LOG="${1#--log=}" ;;
  -h | --help) sed -n '2,/^set -o pipefail/p' "$0" | sed '$d'; exit 0 ;;
  *) echo "未知参数: $1（见 --help）"; exit 2 ;;
  esac
  shift
done

SCRIPT_DIR="${0%/*}"
[ "${SCRIPT_DIR}" = "${0}" ] && SCRIPT_DIR="."
SCRIPT_DIR=$(cd "${SCRIPT_DIR}" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd)
TARGET="${REPO_ROOT}/Manage/meme_generator.sh"
[ -f "${TARGET}" ] || { echo "找不到被测脚本: ${TARGET}"; exit 2; }

# 默认 300s：慢盘/模拟文件系统（例如 Windows 上经 MSYS 跑，一次进程创建可达数百毫秒）
# 会显著变慢，但仍必须是**有限**上限——死循环绝不能拖死整个套件。可用 HARNESS_TIMEOUT 覆盖。
HARNESS_TIMEOUT="${HARNESS_TIMEOUT:-300}"

# timeout 是硬前提：没有它就没有有界执行，"绝不拖死"这条保证直接失效。
# 所以**缺了就直接失败退出**，而不是悄悄退化成"无限运行"。
if ! command -v timeout > /dev/null 2>&1; then
  echo "缺少 timeout（coreutils），无法保证测试有界执行；请安装 coreutils 或换一台机器跑"
  exit 2
fi
# 能力探测：只确认命令存在还不够，非 GNU/coreutils 的 timeout 语义可能不同
# 能力探测必须**真的超时一次**：只跑 `timeout 1 true` 只能证明"有个叫 timeout 的程序能跑通 true"，
# 不能证明它真的会在超时时终止子进程并按约定返回状态——而"有界"恰恰靠的就是这一点。
timeout 1 sh -c 'sleep 5' > /dev/null 2>&1
probe_rc=$?
if [ "${probe_rc}" -ne 124 ]; then
  echo "timeout 能力探测失败（期望超时返回 124，实得 ${probe_rc}），无法保证测试有界执行"
  exit 2
fi

# ⚠️ Windows/MSYS 上 TMPDIR 常常是 `C:\Users\...\Temp` 这种 **Windows 形式**。
# 宿主（WorkBuddy）会把 `rm` 包装成一个走"移到回收站"的函数，而它在 Windows 形式的路径上
# CanonicalizePath 会失败，并且是 **fail-closed —— 文件根本没有被删掉**（stderr 里是
# `[safe-delete][SAFE_DELETE_FAIL_CLOSED] ... "reason":"trash-failed"`）。
# 后果：harness 里所有 `rm -f` 静默失效（`reset_pid_file` 删不掉身份文件、`cleanup` 删不掉 WORK），
# A2「无身份时报运行中」/ B1「venv 失败前已写身份文件」/ B2「取不到 boot_id 却登记成功」会连着变红 ——
# 这三条看起来都像生产 bug，实际是环境把删除吞了。
# 所以先把 TMPDIR 归一到 POSIX 形式（`/c/Users/...`），让 rm 真正生效。实测：`/tmp` 与 `/c/...` 均正常，
# 只有 `C:\...` 形式会失败。
if command -v cygpath > /dev/null 2>&1; then
  case "${TMPDIR:-}" in
  [A-Za-z]:[\\/]*) TMPDIR=$(cygpath -u "${TMPDIR}") ;;
  esac
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/meme_regress.XXXXXX") || { echo "无法创建临时目录"; exit 2; }

# 进度日志**故意放在 WORK 之外**：WORK 会在 EXIT trap 里被整个删掉，
# 而文档承诺"被外部杀掉也能看出停在哪一步"——日志不能跟着一起消失。
# 规则：显式 --log 用用户给的（永不删）；默认日志失败时保留、成功时删。
LOG_IS_DEFAULT=0
if [ -z "${LOG}" ]; then
  LOG="${TMPDIR:-/tmp}/meme_generator_test.$$.log"
  LOG_IS_DEFAULT=1
fi
if ! : > "${LOG}" 2>/dev/null; then
  echo "进度日志不可写: ${LOG}（用 --log 指定一个可写路径）"
  exit 2
fi

cleanup() {
  local rc=$?
  if [ "${LOG_IS_DEFAULT}" = "1" ] && [ "${rc}" -eq 0 ]; then
    rm -f "${LOG}"          # 成功才删默认日志；失败/超时/被杀一律保留现场
  else
    echo "[进度日志] ${LOG}"
  fi
  if [ "${KEEP_WORK:-0}" = "1" ]; then
    echo "[保留工作目录] ${WORK}"
  else
    rm -rf "${WORK}"
  fi
  return "${rc}"
}
trap cleanup EXIT

# 有界执行：timeout 已在上面确认可用；顺带把 stdin 也钉死，双保险
bounded() {   # $1 = 秒数；其余为命令
  local secs="$1"
  shift
  timeout "${secs}" "$@" < /dev/null
}

# ============================================================
# 1) 抽取：只保留「前置变量 + 全部函数」
#    顶层守卫遇到非 Linux 会 exit、末尾 mainbak 会死循环，都不能 source；
#    平台守卫与 ipinfo 探测块按内容定位后丢掉（镜像变量改由测试注入"直连"值）。
# ============================================================
extract_lib() {   # $1 = 源脚本（可以是变异副本）
  awk '
    BEGIN { mode = "head" }
    mode == "head" {
      if ($0 ~ /^cd .*exit 1$/) { mode = "guard"; next }
      if (NR > 1) print                      # 丢掉原 shebang
      next
    }
    mode == "guard" {
      if ($0 ~ /^CURL_CONNECT_TIMEOUT=/) { mode = "body"; print }
      next
    }
    mode == "body" {
      if ($0 ~ /^URL=/) { mode = "probe"; next }
      if ($0 ~ /^function mainbak/) exit
      print
      next
    }
    mode == "probe" {
      if ($0 ~ /^config=/) {
        print "GitMirror=\"github.com\""
        print "GithubMirror_1=\"\""
        print "GithubMirror_2=\"\""
        mode = "body2"
        print
      }
      next
    }
    mode == "body2" {
      if ($0 ~ /^function mainbak/) exit
      print
    }
  ' "$1" | tr -d '\r'
}

# Foreground_Start 是嵌在 start_meme_generator 里的嵌套定义，主菜单外调不到，单独抽出来。
# 函数体内各行都缩进、闭合 `}` 在行首——按这个规则切比数花括号可靠（体内满是 ${} 展开）。
extract_foreground_start() {   # $1 = 源脚本
  awk '
    /^Foreground_Start\(\)\{$/ { f = 1 }
    f { print; if ($0 == "}") exit }
  ' "$1" | tr -d '\r'
}

# ============================================================
# 2) harness 组件：预置 → 被测库 → 函数桩 → 抽取的 Foreground_Start → 断言
# ============================================================
cat > "${WORK}/prelude.sh" <<PRELUDE
# ---- 测试预置：HOME 指向临时目录，被测脚本的路径变量随之全部落在临时目录内 ----
export HOME="${WORK}/home"
export WORK_DIR="${WORK}"
export PIP_SHOW_RC_FILE="${WORK}/pip_show_rc"
export RUN_GIT="${RUN_GIT}"
# 注意：本 heredoc **未加引号**（本来就需要 WORK / ONLY / LOG 这些变量在这里展开），
#   所以正文里的反引号与美元花括号都会被求值：反引号是**命令替换，会真的执行**
#   （踩过：注释里写一对反引号包住的赋值，bash 就去跑 groups，报 "No such file or directory"，
#   并把注释文字替换成空）；美元花括号同理会被展开掉。要写字面量必须转义。
# ONLY / LOG_FILE 必须允许**运行时**覆盖：变异运行会用 ONLY=... LOG_FILE= 精确限定范围。
# 所以这里只能"没设置时才填默认值"，判断"是否设置过"必须用 \${VAR+x} 的形式——
# 不能用 \${VAR:-...}：变异**故意**传空 LOG_FILE，而 :- 会把空串也当成"没设置"，于是又写回主日志。
if [ -z "\${ONLY+x}" ]; then ONLY="${ONLY}"; fi
if [ -z "\${LOG_FILE+x}" ]; then LOG_FILE="${LOG}"; fi
export ONLY LOG_FILE
export REPO_ROOT="${REPO_ROOT}"
export TARGET_SCRIPT="${TARGET}"
mkdir -p "\${HOME}"
PRELUDE

cat > "${WORK}/stubs.sh" <<'STUBS'

# ---- 函数桩（source 之后定义，覆盖生产实现）----
# 原则：凡是生产函数会碰**系统级资源**（进程、tmux socket、cron、网络、系统目录）的，都必须显式 stub。
# 仅把 HOME 指到临时目录**不等于隔离**——tmux socket 名与 /tmp/tmux-<uid>/<name> 都不受 HOME 影响，
# 不 stub 就可能把开发机上真正在跑的那个 meme 服务停掉。
proc_boot_id(){ echo "FAKE-BOOT"; }
proc_starttime(){ echo "FAKE-START"; }
meme_pid(){ :; }                  # 不查真实 python 进程
meme_curl(){ return 1; }          # 不访问本机端口（否则"碰巧有服务在监听"会改变行为）
tmux(){ return 0; }               # 兜底：任何 tmux 调用都不落到真实 tmux
tmux_ls(){ return 1; }
tmux_new(){ return 0; }
tmux_kill_session(){ return 0; }  # 关键：stop_meme_service 会调它；绝不能碰真实 tmux server

# ---- 全局"系统路径"钉死（安全兜底，别删）----
# 生产的默认值是 /usr/local/bin/meme_generator.sh，是**真实系统目录**。
# 任何一条用例只要不小心走到 ensure_script_saved / setup_auto_update / toggle_auto_update，
# 就会往真实机器上写文件（下载并原子替换系统脚本）。这里统一钉到本次运行的临时目录，
# 让"不会在你本地装东西"成为**结构性**保证，而不是"碰巧没跑到那一步"。
SCRIPT_SYSTEM_PATH="${WORK_DIR}/sys_meme_generator.sh"

# ---- 系统路径写入的 fail-closed 保险（别删）----
# 目标：即使 production 将来真的越过"pip 失败点"走到字体安装，也要**先被拦住**，而不是先写坏开发机。
# 这两个 wrapper 只在命中 /usr/share/fonts 时拦截（返回 97 + 显著 stderr），其余参数原样透传。
# 用 `command` 绕开函数自身，避免递归。
mkdir(){
  local a
  for a in "$@"; do
    case "${a}" in
    /usr/share/fonts | /usr/share/fonts/*)
      echo "BLOCKED_SYSTEM_WRITE:/usr/share/fonts" >&2
      return 97
      ;;
    esac
  done
  command mkdir "$@"
}
cp(){
  local a
  for a in "$@"; do
    case "${a}" in
    /usr/share/fonts | /usr/share/fonts/*)
      echo "BLOCKED_SYSTEM_WRITE:/usr/share/fonts" >&2
      return 97
      ;;
    esac
  done
  command cp "$@"
}
fc-cache(){ return 0; }   # 绝不刷新真实字体缓存
STUBS

cat > "${WORK}/tests.sh" <<'TESTS'

# ---------- 不阻塞保证 + 进度日志 ----------
exec 0< /dev/null          # 任何漏写重定向的 read 都立刻 EOF，绝不因 stdin 永久阻塞
log(){ [ -n "${LOG_FILE}" ] && printf '%s\n' "$1" >> "${LOG_FILE}"; return 0; }

PASS=0; FAIL=0; SKIP=0
ok(){   echo "  ok     - $1"; log "  ok     - $1"; PASS=$((PASS + 1)); }
no(){   echo "  NOT OK - $1"; log "  NOT OK - $1"; FAIL=$((FAIL + 1)); }
skip(){ echo "  SKIP   - $1"; log "  SKIP   - $1"; SKIP=$((SKIP + 1)); }
head_(){ echo "$1"; log "$1"; }
done_(){ echo; echo "TOTAL: pass=${PASS} fail=${FAIL} skip=${SKIP}"; log "TOTAL: pass=${PASS} fail=${FAIL} skip=${SKIP}"; }

# 分组开关：ONLY 为空=全跑；否则只跑列出的组（排障时把范围切小）
group_on(){ [ -z "${ONLY}" ] && return 0; case ",${ONLY}," in *",${1},"*) return 0 ;; esac; return 1; }

reset_pid_file(){ rm -f "${FOREGROUND_PID_FILE}"; }

# 假装的"已安装"现场：.git + venv/bin/activate + venv/bin/python（pip show 桩）+ config。
# C 组和 D 组都要用，必须各自建立——单独跑 `--only D` 时 C 组不会执行，
# 少了 .git 会让 rewrite_config 在第一道守卫就 return（表现为"莫名跳过"）。
fixture_fake_install(){
  mkdir -p "${install_path}/${MAIN_REPO_NAME}/.git" "${install_path}/${MAIN_REPO_NAME}/venv/bin"
  : > "${install_path}/${MAIN_REPO_NAME}/venv/bin/activate"
  mkdir -p "${config%/*}"; : > "${config}"
  cat > "${install_path}/${MAIN_REPO_NAME}/venv/bin/python" <<'PYSTUB'
#!/bin/sh
# 由外部文件控制 pip show 的成败，避免每个用例都重写桩
exit "$(cat "${PIP_SHOW_RC_FILE}" 2>/dev/null || echo 0)"
PYSTUB
  chmod +x "${install_path}/${MAIN_REPO_NAME}/venv/bin/python"
}

# Windows 上 git.exe 不认 /tmp/... 、/e/... 形式的 POSIX 路径，交给 git 前统一 cygpath -m 转成 C:/...
gp(){ if command -v cygpath > /dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

log "==== harness 启动：ONLY='${ONLY}' RUN_GIT='${RUN_GIT}' ===="

# ---------- 前置自检 ----------
# 抽取出错时，「函数不存在」会被 `if <函数>` 当成「未运行/未完成」而**假绿**。
MISSING=""
for f in is_meme_process_running is_meme_install_complete install_meme_generator \
         start_meme_generator stop_meme_service write_default_config rewrite_config \
         register_foreground_watchdog Foreground_Start git_update git_clone \
         foreground_pid_alive is_meme_repo_installed \
         read_current_crontab meme_cron_present append_meme_cron remove_meme_cron \
         toggle_auto_update setup_auto_update download_script ensure_script_saved \
         is_valid_ipv4 load_public_ip_cache refresh_public_ip_bg init_public_ip; do
  declare -f "${f}" > /dev/null || MISSING="${MISSING} ${f}"
done
for v in install_path config FOREGROUND_PID_FILE FOREGROUND_STOP_FLAG MAIN_REPO_NAME PUBLIC_IP_CACHE PUBLIC_IP_TTL; do
  eval "val=\${${v}:-}"
  [ -n "${val}" ] || MISSING="${MISSING} \$${v}"
done
if [ -n "${MISSING}" ]; then
  no "harness 自检失败，抽取不到以下函数/变量:${MISSING}"
  done_
  exit 1
fi

# ---------- 隔离前置条件（fail-closed）----------
# 生产脚本的 config / install_path / PID 文件全部以 $HOME 为根；HOME 没被重定向就可能写进真实家目录。
# 所以这里**拒绝在未重定向的环境下运行**，而不是"假定已经隔离好了"。
case "${HOME}" in
*"/meme_regress."* | *"/meme_regress_"*) ;;
*)
  no "HOME 未重定向到临时目录（HOME=${HOME}），为避免在你本机产生写入，拒绝运行"
  done_
  exit 2
  ;;
esac

# ---------- A 运行判据 ----------
if group_on A; then
  head_ "A) is_meme_process_running：前台 watchdog 活着、无 python、无 tmux 时必须算「运行中」"
  mkdir -p "${HOME}/.config/meme_generator"
  printf '%s\n' "$$" "FAKE-BOOT" "FAKE-START" > "${FOREGROUND_PID_FILE}"
  if is_meme_process_running; then
    ok "sleep 2 间隙不再被误判为「未运行」"
  else
    no "sleep 2 间隙被误判为「未运行」"
  fi
  reset_pid_file
  if is_meme_process_running; then
    no "无任何身份/进程时仍报「运行中」（恒真）"
  else
    ok "无身份、无进程时报「未运行」"
  fi
fi

# ---------- B 前台身份的生命周期 ----------
if group_on B; then
  head_ "B1) activate_meme_venv 失败时，Foreground_Start 不得已登记身份"
  mkdir -p "${install_path}/${MAIN_REPO_NAME}"
  reset_pid_file
  rm -f "${WORK_DIR}/venv_call_marker"
  # 关键：不能用「跑完后 [ ! -f PID ]」判断——子 Shell 退出时 EXIT trap 会把文件删掉、把 bug 掩盖掉。
  # 改成在 venv 桩里检查「此刻身份文件是否已存在」，才真正测到登记时机。
  out=$( { activate_meme_venv(){ if [ -f "${FOREGROUND_PID_FILE}" ]; then echo present > "${WORK_DIR}/venv_call_marker"; fi; return 1; }; Foreground_Start; } 2>&1 </dev/null )
  rc=$?
  if [ ! -f "${WORK_DIR}/venv_call_marker" ]; then
    ok "venv 激活失败时尚未写入身份文件（登记顺序正确）"
  else
    no "venv 激活失败前就已写入身份文件"
  fi
  if [ "${rc}" -ne 0 ]; then ok "Foreground_Start 如实返回非零"; else no "Foreground_Start 返回 0"; fi

  head_ "B2) register_foreground_watchdog：取不到 boot_id 时必须失败且不落地身份文件"
  reset_pid_file
  ( proc_boot_id(){ :; }; register_foreground_watchdog ) > /dev/null 2>&1 </dev/null
  rc=$?
  if [ "${rc}" -ne 0 ] && [ ! -f "${FOREGROUND_PID_FILE}" ]; then
    ok "取不到 boot_id → 登记失败且不写身份文件"
  else
    no "取不到 boot_id 却登记成功（rc=${rc}）"
  fi
  reset_pid_file
  if register_foreground_watchdog \
     && [ "$(sed -n '1p' "${FOREGROUND_PID_FILE}" 2>/dev/null)" = "$$" ] \
     && [ "$(sed -n '2p' "${FOREGROUND_PID_FILE}" 2>/dev/null)" = "FAKE-BOOT" ] \
     && [ -n "$(sed -n '3p' "${FOREGROUND_PID_FILE}" 2>/dev/null)" ]; then
    ok "正常路径写出三行身份（PID/boot_id/starttime）"
  else
    no "正常路径未写出三行身份"
  fi

  head_ "B3) stop_meme_service：watchdog 仍存活（kill 无效）时必须报失败且保留身份文件"
  reset_pid_file
  printf '%s\n' "$$" "FAKE-BOOT" "FAKE-START" > "${FOREGROUND_PID_FILE}"
  # kill 只让「发信号」失败、kill -0 仍有效；sleep 变 no-op 以免空等 10 秒
  ( kill(){ if [ "$1" = "-0" ]; then builtin kill -0 "$2" 2>/dev/null; return $?; fi; return 1; }
    sleep(){ :; }
    stop_meme_service ) > /dev/null 2>&1 </dev/null
  rc=$?
  if [ "${rc}" -ne 0 ]; then ok "仍存活时报「停止失败」，没有假成功"; else no "watchdog 仍存活却报停止成功"; fi
  if [ -f "${FOREGROUND_PID_FILE}" ]; then ok "身份文件被保留（未提前销毁证据）"; else no "身份文件已被删除，残留循环检测不到"; fi

  head_ "B4) stop_meme_service：一行式旧身份文件指向活进程时必须报失败且保留文件"
  reset_pid_file
  printf '%s\n' "$$" > "${FOREGROUND_PID_FILE}"     # 旧格式只有 PID 一行，身份校验必然 fail-closed
  stop_meme_service > /dev/null 2>&1 </dev/null
  rc=$?
  if [ "${rc}" -ne 0 ]; then ok "身份不可信时报「停止失败」"; else no "身份不可信却报停止成功"; fi
  if [ -f "${FOREGROUND_PID_FILE}" ]; then ok "不可信的身份文件未被删除"; else no "身份不可信却删掉了身份文件"; fi
  reset_pid_file
fi

# ---------- C 安装完成判据必须证明 pip 装成功 ----------
if group_on C; then
  head_ "C) is_meme_install_complete 必须区分「venv 文件在」与「包真的装上了」"
  fixture_fake_install

  echo 1 > "${PIP_SHOW_RC_FILE}"
  if is_meme_install_complete; then no "venv/配置都在但包没装上，却判为「已完成」"; else ok "pip 未装成功 ⇒ 未完成"; fi
  echo 0 > "${PIP_SHOW_RC_FILE}"
  if is_meme_install_complete; then ok "pip 装成功 ⇒ 已完成"; else no "pip 装成功却判为「未完成」"; fi

  head_ "C2) pip 失败后再次选「安装」必须能再进修复模式（不能被「您已安装」挡住）"
  echo 1 > "${PIP_SHOW_RC_FILE}"
  install_repair_probe() {
    command(){ if [ "$1" = "-v" ]; then echo "/usr/bin/$2"; return 0; fi; builtin command "$@"; }
    apt(){ return 0; }
    python3(){ mkdir -p venv/bin; : > venv/bin/activate; return 0; }
    python(){ return 1; }                      # pip install 故意失败
    select_extra_repos_to_install(){ :; }
    clone_selected_extra_repos(){ :; }
    install_meme_generator 2>&1 </dev/null
  }
  out=$(install_repair_probe)
  case "${out}" in *修复模式*) ok "第 1 次进入修复模式" ;; *) no "第 1 次未进入修复模式" ;; esac
  case "${out}" in *"您已安装meme生成器"*) no "被误判为「已安装」，挡在修复流程外" ;; *) ok "未被误判为「已安装」" ;; esac
  out=$(install_repair_probe)                  # 关键：pip 再次失败后仍必须能重进
  case "${out}" in *修复模式*) ok "pip 再次失败后仍可重进修复模式" ;; *) no "pip 失败后被「已完成」挡住，无法重试" ;; esac
  # 安全断言：install 用例必须在「被桩掉的 pip」处就失败，不能走到「安装字体」——
  # 那一步会 `mkdir /usr/share/fonts` 并往里拷文件，属于真实机器上的系统级写入。
  case "${out}" in
  *安装字体*) no "install 用例越界到了字体安装阶段（会写 /usr/share/fonts）" ;;
  *) ok "未越界到系统目录写入阶段" ;;
  esac

  head_ "C3) 重装依赖成功后选「重新启动」必须真的启动（不能撞上 restart 的「未启动无法重启」）"
  fixture_fake_install
  mkdir -p "${install_path}/${MAIN_REPO_NAME}"
  c3_mark="${WORK_DIR}/c3_mark"
  rm -f "${c3_mark}"
  # 现场：原本在运行 → 安全停止 → pip 成功 → 用户选"重新启动"（默认分支）。
  # 记录实际调用的是 start 还是 restart：restart 的入口守卫此刻必然失败（服务已停），
  # 所以只要走到 restart，服务就不会被拉起来。
  out=$( {
    is_meme_process_running(){ return 0; }     # 假装原本在运行
    stop_meme_service(){ return 0; }           # 停止成功
    activate_meme_venv(){ return 0; }
    python3(){ mkdir -p venv/bin; : > venv/bin/activate; return 0; }
    python(){ return 0; }                      # pip 全部成功
    sleep(){ :; }
    start_meme_generator(){ echo "START:${1:-}" >> "${c3_mark}"; }
    restart_meme_generator(){ echo "RESTART" >> "${c3_mark}"; }
    reinstall_pip_dependencies
  } <<< "1" 2>&1 )
  if grep -q '^START:重启$' "${c3_mark}" 2>/dev/null; then
    ok "进入了 start_meme_generator（带「重启」标签）"
  else
    no "没有进入 start_meme_generator —— mark=[$(cat "${c3_mark}" 2>/dev/null | tr '\n' ' ')]"
  fi
  if grep -q '^RESTART$' "${c3_mark}" 2>/dev/null; then
    no "调用了 restart_meme_generator（此刻服务已停，它只会打印「未启动，无法重启」）"
  else
    ok "没有调用 restart_meme_generator"
  fi
  case "${out}" in
  *"未启动，无法重启"*) no "输出里出现「未启动，无法重启」，服务不会被恢复" ;;
  *) ok "未出现「未启动，无法重启」" ;;
  esac
fi

# ---------- D 配置写入必须是原子事务 ----------
if group_on D; then
  fixture_fake_install        # D2 需要 rewrite_config 的第一道守卫（.git）通过
  head_ "D1) write_default_config：成功则落地、权限 600、内容完整"
  rm -f "${config}"
  if write_default_config; then ok "写入返回成功"; else no "写入返回失败"; fi
  if [ -f "${config}" ]; then ok "配置文件已生成"; else no "配置文件未生成"; fi
  # POSIX 权限位在 Windows（MSYS/Cygwin）上只是模拟：chmod 600 不会真的生效，stat 会报 644。
  # 先做能力探测，不支持就明确 SKIP——别把平台差异报成生产 bug（在 Linux 上这条必须真的绿）。
  can_chmod=0
  if command -v stat > /dev/null 2>&1 && command -v chmod > /dev/null 2>&1; then
    probe="${WORK_DIR}/perm_probe"
    : > "${probe}"
    chmod 600 "${probe}" 2> /dev/null
    [ "$(stat -c '%a' "${probe}" 2> /dev/null)" = "600" ] && can_chmod=1
    rm -f "${probe}"
  fi
  if [ "${can_chmod}" = "1" ]; then
    perm=$(stat -c '%a' "${config}" 2>/dev/null)
    if [ "${perm}" = "600" ]; then ok "权限为 600（含密钥的配置已收紧）"; else no "权限为 ${perm}（应为 600）"; fi
  else
    skip "本平台不强制 POSIX 权限位（chmod 600 无效），跳过权限断言"
  fi
  if grep -q '^\[server\]' "${config}" && grep -q '^port = ' "${config}"; then
    ok "包含 [server]/port（TOML 结构完整）"
  else
    no "默认配置内容不完整"
  fi

  head_ "D2) rewrite_config：备份失败必须中止，且不得改动原配置"
  printf 'baidu_trans_apikey = "ORIGINAL-SECRET"\n' > "${config}"
  before=$(cat "${config}")
  out=$( { cp(){ return 1; }; rewrite_config; } <<< "y" 2>&1 )
  rc=$?
  after=$(cat "${config}" 2>/dev/null)
  # 注意：rewrite_config 末尾还有一次 `read`，它的退出码会盖掉 rc，所以判据用「提示语 + 内容未变」而不是 rc
  case "${out}" in
  *中止* | *未改动*) ok "备份失败时给出中止提示（未继续覆盖）" ;;
  *) no "备份失败未中止 —— rc=${rc}，输出: $(printf '%s' "${out}" | tr '\n' ' ' | head -c 200)" ;;
  esac
  if [ "${before}" = "${after}" ]; then ok "原配置内容未被改动"; else no "原配置被覆盖，自定义设置/密钥已丢"; fi

  head_ "D3) rewrite_config：必须真正调用它（接线测试），而不是再测一遍 helper"
  # 之前的写法直接调 write_default_config —— 万一有人把 rewrite_config 里那一行调用删了，
  # 测试照样全绿。这里改成执行 rewrite_config 本体并检查"接线"是否还在。
  printf 'baidu_trans_apikey = "SECRET-BEFORE-REWRITE"\n\n[meme]\nmeme_dirs = ["/tmp/nowhere"]\n' > "${config}"
  rewrite_out=$(rewrite_config <<< "y" 2>&1)
  rc=$?
  if grep -q 'SECRET-BEFORE-REWRITE' "${config}" 2>/dev/null; then
    no "rewrite_config 没有真正重写配置（write_default_config 的接线可能被删）—— rc=${rc}，输出: $(printf '%s' "${rewrite_out}" | tr '\n' ' ' | head -c 160)"
  else
    ok "原内容已被默认配置替换（接线正确）"
  fi
  if grep -q '^\[server\]' "${config}" 2>/dev/null; then ok "重写后是默认配置（含 [server]）"; else no "重写后内容异常"; fi
  if ls "${config}".backup.* > /dev/null 2>&1; then ok "已创建备份文件"; else no "没有创建备份文件"; fi
fi

# ---------- E 配置读写（段内定位 / 转义 / meme_dirs） ----------
if group_on E; then
  fixture_fake_install
  head_ "E1) config_set：未命中 key / section 必须返回非零，且不改动文件"
  printf '[server]\nport = 50835\n' > "${config}"
  before=$(cat "${config}")
  if config_set server no_such_key '"x"' "${config}"; then no "未命中的 key 却返回 0"; else ok "未命中 key 返回非零"; fi
  if config_set no_such_section port '"1"' "${config}"; then no "未命中的 section 却返回 0"; else ok "未命中 section 返回非零"; fi
  if [ "$(cat "${config}")" = "${before}" ]; then ok "未命中时文件内容未被改动"; else no "未命中却改动了文件"; fi

  head_ "E2) config_set：命中时改写值，并保留该行行尾注释与其它行"
  printf '[server]\nport = 50835  # 监听端口\nhost = "0.0.0.0"\n' > "${config}"
  if config_set server port '12345' "${config}"; then ok "命中并写入成功"; else no "命中却写入失败"; fi
  if grep -q '^port = 12345  # 监听端口$' "${config}"; then ok "新值生效且行尾注释保留"; else no "写入结果不符: $(grep '^port' "${config}")"; fi
  if grep -q '^host = "0.0.0.0"$' "${config}"; then ok "其它行未被破坏"; else no "其它行被破坏"; fi

  head_ "E3) config_set_string：\ 与 \" 必须转义，写出结构完整的一行"
  printf '[translate]\nbaidu_trans_apikey = ""\n' > "${config}"
  if config_set_string translate baidu_trans_apikey 'p\q"r' "${config}"; then ok "字符串写入成功"; else no "字符串写入失败"; fi
  line=$(grep '^baidu_trans_apikey' "${config}")
  if [ "${line}" = 'baidu_trans_apikey = "p\\q\"r"' ]; then
    ok "转义形式正确（\\ 与 \" 均已转义，未破坏 TOML 结构）"
  else
    no "转义形式不符: ${line}"
  fi

  head_ "E4) config_get：剥掉整体引号，但数组值的引号必须保留"
  printf '[server]\nhost = "0.0.0.0"\n\n[meme]\nmeme_dirs = ["/a/b", "/c/d"]\n' > "${config}"
  if [ "$(config_get server host "${config}")" = "0.0.0.0" ]; then ok "普通字符串剥掉外层引号"; else no "普通字符串读取异常: $(config_get server host "${config}")"; fi
  if [ "$(config_get meme meme_dirs "${config}")" = '["/a/b", "/c/d"]' ]; then ok "数组值的引号被保留"; else no "数组值读取异常: $(config_get meme meme_dirs "${config}")"; fi

  head_ "E5) meme_dirs 增删链路（比较前先去掉分隔符空白）"
  printf '[meme]\nmeme_dirs = ["/a", "/b"]\n' > "${config}"
  if [ "$(remove_dir_from_list "$(meme_dirs_value)" "/a" | tr -d ' ')" = '"/b"' ]; then ok "移除存在的项"; else no "移除结果不符"; fi
  if [ "$(remove_dir_from_list "$(meme_dirs_value)" "/zz" | tr -d ' ')" = '"/a","/b"' ]; then ok "移除不存在的项时列表原样保留"; else no "移除不存在项时列表被破坏"; fi
fi

# ---------- F 自更新 / 版本一致性 / cron ----------
if group_on F; then
  # 这里**故意没有**「SCRIPT_VERSION 必须高于 HEAD」那条断言（2026-09-13 用户决定删除）：
  # 那种"拿工作区版本跟 HEAD 比"的断言与**提交流程耦合**——刚 commit 完工作区 == HEAD，必然判红，
  # 是假警报；要让它不假红，就得再加一堆"有没有未提交改动"的判断，等于把测试变成流程检查器。
  # 该约定改为**纯文档约定**（见 AGENTS.md「验证方式」与「自更新」）：改脚本时记得提版本，提交前自查。
  # ⚠️ 下方编号**从 F2 开始且保持不变**：AGENTS.md 多处引用 F5~F9，重排会让这些引用全部对不上。

  # ⚠️ 共享 fixture（别删）：下面 F2/F3 要拿"当前版本"造 curl 桩——源返回当前版本 / 返回旧版本。
  # 真实教训（2026-09-13）：删掉上面那条版本断言时，顺手删掉了它顺带定义的版本变量，
  # 于是 F2/F3 拿着空版本去造桩，当场全红——**跑一遍才抓到**。
  # 推论：删改断言块前，先查它是否顺带建立了后面的用例依赖的 fixture（变量 / 桩 / 现场）。
  cur_ver=$(grep -m 1 '^SCRIPT_VERSION=' "${TARGET_SCRIPT}" | cut -d'"' -f2)
  if [ -z "${cur_ver}" ]; then
    no "取不到被测脚本的 SCRIPT_VERSION，F2/F3 无法造桩（后续结果不可信）"
  fi

  # ---- 自更新：用 curl 桩按「源」返回不同版本 ----
  sys_script="${WORK_DIR}/sys_meme_generator.sh"
  SCRIPT_SYSTEM_PATH="${sys_script}"
  mkver(){ printf '#!/usr/bin/env bash\nSCRIPT_VERSION="%s"\n' "$1"; }
  curl(){   # 桩：gitee 视为源1，其它视为源2，各自返回 FAKE_VER_n
    local out="" url=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -o) out="$2"; shift 2 ;;
        http*) url="$1"; shift ;;
        *) shift ;;
      esac
    done
    [ -n "${out}" ] || return 1
    case "${url}" in
      *gitee*) mkver "${FAKE_VER_1}" > "${out}" ;;
      *) mkver "${FAKE_VER_2}" > "${out}" ;;
    esac
    return 0
  }

  head_ "F2) ensure_script_saved：同版本但内容已损坏时必须重下（不能当「已是最新」）"
  { mkver "${cur_ver}"; printf 'if then\n'; } > "${sys_script}"
  chmod +x "${sys_script}"
  FAKE_VER_1="${cur_ver}"; FAKE_VER_2="${cur_ver}"
  if ensure_script_saved; then ok "重下成功（返回 0）"; else no "损坏的同版本脚本没有被重下"; fi
  if bash -n "${sys_script}" > /dev/null 2>&1; then ok "系统脚本已被换成语法可用的脚本"; else no "系统脚本仍不可用"; fi

  head_ "F3) download_script：源返回旧版本时必须跳到下一个源，不能把旧版本写回"
  mkver "0.0.1" > "${sys_script}"
  FAKE_VER_1="0.0.1"; FAKE_VER_2="${cur_ver}"
  if download_script; then ok "最终下载成功"; else no "下载失败（本应在源2 成功）"; fi
  if grep -q "^SCRIPT_VERSION=\"${cur_ver}\"$" "${sys_script}"; then
    ok "写回的是当前版本（旧版镜像被跳过）"
  else
    no "写回的不是当前版本: $(grep -m 1 SCRIPT_VERSION "${sys_script}")"
  fi

  head_ "F4) download_script：所有源版本都不符时必须失败，且不覆盖现有系统脚本"
  mkver "${cur_ver}" > "${sys_script}"
  before_sys=$(cat "${sys_script}")
  FAKE_VER_1="0.0.1"; FAKE_VER_2="0.0.2"
  if download_script; then no "全源版本不符却返回成功"; else ok "全源版本不符时返回非零"; fi
  if [ "$(cat "${sys_script}")" = "${before_sys}" ]; then ok "现有系统脚本未被覆盖"; else no "现有系统脚本被改动了"; fi

  # ---- cron：统一读取层（read_current_crontab）的行为 ----
  cron_store="${WORK_DIR}/fake_crontab"
  cron_written="${WORK_DIR}/cron_written"
  cron_mode="ok"     # ok | nocrontab | stderr_error | stdout_error
  cron_write_rc=0    # 0 = 写回成功；非 0 = 模拟 `crontab -` 写回失败（供 F9 用）
  crontab(){   # 桩：不碰真实 crontab；按 cron_mode 模拟四种读取结果
    if [ "$1" = "-l" ]; then
      case "${cron_mode}" in
      nocrontab)    echo "no crontab for $(id -un 2>/dev/null || echo root)" >&2; return 1 ;;
      stderr_error) echo "crontab: permission denied" >&2; return 1 ;;   # 非零 + 只有 stderr
      stdout_error) printf '0 3 * * * echo x\n'; return 1 ;;             # 非零 + 有 stdout
      esac
      if [ ! -f "${cron_store}" ]; then
        echo "no crontab for $(id -un 2>/dev/null || echo root)" >&2
        return 1
      fi
      cat "${cron_store}"
      return 0
    fi
    echo "WRITTEN" >> "${cron_written}"     # 记录任何一次"尝试写回"，供 F8 / F9 断言
    if [ "${cron_write_rc}" -ne 0 ]; then
      cat > /dev/null                       # 吃掉 stdin，免得上游写管道拿到 EPIPE 刷噪音
      return "${cron_write_rc}"
    fi
    if [ "$1" = "-" ]; then cat > "${cron_store}"; else cp "$1" "${cron_store}"; fi
    return 0
  }

  head_ "F5) remove_meme_cron：meme 是唯一一条 cron 时也必须删成功（pipefail 老坑）"
  cron_mode="ok"
  printf '0 3 * * * /bin/bash -c true # meme_generator_auto_update\n' > "${cron_store}"
  if remove_meme_cron; then ok "删除返回成功"; else no "唯一的 meme cron 已删掉却报失败（grep -v 无输出 + pipefail）"; fi
  if [ -n "$(tr -d '[:space:]' < "${cron_store}" 2>/dev/null)" ]; then
    no "crontab 里仍有内容: $(cat "${cron_store}")"
  else
    ok "crontab 已被清空（任务真的删掉了）"
  fi

  head_ "F6) remove_meme_cron：确认没有 crontab / 没有该任务时必须幂等成功，且不误删其它条目"
  rm -f "${cron_store}"; cron_mode="nocrontab"
  if remove_meme_cron; then ok "明确「no crontab for」时返回成功（幂等）"; else no "确认没有 crontab 时却返回失败"; fi
  cron_mode="ok"; printf '0 3 * * * echo hello\n' > "${cron_store}"
  if remove_meme_cron; then ok "没有该任务时返回成功"; else no "没有该任务却返回失败"; fi
  if grep -q 'echo hello' "${cron_store}"; then ok "其它 cron 条目未被误删"; else no "其它 cron 条目被删掉了"; fi

  head_ "F7) 读取真失败时必须 fail-closed（**只带 stderr 也不行**）"
  # 最危险的形态就是「非零 + stdout 为空 + stderr 有真错误」：
  # 旧实现会因为"stdout 为空"把它当成「用户没有 crontab」，从而 fail-open。
  cron_mode="stderr_error"
  if remove_meme_cron; then
    no "stderr-only 的读取错误被当成「没有 crontab」，返回了成功（fail-open）"
  else
    ok "stderr-only 错误时如实返回非零"
  fi
  cron_mode="stdout_error"
  if remove_meme_cron; then no "非零 + 有输出时却返回成功"; else ok "非零 + 有输出时也如实返回非零"; fi
  cron_mode="ok"

  head_ "F8) 读不到 crontab 时绝不能写回（否则会覆盖用户整份 crontab）"
  : > "${cron_written}"
  cron_mode="stderr_error"
  # ① 追加入口必须拒绝写入
  append_meme_cron "0 3 * * * echo x # meme_generator_auto_update" > /dev/null 2>&1
  if [ -s "${cron_written}" ]; then no "读取失败时 append_meme_cron 仍然写回了 crontab"; else ok "读取失败时 append 拒绝写入"; fi
  # ② 菜单「切换自动更新」在读不到时必须中止，且不得写入
  out=$(toggle_auto_update <<< "" 2>&1)
  # 注意：case 的**模式里带空格必须加引号**，否则 bash 直接 `syntax error near unexpected token`。
  # 这个坑吃到过：`*无法读取当前 crontab*)` 没加引号，整个生成出来的 harness 语法错误，
  # 于是「harness 生成失败」——F 组（含本条）根本没跑过。改成把含空格的子串整体加引号。
  case "${out}" in
  *"无法读取当前 crontab"*) ok "toggle_auto_update 在读不到时明确中止" ;;
  *) no "toggle 未明确中止（输出: $(printf '%s' "${out}" | tr '\n' ' ' | head -c 120)）" ;;
  esac
  if [ -s "${cron_written}" ]; then no "读取失败时 toggle 仍然写回了 crontab"; else ok "读取失败时 toggle 未写 crontab"; fi
  # ③ 菜单「开启自动更新」（setup_auto_update 的启用分支）同样不得写入。
  # 这条必须单独测：setup / toggle 是两个不同的调用点，只测 append + toggle 会漏掉「启用」这条路。
  # ensure_script_saved 在这里被桩掉：本例只关心"读不到 crontab 时不许写回"，
  # 不能让它去下载系统脚本（那会走到网络/系统目录）。
  out=$( { ensure_script_saved(){ return 0; }; setup_auto_update; } <<< "" 2>&1 )
  case "${out}" in
  *"无法读取当前 crontab"*) ok "setup_auto_update 启用分支在读不到时明确中止" ;;
  *) no "setup 未明确中止（输出: $(printf '%s' "${out}" | tr '\n' ' ' | head -c 120)）" ;;
  esac
  if [ -s "${cron_written}" ]; then no "读取失败时 setup 仍然写回了 crontab"; else ok "读取失败时 setup 未写 crontab"; fi

  head_ "F9) setup_auto_update 关闭分支：失败必须如实返回非零（不能只打印错误就返回 0）"
  # 为什么必须直接断言返回码：这个函数的失败分支一度只 echo、不留 return，于是 rc=0，
  # 违反「封装函数必须如实返回」；而它的调用点（Tmux_Start 的 case）最后一条语句是 echo，
  # 返回值在那一层被吃掉 —— 所以**端到端用例永远抓不到**，只能直接断言函数返回码。
  # ① 读取失败 → 非零
  cron_mode="stderr_error"
  out=$(setup_auto_update <<< "n" 2>&1); rc=$?
  if [ "${rc}" -ne 0 ]; then ok "读取失败时返回非零（rc=${rc}）"; else no "只打印了错误却返回 0（违反「封装函数必须如实返回」）"; fi
  case "${out}" in
  *"无法读取当前 crontab"*) ok "同时给出了人工处理提示" ;;
  *) no "缺少「无法读取当前 crontab」提示（输出: $(printf '%s' "${out}" | tr '\n' ' ' | head -c 120)）" ;;
  esac
  # ② 任务存在、但删除写回失败 → 非零
  cron_mode="ok"; cron_write_rc=1
  printf '0 3 * * * /bin/bash -c true # meme_generator_auto_update\n' > "${cron_store}"
  out=$(setup_auto_update <<< "n" 2>&1); rc=$?
  if [ "${rc}" -ne 0 ]; then ok "删除写回失败时返回非零（rc=${rc}）"; else no "删除写回失败却返回 0"; fi
  case "${out}" in
  *"移除自动更新任务失败"*) ok "同时给出了删除失败提示" ;;
  *) no "缺少「移除自动更新任务失败」提示" ;;
  esac
  # ③ 正向对照：确认存在且删成功时必须返回 0（防止修过头、把成功也报成失败）
  cron_write_rc=0
  printf '0 3 * * * /bin/bash -c true # meme_generator_auto_update\n' > "${cron_store}"
  if setup_auto_update <<< "n" > /dev/null 2>&1; then ok "正常关闭时返回 0"; else no "正常关闭却返回非零（把成功报成了失败）"; fi
  cron_mode="ok"
fi

# ---------- G 真实 git 行为（--fast 跳过）----------
if group_on G; then
  if [ "${RUN_GIT}" != "1" ]; then
    skip "git 用例（默认不跑 G 组；确实改了 git_clone / git_update 才加 --with-git）"
  else
    GIT_BIN="${GIT_BIN:-$(command -v git)}"
    if [ -z "${GIT_BIN}" ]; then
      skip "本机没有 git，跳过 git 用例"
    else
      # 仓库地址同样用 gp 的 C:/ 形式。实测（MSYS 版 git）：
      #   C:/.../bare.git        → clone / remote set-url / fetch 全部正常（被当成本地路径）
      #   file:///C:/.../bare.git → 被解析成 /C:/... 而失败
      # 而 Linux 上 gp 就是普通 POSIX 路径，裸路径同样可用。所以不要加 file:/// 前缀。
      gurl(){ gp "$1"; }
      gnew(){ "${GIT_BIN}" -c user.email=t@t -c user.name=t -C "$(gp "$1")" "${@:2}"; }
      REL="${WORK_DIR}/gitcase"
      rm -rf "${REL}"; mkdir -p "${REL}/gwork" "${REL}/glocal"
      gnew "${REL}/gwork" init -b main > /dev/null
      echo init > "${REL}/gwork/README.md"
      gnew "${REL}/gwork" add . > /dev/null
      gnew "${REL}/gwork" commit -m init > /dev/null
      "${GIT_BIN}" init --bare -b main "$(gp "${REL}/gbare.git")" > /dev/null
      gnew "${REL}/gwork" remote add origin "$(gurl "${REL}/gbare.git")"
      gnew "${REL}/gwork" push -u origin main > /dev/null 2>&1
      clone_err=$("${GIT_BIN}" clone "$(gurl "${REL}/gbare.git")" "$(gp "${REL}/glocal")" 2>&1)
      if [ ! -d "${REL}/glocal/.git" ]; then
        no "git 现场构建失败：clone 没有生成仓库 —— ${clone_err}"
      fi

      head_ "G1) git_update：远端被 force-push 改写历史后仍能对齐，且同名未跟踪文件被覆盖"
      printf 'user\n' > "${REL}/glocal/future"
      printf 'keep\n' > "${REL}/glocal/keepme"

      # 造**真正的非快进**改写：先让上游走到 B、本地同步到 B；再把上游 reset 回 A、另造 C、强推。
      # 这样本地 B 与远端 C 分叉（不是普通 fast-forward，单用 -f 但线性追加是测不出来的）。
      echo B > "${REL}/gwork/B.txt"
      gnew "${REL}/gwork" add . > /dev/null
      gnew "${REL}/gwork" commit -m B > /dev/null
      gnew "${REL}/gwork" push origin main > /dev/null 2>&1
      gnew "${REL}/glocal" pull --ff-only origin main > /dev/null 2>&1
      b_commit=$(gnew "${REL}/gwork" rev-parse HEAD)
      a_commit=$(gnew "${REL}/gwork" rev-parse HEAD~1)
      gnew "${REL}/gwork" reset --hard "${a_commit}" > /dev/null
      printf 'remote\n' > "${REL}/gwork/future"      # 让 future 在 C 里变成 tracked
      echo C > "${REL}/gwork/C.txt"
      gnew "${REL}/gwork" add . > /dev/null
      gnew "${REL}/gwork" commit -m "C (history rewritten)" > /dev/null
      c_commit=$(gnew "${REL}/gwork" rev-parse HEAD)
      gnew "${REL}/gwork" push -f origin main > /dev/null 2>&1

      upd_err=$(git_update "$(gp "${REL}/glocal")" /dev/null main "$(gurl "${REL}/gbare.git")" 2>&1)
      rc=$?
      if [ "${rc}" -eq 0 ]; then ok "git_update 返回 0"; else no "git_update 返回 ${rc} —— ${upd_err}"; fi
      if [ "$(gnew "${REL}/glocal" rev-parse HEAD 2>/dev/null)" = "${c_commit}" ]; then
        ok "本地 HEAD 已对齐被改写后的远端（非快进也能强制覆盖）"
      else
        no "本地 HEAD 未对齐远端新 HEAD"
      fi
      if gnew "${REL}/glocal" merge-base --is-ancestor "${b_commit}" HEAD 2>/dev/null; then
        no "被丢弃的旧提交 B 仍是本地祖先（历史没真正对齐）"
      else
        ok "旧提交 B 已不是本地祖先（历史被强制改写）"
      fi
      if [ "$(cat "${REL}/glocal/future" 2>/dev/null)" = "remote" ]; then ok "同名未跟踪文件被覆盖（与 AGENTS 声明一致）"; else no "同名未跟踪文件未被覆盖（语义变了）"; fi
      if [ "$(cat "${REL}/glocal/keepme" 2>/dev/null)" = "keep" ]; then ok "不冲突的未跟踪文件保留"; else no "不冲突的未跟踪文件被删"; fi

      head_ "G2) git_clone：已存在且非空的目标目录必须被拒绝，且不删除里面任何文件"
      mkdir -p "${REL}/nonempty"
      echo userfile > "${REL}/nonempty/userfile"
      git_clone "https://example.invalid/x.git" "${REL}/nonempty" /dev/null > /dev/null 2>&1
      rc=$?
      if [ "${rc}" -ne 0 ]; then ok "拒绝接管已存在的非空目录"; else no "错误地接管了非空目录"; fi
      if [ -f "${REL}/nonempty/userfile" ]; then ok "目录内原有文件未被删除"; else no "目录内原有文件被删"; fi

      head_ "G3) git_update：所有地址都失败后，origin 必须被恢复成权威地址"
      # 把 origin 指到一个「不是仓库的文件」+ 权威地址也给一个不存在的路径 → 全源失败。
      # 全程本地路径，不触发网络，避免 DNS 超时拖慢测试。
      broken_url="$(gp "${REL}/gwork/README.md")"
      canonical_url="$(gp "${REL}/nowhere.git")"
      gnew "${REL}/glocal" remote set-url origin "${broken_url}"
      git_update "$(gp "${REL}/glocal")" /dev/null main "${canonical_url}" > /dev/null 2>&1
      rc=$?
      if [ "${rc}" -ne 0 ]; then ok "全部地址失败时如实返回非零"; else no "全源失败却返回 0"; fi
      cur_origin=$(gnew "${REL}/glocal" remote get-url origin 2>/dev/null)
      if [ "${cur_origin}" = "${canonical_url}" ]; then
        ok "origin 被恢复为权威地址（未留下残缺 / 相对路径）"
      else
        no "origin 变成了 ${cur_origin}（应为 ${canonical_url}）"
      fi
    fi
  fi
fi

# ---------- H 公网 IP：后台获取 + 本地缓存（curl 全程桩掉，不联网） ----------
if group_on H; then
  mkdir -p "${HOME}/.config/meme_generator"   # --only H 时其它组不会建这个目录
  head_ "H1) is_valid_ipv4：合法放行；超段/缺段/多段/字母/HTML/空白/空串全部拒绝"
  if is_valid_ipv4 "1.2.3.4" && is_valid_ipv4 "0.0.0.0" && is_valid_ipv4 "255.255.255.255"; then
    ok "合法 IPv4 放行"
  else
    no "合法 IPv4 被误拒"
  fi
  bad_cnt=0
  for b in "256.1.1.1" "1.2.3" "1.2.3.4.5" "abc" "1.2.3.4 " "<html>1.2.3.4</html>" ""; do
    if is_valid_ipv4 "${b}"; then bad_cnt=$((bad_cnt + 1)); fi
  done
  if [ "${bad_cnt}" -eq 0 ]; then
    ok "非法输入全部拒绝"
  else
    no "${bad_cnt} 个非法输入被放行"
  fi

  head_ "H2) load_public_ip_cache：只读文件零网络；缺失/损坏/过期都必须拒绝且清空 PUBLIC_IP"
  rm -f "${PUBLIC_IP_CACHE}"
  if load_public_ip_cache; then no "缓存不存在却返回成功"; else ok "缓存不存在时如实返回失败"; fi
  if [ -z "${PUBLIC_IP}" ]; then ok "读取失败后 PUBLIC_IP 保持为空"; else no "读取失败却残留 PUBLIC_IP=${PUBLIC_IP}"; fi
  printf 'hello world\n' > "${PUBLIC_IP_CACHE}"
  if load_public_ip_cache; then no "损坏内容被当成 IP 采用了"; else ok "损坏内容被拒绝"; fi
  printf '%s %s\n' "$(date +%s)" "203.0.113.7" > "${PUBLIC_IP_CACHE}"
  if load_public_ip_cache && [ "${PUBLIC_IP}" = "203.0.113.7" ]; then
    ok "新鲜缓存读出 IP 存入变量"
  else
    no "新鲜缓存未读出（PUBLIC_IP=${PUBLIC_IP}）"
  fi
  printf '%s %s\n' "$(( $(date +%s) - PUBLIC_IP_TTL - 10 ))" "203.0.113.7" > "${PUBLIC_IP_CACHE}"
  PUBLIC_IP="stale-marker"
  if load_public_ip_cache; then no "过期缓存仍被采用"; else ok "过期缓存被拒绝"; fi
  if [ -z "${PUBLIC_IP}" ]; then ok "拒绝过期缓存时 PUBLIC_IP 被清空"; else no "拒绝后仍残留 PUBLIC_IP=${PUBLIC_IP}"; fi

  head_ "H3) refresh_public_ip_bg：合法响应写入缓存；非法响应（错误页）绝不写缓存"
  rm -f "${PUBLIC_IP_CACHE}"
  ( curl(){ printf '198.51.100.23\n'; }; refresh_public_ip_bg ) > /dev/null 2>&1 </dev/null
  wait_n=0
  while [ ! -s "${PUBLIC_IP_CACHE}" ] && [ "${wait_n}" -lt 50 ]; do sleep 0.1; wait_n=$((wait_n + 1)); done
  if [ "$(awk '{print $2}' "${PUBLIC_IP_CACHE}" 2>/dev/null)" = "198.51.100.23" ]; then
    ok "后台获取把合法响应写入缓存"
  else
    no "后台获取未写入缓存或内容错误：$(cat "${PUBLIC_IP_CACHE}" 2>/dev/null)"
  fi
  rm -f "${PUBLIC_IP_CACHE}"
  ( curl(){ printf '<html>error</html>\n'; }; refresh_public_ip_bg ) > /dev/null 2>&1 </dev/null
  wait_n=0
  while [ ! -s "${PUBLIC_IP_CACHE}" ] && [ "${wait_n}" -lt 20 ]; do sleep 0.1; wait_n=$((wait_n + 1)); done
  if [ ! -s "${PUBLIC_IP_CACHE}" ]; then
    ok "非法响应不写缓存（否则错误页会被当 IP 展示）"
  else
    no "非法响应被写进缓存：$(cat "${PUBLIC_IP_CACHE}")"
  fi

  head_ "H4) init_public_ip：缓存新鲜 → 绝不触发后台获取（「不要每次都 POST」的保证）"
  printf '%s %s\n' "$(date +%s)" "203.0.113.99" > "${PUBLIC_IP_CACHE}"
  rm -f "${WORK_DIR}/pubip_refresh_marker" "${WORK_DIR}/pubip_var_marker"
  (
    refresh_public_ip_bg(){ : > "${WORK_DIR}/pubip_refresh_marker"; }
    init_public_ip
    [ "${PUBLIC_IP}" = "203.0.113.99" ] && : > "${WORK_DIR}/pubip_var_marker"
  ) > /dev/null 2>&1 </dev/null
  if [ ! -f "${WORK_DIR}/pubip_refresh_marker" ]; then
    ok "缓存新鲜 → 没有触发后台获取"
  else
    no "缓存新鲜却触发了后台获取（会造成反复请求）"
  fi
  if [ -f "${WORK_DIR}/pubip_var_marker" ]; then
    ok "init 后 PUBLIC_IP 已填充"
  else
    no "init 后 PUBLIC_IP 未填充"
  fi

  head_ "H5) init_public_ip：缓存缺失 → 触发一次后台获取（每次脚本启动至多补一发）"
  rm -f "${PUBLIC_IP_CACHE}" "${WORK_DIR}/pubip_refresh_marker"
  (
    refresh_public_ip_bg(){ : > "${WORK_DIR}/pubip_refresh_marker"; }
    init_public_ip
  ) > /dev/null 2>&1 </dev/null
  if [ -f "${WORK_DIR}/pubip_refresh_marker" ]; then
    ok "无缓存 → 触发了后台获取"
  else
    no "无缓存却没触发后台获取（公网地址永远显示不出来）"
  fi
  rm -f "${PUBLIC_IP_CACHE}" "${WORK_DIR}/pubip_refresh_marker" "${WORK_DIR}/pubip_var_marker"
fi

done_
[ "${FAIL}" -eq 0 ]
TESTS

build_harness() {   # $1 = 源脚本（可能是变异副本），$2 = 输出 harness
  {
    printf '#!/usr/bin/env bash\n'
    cat "${WORK}/prelude.sh"
    extract_lib "$1"
    printf '\n'
    cat "${WORK}/stubs.sh"
    printf '\n'
    extract_foreground_start "$1"
    printf '\n'
    cat "${WORK}/tests.sh"
  } > "$2"
  bash -n "$2" || return 1
}

# ============================================================
# 3) 跑正常用例（有界：timeout + stdin 钉死）
# ============================================================
build_harness "${TARGET}" "${WORK}/harness.sh" || { echo "harness 生成失败"; exit 2; }

echo "=========== 被测：${TARGET} ==========="
echo "进度日志: ${LOG}"
bounded "${HARNESS_TIMEOUT}" bash "${WORK}/harness.sh"
NORMAL_RC=$?
if [ "${NORMAL_RC}" -eq 124 ]; then
  echo "  NOT OK - harness 超时（${HARNESS_TIMEOUT}s）被强制终止，可能有死循环；日志尾部见 ${LOG}"
fi

# ============================================================
# 4) 变异验证（--mutate 才跑）：故意注入 bug，断言必须变红
#    变异施加在源脚本副本上再重新抽取，这样也覆盖到嵌套的 Foreground_Start
# ============================================================
MUT_OK=0
MUT_BAD=0
if [ "${DO_MUTATE}" != "1" ]; then
  echo
  echo "（变异验证已停用，见 AGENTS.md；参数 --mutate 保留但不要跑）"
else
  mutate() {   # $1=文件 $2=旧内容(多行字面量) $3=新内容
    local content
    # 先剥 CR：Windows 工作区是 CRLF，而下面的字面量按 LF 写，不剥就永远匹配不上
    content=$(tr -d '\r' < "$1")
    case "${content}" in
    *"$2"*) printf '%s' "${content//"$2"/"$3"}" > "$1"; return 0 ;;
    *) return 1 ;;
    esac
  }

  run_mutation() {   # $1=名称 $2=旧 $3=新 $4=适用分组（逗号分隔；空=全部）
    local groups="${4:-}"
    [ -n "${groups}" ] || groups="A,B,C,D,E,F,G"
    if [ -n "${ONLY}" ]; then
      # 已经用 --only 缩小范围时，只跑「完全落在选择内」的变异，否则会误报"未被抓住"
      local g okg=1
      for g in $(printf '%s' "${groups}" | tr ',' ' '); do
        case ",${ONLY}," in *",${g},"*) ;; *) okg=0 ;; esac
      done
      if [ "${okg}" = "0" ]; then
        echo "  SKIP   - ${1}（不在 --only ${ONLY} 范围内）"
        return
      fi
    fi
    cp "${TARGET}" "${WORK}/target_mut.sh"
    if ! mutate "${WORK}/target_mut.sh" "$2" "$3"; then
      echo "  [变异失败] ${1}：源脚本里没匹配到目标代码，未能验证"
      MUT_BAD=$((MUT_BAD + 1))
      return
    fi
    if ! build_harness "${WORK}/target_mut.sh" "${WORK}/harness_mut.sh"; then
      echo "  [变异失败] ${1}：变异后语法错误，未能验证"
      MUT_BAD=$((MUT_BAD + 1))
      return
    fi
    local out red first mut_rc log_before log_after g leaked
    log_before=$(grep -c '' "${LOG}" 2>/dev/null)
    [ -n "${log_before}" ] || log_before=0
    # 变异只跑它涉及的分组（快很多），并且不往主进度日志里写
    out=$(export ONLY="${groups}" LOG_FILE=""; bounded "${HARNESS_TIMEOUT}" bash "${WORK}/harness_mut.sh" 2>&1)
    mut_rc=$?
    log_after=$(grep -c '' "${LOG}" 2>/dev/null)
    [ -n "${log_after}" ] || log_after=0

    # 关键：必须**完整跑完、并由断言主动判红**才算 caught。
    # 否则"中途超时/运行崩坏 + 之前碰巧打印过一个 NOT OK"会被误判成 caught（假 caught）。
    # 正常 harness 的收尾是 `[ "${FAIL}" -eq 0 ]`，所以被抓住时退出码应当是 1。
    if [ "${mut_rc}" -eq 124 ]; then
      echo "  NOT OK - ${1}：变异 harness 超时被终止（不能算 caught）"
      MUT_BAD=$((MUT_BAD + 1))
      return
    fi
    if [ "${mut_rc}" -ne 1 ]; then
      echo "  NOT OK - ${1}：变异 harness 退出码 ${mut_rc}（预期 1 = 有断言失败地正常收尾）"
      MUT_BAD=$((MUT_BAD + 1))
      return
    fi
    if ! printf '%s\n' "${out}" | grep -qE '^TOTAL: .*fail=[1-9]'; then
      echo "  NOT OK - ${1}：没有完整结束（缺 TOTAL 行）或没有真实断言失败"
      MUT_BAD=$((MUT_BAD + 1))
      return
    fi

    # 自检①：分组隔离必须真的生效。否则"别的组里某条 NOT OK"也能把本变异判成 caught（假 caught）。
    leaked=""
    for g in A B C D E F G H; do
      case ",${groups}," in *",${g},"*) continue ;; esac
      printf '%s\n' "${out}" | grep -qE "^${g}[0-9]?\)" && leaked="${leaked} ${g}"
    done
    if [ -n "${leaked}" ]; then
      echo "  NOT OK - ${1}：分组隔离失效，输出里出现了未选中的组:${leaked}"
      MUT_BAD=$((MUT_BAD + 1))
    fi
    # 自检②：变异运行不得污染主进度日志（LOG_FILE 覆盖也要真的生效）
    if [ "${log_after}" != "${log_before}" ]; then
      echo "  NOT OK - ${1}：变异运行污染了主进度日志（+$((log_after - log_before)) 行）"
      MUT_BAD=$((MUT_BAD + 1))
    fi

    red=$(printf '%s\n' "${out}" | grep -c 'NOT OK')
    first=$(printf '%s\n' "${out}" | grep 'NOT OK' | head -1 | sed 's/^ *//')
    if [ "${red}" -ge 1 ]; then
      echo "  ok     - ${1}（被 ${red} 条断言抓住：${first}）"
      MUT_OK=$((MUT_OK + 1))
    else
      echo "  NOT OK - ${1}：注入 bug 后断言依然全绿 —— 这条断言是恒真的，无效"
      MUT_BAD=$((MUT_BAD + 1))
    fi
  }

  echo
  echo "⚠️ 变异验证已停用（2026-09-13，用户决定，见 AGENTS.md）；本次是你显式传了 --mutate，继续执行。"
  echo "=========== 变异验证（期望每条都变红）==========="

  run_mutation "去掉 is_meme_process_running 的前台判据" \
'if foreground_pid_alive; then
    return 0
fi
' '' A

  run_mutation "把 watchdog 身份登记挪到 cd/激活 venv 之前" \
  'Foreground_Start(){
# 先把「所有可能失败的准备」做完，再登记 watchdog 身份。' \
  'Foreground_Start(){
register_foreground_watchdog || true
# 先把「所有可能失败的准备」做完，再登记 watchdog 身份。' B

  run_mutation "安装判据退回只看 .git" \
  'venv / 配置可能还没建好
if is_meme_install_complete; then' \
  'venv / 配置可能还没建好
if is_meme_repo_installed; then' C

  run_mutation "is_meme_install_complete 去掉 pip 包判据" \
  '"${venv_python}" -m pip show meme-generator > /dev/null 2>&1 || return 1' 'true' C

  run_mutation "stop_meme_service 改回「先删身份文件再确认退出」" \
  '        if ! foreground_pid_alive; then
            rm -f "${FOREGROUND_PID_FILE}"
        fi' '        rm -f "${FOREGROUND_PID_FILE}"' B

  run_mutation "stop_meme_service 去掉「身份不可信就不算停止成功」" \
  '            fg_unverified=true' '            fg_unverified=false' B

  run_mutation "rewrite_config 备份失败仍继续覆盖" \
  '        if ! cp "${config}" "${backup_file}"; then' '        if false; then' D

  run_mutation "rewrite_config 丢掉 write_default_config 的接线" \
  '    if ! write_default_config; then' '    if false; then' D

  run_mutation "重装依赖后回调 restart_meme_generator（服务起不来）" \
  '        N|n) echo -e ${yellow}请记得手动启动meme生成器${background} ;;
        *) start_meme_generator "重启" ;;' \
  '        N|n) echo -e ${yellow}请记得手动启动meme生成器${background} ;;
        *) restart_meme_generator ;;' C

  run_mutation "remove_meme_cron 退回「grep -v | crontab -」老写法（pipefail 会误报失败）" \
  'if [ -n "${filtered}" ]; then
    if printf '"'"'%s\n'"'"' "${filtered}" | crontab -; then return 0; fi
    return 1
fi
if printf '"'"''"'"' | crontab -; then return 0; fi
return 1' \
  '{ crontab -l 2>/dev/null | grep -v "meme_generator_auto_update"; } | crontab -
return $?' F

  run_mutation "read_current_crontab 把「非零」一律当成「没有 crontab」（fail-open）" \
  'if [ -s "${err_tmp}" ] && grep -qi '"'"'no crontab for'"'"' "${err_tmp}"; then' 'if true; then' F

  run_mutation "download_script 去掉版本一致性校验" \
  'if [ "${downloaded_version}" != "${SCRIPT_VERSION}" ]; then' 'if false; then' F

  run_mutation "setup_auto_update 关闭分支去掉两个「如实返回」（报错却返回 0）" \
  '      echo -e ${red}无法读取当前 crontab，未能确认自动更新任务是否已移除，请手动执行 crontab -e 检查${background}
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
    return 0' \
  '      echo -e ${red}无法读取当前 crontab，未能确认自动更新任务是否已移除，请手动执行 crontab -e 检查${background}
    elif [ "${cron_state}" -eq 0 ]; then
      if remove_meme_cron; then
        echo -e ${yellow}已关闭meme生成器的自动更新${background}
      else
        echo -e ${red}移除自动更新任务失败，请手动执行 crontab -e 检查${background}
      fi
    fi
    return 0' F

  if [ "${RUN_GIT}" = "1" ]; then
    run_mutation "git_update 改用 reset --soft" \
    'git reset --hard "origin/${branch}"' 'git reset --soft "origin/${branch}"' G
  else
    echo "  SKIP   - git_update 变异（--fast 已跳过 git 组）"
  fi

  echo
  echo "VARIANT: caught=${MUT_OK} missed=${MUT_BAD}"
fi

echo
if [ "${NORMAL_RC}" -eq 0 ] && [ "${MUT_BAD}" -eq 0 ]; then
  echo "RESULT: PASS  (日志: ${LOG})"
  exit 0
fi
echo "RESULT: FAIL（正常用例 rc=${NORMAL_RC}，未被抓住的变异=${MUT_BAD}；日志: ${LOG}）"
exit 1
