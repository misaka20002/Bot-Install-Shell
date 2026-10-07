#!/usr/bin/env bash
set -o pipefail
exec 0</dev/null

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd) || exit 2
SOURCE=${INSTALL_SOURCE:-"$ROOT/install.sh"}
TIMEOUT=$(command -v timeout) || exit 2
CHMOD_BIN=$(command -v chmod) || exit 2
"$TIMEOUT" 0.1 bash -c 'sleep 5'
if [ "$?" -ne 124 ]; then
    echo '错误：timeout 无法终止超时进程。' >&2
    exit 2
fi
WORK=$(mktemp -d) || exit 2
trap 'rm -rf -- "$WORK"' EXIT
if [ "$#" -eq 2 ] && [ "$1" = --log ]; then
    LOG_FILE=$2
    KEEP_LOG=true
elif [ "$#" -eq 0 ]; then
    LOG_FILE=$(mktemp /tmp/install-test.XXXXXX.log) || exit 2
    KEEP_LOG=false
else
    echo '用法：bash tests/install/run.sh [--log FILE]' >&2
    exit 2
fi
: > "$LOG_FILE" || exit 2
echo "日志：$LOG_FILE"

# 仅抽取依赖函数和安装调用链，不执行生产脚本的顶层代码或真实下载。
tr -d '\r' < "$SOURCE" > "$WORK/source.sh" || exit 2
awk '/^function Dependency\(\)/ {copy=1} /^function SystemCheck\(\)/ {copy=0} copy' \
    "$WORK/source.sh" > "$WORK/harness.sh"
cat >> "$WORK/harness.sh" <<'BASH'
SystemCheck() { :; }
sleep() { :; }
Script_Install() { printf 'download\n' >> "$INSTALL_LOG"; }
if [ "$1" = dependency ]; then
    Dependency
    exit "$?"
fi
yn='同意安装'
BASH
awk '/^if \[  "\$\{yn\}" == "同意安装" \]/ {copy=1} copy' \
    "$WORK/source.sh" >> "$WORK/harness.sh"
bash -n "$WORK/harness.sh" || exit 2
grep -q '^function Dependency()' "$WORK/harness.sh" || exit 2
grep -q '^if \[  "${yn}" == "同意安装" \]' "$WORK/harness.sh" || exit 2

pass=0
fail=0
case_id=0
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
fixture() {
    case_id=$((case_id + 1))
    FIXTURE_BIN="$WORK/case-$case_id/bin"
    PACKAGE_LOG="$WORK/case-$case_id/packages.log"
    INSTALL_LOG="$WORK/case-$case_id/install.log"
    mkdir -p "$FIXTURE_BIN" || exit 2
    : > "$PACKAGE_LOG"
    : > "$INSTALL_LOG"
    PACKAGE_MODE=success
}
fake_command() {
    printf '#!%s\nexit 0\n' "$BASH" > "$FIXTURE_BIN/$1"
    chmod +x "$FIXTURE_BIN/$1" || exit 2
}
fake_manager() {
    printf '#!%s\n' "$BASH" > "$FIXTURE_BIN/$1"
    cat >> "$FIXTURE_BIN/$1" <<'BASH'
printf '%s\n' "$*" >> "$PACKAGE_LOG"
case "$PACKAGE_MODE" in
    fail) exit 7 ;;
    missing) exit 0 ;;
esac
for package in "$@"; do
    case "$package" in
        dialog|curl)
            printf '#!%s\nexit 0\n' "$BASH" > "$FIXTURE_BIN/$package"
            "$CHMOD_BIN" +x "$FIXTURE_BIN/$package" || exit 8
            ;;
    esac
done
if [ "$PACKAGE_MODE" = fail_after_install ]; then
    exit 7
