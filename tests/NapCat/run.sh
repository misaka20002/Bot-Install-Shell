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
WORK=$(mktemp -d) || exit 2
trap 'rm -rf -- "$WORK"' EXIT
if [ "$#" -eq 2 ] && [ "$1" = --log ]; then
    LOG_FILE=$2
    KEEP_LOG=true
elif [ "$#" -eq 0 ]; then
    LOG_FILE=$(mktemp /tmp/napcat-test.XXXXXX.log) || exit 2
    KEEP_LOG=false
else
    echo '用法：bash tests/NapCat/run.sh [--log FILE]' >&2
    exit 2
fi
: > "$LOG_FILE" || exit 2
printf '日志：%s\n' "$LOG_FILE"

# 只提取本次涉及的函数，绝不运行入口、安装系统依赖或启动真实 QQ。
tr -d '\r' < "$SOURCE" > "$WORK/source.sh" || exit 2
grep '^INSTALL_URL=' "$WORK/source.sh" > "$WORK/functions.sh" || exit 2
for name in read_qq_target_version download_napcat_installer install_NapCat \
    get_qq_target_version check_qq_update clear_version_cache; do
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

printf 'TOTAL: pass=%s fail=%s\n' "$pass" "$fail"
printf 'TOTAL: pass=%s fail=%s\n' "$pass" "$fail" >> "$LOG_FILE" || exit 2
if [ "$fail" -eq 0 ]; then
    $KEEP_LOG || rm -f -- "$LOG_FILE"
    exit 0
fi
exit 1
