#!/usr/bin/env bash
set -o pipefail
exec 0</dev/null

if [ "${1:-}" != --worker ]; then
    command -v timeout >/dev/null || exit 2
    timeout 0.1 sleep 2
    [ "$?" -eq 124 ] || exit 2
    timeout "${HARNESS_TIMEOUT:-30}" bash "$0" --worker "$@"
    rc=$?
    [ "$rc" -ne 124 ] || echo '错误：测试超时。' >&2
    exit "$rc"
fi
shift
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd) || exit 2
SOURCE=${NAPCAT_SOURCE:-"$ROOT/Manage/NapCat.sh"}
# TMPDIR 可能是 Windows 形式（C:\Users\...\Temp）：宿主包装的 rm 在这种路径上 fail-closed，
# EXIT trap 就删不掉 WORK。先归一成 POSIX 形式（同 docs/验证方式.md 的 2026-09-13 实测）。
if [ -n "${TMPDIR:-}" ] && command -v cygpath >/dev/null 2>&1; then
    TMPDIR=$(cygpath -u "$TMPDIR" 2>/dev/null) || TMPDIR=
    export TMPDIR
fi
WORK=$(mktemp -d) || exit 2
CACHE_FIXTURE=''
trap 'if [ -n "$CACHE_FIXTURE" ]; then rm -rf -- "$CACHE_FIXTURE"; fi; rm -rf -- "$WORK"' EXIT

# 参数：--only 只跑指定组（逗号分隔，默认全跑），--log 指定进度日志
ONLY=''
LOG_FILE=''
KEEP_LOG=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        --log)
            if [ "$#" -lt 2 ]; then
                echo '用法：bash tests/NapCat/run.sh [--only 组] [--log FILE]' >&2
                exit 2
            fi
            LOG_FILE=$2
            KEEP_LOG=true
            shift 2
            ;;
        --only)
            if [ "$#" -lt 2 ]; then
                echo '用法：bash tests/NapCat/run.sh [--only 组] [--log FILE]' >&2
                exit 2
            fi
            ONLY=$2
            shift 2
            ;;
        *)
            echo '用法：bash tests/NapCat/run.sh [--only version,cache] [--log FILE]' >&2
            exit 2
            ;;
    esac
done
if [ -z "$LOG_FILE" ]; then
    LOG_FILE=$(mktemp /tmp/napcat-test.XXXXXX.log) || exit 2
fi
: > "$LOG_FILE" || exit 2
printf '日志：%s\n' "$LOG_FILE"

# 组开关：不写 --only 就是全跑。组的划分见文件末尾的 version / cache 两段。
want_group() {
    [ -z "$ONLY" ] && return 0
    case ",$ONLY," in
        *",$1,"*) return 0 ;;
    esac
    return 1
}

# 只提取本次涉及的函数，绝不运行入口、安装系统依赖或启动真实 QQ。
tr -d '\r' < "$SOURCE" > "$WORK/source.sh" || exit 2
grep '^INSTALL_URL=' "$WORK/source.sh" > "$WORK/functions.sh" || exit 2
for name in read_qq_target_version download_napcat_installer install_NapCat \
    get_qq_target_version check_qq_update clear_version_cache \
    format_size_kb format_timestamp cache_dir_stats napcat_logs_dir \
    napcat_cache_targets napcat_cache_total_kb cache_pending_stat cache_delete_entries \
    print_napcat_cache_overview clean_napcat_cache; do
    grep -q "^${name}() {" "$WORK/source.sh" || exit 2
    awk -v start="${name}() {" '$0 == start {copy=1} copy {print} copy && /^}$/ {exit}' \
        "$WORK/source.sh" >> "$WORK/functions.sh" || exit 2
done
bash -n "$WORK/functions.sh" || exit 2
source "$WORK/functions.sh"
export TMPDIR="$WORK/tmp"
mkdir -p "$TMPDIR" "$WORK/cwd" || exit 2
cd "$WORK/cwd" || exit 2
export TEST_EXEC_LOG="$WORK/executed"
export TEST_INSTALL_RC=0
CURL_LOG="$WORK/curl.log"
INIT_LOG="$WORK/init.log"
red='' green='' yellow='' cyan='' background=''
APP_NAME=NapCat
NAPCAT_CMD='fixture-qq'

