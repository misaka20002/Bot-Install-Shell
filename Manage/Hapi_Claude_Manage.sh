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
    local default_sonnet_model="${5:-claude-sonnet-4-5-20250929}"
    local default_opus_model="${6:-claude-opus-4-8[1M]}"
    local default_max_effort="$7"
    local auth_token base_url haiku_model sonnet_model opus_model enable_max_effort
    local reasoning_suffix effort_line
    local auth_token_json base_url_json haiku_json sonnet_json opus_json

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

    echo -en "${cyan}请输入 HAIKU_MODEL (默认 ${default_haiku_model}): ${background}"
    read -r haiku_model
    haiku_model=${haiku_model:-${default_haiku_model}}

    echo -en "${cyan}请输入 SONNET_MODEL (默认 ${default_sonnet_model}): ${background}"
    read -r sonnet_model
    sonnet_model=${sonnet_model:-${default_sonnet_model}}

    echo -en "${cyan}请输入 OPUS_MODEL (默认 ${default_opus_model}): ${background}"
    read -r opus_model
    opus_model=${opus_model:-${default_opus_model}}

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
    opus_json=$(hapi_json_escape "${opus_model}")

    cat > "${output_file}" << EOF
{
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "${auth_token_json}",
    "ANTHROPIC_BASE_URL": "${base_url_json}",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "${haiku_json}",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "${opus_json}",
    "ANTHROPIC_DEFAULT_OPUS_MODEL_NAME": "${opus_json}",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "${sonnet_json}",
    "ANTHROPIC_DEFAULT_SONNET_MODEL_NAME": "${sonnet_json}",
    "ANTHROPIC_MODEL": "${sonnet_json}",
    "ANTHROPIC_REASONING_MODEL": "${opus_json}"${reasoning_suffix}
${effort_line}
  },
  "includeCoAuthoredBy": false
}
EOF
}

