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
if [ "$(uname -o)" = "Android" ]; then
    echo -e "${red}不支持Android环境${background}"
    exit 1
fi
if [ ! "$(uname)" = "Linux" ]; then
    echo -e "${red}请在Linux系统上运行${background}"
    exit 1
fi

URL="https://ipinfo.io"
Address=$(curl -sL ${URL} | sed -n 's/.*"country": "\(.*\)",.*/\1/p')
if [ "${Address}" = "CN" ]; then
    GitMirror="gitee.com"
    GithubMirror="https://ghfast.top/"
else
    GitMirror="github.com"
    GithubMirror=""
fi

# 按任意键继续函数
pause() {
    echo -en "${yellow}按回车键继续...${background}"
    read
}

# Hapi / Claude Code 管理辅助函数
HAPI_HUB_TMUX_NAME="hapi_hub"
HAPI_SELECTED_WORKSPACES=()
HAPI_HUB_URL=""
# Hapi 的 tunwg 首次分配隧道地址最多会等待 30 秒；这里留出少量余量。
HAPI_HUB_URL_WAIT_SECONDS="${HAPI_HUB_URL_WAIT_SECONDS:-40}"

# opencode 网页控制台 (WebUI / headless) 相关变量
HAPI_OPENCODE_WEB_TMUX_NAME="opencode_web"
HAPI_OPENCODE_WEB_URL=""
HAPI_OPENCODE_WEB_PHONE_URL=""
HAPI_OPENCODE_WEB_PUBLIC_URL=""
HAPI_OPENCODE_WEB_AUTH=""
HAPI_OPENCODE_WEB_USERNAME=""
HAPI_OPENCODE_WEB_PASSWORD=""

hapi_load_node_env() {
    if [ -d "/usr/local/node/bin" ]; then
        PATH="${PATH}:/usr/local/node/bin"
    fi
    if [ ! -d "${HOME}/.local/share/pnpm" ]; then
        mkdir -p "${HOME}/.local/share/pnpm"
    fi
    PATH="${PATH}:${HOME}/.local/share/pnpm:/root/.local/share/pnpm"
    PNPM_HOME="${HOME}/.local/share/pnpm"
    export PATH PNPM_HOME
    hash -r 2>/dev/null
}

hapi_ensure_pnpm() {
    hapi_load_node_env
    if command -v pnpm >/dev/null 2>&1; then
        return 0
    fi

    if command -v npm >/dev/null 2>&1; then
        echo -e "${yellow}未检测到 pnpm，正在使用 npm 安装 pnpm...${background}"
        npm install -g pnpm@latest
        hapi_load_node_env
    fi

    if ! command -v pnpm >/dev/null 2>&1; then
        echo -e "${red}未检测到 pnpm/npm，请先安装 Node.js 环境。${background}"
        return 1
    fi
}

hapi_ensure_command() {
    hapi_load_node_env
    if ! command -v hapi >/dev/null 2>&1; then
        echo -e "${red}未检测到 hapi 命令，请先安装/更新 Hapi。${background}"
        return 1
    fi
}

hapi_ensure_opencode() {
    hapi_load_node_env
    if ! command -v opencode >/dev/null 2>&1; then
        echo -e "${red}未检测到 opencode 命令，请先安装/更新 opencode。${background}"
        return 1
    fi
}

hapi_ensure_tmux() {
    if command -v tmux >/dev/null 2>&1; then
        return 0
    fi

    echo -e "${yellow}未检测到 tmux，正在尝试自动安装...${background}"
    if command -v apt >/dev/null 2>&1; then
        sudo apt update && sudo apt install -y tmux
    elif command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -y && sudo apt-get install -y tmux
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y tmux
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y tmux
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -Sy --noconfirm --needed tmux
    fi

    if ! command -v tmux >/dev/null 2>&1; then
        echo -e "${red}tmux 安装失败，请手动安装后重试。${background}"
        return 1
    fi
}

hapi_print_tmux_log() {
    local session_name="$1"
    local service_label="$2"
    local pane_output

    if ! command -v tmux >/dev/null 2>&1 || ! tmux has-session -t "${session_name}" 2>/dev/null; then
        echo -e "${yellow}${service_label} tmux 会话不存在，无法捕获日志。${background}"
        return 1
    fi

    pane_output=$(tmux capture-pane -pt "${session_name}" -S -200 2>/dev/null)
    echo -e "${white}=====${yellow}${service_label} tmux 最近日志${white}=====${background}"
    if [ -n "${pane_output}" ]; then
        printf '%s\n' "${pane_output}"
    else
        echo -e "${yellow}tmux pane 暂无输出。${background}"
    fi
    echo -e "${white}========================================${background}"
}

hapi_generate_secure_password() {
    local generated

    if command -v openssl >/dev/null 2>&1; then
        generated=$(openssl rand -base64 24 2>/dev/null | tr -d '\n')
    fi
    if [ -z "${generated}" ] && [ -r /dev/urandom ]; then
        generated=$(LC_ALL=C tr -dc 'A-Za-z0-9_@%+=:,.~-' < /dev/urandom | head -c 32)
    fi

    if [ -z "${generated}" ]; then
        return 1
    fi
    printf '%s' "${generated}"
}

hapi_json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

hapi_report_install_failure() {
    local install_status="$1"
    local package_label="$2"

    if [ "${install_status}" -eq 137 ]; then
        echo -e "${red}${package_label} 安装/更新失败：安装进程被系统终止（Killed），通常是内存不足或 Swap 不足导致。${background}"
        echo -e "${yellow}建议关闭占用内存的程序，或增加 Swap 后重新执行安装。${background}"
    else
        echo -e "${red}${package_label} 安装/更新失败，退出码：${install_status}。请检查上方输出。${background}"
    fi
}

hapi_install_claude_code() {
    local install_status

    hapi_ensure_pnpm || return
    echo -e "${yellow}正在安装/更新 Claude Code...${background}"
    pnpm add -g @anthropic-ai/claude-code --allow-build=@anthropic-ai/claude-code
    install_status=$?
    if [ "${install_status}" -ne 0 ]; then
        hapi_report_install_failure "${install_status}" "Claude Code"
        return "${install_status}"
    fi
    if command -v claude >/dev/null 2>&1; then
        claude --version
    fi
}

hapi_install_codex() {
    local install_status

    hapi_ensure_pnpm || return
    echo -e "${yellow}正在安装/更新 Codex...${background}"
    pnpm add -g @openai/codex@latest
    install_status=$?
    if [ "${install_status}" -ne 0 ]; then
        hapi_report_install_failure "${install_status}" "Codex"
        return "${install_status}"
    fi
    hapi_load_node_env
    if command -v codex >/dev/null 2>&1; then
        codex --version
    fi
}

hapi_install_hapi() {
    local install_status

    hapi_ensure_pnpm || return
    echo -e "${yellow}正在安装/更新 Hapi...${background}"
    pnpm add -g @twsxtd/hapi
    install_status=$?
    if [ "${install_status}" -ne 0 ]; then
        hapi_report_install_failure "${install_status}" "Hapi"
        return "${install_status}"
    fi
    if command -v hapi >/dev/null 2>&1; then
        hapi --version
    fi
}

hapi_install_opencode() {
    local install_status

    hapi_ensure_pnpm || return
    echo -e "${yellow}正在安装/更新 opencode...${background}"
    pnpm add -g opencode-ai@latest --allow-build=opencode-ai
    install_status=$?
    if [ "${install_status}" -ne 0 ]; then
        hapi_report_install_failure "${install_status}" "opencode"
        return "${install_status}"
    fi
    hapi_load_node_env
    if command -v opencode >/dev/null 2>&1; then
        opencode --version
    fi
}

hapi_show_claude_config() {
    local settings_file="${1:-${HOME}/.claude/settings.json}"

    echo -e "${white}=====${green}当前 Claude Code 配置${white}=====${background}"
    if [ ! -f "${settings_file}" ]; then
        echo -e "${yellow}未找到配置文件: ${settings_file}${background}"
        return 1
    fi

    sed -E 's#("(ANTHROPIC_AUTH_TOKEN|ANTHROPIC_API_KEY|CLAUDE_CODE_OAUTH_TOKEN)"[[:space:]]*:[[:space:]]*")[^"]*#\1******#g' "${settings_file}"
}

hapi_claude_current_value() {
    local field="$1"
    local settings_file="${2:-${HOME}/.claude/settings.json}"

    hapi_ensure_node_json >/dev/null || return
    CLAUDE_SETTINGS_FILE="${settings_file}" CLAUDE_FIELD="${field}" node <<'NODE'
const fs = require("fs");
const settingsFile = process.env.CLAUDE_SETTINGS_FILE;
const field = process.env.CLAUDE_FIELD;

if (!settingsFile || !field || !fs.existsSync(settingsFile)) process.exit(0);

try {
  const raw = fs.readFileSync(settingsFile, "utf8");
  const config = raw.trim() ? JSON.parse(raw) : {};
  const env = config && typeof config === "object" && config.env && typeof config.env === "object" ? config.env : {};
  if (env[field] !== undefined && env[field] !== null) process.stdout.write(String(env[field]));
} catch {
  process.exit(0);
}
NODE
}

hapi_write_claude_settings_file() {
    local output_file="$1"
    local default_auth_token="$2"
    local default_base_url="${3:-https://api.deepseek.com/anthropic}"
    local default_haiku_model="${4:-claude-haiku-4-5-20251001}"
    local default_sonnet_model="${5:-claude-sonnet-4-5-20250929[1M]}"
    local default_opus_model="${6:-claude-opus-4-8[1M]}"
    local default_fable_model="${7:-claude-fable-5[1M]}"
    local default_max_effort="$8"
    local auth_token base_url haiku_model sonnet_model opus_model fable_model enable_max_effort
    local reasoning_suffix effort_line
    local auth_token_json base_url_json haiku_json sonnet_json sonnet_name_json opus_json opus_name_json fable_json fable_name_json

    while [ -z "${auth_token}" ]; do
        if [ -n "${default_auth_token}" ]; then
            echo -en "${cyan}请输入 ANTHROPIC_AUTH_TOKEN（已隐藏输入，回车保留当前值）: ${background}"
        else
            echo -en "${cyan}请输入 ANTHROPIC_AUTH_TOKEN（已隐藏输入）: ${background}"
        fi
        read -rs auth_token
        echo
        if [ -z "${auth_token}" ] && [ -n "${default_auth_token}" ]; then
            auth_token="${default_auth_token}"
        fi
        if [ -z "${auth_token}" ]; then
            echo -e "${red}ANTHROPIC_AUTH_TOKEN 不能为空。${background}"
        fi
    done

    echo -en "${cyan}请输入 ANTHROPIC_BASE_URL (默认 ${default_base_url}): ${background}"
    read -r base_url
    base_url=${base_url:-${default_base_url}}

    echo -e "${yellow}如需开启 [1m] 或 [1M] 上下文，请自行在模型名后添加。${background}"
    echo -e "${yellow}示例: claude-opus-4-8[1M] 或 claude-opus-4-8[1m]${background}"
    echo -e "${yellow}对应的 *_MODEL_NAME 字段会自动生成（去掉 [1M]/[1m] 后缀）。${background}"

    echo -en "${cyan}请输入 HAIKU_MODEL (默认 ${default_haiku_model}): ${background}"
    read -r haiku_model
    haiku_model=${haiku_model:-${default_haiku_model}}

    echo -en "${cyan}请输入 SONNET_MODEL (默认 ${default_sonnet_model}): ${background}"
    read -r sonnet_model
    sonnet_model=${sonnet_model:-${default_sonnet_model}}

    echo -en "${cyan}请输入 OPUS_MODEL (默认 ${default_opus_model}): ${background}"
    read -r opus_model
    opus_model=${opus_model:-${default_opus_model}}

    echo -en "${cyan}请输入 FABLE_MODEL (默认 ${default_fable_model}): ${background}"
    read -r fable_model
    fable_model=${fable_model:-${default_fable_model}}

    if [[ "${default_max_effort}" == "max" || "${default_max_effort}" == "y" || "${default_max_effort}" == "Y" ]]; then
        echo -en "${cyan}是否开启最大强度思考？[Y/n]: ${background}"
    else
        echo -en "${cyan}是否开启最大强度思考？[y/N]: ${background}"
    fi
    read -r enable_max_effort
    if [ -z "${enable_max_effort}" ]; then
        enable_max_effort="${default_max_effort}"
    fi
    reasoning_suffix=""
    effort_line=""
    if [[ "${enable_max_effort}" == "max" || "${enable_max_effort}" == "y" || "${enable_max_effort}" == "Y" ]]; then
        reasoning_suffix=","
        effort_line='    "CLAUDE_CODE_EFFORT_LEVEL": "max"'
    fi

    auth_token_json=$(hapi_json_escape "${auth_token}")
    base_url_json=$(hapi_json_escape "${base_url}")
    haiku_json=$(hapi_json_escape "${haiku_model}")
    sonnet_json=$(hapi_json_escape "${sonnet_model}")
    sonnet_name_json=$(hapi_json_escape "${sonnet_model%%\[*}")
    opus_json=$(hapi_json_escape "${opus_model}")
    opus_name_json=$(hapi_json_escape "${opus_model%%\[*}")
    fable_json=$(hapi_json_escape "${fable_model}")
    fable_name_json=$(hapi_json_escape "${fable_model%%\[*}")

    # 该文件含 ANTHROPIC_AUTH_TOKEN：先以 0600 建好（umask 077）再覆盖写入，
    # 避免出现「先 0644 再 chmod」的可读窗口。
    (umask 077; : > "${output_file}") || return 1
    chmod 600 "${output_file}" 2>/dev/null

    cat > "${output_file}" << EOF
{
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "${auth_token_json}",
    "ANTHROPIC_BASE_URL": "${base_url_json}",
    "ANTHROPIC_DEFAULT_FABLE_MODEL": "${fable_json}",
    "ANTHROPIC_DEFAULT_FABLE_MODEL_NAME": "${fable_name_json}",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "${haiku_json}",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "${opus_json}",
    "ANTHROPIC_DEFAULT_OPUS_MODEL_NAME": "${opus_name_json}",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "${sonnet_json}",
    "ANTHROPIC_DEFAULT_SONNET_MODEL_NAME": "${sonnet_name_json}",
    "ANTHROPIC_MODEL": "${sonnet_name_json}",
    "ANTHROPIC_REASONING_MODEL": "${opus_json}"${reasoning_suffix}
${effort_line}
  },
  "includeCoAuthoredBy": false
}
EOF
}

hapi_prompt_add_extra_env() {
    local settings_file="${1:-${HOME}/.claude/settings.json}"
    local confirm backup_file

    echo -e "${white}=====${green}Claude Code 额外参数${white}=====${background}"
    echo -e "${yellow}以下参数可优化 Claude Code 的性能和行为：${background}"
    echo -e "${cyan}env 环境变量：${background}"
    echo -e "  ${cyan}API_TIMEOUT_MS: 600000${background}"
    echo -e "  ${cyan}BASH_DEFAULT_TIMEOUT_MS: 600000${background}"
    echo -e "  ${cyan}BASH_MAX_TIMEOUT_MS: 600000${background}"
    echo -e "  ${cyan}CLAUDE_API_TIMEOUT: 600000${background}"
    echo -e "  ${cyan}CLAUDE_AUTOCOMPACT_PCT_OVERRIDE: 97${background}"
    echo -e "  ${cyan}CLAUDE_CODE_ATTRIBUTION_HEADER: 0${background}"
    echo -e "  ${cyan}CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: 1${background}"
    echo -e "  ${cyan}CLAUDE_CODE_PROXY_RESOLVES_HOSTS: 1${background}"
    echo -e "  ${cyan}DISABLE_INSTALLATION_CHECKS: 1${background}"
    echo -e "  ${cyan}MCP_TIMEOUT: 50000${background}"
    echo -e "  ${cyan}MCP_TOOL_TIMEOUT: 1800000${background}"
    echo "========================="
    echo -en "${green}是否添加这些额外参数？[y/N]: ${background}"
    read -r confirm

    if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
        echo -e "${yellow}已跳过添加额外参数。${background}"
        return 0
    fi

    if [ ! -f "${settings_file}" ]; then
        echo -e "${red}配置文件不存在: ${settings_file}${background}"
        return 1
    fi

    hapi_ensure_node_json || return
    backup_file="${settings_file}.bak"
    cp -a "${settings_file}" "${backup_file}"
    chmod 600 "${backup_file}" 2>/dev/null
    echo -e "${green}已备份原配置到: ${backup_file}${background}"

    CLAUDE_SETTINGS_FILE="${settings_file}" node <<'NODE'
const fs = require("fs");
const settingsFile = process.env.CLAUDE_SETTINGS_FILE;

try {
  const raw = fs.readFileSync(settingsFile, "utf8");
  const config = raw.trim() ? JSON.parse(raw) : {};

  if (!config.env || typeof config.env !== "object") {
    config.env = {};
  }

  config.env.API_TIMEOUT_MS = "600000";
  config.env.BASH_DEFAULT_TIMEOUT_MS = "600000";
  config.env.BASH_MAX_TIMEOUT_MS = "600000";
  config.env.CLAUDE_API_TIMEOUT = "600000";
  config.env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE = "97";
  config.env.CLAUDE_CODE_ATTRIBUTION_HEADER = "0";
  config.env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
  config.env.CLAUDE_CODE_PROXY_RESOLVES_HOSTS = "1";
  config.env.DISABLE_INSTALLATION_CHECKS = "1";
  config.env.MCP_TIMEOUT = "50000";
  config.env.MCP_TOOL_TIMEOUT = "1800000";

  fs.writeFileSync(settingsFile, JSON.stringify(config, null, 2) + "\n", { mode: 0o600 });
  try { fs.chmodSync(settingsFile, 0o600); } catch {}
} catch (error) {
  console.error("添加额外参数失败: " + error.message);
  process.exit(1);
}
NODE
    local status=$?
    if [ "${status}" -eq 0 ]; then
        echo -e "${green}Claude Code 额外参数已添加: ${settings_file}${background}"
    else
        echo -e "${red}添加额外参数失败。${background}"
        return "${status}"
    fi
}

hapi_config_claude() {
    local config_dir="${HOME}/.claude"
    local settings_file="${config_dir}/settings.json"
    local backup_file
    local current_auth_token current_base_url current_haiku_model current_sonnet_model current_opus_model current_fable_model current_max_effort

    hapi_show_claude_config "${settings_file}" || true

    if [ -f "${settings_file}" ]; then
        echo -en "${yellow}检测到已存在 Claude Code 配置，继续修改将覆盖原有配置！是否继续？[y/N]: ${background}"
        read -r overwrite
        if [[ "${overwrite}" != "y" && "${overwrite}" != "Y" ]]; then
            echo -e "${yellow}已取消配置。${background}"
            return
        fi
        backup_file="${settings_file}.bak"
        cp -a "${settings_file}" "${backup_file}"
        chmod 600 "${backup_file}" 2>/dev/null
        echo -e "${green}已备份原配置到: ${backup_file}${background}"
    fi

    current_auth_token=$(hapi_claude_current_value "ANTHROPIC_AUTH_TOKEN" "${settings_file}")
    if [ -z "${current_auth_token}" ]; then
        current_auth_token=$(hapi_claude_current_value "ANTHROPIC_API_KEY" "${settings_file}")
    fi
    if [ -z "${current_auth_token}" ]; then
        current_auth_token=$(hapi_claude_current_value "CLAUDE_CODE_OAUTH_TOKEN" "${settings_file}")
    fi
    current_base_url=$(hapi_claude_current_value "ANTHROPIC_BASE_URL" "${settings_file}")
    current_haiku_model=$(hapi_claude_current_value "ANTHROPIC_DEFAULT_HAIKU_MODEL" "${settings_file}")
    current_sonnet_model=$(hapi_claude_current_value "ANTHROPIC_DEFAULT_SONNET_MODEL" "${settings_file}")
    if [ -z "${current_sonnet_model}" ]; then
        current_sonnet_model=$(hapi_claude_current_value "ANTHROPIC_DEFAULT_SONNET_MODEL_NAME" "${settings_file}")
    fi
    if [ -z "${current_sonnet_model}" ]; then
        current_sonnet_model=$(hapi_claude_current_value "ANTHROPIC_MODEL" "${settings_file}")
    fi
    current_opus_model=$(hapi_claude_current_value "ANTHROPIC_DEFAULT_OPUS_MODEL" "${settings_file}")
    if [ -z "${current_opus_model}" ]; then
        current_opus_model=$(hapi_claude_current_value "ANTHROPIC_DEFAULT_OPUS_MODEL_NAME" "${settings_file}")
    fi
    if [ -z "${current_opus_model}" ]; then
        current_opus_model=$(hapi_claude_current_value "ANTHROPIC_REASONING_MODEL" "${settings_file}")
    fi
    current_fable_model=$(hapi_claude_current_value "ANTHROPIC_DEFAULT_FABLE_MODEL" "${settings_file}")
    if [ -z "${current_fable_model}" ]; then
        current_fable_model=$(hapi_claude_current_value "ANTHROPIC_DEFAULT_FABLE_MODEL_NAME" "${settings_file}")
    fi
    current_max_effort=$(hapi_claude_current_value "CLAUDE_CODE_EFFORT_LEVEL" "${settings_file}")

    mkdir -p "${config_dir}"
    hapi_write_claude_settings_file \
        "${settings_file}" \
        "${current_auth_token}" \
        "${current_base_url}" \
        "${current_haiku_model}" \
        "${current_sonnet_model}" \
        "${current_opus_model}" \
        "${current_fable_model}" \
        "${current_max_effort}" || return
    chmod 600 "${settings_file}"
    echo -e "${green}Claude Code 配置已写入: ${settings_file}${background}"

    hapi_prompt_add_extra_env "${settings_file}"
}

hapi_ensure_node_json() {
    if ! command -v node >/dev/null 2>&1; then
        echo -e "${red}未检测到 node，无法管理配置库。${background}"
        return 1
    fi
}

hapi_claude_profile_store_file() {
    printf '%s' "${HOME}/.claude/hapi_config_profiles.json"
}

hapi_save_claude_profile_from_file() {
    local profile_name="$1"
    local source_file="$2"
    local store_file
    store_file=$(hapi_claude_profile_store_file)

    hapi_ensure_node_json || return
    mkdir -p "$(dirname "${store_file}")"
    node -e 'const fs = require("fs"); const path = require("path"); const storeFile = process.argv[1]; const name = process.argv[2]; const sourceFile = process.argv[3]; const config = JSON.parse(fs.readFileSync(sourceFile, "utf8")); let store = { profiles: [] }; if (fs.existsSync(storeFile)) { try { store = JSON.parse(fs.readFileSync(storeFile, "utf8")); } catch {} } if (!Array.isArray(store.profiles)) store.profiles = []; const now = new Date().toISOString(); const idx = store.profiles.findIndex((item) => item && item.name === name); if (idx >= 0) { store.profiles[idx] = { ...store.profiles[idx], name, updatedAt: now, config }; } else { store.profiles.push({ name, createdAt: now, updatedAt: now, config }); } fs.mkdirSync(path.dirname(storeFile), { recursive: true }); fs.writeFileSync(storeFile, JSON.stringify(store, null, 2) + "\n", { mode: 0o600 }); try { fs.chmodSync(storeFile, 0o600); } catch {}' "${store_file}" "${profile_name}" "${source_file}" || return
    chmod 600 "${store_file}" 2>/dev/null
    echo -e "${green}配置已保存到配置库: ${profile_name}${background}"
}

