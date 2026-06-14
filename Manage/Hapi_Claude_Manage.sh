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

hapi_install_claude_code() {
    hapi_ensure_pnpm || return
    echo -e "${yellow}正在安装/更新 Claude Code...${background}"
    pnpm add -g @anthropic-ai/claude-code --allow-build=@anthropic-ai/claude-code
    if command -v claude >/dev/null 2>&1; then
        claude --version
    fi
}

hapi_install_hapi() {
    hapi_ensure_pnpm || return
    echo -e "${yellow}正在安装/更新 Hapi...${background}"
    pnpm add -g @twsxtd/hapi
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

hapi_write_claude_settings_file() {
    local output_file="$1"
    local auth_token base_url haiku_model sonnet_model opus_model enable_max_effort
    local reasoning_suffix effort_line
    local auth_token_json base_url_json haiku_json sonnet_json opus_json
    local default_haiku_model="claude-haiku-4-5-20251001"
    local default_sonnet_model="claude-sonnet-4-5-20250929"
    local default_opus_model="claude-opus-4-8[1M]"

    while [ -z "${auth_token}" ]; do
        echo -en "${cyan}请输入 ANTHROPIC_AUTH_TOKEN（已隐藏输入）: ${background}"
        read -rs auth_token
        echo
        if [ -z "${auth_token}" ]; then
            echo -e "${red}ANTHROPIC_AUTH_TOKEN 不能为空。${background}"
        fi
    done

    echo -en "${cyan}请输入 ANTHROPIC_BASE_URL (默认 https://api.deepseek.com/anthropic): ${background}"
    read -r base_url
    base_url=${base_url:-https://api.deepseek.com/anthropic}

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

    echo -en "${cyan}是否开启最大强度思考？[y/N]: ${background}"
    read -r enable_max_effort
    reasoning_suffix=""
    effort_line=""
    if [[ "${enable_max_effort}" == "y" || "${enable_max_effort}" == "Y" ]]; then
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

    mkdir -p "${config_dir}"
    hapi_write_claude_settings_file "${settings_file}" || return
    chmod 600 "${settings_file}"
    echo -e "${green}Claude Code 配置已写入: ${settings_file}${background}"
}

hapi_ensure_node_json() {
    if ! command -v node >/dev/null 2>&1; then
        echo -e "${red}未检测到 node，无法管理 Claude 配置库。${background}"
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
    echo -e "${white}=====${green}Hapi / Claude Code 版本${white}=====${background}"
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
    echo -e "${green}1.  ${cyan}卸载 Claude Code${background}"
    echo -e "${green}2.  ${cyan}卸载 Hapi${background}"
    echo -e "${green}3.  ${cyan}卸载 Claude Code 和 Hapi${background}"
    echo -e "${green}0.  ${cyan}取消${background}"
    echo "========================="
    echo -en "${green}请输入您的选项: ${background}"; read -r num

    case "${num}" in
    1)
        target_label="Claude Code"
        uninstall_packages=("@anthropic-ai/claude-code")
        stop_hapi="false"
        ;;
    2)
        target_label="Hapi"
        uninstall_packages=("@twsxtd/hapi")
        stop_hapi="true"
        ;;
    3)
        target_label="Claude Code 和 Hapi"
        uninstall_packages=("@anthropic-ai/claude-code" "@twsxtd/hapi")
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

    echo -e "${yellow}卸载将移除全局安装的 ${target_label}，不会删除 ~/.claude 或 ~/.hapi 配置目录。${background}"
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
    echo -e "${white}=====${green}Hapi / Claude Code 管理${white}=====${background}"
    echo -e "${green}1.  ${cyan}安装/更新 Claude Code${background}"
    echo -e "${green}2.  ${cyan}配置 Claude Code${background}"
    echo -e "${green}3.  ${cyan}安装/更新 Hapi${background}"
    echo -e "${green}4.  ${cyan}设置/运行 Hapi runner 工作目录${background}"
    echo -e "${green}5.  ${cyan}设置 Hapi CLI${background}"
    echo -e "${green}6.  ${cyan}运行 Hapi hub${background}"
    echo -e "${green}7.  ${cyan}停止 Hapi${background}"
    echo -e "${green}8.  ${cyan}卸载${background}"
    echo -e "${green}0.  ${cyan}退出${background}"
    echo "========================="
    echo -en "${green}请输入您的选项: ${background}"; read -r num

    case "${num}" in
    1) hapi_install_claude_code; pause; manage_hapi ;;
    2) hapi_claude_config_menu; manage_hapi ;;
    3) hapi_install_hapi; pause; manage_hapi ;;
    4) hapi_runner_workspace_menu; manage_hapi ;;
    5) hapi_config_menu; manage_hapi ;;
    6) hapi_hub_menu; manage_hapi ;;
    7) hapi_stop_all; pause; manage_hapi ;;
    8) hapi_uninstall; pause; manage_hapi ;;
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

