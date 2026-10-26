#!/usr/bin/env bash
# 云崽日志清理（cleanup_yunzai_logs）：只删 command.<日期>.log[.zst|.gz] 中日期早于「今天-6」的文件；
# error.log 原地清空且文件仍在；白名单之外的文件、目录、符号链接一律不动。
# 日期只看文件名：今天的文件即使 mtime 是 40 天前也保留，30 天前的文件即使刚写入也删除。
set -o pipefail
exec 0</dev/null

# 三条硬保证（docs/验证方式.md）：stdin 立即 EOF、整体套 timeout、每条断言即时落盘
if [ "${1:-}" != --worker ]; then
    command -v timeout >/dev/null || { echo "缺少 timeout，拒绝运行（无法保证不卡死）" >&2; exit 2; }
    timeout 0.1 sleep 2
    [ "$?" -eq 124 ] || { echo "timeout 无法终止超时进程，拒绝运行" >&2; exit 2; }
    timeout "${HARNESS_TIMEOUT:-300}" bash "$0" --worker "$@"
    rc=$?
    [ "$rc" -ne 124 ] || echo "超时（HARNESS_TIMEOUT=${HARNESS_TIMEOUT:-300}s），可能有死循环" >&2
    exit "$rc"
fi
shift
ROOT=$(cd "$(dirname "$0")/../.." && pwd) || exit 2
LOG_FILE=''
USER_LOG=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --log)
            [ "$#" -ge 2 ] || { echo "--log 需要参数" >&2; exit 2; }
            LOG_FILE=$2
            USER_LOG=1
            shift 2
            ;;
        *)
            echo "未知参数：$1" >&2
            exit 2
            ;;
    esac
done
[ -n "$LOG_FILE" ] || LOG_FILE=/tmp/sys-yunzai-logs-test.$$.log
: > "$LOG_FILE" || { echo "日志不可写：$LOG_FILE" >&2; exit 2; }

# 允许指向副本：手工反例自证（把 truncate 改成 rm 等）时不要动生产文件
SOURCE=${SYS_MANAGE_SOURCE:-"$ROOT/Manage/SYS_Manage.sh"}
source <(sed -n '/^cleanup_run()/,/^# 系统垃圾清理函数/p' "$SOURCE" | tr -d '\r' | sed '$d')
for fn in cleanup_run cleanup_log_date cleanup_human_size cleanup_yunzai_logs cleanup_dev_environment; do
    declare -F "$fn" >/dev/null || { echo "缺少函数 $fn" >&2; exit 1; }
done