hapi_list_claude_profiles() {
    local store_file
    store_file=$(hapi_claude_profile_store_file)

    hapi_ensure_node_json || return
    if [ ! -f "${store_file}" ]; then
        echo -e "${yellow}暂无已储存的 Claude Code 配置。${background}"
        return 1
    fi
    node -e 'const fs = require("fs"); const storeFile = process.argv[1]; let store = { profiles: [] }; try { store = JSON.parse(fs.readFileSync(storeFile, "utf8")); } catch {} const profiles = Array.isArray(store.profiles) ? store.profiles : []; if (profiles.length === 0) process.exit(1); profiles.forEach((item, index) => { console.log(`${index + 1}. ${item.name}    更新: ${item.updatedAt || "-"}`); });' "${store_file}" || {
        echo -e "${yellow}暂无已储存的 Claude Code 配置。${background}"
        return 1
    }
}

hapi_show_claude_profile_by_index() {
    local profile_index="$1"
    local store_file
    store_file=$(hapi_claude_profile_store_file)

    hapi_ensure_node_json || return
    node -e 'const fs = require("fs"); const storeFile = process.argv[1]; const index = Number(process.argv[2]) - 1; const store = JSON.parse(fs.readFileSync(storeFile, "utf8")); const profiles = Array.isArray(store.profiles) ? store.profiles : []; const profile = profiles[index]; if (!profile || !profile.config) { console.error("配置序号不存在"); process.exit(1); } const config = JSON.parse(JSON.stringify(profile.config)); if (config.env) { for (const key of ["ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_API_KEY", "CLAUDE_CODE_OAUTH_TOKEN"]) { if (config.env[key]) config.env[key] = "******"; } } console.log(`名称: ${profile.name}`); console.log(JSON.stringify(config, null, 2));' "${store_file}" "${profile_index}"
}

hapi_store_current_claude_config() {
    local settings_file="${HOME}/.claude/settings.json"
    local profile_name

    if [ ! -f "${settings_file}" ]; then
        echo -e "${yellow}当前没有 Claude Code 配置可储存: ${settings_file}${background}"
        return 1
    fi
    echo -en "${cyan}请输入配置名称: ${background}"
    read -r profile_name
    if [ -z "${profile_name}" ]; then
        echo -e "${red}配置名称不能为空。${background}"
        return 1
    fi
    hapi_save_claude_profile_from_file "${profile_name}" "${settings_file}"
}

hapi_create_claude_profile() {
    local profile_name tmp_file

    echo -en "${cyan}请输入新配置名称: ${background}"
    read -r profile_name
    if [ -z "${profile_name}" ]; then
        echo -e "${red}配置名称不能为空。${background}"
        return 1
    fi

    tmp_file=$(mktemp "${TMPDIR:-/tmp}/hapi_claude_settings.XXXXXX") || {
        echo -e "${red}临时文件创建失败，请确认系统有可用的 mktemp。${background}"
        return 1
    }
    chmod 600 "${tmp_file}" 2>/dev/null
    HAPI_CLAUDE_SETTINGS_TMP="${tmp_file}"
    hapi_install_sensitive_tmp_traps

    if ! hapi_write_claude_settings_file "${tmp_file}"; then
        hapi_cleanup_sensitive_tmp
        return 1
    fi
    if ! hapi_save_claude_profile_from_file "${profile_name}" "${tmp_file}"; then
        hapi_cleanup_sensitive_tmp
        return 1
    fi
    hapi_cleanup_sensitive_tmp
    echo -e "${yellow}新配置已保存，但未切换当前 Claude Code 配置。${background}"
}

hapi_switch_claude_profile() {
    local store_file settings_file config_dir backup_file num confirm
    store_file=$(hapi_claude_profile_store_file)
    config_dir="${HOME}/.claude"
    settings_file="${config_dir}/settings.json"

    hapi_list_claude_profiles || return
    echo -en "${green}请输入要切换的配置序号: ${background}"
    read -r num
    if [[ ! "${num}" =~ ^[0-9]+$ ]] || [ "${num}" -lt 1 ]; then
        echo -e "${red}请输入有效的序号。${background}"
        return 1
    fi

    echo -e "${white}=====${green}即将切换到以下配置${white}=====${background}"
    hapi_show_claude_profile_by_index "${num}" || return
    echo -en "${yellow}确认切换到该配置吗？[y/N]: ${background}"
    read -r confirm
    if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
        echo -e "${yellow}已取消切换。${background}"
        return
    fi

    mkdir -p "${config_dir}"
    if [ -f "${settings_file}" ]; then
        backup_file="${settings_file}.bak"
        cp -a "${settings_file}" "${backup_file}"
        chmod 600 "${backup_file}" 2>/dev/null
        echo -e "${green}已备份原配置到: ${backup_file}${background}"
    fi
    hapi_ensure_node_json || return
    node -e 'const fs = require("fs"); const storeFile = process.argv[1]; const settingsFile = process.argv[2]; const index = Number(process.argv[3]) - 1; const store = JSON.parse(fs.readFileSync(storeFile, "utf8")); const profiles = Array.isArray(store.profiles) ? store.profiles : []; if (!profiles[index] || !profiles[index].config) { console.error("配置序号不存在"); process.exit(1); } fs.writeFileSync(settingsFile, JSON.stringify(profiles[index].config, null, 2) + "\n", { mode: 0o600 }); try { fs.chmodSync(settingsFile, 0o600); } catch {} console.log(profiles[index].name);' "${store_file}" "${settings_file}" "${num}"
    local switch_status=$?
    if [ "${switch_status}" -ne 0 ]; then
        echo -e "${red}切换配置失败。${background}"
        return "${switch_status}"
    fi
    chmod 600 "${settings_file}"
    echo -e "${green}Claude Code 配置已切换: ${settings_file}${background}"

    hapi_prompt_add_extra_env "${settings_file}"
}

hapi_delete_claude_profile() {
    local store_file num confirm
    store_file=$(hapi_claude_profile_store_file)

    hapi_list_claude_profiles || return
    echo -en "${green}请输入要删除的配置序号: ${background}"
    read -r num
    if [[ ! "${num}" =~ ^[0-9]+$ ]] || [ "${num}" -lt 1 ]; then
        echo -e "${red}请输入有效的序号。${background}"
        return 1
    fi

    echo -e "${white}=====${green}即将删除以下配置${white}=====${background}"
    hapi_show_claude_profile_by_index "${num}" || return
    echo -en "${yellow}确认删除该配置吗？[y/N]: ${background}"
    read -r confirm
    if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
        echo -e "${yellow}已取消删除。${background}"
        return
    fi

    hapi_ensure_node_json || return
    node -e 'const fs = require("fs"); const storeFile = process.argv[1]; const index = Number(process.argv[2]) - 1; const store = JSON.parse(fs.readFileSync(storeFile, "utf8")); const profiles = Array.isArray(store.profiles) ? store.profiles : []; if (!profiles[index]) { console.error("配置序号不存在"); process.exit(1); } const removed = profiles.splice(index, 1)[0]; store.profiles = profiles; fs.writeFileSync(storeFile, JSON.stringify(store, null, 2) + "\n", { mode: 0o600 }); try { fs.chmodSync(storeFile, 0o600); } catch {} console.log(removed.name);' "${store_file}" "${num}"
    local delete_status=$?
    if [ "${delete_status}" -ne 0 ]; then
        echo -e "${red}删除配置失败。${background}"
        return "${delete_status}"
    fi
    chmod 600 "${store_file}" 2>/dev/null
    echo -e "${green}配置已删除。${background}"
}

hapi_claude_config_menu() {
    local num

    while true; do
        echo -e "${white}=====${green}Claude Code 配置${white}=====${background}"
        echo -e "${green}1.  ${cyan}查看/修改配置${background}"
        echo -e "${green}2.  ${cyan}储存当前配置${background}"
        echo -e "${green}3.  ${cyan}新建配置（不切换）${background}"
        echo -e "${green}4.  ${cyan}切换配置${background}"
        echo -e "${green}5.  ${cyan}删除配置${background}"
        echo -e "${green}0.  ${cyan}返回上一级${background}"
        echo "========================="
        echo -en "${green}请输入您的选项: ${background}"; read -r num

        case "${num}" in
        1) hapi_config_claude; pause ;;
        2) hapi_store_current_claude_config; pause ;;
        3) hapi_create_claude_profile; pause ;;
        4) hapi_switch_claude_profile; pause ;;
        5) hapi_delete_claude_profile; pause ;;
        0) return ;;
        *) echo -e "${red}输入错误${background}"; pause ;;
        esac
    done
}

hapi_codex_profile_store_file() {
    printf '%s' "${HOME}/.codex/hapi_config_profiles.json"
}

# 第三方路由暂存文件：官方登录/官方 Key 会把 config.toml 里的第三方路由（model_provider
# 与对应的 [model_providers.*] 段）整段剥离到这里，之后填第三方 base_url 时按原文恢复。
# 它可能带着第三方 bearer token，因此写入时同样按 0600 处理。
hapi_codex_route_stash_file() {
    printf '%s' "${HOME}/.codex/hapi_provider_route.json"
}

hapi_show_codex_config() {
    local config_dir auth_file config_file
    config_dir="${HOME}/.codex"
    auth_file="${config_dir}/auth.json"
    config_file="${config_dir}/config.toml"

    echo -e "${white}=====${green}当前 Codex 配置${white}=====${background}"
    hapi_ensure_node_json || return
    CODEX_AUTH_FILE="${auth_file}" CODEX_CONFIG_FILE="${config_file}" CODEX_STASH_FILE="$(hapi_codex_route_stash_file)" node <<'NODE'
const fs = require("fs");
const authFile = process.env.CODEX_AUTH_FILE;
const configFile = process.env.CODEX_CONFIG_FILE;
const stashFile = process.env.CODEX_STASH_FILE;

function isSensitiveKey(key) {
  const normalized = String(key).toLowerCase();
  return normalized === "openai_api_key"
    || normalized.includes("api_key")
    || normalized.includes("apikey")
    || normalized.includes("token")
    || normalized.includes("secret")
    || normalized.includes("experimental_bearer_token");
}

function sanitizeJson(value, key = "") {
  // tokens 是容器：只对子字段打码（access_token / id_token / refresh_token），
  // 保留 account_id 之类非密字段，便于人工核对粘贴结构。
  if (key === "tokens" && value && typeof value === "object" && !Array.isArray(value)) {
    return Object.fromEntries(Object.entries(value).map(([itemKey, itemValue]) => [itemKey, sanitizeJson(itemValue, itemKey)]));
  }
  if (isSensitiveKey(key) && value !== undefined && value !== null) return "******";
  if (Array.isArray(value)) return value.map((item) => sanitizeJson(item));
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([itemKey, itemValue]) => [itemKey, sanitizeJson(itemValue, itemKey)]));
  }
  return value;
}

function commentSuffix(rest) {
  let quote = "";
  let escaped = false;
  for (let i = 0; i < rest.length; i += 1) {
    const char = rest[i];
    if (quote) {
      if (quote === '"' && !escaped && char === "\\") {
        escaped = true;
        continue;
      }
      if (!escaped && char === quote) quote = "";
      escaped = false;
      continue;
    }
    if (char === '"' || char === "'") {
      quote = char;
      continue;
    }
    if (char === "#") return ` ${rest.slice(i).trimEnd()}`;
  }
  return "";
}

function sanitizeToml(text) {
  return text.split(/\r?\n/).map((line) => {
    const match = line.match(/^(\s*([A-Za-z0-9_.-]+)\s*=\s*)(.*)$/);
    if (match && isSensitiveKey(match[2])) {
      return `${match[1]}"******"${commentSuffix(match[3])}`;
    }
    return line;
  }).join("\n");
}

console.log("auth.json:");
if (!fs.existsSync(authFile)) {
  console.log(`未找到配置文件: ${authFile}`);
} else {
  try {
    const raw = fs.readFileSync(authFile, "utf8");
    const auth = raw.trim() ? JSON.parse(raw) : {};
    console.log(JSON.stringify(sanitizeJson(auth), null, 2));
  } catch (error) {
    console.log(`auth.json 读取失败: ${error.message}`);
    process.exitCode = 1;
  }
}

console.log("");
console.log("config.toml:");
if (!fs.existsSync(configFile)) {
  console.log(`未找到配置文件: ${configFile}`);
} else {
  const raw = fs.readFileSync(configFile, "utf8");
  console.log(sanitizeToml(raw) || "(空文件)");
}

// 官方登录/官方 Key 会把第三方路由剥离到暂存文件，这里只报 id 与时间（不打印内容，避免泄露 token）
//
// ⚠️ 下面这份结构校验必须与写入侧 readStash() 的规则保持同步（那边才是权威）。
//    漏同步的后果：写入侧判 invalid（会 fail-closed 拒绝恢复）的暂存，预览却显示成正常，
//    用户会以为还能恢复。readStash 的规则顺序：
//    顶层是对象 → providerId 是可用自定义 id → sectionLines 是字符串数组 → extraTopLevelLines（可选）是字符串数组。
const CODEX_RESERVED_MODEL_PROVIDER_IDS = [
  "amazon-bedrock",
  "amazon-bedrock-runtime",
  "openai",
  "ollama",
  "lmstudio",
];

function stashProblem(stash) {
  if (!stash || typeof stash !== "object" || Array.isArray(stash)) return "顶层不是 JSON 对象";
  const providerId = String(stash.providerId === undefined || stash.providerId === null ? "" : stash.providerId).trim();
  if (providerId === "" || CODEX_RESERVED_MODEL_PROVIDER_IDS.includes(providerId)) {
    return `providerId 不是可用的自定义 id（当前为 ${JSON.stringify(stash.providerId)}）`;
  }
  if (!Array.isArray(stash.sectionLines) || !stash.sectionLines.every((line) => typeof line === "string")) {
    return "sectionLines 缺失或不是字符串数组";
  }
  if (stash.extraTopLevelLines !== undefined
      && (!Array.isArray(stash.extraTopLevelLines) || !stash.extraTopLevelLines.every((line) => typeof line === "string"))) {
    return "extraTopLevelLines 不是字符串数组";
  }
  return "";
}

console.log("");
console.log("暂存的第三方路由（下次填写第三方 base_url 时自动恢复）:");
if (!stashFile || !fs.existsSync(stashFile)) {
  console.log("(无)");
} else {
  try {
    const stash = JSON.parse(fs.readFileSync(stashFile, "utf8"));
    const problem = stashProblem(stash);
    if (problem) {
      console.log(`格式异常（${problem}）: ${stashFile}`);
      console.log("写入第三方 base_url 时会被拒绝（fail-closed），请修复或删除该文件。");
    } else {
      console.log(`provider id: ${stash.providerId}    暂存于: ${stash.savedAt || "-"}    section 行数: ${stash.sectionLines.length}`);
      console.log(`暂存文件: ${stashFile}`);
    }
  } catch (error) {
    console.log(`暂存文件读取失败: ${error.message}`);
    console.log("写入第三方 base_url 时会被拒绝（fail-closed），请修复或删除该文件。");
  }
}
NODE
}

