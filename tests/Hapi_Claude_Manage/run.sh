#!/usr/bin/env bash
# ============================================================
# tests/Hapi_Claude_Manage/run.sh
#   Manage/Hapi_Claude_Manage.sh 的回归测试（Codex / Claude 配置语义 + 凭据写入路径）
#
# 用法：
#   bash tests/Hapi_Claude_Manage/run.sh                  # 全量（A~I）
#   bash tests/Hapi_Claude_Manage/run.sh --only A,C       # 只跑指定分组（日常最常用）
#   bash tests/Hapi_Claude_Manage/run.sh --log /tmp/x.log # 指定进度日志（默认自动生成）
#
# 分组：
#   A last_refresh 真 RFC3339（格式 + 日历/时钟/时区范围）
#   B id_token 严格 JWT envelope（三段非空 / 严格 base64url-no-pad / plain object）
#   C auth_mode 解析优先级 + official / loadable 两级校验
#   D 写入器：官方登录路由保护（隐式模式、保留 provider id、experimental token、空 Key）
#   E 菜单 7：编辑器探测 / vim 参数 / 编辑器失败拦截 / mktemp / 信号清理
#   F 配置库旁路卡点（菜单 2 储存、菜单 3 新建、菜单 4 切换）
#   G 凭据权限（备份 0600）与预览脱敏
#   H 兼容性回归（既有校验 / 展示 / 菜单接线）
#   I 路由自动收敛（官方登录剥离并暂存第三方路由 / 第三方 base_url 自动恢复 / 保留 id 不动）
#
# 三条"绝不卡住"的保证（与 tests/meme_generator/run.sh 一致）：
#   1) harness 里 `exec 0< /dev/null`：漏写重定向的 read 立刻 EOF，不会永久阻塞；
#   2) harness 整体套 timeout（HARNESS_TIMEOUT，默认 300s）；本机没有可用 timeout 直接失败退出，
#      且能力探测会**真的超时一次**（要求 rc=124）；
#   3) 每条断言即时追加到 --log（追加写=不缓冲），被外部杀掉也能看出停在哪一步。
#
# 隔离（结构性保证，不靠"碰巧没跑到"）：
#   · HOME / TMPDIR 都指向本次运行的临时目录，被测脚本的全部配置路径随之落进去；
#   · harness 开头 fail-closed 校验 HOME 必须在本次运行的临时目录内，否则 exit 2；
#   · curl / tmux / crontab / systemctl / 防火墙 全部 stub；
#   · chmod 是"记录 + 透传"桩：既能断言 0600 真的被调用，又保留真实行为。
#
# ⚠️ 本套件**不做变异验证**（仓库约定：变异矩阵停用、耗时不划算）。
#    新增断言必须用**手工反例**自证：临时改坏对应生产代码 → 跑本组看到变红 → 改回。
# ============================================================
set -o pipefail