# 宿主若是把 TMPDIR 设成 Windows 路径，mktemp 会返回 C:\...\Temp/...，本机的 rm 包装
# 会以「embedded drive prefix」拒绝删除（目标环境没有这层包装）。统一落到 /tmp 的 POSIX 路径。
unset TMPDIR
WORK=$(mktemp -d) || exit 1
trap 'rm -rf -- "$WORK"' EXIT
export HOME="$WORK/home"
case "$HOME" in
    "$WORK"/*) ;;
    *) echo "HOME 未隔离到临时目录，拒绝运行" >&2; exit 2 ;;
esac

today=$(date +%Y-%m-%d)
d6=$(date -d '6 days ago' +%Y-%m-%d) || exit 1
d7=$(date -d '7 days ago' +%Y-%m-%d) || exit 1
d30=$(date -d '30 days ago' +%Y-%m-%d) || exit 1
trss="$HOME/TRSS-Yunzai/logs"
miao="$HOME/Miao-Yunzai/logs"
mkdir -p "$trss/command.$d30.log.d" "$WORK/outside" || exit 1

printf 'old' > "$trss/command.$d30.log" || exit 1
printf 'old' > "$trss/command.$d7.log.zst" || exit 1
printf 'old' > "$trss/command.$d30.log.gz" || exit 1
printf 'keep' > "$trss/command.$d6.log" || exit 1
printf 'keep' > "$trss/command.$today.log" || exit 1
printf 'keep' > "$trss/command.log" || exit 1
printf 'keep' > "$trss/miao-plugin.log" || exit 1
printf 'keep' > "$trss/command.$d30.log.bak" || exit 1
printf 'keep' > "$trss/command.2026-02-30.log" || exit 1
printf 'error-body' > "$trss/error.log" || exit 1
printf 'outside' > "$WORK/outside/target.log" || exit 1
# 今天的日志故意改成很旧的 mtime：证明判据是文件名日期，不是 mtime
touch -t "$(date -d '40 days ago' +%Y%m%d%H%M)" "$trss/command.$today.log" || exit 1
# 硬链接跟着 error.log 指向同一个 inode：只有原地 truncate 才会一起变空
HARD=0
ln "$trss/error.log" "$WORK/error.hard" 2>/dev/null && HARD=1
# 符号链接只在真的建出来时才断言（Windows 上 ln -s 常退化成复制或直接失败）
LINK=0
ln -s "$WORK/outside/target.log" "$trss/command.$d30.log.zst" 2>/dev/null && [ -L "$trss/command.$d30.log.zst" ] && LINK=1

pass=0 fail=0
check() {
    local name=$1 line
    shift
    if "$@"; then
        pass=$((pass + 1))
        line="OK: $name"
    else
        fail=$((fail + 1))
        line="FAIL: $name"
    fi
    printf '%s\n' "$line"
    printf '%s\n' "$line" >> "$LOG_FILE"
}
check_out() {
    case "$out" in
        *"$1"*) check "$2" true ;;
        *) check "$2" false ;;
    esac
}

inode_before=$(stat -c %i -- "$trss/error.log")
out=$(cleanup_yunzai_logs 2>&1)
rc=$?
inode_after=$(stat -c %i -- "$trss/error.log" 2>/dev/null)
check "返回 0" test "$rc" -eq 0
check "30 天前的 .log 已删除" test ! -e "$trss/command.$d30.log"
check "7 天前的 .log.zst 已删除" test ! -e "$trss/command.$d7.log.zst"
check "30 天前的 .log.gz 已删除" test ! -e "$trss/command.$d30.log.gz"
check "6 天前的 .log 保留（7 天边界）" test -e "$trss/command.$d6.log"
check "今天的 .log 保留（mtime 更旧也不删）" test -e "$trss/command.$today.log"
check "无日期的 command.log 保留" test -e "$trss/command.log"
check "插件日志 miao-plugin.log 保留" test -e "$trss/miao-plugin.log"
check "command.<日期>.log.bak 保留" test -e "$trss/command.$d30.log.bak"
check "非法日期 2026-02-30 保留" test -e "$trss/command.2026-02-30.log"
check "同名目录不被删除" test -d "$trss/command.$d30.log.d"
check "error.log 仍存在" test -f "$trss/error.log"
check "error.log 已清空" test ! -s "$trss/error.log"
check "error.log inode 未变（原地清空，不是 rm 后重建）" test "$inode_before" = "$inode_after"
if [ "$HARD" -eq 1 ]; then
    check "硬链接一起变空（证明原地 truncate）" test ! -s "$WORK/error.hard"
else
    printf 'SKIP: 本机不支持硬链接，跳过 truncate 语义断言\n'
fi
if [ "$LINK" -eq 1 ]; then
    check "软链本身保留" test -L "$trss/command.$d30.log.zst"
    check "软链目标未被删除" test -e "$WORK/outside/target.log"
    case "$out" in
        *"将删除 3 个"*) check "计数不含软链（3 个真实文件）" true ;;
        *) check "计数不含软链（3 个真实文件）" false ;;
    esac
else
    printf 'SKIP: 本机 ln -s 不可用，跳过文件软链断言\n'
fi

# 失败路径：rm 失败要如实返回非零、继续处理 error.log；truncate 失败也要如实失败，
# 且绝不能用 `: > file` 兜底（那会以 root 重新创建 error.log，并把失败伪装成成功）。
# 桩只活在 $( ) 子 shell 里，不影响后面的用例。
printf 'old' > "$trss/command.$d30.log" || exit 1
out=$(rm() { return 1; }; cleanup_yunzai_logs 2>&1)
rc=$?
check "rm 失败时返回非零" test "$rc" -ne 0
check "rm 失败时文件仍在" test -e "$trss/command.$d30.log"
check_out "删除失败" "rm 失败有提示"
rm -f -- "$trss/command.$d30.log" || exit 1
printf 'error-body' > "$trss/error.log" || exit 1
out=$(truncate() { return 1; }; cleanup_yunzai_logs 2>&1)
rc=$?
check "truncate 失败时返回非零" test "$rc" -ne 0
check "truncate 失败时 error.log 仍在" test -f "$trss/error.log"
check "truncate 失败时内容没被清掉（没走 : > 兜底）" test -s "$trss/error.log"
check_out "清空失败" "truncate 失败有提示"

# 第二个 bot：目录存在但没有 error.log —— 只清旧日志，绝不新建 error.log
mkdir -p "$miao" || exit 1
printf 'old' > "$miao/command.$d30.log" || exit 1
out=$(cleanup_yunzai_logs 2>&1)
rc=$?
check "Miao 旧日志已删除" test ! -e "$miao/command.$d30.log"
check "缺失的 error.log 不被创建" test ! -e "$miao/error.log"
check_out "error.log 不存在" "提示 error.log 不存在"

# logs 目录本身是符号链接：整体跳过，目标目录里的文件一个都不能少
# Windows 上 ln -s 需要开发者权限，改用目录 junction 代替（MSYS 里同样满足 [ -L ]）
link_dir() {
    ln -s "$1" "$2" 2>/dev/null && [ -L "$2" ] && return 0
    if [ -d "$1" ] && command -v cygpath >/dev/null 2>&1; then
        cmd //c mklink //J "$(cygpath -w "$2")" "$(cygpath -w "$1")" >/dev/null 2>&1 && [ -L "$2" ] && return 0
    fi
    return 1
}
rm -rf -- "$miao" || exit 1
printf 'old' > "$WORK/outside/command.$d30.log" || exit 1
if link_dir "$WORK/outside" "$miao"; then
    out=$(cleanup_yunzai_logs 2>&1)
    check "logs 是软链时跳过（文件保留）" test -e "$WORK/outside/command.$d30.log"
    check_out "符号链接" "提示符号链接"
else
    printf 'SKIP: 本机无法创建链接，跳过目录软链用例\n'
fi

# 接线：走 cleanup_dev_environment 的 y 路径，必须真的调用日志清理。
# 其余步骤全部 stub（pnpm/apt/journal/docker/find/Hapi/临时目录），不碰系统。
pnpm() { return 0; }
npm() { return 0; }
apt-get() { return 0; }
journalctl() { return 0; }
docker() { printf 'REPOSITORY\n'; return 0; }
find() { return 0; }
df() { printf 'Avail\n1000\n'; }
cleanup_hapi_candidates() { return 1; }
cleanup_confirm_dirs() { return 0; }
printf 'old' > "$trss/command.$d30.log" || exit 1
printf 'error-body' > "$trss/error.log" || exit 1
out=$(cleanup_dev_environment <<< y 2>&1)
rc=$?
check "y 路径返回 0" test "$rc" -eq 0
check "y 路径真的删了旧日志（接线）" test ! -e "$trss/command.$d30.log"
check "y 路径清空了 error.log" test ! -s "$trss/error.log"
check_out "清理云崽日志" "y 路径输出云崽日志步骤"

# 取消确认后不得进入任何清理步骤
cleanup_run() { echo '意外清理' >&2; return 99; }
printf 'old' > "$trss/command.$d30.log" || exit 1
cleanup_dev_environment <<< n >/dev/null || exit 1
check "取消后不删日志" test -e "$trss/command.$d30.log"

printf 'TOTAL: pass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
[ "$USER_LOG" -eq 1 ] || rm -f -- "$LOG_FILE"