hapi_validate_codex_files() {
    local config_dir auth_file config_file
    config_dir="${HOME}/.codex"
    auth_file="${config_dir}/auth.json"
    config_file="${config_dir}/config.toml"

    hapi_ensure_node_json || return
    CODEX_AUTH_FILE="${auth_file}" CODEX_CONFIG_FILE="${config_file}" node <<'NODE'
const fs = require("fs");
const authFile = process.env.CODEX_AUTH_FILE;
const configFile = process.env.CODEX_CONFIG_FILE;

function parseSectionHeader(line, lineNo) {
  const trimmed = line.trim();
  if (!trimmed.startsWith("[")) return null;
  const match = trimmed.match(/^\[\[?\s*([^\[\]]+?)\s*\]?\]\s*(?:#.*)?$/);
  if (!match) throw new Error(`config.toml 第 ${lineNo} 行 section 格式异常`);
  return match[1].trim();
}

function parseTomlString(line, lineNo, key) {
  const eqIndex = line.indexOf("=");
  const raw = line.slice(eqIndex + 1).trim();
  if (!raw || raw.startsWith("#")) throw new Error(`config.toml 第 ${lineNo} 行 ${key} 缺少值`);
  if (raw.startsWith('"""') || raw.startsWith("'''")) {
    throw new Error(`config.toml 第 ${lineNo} 行 ${key} 暂不支持多行字符串`);
  }
  const quote = raw[0];
  if (quote === '"' || quote === "'") {
    let escaped = false;
    for (let i = 1; i < raw.length; i += 1) {
      const char = raw[i];
      if (quote === '"' && !escaped && char === "\\") {
        escaped = true;
        continue;
      }
      if (!escaped && char === quote) {
        const token = raw.slice(0, i + 1);
        if (quote === '"') {
          try {
            return JSON.parse(token);
          } catch {
            throw new Error(`config.toml 第 ${lineNo} 行 ${key} 字符串转义异常`);
          }
        }
        return raw.slice(1, i);
      }
      escaped = false;
    }
    throw new Error(`config.toml 第 ${lineNo} 行 ${key} 字符串未闭合`);
  }
  return raw.split(/\s+#/)[0].trim();
}

function validateToml(text) {
  const sensitiveKeys = new Set(["model", "model_provider", "base_url", "experimental_bearer_token"]);
  text.split(/\r?\n/).forEach((line, index) => {
    const lineNo = index + 1;
    parseSectionHeader(line, lineNo);
    const keyMatch = line.match(/^\s*([A-Za-z0-9_.-]+)\s*=/);
    if (keyMatch && sensitiveKeys.has(keyMatch[1])) parseTomlString(line, lineNo, keyMatch[1]);
  });
}

try {
  if (fs.existsSync(authFile)) {
    const raw = fs.readFileSync(authFile, "utf8");
    const auth = raw.trim() ? JSON.parse(raw) : {};
    if (!auth || typeof auth !== "object" || Array.isArray(auth)) throw new Error("auth.json 必须是 JSON 对象");
  }
  if (fs.existsSync(configFile)) validateToml(fs.readFileSync(configFile, "utf8"));
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
NODE
}

hapi_codex_current_value() {
    local field="$1"
    local config_dir auth_file config_file
    config_dir="${HOME}/.codex"
    auth_file="${config_dir}/auth.json"
    config_file="${config_dir}/config.toml"

    hapi_ensure_node_json >/dev/null || return
    CODEX_AUTH_FILE="${auth_file}" CODEX_CONFIG_FILE="${config_file}" CODEX_FIELD="${field}" node <<'NODE'
const fs = require("fs");
const authFile = process.env.CODEX_AUTH_FILE;
const configFile = process.env.CODEX_CONFIG_FILE;
const field = process.env.CODEX_FIELD;

function parseSectionHeader(line) {
  const match = line.trim().match(/^\[\[?\s*([^\[\]]+?)\s*\]?\]\s*(?:#.*)?$/);
  return match ? match[1].trim() : null;
}

function parseTomlString(line) {
  const eqIndex = line.indexOf("=");
  const raw = line.slice(eqIndex + 1).trim();
  const quote = raw[0];
  if (quote === '"' || quote === "'") {
    let escaped = false;
    for (let i = 1; i < raw.length; i += 1) {
      const char = raw[i];
      if (quote === '"' && !escaped && char === "\\") {
        escaped = true;
        continue;
      }
      if (!escaped && char === quote) {
        return quote === '"' ? JSON.parse(raw.slice(0, i + 1)) : raw.slice(1, i);
      }
      escaped = false;
    }
    return "";
  }
  return raw.split(/\s+#/)[0].trim();
}

function readConfigFields() {
  const result = { model: "", model_provider: "", base_url: "" };
  if (!fs.existsSync(configFile)) return result;
  const providerBaseUrls = {};
  let section = "";
  for (const line of fs.readFileSync(configFile, "utf8").split(/\r?\n/)) {
    const sectionName = parseSectionHeader(line);
    if (sectionName !== null) {
      section = sectionName;
      continue;
    }
    const keyMatch = line.match(/^\s*([A-Za-z0-9_.-]+)\s*=/);
    if (!keyMatch) continue;
    const key = keyMatch[1];
    if (!section && (key === "model" || key === "model_provider")) {
      result[key] = parseTomlString(line);
    } else if (section.startsWith("model_providers.") && key === "base_url") {
      providerBaseUrls[section.slice("model_providers.".length).replace(/^"|"$/g, "")] = parseTomlString(line);
    }
  }
  const providerId = result.model_provider || "custom";
  result.base_url = providerBaseUrls[providerId] || providerBaseUrls.custom || "";
  return result;
}

if (field === "OPENAI_API_KEY") {
  if (fs.existsSync(authFile)) {
    const raw = fs.readFileSync(authFile, "utf8");
    const auth = raw.trim() ? JSON.parse(raw) : {};
    if (auth.OPENAI_API_KEY) process.stdout.write(String(auth.OPENAI_API_KEY));
  }
} else {
  const config = readConfigFields();
  if (config[field]) process.stdout.write(String(config[field]));
}
NODE
}

hapi_write_codex_current_config() {
    local route_only=0
    if [ "$1" = "route-only" ]; then
        route_only=1
        shift
    fi
    local api_key="${1:-}"
    local base_url="${2:-}"
    local model="${3:-}"
    local config_dir auth_file config_file stash_file backup_file
    config_dir="${HOME}/.codex"
    auth_file="${config_dir}/auth.json"
    config_file="${config_dir}/config.toml"
    stash_file=$(hapi_codex_route_stash_file)

    hapi_ensure_node_json || return
    mkdir -p "${config_dir}"
    # route-only（菜单 7 写完官方 auth、菜单 4 切换配置之后）只收敛路由，不改 model / base_url / Key，
    # 也不碰 auth.json，因此不需要备份。
    if [ "${route_only}" -eq 0 ]; then
        if [ -f "${auth_file}" ]; then
            backup_file="${auth_file}.bak"
            cp -a "${auth_file}" "${backup_file}"
            chmod 600 "${backup_file}" 2>/dev/null
            echo -e "${green}已备份原配置到: ${backup_file}${background}"
        fi
        if [ -f "${config_file}" ]; then
            backup_file="${config_file}.bak"
            cp -a "${config_file}" "${backup_file}"
            chmod 600 "${backup_file}" 2>/dev/null
            echo -e "${green}已备份原配置到: ${backup_file}${background}"
        fi
    fi

    CODEX_AUTH_FILE="${auth_file}" CODEX_CONFIG_FILE="${config_file}" CODEX_STASH_FILE="${stash_file}" CODEX_API_KEY="${api_key}" CODEX_BASE_URL="${base_url}" CODEX_MODEL="${model}" CODEX_ROUTE_ONLY="${route_only}" node <<'NODE'
const fs = require("fs");
const path = require("path");
const authFile = process.env.CODEX_AUTH_FILE;
const configFile = process.env.CODEX_CONFIG_FILE;
const stashFile = process.env.CODEX_STASH_FILE;
const apiKey = process.env.CODEX_API_KEY || "";
const baseUrlInput = (process.env.CODEX_BASE_URL || "").trim();
const model = process.env.CODEX_MODEL || "gpt-5.5";
const routeOnly = process.env.CODEX_ROUTE_ONLY === "1";
// 菜单 1 的 base_url 提示语给出的默认值。只在「真的要写 base_url」的分支用它，
// route-only 不写 base_url，避免把官方默认值当成用户输入。
const defaultBaseUrl = "https://api.openai.com/v1";
const writeBaseUrl = baseUrlInput || defaultBaseUrl;

function tomlString(value) {
  return JSON.stringify(String(value));
}

function tomlKeySegment(value) {
  return /^[A-Za-z0-9_-]+$/.test(value) ? value : tomlString(value);
}

function parseSectionHeader(line, lineNo) {
  const trimmed = line.trim();
  if (!trimmed.startsWith("[")) return null;
  const match = trimmed.match(/^\[\[?\s*([^\[\]]+?)\s*\]?\]\s*(?:#.*)?$/);
  if (!match) throw new Error(`config.toml 第 ${lineNo} 行 section 格式异常`);
  return match[1].trim();
}

function parseTomlString(line, lineNo, key) {
  const eqIndex = line.indexOf("=");
  const raw = line.slice(eqIndex + 1).trim();
  if (!raw || raw.startsWith("#")) throw new Error(`config.toml 第 ${lineNo} 行 ${key} 缺少值`);
  if (raw.startsWith('"""') || raw.startsWith("'''")) {
    throw new Error(`config.toml 第 ${lineNo} 行 ${key} 暂不支持多行字符串`);
  }
  const quote = raw[0];
  if (quote === '"' || quote === "'") {
    let escaped = false;
    for (let i = 1; i < raw.length; i += 1) {
      const char = raw[i];
      if (quote === '"' && !escaped && char === "\\") {
        escaped = true;
        continue;
      }
      if (!escaped && char === quote) {
        const token = raw.slice(0, i + 1);
        if (quote === '"') {
          try {
            return JSON.parse(token);
          } catch {
            throw new Error(`config.toml 第 ${lineNo} 行 ${key} 字符串转义异常`);
          }
        }
        return raw.slice(1, i);
      }
      escaped = false;
    }
    throw new Error(`config.toml 第 ${lineNo} 行 ${key} 字符串未闭合`);
  }
  return raw.split(/\s+#/)[0].trim();
}

function commentSuffix(rest) {
  let quote = "";
  let escaped = false;
  for (let i = 0; i < rest.length; i += 1) {
    const char = rest[i];
    if (quote) {
      if (quote === '"' && !escaped && char === "\\") {
        escaped = true;
        continue;
      }
      if (!escaped && char === quote) quote = "";
      escaped = false;
      continue;
    }
    if (char === '"' || char === "'") {
      quote = char;
      continue;
    }
    if (char === "#") return ` ${rest.slice(i).trimEnd()}`;
  }
  return "";
}

function replaceAssignment(line, value) {
  const match = line.match(/^(\s*[A-Za-z0-9_.-]+\s*=\s*)(.*)$/);
  if (!match) return line;
  return `${match[1]}${tomlString(value)}${commentSuffix(match[2])}`;
}

function keyOf(line) {
  const match = line.match(/^\s*([A-Za-z0-9_.-]+)\s*=/);
  return match ? match[1] : "";
}

function firstSectionIndex(lines) {
  const index = lines.findIndex((line) => line.trim().startsWith("["));
  return index >= 0 ? index : lines.length;
}

function getTopLevelString(lines, key) {
  let section = "";
  for (let i = 0; i < lines.length; i += 1) {
    const sectionName = parseSectionHeader(lines[i], i + 1);
    if (sectionName !== null) {
      section = sectionName;
      continue;
    }
    if (!section && keyOf(lines[i]) === key) return parseTomlString(lines[i], i + 1, key);
  }
  return "";
}

function ensureTopLevelString(lines, key, value) {
  let section = "";
  for (let i = 0; i < lines.length; i += 1) {
    const sectionName = parseSectionHeader(lines[i], i + 1);
    if (sectionName !== null) {
      section = sectionName;
      continue;
    }
    if (!section && keyOf(lines[i]) === key) {
      lines[i] = replaceAssignment(lines[i], value);
      return;
    }
  }
  lines.splice(firstSectionIndex(lines), 0, `${key} = ${tomlString(value)}`);
}

function findSection(lines, sectionName, providerId) {
  let current = "";
  let start = -1;
  for (let i = 0; i < lines.length; i += 1) {
    const found = parseSectionHeader(lines[i], i + 1);
    if (found === null) continue;
    if (start >= 0) return { start, end: i };
    current = found;
    if (current === sectionName || (providerId && current === `model_providers.${tomlString(providerId)}`)) start = i;
  }
  return start >= 0 ? { start, end: lines.length } : null;
}

function updateExistingExperimentalToken(lines) {
  // 空 Key 不应该把已有的第三方 token 抹掉：只有确实填了新 Key 才覆盖
  if (!apiKey) return;
  for (let i = 0; i < lines.length; i += 1) {
    if (keyOf(lines[i]) === "experimental_bearer_token") lines[i] = replaceAssignment(lines[i], apiKey);
  }
}

function ensureFeatureGoals(lines) {
  const section = findSection(lines, "features");
  if (!section) {
    if (lines.length && lines[lines.length - 1].trim() !== "") lines.push("");
    lines.push("[features]", "goals = true");
    return;
  }
  for (let i = section.start + 1; i < section.end; i += 1) {
    if (keyOf(lines[i]) === "goals") return;
  }
  lines.splice(section.start + 1, 0, "goals = true");
}

function validateToml(text) {
  const sensitiveKeys = new Set(["model", "model_provider", "base_url", "experimental_bearer_token"]);
  text.split(/\r?\n/).forEach((line, index) => {
    const lineNo = index + 1;
    parseSectionHeader(line, lineNo);
    const key = keyOf(line);
    if (sensitiveKeys.has(key)) parseTomlString(line, lineNo, key);
  });
}

// Codex 保留的内置 provider id：cc-switch CODEX_RESERVED_MODEL_PROVIDER_IDS
// （0.149 就是这五个）。给这些 id 建 [model_providers.<id>] 表会让 Codex
// 在加载时直接拒绝整份 config.toml（validate_reserved_model_provider_ids，大小写敏感）。
const CODEX_RESERVED_MODEL_PROVIDER_IDS = [
  "amazon-bedrock",
  "amazon-bedrock-runtime",
  "openai",
  "ollama",
  "lmstudio",
];

function isCustomProviderId(id) {
  const trimmed = String(id === undefined || id === null ? "" : id).trim();
  return trimmed !== "" && !CODEX_RESERVED_MODEL_PROVIDER_IDS.includes(trimmed);
}

// 官方登录（auth.json 里是 ChatGPT OAuth）且没填 API Key 时，不能凭空造出
// `model_provider = "custom"`：Codex 在 model_provider 缺省时默认走内置 openai provider
// （见 cc-switch `active_codex_model_provider_id` 的注释），而 custom + env_key 又拿不到
// Key 时请求既进不了官方路由、也拿不到第三方凭据。
// 这条语义现在由 decideCodexRoute 的 official 目标承担；空配置也走同一条流程，
// 所以这里不再保留「按模板生成整份 config」的 createTemplate——
// 否则「空配置」会绕过暂存恢复（历史 bug：只写了第三方路由的 config 被剥离成空文件后，
// 下一次填第三方 base_url 会静默退化成 generic custom）。
//
// ---- 与 cc-switch 对齐的 Codex auth.json 语义（writer 与 validator 共用判定） ----

// codex_auth_resolved_mode 的「字段存在」：只要非 null 就算存在（空字符串也算），决定模式优先级
function fieldExistsForMode(value) {
  return value !== undefined && value !== null;
}

// codex_auth_has_openai_account_material 的 value_present：字符串必须非空白，容器必须非空
function credentialIsUsable(value) {
  if (value === undefined || value === null) return false;
  if (typeof value === "string") return value.trim() !== "";
  if (Array.isArray(value)) return value.length > 0;
  if (typeof value === "object") return Object.keys(value).length > 0;
  return true;
}

function resolveAuthMode(auth) {
  const mode = auth.auth_mode;
  if (fieldExistsForMode(mode)) {
    if (typeof mode !== "string") return "unrecognized";
    const known = ["apikey", "chatgpt", "chatgptAuthTokens", "headers", "agentIdentity", "personalAccessToken", "bedrockApiKey", "bedrockAccessKeys"];
    return known.includes(mode) ? mode : "unrecognized";
  }
  if (fieldExistsForMode(auth.personal_access_token)) return "personalAccessToken";
  if (fieldExistsForMode(auth.bedrock_api_key)) return "bedrockApiKey";
  if (fieldExistsForMode(auth.bedrock_access_keys)) return "bedrockAccessKeys";
  if (fieldExistsForMode(auth.OPENAI_API_KEY)) return "apikey";
  return "chatgpt";
}

function hasOfficialAccountMaterial(auth) {
  if (!auth || typeof auth !== "object" || Array.isArray(auth)) return false;
  switch (resolveAuthMode(auth)) {
  case "apikey":
    return credentialIsUsable(auth.OPENAI_API_KEY);
  case "personalAccessToken":
    return credentialIsUsable(auth.personal_access_token);
  case "agentIdentity":
    return credentialIsUsable(auth.agent_identity);
  case "chatgpt":
  case "chatgptAuthTokens": {
    const tokens = auth.tokens;
    if (!tokens || typeof tokens !== "object" || Array.isArray(tokens)) return false;
    return ["id_token", "access_token", "refresh_token"].some((key) => credentialIsUsable(tokens[key]));
  }
  default:
    return false;
  }
}

// ---- 路由判定与自动收敛（对照 cc-switch） ----
//
// cc-switch 的官方预设是 `auth: {}` + `config: ""`（src/config/codexProviderPresets.ts 里
// OpenAI Official 那条：`isOfficial: true` / `category: "official"` / 空 config），也就是
// 「官方 = config.toml 里既没有 model_provider，也没有 [model_providers.*]」；第三方预设则同时给出
// `model_provider = "custom"` 与 `[model_providers.custom]`。cc-switch 靠数据库保存每个供应商的
// config 文本，切回时整份写回（write_codex_live_config_atomic），本脚本没有数据库，
// 所以剥离时把这段原文存进暂存文件。
//
// ⚠️ 官方 host 判据是**本脚本自己加的保守规则**（host 精确等于 api.openai.com）：
//    cc-switch 没有「Codex 官方 host 分类」函数——它判断官方与否靠预设的 isOfficial / category，
//    以及 auth.json 侧的 codex_auth_has_openai_account_material。这个「host 精确匹配」的写法与
//    src-tauri/src/proxy/providers/codex.rs 的 `should_send_codex_chat_prompt_cache_key()`
//    （用途：决定转成 Chat Completions 后要不要发 prompt_cache_key）里的 host 比较形式一致，
//    但**用途不同**，引用时不要写成「cc-switch 定义了官方 host」。

function classifyBaseUrl(rawUrl) {
  const value = String(rawUrl || "").trim();
  if (!value) return "official";
  let host = "";
  try {
    host = new URL(value).hostname.toLowerCase();
  } catch {
    // 不是完整 URL（例如只写了 host，或用户手滑）：退化成手工取 host
    const match = value.match(/^(?:[A-Za-z][A-Za-z0-9+.-]*:\/\/)?([^/?#]*)/);
    host = (match ? match[1] : "").toLowerCase();
    const at = host.lastIndexOf("@");
    if (at >= 0) host = host.slice(at + 1);
    host = host.replace(/:\d+$/, "");
  }
  if (!host) return "unknown";
  return host === "api.openai.com" ? "official" : "third-party";
}

function providerBaseUrls(lines) {
  const result = {};
  let section = "";
  for (const line of lines) {
    const sectionName = parseSectionHeader(line, 0);
    if (sectionName !== null) {
      section = sectionName;
      continue;
    }
    if (section.startsWith("model_providers.") && keyOf(line) === "base_url") {
      result[section.slice("model_providers.".length).replace(/^"|"$/g, "")] = parseTomlString(line, 0, "base_url");
    }
  }
  return result;
}

function currentProviderBaseUrl(lines, providerId) {
  const baseUrls = providerBaseUrls(lines);
  return baseUrls[providerId] || baseUrls.custom || "";
}

// 返回 { target, notice }；target 取值:
//   "official"    要收敛到官方内置 openai provider（config.toml 不得有第三方路由）
//   "third-party" 要走第三方 provider（缺路由时恢复暂存的路由）
//   "keep"        保留 id / 脚本无法判断的模式：不动路由
//   "legacy"      既不是官方登录、也没有新的 Key：沿用旧行为（有路由更新，没有则建 custom 模板）
function decideCodexRoute(options) {
  const providerId = options.existingProviderId || "";
  if (providerId && !isCustomProviderId(providerId)) {
    // 内置/保留 provider：openai 本身就是官方路由；其余（ollama / lmstudio / bedrock）是别的内置后端，
    // 一律保持原样——既不补 model_provider 也不建表，否则 Codex 拒绝加载整份 config.toml。
    return { target: "keep", notice: "reserved" };
  }
  const mode = options.resolvedMode;
  if (mode !== "chatgpt" && mode !== "chatgptAuthTokens" && mode !== "apikey") {
    // PAT / agentIdentity / Bedrock：这些模式该配哪条路由脚本判断不了，宁可不动
    return { target: "keep", notice: "unsupported-mode" };
  }
  if (mode === "chatgpt" || mode === "chatgptAuthTokens") {
    if (options.officialLogin) {
      // auth.json 里是官方登录材料：默认走官方内置 provider（残留的第三方路由要剥离，
      // 否则官方登录只影响 Codex 识别到的账号，请求仍会发到第三方）。
      // 只有「本次明确填了第三方 base_url，且同时填了 Key」才按第三方路由处理。
      if (options.hasNewKey && options.baseUrlClass === "third-party") return { target: "third-party", notice: "" };
      return { target: "official", notice: "" };
    }
    if (options.hasNewKey) {
      if (options.baseUrlClass === "third-party") return { target: "third-party", notice: "" };
      if (options.baseUrlClass === "official") return { target: "official", notice: "" };
      return { target: "legacy", notice: "" };
    }
    // 没有可用登录材料、本次也没填 Key：不确认是官方，沿用旧行为（有路由更新，没有则建 custom 模板）
    return { target: "legacy", notice: "" };
  }
  // apikey：凭据就在 auth.json 里，官方/第三方只能靠 base_url 判断——
  // 第三方端点（中转/自建）要保留它自己的路由，不能因为"auth.json 有 Key"就当成官方登录剥掉。
  if (options.baseUrlClass === "official") return { target: "official", notice: "" };
  if (options.baseUrlClass === "third-party") return { target: "third-party", notice: "" };
  return { target: "keep", notice: "unknown-base-url" };
}

function removeTopLevelLine(lines, key) {
  let section = "";
  for (let i = 0; i < lines.length; i += 1) {
    const sectionName = parseSectionHeader(lines[i], i + 1);
    if (sectionName !== null) {
      section = sectionName;
      continue;
    }
    if (!section && keyOf(lines[i]) === key) {
      const removed = lines.splice(i, 1)[0];
      if (i < lines.length && i > 0 && lines[i].trim() === "" && lines[i - 1].trim() === "") lines.splice(i, 1);
      return removed;
    }
  }
  return "";
}

function ensureTopLevelRawLine(lines, rawLine) {
  const key = keyOf(rawLine);
  if (!key) return;
  let section = "";
  for (let i = 0; i < lines.length; i += 1) {
    const sectionName = parseSectionHeader(lines[i], i + 1);
    if (sectionName !== null) {
      section = sectionName;
      continue;
    }
    if (!section && keyOf(lines[i]) === key) return;
  }
  lines.splice(firstSectionIndex(lines), 0, rawLine);
}

// 摘掉整个段（含它前面的空行），返回段本身（去掉首尾空行），供暂存用
function takeSection(lines, section) {
  const body = lines.slice(section.start, section.end);
  while (body.length && body[body.length - 1].trim() === "") body.pop();
  lines.splice(section.start, section.end - section.start);
  if (section.start > 0 && section.start < lines.length && lines[section.start].trim() === "" && lines[section.start - 1].trim() === "") {
    lines.splice(section.start, 1);
  }
  return body;
}

function appendSection(lines, sectionLines) {
  if (lines.length && lines[lines.length - 1].trim() !== "") lines.push("");
  for (const line of sectionLines) lines.push(line);
}

// 暂存文件读取结果必须分**三态**，不能把 invalid 和 missing 混成同一个 null：
//   missing —— 文件不存在：允许退化成「新建 generic custom 模板」（旧行为，合理）
//   valid   —— 文件存在且合法：按原文恢复（provider id 与段内字段一起回来）
//   invalid —— 文件存在但损坏：**fail-closed**，中止本次写入，既不恢复也不新建
// 把 invalid 当 missing 的后果是「假恢复」：rc=0、悄悄建出 generic custom，
// 用户原来 provider 的 query_params / requires_openai_auth 等字段无声丢失。
function readStash() {
  if (!stashFile || !fs.existsSync(stashFile)) return { status: "missing", entry: null, reason: "" };
  let parsed = null;
  try {
    const raw = fs.readFileSync(stashFile, "utf8");
    parsed = raw.trim() ? JSON.parse(raw) : null;
  } catch (error) {
    return { status: "invalid", entry: null, reason: `JSON 解析失败: ${error.message}` };
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    return { status: "invalid", entry: null, reason: "顶层不是 JSON 对象" };
  }
  if (!isCustomProviderId(parsed.providerId)) {
    return { status: "invalid", entry: null, reason: `providerId 不是可用的自定义 id（当前为 ${JSON.stringify(parsed.providerId)}）` };
  }
  if (!Array.isArray(parsed.sectionLines) || !parsed.sectionLines.every((line) => typeof line === "string")) {
    return { status: "invalid", entry: null, reason: "sectionLines 缺失或不是字符串数组" };
  }
  if (parsed.extraTopLevelLines !== undefined
      && (!Array.isArray(parsed.extraTopLevelLines) || !parsed.extraTopLevelLines.every((line) => typeof line === "string"))) {
    return { status: "invalid", entry: null, reason: "extraTopLevelLines 不是字符串数组" };
  }
  return { status: "valid", entry: parsed, reason: "" };
}

function abortCorruptStash(reason) {
  console.error("暂存的路由文件已损坏，已中止本次写入（fail-closed）。");
  console.error(`  文件: ${stashFile}`);
  console.error(`  原因: ${reason}`);
  console.error("  为避免把原 provider 的字段（query_params / requires_openai_auth 等）静默换成 generic custom，");
  console.error("  auth.json 与 config.toml 均未改动。请修复该文件后重试；删除它则会按新配置生成 generic custom。");
  process.exit(1);
}

// 暂存文件里可能有第三方 bearer token，所以和 auth.json 一样按 0600 写
function writeStash(entry) {
  fs.mkdirSync(path.dirname(stashFile), { recursive: true });
  fs.writeFileSync(stashFile, `${JSON.stringify(entry, null, 2)}\n`, { mode: 0o600 });
  try { fs.chmodSync(stashFile, 0o600); } catch {}
}

function writeConfigText(text) {
  fs.mkdirSync(path.dirname(configFile), { recursive: true });
  fs.writeFileSync(configFile, text, { mode: 0o600 });
  try { fs.chmodSync(configFile, 0o600); } catch {}
}

// 凭据文件按 cc-switch atomic_write_private 的做法在创建时就指定 0600。
// 两条写盘路径（空配置 / 非空配置）都要写 auth.json——空配置分支曾经提前 exit 漏掉过这一句。
function writeAuthJson(auth) {
  fs.mkdirSync(path.dirname(authFile), { recursive: true });
  fs.writeFileSync(authFile, `${JSON.stringify(auth, null, 2)}\n`, { mode: 0o600 });
  try { fs.chmodSync(authFile, 0o600); } catch {}
}

try {
  let auth = {};
  if (fs.existsSync(authFile)) {
    const rawAuth = fs.readFileSync(authFile, "utf8");
    auth = rawAuth.trim() ? JSON.parse(rawAuth) : {};
    if (!auth || typeof auth !== "object" || Array.isArray(auth)) throw new Error("auth.json 必须是 JSON 对象");
  }
  // 先按 cc-switch 的 resolved mode 判定，再决定是否碰 OPENAI_API_KEY：
  // auth_mode 缺失/null 的隐式 ChatGPT 登录同样适用——cc-switch 的字段存在判定是
  // 「非 null 即存在」，所以写进空字符串会把隐式模式抢成 apikey，等于毁掉官方登录。
  const resolvedMode = resolveAuthMode(auth);
  const officialLogin = hasOfficialAccountMaterial(auth);
  if (!routeOnly) {
    if (resolvedMode === "chatgpt" || resolvedMode === "chatgptAuthTokens") {
      // 官方 auth.json 里 OPENAI_API_KEY 应为 null；写入空字符串会被 Codex 视为提供了 API Key，
      // 从而覆盖官方登录路径，因此这里只在用户确实填写了 Key 时才写入。
      if (apiKey) {
        console.error("提示: auth.json 当前是官方 ChatGPT 登录缓存，本次仍写入了 OPENAI_API_KEY。");
        console.error("      如需长期保留官方登录，请让第三方 Key 走 config.toml，或改用「7 写入/编辑官方 auth.json」。");
        auth.OPENAI_API_KEY = apiKey;
      } else {
        console.error("提示: auth.json 当前是官方 ChatGPT 登录缓存，未填写 API Key，已保留原有登录字段不变。");
      }
    } else {
      auth.OPENAI_API_KEY = apiKey;
    }
  }

  // 空配置 / 不存在的 config.toml 走**同一条**路由流程，不在这里提前 exit：
  // 「只写了第三方路由的 config.toml 被官方同步剥离」正好会把文件变成空文件（或只剩一个换行），
  // 这是本脚本自己会制造出来的状态。空配置若提前返回，下一次填第三方 base_url 就会绕过
  // 暂存直接建 generic custom —— 原 provider 的 id / query_params / requires_openai_auth 全丢。
  const rawConfig = fs.existsSync(configFile) ? fs.readFileSync(configFile, "utf8") : "";
  const emptyConfig = !rawConfig.trim();
  if (emptyConfig && routeOnly) {
    console.error("提示: config.toml 为空，无需同步 Codex 路由。");
    process.exit(0);
  }
  if (!emptyConfig) validateToml(rawConfig);
  const lines = emptyConfig ? [] : rawConfig.replace(/\r\n/g, "\n").split("\n");
  if (lines.length && lines[lines.length - 1] === "") lines.pop();
  // model 先写：空配置恢复路由时它才会落在文件顶部（与旧模板的字段顺序一致）
  if (!routeOnly) ensureTopLevelString(lines, "model", model);
  const existingProviderId = getTopLevelString(lines, "model_provider").trim();
  // route-only 没有 base_url 输入，就用 config.toml 里现有路由的 base_url 判断
  const baseUrlClass = classifyBaseUrl(baseUrlInput || currentProviderBaseUrl(lines, existingProviderId));
  const decision = decideCodexRoute({
    resolvedMode,
    officialLogin,
    hasNewKey: Boolean(apiKey),
    baseUrlClass,
    existingProviderId,
  });

  if (routeOnly && decision.target !== "official") {
    // route-only 只做「官方登录 → 剥离第三方路由」这一件事。恢复/新建第三方路由必须由用户在
    // 菜单 1 显式填 base_url 触发，避免切换配置时凭空造出一条没凭据的路由。
    console.error("提示: 当前 Codex 路由无需调整。");
    process.exit(0);
  }

  let routeAction = "none";
  let routeProviderId = existingProviderId;

  if (decision.target === "official") {
    if (isCustomProviderId(existingProviderId)) {
      const modelProviderLine = removeTopLevelLine(lines, "model_provider");
      const section = findSection(lines, `model_providers.${tomlKeySegment(existingProviderId)}`, existingProviderId);
      const sectionLines = section ? takeSection(lines, section) : [];
      const extraTopLevelLines = [];
      const bearerLine = removeTopLevelLine(lines, "experimental_bearer_token");
      if (bearerLine) extraTopLevelLines.push(bearerLine);
      if (modelProviderLine || sectionLines.length) {
        // 剥离会覆盖旧的暂存文件：旧文件要是坏的就明确说一声，别让用户以为它还在
        const previousStash = readStash();
        routeProviderId = existingProviderId;
        writeStash({
          version: 1,
          savedAt: new Date().toISOString(),
          providerId: existingProviderId,
          modelProviderLine: modelProviderLine || `model_provider = ${tomlString(existingProviderId)}`,
          sectionLines,
          extraTopLevelLines,
        });
        routeAction = "strip";
        if (previousStash.status === "invalid") {
          console.error(`警告: 原暂存文件 ${stashFile} 已损坏（${previousStash.reason}），本次剥离已用新的路由内容覆盖它。`);
        }
      }
    }
  } else if (decision.target === "third-party" && !isCustomProviderId(existingProviderId)) {
    const stash = readStash();
    // 三态：missing（文件不存在）→ 什么都不做，允许继续走下面的「新建 generic custom」分支（旧行为）；
    //       valid → 按原文恢复；invalid → fail-closed。
    // invalid 的处理早于任何写盘动作，所以 auth.json / config.toml「未改动」是结构性保证，不是巧合。
    if (stash.status === "invalid") abortCorruptStash(stash.reason);
    if (stash.status === "valid") {
      const entry = stash.entry;
      const stashSection = findSection(lines, `model_providers.${tomlKeySegment(entry.providerId)}`, entry.providerId);
      ensureTopLevelString(lines, "model_provider", entry.providerId);
      if (!stashSection && entry.sectionLines.length) appendSection(lines, entry.sectionLines);
      for (const rawLine of Array.isArray(entry.extraTopLevelLines) ? entry.extraTopLevelLines : []) {
        ensureTopLevelRawLine(lines, rawLine);
      }
      routeProviderId = entry.providerId;
      routeAction = "restore";
    }
  }

  // model 已经在路由处理之前写入（空配置场景下要保证它在文件顶部），这里只做
  // 「确实填了新 Key 才覆盖已有 token」这一件事。
  if (!routeOnly) updateExistingExperimentalToken(lines);

  if (decision.target === "official" || decision.target === "keep") {
    // 官方路由 / 保留 id：不创建也不更新任何 [model_providers.*] 段。
    // route-only 只做路由收敛，连 [features] 这类无关字段也不动（保持最小改动）。
    if (!routeOnly) ensureFeatureGoals(lines);
  } else {
    // third-party / legacy：沿用原有行为（有 route 就更新 base_url，没有就建默认 custom 模板）
    const providerId = routeProviderId || existingProviderId || "custom";
    if (!existingProviderId) ensureTopLevelString(lines, "model_provider", providerId);

    const sectionName = `model_providers.${tomlKeySegment(providerId)}`;
    const section = findSection(lines, sectionName, providerId);
    if (!section) {
      if (lines.length && lines[lines.length - 1].trim() !== "") lines.push("");
      lines.push(`[${sectionName}]`, `name = ${tomlString(providerId)}`, `base_url = ${tomlString(writeBaseUrl)}`, 'env_key = "OPENAI_API_KEY"', 'wire_api = "responses"');
    } else {
      let baseLine = -1;
      for (let i = section.start + 1; i < section.end; i += 1) {
        if (keyOf(lines[i]) === "base_url") {
          baseLine = i;
          break;
        }
      }
      if (baseLine >= 0) {
        lines[baseLine] = replaceAssignment(lines[baseLine], writeBaseUrl);
      } else {
        lines.splice(section.start + 1, 0, `base_url = ${tomlString(writeBaseUrl)}`);
      }
    }
    ensureFeatureGoals(lines);
  }

  const nextConfig = `${lines.join("\n")}\n`;
  const configChanged = nextConfig !== rawConfig;
  if (!routeOnly || configChanged) {
    writeConfigText(nextConfig);
  }
  if (!routeOnly) {
    writeAuthJson(auth);
  }

  if (routeAction === "strip") {
    console.error(`提示: 检测到官方登录/官方 API Key，已自动移除 config.toml 里的第三方路由（model_provider = "${routeProviderId}" 与其对应的 [model_providers.*] 段）。`);
    console.error(`      被移除的内容已暂存到 ${stashFile}，下次填写第三方 base_url 时会自动恢复。`);
  } else if (routeAction === "restore") {
    console.error(`提示: 已自动恢复此前的第三方路由 provider id = "${routeProviderId}"（来自 ${stashFile}），并按本次 base_url 更新端点。`);
  }

  if (decision.target === "official") {
    if (routeAction !== "strip") {
      console.error("提示: auth.json 是官方登录/官方 API Key，config.toml 保持不指定 model_provider，模型请求继续走内置 openai provider。");
    }
  } else if (decision.notice === "reserved") {
    console.error("提示: config.toml 里的 model_provider 指向 Codex 内置/保留 provider，已保持原样：");
    console.error("      不补 model_provider、也不创建 [model_providers.<id>]，因为覆盖保留 id 会让 Codex 拒绝加载整份配置。");
    console.error("      如需自定义 base_url，请改用自定义 provider id（菜单 1 默认写 custom）。");
  } else if (decision.notice === "unsupported-mode") {
    console.error(`提示: auth.json 的登录模式解析为 ${resolvedMode}，脚本无法判断它该走官方还是第三方，已保持 config.toml 的路由不变。`);
  } else if (decision.notice === "unknown-base-url") {
    console.error("提示: base_url 解析不出主机名，无法判断官方/第三方，已保持 config.toml 的路由不变。");
  } else if (officialLogin && !apiKey) {
    console.error("提示: config.toml 仍指定第三方 model_provider 且本次未填写 API Key，该路由可能拿不到可用凭据；");
    console.error("      如需完全回到官方，请清空 base_url 指向或改用官方端点。");
  }
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
NODE
    local write_status=$?
    if [ "${write_status}" -ne 0 ]; then
        echo -e "${red}Codex 配置写入失败。${background}"
        return "${write_status}"
    fi
    # 暂存文件里可能有第三方 bearer token，存在就再收紧一次权限（与备份同一处理方式）
    if [ -f "${stash_file}" ]; then
        chmod 600 "${stash_file}" 2>/dev/null
    fi
    if [ "${route_only}" -eq 1 ]; then
        chmod 600 "${config_file}" 2>/dev/null
        return 0
    fi
    chmod 600 "${auth_file}" "${config_file}" 2>/dev/null
    echo -e "${green}Codex 配置已写入: ${auth_file} / ${config_file}${background}"
}

# 只按 auth.json + config.toml 现状收敛路由：官方登录/官方 Key 会把第三方路由剥离并暂存。
# 供菜单 7（写完官方 auth.json）与菜单 4（切换配置）调用；不写 model / base_url / Key。
hapi_sync_codex_route() {
    local config_file="${HOME}/.codex/config.toml"

    if [ ! -f "${config_file}" ]; then
        echo -e "${yellow}未找到 ${config_file}，跳过 Codex 路由同步。${background}"
        return 0
    fi
    hapi_write_codex_current_config route-only
}

hapi_config_codex() {
    local config_dir="${HOME}/.codex"
    local auth_file="${config_dir}/auth.json"
    local config_file="${config_dir}/config.toml"
    local current_api_key current_base_url current_model api_key base_url model
    local auth_backup_file config_backup_file overwrite
    local default_base_url="https://api.openai.com/v1"
    local default_model="gpt-5.5"

    hapi_show_codex_config || true
    hapi_validate_codex_files || {
        echo -e "${red}检测到 Codex 配置格式异常，已中止修改。${background}"
        return 1
    }

    if [ -f "${auth_file}" ] || [ -f "${config_file}" ]; then
        echo -e "${yellow}说明: base_url 指向官方端点时 config.toml 不会保留第三方 model_provider（会剥离并暂存）；${background}"
        echo -e "${yellow}      指向第三方端点时会自动恢复此前暂存的路由。${background}"
        echo -en "${yellow}检测到已存在 Codex 配置，是否仅修改 key/model/base_url 等字段（其他配置会保留），是否继续修改？[y/N]: ${background}"
        read -r overwrite
        if [[ "${overwrite}" != "y" && "${overwrite}" != "Y" ]]; then
            echo -e "${yellow}已取消配置。${background}"
            return
        fi
        if [ -f "${auth_file}" ]; then
            auth_backup_file="${auth_file}.bak"
            cp -a "${auth_file}" "${auth_backup_file}"
            chmod 600 "${auth_backup_file}" 2>/dev/null
            echo -e "${green}已备份原配置到: ${auth_backup_file}${background}"
        fi
        if [ -f "${config_file}" ]; then
            config_backup_file="${config_file}.bak"
            cp -a "${config_file}" "${config_backup_file}"
            chmod 600 "${config_backup_file}" 2>/dev/null
            echo -e "${green}已备份原配置到: ${config_backup_file}${background}"
        fi
    fi

    current_api_key=$(hapi_codex_current_value "OPENAI_API_KEY")
    current_base_url=$(hapi_codex_current_value "base_url")
    current_model=$(hapi_codex_current_value "model")
    current_base_url=${current_base_url:-${default_base_url}}
    current_model=${current_model:-${default_model}}

    if [ -n "${current_api_key}" ]; then
        echo -en "${cyan}请输入 OPENAI_API_KEY（已隐藏输入，回车保留当前值）: ${background}"
    else
        echo -en "${cyan}请输入 OPENAI_API_KEY（已隐藏输入，默认留空）: ${background}"
    fi
    read -rs api_key
    echo
    if [ -z "${api_key}" ]; then
        api_key="${current_api_key}"
    fi

    echo -en "${cyan}请输入 base_url (默认 ${current_base_url}): ${background}"
    read -r base_url
    base_url=${base_url:-${current_base_url}}

    echo -en "${cyan}请输入 model (默认 ${current_model}): ${background}"
    read -r model
    model=${model:-${current_model}}

    hapi_write_codex_current_config "${api_key}" "${base_url}" "${model}"
}

hapi_toggle_codex_recommended_values() {
    local config_dir="${HOME}/.codex"
    local config_file="${config_dir}/config.toml"
    local confirm toggle_status

    echo -e "${white}=====${green}Codex 推荐值${white}=====${background}"
    echo -e "${yellow}将作用于 config.toml 顶部全局配置段，和 model = \"...\" 放在同一段。${background}"
    echo "store = false"
    echo "stream = true"
    echo 'include = [ "reasoning.encrypted_content" ]'
    echo 'api_protocol = "responses"'
    echo "========================="

    echo -en "${green}请选择操作：[1] 新增/更新 [2] 移除 [0] 取消: ${background}"
    read -r confirm
    case "${confirm}" in
    1)
        confirm="add"
        ;;
    2)
        confirm="remove"
        ;;
    0)
        echo -e "${yellow}已取消。${background}"
        return
        ;;
    *)
        echo -e "${red}输入错误${background}"
        return 1
        ;;
    esac

    hapi_ensure_node_json || return
    hapi_validate_codex_files || {
        echo -e "${red}检测到 Codex 配置格式异常，已中止修改。${background}"
        return 1
    }
    mkdir -p "${config_dir}"
    if [ -f "${config_file}" ]; then
        cp -a "${config_file}" "${config_file}.bak"
        chmod 600 "${config_file}.bak" 2>/dev/null
        echo -e "${green}已备份原配置到: ${config_file}.bak${background}"
    fi

    CODEX_CONFIG_FILE="${config_file}" CODEX_RECOMMENDED_ACTION="${confirm}" node <<'NODE'
const fs = require("fs");
const path = require("path");

const configFile = process.env.CODEX_CONFIG_FILE;
const action = process.env.CODEX_RECOMMENDED_ACTION;
const recommended = [
  "store = false",
  "stream = true",
  'include = [ "reasoning.encrypted_content" ]',
  'api_protocol = "responses"',
];
const recommendedKeys = new Set(["store", "stream", "include", "api_protocol"]);

function parseSectionHeader(line) {
  const match = line.trim().match(/^\[\[?\s*([^\[\]]+?)\s*\]?\]\s*(?:#.*)?$/);
  return match ? match[1].trim() : null;
}

function keyOf(line) {
  const match = line.match(/^\s*([A-Za-z0-9_.-]+)\s*=/);
  return match ? match[1] : "";
}

function firstSectionIndex(lines) {
  for (let i = 0; i < lines.length; i += 1) {
    if (parseSectionHeader(lines[i]) !== null) return i;
  }
  return lines.length;
}

function normalizeTrailingBlank(lines) {
  while (lines.length && lines[lines.length - 1] === "") lines.pop();
}

function removeTopLevelRecommended(lines) {
  const end = firstSectionIndex(lines);
  for (let i = end - 1; i >= 0; i -= 1) {
    if (recommendedKeys.has(keyOf(lines[i]))) lines.splice(i, 1);
  }
}

function topLevelInsertIndex(lines) {
  const end = firstSectionIndex(lines);
  for (let i = 0; i < end; i += 1) {
    if (keyOf(lines[i]) === "model") return i + 1;
  }
  return end;
}

function toggleRecommended(text) {
  const lines = text.replace(/\r\n/g, "\n").split("\n");
  normalizeTrailingBlank(lines);
  removeTopLevelRecommended(lines);

  if (action === "add") {
    lines.splice(topLevelInsertIndex(lines), 0, ...recommended);
  }

  return `${lines.join("\n")}\n`;
}

try {
  const rawConfig = fs.existsSync(configFile) ? fs.readFileSync(configFile, "utf8") : "";
  const nextConfig = toggleRecommended(rawConfig);
  fs.mkdirSync(path.dirname(configFile), { recursive: true });
  fs.writeFileSync(configFile, nextConfig, { mode: 0o600 });
  try { fs.chmodSync(configFile, 0o600); } catch {}
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
NODE
    toggle_status=$?
    if [ "${toggle_status}" -ne 0 ]; then
        echo -e "${red}Codex 推荐值切换失败。${background}"
        return "${toggle_status}"
    fi
    chmod 600 "${config_file}" 2>/dev/null
    if [ "${confirm}" = "add" ]; then
        echo -e "${green}Codex 推荐值已新增/更新。${background}"
    else
        echo -e "${green}Codex 推荐值已移除。${background}"
    fi
}

hapi_save_codex_profile_from_files() {
    local profile_name="$1"
    local source_auth_file="$2"
    local source_config_file="$3"
    local store_file
    store_file=$(hapi_codex_profile_store_file)

    hapi_ensure_node_json || return
    mkdir -p "$(dirname "${store_file}")"
    CODEX_STORE_FILE="${store_file}" CODEX_PROFILE_NAME="${profile_name}" CODEX_AUTH_FILE="${source_auth_file}" CODEX_CONFIG_FILE="${source_config_file}" node <<'NODE'
const fs = require("fs");
const path = require("path");
const storeFile = process.env.CODEX_STORE_FILE;
const name = process.env.CODEX_PROFILE_NAME;
const authFile = process.env.CODEX_AUTH_FILE;
const configFile = process.env.CODEX_CONFIG_FILE;

function parseSectionHeader(line, lineNo) {
  const trimmed = line.trim();
  if (!trimmed.startsWith("[")) return null;
  const match = trimmed.match(/^\[\[?\s*([^\[\]]+?)\s*\]?\]\s*(?:#.*)?$/);
  if (!match) throw new Error(`config.toml 第 ${lineNo} 行 section 格式异常`);
  return match[1].trim();
}

function validateToml(text) {
  text.split(/\r?\n/).forEach((line, index) => parseSectionHeader(line, index + 1));
}

function readStore() {
  if (!fs.existsSync(storeFile)) return { profiles: [] };
  const raw = fs.readFileSync(storeFile, "utf8");
  const store = raw.trim() ? JSON.parse(raw) : { profiles: [] };
  if (!Array.isArray(store.profiles)) store.profiles = [];
  return store;
}

try {
  let auth = {};
  if (fs.existsSync(authFile)) {
    const rawAuth = fs.readFileSync(authFile, "utf8");
    auth = rawAuth.trim() ? JSON.parse(rawAuth) : {};
    if (!auth || typeof auth !== "object" || Array.isArray(auth)) throw new Error("auth.json 必须是 JSON 对象");
  }
  const config = fs.existsSync(configFile) ? fs.readFileSync(configFile, "utf8") : "";
  validateToml(config);
  const store = readStore();
  const now = new Date().toISOString();
  const idx = store.profiles.findIndex((item) => item && item.name === name);
  const profile = { name, createdAt: now, updatedAt: now, config: { auth, config } };
  if (idx >= 0) {
    profile.createdAt = store.profiles[idx].createdAt || now;
    store.profiles[idx] = profile;
  } else {
    store.profiles.push(profile);
  }
  fs.mkdirSync(path.dirname(storeFile), { recursive: true });
  fs.writeFileSync(storeFile, `${JSON.stringify(store, null, 2)}\n`, { mode: 0o600 });
  try { fs.chmodSync(storeFile, 0o600); } catch {}
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
NODE
    local save_status=$?
    if [ "${save_status}" -ne 0 ]; then
        echo -e "${red}Codex 配置保存失败。${background}"
        return "${save_status}"
    fi
    chmod 600 "${store_file}" 2>/dev/null
    echo -e "${green}配置已保存到配置库: ${profile_name}${background}"
}

hapi_list_codex_profiles() {
    local store_file
    store_file=$(hapi_codex_profile_store_file)

    hapi_ensure_node_json || return
    if [ ! -f "${store_file}" ]; then
        echo -e "${yellow}暂无已储存的 Codex 配置。${background}"
        return 1
    fi
    CODEX_STORE_FILE="${store_file}" node <<'NODE'
const fs = require("fs");
const storeFile = process.env.CODEX_STORE_FILE;
let store = { profiles: [] };
try {
  store = JSON.parse(fs.readFileSync(storeFile, "utf8"));
} catch {}
const profiles = Array.isArray(store.profiles) ? store.profiles : [];
if (profiles.length === 0) process.exit(1);
profiles.forEach((item, index) => {
  console.log(`${index + 1}. ${item.name}    更新: ${item.updatedAt || "-"}`);
});
NODE
    local list_status=$?
    if [ "${list_status}" -ne 0 ]; then
        echo -e "${yellow}暂无已储存的 Codex 配置。${background}"
        return "${list_status}"
    fi
}

hapi_show_codex_profile_by_index() {
    local profile_index="$1"
    local store_file
    store_file=$(hapi_codex_profile_store_file)

    hapi_ensure_node_json || return
    CODEX_STORE_FILE="${store_file}" CODEX_PROFILE_INDEX="${profile_index}" node <<'NODE'
const fs = require("fs");
const storeFile = process.env.CODEX_STORE_FILE;
const index = Number(process.env.CODEX_PROFILE_INDEX) - 1;

function isSensitiveKey(key) {
  const normalized = String(key).toLowerCase();
  return normalized === "openai_api_key"
    || normalized.includes("api_key")
    || normalized.includes("apikey")
    || normalized.includes("token")
    || normalized.includes("secret")
    || normalized.includes("experimental_bearer_token");
}

function sanitizeJson(value, key = "") {
  // tokens 是容器：只对子字段打码（access_token / id_token / refresh_token），
  // 保留 account_id 之类非密字段，便于人工核对粘贴结构。
  if (key === "tokens" && value && typeof value === "object" && !Array.isArray(value)) {
    return Object.fromEntries(Object.entries(value).map(([itemKey, itemValue]) => [itemKey, sanitizeJson(itemValue, itemKey)]));
  }
  if (isSensitiveKey(key) && value !== undefined && value !== null) return "******";
  if (Array.isArray(value)) return value.map((item) => sanitizeJson(item));
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([itemKey, itemValue]) => [itemKey, sanitizeJson(itemValue, itemKey)]));
  }
  return value;
}

function sanitizeToml(text) {
  return String(text || "").split(/\r?\n/).map((line) => {
    const match = line.match(/^(\s*([A-Za-z0-9_.-]+)\s*=\s*)(.*)$/);
    return match && isSensitiveKey(match[2]) ? `${match[1]}"******"` : line;
  }).join("\n");
}

const store = JSON.parse(fs.readFileSync(storeFile, "utf8"));
const profiles = Array.isArray(store.profiles) ? store.profiles : [];
const profile = profiles[index];
if (!profile || !profile.config) {
  console.error("配置序号不存在");
  process.exit(1);
}
console.log(`名称: ${profile.name}`);
console.log("auth.json:");
console.log(JSON.stringify(sanitizeJson(profile.config.auth || {}), null, 2));
console.log("");
console.log("config.toml:");
console.log(sanitizeToml(profile.config.config || "") || "(空配置)");
NODE
}

hapi_store_current_codex_config() {
    local config_dir auth_file config_file profile_name
    config_dir="${HOME}/.codex"
    auth_file="${config_dir}/auth.json"
    config_file="${config_dir}/config.toml"

    if [ ! -f "${auth_file}" ] || [ ! -f "${config_file}" ]; then
        echo -e "${yellow}当前 Codex 配置不完整，需同时存在: ${auth_file} / ${config_file}${background}"
        return 1
    fi
    hapi_validate_codex_files || {
        echo -e "${red}检测到 Codex 配置格式异常，已中止储存。${background}"
        return 1
    }
    # 配置库不能成为「写入无效 auth」的旁路：菜单 4 切换时会把这个 auth 直接写回 live auth.json，
    # 所以这里先按「Codex 能加载且带可用凭据」这一级卡一次（不要求完整的官方三件套，避免误杀 apikey/PAT 配置）。
    if ! hapi_check_codex_auth_file "${auth_file}" loadable; then
        echo -e "${red}当前 auth.json 不符合 Codex 的加载要求，已中止储存。${background}"
        echo -e "${yellow}请先用菜单 7「写入/编辑官方 auth.json」写入有效配置，或修正 ${auth_file} 后重试。${background}"
        return 1
    fi
    echo -en "${cyan}请输入配置名称: ${background}"
    read -r profile_name
    if [ -z "${profile_name}" ]; then
        echo -e "${red}配置名称不能为空。${background}"
        return 1
    fi
    hapi_save_codex_profile_from_files "${profile_name}" "${auth_file}" "${config_file}"
}

hapi_create_codex_profile() {
    local profile_name api_key base_url model store_file
    local default_base_url="https://api.openai.com/v1"
    local default_model="gpt-5.5"
    store_file=$(hapi_codex_profile_store_file)

    echo -en "${cyan}请输入新配置名称: ${background}"
    read -r profile_name
    if [ -z "${profile_name}" ]; then
        echo -e "${red}配置名称不能为空。${background}"
        return 1
    fi

    echo -en "${cyan}请输入 OPENAI_API_KEY（已隐藏输入）: ${background}"
    read -rs api_key
    echo
    # 空 Key 会写出 {OPENAI_API_KEY: ""}：隐式模式会被判成 apikey 却没有可用凭据，
    # 等于造出一个 Codex 用不了的配置，所以这里必须非空。
    while [ -z "${api_key}" ]; do
        echo -e "${red}OPENAI_API_KEY 不能为空（空 Key 会让 Codex 既进不了官方登录、也拿不到第三方凭据）。${background}"
        echo -en "${cyan}请重新输入 OPENAI_API_KEY（已隐藏输入）: ${background}"
        read -rs api_key
        echo
    done
    echo -en "${cyan}请输入 base_url (默认 ${default_base_url}): ${background}"
    read -r base_url
    base_url=${base_url:-${default_base_url}}
    echo -en "${cyan}请输入 model (默认 ${default_model}): ${background}"
    read -r model
    model=${model:-${default_model}}

    hapi_ensure_node_json || return
    mkdir -p "$(dirname "${store_file}")"
    CODEX_STORE_FILE="${store_file}" CODEX_PROFILE_NAME="${profile_name}" CODEX_API_KEY="${api_key}" CODEX_BASE_URL="${base_url}" CODEX_MODEL="${model}" node <<'NODE'
const fs = require("fs");
const path = require("path");
const storeFile = process.env.CODEX_STORE_FILE;
const name = process.env.CODEX_PROFILE_NAME;
const apiKey = process.env.CODEX_API_KEY || "";
const baseUrl = process.env.CODEX_BASE_URL || "https://api.openai.com/v1";
const model = process.env.CODEX_MODEL || "gpt-5.5";

function tomlString(value) {
  return JSON.stringify(String(value));
}

function readStore() {
  if (!fs.existsSync(storeFile)) return { profiles: [] };
  const raw = fs.readFileSync(storeFile, "utf8");
  const store = raw.trim() ? JSON.parse(raw) : { profiles: [] };
  if (!Array.isArray(store.profiles)) store.profiles = [];
  return store;
}

try {
  const auth = { OPENAI_API_KEY: apiKey };
  const config = [
    `model = ${tomlString(model)}`,
    'model_provider = "custom"',
    "",
    "[model_providers.custom]",
    'name = "Custom"',
    `base_url = ${tomlString(baseUrl)}`,
    'env_key = "OPENAI_API_KEY"',
    'wire_api = "responses"',
    "",
    "[features]",
    "goals = true",
    "",
  ].join("\n");
  const store = readStore();
  const now = new Date().toISOString();
  const idx = store.profiles.findIndex((item) => item && item.name === name);
  const profile = { name, createdAt: now, updatedAt: now, config: { auth, config } };
  if (idx >= 0) {
    profile.createdAt = store.profiles[idx].createdAt || now;
    store.profiles[idx] = profile;
  } else {
    store.profiles.push(profile);
  }
  fs.mkdirSync(path.dirname(storeFile), { recursive: true });
  fs.writeFileSync(storeFile, `${JSON.stringify(store, null, 2)}\n`, { mode: 0o600 });
  try { fs.chmodSync(storeFile, 0o600); } catch {}
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
NODE
    local create_status=$?
    if [ "${create_status}" -ne 0 ]; then
        echo -e "${red}Codex 新配置保存失败。${background}"
        return "${create_status}"
    fi
    chmod 600 "${store_file}" 2>/dev/null
    echo -e "${yellow}新配置已保存，但未切换当前 Codex 配置。${background}"
}

# 把配置库里某个 profile 的 auth 抽成 JSON 文件，供 hapi_check_codex_auth_file 复用。
# ⚠️ 临时文件由调用方创建并登记（不要在这里 mktemp 后用 `$(...)` 返回路径）：
#    命令替换会起子 shell，子 shell 退出时 EXIT trap 会把刚写好的临时文件删掉。
hapi_extract_codex_profile_auth() {
    local store_file="$1"
    local index="$2"
    local out_file="$3"

    hapi_ensure_node_json || return 1
    CODEX_STORE_FILE="${store_file}" CODEX_PROFILE_INDEX="${index}" CODEX_OUT_FILE="${out_file}" node <<'NODE'
const fs = require("fs");
try {
  const store = JSON.parse(fs.readFileSync(process.env.CODEX_STORE_FILE, "utf8"));
  const profiles = Array.isArray(store.profiles) ? store.profiles : [];
  const profile = profiles[Number(process.env.CODEX_PROFILE_INDEX) - 1];
  if (!profile || !profile.config) throw new Error("配置序号不存在");
  const auth = profile.config.auth || {};
  if (!auth || typeof auth !== "object" || Array.isArray(auth)) throw new Error("profile auth 必须是 JSON 对象");
  fs.writeFileSync(process.env.CODEX_OUT_FILE, `${JSON.stringify(auth, null, 2)}\n`, { mode: 0o600 });
  try { fs.chmodSync(process.env.CODEX_OUT_FILE, 0o600); } catch {}
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
NODE
}

hapi_switch_codex_profile() {
    local store_file config_dir auth_file config_file backup_file num confirm profile_auth_tmp
    store_file=$(hapi_codex_profile_store_file)
    config_dir="${HOME}/.codex"
    auth_file="${config_dir}/auth.json"
    config_file="${config_dir}/config.toml"

    hapi_list_codex_profiles || return
    echo -en "${green}请输入要切换的配置序号: ${background}"
    read -r num
    if [[ ! "${num}" =~ ^[0-9]+$ ]] || [ "${num}" -lt 1 ]; then
        echo -e "${red}请输入有效的序号。${background}"
        return 1
    fi

    echo -e "${white}=====${green}即将切换到以下配置${white}=====${background}"
    hapi_show_codex_profile_by_index "${num}" || return
    echo -en "${yellow}确认切换到该配置吗？[y/N]: ${background}"
    read -r confirm
    if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
        echo -e "${yellow}已取消切换。${background}"
        return
    fi

    # 配置库不能成为旁路：写回 live auth.json 之前，先确认这份 auth 是 Codex 真能加载的
    # （loadable 级：类型/格式/可反序列化 + 至少一个可用凭据，不要求官方三件套）。
    profile_auth_tmp=$(mktemp "${TMPDIR:-/tmp}/hapi_codex_profile_auth.XXXXXX") || {
        echo -e "${red}临时文件创建失败，请确认系统有可用的 mktemp。${background}"
        return 1
    }
    chmod 600 "${profile_auth_tmp}" 2>/dev/null
    HAPI_CODEX_AUTH_TMP="${profile_auth_tmp}"
    hapi_install_sensitive_tmp_traps
    if ! hapi_extract_codex_profile_auth "${store_file}" "${num}" "${profile_auth_tmp}"; then
        echo -e "${red}无法读取该配置的 auth.json，已中止切换。${background}"
        hapi_cleanup_sensitive_tmp
        return 1
    fi
    if ! hapi_check_codex_auth_file "${profile_auth_tmp}" loadable; then
        echo -e "${red}该配置的 auth.json 不符合 Codex 的加载要求，已中止切换（未改动 ~/.codex）。${background}"
        echo -e "${yellow}请删除并重建该配置，或先用菜单 7 写入有效的官方 auth.json 后再储存。${background}"
        hapi_cleanup_sensitive_tmp
        return 1
    fi
    hapi_cleanup_sensitive_tmp

    mkdir -p "${config_dir}"
    if [ -f "${auth_file}" ]; then
        backup_file="${auth_file}.bak"
        cp -a "${auth_file}" "${backup_file}"
        chmod 600 "${backup_file}" 2>/dev/null
        echo -e "${green}已备份原配置到: ${backup_file}${background}"
    fi
    if [ -f "${config_file}" ]; then
        backup_file="${config_file}.bak"
        cp -a "${config_file}" "${backup_file}"
        chmod 600 "${backup_file}" 2>/dev/null
        echo -e "${green}已备份原配置到: ${backup_file}${background}"
    fi
    hapi_ensure_node_json || return
    CODEX_STORE_FILE="${store_file}" CODEX_PROFILE_INDEX="${num}" CODEX_AUTH_FILE="${auth_file}" CODEX_CONFIG_FILE="${config_file}" node <<'NODE'
const fs = require("fs");
const path = require("path");
const storeFile = process.env.CODEX_STORE_FILE;
const index = Number(process.env.CODEX_PROFILE_INDEX) - 1;
const authFile = process.env.CODEX_AUTH_FILE;
const configFile = process.env.CODEX_CONFIG_FILE;

try {
  const store = JSON.parse(fs.readFileSync(storeFile, "utf8"));
  const profiles = Array.isArray(store.profiles) ? store.profiles : [];
  const profile = profiles[index];
  if (!profile || !profile.config) throw new Error("配置序号不存在");
  const auth = profile.config.auth || {};
  const config = String(profile.config.config || "");
  if (!auth || typeof auth !== "object" || Array.isArray(auth)) throw new Error("profile auth 必须是 JSON 对象");
  fs.mkdirSync(path.dirname(authFile), { recursive: true });
  fs.writeFileSync(authFile, `${JSON.stringify(auth, null, 2)}\n`, { mode: 0o600 });
  try { fs.chmodSync(authFile, 0o600); } catch {}
  fs.writeFileSync(configFile, config.endsWith("\n") ? config : `${config}\n`, { mode: 0o600 });
  try { fs.chmodSync(configFile, 0o600); } catch {}
  console.log(profile.name);
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
NODE
    local switch_status=$?
    if [ "${switch_status}" -ne 0 ]; then
        echo -e "${red}切换配置失败。${background}"
        return "${switch_status}"
    fi
    chmod 600 "${auth_file}" "${config_file}" 2>/dev/null
    echo -e "${green}Codex 配置已切换: ${auth_file} / ${config_file}${background}"

    # 切过来的配置也要收敛路由：旧配置可能是「官方登录 + 残留第三方 model_provider」，
    # 那样请求会走第三方 provider。判定为「需要保持第三方」时（保留 id / 第三方 base_url）不动。
    if ! hapi_sync_codex_route; then
        echo -e "${red}Codex 路由同步失败：当前路由可能与该配置不匹配，请检查 ${config_file}。${background}"
        return 1
    fi
}

hapi_delete_codex_profile() {
    local store_file num confirm
    store_file=$(hapi_codex_profile_store_file)

    hapi_list_codex_profiles || return
    echo -en "${green}请输入要删除的配置序号: ${background}"
    read -r num
    if [[ ! "${num}" =~ ^[0-9]+$ ]] || [ "${num}" -lt 1 ]; then
        echo -e "${red}请输入有效的序号。${background}"
        return 1
    fi

    echo -e "${white}=====${green}即将删除以下配置${white}=====${background}"
    hapi_show_codex_profile_by_index "${num}" || return
    echo -en "${yellow}确认删除该配置吗？[y/N]: ${background}"
    read -r confirm
    if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
        echo -e "${yellow}已取消删除。${background}"
        return
    fi

    hapi_ensure_node_json || return
    CODEX_STORE_FILE="${store_file}" CODEX_PROFILE_INDEX="${num}" node <<'NODE'
const fs = require("fs");
const storeFile = process.env.CODEX_STORE_FILE;
const index = Number(process.env.CODEX_PROFILE_INDEX) - 1;

try {
  const store = JSON.parse(fs.readFileSync(storeFile, "utf8"));
  const profiles = Array.isArray(store.profiles) ? store.profiles : [];
  if (!profiles[index]) throw new Error("配置序号不存在");
  const removed = profiles.splice(index, 1)[0];
  store.profiles = profiles;
  fs.writeFileSync(storeFile, `${JSON.stringify(store, null, 2)}\n`, { mode: 0o600 });
  try { fs.chmodSync(storeFile, 0o600); } catch {}
  console.log(removed.name);
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
NODE
    local delete_status=$?
    if [ "${delete_status}" -ne 0 ]; then
        echo -e "${red}删除配置失败。${background}"
        return "${delete_status}"
    fi
    chmod 600 "${store_file}" 2>/dev/null
    echo -e "${green}配置已删除。${background}"
}

hapi_editor_program() {
    local editor="$1"
    local -a editor_cmd=()

    read -r -a editor_cmd <<< "${editor}"
    if [ "${#editor_cmd[@]}" -eq 0 ]; then
        return 1
    fi
    printf '%s' "${editor_cmd[0]}"
}

hapi_editor_basename() {
    local editor_program
    editor_program=$(hapi_editor_program "$1") || return 1
    basename "${editor_program}"
}

hapi_detect_editor() {
    local editor="" candidate editor_program

    if [ -n "${HAPI_EDITOR}" ]; then
        editor="${HAPI_EDITOR}"
    elif [ -n "${VISUAL}" ]; then
        editor="${VISUAL}"
    elif [ -n "${EDITOR}" ]; then
        editor="${EDITOR}"
    fi

    if [ -n "${editor}" ]; then
        editor_program=$(hapi_editor_program "${editor}")
        if [ -n "${editor_program}" ] && command -v "${editor_program}" >/dev/null 2>&1; then
            printf '%s' "${editor}"
            return 0
        fi
        echo -e "${yellow}环境变量指定的编辑器不可用: ${editor}，改用自动探测。${background}" >&2
    fi

    for candidate in vim vi nano emacs; do
        if command -v "${candidate}" >/dev/null 2>&1; then
            printf '%s' "${candidate}"
            return 0
        fi
    done

    return 1
}

# 判断编辑器是否兼容 vim 的 -c 参数；vi 在多数发行版是 vim 的软链，但不能直接假定
hapi_editor_is_vim_like() {
    local editor="$1"
    local editor_program editor_name

    editor_program=$(hapi_editor_program "${editor}") || return 1
    editor_name=$(basename "${editor_program}")

    case "${editor_name}" in
    vim | nvim) return 0 ;;
    vi)
        "${editor_program}" --version 2>/dev/null | head -n 1 | grep -qi 'vim' && return 0
        return 1
        ;;
    esac
    return 1
}

hapi_run_editor() {
    local editor="$1"
    local target_file="$2"
    local -a editor_cmd=()

    read -r -a editor_cmd <<< "${editor}"
    if [ "${#editor_cmd[@]}" -eq 0 ]; then
        echo -e "${red}编辑器命令为空，无法打开编辑器。${background}"
        return 1
    fi

    if hapi_editor_is_vim_like "${editor}"; then
        # paste 模式关闭自动缩进，避免粘贴 JSON 时被逐层缩进破坏结构；
        # 同时关闭 backup / swap / undo / viminfo，避免 token 残留在磁盘上。
        "${editor_cmd[@]}" -c 'set paste' -c 'set nobackup nowritebackup noswapfile noundofile viminfo=' "${target_file}"
    else
        "${editor_cmd[@]}" "${target_file}"
    fi
}

# 校验待写入 / 待写回的 Codex auth.json。
# 分级原则（对齐 Codex 的 AuthDotJson 反序列化约束 + cc-switch 的判定函数）：
#   · 结构/类型不符合 Codex AuthDotJson、或官方 ChatGPT 登录缺少必要凭据 → error（阻断写入）
#   · 不影响反序列化的可选元数据缺失（account_id / last_refresh）、非目标登录模式 → warning（须二次确认）
#   · level=official（默认，菜单 7 用）：额外要求 tokens 三件套（id_token/access_token/refresh_token）齐备
#   · level=loadable（配置库写入 / 切换时用）：只要求「Codex 能加载，且带至少一个可用凭据」
hapi_check_codex_auth_file() {
    local auth_file="$1"
    local level="${2:-official}"

    hapi_ensure_node_json || return 1
    if [ ! -f "${auth_file}" ]; then
        echo -e "${red}待校验文件不存在: ${auth_file}${background}"
        return 1
    fi
    CODEX_AUTH_FILE="${auth_file}" CODEX_AUTH_LEVEL="${level}" node <<'NODE'
const fs = require("fs");

const authFile = process.env.CODEX_AUTH_FILE;
const level = process.env.CODEX_AUTH_LEVEL === "loadable" ? "loadable" : "official";
const errors = [];
const warnings = [];
const infos = [];
const TOP_LEVEL_KEYS = ["auth_mode", "OPENAI_API_KEY", "tokens", "last_refresh"];
const TOKEN_KEYS = ["access_token", "account_id", "id_token", "refresh_token"];
const LOGIN_TOKEN_KEYS = ["id_token", "access_token", "refresh_token"];
const KNOWN_AUTH_MODES = [
  "apikey",
  "chatgpt",
  "chatgptAuthTokens",
  "headers",
  "agentIdentity",
  "personalAccessToken",
  "bedrockApiKey",
  "bedrockAccessKeys",
];
const BASE64URL_PATTERN = /^[A-Za-z0-9_-]+$/;

function isNonEmptyString(value) {
  return typeof value === "string" && value.trim() !== "";
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function typeName(value) {
  if (value === null) return "null";
  if (Array.isArray(value)) return "array";
  return typeof value;
}

// cc-switch 判定模式优先级用的是「字段存在」：值非 null 即算存在，
// 空字符串 / 空数组一样算，因此空值也会抢到模式优先级。
function fieldExistsForMode(value) {
  return value !== undefined && value !== null;
}

// cc-switch codex_auth_has_openai_account_material 的 value_present：
// 字符串必须非空白、容器必须非空，数字/布尔算存在。用来判断「凭据是否可用」。
function credentialIsUsable(value) {
  if (value === undefined || value === null) return false;
  if (typeof value === "string") return value.trim() !== "";
  if (Array.isArray(value)) return value.length > 0;
  if (typeof value === "object") return Object.keys(value).length > 0;
  return true;
}

// 与 cc-switch 的 codex_auth_resolved_mode 一致：auth_mode 缺失或为 null 时按隐式优先级判定，
// 最终回退到 ChatGPT 模式，因此「没有 auth_mode」也按官方登录校验。
function resolveAuthMode(auth) {
  const mode = auth.auth_mode;
  if (mode !== undefined && mode !== null) {
    if (typeof mode !== "string") return "invalid-type";
    return KNOWN_AUTH_MODES.includes(mode) ? mode : "unrecognized";
  }
  if (fieldExistsForMode(auth.personal_access_token)) return "personalAccessToken";
  if (fieldExistsForMode(auth.bedrock_api_key)) return "bedrockApiKey";
  if (fieldExistsForMode(auth.bedrock_access_keys)) return "bedrockAccessKeys";
  if (fieldExistsForMode(auth.OPENAI_API_KEY)) return "apikey";
  return "chatgpt";
}

function daysInMonth(year, month) {
  const table = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  const isLeap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  return month === 2 && isLeap ? 29 : table[month - 1];
}

// 真·RFC3339：只做正则是不够的（"2026-99-99T99:99:99Z" 形状合法但日期不存在），
// 而 Codex 按 DateTime 类型反序列化，非法日期会让整份 auth.json 加载失败。
function isValidRfc3339(value) {
  const match = /^(\d{4})-(\d{2})-(\d{2})[Tt](\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?([Zz]|([+-])(\d{2}):(\d{2}))$/.exec(value);
  if (!match) return false;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const hour = Number(match[4]);
  const minute = Number(match[5]);
  const second = Number(match[6]);
  const offsetHour = match[10] === undefined ? 0 : Number(match[10]);
  const offsetMinute = match[11] === undefined ? 0 : Number(match[11]);
  if (month < 1 || month > 12) return false;
  if (day < 1 || day > daysInMonth(year, month)) return false;
  if (hour > 23 || minute > 59 || second > 60) return false;
  if (offsetHour > 23 || offsetMinute > 59) return false;
  return true;
}

// 严格 base64url-no-pad（Rust 侧是 URL_SAFE_NO_PAD）。Node 的 base64 解码很宽容
// （会忽略非法字符、容忍缺填充），所以这里用「字符集 + 长度 + 往返编码一致」把宽容性收回来。
function decodeBase64UrlStrict(segment) {
  if (typeof segment !== "string" || segment === "") return null;
  if (!BASE64URL_PATTERN.test(segment)) return null;
  if (segment.length % 4 === 1) return null;
  try {
    const decoded = Buffer.from(segment, "base64url");
    if (decoded.toString("base64url") !== segment) return null;
    return decoded.toString("utf8");
  } catch {
    return null;
  }
}

// JWT envelope 严格校验：恰好三段、三段都非空、都必须是合法 base64url-no-pad，
// header / payload 反序列化后必须是 plain object。
// 不校验签名——Codex 自己也只是解 envelope 与 claims。
function decodeJwt(token) {
  if (typeof token !== "string") return null;
  const segments = token.split(".");
  if (segments.length !== 3) return null;
  if (segments.some((segment) => segment === "")) return null;
  const headerJson = decodeBase64UrlStrict(segments[0]);
  const payloadJson = decodeBase64UrlStrict(segments[1]);
  if (decodeBase64UrlStrict(segments[2]) === null) return null;
  if (headerJson === null || payloadJson === null) return null;
  let header;
  let claims;
  try { header = JSON.parse(headerJson); } catch { return null; }
  try { claims = JSON.parse(payloadJson); } catch { return null; }
  if (!isPlainObject(header) || !isPlainObject(claims)) return null;
  return { header, claims };
}

function isSensitiveKey(key) {
  const normalized = String(key).toLowerCase();
  return normalized === "openai_api_key"
    || normalized.includes("api_key")
    || normalized.includes("apikey")
    || normalized.includes("token")
    || normalized.includes("secret");
}

function sanitizeJson(value, key = "") {
  // tokens 是容器：只对子字段打码（access_token / id_token / refresh_token），
  // 保留 account_id 之类非密字段，便于人工核对粘贴结构。
  if (key === "tokens" && value && typeof value === "object" && !Array.isArray(value)) {
    return Object.fromEntries(Object.entries(value).map(([itemKey, itemValue]) => [itemKey, sanitizeJson(itemValue, itemKey)]));
  }
  if (isSensitiveKey(key) && value !== undefined && value !== null) return "******";
  if (Array.isArray(value)) return value.map((item) => sanitizeJson(item));
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([itemKey, itemValue]) => [itemKey, sanitizeJson(itemValue, itemKey)]));
  }
  return value;
}

// 非 ChatGPT 模式各自的凭据字段：存在 + 类型正确 + 非空，缺一不可。
// 字段名对齐 cc-switch 的 codex_auth_has_openai_account_material（PAT / agentIdentity 分支），
// bedrock 两族 cc-switch 把它算作"非 OpenAI 账号材料"，但对我们的写入路径同样是"必须有可用凭据"。
const MODE_CREDENTIAL_SPEC = {
  apikey: { key: "OPENAI_API_KEY", accepts: (value) => typeof value === "string", desc: "非空白字符串" },
  personalAccessToken: { key: "personal_access_token", accepts: (value) => typeof value === "string", desc: "非空白字符串" },
  agentIdentity: { key: "agent_identity", accepts: (value) => isPlainObject(value) || typeof value === "string", desc: "非空对象或非空白字符串" },
  bedrockApiKey: { key: "bedrock_api_key", accepts: (value) => typeof value === "string", desc: "非空白字符串" },
  bedrockAccessKeys: { key: "bedrock_access_keys", accepts: (value) => isPlainObject(value) || typeof value === "string", desc: "非空对象或非空白字符串" },
};

function checkModeCredential(auth, mode) {
  const spec = MODE_CREDENTIAL_SPEC[mode];
  if (!spec) return;
  const value = auth[spec.key];
  if (value === undefined || value === null) {
    errors.push(`auth_mode 解析为 ${mode}，但缺少 ${spec.key}，Codex 拿不到可用凭据。`);
    return;
  }
  if (!spec.accepts(value)) {
    errors.push(`auth_mode 解析为 ${mode}，${spec.key} 类型不符（当前为 ${typeName(value)}，期望${spec.desc}）。`);
    return;
  }
  if (!credentialIsUsable(value)) {
    errors.push(`auth_mode 解析为 ${mode}，${spec.key} 为空，Codex 会视为未登录。`);
  }
}

// ChatGPT 登录凭据：三个字段必须**存在且是字符串**（Codex 的 TokenData 里它们都是必需字段，
// 缺一个会让整份 auth.json 反序列化失败）；official 级别还要求三者都非空。
function checkChatgptTokens(auth) {
  const tokens = auth.tokens;
  if (tokens === undefined || tokens === null) {
    errors.push("auth_mode 解析为 ChatGPT 登录，但缺少 tokens 字段，Codex 拿不到任何可用凭据。");
    return null;
  }
  if (!isPlainObject(tokens)) {
    errors.push(`tokens 必须是 JSON 对象，当前为 ${typeName(tokens)}。`);
    return null;
  }

  const unknownTokenKeys = Object.keys(tokens).filter((key) => !TOKEN_KEYS.includes(key));
  if (unknownTokenKeys.length) {
    warnings.push(`tokens 存在官方登录缓存之外的字段: ${unknownTokenKeys.join(", ")}`);
  }

  LOGIN_TOKEN_KEYS.forEach((key) => {
    const value = tokens[key];
    if (value === undefined || value === null) {
      errors.push(`缺少 tokens.${key}：Codex 的 TokenData 里 id_token / access_token / refresh_token 都是必需字段，缺失会让整份 auth.json 反序列化失败（account_id 才是可选）。`);
      return;
    }
    if (typeof value !== "string") {
      errors.push(`tokens.${key} 必须是字符串，当前为 ${typeName(value)}。`);
      return;
    }
    if (value.trim() === "") {
      if (level === "official") errors.push(`tokens.${key} 是空字符串，官方 ChatGPT 登录需要 id_token / access_token / refresh_token 三者齐备。`);
      else warnings.push(`tokens.${key} 是空字符串（Codex 能加载，但该配置无法完成登录）。`);
    }
  });

  if (level === "loadable" && !LOGIN_TOKEN_KEYS.some((key) => isNonEmptyString(tokens[key]))) {
    errors.push("tokens 里没有任何可用凭据（id_token / access_token / refresh_token 全空），该配置无法登录。");
  }

  if (tokens.account_id !== undefined && tokens.account_id !== null && typeof tokens.account_id !== "string") {
    errors.push(`tokens.account_id 必须是字符串，当前为 ${typeName(tokens.account_id)}（Codex 的类型是 Option\u003cString\u003e，类型不符会让整份 auth.json 反序列化失败）。`);
  } else if (!credentialIsUsable(tokens.account_id)) {
    warnings.push("tokens.account_id 缺失或为空（Codex 只把它当元数据，不影响登录，但可能影响 workspace 识别）。");
  }
  return tokens;
}

let raw = "";
try {
  // 去掉 BOM 并把 Windows 换行统一成 LF：从网页/剪贴板粘贴时经常带 \r\n
  raw = fs.readFileSync(authFile, "utf8").replace(/^\uFEFF/, "").replace(/\r\n/g, "\n");
} catch (error) {
  console.log(`错误: 读取失败: ${error.message}`);
  process.exit(1);
}

if (!raw.trim()) errors.push("文件为空，没有可写入的内容。");

let auth = null;
if (errors.length === 0) {
  try {
    auth = JSON.parse(raw);
  } catch (error) {
    errors.push(`JSON 解析失败: ${error.message}`);
    errors.push("常见原因：缺少首尾大括号、复制内容不完整，或粘贴时被编辑器自动缩进/自动补全破坏。");
  }
}

if (errors.length === 0 && !isPlainObject(auth)) {
  errors.push("顶层必须是 JSON 对象（以 { 开头、以 } 结尾）。");
  auth = null;
}

if (auth) {
  const unknownTopKeys = Object.keys(auth).filter((key) => !TOP_LEVEL_KEYS.includes(key));
  if (unknownTopKeys.length) {
    warnings.push(`顶层存在官方登录缓存之外的字段: ${unknownTopKeys.join(", ")}（官方 auth.json 通常只有 auth_mode / OPENAI_API_KEY / tokens / last_refresh）`);
  }

  if (auth.last_refresh !== undefined && auth.last_refresh !== null) {
    if (typeof auth.last_refresh !== "string") {
      errors.push(`last_refresh 必须是 RFC3339 字符串，当前为 ${typeName(auth.last_refresh)}（Codex 用强类型 DateTime 反序列化，类型不符会让整份 auth.json 加载失败）。`);
    } else if (!isValidRfc3339(auth.last_refresh)) {
      errors.push(`last_refresh 不是合法的 RFC3339 时间: ${JSON.stringify(auth.last_refresh)}（日期/时钟/时区越界；Codex 反序列化整份 auth.json 会失败，不会退化成"当作缺失"）。`);
    }
  }

  if (fieldExistsForMode(auth.OPENAI_API_KEY) && typeof auth.OPENAI_API_KEY !== "string") {
    errors.push(`OPENAI_API_KEY 必须是字符串或 null，当前为 ${typeName(auth.OPENAI_API_KEY)}。`);
  }

  const mode = resolveAuthMode(auth);
  if (mode === "invalid-type") {
    errors.push(`auth_mode 必须是字符串，当前为 ${typeName(auth.auth_mode)}。`);
  } else if (mode === "unrecognized") {
    errors.push(`auth_mode 取值无法识别: ${JSON.stringify(auth.auth_mode)}（Codex 支持的取值：${KNOWN_AUTH_MODES.join(" / ")}；不认识的取值会让整份 auth.json 反序列化失败）。`);
  } else if (mode === "headers") {
    // cc-switch：'Modes Codex cannot load from storage (headers, unrecognized) are signed out'
    errors.push('auth_mode 为 "headers"：Codex 无法从 auth.json 加载该模式，写进去等于没登录。');
  } else if (mode !== "chatgpt" && mode !== "chatgptAuthTokens") {
    // 非 ChatGPT 模式：先按各自模式的凭据字段做「存在 + 类型 + 非空」检查，再给模式提示
    checkModeCredential(auth, mode);
    if (mode !== "apikey") {
      warnings.push(`auth_mode 解析为 ${mode}，不是官方 ChatGPT 登录缓存（本选项用来写入官方登录态）。`);
    }
  }

  if (mode === "chatgpt" || mode === "chatgptAuthTokens") {
    if (!(auth.OPENAI_API_KEY === null || auth.OPENAI_API_KEY === undefined || auth.OPENAI_API_KEY === "")) {
      warnings.push("OPENAI_API_KEY 建议为 null（官方登录使用 tokens，该字段会被忽略）");
    }
    const tokens = checkChatgptTokens(auth);
    if (tokens) {
      if (isNonEmptyString(tokens.id_token)) {
        const identity = decodeJwt(tokens.id_token);
        if (!identity) {
          errors.push("tokens.id_token 不是合法的 JWT（要求恰好三段、三段非空、严格 base64url、payload 是 JSON 对象；Codex 对 id_token 有专用反序列化，解析失败会让整份 auth.json 加载失败）。");
        } else {
          const account = [];
          if (identity.claims.email) account.push(`email: ${identity.claims.email}`);
          if (identity.claims.sub) account.push(`sub: ${identity.claims.sub}`);
          if (account.length) infos.push(`id_token 账号信息: ${account.join("    ")}`);
          if (!isNonEmptyString(identity.header.alg)) {
            warnings.push("tokens.id_token 的 header 缺少 alg（cc-switch 提取账号身份时要求该字段，登录本身通常不受影响）。");
          }
        }
      }
      if (isNonEmptyString(tokens.access_token)) {
        const access = decodeJwt(tokens.access_token);
        if (access && access.claims.exp) {
          const expiresAt = new Date(access.claims.exp * 1000);
          const remainHours = (expiresAt.getTime() - Date.now()) / 3600000;
          if (remainHours > 0) infos.push(`access_token 有效期至: ${expiresAt.toISOString()}（约 ${remainHours.toFixed(1)} 小时后过期）`);
          else infos.push(`access_token 已于 ${expiresAt.toISOString()} 过期（Codex 启动时会用 refresh_token 自动刷新）`);
        }
      }
    }
  }
  // 注意：apikey 模式由上面的 checkModeCredential 负责（原处另一个 apikey 判据已删除，避免留下死分支）
}

infos.forEach((message) => console.log(message));
warnings.forEach((message) => console.log(`警告: ${message}`));
errors.forEach((message) => console.log(`错误: ${message}`));

if (auth) {
  console.log("内容预览（敏感字段已隐藏）:");
  console.log(JSON.stringify(sanitizeJson(auth), null, 2));
}

process.exit(errors.length > 0 ? 1 : 0);
NODE
}
# 把已校验的内容规范化（去 BOM、统一两空格缩进）后写入目标文件
hapi_write_codex_auth_file() {
    local source_file="$1"
    local dest_file="$2"

    hapi_ensure_node_json || return 1
    CODEX_AUTH_SOURCE="${source_file}" CODEX_AUTH_DEST="${dest_file}" node <<'NODE'
const fs = require("fs");
const path = require("path");
const sourceFile = process.env.CODEX_AUTH_SOURCE;
const destFile = process.env.CODEX_AUTH_DEST;

try {
  const raw = fs.readFileSync(sourceFile, "utf8").replace(/^\uFEFF/, "").replace(/\r\n/g, "\n");
  const auth = raw.trim() ? JSON.parse(raw) : {};
  if (!auth || typeof auth !== "object" || Array.isArray(auth)) throw new Error("auth.json 必须是 JSON 对象");
  fs.mkdirSync(path.dirname(destFile), { recursive: true });
  // 与 cc-switch 的 atomic_write_private 一致：凭据文件在创建时就要求 0600，
  // 避免「先 0644 再 chmod」之间出现可读窗口；已存在的文件再统一收紧一次。
  fs.writeFileSync(destFile, `${JSON.stringify(auth, null, 2)}\n`, { mode: 0o600 });
  try { fs.chmodSync(destFile, 0o600); } catch {}
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
NODE
}

# 只在正常返回路径删临时文件是不够的：Ctrl+C / 断线 / kill 都可能留下凭据副本，
# 因此敏感临时文件统一用 mktemp 生成不可预测路径，并挂上退出清理
# （见 hapi_edit_codex_official_auth / hapi_create_claude_profile）。
HAPI_CODEX_AUTH_TMP=""
HAPI_CLAUDE_SETTINGS_TMP=""

hapi_cleanup_sensitive_tmp() {
    local tmp_file
    for tmp_file in "${HAPI_CODEX_AUTH_TMP}" "${HAPI_CLAUDE_SETTINGS_TMP}"; do
        if [ -n "${tmp_file}" ] && [ -f "${tmp_file}" ]; then
            rm -f "${tmp_file}"
        fi
    done
    HAPI_CODEX_AUTH_TMP=""
    HAPI_CLAUDE_SETTINGS_TMP=""
}

hapi_cleanup_sensitive_tmp_and_exit() {
    hapi_cleanup_sensitive_tmp
    exit "$1"
}

# 敏感临时文件就绪后立即安装清理钩子；重复安装无副作用。
# 故意不挂 INT：vim 里 Ctrl+C 是退出插入模式的常用操作，挂上会在 vim 退出后
# 连带删掉用户刚保存的内容。
hapi_install_sensitive_tmp_traps() {
    trap 'hapi_cleanup_sensitive_tmp' EXIT
    trap 'hapi_cleanup_sensitive_tmp_and_exit 143' TERM
    trap 'hapi_cleanup_sensitive_tmp_and_exit 129' HUP
}

# 路由状态报告。路由的自动收敛由 hapi_sync_codex_route / 写入器完成，这里只报告最终状态：
# 还能留下第三方 model_provider 的情形只有「保留 id」「脚本无法判断的登录模式」「本轮判定为保持不变」。
hapi_warn_codex_provider_route() {
    local model_provider
    model_provider=$(hapi_codex_current_value "model_provider")

    if [ -z "${model_provider}" ] || [ "${model_provider}" = "openai" ]; then
        echo -e "${green}当前 config.toml 未指定第三方 model_provider，Codex 会直接使用 auth.json 中的官方登录。${background}"
        return 0
    fi
    echo -e "${yellow}注意: 当前 config.toml 中 model_provider = \"${model_provider}\"，模型请求仍会走该 provider。${background}"
    echo -e "${yellow}      脚本只在识别到官方登录/官方 Key（自动移除并暂存）或填写第三方 base_url（自动恢复）时改路由；${background}"
    echo -e "${yellow}      这条路由本轮判定为保持不变。如需完全走官方，请移除 model_provider 及对应的 [model_providers.*] 段。${background}"
}

hapi_edit_codex_official_auth() {
    local config_dir auth_file config_file backup_file editor tmp_file editor_status
    local edit_mode edit_round max_editor_rounds confirm profile_name default_profile_name
    config_dir="${HOME}/.codex"
    auth_file="${config_dir}/auth.json"
    config_file="${config_dir}/config.toml"
    max_editor_rounds=5
    default_profile_name="官方登录"

    hapi_ensure_node_json || return

    echo -e "${white}=====${green}写入官方 auth.json（ChatGPT 登录缓存）${white}=====${background}"
    echo -e "${yellow}该文件保存 Codex 官方登录态（access_token / id_token / refresh_token），属于敏感凭据，请勿泄露。${background}"
    echo -e "${yellow}目标文件: ${auth_file}${background}"
    echo -e "${green}1.  ${cyan}空白文件（推荐：直接粘贴整份官方 auth.json）${background}"
    echo -e "${green}2.  ${cyan}载入现有 auth.json 内容（适合局部修改）${background}"
    echo -e "${green}0.  ${cyan}取消${background}"
    echo "========================="
    echo -en "${green}请输入您的选项: ${background}"; read -r edit_mode

    case "${edit_mode}" in
    1) edit_mode="blank" ;;
    2) edit_mode="existing" ;;
    0)
        echo -e "${yellow}已取消。${background}"
        return
        ;;
    *)
        echo -e "${red}输入错误${background}"
        return 1
        ;;
    esac

    editor=$(hapi_detect_editor)
    if [ -z "${editor}" ]; then
        echo -e "${red}未找到可用的文本编辑器，请先安装 vim 或 nano。${background}"
        echo -e "${yellow}也可用 HAPI_EDITOR 指定编辑器，例如: HAPI_EDITOR=vim bash Hapi_Claude_Manage.sh${background}"
        return 1
    fi

    if [ "${edit_mode}" = "existing" ] && [ ! -f "${auth_file}" ]; then
        echo -e "${yellow}未找到 ${auth_file}，改为从空白文件开始。${background}"
        edit_mode="blank"
    fi

    tmp_file=$(mktemp "${TMPDIR:-/tmp}/hapi_codex_auth.XXXXXX") || {
        echo -e "${red}临时文件创建失败，请确认系统有可用的 mktemp。${background}"
        return 1
    }
    chmod 600 "${tmp_file}" 2>/dev/null
    HAPI_CODEX_AUTH_TMP="${tmp_file}"
    hapi_install_sensitive_tmp_traps

    if [ "${edit_mode}" = "existing" ]; then
        cp -a "${auth_file}" "${tmp_file}"
        chmod 600 "${tmp_file}" 2>/dev/null
        echo -e "${green}已载入现有 auth.json 内容，可直接修改后保存。${background}"
    else
        echo -e "${yellow}请粘贴完整 JSON，字段结构如下（示例仅用于说明，不要把示例一起粘贴进去）:${background}"
        echo '{
  "auth_mode": "chatgpt",
  "OPENAI_API_KEY": null,
  "tokens": {
    "access_token": "eyJ...",
    "account_id": "00000000-0000-0000-0000-000000000000",
    "id_token": "eyJ...",
    "refresh_token": "rt_..."
  },
  "last_refresh": "2026-01-01T00:00:00.000000000Z"
}'
    fi

    echo -e "${yellow}编辑器: ${editor}${background}"
    if hapi_editor_is_vim_like "${editor}"; then
        echo -e "${yellow}已为 vim 开启 paste 模式，按 i 后直接粘贴即可（保存退出: Esc 后输入 :wq 回车）。${background}"
    else
        echo -e "${yellow}保存并退出编辑器后，脚本会立即校验内容。${background}"
    fi
    pause

    edit_round=1
    while [ "${edit_round}" -le "${max_editor_rounds}" ]; do
        hapi_run_editor "${editor}" "${tmp_file}"
        editor_status=$?
        if [ "${editor_status}" -ne 0 ]; then
            echo -e "${yellow}编辑器异常退出（退出码 ${editor_status}），内容可能根本没有被修改。${background}"
            echo -en "${yellow}是否仍然校验并写入当前内容？[y/N]: ${background}"
            read -r confirm
            if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
                echo -e "${yellow}已取消写入。${background}"
                hapi_cleanup_sensitive_tmp
                return 1
            fi
        fi
        echo -e "${white}=====${green}校验 auth.json 内容（第 ${edit_round} 次）${white}=====${background}"
        if hapi_check_codex_auth_file "${tmp_file}"; then
            echo -en "${green}确认将以上内容写入 ${auth_file} 吗？[y/N]: ${background}"
            read -r confirm
            if [[ "${confirm}" == "y" || "${confirm}" == "Y" ]]; then
                break
            fi
            echo -e "${yellow}已取消写入。${background}"
            hapi_cleanup_sensitive_tmp
            return
        fi

        echo -en "${yellow}校验未通过，是否重新打开编辑器修改？[Y/n]: ${background}"
        read -r confirm
        if [[ "${confirm}" == "n" || "${confirm}" == "N" ]]; then
            echo -e "${yellow}已取消写入。${background}"
            hapi_cleanup_sensitive_tmp
            return
        fi
        edit_round=$((edit_round + 1))
    done

    if [ "${edit_round}" -gt "${max_editor_rounds}" ]; then
        echo -e "${red}连续 ${max_editor_rounds} 次校验未通过，已放弃写入。${background}"
        hapi_cleanup_sensitive_tmp
        return 1
    fi

    mkdir -p "${config_dir}"
    if [ -f "${auth_file}" ]; then
        backup_file="${auth_file}.bak"
        cp -a "${auth_file}" "${backup_file}"
        chmod 600 "${backup_file}" 2>/dev/null
        echo -e "${green}已备份原配置到: ${backup_file}${background}"
    fi
    if ! hapi_write_codex_auth_file "${tmp_file}" "${auth_file}"; then
        echo -e "${red}auth.json 写入失败。${background}"
        hapi_cleanup_sensitive_tmp
        return 1
    fi
    hapi_cleanup_sensitive_tmp
    chmod 600 "${auth_file}" 2>/dev/null
    echo -e "${green}官方 auth.json 已写入: ${auth_file}${background}"

    # 官方登录写入后立刻收敛路由：把 config.toml 里残留的第三方路由（model_provider +
    # 对应的 [model_providers.*] 段）剥离并暂存。否则模型请求仍会走那个第三方 provider——
    # 官方登录只影响 Codex 识别到的账号，不改变请求实际发往哪里。
    if ! hapi_sync_codex_route; then
        echo -e "${red}Codex 路由同步失败：config.toml 可能仍指向第三方 provider，请检查后重试。${background}"
        return 1
    fi
    hapi_warn_codex_provider_route

    echo -en "${cyan}是否同时保存到 Codex 配置库（之后可用「切换配置」恢复）？[Y/n]: ${background}"
    read -r confirm
    if [[ "${confirm}" == "n" || "${confirm}" == "N" ]]; then
        return 0
    fi
    if [ ! -f "${config_file}" ]; then
        echo -e "${yellow}未找到 ${config_file}，配置库中该条配置的 config.toml 将为空。${background}"
    fi
    echo -en "${cyan}请输入配置名称 (默认 ${default_profile_name}): ${background}"
    read -r profile_name
    profile_name=${profile_name:-${default_profile_name}}
    hapi_save_codex_profile_from_files "${profile_name}" "${auth_file}" "${config_file}"
}

hapi_codex_config_menu() {
    local num

    while true; do
        echo -e "${white}=====${green}Codex 配置${white}=====${background}"
        echo -e "${green}1.  ${cyan}查看/修改配置${background}"
        echo -e "${green}2.  ${cyan}储存当前配置${background}"
        echo -e "${green}3.  ${cyan}新建配置（不切换）${background}"
        echo -e "${green}4.  ${cyan}切换配置${background}"
        echo -e "${green}5.  ${cyan}删除配置${background}"
        echo -e "${green}6.  ${cyan}切换新增推荐值${background}"
        echo -e "${green}7.  ${cyan}写入/编辑官方 auth.json（ChatGPT 登录）${background}"
        echo -e "${green}0.  ${cyan}返回上一级${background}"
        echo "========================="
        echo -en "${green}请输入您的选项: ${background}"; read -r num

        case "${num}" in
        1) hapi_config_codex; pause ;;
        2) hapi_store_current_codex_config; pause ;;
        3) hapi_create_codex_profile; pause ;;
        4) hapi_switch_codex_profile; pause ;;
        5) hapi_delete_codex_profile; pause ;;
        6) hapi_toggle_codex_recommended_values; pause ;;
        7) hapi_edit_codex_official_auth; pause ;;
        0) return ;;
        *) echo -e "${red}输入错误${background}"; pause ;;
        esac
    done
}

hapi_prepare_workspace() {
    local workspace_root="$1"
    case "${workspace_root}" in
        "~")
            workspace_root="${HOME}"
            ;;
        "~/"*)
            workspace_root="${HOME}/${workspace_root#~/}"
            ;;
    esac

    if [ ! -d "${workspace_root}" ]; then
        echo -en "${yellow}目录不存在: ${workspace_root}，是否创建？[Y/n]: ${background}"
        read -r create_workspace
        if [[ "${create_workspace}" == "n" || "${create_workspace}" == "N" ]]; then
            echo -e "${yellow}已取消添加目录。${background}"
            return 1
        fi
        if ! mkdir -p "${workspace_root}"; then
            echo -e "${red}目录创建失败: ${workspace_root}${background}"
            return 1
        fi
        echo -e "${green}已创建目录: ${workspace_root}${background}"
    fi

    if [ ! -d "${workspace_root}" ]; then
        echo -e "${red}workspace-root 不是有效目录: ${workspace_root}${background}"
        return 1
    fi

    local existing_workspace
    for existing_workspace in "${HAPI_SELECTED_WORKSPACES[@]}"; do
        if [ "${existing_workspace}" = "${workspace_root}" ]; then
            echo -e "${yellow}目录已在列表中: ${workspace_root}${background}"
            return 0
        fi
    done

    HAPI_SELECTED_WORKSPACES+=("${workspace_root}")
    echo -e "${green}已添加工作目录: ${workspace_root}${background}"
}