cat > "$WORK/valid.sh" <<'BASH'
#!/bin/bash
function install_linuxqq_rootless() { :; }
linuxqq_target_version="3.2.32-52194"
printf '%s\n' "$linuxqq_target_version" >> "$TEST_EXEC_LOG"
exit "$TEST_INSTALL_RC"
BASH
sed 's/3.2.32-52194/3.2.20-40990/' "$WORK/valid.sh" > "$WORK/older.sh"
sed 's/3.2.32-52194/unknown/' "$WORK/valid.sh" > "$WORK/bad-version.sh"
sed '/^linuxqq_target_version=/d' "$WORK/valid.sh" > "$WORK/no-version.sh"
sed '/^function install_linuxqq_rootless/d' "$WORK/valid.sh" > "$WORK/no-marker.sh"
cp "$WORK/valid.sh" "$WORK/bad-syntax.sh"
printf 'if then\n' >> "$WORK/bad-syntax.sh"
printf 'The content may contain violation information\n' > "$WORK/error-page.sh"
: > "$WORK/empty.sh"

# 所有网络、包管理与进程操作都有桩；下载到的也只能是上面的无害夹具。
curl() {
    local output='' url='' arg previous='' safe=false
    local has_connect=false has_max=false has_retry=false
    for arg in "$@"; do
        case "$previous" in
            --output|-o) output=$arg ;;
        esac
        case "$arg" in
            -fLsS) safe=true ;;
            --connect-timeout) has_connect=true ;;
            --max-time) has_max=true ;;
            --retry) has_retry=true ;;
            https://*) url=$arg ;;
        esac
        previous=$arg
    done
    printf '%s\n' "$url" >> "$CURL_LOG"
    if ! $safe || ! $has_connect || ! $has_max || ! $has_retry ||
        [[ "$output" != "$TMPDIR/"* ]]; then
        printf '下载参数或临时路径不安全\n' >&2
        return 97
    fi
    local response
    case "$url" in
        https://raw.githubusercontent.com/NapNeko/NapCat-Installer/main/script/install.sh)
            response=$DIRECT_RESPONSE ;;
        https://gh-proxy.com/https://raw.githubusercontent.com/NapNeko/NapCat-Installer/main/script/install.sh)
            response=$MIRROR_RESPONSE ;;
        *) return 98 ;;
    esac
    case "$response" in
        timeout) return 28 ;;
        http-error) cp "$WORK/error-page.sh" "$output"; return 22 ;;
        partial) cp "$WORK/valid.sh" "$output"; return 18 ;;
        *) cp "$WORK/$response.sh" "$output" ;;
    esac
}
apt() { return 0; }
yum() { return 0; }
dnf() { return 0; }
pacman() { return 0; }
check_installed() { return 1; }
check_running() { return 1; }
stop_NapCat() { return 99; }
check_tmux() { return 0; }
tmux() { printf '%s\n' "$*" >> "$INIT_LOG"; }
sleep() { :; }

pass=0 fail=0
report() {
    local status=$1 message=$2
    if [ "$status" -eq 0 ]; then
        pass=$((pass + 1))
        message="OK - $message"
    else
        fail=$((fail + 1))
        message="NOT OK - $message"
    fi
    printf '%s\n' "$message"
    printf '%s\n' "$message" >> "$LOG_FILE" || exit 2
}
reset_case() {
    DIRECT_RESPONSE=valid
    MIRROR_RESPONSE=valid
    TEST_INSTALL_RC=0
    VERSION_INFO_CACHED=true
    : > "$CURL_LOG"
    : > "$TEST_EXEC_LOG"
    : > "$INIT_LOG"
}
no_temporary_files() {
    [ -z "$(find "$TMPDIR" -mindepth 1 -print -quit)" ]
}

if want_group version; then

reset_case
actual=$(get_qq_target_version); rc=$?
[ "$rc" -eq 0 ] && [ "$actual" = 3.2.32-52194 ] &&
    [ "$(wc -l < "$CURL_LOG")" -eq 1 ] && [ ! -s "$TEST_EXEC_LOG" ] && no_temporary_files
report "$?" '直连读取目标版本，不执行远端脚本，清理临时文件'

for response in timeout http-error partial empty error-page bad-syntax bad-version no-version no-marker; do
    reset_case
    DIRECT_RESPONSE=$response
    actual=$(get_qq_target_version); rc=$?
    [ "$rc" -eq 0 ] && [ "$actual" = 3.2.32-52194 ] &&
        [ "$(wc -l < "$CURL_LOG")" -eq 2 ] && [ ! -s "$TEST_EXEC_LOG" ] && no_temporary_files
    report "$?" "直连返回 $response 时切换镜像"
done