hapi_config_claude() {
    local config_dir="${HOME}/.claude"
    local settings_file="${config_dir}/settings.json"
    local backup_file
    local current_auth_token current_base_url current_haiku_model current_sonnet_model current_opus_model current_max_effort

    hapi_show_claude_config "${settings_file}" || true

    if [ -f "${settings_file}" ]; then
        echo -en "${yellow}检测到已存在 Claude Code 配置，继续将覆盖原有配置！是否继续？[y/N]: ${background}"
        read -r overwrite
        if [[ "${overwrite}" != "y" && "${overwrite}" != "Y" ]]; then
            echo -e "${yellow}已取消配置。${background}"
            return
        fi
        backup_file="${settings_file}.bak"
        cp -a "${settings_file}" "${backup_file}"
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
    current_max_effort=$(hapi_claude_current_value "CLAUDE_CODE_EFFORT_LEVEL" "${settings_file}")

    mkdir -p "${config_dir}"
    hapi_write_claude_settings_file \
        "${settings_file}" \
        "${current_auth_token}" \
        "${current_base_url}" \
        "${current_haiku_model}" \
        "${current_sonnet_model}" \
        "${current_opus_model}" \
        "${current_max_effort}" || return
    chmod 600 "${settings_file}"
    echo -e "${green}Claude Code 配置已写入: ${settings_file}${background}"
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
    node -e 'const fs = require("fs"); const path = require("path"); const storeFile = process.argv[1]; const name = process.argv[2]; const sourceFile = process.argv[3]; const config = JSON.parse(fs.readFileSync(sourceFile, "utf8")); let store = { profiles: [] }; if (fs.existsSync(storeFile)) { try { store = JSON.parse(fs.readFileSync(storeFile, "utf8")); } catch {} } if (!Array.isArray(store.profiles)) store.profiles = []; const now = new Date().toISOString(); const idx = store.profiles.findIndex((item) => item && item.name === name); if (idx >= 0) { store.profiles[idx] = { ...store.profiles[idx], name, updatedAt: now, config }; } else { store.profiles.push({ name, createdAt: now, updatedAt: now, config }); } fs.mkdirSync(path.dirname(storeFile), { recursive: true }); fs.writeFileSync(storeFile, JSON.stringify(store, null, 2) + "\n");' "${store_file}" "${profile_name}" "${source_file}" || return
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

    tmp_file="${TMPDIR:-/tmp}/hapi_claude_settings_$$.json"
    if ! hapi_write_claude_settings_file "${tmp_file}"; then
        rm -f "${tmp_file}"
        return 1
    fi
    if ! hapi_save_claude_profile_from_file "${profile_name}" "${tmp_file}"; then
        rm -f "${tmp_file}"
        return 1
    fi
    rm -f "${tmp_file}"
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
        echo -e "${green}已备份原配置到: ${backup_file}${background}"
    fi
    hapi_ensure_node_json || return
    node -e 'const fs = require("fs"); const storeFile = process.argv[1]; const settingsFile = process.argv[2]; const index = Number(process.argv[3]) - 1; const store = JSON.parse(fs.readFileSync(storeFile, "utf8")); const profiles = Array.isArray(store.profiles) ? store.profiles : []; if (!profiles[index] || !profiles[index].config) { console.error("配置序号不存在"); process.exit(1); } fs.writeFileSync(settingsFile, JSON.stringify(profiles[index].config, null, 2) + "\n"); console.log(profiles[index].name);' "${store_file}" "${settings_file}" "${num}"
    local switch_status=$?
    if [ "${switch_status}" -ne 0 ]; then
        echo -e "${red}切换配置失败。${background}"
        return "${switch_status}"
    fi
    chmod 600 "${settings_file}"
    echo -e "${green}Claude Code 配置已切换: ${settings_file}${background}"
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
    node -e 'const fs = require("fs"); const storeFile = process.argv[1]; const index = Number(process.argv[2]) - 1; const store = JSON.parse(fs.readFileSync(storeFile, "utf8")); const profiles = Array.isArray(store.profiles) ? store.profiles : []; if (!profiles[index]) { console.error("配置序号不存在"); process.exit(1); } const removed = profiles.splice(index, 1)[0]; store.profiles = profiles; fs.writeFileSync(storeFile, JSON.stringify(store, null, 2) + "\n"); console.log(removed.name);' "${store_file}" "${num}"
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

hapi_show_codex_config() {
    local config_dir auth_file config_file
    config_dir="${HOME}/.codex"
    auth_file="${config_dir}/auth.json"
    config_file="${config_dir}/config.toml"

    echo -e "${white}=====${green}当前 Codex 配置${white}=====${background}"
    hapi_ensure_node_json || return
    CODEX_AUTH_FILE="${auth_file}" CODEX_CONFIG_FILE="${config_file}" node <<'NODE'
const fs = require("fs");
const authFile = process.env.CODEX_AUTH_FILE;
const configFile = process.env.CODEX_CONFIG_FILE;

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
    local api_key="$1"
    local base_url="$2"
    local model="$3"
    local config_dir auth_file config_file backup_file
    config_dir="${HOME}/.codex"
    auth_file="${config_dir}/auth.json"
    config_file="${config_dir}/config.toml"

    hapi_ensure_node_json || return
    mkdir -p "${config_dir}"
    if [ -f "${auth_file}" ]; then
        backup_file="${auth_file}.bak"
        cp -a "${auth_file}" "${backup_file}"
        echo -e "${green}已备份原配置到: ${backup_file}${background}"
    fi
    if [ -f "${config_file}" ]; then
        backup_file="${config_file}.bak"
        cp -a "${config_file}" "${backup_file}"
        echo -e "${green}已备份原配置到: ${backup_file}${background}"
    fi

    CODEX_AUTH_FILE="${auth_file}" CODEX_CONFIG_FILE="${config_file}" CODEX_API_KEY="${api_key}" CODEX_BASE_URL="${base_url}" CODEX_MODEL="${model}" node <<'NODE'
const fs = require("fs");
const path = require("path");
const authFile = process.env.CODEX_AUTH_FILE;
const configFile = process.env.CODEX_CONFIG_FILE;
const apiKey = process.env.CODEX_API_KEY || "";
const baseUrl = process.env.CODEX_BASE_URL || "https://api.openai.com/v1";
const model = process.env.CODEX_MODEL || "gpt-5.5";

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

function createTemplate() {
  return [
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
}

function updateToml(text) {
  if (!text.trim()) return createTemplate();
  validateToml(text);
  const lines = text.replace(/\r\n/g, "\n").split("\n");
  if (lines.length && lines[lines.length - 1] === "") lines.pop();
  const providerId = getTopLevelString(lines, "model_provider") || "custom";
  ensureTopLevelString(lines, "model", model);
  if (!getTopLevelString(lines, "model_provider")) ensureTopLevelString(lines, "model_provider", providerId);
  updateExistingExperimentalToken(lines);

  const sectionName = `model_providers.${tomlKeySegment(providerId)}`;
  const section = findSection(lines, sectionName, providerId);
  if (!section) {
    if (lines.length && lines[lines.length - 1].trim() !== "") lines.push("");
    lines.push(`[${sectionName}]`, `name = ${tomlString(providerId)}`, `base_url = ${tomlString(baseUrl)}`, 'env_key = "OPENAI_API_KEY"', 'wire_api = "responses"');
  } else {
    let baseLine = -1;
    for (let i = section.start + 1; i < section.end; i += 1) {
      if (keyOf(lines[i]) === "base_url") {
        baseLine = i;
        break;
      }
    }
    if (baseLine >= 0) {
      lines[baseLine] = replaceAssignment(lines[baseLine], baseUrl);
    } else {
      lines.splice(section.start + 1, 0, `base_url = ${tomlString(baseUrl)}`);
    }
  }
  ensureFeatureGoals(lines);
  return `${lines.join("\n")}\n`;
}

try {
  let auth = {};
  if (fs.existsSync(authFile)) {
    const rawAuth = fs.readFileSync(authFile, "utf8");
    auth = rawAuth.trim() ? JSON.parse(rawAuth) : {};
    if (!auth || typeof auth !== "object" || Array.isArray(auth)) throw new Error("auth.json 必须是 JSON 对象");
  }
  auth.OPENAI_API_KEY = apiKey;

  const rawConfig = fs.existsSync(configFile) ? fs.readFileSync(configFile, "utf8") : "";
  const nextConfig = updateToml(rawConfig);
  fs.mkdirSync(path.dirname(authFile), { recursive: true });
  fs.writeFileSync(authFile, `${JSON.stringify(auth, null, 2)}\n`);
  fs.writeFileSync(configFile, nextConfig);
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
    chmod 600 "${auth_file}" "${config_file}" 2>/dev/null
    echo -e "${green}Codex 配置已写入: ${auth_file} / ${config_file}${background}"
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
        echo -en "${yellow}检测到已存在 Codex 配置，将更新 auth.json，并修改 config.toml 中的 model/base_url 等字段；其他配置会尽量保留。是否继续？[y/N]: ${background}"
        read -r overwrite
        if [[ "${overwrite}" != "y" && "${overwrite}" != "Y" ]]; then
            echo -e "${yellow}已取消配置。${background}"
            return
        fi
        if [ -f "${auth_file}" ]; then
            auth_backup_file="${auth_file}.bak"
            cp -a "${auth_file}" "${auth_backup_file}"
            echo -e "${green}已备份原配置到: ${auth_backup_file}${background}"
        fi
        if [ -f "${config_file}" ]; then
            config_backup_file="${config_file}.bak"
            cp -a "${config_file}" "${config_backup_file}"
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
  fs.writeFileSync(configFile, nextConfig);
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
  fs.writeFileSync(storeFile, `${JSON.stringify(store, null, 2)}\n`);
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

    echo -en "${cyan}请输入 OPENAI_API_KEY（已隐藏输入，默认留空）: ${background}"
    read -rs api_key
    echo
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
  fs.writeFileSync(storeFile, `${JSON.stringify(store, null, 2)}\n`);
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

hapi_switch_codex_profile() {
    local store_file config_dir auth_file config_file backup_file num confirm
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

    mkdir -p "${config_dir}"
    if [ -f "${auth_file}" ]; then
        backup_file="${auth_file}.bak"
        cp -a "${auth_file}" "${backup_file}"
        echo -e "${green}已备份原配置到: ${backup_file}${background}"
    fi
    if [ -f "${config_file}" ]; then
        backup_file="${config_file}.bak"
        cp -a "${config_file}" "${backup_file}"
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
  fs.writeFileSync(authFile, `${JSON.stringify(auth, null, 2)}\n`);
  fs.writeFileSync(configFile, config.endsWith("\n") ? config : `${config}\n`);
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
  fs.writeFileSync(storeFile, `${JSON.stringify(store, null, 2)}\n`);
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
    local workspace_root

    hapi_ensure_command || return
    echo -e "${yellow}提示1：Hapi runner 是全局单实例，新设置会覆盖当前 runner 的 workspace-root。${background}"
    echo -e "${yellow}提示2：Hapi runner 用于从聊天窗口远程创建 session。如果不启动 Runner，你仍然可以管理已有 session，但不能方便地让 HAPI 在指定机器上新建任务。${background}"
    hapi_select_workspaces || return

    for workspace_root in "${HAPI_SELECTED_WORKSPACES[@]}"; do
        runner_args+=(--workspace-root "${workspace_root}")
    done

    echo -e "${yellow}正在设置/运行 Hapi 工作目录:${background}"
    printf '  - %s\n' "${HAPI_SELECTED_WORKSPACES[@]}"
    hapi runner start "${runner_args[@]}"
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
    if [[ "${HAPI_HUB_URL}" == *"token=" ]]; then
        cli_token=$(hapi_read_setting "cliApiToken" "")
        if [ -n "${cli_token}" ]; then
            HAPI_HUB_URL="${HAPI_HUB_URL}${cli_token}"
        fi
    fi
    [ -n "${HAPI_HUB_URL}" ]
}

hapi_show_hub_url() {
    if hapi_capture_hub_url; then
        echo -e "${red}重要：以下 URL 包含访问 token，不要发送给其他人！${background}"
        echo -e "${red}${HAPI_HUB_URL}${background}"
    else
        echo -e "${yellow}暂未提取到 Hapi Hub URL，请稍后重试或查看 tmux 日志。${background}"
        return 1
    fi
}

hapi_start_hub() {
    hapi_ensure_command || return
    hapi_ensure_tmux || return

    if tmux has-session -t "${HAPI_HUB_TMUX_NAME}" 2>/dev/null; then
        echo -e "${green}Hapi Hub 已在后台运行。${background}"
        if hapi_show_hub_url; then
            return
        fi
        echo -e "${yellow}现有 Hapi Hub 未提取到 URL，准备重启后重试。${background}"
        tmux kill-session -t "${HAPI_HUB_TMUX_NAME}" >/dev/null 2>&1
    fi

    local attempt wait_count
    attempt=1
    while [ "${attempt}" -le 3 ]; do
        echo -e "${yellow}正在启动 Hapi Hub (第 ${attempt}/3 次)...${background}"
        tmux kill-session -t "${HAPI_HUB_TMUX_NAME}" >/dev/null 2>&1
        if ! tmux new-session -d -s "${HAPI_HUB_TMUX_NAME}" "export PATH=\"${PATH}\"; export PNPM_HOME=\"${PNPM_HOME}\"; hapi hub --relay"; then
            echo -e "${red}Hapi Hub tmux 会话创建失败。${background}"
            return 1
        fi

        wait_count=0
        while [ "${wait_count}" -lt 20 ]; do
            sleep 1
            if hapi_capture_hub_url; then
                hapi_show_hub_url
                echo -e "${green}Hapi Hub 已在 tmux 会话 ${HAPI_HUB_TMUX_NAME} 中后台运行。${background}"
                return 0
            fi
            wait_count=$((wait_count + 1))
        done

        echo -e "${yellow}本次未提取到 Hapi Hub URL，正在重启重试...${background}"
        tmux kill-session -t "${HAPI_HUB_TMUX_NAME}" >/dev/null 2>&1
        attempt=$((attempt + 1))
    done

    echo -e "${red}连续 3 次未提取到 Hapi Hub URL，请稍后重新选择"启动/查看 Hapi hub URL"或检查 tmux 日志。${background}"
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
        echo -e "${green}已备份原配置到: ${backup_file}${background}"
    fi
    if ! node -e 'const fs = require("fs"); const path = require("path"); const file = process.argv[1]; const token = process.argv[2]; let data = {}; if (fs.existsSync(file)) { try { data = JSON.parse(fs.readFileSync(file, "utf8")); } catch {} } data.cliApiToken = token; fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, JSON.stringify(data, null, 2) + "\n");' "${settings_file}" "${token}"; then
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

    echo -e "${white}=====${green}AstrBot 插件配置${white}=====${background}"
    echo -e "${yellow}当前 Hapi listenHost: ${listen_host}${background}"
    echo -e "${yellow}当前 Hapi listenPort: ${listen_port}${background}"
    echo -e "${green}在 AstrBot 管理面板的插件配置页填写以下必填字段:${background}"
    echo -e "${cyan}hapi_endpoint:${background}"
    echo -e "  同一宿主机（非 Docker）: http://localhost:${listen_port}"
    echo -e "  AstrBot/TRSS Docker（Linux 宿主机默认）: http://172.17.0.1:${listen_port}"
    echo -e "  AstrBot/TRSS Docker（Windows/macOS 宿主机）: http://host.docker.internal:${listen_port}"
    echo -e "  同一内网 / Tailscale: http://<HAPI机器IP>:${listen_port}"
    echo -e "  公共中继 / 自建隧道: 使用 Hub URL 或你的域名"
    echo -e "${cyan}access_token:${background}"
    if [ -n "${token}" ]; then
        echo -e "  ${red}${token}${background}"
    else
        echo -e "  ${yellow}未读取到 cliApiToken，请先启动 Hapi Hub 生成 ~/.hapi/settings.json。${background}"
    fi

    echo -e "${yellow}如果 AstrBot 是 Docker 启动，本脚本所在 Linux 宿主机通常填写: http://172.17.0.1:${listen_port}${background}"
    echo -e "${yellow}Docker 场景必须先让 Hapi 监听所有网卡，即 listenHost -> 0.0.0.0。${background}"
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
    hapi_ensure_command || return
    hapi_ensure_tmux || return

    if tmux has-session -t "${HAPI_HUB_TMUX_NAME}" 2>/dev/null; then
        tmux kill-session -t "${HAPI_HUB_TMUX_NAME}" >/dev/null 2>&1
        echo -e "${green}已停止现有 Hapi Hub tmux 会话。${background}"
    else
        echo -e "${yellow}未检测到正在运行的 Hapi Hub tmux 会话，将直接启动。${background}"
    fi
    hapi_start_hub
}

hapi_hub_menu() {
    local num

    while true; do
        echo -e "${white}=====${green}Hapi hub${white}=====${background}"
        echo -e "${green}1.  ${cyan}启动/查看 Hapi hub URL${background}"
        echo -e "${green}2.  ${cyan}重启 Hapi hub${background}"
        echo -e "${green}3.  ${cyan}打开当前的 tmux${background}"
        echo -e "${green}0.  ${cyan}返回上一级${background}"
        echo "========================="
        echo -en "${green}请输入您的选项: ${background}"; read -r num

        case "${num}" in
        1) hapi_start_hub; pause ;;
        2) hapi_restart_hub; pause ;;
        3) hapi_attach_tmux; pause ;;
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
    echo -e "${green}3.  ${cyan}卸载 Hapi${background}"
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

    echo -e "${yellow}卸载将移除全局安装的 ${target_label}，不会删除 ~/.codex、~/.claude 或 ~/.hapi 配置目录。${background}"
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
    echo -e "${white}  ${green}Hapi / Claude Code / Codex 管理${background}"
    echo -e "${white}========================================${background}"
    echo -e "${yellow}-- Codex --${background}"
    echo -e "${green}1.  ${cyan}安装/更新 Codex${background}"
    echo -e "${green}2.  ${cyan}配置 Codex${background}"
    echo -e "${white}----------------------------------------${background}"
    echo -e "${yellow}-- Claude Code --${background}"
    echo -e "${green}3.  ${cyan}安装/更新 Claude Code${background}"
    echo -e "${green}4.  ${cyan}配置 Claude Code${background}"
    echo -e "${white}----------------------------------------${background}"
    echo -e "${yellow}-- Hapi --${background}"
    echo -e "${green}5.  ${cyan}安装/更新 Hapi${background}"
    echo -e "${green}6.  ${cyan}设置/运行 Hapi runner 工作目录${background}"
    echo -e "${green}7.  ${cyan}设置 Hapi CLI${background}"
    echo -e "${green}8.  ${cyan}运行 Hapi hub${background}"
    echo -e "${green}9.  ${cyan}停止 Hapi${background}"
    echo -e "${white}----------------------------------------${background}"
    echo -e "${yellow}-- 其他 --${background}"
    echo -e "${green}10. ${cyan}卸载${background}"
    echo -e "${green}0.  ${cyan}退出${background}"
    echo -e "${white}========================================${background}"
    echo -en "${green}请输入您的选项: ${background}"; read -r num

    case "${num}" in
    1) hapi_install_codex; pause; manage_hapi ;;
    2) hapi_codex_config_menu; manage_hapi ;;
    3) hapi_install_claude_code; pause; manage_hapi ;;
    4) hapi_claude_config_menu; manage_hapi ;;
    5) hapi_install_hapi; pause; manage_hapi ;;
    6) hapi_runner_workspace_menu; manage_hapi ;;
    7) hapi_config_menu; manage_hapi ;;
    8) hapi_hub_menu; manage_hapi ;;
    9) hapi_stop_all; pause; manage_hapi ;;
    10) hapi_uninstall; pause; manage_hapi ;;
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