hapi_select_workspaces() {
    local num custom_path
    HAPI_SELECTED_WORKSPACES=()

    while true; do
        echo -e "${white}=====${green}设置 Hapi 工作目录${white}=====${background}"
        if [ "${#HAPI_SELECTED_WORKSPACES[@]}" -gt 0 ]; then
            echo -e "${yellow}已选择:${background}"
            printf '  - %s\n' "${HAPI_SELECTED_WORKSPACES[@]}"
        fi
        echo -e "${green}1.  ${cyan}添加 ${HOME}/TRSS-Yunzai${background}"
        echo -e "${green}2.  ${cyan}添加 ${HOME}/AstrBot${background}"
        echo -e "${green}3.  ${cyan}添加 ${HOME}/myrepo${background}"
        echo -e "${green}4.  ${cyan}添加自定义目录${background}"
        echo -e "${green}5.  ${cyan}开始设置${background}"
        echo -e "${green}0.  ${cyan}取消${background}"
        echo "========================="
        echo -en "${green}请输入您的选项: ${background}"; read -r num

        case "${num}" in
        1) hapi_prepare_workspace "${HOME}/TRSS-Yunzai" ;;
        2) hapi_prepare_workspace "${HOME}/AstrBot" ;;
        3) hapi_prepare_workspace "${HOME}/myrepo" ;;
        4)
            echo -en "${cyan}请输入 workspace-root 路径: ${background}"
            read -r custom_path
            if [ -z "${custom_path}" ]; then
                echo -e "${red}workspace-root 不能为空。${background}"
                continue
            fi
            hapi_prepare_workspace "${custom_path}"
            ;;
        5)
            if [ "${#HAPI_SELECTED_WORKSPACES[@]}" -eq 0 ]; then
                echo -e "${red}请至少添加一个工作目录。${background}"
                continue
            fi
            return 0
            ;;
        0) return 1 ;;
        *) echo -e "${red}输入错误${background}" ;;
        esac
    done
}