ONLY=""
LOG=""
while [ $# -gt 0 ]; do
  case "$1" in
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

# ---- 路径形式统一（关键，踩过）----
# MSYS 会转换**命令行参数**里的类 POSIX 路径，但**不转换环境变量**；而 Windows 原生 node 会把
# `/tmp/x` 解析成"当前盘符根 + tmp\x"（例如 E:\tmp\x），与 bash 眼里的 /tmp **不是同一位置**。
# 后果：夹具/配置被写到另一个目录 —— 正向用例整片变红，反向用例反而"假绿"。
# 规避：仓库路径与临时根目录统一用**盘符形式**（`C:/...`）。实测 mkdir / cp / rm / mktemp / chmod
# 与原生 node 都认这种形式，于是 bash 与被测脚本里的 node 指向同一份文件。
# 唯一的例外是 PATH：里面的目录必须是 POSIX 形式，否则 bash 找不到（见 prelude 的 BIN_DIR_POSIX）。
as_drive_path() {
  if command -v cygpath > /dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}
as_posix_path() {
  if command -v cygpath > /dev/null 2>&1; then cygpath -u "$1"; else printf '%s' "$1"; fi
}

SCRIPT_DIR=$(as_drive_path "$(cd "${SCRIPT_DIR}" && pwd)")
REPO_ROOT=$(as_drive_path "$(cd "${SCRIPT_DIR}/../.." && pwd)")
TARGET="${REPO_ROOT}/Manage/Hapi_Claude_Manage.sh"
[ -f "${TARGET}" ] || { echo "找不到被测脚本: ${TARGET}"; exit 2; }

# 被测脚本本身依赖 node；测试也要用它造夹具 / 扫描源码。
if ! command -v node > /dev/null 2>&1; then
  echo "缺少 node（被测脚本的 JSON/TOML 处理依赖它），无法运行本套件"
  exit 2
fi

# 默认 300s：慢盘/模拟文件系统（Windows 经 MSYS 跑）一次进程创建可达数百毫秒，会明显变慢，
# 但仍必须是**有限**上限。可用 HARNESS_TIMEOUT 覆盖。
HARNESS_TIMEOUT="${HARNESS_TIMEOUT:-300}"

# timeout 是硬前提：没有它就没有有界执行。缺了直接失败退出，不悄悄退化成"无限运行"。
if ! command -v timeout > /dev/null 2>&1; then
  echo "缺少 timeout（coreutils），无法保证测试有界执行；请安装 coreutils 或换一台机器跑"
  exit 2
fi
# 能力探测必须真的超时一次：只跑 `timeout 1 true` 证明不了它真会终止超时的子进程。
timeout 1 sh -c 'sleep 5' > /dev/null 2>&1
probe_rc=$?
if [ "${probe_rc}" -ne 124 ]; then
  echo "timeout 能力探测失败（期望超时返回 124，实得 ${probe_rc}），无法保证测试有界执行"
  exit 2
fi

# 临时根目录同样统一成盘符形式（理由见上面的路径统一说明）：
# 这样 HOME / TMPDIR / mktemp 出来的敏感临时文件，bash 与被测脚本里的 node 都指向同一处。
TMPBASE=$(as_drive_path "${TMPDIR:-/tmp}")
WORK=$(mktemp -d "${TMPBASE}/hapi_claude_regress.XXXXXX") || { echo "无法创建临时目录"; exit 2; }
WORK_POSIX=$(as_posix_path "${WORK}")

# 进度日志故意放 WORK 之外（WORK 会被 EXIT trap 整个删掉）；显式 --log 永不删，
# 默认日志成功时删、失败/超时/被杀一律保留现场。
LOG_IS_DEFAULT=0
if [ -z "${LOG}" ]; then
  LOG="${TMPBASE}/hapi_claude_manage_test.$$.log"
  LOG_IS_DEFAULT=1
fi
if ! : > "${LOG}" 2>/dev/null; then
  echo "进度日志不可写: ${LOG}（用 --log 指定一个可写路径）"
  exit 2
fi

cleanup() {
  local rc=$?
  if [ "${LOG_IS_DEFAULT}" = "1" ] && [ "${rc}" -eq 0 ]; then
    rm -f "${LOG}"
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

bounded() {   # $1 = 秒数；其余为命令
  local secs="$1"
  shift
  timeout "${secs}" "$@" < /dev/null
}

# ============================================================
# 1) 抽取：形状 = 颜色变量 + 全部函数定义
#    顶层守卫（Android/非 Linux 直接 exit）与末尾 mainloop 调用都不能进 harness；
#    按**内容锚点**定位，不要写死行号——脚本持续插函数，行号一漂就静默取错范围。
# ============================================================
extract_lib() {   # $1 = 源脚本
  awk '
    BEGIN { mode = "head" }
    mode == "head" {
      if ($0 ~ /^export (red|green|yellow|blue|purple|cyan|white|background)=/) print
      if ($0 ~ /^# 按任意键继续函数/) mode = "body"
      next
    }
    mode == "body" {
      if ($0 ~ /^# 主循环函数/) exit
      print
    }
  ' "$1" | tr -d '\r'
}

# ============================================================
# 2) harness 组件：预置 → 被测库 → 函数桩 → 断言
# ============================================================
cat > "${WORK}/prelude.sh" <<PRELUDE
# ---- 测试预置：HOME / TMPDIR 都在本次运行的临时目录内 ----
export HOME="${WORK}/home"
export WORK_DIR="${WORK}"
export FX_DIR="${WORK}/fx"
export TMPDIR="${WORK}/tmp"
export CHMOD_LOG="${WORK}/chmod.log"
export BIN_DIR="${WORK}/bin"
# 被测脚本里与安装/更新相关的镜像变量（本次不测那条路径，给个直连值避免空变量）
GitMirror="github.com"
GithubMirror=""
# ONLY / LOG_FILE 必须允许运行时覆盖，所以只能"没设置时才填默认值"（用 \${VAR+x} 判断）。
if [ -z "\${ONLY+x}" ]; then ONLY="${ONLY}"; fi
if [ -z "\${LOG_FILE+x}" ]; then LOG_FILE="${LOG}"; fi
export ONLY LOG_FILE
mkdir -p "\${HOME}" "\${FX_DIR}" "\${TMPDIR}" "\${BIN_DIR}"
: > "\${CHMOD_LOG}"
# PATH 里必须放 POSIX 形式（Windows 形式在 PATH 中不被 bash 解析），它指向同一个目录。
export PATH="${WORK_POSIX}/bin:\${PATH}"
PRELUDE

cat > "${WORK}/stubs.sh" <<'STUBS'

# ---- 函数桩（在 source 之后定义，覆盖生产实现）----
# 原则：凡是会碰系统级资源（网络、tmux、cron、服务、防火墙、系统目录）的一律 stub。
# 只把 HOME 指到临时目录**不等于隔离**——网络与系统服务完全不受 HOME 影响。
curl(){ return 1; }                       # 绝不联网（生产里用于 ipinfo / 公网 IP / 下载）
tmux(){ return 0; }
crontab(){ return 0; }
systemctl(){ return 0; }
service(){ return 0; }
firewall-cmd(){ return 0; }
iptables(){ return 0; }
ufw(){ return 0; }
ip(){ return 1; }                         # hapi_detect_lan_ip 用；返回失败即不探测
hostname(){ return 1; }
pkill(){ return 1; }                      # 兜底：任何 pkill 都不落到真实进程
reboot(){ return 1; }
shutdown(){ return 1; }

# chmod 桩：记录 + 透传。"凭据文件必须 0600"这条要能在**运行时**被断言，
# 而不是只 grep 源码；透传保证真实权限行为不变（Windows 上权限位本身不生效，仅做记录）。
chmod(){
  printf '%s\n' "$*" >> "${CHMOD_LOG}"
  command chmod "$@"
}

# ---- 系统目录写入的 fail-closed 保险（别删）----
# 本套件测的路径全部落在 HOME / TMPDIR 内，但万一将来 production 走到"往系统目录写"的分支，
# 必须先被拦住，而不是先写坏开发机。只在命中系统目录时拦截（返回 97 + 显著 stderr），其余原样透传。
mkdir(){
  local a
  for a in "$@"; do
    case "${a}" in
    /etc | /etc/* | /usr | /usr/* | /var | /var/* | /boot | /boot/*)
      echo "BLOCKED_SYSTEM_WRITE:${a}" >&2
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
    /etc | /etc/* | /usr | /usr/* | /var | /var/* | /boot | /boot/*)
      echo "BLOCKED_SYSTEM_WRITE:${a}" >&2
      return 97
      ;;
    esac
  done
  command cp "$@"
}
STUBS

cat > "${WORK}/tests.sh" <<'TESTS'

# ---------- 不阻塞保证 + 进度日志 ----------
exec 0< /dev/null          # 漏写重定向的 read 立刻 EOF，绝不因 stdin 永久阻塞
log(){ [ -n "${LOG_FILE}" ] && printf '%s\n' "$1" >> "${LOG_FILE}"; return 0; }

PASS=0; FAIL=0; SKIP=0
ok(){   echo "  ok     - $1"; log "  ok     - $1"; PASS=$((PASS + 1)); }
no(){   echo "  NOT OK - $1"; log "  NOT OK - $1"; FAIL=$((FAIL + 1)); }
skip(){ echo "  SKIP   - $1"; log "  SKIP   - $1"; SKIP=$((SKIP + 1)); }
head_(){ echo "$1"; log "$1"; }
done_(){ echo; echo "TOTAL: pass=${PASS} fail=${FAIL} skip=${SKIP}"; log "TOTAL: pass=${PASS} fail=${FAIL} skip=${SKIP}"; }
group_on(){ [ -z "${ONLY}" ] && return 0; case ",${ONLY}," in *",${1},"*) return 0 ;; esac; return 1; }

# ---------- 断言helper ----------
expect_rc(){   # $1 描述 $2 期望 $3 实得
  if [ "$2" = "$3" ]; then ok "$1（rc=$3）"; else no "$1：期望 rc=$2，实得 rc=$3"; fi
}
expect_grep(){   # $1 描述 $2 文件 $3 正则
  if grep -qE -- "$3" "$2" 2>/dev/null; then ok "$1"; else no "$1（未匹配 /$3/，见 $(basename "$2")）"; fi
}
expect_no_grep(){   # $1 描述 $2 文件 $3 正则
  if grep -qE -- "$3" "$2" 2>/dev/null; then no "$1（不该出现 /$3/）"; else ok "$1"; fi
}
expect_count(){   # $1 描述 $2 文件 $3 正则 $4 期望条数
  local got
  got=$(grep -cE -- "$3" "$2" 2>/dev/null || true)
  got=${got:-0}
  if [ "${got}" -eq "$4" ]; then ok "$1（${got}）"; else no "$1：期望 $4 条，实得 ${got}"; fi
}
expect_eq(){   # $1 描述 $2 期望 $3 实得
  if [ "$2" = "$3" ]; then ok "$1"; else no "$1：期望[$2]，实得[$3]"; fi
}

# ---------- 夹具 ----------
fx_path(){ printf '%s' "${FX_DIR}/$1.json"; }
mk_fixtures(){
  node <<'JS'
const fs = require("fs");
const dir = process.env.FX_DIR;
function b64url(v){ return Buffer.from(JSON.stringify(v)).toString("base64").replace(/\+/g,"-").replace(/\//g,"_").replace(/=+$/,""); }
const header = b64url({ alg: "RS256", kid: "test-kid" });
const headerNoAlg = b64url({ kid: "test-kid" });
const idToken = header + "." + b64url({ sub: "user-abc123", email: "someone@example.com" }) + ".sig";
const accessToken = header + "." + b64url({ sub: "user-abc123", exp: Math.floor(Date.now()/1000) + 3600 * 6 }) + ".sig";
const official = {
  OPENAI_API_KEY: null,
  auth_mode: "chatgpt",
  last_refresh: "2026-09-18T03:30:52.134997151Z",
  tokens: { access_token: accessToken, account_id: "b4ea17f9-c7ad-4c76-af4c-112233445566", id_token: idToken, refresh_token: "rt.1.AAD4M-0VQe87Gb-test-refresh-token" }
};
const clone = (v) => JSON.parse(JSON.stringify(v));
const w = (name, obj) => fs.writeFileSync(dir + "/" + name + ".json", typeof obj === "string" ? obj : JSON.stringify(obj, null, 2) + "\n");
const wDate = (name, value) => { const n = clone(official); n.last_refresh = value; w(name, n); };
const wId = (name, value) => { const n = clone(official); n.tokens.id_token = value; w(name, n); };

w("ok_official", official);
w("ok_absent_key", (() => { const n = clone(official); delete n.OPENAI_API_KEY; return n; })());
w("ok_absent_mode", (() => { const n = clone(official); delete n.auth_mode; return n; })());
w("ok_missing_account", (() => { const n = clone(official); delete n.tokens.account_id; return n; })());
w("ok_last_refresh_missing", (() => { const n = clone(official); delete n.last_refresh; return n; })());

wDate("a_ok_frac", "2026-09-18T03:30:52.134997151Z");
wDate("a_ok_leap_year", "2028-02-29T00:00:00Z");
wDate("a_ok_lowercase", "2026-09-18t03:30:52z");
wDate("a_ok_leap_second", "2026-09-18T03:30:60Z");
wDate("a_ok_offset_max", "2026-09-18T03:30:52+23:59");
wDate("a_bad_month", "2026-99-99T99:99:99Z");
wDate("a_bad_feb31", "2026-02-31T00:00:00Z");
wDate("a_bad_feb29_nonleap", "2026-02-29T00:00:00Z");
wDate("a_bad_offset", "2026-01-01T00:00:00+99:99");
wDate("a_bad_hour", "2026-01-01T24:00:00Z");
wDate("a_bad_nodash", "20260918T033052Z");
wDate("c_bad_date_number", 123);

wId("b_ok_no_alg", headerNoAlg + "." + b64url({ sub: "user-abc123" }) + ".sig");
wId("b_ok_official", idToken);
wId("b_bad_empty_header", ".e30.");
wId("b_bad_dollar", "a.e30$.b");
wId("b_bad_array_payload", header + "." + b64url([]) + ".sig");
wId("b_bad_null_payload", header + ".bnVsbA.sig");
wId("b_bad_two_segments", header + "." + b64url({ sub: "x" }));
wId("b_bad_padded", header + ".eyJzdWIiOiJ4In0=.sig");
wId("b_bad_std_b64", header + ".eyJzdWIiOiJ4In0+/sig");
wId("b_bad_not_jwt", "not-a-jwt");

w("c_partial_tokens", (() => { const n = clone(official); n.tokens = { access_token: accessToken, account_id: "b4ea17f9-c7ad-4c76-af4c-112233445566" }; return n; })());
w("c_all_blank_tokens", (() => { const n = clone(official); n.tokens = { access_token: "", account_id: "", id_token: "", refresh_token: "" }; return n; })());
w("c_tokens_array", (() => { const n = clone(official); n.tokens = [1, 2]; return n; })());
w("c_no_tokens", (() => { const n = clone(official); delete n.tokens; return n; })());
w("c_apikey_ok", { OPENAI_API_KEY: "sk-test-123" });
w("c_apikey_blank", { OPENAI_API_KEY: "" });
w("c_apikey_blank_mode", { auth_mode: "apikey", OPENAI_API_KEY: "" });
w("c_pat_empty_plus_key", { personal_access_token: "", OPENAI_API_KEY: "sk-valid-looking" });
w("c_unknown_mode", (() => { const n = clone(official); n.auth_mode = "whatever"; return n; })());
w("c_mode_type", (() => { const n = clone(official); n.auth_mode = 5; return n; })());
w("c_account_number", (() => { const n = clone(official); n.tokens.account_id = 123; return n; })());
w("c_key_number", (() => { const n = clone(official); n.OPENAI_API_KEY = 123; return n; })());
w("c_empty_file", "");
w("c_array", "[1, 2, 3]\n");
w("c_truncated", '{\n  "auth_mode": "chatgpt",\n  "tokens": {\n    "access_token": "eyJ');
// loadable 漏口回归：非 ChatGPT 模式也必须有可用凭据；headers 直接拦（cc-switch: Codex 无法从 auth.json 加载）
w("c_load_pat_blank", { auth_mode: "personalAccessToken", personal_access_token: "" });
w("c_load_pat_number", { auth_mode: "personalAccessToken", personal_access_token: 123 });
w("c_load_agent_blank", { auth_mode: "agentIdentity", agent_identity: "" });
w("c_load_bedrock_blank", { auth_mode: "bedrockApiKey", bedrock_api_key: "" });
w("c_load_headers", { auth_mode: "headers" });
w("c_load_chatgpt_no_refresh", (() => { const n = clone(official); delete n.tokens.refresh_token; return n; })());
// 正向对照：合法凭据必须放行（防止"修成一律返回 1"）
w("c_load_pat_ok", { auth_mode: "personalAccessToken", personal_access_token: "pat-abc123" });
w("c_load_agent_ok", { auth_mode: "agentIdentity", agent_identity: { subject: "agent-1" } });
w("c_load_bedrock_ok", { auth_mode: "bedrockApiKey", bedrock_api_key: "ABSK-test" });
w("c_load_bedrock_keys_ok", { auth_mode: "bedrockAccessKeys", bedrock_access_keys: { access_key_id: "AKIA-TEST", secret_access_key: "s" } });
console.log("fixtures ready");
JS
}

# 假编辑器：把预置夹具 cp 到目标路径（模拟"用户在编辑器里粘贴并保存"）
mk_fake_editors(){
  cat > "${BIN_DIR}/editor.sh" <<'ED'
#!/usr/bin/env bash
target="${@: -1}"
[ -n "${FAKE_EDITOR_LOG}" ] && printf '%s\n' "${target}" >> "${FAKE_EDITOR_LOG}"
if [ -n "${FAKE_EDITOR_SEQ}" ]; then
  n=$(cat "${FAKE_EDITOR_COUNT_FILE}" 2>/dev/null || echo 0); n=$((n + 1)); echo "${n}" > "${FAKE_EDITOR_COUNT_FILE}"
  src="${FAKE_EDITOR_SEQ}/step_${n}.json"
  [ -f "${src}" ] && cp "${src}" "${target}"
elif [ -n "${FAKE_EDITOR_SOURCE}" ]; then
  cp "${FAKE_EDITOR_SOURCE}" "${target}"
fi
[ "${FAKE_EDITOR_TERM}" = "1" ] && kill -TERM "${PPID}" 2>/dev/null
exit "${FAKE_EDITOR_STATUS:-0}"
ED
  # 记录被调用参数的假 vim（验证 vim 系参数串）
  cat > "${BIN_DIR}/vim" <<'VIM'
#!/usr/bin/env bash
printf 'VIM ARGS:' >> "${VIM_ARGS_LOG}"
for a in "$@"; do printf ' [%s]' "$a" >> "${VIM_ARGS_LOG}"; done
printf '\n' >> "${VIM_ARGS_LOG}"
last="${@: -1}"
[ -n "${FAKE_EDITOR_SOURCE}" ] && cp "${FAKE_EDITOR_SOURCE}" "${last}"
exit 0
VIM
  chmod +x "${BIN_DIR}/editor.sh" "${BIN_DIR}/vim"
}

# 造一份可用的 live Codex 配置（auth.json + config.toml）
seed_live(){   # $1 = auth 夹具名 $2 = config.toml 内容（可选）
  rm -rf "${HOME}/.codex"; mkdir -p "${HOME}/.codex"
  cp "$(fx_path "$1")" "${HOME}/.codex/auth.json"
  if [ $# -ge 2 ]; then printf '%s' "$2" > "${HOME}/.codex/config.toml"; fi
}

auth_check(){   # $1 夹具名 $2 level（可选）| 输出写 ${WORK_DIR}/check.out，返回 rc
  local file="${FX_DIR}/$1.json"
  # 夹具缺失必须返回专用码 3：否则"期望 rc=1（拒绝）"的断言会因为文件根本不存在而**假绿**。
  if [ ! -f "${file}" ]; then
    printf '错误: 夹具缺失 %s（FIXTURE-MISSING）\n' "${file}" > "${WORK_DIR}/check.out"
    return 3
  fi
  if [ $# -ge 2 ]; then hapi_check_codex_auth_file "${file}" "$2" > "${WORK_DIR}/check.out" 2>&1
  else hapi_check_codex_auth_file "${file}" > "${WORK_DIR}/check.out" 2>&1; fi
}

# ---------- 前置自检：抽不到函数时必须立刻失败，不能"假绿" ----------
if [ "${HOME}" != "${WORK_DIR}/home" ]; then
  echo "隔离前置条件不满足：HOME=${HOME} 不在 ${WORK_DIR} 内，拒绝运行" >&2
  exit 2
fi
MISSING=""
for f in hapi_check_codex_auth_file hapi_write_codex_auth_file hapi_write_codex_current_config \
         hapi_validate_codex_files hapi_codex_current_value hapi_show_codex_config \
         hapi_edit_codex_official_auth hapi_detect_editor hapi_editor_program hapi_editor_basename \
         hapi_editor_is_vim_like hapi_run_editor hapi_cleanup_sensitive_tmp \
         hapi_install_sensitive_tmp_traps hapi_extract_codex_profile_auth \
         hapi_save_codex_profile_from_files hapi_store_current_codex_config \
         hapi_create_codex_profile hapi_switch_codex_profile hapi_codex_profile_store_file \
         hapi_sync_codex_route hapi_codex_route_stash_file; do
  declare -f "${f}" > /dev/null || MISSING="${MISSING} ${f}"
done
if [ -n "${MISSING}" ]; then
  echo "harness 抽取失败，缺少函数:${MISSING}" >&2
  exit 2
fi

mk_fixtures > /dev/null || { echo "夹具生成失败（node 写入失败？）" >&2; exit 2; }
# 夹具数量自检：夹具没写出来时，所有"期望 rc=1"的断言都会假绿，所以这里必须先兜住。
FX_COUNT=$(ls "${FX_DIR}" 2>/dev/null | wc -l | tr -d ' ')
if [ "${FX_COUNT}" -lt 30 ]; then
  echo "夹具数量异常（只有 ${FX_COUNT} 个，期望 >=30），拒绝继续" >&2
  exit 2
fi
mk_fake_editors
log "==== harness 启动：ONLY='${ONLY}' 夹具=${FX_COUNT} ===="

# ============================================================
# A) last_refresh：真 RFC3339
# ============================================================
if group_on A; then
  head_ "A) last_refresh 必须是真 RFC3339（格式 + 日历/时钟/时区范围）"
  for name in ok_official a_ok_frac a_ok_leap_year a_ok_lowercase a_ok_leap_second a_ok_offset_max; do
    auth_check "${name}"; expect_rc "接受合法时间 ${name}" 0 "$?"
  done
  for name in a_bad_month a_bad_feb31 a_bad_feb29_nonleap a_bad_offset a_bad_hour a_bad_nodash c_bad_date_number; do
    auth_check "${name}"; expect_rc "拒绝非法时间 ${name}" 1 "$?"
  done
  auth_check a_bad_month
  expect_grep "非法日期报「不是合法的 RFC3339」" "${WORK_DIR}/check.out" "不是合法的 RFC3339"
  auth_check c_bad_date_number
  expect_grep "数字型 last_refresh 报类型错误" "${WORK_DIR}/check.out" "必须是 RFC3339 字符串"
fi

# ============================================================
# B) id_token：严格 JWT envelope
# ============================================================
if group_on B; then
  head_ "B) id_token 严格 JWT envelope（三段非空 / 严格 base64url-no-pad / payload 为对象）"
  auth_check b_ok_official;   expect_rc "合法三件套通过" 0 "$?"
  auth_check b_ok_no_alg;     expect_rc "header 缺 alg 不阻断" 0 "$?"
  expect_grep "header 缺 alg 给出警告" "${WORK_DIR}/check.out" "缺少 alg"
  expect_no_grep "缺 alg 时没有硬错误" "${WORK_DIR}/check.out" "^错误"
  for name in b_bad_empty_header b_bad_dollar b_bad_array_payload b_bad_null_payload \
              b_bad_two_segments b_bad_padded b_bad_std_b64 b_bad_not_jwt; do
    auth_check "${name}"; expect_rc "拒绝非严格 JWT ${name}" 1 "$?"
  done
  auth_check b_bad_empty_header
  expect_grep "非 JWT 报硬错误" "${WORK_DIR}/check.out" "不是合法的 JWT"
  auth_check b_bad_array_payload
  expect_grep "payload 为数组也拒绝" "${WORK_DIR}/check.out" "不是合法的 JWT"
fi

# ============================================================
# C) auth_mode 解析优先级 + official / loadable 分级
# ============================================================
if group_on C; then
  head_ "C) auth_mode 解析优先级与两级校验"
  auth_check ok_absent_mode;  expect_rc "无 auth_mode（隐式 ChatGPT）按官方登录校验" 0 "$?"
  auth_check c_partial_tokens official; expect_rc "official 级要求三件套齐备" 1 "$?"
  auth_check c_partial_tokens loadable; expect_rc "loadable 级也拒绝缺必需字段的 tokens" 1 "$?"
  expect_grep "缺字段说明是 TokenData 必需字段" "${WORK_DIR}/check.out" "都是必需字段"
  auth_check c_all_blank_tokens loadable; expect_rc "loadable 级拦住全空凭据" 1 "$?"
  auth_check c_apikey_ok loadable;    expect_rc "loadable 级放行 apikey 配置" 0 "$?"
  auth_check c_apikey_blank loadable; expect_rc "loadable 级拦住空 Key" 1 "$?"
  auth_check c_apikey_blank;          expect_rc "official 级也拦住空 Key" 1 "$?"
  auth_check c_apikey_blank_mode;     expect_rc "auth_mode=apikey 空 Key 报错" 1 "$?"
  auth_check c_bad_date_number loadable; expect_rc "loadable 级同样拦类型错误" 1 "$?"
  auth_check c_unknown_mode;  expect_rc "拒绝无法识别的 auth_mode" 1 "$?"
  expect_grep "unknown auth_mode 列取值" "${WORK_DIR}/check.out" "取值无法识别"
  auth_check c_mode_type;     expect_rc "auth_mode 类型错误被拒绝" 1 "$?"
  auth_check c_account_number; expect_rc "account_id 类型错误被拒绝" 1 "$?"
  auth_check c_key_number;    expect_rc "OPENAI_API_KEY 类型错误被拒绝" 1 "$?"
  auth_check c_tokens_array;  expect_rc "tokens 不是对象被拒绝" 1 "$?"
  auth_check c_no_tokens;     expect_rc "chatgpt 模式缺 tokens 被拒绝" 1 "$?"
  auth_check c_empty_file;    expect_rc "空文件被拒绝" 1 "$?"
  auth_check c_array;         expect_rc "顶层非对象被拒绝" 1 "$?"
  auth_check c_truncated;     expect_rc "JSON 截断被拒绝" 1 "$?"

  head_ "C2) loadable 不能放过「无可用凭据」的非 ChatGPT 模式（本轮修复）"
  auth_check c_load_chatgpt_no_refresh loadable
  expect_rc "loadable 拦住缺 refresh_token（TokenData 必需字段）" 1 "$?"
  auth_check c_load_pat_blank loadable
  expect_rc "loadable 拦住空 PAT 字符串" 1 "$?"
  expect_grep "空 PAT 报「为空」" "${WORK_DIR}/check.out" "personal_access_token 为空"
  auth_check c_load_pat_number loadable
  expect_rc "loadable 拦住数字型 PAT" 1 "$?"
  expect_grep "数字 PAT 报类型不符" "${WORK_DIR}/check.out" "personal_access_token 类型不符"
  auth_check c_load_agent_blank loadable
  expect_rc "loadable 拦住空 agentIdentity" 1 "$?"
  auth_check c_load_bedrock_blank loadable
  expect_rc "loadable 拦住空 Bedrock Key" 1 "$?"
  auth_check c_load_headers loadable
  expect_rc "loadable 拦住 headers 模式" 1 "$?"
  expect_grep "headers 说明 Codex 无法加载" "${WORK_DIR}/check.out" "无法从 auth.json 加载"
  for name in c_load_pat_ok c_load_agent_ok c_load_bedrock_ok c_load_bedrock_keys_ok; do
    auth_check "${name}" loadable; expect_rc "loadable 放行合法凭据 ${name}" 0 "$?"
  done

  auth_check c_pat_empty_plus_key
  expect_rc "空字符串也抢模式优先级（PAT 胜出并报错）" 1 "$?"
  expect_grep "空 PAT 报「为空」" "${WORK_DIR}/check.out" "personal_access_token 为空"
  expect_no_grep "空 PAT 不会被降级成 apikey" "${WORK_DIR}/check.out" "解析为 apikey"
  auth_check ok_missing_account
  expect_rc "account_id 缺失只警告" 0 "$?"
  expect_grep "account_id 缺失给出警告" "${WORK_DIR}/check.out" "account_id 缺失或为空"
  auth_check ok_last_refresh_missing
  expect_rc "last_refresh 缺失只警告" 0 "$?"
fi

# ============================================================
# D) 写入器：官方登录路由保护
# ============================================================
if group_on D; then
  head_ "D) hapi_write_codex_current_config：不让空 Key 破坏官方路由"
  seed_live ok_official $'model = "gpt-5.5"\n'
  hapi_write_codex_current_config "" "https://api.example.com/v1" "gpt-5.5" > "${WORK_DIR}/d1.log" 2>&1
  expect_count "官方登录 + 空 Key 不写 model_provider" "${HOME}/.codex/config.toml" "model_provider" 0
  expect_count "不建 custom provider 段" "${HOME}/.codex/config.toml" "model_providers" 0
  expect_count "auth.json 保持 OPENAI_API_KEY=null" "${HOME}/.codex/auth.json" '"OPENAI_API_KEY": null' 1
  expect_grep "提示保持官方路由" "${WORK_DIR}/d1.log" "保持不指定 model_provider"

  seed_live ok_absent_key
  hapi_write_codex_current_config "" "https://api.example.com/v1" "gpt-5.5" > "${WORK_DIR}/d2.log" 2>&1
  expect_count "隐式登录且字段缺失（不断言不存在）时不会凭空写出 Key 字段" "${HOME}/.codex/auth.json" "OPENAI_API_KEY" 0
  expect_count "tokens 原样保留" "${HOME}/.codex/auth.json" '"refresh_token"' 1

  seed_live ok_official
  hapi_write_codex_current_config "" "https://api.example.com/v1" "gpt-5.5" > /dev/null 2>&1
  expect_count "不把 null 改写成空字符串" "${HOME}/.codex/auth.json" '"OPENAI_API_KEY": ""' 0

  for reserved in openai ollama lmstudio amazon-bedrock; do
    seed_live ok_official "model = \"gpt-5.5\"
model_provider = \"${reserved}\"
"
    hapi_write_codex_current_config "" "https://api.example.com/v1" "gpt-5.5" > "${WORK_DIR}/d_res.log" 2>&1
    expect_count "保留 id ${reserved}：不建 provider 表" "${HOME}/.codex/config.toml" "model_providers" 0
    expect_grep "保留 id ${reserved}：给出提示" "${WORK_DIR}/d_res.log" "内置/保留 provider"
  done

  rm -f "$(hapi_codex_route_stash_file)"
  seed_live ok_official $'model = "gpt-5.5"\nmodel_provider = "myrelay"\n'
  hapi_write_codex_current_config "" "https://api.example.com/v1" "gpt-5.5" > "${WORK_DIR}/d5.log" 2>&1
  expect_count "官方登录 + 残留自定义路由：不再保留第三方路由" "${HOME}/.codex/config.toml" "model_provider" 0
  expect_grep "官方登录剥离路由时给出说明" "${WORK_DIR}/d5.log" "已自动移除 config.toml 里的第三方路由"

  rm -f "$(hapi_codex_route_stash_file)"
  seed_live ok_official
  hapi_write_codex_current_config "sk-third-party" "https://api.example.com/v1" "gpt-5.5" > "${WORK_DIR}/d6.log" 2>&1
  expect_count "官方登录 + 填了 Key + 第三方 base_url 时写 custom 模板" "${HOME}/.codex/config.toml" 'model_provider = "custom"' 1
  expect_grep "填 Key 时给出风险提示" "${WORK_DIR}/d6.log" "本次仍写入了 OPENAI_API_KEY"
  expect_count "官方登录字段未被删" "${HOME}/.codex/auth.json" '"refresh_token"' 1

  # 官方登录 + 残留第三方路由 + 已有 token：路由整段剥离并暂存，token 不留在 config.toml
  seed_live ok_official 'model = "gpt-5.5"
model_provider = "myrelay"

[model_providers.myrelay]
base_url = "https://api.example.com/v1"
experimental_bearer_token = "sk-existing"
'
  hapi_write_codex_current_config "" "https://api.example.com/v1" "gpt-5.5" > /dev/null 2>&1
  expect_count "剥离后 config.toml 不再留第三方 token" "${HOME}/.codex/config.toml" "sk-existing" 0
  expect_count "第三方 token 随路由一起暂存" "$(hapi_codex_route_stash_file)" "sk-existing" 1

  # 第三方端点的 apikey 配置：空 Key 依旧不能清掉已写的 token，路由也必须保留
  seed_live c_apikey_ok 'model = "gpt-5.5"
model_provider = "myrelay"

[model_providers.myrelay]
base_url = "https://api.example.com/v1"
experimental_bearer_token = "sk-existing"
'
  hapi_write_codex_current_config "" "https://api.example.com/v1" "gpt-5.5" > /dev/null 2>&1
  expect_count "第三方 apikey：空 Key 不清空已有的 experimental_bearer_token" "${HOME}/.codex/config.toml" "sk-existing" 1
  expect_count "第三方 apikey：路由保留" "${HOME}/.codex/config.toml" 'model_provider = "myrelay"' 1

  rm -rf "${HOME}/.codex"; mkdir -p "${HOME}/.codex"
  hapi_write_codex_current_config "" "https://api.example.com/v1" "gpt-5.5" > "${WORK_DIR}/d8.log" 2>&1
  expect_count "非官方场景仍生成 custom 模板（原行为）" "${HOME}/.codex/config.toml" 'model_provider = "custom"' 1
  expect_no_grep "非官方场景不打印官方路由提示" "${WORK_DIR}/d8.log" "保持不指定 model_provider"
fi

# ============================================================
# E) 菜单 7：编辑器流程
# ============================================================
if group_on E; then
  head_ "E) hapi_edit_codex_official_auth：编辑器探测 / 参数 / 失败拦截 / 临时文件"
  HAPI_EDITOR="/nonexistent/editor-probe" ; detected=$(hapi_detect_editor 2>/dev/null)
  expect_count "不可用的 HAPI_EDITOR 会被跳过（回退自动探测）" <(printf '%s\n' "${detected}") "nonexistent" 0
  unset HAPI_EDITOR

  # 注意：探测会先确认"这个程序真的存在"，所以这里必须用确实存在的命令（bash/sh/cp），
  # 否则测到的是"回退逻辑"而不是"优先级"（踩过：用不存在的 myvim/vis-ed 让三条断言全红）。
  HAPI_EDITOR="bash --flag"; expect_eq "可用的 HAPI_EDITOR 优先" "bash --flag" "$(hapi_detect_editor)"; unset HAPI_EDITOR
  VISUAL="sh"; EDITOR="cp"; expect_eq "VISUAL 优先于 EDITOR" "sh" "$(hapi_detect_editor)"; unset VISUAL
  expect_eq "EDITOR 兜底" "cp" "$(hapi_detect_editor)"; unset EDITOR

  hapi_editor_is_vim_like "vim" && ok "vim 判定为 vim 系" || no "vim 应判定为 vim 系"
  hapi_editor_is_vim_like "nano" && no "nano 不应判定为 vim 系" || ok "nano 不是 vim 系"

  rm -f "${VIM_ARGS_LOG}"; printf '{}\n' > "${WORK_DIR}/probe.json"
  FAKE_EDITOR_SOURCE="$(fx_path ok_official)" hapi_run_editor "vim" "${WORK_DIR}/probe.json" > /dev/null 2>&1
  expect_grep "vim 参数含 set paste" "${VIM_ARGS_LOG}" "\[set paste\]"
  expect_grep "vim 参数关闭 backup/swap/undo/viminfo" "${VIM_ARGS_LOG}" "\[set nobackup nowritebackup noswapfile noundofile viminfo=\]"
  rm -f "${WORK_DIR}/probe2.json"
  FAKE_EDITOR_SOURCE="$(fx_path ok_official)" hapi_run_editor "bash ${BIN_DIR}/editor.sh" "${WORK_DIR}/probe2.json" > /dev/null 2>&1
  expect_count "非 vim 编辑器不传 -c 但文件被写入" "${WORK_DIR}/probe2.json" "account_id" 1

  export HAPI_EDITOR="bash ${BIN_DIR}/editor.sh"
  export FAKE_EDITOR_SOURCE="$(fx_path ok_official)"
  export FAKE_EDITOR_LOG="${EDITOR_TARGET_LOG}"   # 必须 export：假编辑器是子进程，只继承导出变量
  unset FAKE_EDITOR_SEQ FAKE_EDITOR_STATUS FAKE_EDITOR_TERM
  rm -f "${EDITOR_TARGET_LOG}"

  seed_live ok_official
  printf '1\n\ny\nn\n' | hapi_edit_codex_official_auth > /dev/null 2>&1
  expect_count "正常粘贴写入 auth.json" "${HOME}/.codex/auth.json" '"account_id"' 1
  expect_count "使用 mktemp 随机后缀" "${EDITOR_TARGET_LOG}" "hapi_codex_auth\.[A-Za-z0-9]{6}$" 1
  expect_count "不再是 PID 固定名" "${EDITOR_TARGET_LOG}" "hapi_codex_auth_[0-9]+\.json$" 0
  expect_count "正常结束后无临时文件残留" <(ls "${TMPDIR}") "hapi_codex_auth" 0

  before=$(cat "${HOME}/.codex/auth.json")
  FAKE_EDITOR_SOURCE="$(fx_path c_truncated)"
  printf '1\n\nn\n' | hapi_edit_codex_official_auth > "${WORK_DIR}/e_fail.log" 2>&1
  expect_eq "校验失败放弃后 live 文件未被改动" "${before}" "$(cat "${HOME}/.codex/auth.json")"
  expect_grep "报出 JSON 解析错误" "${WORK_DIR}/e_fail.log" "JSON 解析失败"
  expect_count "失败路径也清理临时文件" <(ls "${TMPDIR}") "hapi_codex_auth" 0

  FAKE_EDITOR_SOURCE="$(fx_path ok_official)"; export FAKE_EDITOR_STATUS=1
  rm -f "${HOME}/.codex/auth.json"
  printf '1\n\nn\n' | hapi_edit_codex_official_auth > "${WORK_DIR}/e_rc.log" 2>&1
  expect_count "编辑器失败 + 拒绝 → 不写文件" <(ls "${HOME}/.codex" 2>/dev/null) '^auth\.json$' 0
  expect_grep "提示编辑器异常退出" "${WORK_DIR}/e_rc.log" "编辑器异常退出"
  printf '1\n\ny\ny\nn\n' | hapi_edit_codex_official_auth > /dev/null 2>&1
  expect_count "编辑器失败 + 确认 → 仍可写入" "${HOME}/.codex/auth.json" '"account_id"' 1
  unset FAKE_EDITOR_STATUS

  seed_live ok_official
  FAKE_EDITOR_SOURCE="$(fx_path ok_official)"
  printf '1\n\ny\nn\n' | hapi_edit_codex_official_auth > /dev/null 2>&1
  FAKE_EDITOR_SOURCE="$(fx_path c_partial_tokens)"
  printf '1\n\ny\nn\n' | hapi_edit_codex_official_auth > "${WORK_DIR}/e_bak.log" 2>&1
  expect_count "生成 auth.json.bak" <(ls -A "${HOME}/.codex") "auth.json.bak" 1
  expect_grep "official 级拦住残缺三件套" "${WORK_DIR}/e_bak.log" "缺少 tokens.id_token"

  rm -f "${WORK_DIR}/term_result"
  (
    export HAPI_EDITOR="bash ${BIN_DIR}/editor.sh"
    export FAKE_EDITOR_SOURCE="$(fx_path ok_official)"
    export FAKE_EDITOR_TERM=1
    printf '1\n\n' | hapi_edit_codex_official_auth > /dev/null 2>&1
    echo "exit=$?" > "${WORK_DIR}/term_result"
    echo "leftover=$(ls "${TMPDIR}" 2>/dev/null | grep -c 'hapi_codex_auth')" >> "${WORK_DIR}/term_result"
  )
  expect_grep "SIGTERM 保持 143 退出语义" "${WORK_DIR}/term_result" "^exit=143$"
  expect_grep "SIGTERM 后无临时文件残留" "${WORK_DIR}/term_result" "^leftover=0$"
fi

# ============================================================
# F) 配置库旁路卡点
# ============================================================
if group_on F; then
  head_ "F) 配置库不能成为写入无效 auth 的旁路"
  seed_live a_bad_month $'model = "gpt-5.5"\n'
  printf 'bad-profile\n' | hapi_store_current_codex_config > "${WORK_DIR}/f1.log" 2>&1
  expect_rc "菜单 2 拒绝储存非法 live auth" 1 "$?"
  expect_count "配置库未被写入" <(ls -A "${HOME}/.codex") "hapi_config_profiles.json" 0
  expect_grep "菜单 2 给出中止提示" "${WORK_DIR}/f1.log" "已中止储存"

  seed_live ok_official $'model = "gpt-5.5"\n'
  printf 'good-profile\n' | hapi_store_current_codex_config > /dev/null 2>&1
  expect_count "菜单 2 正常储存合法配置" "${HOME}/.codex/hapi_config_profiles.json" '"name": "good-profile"' 1

  node <<'JS'
const fs = require("fs");
const file = process.env.HOME + "/.codex/hapi_config_profiles.json";
const store = JSON.parse(fs.readFileSync(file, "utf8"));
store.profiles.push({ name: "evil", createdAt: "x", updatedAt: "x", config: {
  auth: { auth_mode: "chatgpt", OPENAI_API_KEY: null, last_refresh: "2026-99-99T99:99:99Z",
          tokens: { access_token: "a.b.c", account_id: "x", id_token: "a.b.c", refresh_token: "r" } },
  config: "model = \"gpt-5.5\"\n" } });
fs.writeFileSync(file, JSON.stringify(store, null, 2) + "\n");
JS
  before_live=$(cat "${HOME}/.codex/auth.json")
  printf '2\ny\n' | hapi_switch_codex_profile > "${WORK_DIR}/f3.log" 2>&1
  expect_rc "菜单 4 拒绝切换非法 profile" 1 "$?"
  expect_eq "被拒时 live auth.json 未被改动" "${before_live}" "$(cat "${HOME}/.codex/auth.json")"
  expect_grep "菜单 4 给出中止提示" "${WORK_DIR}/f3.log" "已中止切换"
  expect_count "切换校验用的临时文件已清理" <(ls "${TMPDIR}") "hapi_codex_profile_auth" 0

  rm -f "${HOME}/.codex/auth.json"
  printf '1\ny\n' | hapi_switch_codex_profile > /dev/null 2>&1
  expect_rc "菜单 4 正常切换合法 profile" 0 "$?"
  expect_count "live auth.json 由 profile 写回" "${HOME}/.codex/auth.json" '"account_id"' 1

  printf 'p-empty\n\nsk-created-key\n\n\n' | hapi_create_codex_profile > /dev/null 2>&1
  expect_count "菜单 3 建立配置" "${HOME}/.codex/hapi_config_profiles.json" '"name": "p-empty"' 1
  expect_count "菜单 3 写入的是用户后来输入的非空 Key" "${HOME}/.codex/hapi_config_profiles.json" "sk-created-key" 1
fi

# ============================================================
# G) 凭据权限（备份 0600）与预览脱敏
# ============================================================
if group_on G; then
  head_ "G) 凭据文件与备份的 0600，以及预览脱敏"
  expect_count "所有 cp -a 备份点后都紧跟 chmod 600" \
    <(node -e '
const fs = require("fs");
const lines = fs.readFileSync(process.env.TARGET_SCRIPT, "utf8").replace(/\r\n/g, "\n").split("\n");
let miss = 0;
for (let i = 0; i < lines.length; i += 1) {
  if (!/^\s*cp -a "[^"]+" "[^"]+"\s*$/.test(lines[i])) continue;
  const dest = /^\s*cp -a "[^"]+" "([^"]+)"/.exec(lines[i])[1];
  const next = [lines[i + 1] || "", lines[i + 2] || ""].join("\n");
  if (!next.includes("chmod 600 \"" + dest + "\"")) { miss += 1; console.log("缺 chmod: " + lines[i].trim()); }
}
console.log("missing=" + miss);
' | tail -n 1) "missing=0" 1

  seed_live ok_official
  : > "${CHMOD_LOG}"
  export HAPI_EDITOR="bash ${BIN_DIR}/editor.sh"
  export FAKE_EDITOR_SOURCE="$(fx_path ok_official)"; unset FAKE_EDITOR_STATUS FAKE_EDITOR_SEQ FAKE_EDITOR_TERM
  printf '1\n\ny\nn\n' | hapi_edit_codex_official_auth > /dev/null 2>&1
  expect_grep "auth.json 写入时调用 chmod 600" "${CHMOD_LOG}" "600 ${HOME}/.codex/auth.json"
  seed_live ok_official $'model = "gpt-5.5"\n'
  printf '1\n\ny\nn\n' | hapi_edit_codex_official_auth > /dev/null 2>&1
  expect_grep "auth.json.bak 也调用 chmod 600" "${CHMOD_LOG}" "600 ${HOME}/.codex/auth.json.bak"
  hapi_write_codex_current_config "" "https://api.example.com/v1" "gpt-5.5" > /dev/null 2>&1
  expect_grep "config.toml 备份也调用 chmod 600" "${CHMOD_LOG}" "600 ${HOME}/.codex/config.toml.bak"

  expect_count "预览显示 account_id" <(hapi_check_codex_auth_file "$(fx_path ok_official)" 2>&1) "account_id.*b4ea17f9" 1
  expect_count "预览打码 access_token" <(hapi_check_codex_auth_file "$(fx_path ok_official)" 2>&1) '"access_token": "\*\*\*\*\*\*"' 1
  expect_count "预览不出现真实 refresh_token" <(hapi_check_codex_auth_file "$(fx_path ok_official)" 2>&1) "rt\.1\.AAD4M" 0
  seed_live ok_official
  hapi_show_codex_config > "${WORK_DIR}/g_show.log" 2>&1
  expect_count "查看配置不泄露 refresh_token" "${WORK_DIR}/g_show.log" "rt\.1\.AAD4M" 0
  expect_grep "查看配置仍能看到 account_id" "${WORK_DIR}/g_show.log" "b4ea17f9"
fi

# ============================================================
# H) 兼容性回归
# ============================================================
if group_on H; then
  head_ "H) 既有函数与菜单接线"
  seed_live ok_official 'model = "gpt-5.5"
model_provider = "myrelay"

[model_providers.myrelay]
base_url = "https://api.example.com/v1"
'
  hapi_validate_codex_files > /dev/null 2>&1
  expect_rc "hapi_validate_codex_files 接受正常配置" 0 "$?"
  expect_eq "hapi_codex_current_value 读取 model_provider" "myrelay" "$(hapi_codex_current_value 'model_provider')"
  expect_count "菜单项 7 仍在" <(grep -c '7\.  \${cyan}写入/编辑官方 auth.json' "${TARGET_SCRIPT}") "1" 1
  expect_count "菜单 7 case 分支仍在" <(grep -c '7) hapi_edit_codex_official_auth; pause ;;' "${TARGET_SCRIPT}") "1" 1
  expect_count "菜单 2 走 loadable 级校验" \
    <(grep -c 'hapi_check_codex_auth_file "${auth_file}" loadable' "${TARGET_SCRIPT}") "1" 1
  expect_count "菜单 4 走 loadable 级校验" \
    <(grep -c 'hapi_check_codex_auth_file "${profile_auth_tmp}" loadable' "${TARGET_SCRIPT}") "1" 1
fi

# ============================================================
# I) 路由自动收敛：官方登录剥离第三方路由 / 第三方 base_url 自动恢复
#    （对照 cc-switch：官方预设 = 空 config，第三方预设 = model_provider + [model_providers.*]；
#      脚本没有 cc-switch 的数据库，所以剥离时把路由原文存进暂存文件）
# ============================================================
if group_on I; then
  head_ "I) 官方 ↔ 第三方路由自动收敛"
  STASH="$(hapi_codex_route_stash_file)"

  # --- I1 菜单 7 的同步入口：官方登录 + 残留第三方路由 → 剥离并暂存 ---
  rm -f "${STASH}"
  seed_live ok_official 'model = "gpt-5.5"
model_provider = "myrelay"

[model_providers.myrelay]
name = "MyRelay"
base_url = "https://relay.example.com/v1"
env_key = "OPENAI_API_KEY"
experimental_bearer_token = "sk-relay-secret"
wire_api = "responses"

[features]
goals = true
'
  : > "${CHMOD_LOG}"
  hapi_sync_codex_route > "${WORK_DIR}/i1.log" 2>&1
  expect_rc "官方登录下同步路由成功" 0 "$?"
  expect_count "剥离 model_provider 行" "${HOME}/.codex/config.toml" "model_provider" 0
  expect_count "剥离 [model_providers.*] 段" "${HOME}/.codex/config.toml" "model_providers" 0
  expect_count "config.toml 里不再留第三方 token" "${HOME}/.codex/config.toml" "sk-relay-secret" 0
  expect_count "保留顶层 model" "${HOME}/.codex/config.toml" '^model = "gpt-5.5"$' 1
  expect_count "保留 [features] 段" "${HOME}/.codex/config.toml" '^\[features\]$' 1
  expect_grep "提示已自动移除路由" "${WORK_DIR}/i1.log" "已自动移除 config.toml 里的第三方路由"
  expect_count "暂存文件记住 provider id" "${STASH}" '"providerId": "myrelay"' 1
  expect_count "暂存文件保存段原文（含 token）" "${STASH}" "sk-relay-secret" 1
  expect_grep "暂存文件权限收紧到 600" "${CHMOD_LOG}" "600 ${STASH}"

  # --- I2 幂等：已无第三方路由时不再改写 config.toml ---
  before_config=$(cat "${HOME}/.codex/config.toml")
  hapi_sync_codex_route > "${WORK_DIR}/i2.log" 2>&1
  expect_rc "再次同步仍成功（幂等）" 0 "$?"
  expect_eq "已无第三方路由时不改写 config.toml" "${before_config}" "$(cat "${HOME}/.codex/config.toml")"
  expect_grep "无路由可剥离时提示保持官方路由" "${WORK_DIR}/i2.log" "保持不指定 model_provider"

  # route-only 只做路由收敛：连 [features] 这种无关字段都不补（最小改动，便于肉眼 diff）
  # ⚠️ 这里**不能调 seed_live**：它第一行是 `rm -rf "${HOME}/.codex"`，会把 I1 刚写下的暂存路由删掉，
  #    于是 I3 的恢复链失去前提（曾经因此丢过 4 条断言）。只覆盖这两个文件。
  cp "$(fx_path ok_official)" "${HOME}/.codex/auth.json"
  printf '%s' $'model = "gpt-5.5"\n' > "${HOME}/.codex/config.toml"
  hapi_sync_codex_route > /dev/null 2>&1
  expect_count "无第三方路由时 route-only 不补 [features]" "${HOME}/.codex/config.toml" '^\[features\]$' 0
  expect_eq "config.toml 保持只有 model 一行" 'model = "gpt-5.5"' "$(cat "${HOME}/.codex/config.toml")"

  # 前置断言：I3 依赖 I1 留下的暂存路由，先把"前提还在"钉死，免得后续用例再把它删掉却看不出来
  expect_count "I3 前暂存路由仍存在" "${STASH}" '"providerId": "myrelay"' 1

  # --- I3 菜单 1 填第三方 base_url：自动恢复暂存的路由并更新端点 ---
  hapi_write_codex_current_config "sk-new-relay" "https://relay2.example.com/v1" "gpt-5.5" > "${WORK_DIR}/i3.log" 2>&1
  expect_rc "填写第三方 base_url 时写入成功" 0 "$?"
  expect_count "恢复 model_provider 行（provider id 沿用暂存值）" "${HOME}/.codex/config.toml" '^model_provider = "myrelay"$' 1
  expect_count "恢复 [model_providers.myrelay] 段" "${HOME}/.codex/config.toml" '^\[model_providers\.myrelay\]$' 1
  expect_count "按本次 base_url 更新端点" "${HOME}/.codex/config.toml" 'base_url = "https://relay2.example.com/v1"' 1
  expect_count "恢复段里的其它字段（env_key）" "${HOME}/.codex/config.toml" 'env_key = "OPENAI_API_KEY"' 1
  expect_count "恢复段里的 token 换成本次填入的 Key" "${HOME}/.codex/config.toml" "sk-new-relay" 1
  expect_grep "提示已自动恢复路由" "${WORK_DIR}/i3.log" "已自动恢复此前的第三方路由"

  # --- I4 官方 API Key + 官方端点：剥离第三方路由（不建 provider 段）---
  rm -f "${STASH}"
  seed_live c_apikey_ok 'model = "gpt-5.5"
model_provider = "custom"

[model_providers.custom]
name = "Custom"
base_url = "https://relay.example.com/v1"
env_key = "OPENAI_API_KEY"
wire_api = "responses"
'
  hapi_write_codex_current_config "sk-official" "https://api.openai.com/v1" "gpt-5.5" > "${WORK_DIR}/i4.log" 2>&1
  expect_rc "官方 Key + 官方端点写入成功" 0 "$?"
  expect_count "官方端点下不保留 model_provider" "${HOME}/.codex/config.toml" "model_provider" 0
  expect_count "官方端点下不建 provider 段" "${HOME}/.codex/config.toml" "model_providers" 0
  expect_grep "提示已自动移除路由" "${WORK_DIR}/i4.log" "已自动移除 config.toml 里的第三方路由"
  expect_count "剥离内容进入暂存文件" "${STASH}" '"providerId": "custom"' 1

  # --- I5 保留 id（openai / ollama…）：不建表、不剥离、不产生暂存 ---
  rm -f "${STASH}"
  seed_live ok_official 'model = "gpt-5.5"
model_provider = "openai"
'
  hapi_sync_codex_route > "${WORK_DIR}/i5.log" 2>&1
  expect_rc "保留 id 下同步成功" 0 "$?"
  expect_count "保留 id 行保持原样" "${HOME}/.codex/config.toml" '^model_provider = "openai"$' 1
  expect_count "保留 id 不建 provider 表" "${HOME}/.codex/config.toml" "model_providers" 0
  expect_count "保留 id 不产生暂存文件" <(ls -A "${HOME}/.codex" 2>/dev/null) "^hapi_provider_route\.json$" 0

  # --- I6 脚本判断不了的登录模式（PAT）：路由原样保留，base_url 也不动 ---
  seed_live c_load_pat_ok 'model = "gpt-5.5"
model_provider = "myrelay"

[model_providers.myrelay]
base_url = "https://relay.example.com/v1"
'
  hapi_write_codex_current_config "pat-key" "https://other.example.com/v1" "gpt-5.5" > "${WORK_DIR}/i6.log" 2>&1
  expect_rc "PAT 模式下写入成功" 0 "$?"
  expect_count "PAT 模式保留原路由" "${HOME}/.codex/config.toml" '^model_provider = "myrelay"$' 1
  expect_count "PAT 模式不覆盖原 base_url" "${HOME}/.codex/config.toml" 'base_url = "https://relay.example.com/v1"' 1
  expect_count "PAT 模式不写入本次 base_url" "${HOME}/.codex/config.toml" "https://other.example.com/v1" 0
  expect_grep "提示脚本无法判断路由" "${WORK_DIR}/i6.log" "无法判断"

  # --- I7 预览：显示暂存路由，但不打印暂存里的 token ---
  seed_live ok_official 'model = "gpt-5.5"
model_provider = "myrelay"

[model_providers.myrelay]
base_url = "https://relay.example.com/v1"
experimental_bearer_token = "sk-should-not-print"
'
  hapi_sync_codex_route > /dev/null 2>&1
  hapi_show_codex_config > "${WORK_DIR}/i7.log" 2>&1
  expect_grep "查看配置显示暂存路由" "${WORK_DIR}/i7.log" "暂存的第三方路由"
  expect_grep "显示暂存 provider id" "${WORK_DIR}/i7.log" "provider id: myrelay"
  expect_count "不打印暂存里的 token" "${WORK_DIR}/i7.log" "sk-should-not-print" 0

  # --- I8 空配置 + 官方登录：不凭空建第三方路由 ---
  rm -rf "${HOME}/.codex"; mkdir -p "${HOME}/.codex"
  cp "$(fx_path ok_official)" "${HOME}/.codex/auth.json"
  hapi_write_codex_current_config "" "https://api.openai.com/v1" "gpt-5.5" > "${WORK_DIR}/i8.log" 2>&1
  expect_rc "空配置 + 官方登录写入成功" 0 "$?"
  expect_count "空配置下不建 model_provider" "${HOME}/.codex/config.toml" "model_provider" 0
  expect_count "空配置下不建 provider 段" "${HOME}/.codex/config.toml" "model_providers" 0
  expect_grep "提示保持官方路由" "${WORK_DIR}/i8.log" "保持不指定 model_provider"

  # 空配置分支同样必须写 auth.json（曾经因为提前 exit 漏掉过），所以用"文件本来不存在"来验证
  rm -rf "${HOME}/.codex"; mkdir -p "${HOME}/.codex"
  hapi_write_codex_current_config "sk-first-run" "https://api.openai.com/v1" "gpt-5.5" > /dev/null 2>&1
  expect_count "空配置 + 无 auth.json 时仍创建 auth.json" "${HOME}/.codex/auth.json" '"OPENAI_API_KEY": "sk-first-run"' 1
  expect_count "空配置 + 无 auth.json 时也不建第三方路由" "${HOME}/.codex/config.toml" "model_provider" 0

  # --- I9 近似官方域名（api.openai.com.evil.com）必须按第三方处理，不得误剥离 ---
  rm -f "${STASH}"
  seed_live ok_official $'model = "gpt-5.5"\n'
  hapi_write_codex_current_config "sk-lookalike" "https://api.openai.com.evil.com/v1" "gpt-5.5" > "${WORK_DIR}/i9.log" 2>&1
  expect_rc "近似官方域名下写入成功" 0 "$?"
  expect_count "近似官方域名按第三方处理（建路由）" "${HOME}/.codex/config.toml" '^model_provider = "custom"$' 1
  expect_count "近似官方域名下 base_url 原样写入" "${HOME}/.codex/config.toml" 'base_url = "https://api.openai.com.evil.com/v1"' 1
  expect_count "近似官方域名不产生暂存文件" <(ls -A "${HOME}/.codex" 2>/dev/null) "^hapi_provider_route\.json$" 0

  # --- I10 对照：暂存文件不存在 → 允许按新配置建 generic custom ---
  rm -f "${STASH}"
  seed_live ok_official $'model = "gpt-5.5"\n'
  hapi_write_codex_current_config "sk-generic" "https://relay4.example.com/v1" "gpt-5.5" > "${WORK_DIR}/i10.log" 2>&1
  expect_rc "无暂存文件时写入成功" 0 "$?"
  expect_count "无暂存文件时建 generic custom" "${HOME}/.codex/config.toml" '^model_provider = "custom"$' 1
  expect_count "generic custom 段用本次 base_url" "${HOME}/.codex/config.toml" 'base_url = "https://relay4.example.com/v1"' 1

  # --- I11 暂存文件损坏 → fail-closed：不静默降级成 generic custom，两个文件都不动 ---
  seed_live ok_official $'model = "gpt-5.5"\n'
  printf '%s' '{"providerId": "myrelay", "sectionLines": [' > "${STASH}"   # 截断的 JSON
  before_auth=$(cat "${HOME}/.codex/auth.json")
  before_cfg=$(cat "${HOME}/.codex/config.toml")
  hapi_write_codex_current_config "sk-broken" "https://relay5.example.com/v1" "gpt-5.5" > "${WORK_DIR}/i11.log" 2>&1
  expect_rc "暂存文件损坏时中止写入（非 0）" 1 "$?"
  expect_eq "损坏时 config.toml 未被改动" "${before_cfg}" "$(cat "${HOME}/.codex/config.toml")"
  expect_eq "损坏时 auth.json 未被改动" "${before_auth}" "$(cat "${HOME}/.codex/auth.json")"
  expect_grep "明确提示暂存路由文件已损坏" "${WORK_DIR}/i11.log" "暂存的路由文件已损坏"
  expect_count "损坏时不建 generic custom" "${HOME}/.codex/config.toml" "model_providers" 0

  # 另一种损坏形态：能解析、但字段不合法
  printf '%s' '{"providerId": "myrelay", "sectionLines": "oops"}' > "${STASH}"
  hapi_write_codex_current_config "sk-broken2" "https://relay5.example.com/v1" "gpt-5.5" > "${WORK_DIR}/i11b.log" 2>&1
  expect_rc "字段不合法的暂存文件同样中止（非 0）" 1 "$?"
  expect_eq "字段不合法时 config.toml 未被改动" "${before_cfg}" "$(cat "${HOME}/.codex/config.toml")"

  # --- I12 官方登录 + 损坏暂存：剥离照常（用新内容覆盖），但要明确警告 ---
  seed_live ok_official $'model = "gpt-5.5"\nmodel_provider = "myrelay"\n'
  printf '%s' 'not-json' > "${STASH}"
  hapi_sync_codex_route > "${WORK_DIR}/i12.log" 2>&1
  expect_rc "损坏暂存不影响官方剥离" 0 "$?"
  expect_count "剥离后 config.toml 已无路由" "${HOME}/.codex/config.toml" "model_provider" 0
  expect_grep "警告原暂存文件已损坏并被覆盖" "${WORK_DIR}/i12.log" "已损坏"
  expect_count "损坏文件被新的暂存内容覆盖" "${STASH}" '"providerId": "myrelay"' 1

  # --- I13 端到端：生产代码自己把 config.toml 剥成空文件后，第三方输入必须恢复原 provider ---
  # 现场是生产剥离造出来的（不是手造"空 config + stash"）：只写了第三方路由的配置被官方同步剥离后，
  # config.toml 只剩一个换行。首版实现在这里提前 exit，于是下次填第三方 base_url 会绕过暂存、
  # 静默建成 generic custom，原 provider 的 id / query_params / requires_openai_auth 全丢。
  rm -f "${STASH}"
  seed_live ok_official 'model_provider = "myrelay"

[model_providers.myrelay]
name = "MyRelay"
base_url = "https://old.example.com/v1"
env_key = "OPENAI_API_KEY"
requires_openai_auth = true
query_params = { foo = "bar" }
'
  hapi_sync_codex_route > "${WORK_DIR}/i13a.log" 2>&1
  expect_rc "仅路由配置可被官方同步剥离" 0 "$?"
  expect_count "剥离后 config.toml 里没有路由" "${HOME}/.codex/config.toml" "model_provider" 0
  expect_count "生产剥离后暂存仍是 myrelay" "${STASH}" '"providerId": "myrelay"' 1
  expect_eq "生产剥离后 config.toml 已成为空文件" "" "$(cat "${HOME}/.codex/config.toml")"

  hapi_write_codex_current_config "sk-native-restore" "https://relay-native.example.com/v1" "gpt-5.5" > "${WORK_DIR}/i13b.log" 2>&1
  expect_rc "空配置下填第三方 base_url 写入成功" 0 "$?"
  expect_count "空配置恢复原 provider id" "${HOME}/.codex/config.toml" '^model_provider = "myrelay"$' 1
  expect_count "空配置恢复 provider 段" "${HOME}/.codex/config.toml" '^\[model_providers\.myrelay\]$' 1
  expect_count "空配置恢复 query_params" "${HOME}/.codex/config.toml" "query_params" 1
  expect_count "空配置恢复 requires_openai_auth" "${HOME}/.codex/config.toml" "requires_openai_auth = true" 1
  expect_count "空配置按本次 base_url 更新端点" "${HOME}/.codex/config.toml" 'base_url = "https://relay-native.example.com/v1"' 1
  expect_count "空配置下不建 generic custom" "${HOME}/.codex/config.toml" 'name = "custom"' 0
  expect_grep "空配置恢复时提示已恢复路由" "${WORK_DIR}/i13b.log" "已自动恢复此前的第三方路由"

  # --- I14 预览的 stash 结构校验必须和写入侧 readStash() 同规则 ---
  seed_live ok_official $'model = "gpt-5.5"\n'
  printf '%s' '{"providerId": "openai", "sectionLines": []}' > "${STASH}"
  hapi_show_codex_config > "${WORK_DIR}/i14a.log" 2>&1
  expect_grep "预览把保留 providerId 判为格式异常" "${WORK_DIR}/i14a.log" "格式异常"
  printf '%s' '{"providerId": "myrelay", "sectionLines": [1, 2]}' > "${STASH}"
  hapi_show_codex_config > "${WORK_DIR}/i14b.log" 2>&1
  expect_grep "预览把非字符串 sectionLines 判为格式异常" "${WORK_DIR}/i14b.log" "格式异常"
  printf '%s' '{"providerId": "myrelay", "sectionLines": [], "extraTopLevelLines": "oops"}' > "${STASH}"
  hapi_show_codex_config > "${WORK_DIR}/i14c.log" 2>&1
  expect_grep "预览把非字符串数组 extraTopLevelLines 判为格式异常" "${WORK_DIR}/i14c.log" "格式异常"
  printf '%s' '{"providerId": "myrelay", "sectionLines": ["[model_providers.myrelay]"]}' > "${STASH}"
  hapi_show_codex_config > "${WORK_DIR}/i14d.log" 2>&1
  expect_grep "对照：合法 stash 正常显示 provider id" "${WORK_DIR}/i14d.log" "provider id: myrelay"
  expect_count "对照：合法 stash 不报格式异常" "${WORK_DIR}/i14d.log" "格式异常" 0
fi

done_
[ "${FAIL}" -eq 0 ]
TESTS

# ============================================================
# 3) 组装并运行 harness（有界：timeout + stdin 钉死）
# ============================================================
build_harness() {   # $1 = 源脚本；$2 = 输出 harness
  {
    printf '#!/usr/bin/env bash\n'
    cat "${WORK}/prelude.sh"
    extract_lib "$1"
    printf '\n'
    cat "${WORK}/stubs.sh"
    printf '\n'
    cat "${WORK}/tests.sh"
  } > "$2"
  bash -n "$2" || return 1
}

# 被测脚本路径与编辑器参数记录文件要传给 harness（prelude 里展开）
export TARGET_SCRIPT="${TARGET}"
: > "${WORK}/editor_targets.log"
: > "${WORK}/vim_args.log"
export EDITOR_TARGET_LOG="${WORK}/editor_targets.log"
export VIM_ARGS_LOG="${WORK}/vim_args.log"

build_harness "${TARGET}" "${WORK}/harness.sh" || { echo "harness 生成失败"; exit 2; }

echo "=========== 被测：${TARGET} ==========="
echo "进度日志: ${LOG}"
bounded "${HARNESS_TIMEOUT}" bash "${WORK}/harness.sh"
NORMAL_RC=$?
if [ "${NORMAL_RC}" -eq 124 ]; then
  echo "  NOT OK - harness 超时（${HARNESS_TIMEOUT}s）被强制终止，可能有死循环；日志尾部见 ${LOG}"
fi

echo
if [ "${NORMAL_RC}" -eq 0 ]; then
  echo "RESULT: PASS  (日志: ${LOG})"
  exit 0
fi
echo "RESULT: FAIL（harness rc=${NORMAL_RC}；日志: ${LOG}）"
exit 1