for response in timeout http-error partial empty error-page bad-syntax bad-version no-version no-marker; do
    reset_case
    DIRECT_RESPONSE=$response
    MIRROR_RESPONSE=$response
    actual=$(get_qq_target_version); rc=$?
    [ "$rc" -ne 0 ] && [ -z "$actual" ] && [ ! -s "$TEST_EXEC_LOG" ] && no_temporary_files
    report "$?" "两个来源均返回 $response 时如实失败、不使用旧版本兜底"
done

reset_case
actual=$(check_qq_update 3.2.25-45758)
[ "$actual" = '[可更新到 3.2.32-52194]' ]
report "$?" '目标版本更高时提示更新'
actual=$(check_qq_update 3.2.32-52194)
[ "$actual" = '[最新]' ]
report "$?" '目标版本相同时显示最新'
DIRECT_RESPONSE=older
actual=$(check_qq_update 3.2.25-45758)
[ "$actual" = '[可更新到 3.2.20-40990]' ]
report "$?" '上游目标降级时仍提示更新'

reset_case
DIRECT_RESPONSE=timeout
MIRROR_RESPONSE=timeout
actual=$(check_qq_update 3.2.25-45758)
[ "$actual" = '[无法检查更新]' ]
report "$?" '查询失败显示无法检查更新'
for current in 未安装 未知; do
    : > "$CURL_LOG"
    actual=$(check_qq_update "$current")
    [ "$actual" = '[需要安装]' ] && [ ! -s "$CURL_LOG" ]
    report "$?" "$current 保持需要安装提示，无需查询"
done

# 原来的固定文件名不能再被覆盖或删除。
printf '用户自己的文件\n' > napcat.sh
reset_case
DIRECT_RESPONSE=timeout
install_NapCat > "$WORK/output" 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ "$(cat "$TEST_EXEC_LOG")" = 3.2.32-52194 ] &&
    [ "$(wc -l < "$CURL_LOG")" -eq 2 ] && [ -s "$INIT_LOG" ] &&
    [ "$VERSION_INFO_CACHED" = false ] && grep -q 'NapCat安装完成' "$WORK/output" && no_temporary_files
report "$?" '安装复用镜像兜底，执行成功后初始化并清除缓存'
[ "$(cat napcat.sh)" = '用户自己的文件' ]
report "$?" '安装不覆盖或删除当前目录已有的 napcat.sh'

reset_case
DIRECT_RESPONSE=older
install_NapCat > "$WORK/output" 2>&1; rc=$?
[ "$rc" -eq 0 ] && [ "$(cat "$TEST_EXEC_LOG")" = 3.2.20-40990 ] && no_temporary_files
report "$?" '安装允许执行上游提供的较低目标版本'

reset_case
TEST_INSTALL_RC=7
install_NapCat > "$WORK/output" 2>&1; rc=$?
[ "$rc" -ne 0 ] && [ -s "$TEST_EXEC_LOG" ] && [ ! -s "$INIT_LOG" ] &&
    [ "$VERSION_INFO_CACHED" = false ] && grep -q '安装脚本执行失败' "$WORK/output" &&
    ! grep -q 'NapCat安装完成' "$WORK/output" && no_temporary_files
report "$?" '安装脚本执行失败时中止，不初始化或宣告成功'

for response in timeout error-page bad-syntax no-version; do
    reset_case
    DIRECT_RESPONSE=$response
    MIRROR_RESPONSE=$response
    install_NapCat > "$WORK/output" 2>&1; rc=$?
    [ "$rc" -ne 0 ] && [ ! -s "$TEST_EXEC_LOG" ] && [ ! -s "$INIT_LOG" ] &&
        grep -q '下载安装脚本失败或内容校验未通过' "$WORK/output" &&
        ! grep -q 'NapCat安装完成' "$WORK/output" && no_temporary_files
    report "$?" "安装下载遇到 $response 时中止并清理临时文件"
done

fi # version 组

if want_group cache; then