hapi_start_runner() {
    local runner_args=()
    local workspace_root listen_port hub_api_url running_runner_api_url

    hapi_ensure_command || return
    listen_port=$(hapi_read_setting "listenPort" "3006")
    hub_api_url="${HAPI_API_URL:-http://localhost:${listen_port}}"
    echo -e "${yellow}提示1：Hapi runner 是全局单实例，新设置会覆盖当前 runner 的 workspace-root。${background}"
    echo -e "${yellow}提示2：Hapi runner 用于从聊天窗口远程创建 session。如果不启动 Runner，你仍然可以管理已有 session，但不能方便地让 HAPI 在指定机器上新建任务。${background}"
    echo -e "${yellow}Runner 将连接本机 Hapi Hub: ${hub_api_url}${background}"
    hapi_select_workspaces || return

    for workspace_root in "${HAPI_SELECTED_WORKSPACES[@]}"; do
        runner_args+=(--workspace-root "${workspace_root}")
    done

    echo -e "${yellow}正在设置/运行 Hapi 工作目录:${background}"
    printf '  - %s\n' "${HAPI_SELECTED_WORKSPACES[@]}"

    # Hapi Runner 的 Hub 地址由 HAPI_API_URL 决定，默认值固定为
    # http://localhost:3006，并不会随 settings.json 的 listenPort 自动更新。
    # 若端口已变更，先停止仍连接旧地址的单实例 Runner，再以当前端口启动。
    running_runner_api_url=$(hapi runner status 2>/dev/null | sed -nE 's/^[[:space:]]*"startedWithApiUrl"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -n 1)
    if [ -n "${running_runner_api_url}" ] && [ "${running_runner_api_url}" != "${hub_api_url}" ]; then
        echo -e "${yellow}检测到现有 Runner 连接 ${running_runner_api_url}，正在切换到 ${hub_api_url}...${background}"
        if ! hapi runner stop; then
            echo -e "${red}停止现有 Hapi runner 失败，未启动新的 Runner。${background}"
            return 1
        fi
    fi

    if HAPI_API_URL="${hub_api_url}" hapi runner start "${runner_args[@]}"; then
        echo -e "${green}Hapi Runner 已按 listenPort ${listen_port} 启动，Hub 地址: ${hub_api_url}${background}"
    fi
}

hapi_runner_workspace_menu() {
    local num

    while true; do
        echo -e "${white}=====${green}Hapi runner 工作目录${white}=====${background}"
        echo -e "${green}1.  ${cyan}设置/运行 Hapi runner 工作目录${background}"
        echo -e "${green}2.  ${cyan}查看 Hapi runner 状态${background}"
        echo -e "${green}0.  ${cyan}返回上一级${background}"
        echo "========================="
        echo -en "${green}请输入您的选项: ${background}"; read -r num

        case "${num}" in
        1) hapi_start_runner; pause ;;
        2) if hapi_ensure_command; then hapi runner status; fi; pause ;;
        0) return ;;
        *) echo -e "${red}输入错误${background}"; pause ;;
        esac
    done
}