fi
BASH
    chmod +x "$FIXTURE_BIN/$1" || exit 2
}
run_case() {
    # PATH 只有本轮创建的假命令，生产代码不可能调用真实包管理器或 curl。
    PATH="$FIXTURE_BIN" FIXTURE_BIN="$FIXTURE_BIN" PACKAGE_LOG="$PACKAGE_LOG" \
        INSTALL_LOG="$INSTALL_LOG" PACKAGE_MODE="$PACKAGE_MODE" CHMOD_BIN="$CHMOD_BIN" \
        "$TIMEOUT" 5 "$BASH" "$WORK/harness.sh" "${1:-dependency}" \
        > "$WORK/output" 2>&1
    rc=$?
    if [ "$rc" -eq 124 ]; then
        report 1 '用例超时'
        exit 1
    fi
}

fixture
fake_command whiptail
fake_command curl
fake_manager apt
run_case entry
[ "$rc" -eq 0 ] && [ -x "$FIXTURE_BIN/dialog" ] && \
    [ "$(cat "$PACKAGE_LOG")" = 'install -y dialog' ] && [ -s "$INSTALL_LOG" ]
report "$?" '只有 whiptail 时补装 dialog，成功后继续安装脚本'

fixture
fake_command dialog
fake_command curl
fake_manager apt
run_case entry
[ "$rc" -eq 0 ] && [ ! -s "$PACKAGE_LOG" ] && [ -s "$INSTALL_LOG" ]
report "$?" '依赖齐全时不调用包管理器，直接继续安装'

fixture
fake_command dialog
fake_manager apt
run_case
[ "$rc" -eq 0 ] && [ "$(cat "$PACKAGE_LOG")" = 'install -y curl' ]
report "$?" '只缺 curl 时仅安装 curl'

for manager in apt dnf yum pacman apk; do
    fixture
    fake_manager "$manager"
    run_case
    case "$manager" in
        pacman) expected='-S --noconfirm --needed dialog curl' ;;
        apk) expected='add dialog curl' ;;
        *) expected='install -y dialog curl' ;;
    esac
    [ "$rc" -eq 0 ] && [ -x "$FIXTURE_BIN/dialog" ] && [ -x "$FIXTURE_BIN/curl" ] && \
        [ "$(cat "$PACKAGE_LOG")" = "$expected" ]
    report "$?" "$manager 一次补齐缺少的两项依赖"
done

fixture
fake_command whiptail
fake_command curl
fake_manager apt
PACKAGE_MODE=fail
run_case
[ "$rc" -eq 1 ] && [ -s "$PACKAGE_LOG" ]
report "$?" '包安装失败时 Dependency 如实返回失败'
run_case entry
[ "$rc" -eq 1 ] && [ ! -s "$INSTALL_LOG" ] && grep -q '已中止安装脚本' "$WORK/output"
report "$?" '依赖失败后入口中止，不继续下载脚本'

fixture
fake_manager apt
PACKAGE_MODE=fail_after_install
run_case
[ "$rc" -eq 1 ] && [ -x "$FIXTURE_BIN/dialog" ] && [ -x "$FIXTURE_BIN/curl" ]
report "$?" '包管理器返回失败时，即使命令已出现也不能误报成功'

fixture
fake_manager apt
PACKAGE_MODE=missing
run_case entry
[ "$rc" -eq 1 ] && [ ! -s "$INSTALL_LOG" ] && grep -q '安装后仍未找到' "$WORK/output"
report "$?" '包管理器报成功但命令缺失时仍中止'

fixture
run_case entry
[ "$rc" -eq 1 ] && [ ! -s "$INSTALL_LOG" ] && grep -q '未找到支持的系统包管理器' "$WORK/output"
report "$?" '缺少包管理器时明确失败，不继续下载'

printf 'TOTAL: pass=%s fail=%s\n' "$pass" "$fail"
printf 'TOTAL: pass=%s fail=%s\n' "$pass" "$fail" >> "$LOG_FILE" || exit 2
if [ "$fail" -eq 0 ] && [ "$KEEP_LOG" = false ]; then
    rm -f -- "$LOG_FILE"
fi
[ "$fail" -eq 0 ]
