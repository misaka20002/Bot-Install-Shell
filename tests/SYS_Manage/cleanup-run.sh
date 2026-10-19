#!/usr/bin/env bash
set -o pipefail
exec 0</dev/null
ROOT=$(cd "$(dirname "$0")/../.." && pwd) || exit 1
source <(sed -n '/^cleanup_run()/,/^# 系统垃圾清理函数/p' "$ROOT/Manage/SYS_Manage.sh" | tr -d '\r' | sed '$d')
declare -F cleanup_run >/dev/null || exit 1
cleanup_failed=0
cleanup_run 测试 true >/dev/null || exit 1
[ "$cleanup_failed" = 0 ] || exit 1
if cleanup_run 测试 false >/dev/null; then exit 1; fi
[ "$cleanup_failed" = 1 ] || exit 1
# 拒绝确认不得调用删除；所有命令都使用替身。
du() { return 0; }
rm() { echo '意外删除' >&2; return 99; }
cleanup_confirm_dirs /nonexistent <<< n || exit 1
# 菜单取消不得进入任何清理步骤。
df() { printf 'Avail\n1000\n'; }
cleanup_run() { echo '意外清理' >&2; return 99; }
cleanup_dev_environment <<< n >/dev/null || exit 1
echo 'TOTAL pass=4 fail=0'