hapi_capture_hub_url() {
    local hub_output cli_token
    HAPI_HUB_URL=""
    if ! tmux has-session -t "${HAPI_HUB_TMUX_NAME}" 2>/dev/null; then
        return 1
    fi
    hub_output=$(tmux capture-pane -pt "${HAPI_HUB_TMUX_NAME}" -S -200 2>/dev/null)
    HAPI_HUB_URL=$(printf '%s\n' "${hub_output}" | grep -Eo 'https://app\.hapi\.run/[^[:space:]]*' | tail -n 1)
    if [ -z "${HAPI_HUB_URL}" ]; then
        HAPI_HUB_URL=$(printf '%s\n' "${hub_output}" | grep -Eo 'https://[0-9A-Za-z._-]+\.relay\.hapi\.run[^[:space:]]*' | tail -n 1)
    fi
    if [[ "${HAPI_HUB_URL}" == *"token=" ]]; then
        cli_token=$(hapi_read_setting "cliApiToken" "")
        if [ -n "${cli_token}" ]; then
            HAPI_HUB_URL="${HAPI_HUB_URL}${cli_token}"
        fi
    fi
    [ -n "${HAPI_HUB_URL}" ]
}

hapi_show_hub_access_fallback() {
    local access_mode="$1"
    local cli_token listen_host listen_port public_ip lan_ip direct_url

    if [ "${access_mode}" = "no-relay" ]; then
        echo -e "${yellow}当前 Hapi Hub 未使用公共 relay，以下为服务器直连信息。${background}"
    else
        echo -e "${white}========================================${background}"
        echo -e "${yellow}尚未收到公共中继分配的 URL，Hub 会继续在 tmux 中运行；${background}"
        echo -e "${yellow}可能是 Hapi 中继服务器故障，请重启为不使用中继模式。${background}"
        echo -e "${white}========================================${background}"
        return 0
    fi

    cli_token=$(hapi_read_setting "cliApiToken" "")
    listen_host=$(hapi_read_setting "listenHost" "127.0.0.1")
    listen_port=$(hapi_read_setting "listenPort" "3006")
    echo -e "${yellow}正在尝试生成服务器直连信息...${background}"

    if [ "${listen_host}" != "127.0.0.1" ] && [ "${listen_host}" != "localhost" ] && [ "${listen_host}" != "::1" ]; then
        public_ip=$(hapi_detect_public_ip)
        if [ -n "${public_ip}" ]; then
            direct_url="http://${public_ip}:${listen_port}"
            echo -e "${red}服务器公网 Hub 地址（需放行防火墙/安全组 TCP ${listen_port} 端口）：${background}"
            echo -e "${red}${direct_url}${background}"
        else
            lan_ip=$(hapi_detect_lan_ip)
            if [ -n "${lan_ip}" ]; then
                echo -e "${yellow}未获取到服务器公网 IP；局域网 Hub 地址：${background}"
                echo -e "${yellow}http://${lan_ip}:${listen_port}${background}"
            fi
        fi
    else
        echo -e "${yellow}当前 listenHost 为 ${listen_host}，仅能本机访问。将其设为 0.0.0.0 并重启 Hub 后，才能使用公网 IP:${listen_port}。${background}"
    fi

    if [ -n "${cli_token}" ]; then
        echo -e "${red}登录 token（敏感信息，请勿分享）：${background}"
        echo -e "${red}${cli_token}${background}"
    else
        echo -e "${yellow}未读取到 cliApiToken；请查看 ${HOME}/.hapi/settings.json。${background}"
    fi

}

