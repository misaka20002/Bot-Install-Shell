#!/usr/bin/env bash
set -o pipefail
exec 0</dev/null
if [ "${1:-}" != --worker ]; then
    command -v timeout >/dev/null || exit 2
    timeout 0.1 sleep 2
    [ "$?" -eq 124 ] || exit 2
    timeout 30 bash "$0" --worker
    exit $?
fi
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd) || exit 2
work=$(mktemp -d) || exit 2
trap 'rm -rf -- "$work"' EXIT
log=${LOG_FILE:-/tmp/sys-clash-test.$$.log}
: > "$log" || exit 2
sed -n '/^clash_env_ready()/,/^# 主菜单函数/{ /^# 主菜单函数/d; p; }' "$repo/Manage/SYS_Manage.sh" > "$work/functions.sh"
bash -n "$work/functions.sh" || exit 2
source "$work/functions.sh"
export HOME="$work/home"
fixture="$HOME/custom clash"
mkdir -p "$fixture/scripts/"{lib,cmd} "$fixture/bin"
printf ':\n' > "$fixture/.env"
printf ':\n' > "$fixture/scripts/lib/common.sh"
for bin in yq mihomo; do printf '#!/bin/sh\nexit 0\n' > "$fixture/bin/$bin"; chmod +x "$fixture/bin/$bin"; done
cat > "$fixture/scripts/cmd/clashctl.sh" <<'CMD'
. "$CLASHCTL_HOME/.env" || return 1
. "$CLASHCTL_HOME/scripts/lib/common.sh" || return 1
BIN_YQ="$CLASHCTL_HOME/bin/yq"
BIN_KERNEL="$CLASHCTL_HOME/bin/mihomo"
for name in on off status ui secret sub tun mixin upgrade; do
    eval "clash$name() { :; }"
done
service_is_active() { return 0; }
tunstatus() { return 1; }
clashctl() { printf '%s\n' "$*" >> "$TEST_CALLS"; return "${CLASH_TEST_RC:-0}"; }
CMD
TEST_CALLS="$work/calls"
printf 'return\nexport CLASHCTL_HOME="$HOME/custom clash"\n. $CLASHCTL_HOME/scripts/cmd/clashctl.sh\ntouch "%s/should-not-run"\n' "$work" > "$HOME/.bashrc"
# No real service, network, install, or configuration changes.
git() { return 91; }
curl() { return 91; }
systemctl() { return 1; }
ip() { return 1; }
pause() { :; }
pass=0 fail=0
check() {
    if "$@"; then pass=$((pass+1)); printf 'OK: %s\n' "$*" | tee -a "$log"
    else fail=$((fail+1)); printf 'FAIL: %s\n' "$*" | tee -a "$log"; fi
}
clashctl() { return 99; }
unset CLASHCTL_HOME BIN_YQ BIN_KERNEL
check load_clash_env
check test "$CLASHCTL_HOME" = "$fixture"
check test ! -e "$work/should-not-run"
chmod -x "$fixture/bin/yq"
clash_env_ready; rc=$?
check test "$rc" -ne 0
chmod +x "$fixture/bin/yq"
check clash_env_ready
menu() { : > "$TEST_CALLS"; manage_clash > "$work/menu" 2>&1 <<< "$1"; }
menu $'6\n0'
check grep -qx node "$TEST_CALLS"
CLASH_TEST_RC=7
menu $'6\n0'
check grep -q '节点选择未完成' "$work/menu"
menu $'8\non\n0'
check grep -qx 'tun on' "$TEST_CALLS"
check grep -q 'Tun 模式切换失败' "$work/menu"
if grep -q 'Tun 模式已成功切换' "$work/menu"; then check false; else check true; fi
unset CLASH_TEST_RC
for op in on off; do
    menu $'8\n'"$op"$'\n0'
    check grep -qx "tun $op" "$TEST_CALLS"
    check grep -q 'Tun 模式已成功切换' "$work/menu"
done
menu $'7\n3\n0'
check grep -qx 'sub update --all' "$TEST_CALLS"
menu $'7\n2\nhttps://example.test/sub?a=1&b=2\n0'
check grep -Fxq 'sub add https://example.test/sub?a=1&b=2' "$TEST_CALLS"
menu $'9\ny\na b\\c\n0'
check grep -Fxq 'secret a b\c' "$TEST_CALLS"
load_clash_env() { return 1; }
clash_env_ready() { return 1; }
menu $'6\n0'
check grep -q 'source ~/.bashrc' "$work/menu"
check test ! -s "$TEST_CALLS"
printf 'TOTAL: pass=%s fail=%s\n' "$pass" "$fail" | tee -a "$log"
[ "$fail" -eq 0 ]