# ---------------------------------------------------------------------------
# QQ 缓存 / NapCat 日志：查看与清理（决策见 docs/adr/0001-napcat-cache-cleanup.md）
# 夹具放在 /tmp：本组会真的删文件，不能落在只读断言用的 cwd 里。
# 本组三条性能约定（Win/MSYS 上 fork ≈0.25s、rm -rf 走安全网关 ≈3.7s）：
#   · 断言只用内建：case/[[ ]] 匹配变量、$(<file) 读输出、mapfile 数行，
#     不用 grep -c / wc / basename 这类每个都起一个进程的写法
#   · 夹具由 mktemp 新建即为空，除 EXIT trap 外不做 rm -rf
#   · 只有主流程遍历完整 9 个目录，校验类用例用最小夹具
# ---------------------------------------------------------------------------
CACHE_FIXTURE=$(mktemp -d "${CACHE_TMP_ROOT:-/tmp}/napcat-cache.XXXXXX") || exit 2
CACHE_A="$CACHE_FIXTURE/qq/nt_qq_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
CACHE_B="$CACHE_FIXTURE/qq/nt_qq_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
CACHE_MIN="$CACHE_FIXTURE/min"
QQ_DATA_ROOT="$CACHE_FIXTURE/qq"
NAPCAT_BASE_DIR="$CACHE_FIXTURE/napcat"
NAPCAT_INSTALL_DIR="$CACHE_FIXTURE/install"
NAPCAT_WORKDIR=''
list_running_instances() { return 1; }
stop_all_instances() { return 0; }

cache_fixture() {
    # 目录一次建完（每次 mkdir 都是一个进程），文件用内建 printf 写入
    mkdir -p "$CACHE_A/nt_data/log" "$CACHE_A/nt_data/Pic/2026-01/Ori" \
        "$CACHE_A/nt_data/Pic/2026-01/Thumb" "$CACHE_A/nt_data/Ptt" \
        "$CACHE_A/nt_data/Video" "$CACHE_A/nt_data/File/Ori" \
        "$CACHE_B/nt_data/log" "$CACHE_FIXTURE/napcat/logs" \
        "$CACHE_FIXTURE/qq/NapCat/temp" "$CACHE_FIXTURE/elsewhere/pic"
    printf 'xxxx' > "$CACHE_A/nt_data/log/old.log"
    printf 'xxxx' > "$CACHE_A/nt_data/log/new.log"
    printf 'xxxx' > "$CACHE_A/nt_data/Pic/2026-01/Ori/a.jpg"
    printf 'xxxx' > "$CACHE_A/nt_data/Pic/2026-01/Thumb/a.thumb"
    printf 'xxxx' > "$CACHE_A/nt_data/Ptt/a.amr"
    printf 'xxxx' > "$CACHE_A/nt_data/Video/big.mp4"
    printf 'xxxx' > "$CACHE_A/nt_data/File/Ori/recv.zip"
    printf 'xxxx' > "$CACHE_B/nt_data/log/b.log"
    printf 'xxxx' > "$CACHE_FIXTURE/napcat/logs/a.log"
    printf 'xxxx' > "$CACHE_FIXTURE/qq/NapCat/temp/nt.tmp"
    printf 'yyyy' > "$CACHE_FIXTURE/elsewhere/pic/keep.jpg"
    touch -d '40 days ago' "$CACHE_A/nt_data/Pic/2026-01/Ori/a.jpg" \
        "$CACHE_A/nt_data/Pic/2026-01/Thumb/a.thumb" \
        "$CACHE_A/nt_data/Ptt/a.amr" "$CACHE_A/nt_data/File/Ori/recv.zip"
    # 账号 B 的 Pic 指向别处：只显示、不跟随（部分文件系统不支持，故用例可跳过）
    ln -s "$CACHE_FIXTURE/elsewhere/pic" "$CACHE_B/nt_data/Pic" 2>/dev/null
}

cache_has_target() {
    case "$1" in
        *"$2"*) return 0 ;;
    esac
    return 1
}

cache_fixture
targets=$(napcat_cache_targets)
mapfile -t target_lines <<< "$targets"
expected_lines=8
[ -L "$CACHE_B/nt_data/Pic" ] && expected_lines=9
[ "${#target_lines[@]}" -eq "$expected_lines" ] &&
    cache_has_target "$targets" 'qq|media|File|' &&
    cache_has_target "$targets" "|$CACHE_FIXTURE/qq/NapCat/temp" &&
    cache_has_target "$targets" "|$CACHE_FIXTURE/napcat/logs"
report "$?" '枚举账号缓存、NapCat/temp 与 logs，不碰其它目录'

# 符号链接只在真的建出来时才断言（Win 上 ln -s 常退化成复制或直接失败）
cache_link_ok=0
if [ -L "$CACHE_B/nt_data/Pic" ]; then
    cache_link_ok=1
    cache_has_target "$targets" 'qq|skip|Pic|'
    report "$?" '顶层目录是符号链接时标为 skip，不进入'
fi