hapi_show_hub_url() {
    if hapi_capture_hub_url; then
        echo -e "${red}重要：以下 URL 包含访问 token，不要发送给其他人！${background}"
        echo -e "${red}${HAPI_HUB_URL}${background}"
    else
        hapi_print_tmux_log "${HAPI_HUB_TMUX_NAME}" "Hapi Hub"
        hapi_show_hub_access_fallback "relay"
    fi
}

hapi_spinner_start() {
    local spinner_message="$1"

    hapi_spinner_stop
    HAPI_SPINNER_PID=""
    # 非交互输出（例如重定向到日志）不写入光标控制序列。
    [ -t 1 ] || return

    printf '\033[?25l'
    (
        local spinner_chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
        local spinner_index
        trap 'exit 0' TERM INT
        while true; do
            for ((spinner_index = 0; spinner_index < ${#spinner_chars}; spinner_index++)); do
                printf '\r\033[K\033[36m%s\033[0m \033[33m%s\033[0m' \
                    "${spinner_chars:spinner_index:1}" "${spinner_message}"
                sleep 0.1
            done
        done
    ) &
    HAPI_SPINNER_PID=$!
}

hapi_spinner_stop() {
    [ -n "${HAPI_SPINNER_PID:-}" ] || return
    kill "${HAPI_SPINNER_PID}" >/dev/null 2>&1
    wait "${HAPI_SPINNER_PID}" 2>/dev/null || true
    printf '\033[?25h\r\033[K'
    HAPI_SPINNER_PID=""
}

hapi_start_hub() {
    local hub_mode="${1:-relay}"
    local hub_command hub_label wait_limit

    hapi_ensure_command || return
    hapi_ensure_tmux || return

    if [ "${hub_mode}" = "no-relay" ]; then
        hub_command="hapi hub --no-relay"
        hub_label="Hapi Hub（不使用 relay）"
        wait_limit=10
    else
        hub_command="hapi hub --relay"
        hub_label="Hapi Hub"
        wait_limit="${HAPI_HUB_URL_WAIT_SECONDS}"
    fi

    if tmux has-session -t "${HAPI_HUB_TMUX_NAME}" 2>/dev/null; then
        echo -e "${green}${hub_label} 已在后台运行。${background}"
        if [ "${hub_mode}" = "no-relay" ]; then
            hapi_show_hub_access_fallback "no-relay"
        else
            hapi_show_hub_url
        fi
        return $?
    fi

    local wait_count
    wait_count=0
    echo -e "${yellow}正在启动 ${hub_label}...${background}"
    if ! tmux new-session -d -s "${HAPI_HUB_TMUX_NAME}" "export PATH=\"${PATH}\"; export PNPM_HOME=\"${PNPM_HOME}\"; ${hub_command}"; then
        echo -e "${red}Hapi Hub tmux 会话创建失败。${background}"
        return 1
    fi

    hapi_spinner_start "正在等待 ${hub_label} 就绪"
    while [ "${wait_count}" -lt "${wait_limit}" ]; do
        sleep 1
        if [ "${hub_mode}" = "no-relay" ]; then
            if tmux capture-pane -pt "${HAPI_HUB_TMUX_NAME}" -S -50 2>/dev/null | grep -qE '\[Web\] Hub listening on|\[Web\] hub listening on'; then
                hapi_spinner_stop
                hapi_show_hub_access_fallback "no-relay"
                echo -e "${green}${hub_label} 已在 tmux 会话 ${HAPI_HUB_TMUX_NAME} 中后台运行。${background}"
                return 0
            fi
        elif hapi_capture_hub_url; then
            hapi_spinner_stop
            if hapi_show_hub_url; then
                echo -e "${green}Hapi Hub 已在 tmux 会话 ${HAPI_HUB_TMUX_NAME} 中后台运行。${background}"
                return 0
            fi
            return 1
        fi
        wait_count=$((wait_count + 1))
    done
    hapi_spinner_stop

    if [ "${hub_mode}" = "no-relay" ]; then
        echo -e "${yellow}等待 ${wait_limit} 秒后仍未确认 Hub 就绪，下面输出 tmux 日志与直连信息。${background}"
        hapi_print_tmux_log "${HAPI_HUB_TMUX_NAME}" "Hapi Hub"
        hapi_show_hub_access_fallback "no-relay"
        echo -e "${green}${hub_label} 已保留在 tmux 会话 ${HAPI_HUB_TMUX_NAME} 中后台运行。${background}"
    else
        echo -e "${yellow}等待 ${wait_limit} 秒后仍未收到中继 URL，下面输出 tmux 日志。${background}"
        hapi_print_tmux_log "${HAPI_HUB_TMUX_NAME}" "Hapi Hub"
        hapi_show_hub_access_fallback "relay"
        echo -e "${green}${hub_label} 已保留在 tmux 会话 ${HAPI_HUB_TMUX_NAME} 中后台运行。${background}"
    fi
}

hapi_stop_all() {
    hapi_load_node_env
    if command -v tmux >/dev/null 2>&1 && tmux has-session -t "${HAPI_HUB_TMUX_NAME}" 2>/dev/null; then
        tmux kill-session -t "${HAPI_HUB_TMUX_NAME}" >/dev/null 2>&1
        echo -e "${green}已停止 Hapi Hub tmux 会话。${background}"
    else
        echo -e "${yellow}未检测到正在运行的 Hapi Hub tmux 会话。${background}"
    fi

    if command -v hapi >/dev/null 2>&1; then
        echo -e "${yellow}正在执行 hapi doctor clean 清理 runner 与相关进程...${background}"
        hapi doctor clean
    else
        echo -e "${yellow}未检测到 hapi 命令，跳过 runner 清理。${background}"
    fi
}

hapi_read_setting() {
    local key="$1"
    local default_value="$2"
    local settings_file="${HOME}/.hapi/settings.json"
    local value

    if [ -f "${settings_file}" ] && command -v node >/dev/null 2>&1; then
        value=$(node -e 'const fs = require("fs"); const file = process.argv[1]; const key = process.argv[2]; try { const data = JSON.parse(fs.readFileSync(file, "utf8")); const value = data[key]; if (value !== undefined && value !== null && value !== "") process.stdout.write(String(value)); } catch {}' "${settings_file}" "${key}" 2>/dev/null)
    fi

    if [ -n "${value}" ]; then
        printf '%s' "${value}"
    else
        printf '%s' "${default_value}"
    fi
}

hapi_check_listen_host() {
    local listen_host
    listen_host=$(hapi_read_setting "listenHost" "127.0.0.1")

    if [ "${listen_host}" = "0.0.0.0" ]; then
        echo -en ""
    else
        echo -e "${green}当前 listenHost -> ${listen_host}，Docker 或局域网访问前建议设置为 0.0.0.0。${background}"
    fi
}

hapi_set_listen_config() {
    local settings_dir="${HOME}/.hapi"
    local settings_file="${settings_dir}/settings.json"
    local current_host current_port listen_host listen_port backup_file

    if ! command -v node >/dev/null 2>&1; then
        echo -e "${red}未检测到 node，无法安全写入 Hapi JSON 配置。${background}"
        return 1
    fi

    current_host=$(hapi_read_setting "listenHost" "127.0.0.1")
    current_port=$(hapi_read_setting "listenPort" "3006")
    echo -e "${white}=====${green}设置 Hapi listenHost / listenPort${white}=====${background}"
    echo -e "${yellow}当前 listenHost: ${current_host}${background}"
    echo -e "${yellow}当前 listenPort: ${current_port}${background}"
    echo -e "${red}注意：修改 listenPort 后需要 停止 Hapi 并重启"
    echo -en "${cyan}请输入 listenHost (默认 ${current_host}，Docker/局域网建议 0.0.0.0): ${background}"
    read -r listen_host
    listen_host=${listen_host:-${current_host}}
    echo -en "${cyan}请输入 listenPort (默认 ${current_port}): ${background}"
    read -r listen_port
    listen_port=${listen_port:-${current_port}}

    if [ -z "${listen_host}" ]; then
        echo -e "${red}listenHost 不能为空。${background}"
        return 1
    fi
    if [[ ! "${listen_port}" =~ ^[0-9]+$ ]] || [ "${listen_port}" -lt 1 ] || [ "${listen_port}" -gt 65535 ]; then
        echo -e "${red}listenPort 必须是 1-65535 之间的数字。${background}"
        return 1
    fi

    mkdir -p "${settings_dir}"
    if [ -f "${settings_file}" ]; then
        backup_file="${settings_file}.bak"
        cp -a "${settings_file}" "${backup_file}"
        chmod 600 "${backup_file}" 2>/dev/null
        echo -e "${green}已备份原配置到: ${backup_file}${background}"
    fi
    if ! node -e 'const fs = require("fs"); const path = require("path"); const file = process.argv[1]; const host = process.argv[2]; const port = Number(process.argv[3]); let data = {}; if (fs.existsSync(file)) { try { data = JSON.parse(fs.readFileSync(file, "utf8")); } catch {} } data.listenHost = host; data.listenPort = port; fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, JSON.stringify(data, null, 2) + "\n");' "${settings_file}" "${listen_host}" "${listen_port}"; then
        echo -e "${red}Hapi 配置写入失败: ${settings_file}${background}"
        return 1
    fi
    chmod 600 "${settings_file}" 2>/dev/null
    echo -e "${green}已写入 Hapi 配置: ${settings_file}${background}"
    hapi_check_listen_host
    echo -e "${yellow}如果 Hapi Hub 正在运行，请重启 Hub 后让配置生效。${background}"
}

hapi_show_cli_api_token() {
    local settings_file="${HOME}/.hapi/settings.json"
    local token

    echo -e "${white}=====${green}Hapi cliApiToken${white}=====${background}"
    if [ ! -f "${settings_file}" ]; then
        echo -e "${yellow}未找到 Hapi 配置文件: ${settings_file}${background}"
        return 1
    fi

    if command -v node >/dev/null 2>&1; then
        token=$(node -e 'const fs = require("fs"); const file = process.argv[1]; const data = JSON.parse(fs.readFileSync(file, "utf8")); if (data.cliApiToken) process.stdout.write(data.cliApiToken);' "${settings_file}" 2>/dev/null)
    fi
    if [ -z "${token}" ]; then
        token=$(sed -nE 's/^[[:space:]]*"cliApiToken"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' "${settings_file}" | head -n 1)
    fi

    if [ -z "${token}" ]; then
        echo -e "${yellow}未在 ${settings_file} 中读取到 cliApiToken。${background}"
        return 1
    fi

    echo -e "${red}重要：cliApiToken 是敏感凭据，不要发送给其他人！${background}"
    echo -e "${red}${token}${background}"
}

hapi_set_cli_api_token() {
    local settings_dir="${HOME}/.hapi"
    local settings_file="${settings_dir}/settings.json"
    local token backup_file

    if ! command -v node >/dev/null 2>&1; then
        echo -e "${red}未检测到 node，无法安全写入 Hapi JSON 配置。${background}"
        return 1
    fi

    echo -en "${cyan}请输入新的 cliApiToken: ${background}"
    read -rs token
    echo
    if [ -z "${token}" ]; then
        echo -e "${red}cliApiToken 不能为空。${background}"
        return 1
    fi

    mkdir -p "${settings_dir}"
    if [ -f "${settings_file}" ]; then
        backup_file="${settings_file}.bak"
        cp -a "${settings_file}" "${backup_file}"
        chmod 600 "${backup_file}" 2>/dev/null
        echo -e "${green}已备份原配置到: ${backup_file}${background}"
    fi
    if ! node -e 'const fs = require("fs"); const path = require("path"); const file = process.argv[1]; const token = process.argv[2]; let data = {}; if (fs.existsSync(file)) { try { data = JSON.parse(fs.readFileSync(file, "utf8")); } catch {} } data.cliApiToken = token; fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, JSON.stringify(data, null, 2) + "\n", { mode: 0o600 }); try { fs.chmodSync(file, 0o600); } catch {}' "${settings_file}" "${token}"; then
        echo -e "${red}cliApiToken 写入失败: ${settings_file}${background}"
        return 1
    fi
    chmod 600 "${settings_file}" 2>/dev/null
    echo -e "${green}cliApiToken 已写入: ${settings_file}${background}"
}

hapi_manage_cli_api_token() {
    local confirm

    hapi_show_cli_api_token || true
    echo -en "${yellow}是否设置/更新 cliApiToken？[y/N]: ${background}"
    read -r confirm
    if [[ "${confirm}" == "y" || "${confirm}" == "Y" ]]; then
        hapi_set_cli_api_token
    else
        echo -e "${yellow}未修改 cliApiToken。${background}"
    fi
}

hapi_show_astrbot_plugin_config() {
    local listen_host listen_port token

    listen_host=$(hapi_read_setting "listenHost" "127.0.0.1")
    listen_port=$(hapi_read_setting "listenPort" "3006")
    token=$(hapi_read_setting "cliApiToken" "")

    echo -e ""
    echo -e "${white}=========================================${background}"
    echo -e "${white}||   ${green}hapi_connector 插件配置帮助${white}   ||${background}"
    echo -e "${white}=========================================${background}"
    echo -e ""

    echo -e "${white}【${green}一、当前 Hapi Hub 状态${white}】${background}"
    echo -e "  ${yellow}1. listenHost : ${cyan}${listen_host}${background}"
    echo -e "  ${yellow}2. listenPort : ${cyan}${listen_port}${background}"
    echo -e ""

    echo -e "${white}【${green}hapi_connector 插件配置页必填字段${white}】${background}"
    echo -e ""

    echo -e "  ${yellow}1. ${cyan}hapi_endpoint${yellow}（请根据 hapi_connector 插件 与 AstrBot/TRSS 的环境选择其一）：${background}"
    echo -e "     ${cyan}(1)${background} 同一宿主机（非 Docker）"
    echo -e "         ${green}http://localhost:${listen_port}${background}"
    echo -e "     ${cyan}(2)${background} AstrBot/TRSS Docker（Linux 宿主机默认）"
    echo -e "         ${green}http://172.17.0.1:${listen_port}${background}"
    echo -e "     ${cyan}(3)${background} AstrBot/TRSS Docker（Windows / macOS 宿主机）"
    echo -e "         ${green}http://host.docker.internal:${listen_port}${background}"
    echo -e "     ${cyan}(4)${background} 同一内网 / Tailscale"
    echo -e "         ${green}http://<HAPI机器IP>:${listen_port}${background}"
    echo -e "     ${cyan}(5)${background} 公共中继 / 自建隧道"
    echo -e "         ${green}使用 Hub URL 或你的域名${background}"
    echo -e ""

    echo -e "  ${yellow}2. ${cyan}access_token${background}："
    if [ -n "${token}" ]; then
        echo -e "     ${red}${token}${background}"
    else
        echo -e "     ${yellow}未读取到 cliApiToken，请先启动 Hapi Hub 生成 ~/.hapi/settings.json。${background}"
    fi
    echo -e ""

    echo -e "${white}【${green}三、新手必读${white}】${background}"
    echo -e "  ${yellow}1.${background} 如果 AstrBot/TRSS Docker 是 Docker 启动，本脚本所在 Linux 宿主机通常填写:"
    echo -e "     ${green}http://172.17.0.1:${listen_port}${background}"
    echo -e "  ${yellow}2.${background} Docker 场景必须先让 Hapi 监听所有网卡，即 listenHost -> 0.0.0.0。"
    echo -e ""

    hapi_check_listen_host
}

hapi_attach_tmux() {
    hapi_ensure_tmux || return

    if ! tmux has-session -t "${HAPI_HUB_TMUX_NAME}" 2>/dev/null; then
        echo -e "${yellow}未检测到正在运行的 Hapi Hub tmux 会话: ${HAPI_HUB_TMUX_NAME}${background}"
        return 1
    fi

    echo -e "${yellow}即将打开 tmux 会话 ${HAPI_HUB_TMUX_NAME}。${background}"
    echo -e "${yellow}返回菜单请按 ctrl+b d。${background}"
    echo -en "${green}按回车键进入 tmux...${background}"
    read -r
    tmux attach-session -t "${HAPI_HUB_TMUX_NAME}"
}

hapi_restart_hub() {
    local hub_mode="${1:-relay}"

    hapi_ensure_command || return
    hapi_ensure_tmux || return

    if tmux has-session -t "${HAPI_HUB_TMUX_NAME}" 2>/dev/null; then
        tmux kill-session -t "${HAPI_HUB_TMUX_NAME}" >/dev/null 2>&1
        echo -e "${green}已停止现有 Hapi Hub tmux 会话。${background}"
    else
        echo -e "${yellow}未检测到正在运行的 Hapi Hub tmux 会话，将直接启动。${background}"
    fi
    hapi_start_hub "${hub_mode}"
}

hapi_hub_menu() {
    local num

    while true; do
        echo -e "${white}=====${green}Hapi hub${white}=====${background}"
        echo -e "${green}1.  ${cyan}启动/重启 Hapi hub（获取中继 URL）${background}"
        echo -e "${green}2.  ${cyan}启动/重启 Hapi hub（不使用中继）${background}"
        echo -e "${green}3.  ${cyan}打开当前的 tmux${background}"
        echo -e "${green}0.  ${cyan}返回上一级${background}"
        echo "========================="
        echo -en "${green}请输入您的选项: ${background}"; read -r num

        case "${num}" in
        1) hapi_restart_hub; pause ;;
        2) hapi_restart_hub "no-relay"; pause ;;
        3) hapi_attach_tmux; pause ;;
        0) return ;;
        *) echo -e "${red}输入错误${background}"; pause ;;
        esac
    done
}