[ "$(cache_pending_stat "$CACHE_A/nt_data/Pic" days 7)" = '8|2' ] &&
    [ "$(cache_pending_stat "$CACHE_A/nt_data/Pic" days 30)" = '8|2' ] &&
    [ "$(cache_pending_stat "$CACHE_A/nt_data/Pic" all 0)" = '8|2' ]
report "$?" '按 mtime 统计待删：7/30 天只算旧文件，全部口径算全部'

# 校验类用例只跑一次：保留天数 0 同时覆盖「非数字」之外的边界分支
mkdir -p "$CACHE_MIN/qq/nt_qq_0123456789abcdef0123456789abcdef/nt_data/Pic"
printf 'xxxx' > "$CACHE_MIN/qq/nt_qq_0123456789abcdef0123456789abcdef/nt_data/Pic/a.jpg"
CACHE_MIN_PIC="$CACHE_MIN/qq/nt_qq_0123456789abcdef0123456789abcdef/nt_data/Pic/a.jpg"
QQ_DATA_ROOT="$CACHE_MIN/qq"
NAPCAT_BASE_DIR="$CACHE_MIN/napcat"
printf '3\n0\n' | clean_napcat_cache > "$WORK/cache-bad.out" 2>&1
rc=$?
cache_bad_out=$(< "$WORK/cache-bad.out")
[ "$rc" -eq 1 ] && [ -e "$CACHE_MIN_PIC" ] &&
    case "$cache_bad_out" in *天数超出范围*) true ;; *) false ;; esac
report "$?" '自定义保留天数 0 被拒、返回非零且不删任何文件'
QQ_DATA_ROOT="$CACHE_FIXTURE/qq"
NAPCAT_BASE_DIR="$CACHE_FIXTURE/napcat"

printf '1\nn\ny\ny\n\n' | clean_napcat_cache > "$WORK/cache-clean.out" 2>&1
rc=$?
clean_out=$(< "$WORK/cache-clean.out")
[ "$rc" -eq 0 ] && case "$clean_out" in *未清干净*) false ;; *) true ;; esac
report "$?" '清理 7 天且不含 File 时如实返回 0，输出无「未清干净」'

[ ! -e "$CACHE_A/nt_data/Pic/2026-01/Ori/a.jpg" ] &&
    [ ! -e "$CACHE_A/nt_data/Pic/2026-01/Thumb/a.thumb" ] &&
    [ ! -d "$CACHE_A/nt_data/Pic/2026-01" ] &&
    [ -d "$CACHE_A/nt_data/Pic" ]
report "$?" '删旧文件、删空的日期目录、保留 Pic 目录自身（Thumb 一并覆盖）'

[ -e "$CACHE_A/nt_data/File/Ori/recv.zip" ] &&
    [ -e "$CACHE_A/nt_data/Video/big.mp4" ]
report "$?" 'File 回答 n 后保留；未超保留期的视频保留'

[ ! -e "$CACHE_A/nt_data/log/new.log" ] &&
    [ ! -e "$CACHE_A/nt_data/log/old.log" ] &&
    [ ! -e "$CACHE_FIXTURE/qq/NapCat/temp/nt.tmp" ] &&
    [ ! -e "$CACHE_FIXTURE/napcat/logs/a.log" ]
report "$?" 'log / NapCat 的 temp 与 logs 一律整清'

if [ "$cache_link_ok" -eq 1 ]; then
    [ -e "$CACHE_FIXTURE/elsewhere/pic/keep.jpg" ] && [ -L "$CACHE_B/nt_data/Pic" ]
    report "$?" '符号链接未被跟随删除'
fi

CACHE_TMP_QQ="$QQ_DATA_ROOT"
QQ_DATA_ROOT="$CACHE_FIXTURE/nonexistent"
NAPCAT_BASE_DIR="$CACHE_FIXTURE/nonexistent2"
printf '\n' | clean_napcat_cache > "$WORK/cache-none.out" 2>&1
rc=$?
cache_none_out=$(< "$WORK/cache-none.out")
[ "$rc" -eq 0 ] && case "$cache_none_out" in *未找到可清理的目录*) true ;; *) false ;; esac
report "$?" '无目录时提示未找到并按幂等成功返回'
QQ_DATA_ROOT="$CACHE_TMP_QQ"

fi # cache 组

printf 'TOTAL: pass=%s fail=%s\n' "$pass" "$fail"
printf 'TOTAL: pass=%s fail=%s\n' "$pass" "$fail" >> "$LOG_FILE" || exit 2
if [ "$fail" -eq 0 ]; then
    $KEEP_LOG || rm -f -- "$LOG_FILE"
    exit 0
fi
exit 1