hapi_detect_lan_ip() {
    local ip
    ip=$(ip -4 route get 1.1.1.1 2>/dev/null | sed -n 's/.*src \([0-9.]\+\).*/\1/p' | head -n 1)
    if [ -z "${ip}" ] && command -v hostname >/dev/null 2>&1; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    printf '%s' "${ip}"
}

hapi_detect_public_ip() {
    local ip
    ip=$(curl -sL --max-time 5 https://ipinfo.io/ip 2>/dev/null | tr -d '[:space:]')
    if [[ ! "${ip}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        ip=$(curl -sL --max-time 5 https://api.ipify.org 2>/dev/null | tr -d '[:space:]')
    fi
    if [[ "${ip}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        printf '%s' "${ip}"
    fi
}

hapi_capture_opencode_web_url() {
    local pane_output listen_url port lan_ip
    HAPI_OPENCODE_WEB_URL=""
    HAPI_OPENCODE_WEB_PHONE_URL=""
    HAPI_OPENCODE_WEB_PUBLIC_URL=""

    if ! tmux has-session -t "${HAPI_OPENCODE_WEB_TMUX_NAME}" 2>/dev/null; then
        return 1
    fi
    pane_output=$(tmux capture-pane -pt "${HAPI_OPENCODE_WEB_TMUX_NAME}" -S -200 2>/dev/null)
    listen_url=$(printf '%s\n' "${pane_output}" | grep -Eo 'https?://[0-9A-Za-z._-]+:[0-9]+' | tail -n 1)
    [ -n "${listen_url}" ] || return 1

    HAPI_OPENCODE_WEB_URL="${listen_url}"
    port=$(printf '%s' "${listen_url}" | sed -n 's#.*:\([0-9]\+\)$#\1#p')
    lan_ip=$(hapi_detect_lan_ip)
    if [ -n "${lan_ip}" ] && [ -n "${port}" ]; then
        HAPI_OPENCODE_WEB_PHONE_URL="http://${lan_ip}:${port}"
    fi
    return 0
}

hapi_show_opencode_web_url() {
    if ! hapi_capture_opencode_web_url; then
        echo -e "${yellow}暂未提取到 opencode web URL，请稍后重试或查看 tmux 日志。${background}"
        return 1
    fi

    local public_ip port listen_host auth_username auth_password
    echo -e ""
    echo -e "${white}==========${green} opencode Web 访问地址 ${white}==========${background}"
    echo -e "${cyan}本机监听地址${white}：${green}${HAPI_OPENCODE_WEB_URL}${background}"
    if [ -n "${HAPI_OPENCODE_WEB_PHONE_URL}" ]; then
        echo -e "${cyan}局域网访问地址${white}：${green}${HAPI_OPENCODE_WEB_PHONE_URL}${background}"
        echo -e "${yellow}  手机需与本机在同一局域网，或通过 Tailscale / 隧道访问。${background}"
    else
        echo -e "${yellow}未能自动探测局域网 IP，请用本机的局域网/公网 IP 替换上方地址中的 host 部分。${background}"
    fi

    listen_host=$(printf '%s' "${HAPI_OPENCODE_WEB_URL}" | sed -n 's#https\?://\([^:/]*\):[0-9]\+.*#\1#p')
    if [ "${listen_host}" != "127.0.0.1" ] && [ "${listen_host}" != "localhost" ]; then
        port=$(printf '%s' "${HAPI_OPENCODE_WEB_URL}" | sed -n 's#.*:\([0-9]\+\)$#\1#p')
        echo -e "${yellow}正在获取本服务器公网 IP...${background}"
        public_ip=$(hapi_detect_public_ip)
        if [ -n "${public_ip}" ] && [ -n "${port}" ]; then
            HAPI_OPENCODE_WEB_PUBLIC_URL="http://${public_ip}:${port}"
            echo -e "${cyan}公网访问地址${white}：${red}${HAPI_OPENCODE_WEB_PUBLIC_URL}${background}"
            echo -e "${yellow}  请确认已放行防火墙/安全组 TCP ${port} 端口。${background}"
        else
            echo -e "${yellow}未能获取公网 IP，请手动用公网 IP 替换地址中的 host 部分。${background}"
        fi
    fi

    if [ -n "${HAPI_OPENCODE_WEB_AUTH}" ]; then
        auth_username=${HAPI_OPENCODE_WEB_USERNAME:-${HAPI_OPENCODE_WEB_AUTH%% / *}}
        auth_password=${HAPI_OPENCODE_WEB_PASSWORD:-${HAPI_OPENCODE_WEB_AUTH#* / }}
        echo -e "${white}==========${red} HTTP Basic Auth（敏感） ${white}==========${background}"
        echo -e "${cyan}用户名${white}：${red}${auth_username}${background}"
        echo -e "${cyan}密  码${white}：${red}${auth_password}${background}"
        echo -e "${yellow}请勿将以上凭据发送给其他人。${background}"
    else
        echo -e "${yellow}HTTP Basic Auth 为必填；当前脚本未记录本次启动的用户名/密码。${background}"
    fi
    echo -e "${white}=============================================${background}"
    echo -e "${yellow}提示：请在 Chromium 内核浏览器（Chrome / Edge 等）打开，否则可能报错。${background}"
}

hapi_opencode_web_start() {
    hapi_ensure_opencode || return
    hapi_ensure_tmux || return

    local confirm
    if tmux has-session -t "${HAPI_OPENCODE_WEB_TMUX_NAME}" 2>/dev/null; then
        echo -e "${green}opencode web 已在后台运行。${background}"
        hapi_show_opencode_web_url
        echo -en "${yellow}是否停止并使用新配置重启？[y/N]: ${background}"
        read -r confirm
        if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
            return
        fi
        tmux kill-session -t "${HAPI_OPENCODE_WEB_TMUX_NAME}" >/dev/null 2>&1
    fi

    local port hostname password username remote
    echo -e "${white}=====${green}启动 opencode 网页控制台${white}=====${background}"
    echo -en "${cyan}请输入监听端口 (默认 50851): ${background}"
    read -r port
    port=${port:-50851}
    if [[ ! "${port}" =~ ^[0-9]+$ ]] || [ "${port}" -lt 1 ] || [ "${port}" -gt 65535 ]; then
        echo -e "${red}端口必须是 1-65535 之间的数字。${background}"
        return 1
    fi

    echo -en "${cyan}是否允许手机/局域网远程访问（监听 0.0.0.0）？[Y/n]: ${background}"
    read -r remote
    if [[ "${remote}" == "n" || "${remote}" == "N" ]]; then
        hostname="127.0.0.1"
    else
        hostname="0.0.0.0"
    fi

    echo -en "${cyan}请输入访问密码（已隐藏输入，回车则随机密码）: ${background}"
    read -rs password
    echo
    if [ -z "${password}" ]; then
        password=$(hapi_generate_secure_password)
        if [ -z "${password}" ]; then
            echo -e "${red}随机访问密码生成失败，请手动输入访问密码后重试。${background}"
            return 1
        fi
        echo -e "${green}已生成随机访问密码，启动成功后会显示用户名/密码。${background}"
    fi
    echo -en "${cyan}请输入访问用户名 (默认 opencode): ${background}"
    read -r username
    username=${username:-opencode}
    HAPI_OPENCODE_WEB_AUTH="${username} / ${password}"
    HAPI_OPENCODE_WEB_USERNAME="${username}"
    HAPI_OPENCODE_WEB_PASSWORD="${password}"

    local launch_cmd password_shell username_shell
    printf -v password_shell '%q' "${password}"
    printf -v username_shell '%q' "${username}"
    launch_cmd="export PATH=\"${PATH}\"; export PNPM_HOME=\"${PNPM_HOME}\";"
    launch_cmd="${launch_cmd} export OPENCODE_SERVER_PASSWORD=${password_shell}; export OPENCODE_SERVER_USERNAME=${username_shell};"
    launch_cmd="${launch_cmd} opencode web --port ${port} --hostname ${hostname}"

    local attempt wait_count
    attempt=1
    while [ "${attempt}" -le 3 ]; do
        echo -e "${yellow}正在启动 opencode web (第 ${attempt}/3 次)...${background}"
        tmux kill-session -t "${HAPI_OPENCODE_WEB_TMUX_NAME}" >/dev/null 2>&1
        if ! tmux new-session -d -s "${HAPI_OPENCODE_WEB_TMUX_NAME}" "${launch_cmd}"; then
            echo -e "${red}opencode web tmux 会话创建失败。${background}"
            return 1
        fi

        wait_count=0
        while [ "${wait_count}" -lt 20 ]; do
            sleep 1
            if hapi_capture_opencode_web_url; then
                hapi_show_opencode_web_url
                echo -e "${green}opencode web 已在 tmux 会话 ${HAPI_OPENCODE_WEB_TMUX_NAME} 中后台运行。${background}"
                return 0
            fi
            wait_count=$((wait_count + 1))
        done

        if [ "${attempt}" -lt 3 ]; then
            echo -e "${yellow}本次未提取到 opencode web URL，正在重启重试...${background}"
        else
            echo -e "${yellow}最后一次仍未提取到 opencode web URL，下面输出本次 tmux 日志。${background}"
            hapi_print_tmux_log "${HAPI_OPENCODE_WEB_TMUX_NAME}" "opencode web"
        fi
        tmux kill-session -t "${HAPI_OPENCODE_WEB_TMUX_NAME}" >/dev/null 2>&1
        attempt=$((attempt + 1))
    done

    echo -e "${red}连续 3 次未提取到 opencode web URL，已在上方输出最后一次启动的 tmux 日志。${background}"
    return 1
}

hapi_opencode_web_restart() {
    hapi_ensure_opencode || return
    hapi_ensure_tmux || return

    if tmux has-session -t "${HAPI_OPENCODE_WEB_TMUX_NAME}" 2>/dev/null; then
        tmux kill-session -t "${HAPI_OPENCODE_WEB_TMUX_NAME}" >/dev/null 2>&1
        echo -e "${green}已停止现有 opencode web tmux 会话。${background}"
    else
        echo -e "${yellow}未检测到正在运行的 opencode web tmux 会话，将直接启动。${background}"
    fi
    hapi_opencode_web_start
}

hapi_opencode_web_attach() {
    hapi_ensure_tmux || return

    if ! tmux has-session -t "${HAPI_OPENCODE_WEB_TMUX_NAME}" 2>/dev/null; then
        echo -e "${yellow}未检测到正在运行的 opencode web tmux 会话: ${HAPI_OPENCODE_WEB_TMUX_NAME}${background}"
        return 1
    fi

    echo -e "${yellow}即将打开 tmux 会话 ${HAPI_OPENCODE_WEB_TMUX_NAME}。${background}"
    echo -e "${yellow}返回菜单请按 ctrl+b d。${background}"
    echo -en "${green}按回车键进入 tmux...${background}"
    read -r
    tmux attach-session -t "${HAPI_OPENCODE_WEB_TMUX_NAME}"
}

hapi_opencode_web_stop() {
    if command -v tmux >/dev/null 2>&1 && tmux has-session -t "${HAPI_OPENCODE_WEB_TMUX_NAME}" 2>/dev/null; then
        tmux kill-session -t "${HAPI_OPENCODE_WEB_TMUX_NAME}" >/dev/null 2>&1
        HAPI_OPENCODE_WEB_AUTH=""
        HAPI_OPENCODE_WEB_USERNAME=""
        HAPI_OPENCODE_WEB_PASSWORD=""
        echo -e "${green}已停止 opencode web tmux 会话。${background}"
    else
        echo -e "${yellow}未检测到正在运行的 opencode web tmux 会话。${background}"
    fi
}

hapi_opencode_web_menu() {
    local num

    while true; do
        echo -e "${white}=====${green}opencode 网页控制台 (WebUI)${white}=====${background}"
        echo -e "${yellow}通过 opencode web 启动 headless 服务并附带网页界面，可在手机浏览器远程控制。${background}"
        echo -e "${green}1.  ${cyan}启动/查看 网页控制台 URL${background}"
        echo -e "${green}2.  ${cyan}重启 opencode web${background}"
        echo -e "${green}3.  ${cyan}打开当前的 tmux${background}"
        echo -e "${green}4.  ${cyan}停止 opencode web${background}"
        echo -e "${green}0.  ${cyan}返回上一级${background}"
        echo "========================="
        echo -en "${green}请输入您的选项: ${background}"; read -r num

        case "${num}" in
        1) hapi_opencode_web_start; pause ;;
        2) hapi_opencode_web_restart; pause ;;
        3) hapi_opencode_web_attach; pause ;;
        4) hapi_opencode_web_stop; pause ;;
        0) return ;;
        *) echo -e "${red}输入错误${background}"; pause ;;
        esac
    done
}

hapi_show_versions() {
    hapi_load_node_env
    echo -e "${white}=====${green}Hapi / Claude Code / Codex 版本${white}=====${background}"
    if command -v codex >/dev/null 2>&1; then
        codex --version
    else
        echo -e "${yellow}未检测到 codex 命令。${background}"
    fi
    if command -v claude >/dev/null 2>&1; then
        claude --version
    else
        echo -e "${yellow}未检测到 claude 命令。${background}"
    fi
    if command -v opencode >/dev/null 2>&1; then
        opencode --version
    else
        echo -e "${yellow}未检测到 opencode 命令。${background}"
    fi
    if command -v hapi >/dev/null 2>&1; then
        hapi --version
    else
        echo -e "${yellow}未检测到 hapi 命令。${background}"
    fi
}

hapi_uninstall() {
    local num confirm remove_status target_label stop_hapi
    local uninstall_packages=()

    hapi_show_versions
    echo -e "${white}=====${green}选择卸载目标${white}=====${background}"
    echo -e "${green}1.  ${cyan}卸载 Codex${background}"
    echo -e "${green}2.  ${cyan}卸载 Claude Code${background}"
    echo -e "${green}3.  ${cyan}卸载 opencode${background}"
    echo -e "${green}4.  ${cyan}卸载 Hapi${background}"
    echo -e "${green}0.  ${cyan}取消${background}"
    echo "========================="
    echo -en "${green}请输入您的选项: ${background}"; read -r num

    case "${num}" in
    1)
        target_label="Codex"
        uninstall_packages=("@openai/codex")
        stop_hapi="false"
        ;;
    2)
        target_label="Claude Code"
        uninstall_packages=("@anthropic-ai/claude-code")
        stop_hapi="false"
        ;;
    3)
        target_label="opencode"
        uninstall_packages=("opencode-ai")
        stop_hapi="false"
        ;;
    4)
        target_label="Hapi"
        uninstall_packages=("@twsxtd/hapi")
        stop_hapi="true"
        ;;
    0)
        echo -e "${yellow}已取消卸载。${background}"
        return
        ;;
    *)
        echo -e "${red}输入错误${background}"
        return 1
        ;;
    esac

    echo -e "${yellow}卸载将移除全局安装的 ${target_label}，不会删除 ~/.codex、~/.claude、~/.config/opencode 或 ~/.hapi 配置目录。${background}"
    echo -en "${yellow}确定要卸载 ${target_label} 吗？[y/N]: ${background}"
    read -r confirm
    if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
        echo -e "${yellow}已取消卸载。${background}"
        return
    fi

    if [ "${stop_hapi}" = "true" ]; then
        hapi_stop_all
    fi
    hapi_load_node_env
    if command -v pnpm >/dev/null 2>&1; then
        echo -e "${yellow}正在卸载 ${target_label}...${background}"
        pnpm remove -g "${uninstall_packages[@]}"
        remove_status=$?
    elif command -v npm >/dev/null 2>&1; then
        echo -e "${yellow}未检测到 pnpm，正在尝试使用 npm 卸载...${background}"
        npm uninstall -g "${uninstall_packages[@]}"
        remove_status=$?
    else
        echo -e "${red}未检测到 pnpm/npm，无法自动卸载。${background}"
        return 1
    fi

    if [ "${remove_status}" -eq 0 ]; then
        echo -e "${green}${target_label} 卸载完成。${background}"
    else
        echo -e "${red}卸载命令执行失败，请检查上方输出。${background}"
        return "${remove_status}"
    fi
}

hapi_config_menu() {
    local num

    while true; do
        echo -e "${white}=====${green}设置 Hapi 配置${white}=====${background}"
        echo -e "${green}1.  ${cyan}设置 listenHost 和端口号${background}"
        echo -e "${green}2.  ${cyan}查看/设置 cliApiToken${background}"
        echo -e "${green}3.  ${cyan}（额外） hapi_connector 插件配置帮助${background}"
        echo -e "${green}0.  ${cyan}返回上一级${background}"
        echo "========================="
        echo -en "${green}请输入您的选项: ${background}"; read -r num

        case "${num}" in
        1) hapi_set_listen_config; pause ;;
        2) hapi_manage_cli_api_token; pause ;;
        3) hapi_show_astrbot_plugin_config; pause ;;
        0) return ;;
        *) echo -e "${red}输入错误${background}"; pause ;;
        esac
    done
}

manage_hapi() {
    echo -e "${white}========================================${background}"
    echo -e "${white}  ${green}Hapi / Claude Code / Codex / opencode 管理${background}"
    echo -e "${white}========================================${background}"
    echo -e "${yellow}-- Codex --${background}"
    echo -e "${green}1.  ${cyan}安装/更新 Codex${background}"
    echo -e "${green}2.  ${cyan}配置 Codex${background}"
    echo -e "${white}----------------------------------------${background}"
    echo -e "${yellow}-- Claude Code --${background}"
    echo -e "${green}3.  ${cyan}安装/更新 Claude Code${background}"
    echo -e "${green}4.  ${cyan}配置 Claude Code${background}"
    echo -e "${white}----------------------------------------${background}"
    echo -e "${yellow}-- opencode --${background}"
    echo -e "${green}5.  ${cyan}安装/更新 opencode${background}"
    echo -e "${green}6.  ${cyan}opencode 网页控制台 (WebUI)${background}"
    echo -e "${white}----------------------------------------${background}"
    echo -e "${yellow}-- Hapi --${background}"
    echo -e "${green}7.  ${cyan}安装/更新 Hapi${background}"
    echo -e "${green}8.  ${cyan}设置/运行 Hapi runner 工作目录${background}"
    echo -e "${green}9.  ${cyan}设置 Hapi CLI${background}"
    echo -e "${green}10. ${cyan}运行 Hapi hub${background}"
    echo -e "${green}11. ${cyan}停止 Hapi${background}"
    echo -e "${white}----------------------------------------${background}"
    echo -e "${yellow}-- 其他 --${background}"
    echo -e "${green}12. ${cyan}卸载${background}"
    echo -e "${green}0.  ${cyan}退出${background}"
    echo -e "${white}========================================${background}"
    echo -en "${green}请输入您的选项: ${background}"; read -r num

    case "${num}" in
    1) hapi_install_codex; pause; manage_hapi ;;
    2) hapi_codex_config_menu; manage_hapi ;;
    3) hapi_install_claude_code; pause; manage_hapi ;;
    4) hapi_claude_config_menu; manage_hapi ;;
    5) hapi_install_opencode; pause; manage_hapi ;;
    6) hapi_opencode_web_menu; manage_hapi ;;
    7) hapi_install_hapi; pause; manage_hapi ;;
    8) hapi_runner_workspace_menu; manage_hapi ;;
    9) hapi_config_menu; manage_hapi ;;
    10) hapi_hub_menu; manage_hapi ;;
    11) hapi_stop_all; pause; manage_hapi ;;
    12) hapi_uninstall; pause; manage_hapi ;;
    0) exit 0 ;;
    *) echo -e "${red}输入错误${background}"; pause; manage_hapi ;;
    esac
}

# 主循环函数
function mainloop() {
    while true
    do
        manage_hapi
    done
}

# 启动主循环
mainloop

