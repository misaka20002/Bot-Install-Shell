# `Manage/Hapi_Claude_Manage.sh` 专属约定

> 本文件是 `AGENTS.md` 的细节分册。失败路径、镜像源、编辑与 EOL 等通用规则仍在 `AGENTS.md`「通用 Bash 约定」。

管理 Hapi / Claude Code / Codex / opencode（入口 `manage_hapi` → `hapi_codex_config_menu` 等）。通用规则同上，这里只记它独有的。

### 参考实现：cc-switch（不在本仓库）

- Codex / Claude 的配置语义一律以本地参考实现为准：`E:\myrepo\参考\cc-switch`（**只在开发机上，不随仓库分发**）。
  引用行为时写清文件名 + 函数名，别写"我记得"。本轮结论对应 `src-tauri/src/codex_config.rs` 的
  `codex_auth_resolved_mode` / `codex_auth_has_openai_account_material` / `CODEX_RESERVED_MODEL_PROVIDER_IDS`，
  以及 `src-tauri/src/config.rs` 的 `atomic_write_private`。
- 审查（人 / 模型）给出的结论**先拿去和参考实现求证**，冲突时以参考代码为准（用户三次强调"审查模型给出的不一定对"）。
  推论：别把自己对某个 helper 的读法当成"被管理程序的生产行为"——helper 的容错 ≠ Codex 真的能加载这个文件。
- 反向教训（2026-09-19，审查方抓到我方引用错误）：文档里曾写「官方 host 判据见 cc-switch
  `src-tauri/src/proxy/providers/codex.rs`」——那个 `Some("api.openai.com") => true` 其实在
  `should_send_codex_chat_prompt_cache_key()` 里，用途是「转成 Chat Completions 后要不要发 `prompt_cache_key`」，
  **不是官方供应商判定**。cc-switch 对 Codex 官方与否的判定靠预设的 `isOfficial` / `category: "official"` /
  空 config，以及 `codex_auth_has_openai_account_material`（按 auth.json 判，不按 host）；
  它只有一个 `is_official_provider()`，在 `claude_desktop_config.rs`（Claude Desktop 用的）。
  **引用前先打开函数读完上下文**，别只 grep 到一行相似的代码就当成结论。

### Codex `auth.json` 语义

- **模式优先级**（脚本里的 `resolveAuthMode`，对齐 `codex_auth_resolved_mode`）：`auth_mode` 非 null 时优先
  （**空字符串也算存在**）；否则按 `personal_access_token` → `bedrock_api_key` → `bedrock_access_keys` →
  `OPENAI_API_KEY`（同样"非 null 即算"）判定，最后**回退 `chatgpt`**。
  两条推论都必须满足：
  1. **官方登录态下绝不要把 `OPENAI_API_KEY` 写成 `""`**——空串会把隐式模式抢成 `apikey`，等于毁掉官方登录。
     用户没填 Key 时要"原样不动"（保持 `null`，或让该字段继续缺失）。
  2. **"字段存在"与"凭据可用"是两套规则，不能合并**：模式优先级用"非 null 即存在"；
     凭据可用性用"非空白字符串 / 非空容器"（`credentialIsUsable`，对齐 `value_present`）。
- **两级校验（2026-09-19 起）**：`hapi_check_codex_auth_file <file> [official|loadable]`
  - 两级**共同**的硬错误（= "Codex 能不能加载 + 有没有可用凭据"）：
    JSON 解析失败 / 顶层非对象 / 空文件；`last_refresh` 类型错或**真日历越界**；`auth_mode` 类型错、取值不认识、
    或为 `headers`（Codex 无法从 auth.json 加载该模式）；`tokens.id_token` 不是合法 JWT；
    `account_id` / `OPENAI_API_KEY` 出现但类型不是字符串；**chatgpt 模式下 `tokens` 三个字段
    （`id_token`/`access_token`/`refresh_token`）必须存在且是字符串**（Codex 的 TokenData 里它们都是必需字段，
    缺一个会让整份 auth.json 反序列化失败，只有 `account_id` 是 `Option`）；**非 ChatGPT 模式各自必须有可用凭据**：
    `personal_access_token` / `bedrock_api_key` 非空白字符串，`agent_identity` / `bedrock_access_keys` 非空
    （对象或非空白字符串），`OPENAI_API_KEY`（apikey）非空白字符串。
  - `official`（默认；菜单 7 移除后暂无调用方，保留给「整份官方 auth.json」这类完整校验）额外要求：模式解析为 `chatgpt`/`chatgptAuthTokens`，且三个 token
    **都非空**（缺一个或有一个空串即硬错误）。
  - `loadable`（配置库写入 / 切换用）比 official 宽：chatgpt 模式只要求"至少一个 token 非空"（字段存在与类型仍然查），
    用来堵配置库旁路，同时不误杀 apikey / PAT / Bedrock 配置。
  - 只警告：`tokens.account_id` 缺失、`last_refresh` 缺失、额外字段、loadable 下的空 token 字段、非目标登录模式。
  - **没有"强制写入"逃生口**（2026-09-19 用户明确要求按 Codex 有效登录语义处理）。
  - ⚠️ 教训：曾经 loadable 只在 chatgpt 的 `.some()` 与 apikey 分支真正阻断，PAT / agentIdentity / Bedrock / headers
    仅 `warnings.push()`，于是 `{"auth_mode":"personalAccessToken","personal_access_token":""}` 这类"没凭据"的文件
    也能通过 loadable（2026-09-19 被审查抓到）。**新增模式分支时必须同时接上凭据检查**。
- **`last_refresh` 必须做真 RFC3339（格式 + 日历 / 时钟 / 时区范围）**：只写正则会放行 `2026-99-99T99:99:99Z`（实测确认）。
  实测边界：`2028-02-29` 合法、`2026-02-29` 非法（非闰年）、`+23:59` 合法、`+99:99` 与 `24:00` 非法、`:60` 按 RFC3339 闰秒放行。
- **`tokens.id_token` 按 Codex 的 JWT envelope 严格要求**：恰好三段、**三段都非空**、每段都必须是严格
  `base64url-no-pad`、header / payload 反序列化后必须是 plain object（数组不算）。
  ⚠️ Node 的 base64 解码很宽容（会忽略 `$` 这类非法字符、容忍缺填充），所以必须做「字符集 + 长度 + 往返编码一致」校验。
  实测被拦下的例子：`.e30.`、`a.e30$.b`、payload 为 `[]`、只有两段、带 `=` 填充、标准 base64 的 `+`/`/`。
  不校验签名（Codex 自己也只是解 envelope 与 claims）；header 缺 `alg` 只警告（cc-switch 提取账号身份需要它）。
- **配置库不是旁路**：菜单 2（储存当前配置）与菜单 4（切换配置）都先跑 `loadable` 级校验，
  不通过就中止且**不改动 `~/.codex`**；菜单 3（新建配置）要求 `OPENAI_API_KEY` 非空
  （空 Key 会写出 `{OPENAI_API_KEY: ""}`，隐式模式被判成 apikey 却没有凭据）。
- **config.toml 路由**：
  - `model_provider` 缺省 = **内置 openai provider**（官方登录的正常状态）；此时不要凭空写 `model_provider` / `[model_providers.*]`。
  - **保留 id 不得建表**：`amazon-bedrock` / `amazon-bedrock-runtime` / `openai` / `ollama` / `lmstudio`
    （`CODEX_RESERVED_MODEL_PROVIDER_IDS`）。给它们写 `[model_providers.<id>]` 会让 **Codex 拒绝加载整份 config.toml**
    （`validate_reserved_model_provider_ids`，大小写敏感）。
  - 空 Key 不得清空已有的 `experimental_bearer_token`（只有确实填了新 Key 才覆盖）。
  - **路由自动收敛（2026-09-19 加）**：写入器（`hapi_write_codex_current_config`）与
    `hapi_sync_codex_route` 会按 `auth.json` 模式 + `base_url` 自动决定路由目标：
    - **official**：剥离顶层 `model_provider`、它指向的 `[model_providers.<id>]` 整段、以及顶层
      `experimental_bearer_token`，并把原文存进 `~/.codex/hapi_provider_route.json`（`0600`，单槽）；
    - **third-party**：填第三方 `base_url` 时按暂存原文恢复路由（provider id 与段内其它字段一起回来），
      `base_url` 用本次输入覆盖；
    - **keep**：保留 id、PAT/agentIdentity/Bedrock/未识别模式、`base_url` 解析不出 host —— 一律不动路由（只提示）。
    ⚠️ 官方 host 判据（host **精确等于** `api.openai.com`）是**脚本自己加的保守规则**，不是抄自 cc-switch 的判定函数
    （见上文「反向教训」）。`https://api.openai.com.evil.com/v1` 必须判成第三方（I9 已覆盖）。
    - **暂存文件损坏必须 fail-closed**：`readStash()` 分 `missing` / `valid` / `invalid` 三态；
      `invalid` 时**中止写入**（rc=1，auth.json 与 config.toml 都不动），绝不静默降级成 generic custom——
      那会把原 provider 的 `query_params` / `requires_openai_auth` 等字段无声丢掉。
      官方方向的剥离照常进行（用新内容覆盖坏文件），但要打印「原暂存文件已损坏并被覆盖」的警告。
    `route-only` 形参（`hapi_sync_codex_route` 用）**只剥离不恢复**，且只有内容真变了才写回：
    恢复/新建路由必须由用户在菜单 1 显式填 `base_url` 触发，避免切换配置时凭空造出没凭据的路由。
    - ⚠️ **空配置 / 不存在的 `config.toml` 必须走同一条路由流程**，不许在 `readStash()` 之前 `process.exit`：
      「只写了第三方路由的配置被官方剥离」会把文件变成空文件（只剩一个换行）——**这是脚本自己会造出来的状态**。
      空配置一旦提前返回，下次填第三方 `base_url` 就会绕过暂存、静默建成 generic custom
      （原 provider 的 id / `query_params` / `requires_openai_auth` 全丢）。现已统一：`lines = []` 后继续走
      `decideCodexRoute` → `readStash()` 三态（invalid 仍 fail-closed）。I13 用端到端现场钉住它。
      附带后果（有意）：空配置不再用 `createTemplate` 生成整份文件，于是新建的 generic 段里
      `name = "custom"`（旧模板是 `"Custom"`），且「脚本判断不了的模式 + 空配置」不再凭空建模板段。
    - ⚠️ `hapi_show_codex_config` 里的 `stashProblem()` 是 `readStash()` 的**第二份规则**，
      增删规则必须两边同步（漏同步会让预览显示"正常"，而写入侧其实 fail-closed 拒绝恢复）。I14 钉住三条规则。
    ⚠️ 判定细节与依据写在 `tests/Hapi_Claude_Manage/路由自动收敛-测试文档.md`，改判定前先读它；
    特别是：**`apikey` 模式不能用「auth.json 有官方凭据」这条捷径**（中转 key + 中转路由会被误判成官方登录而剥掉）。

### Codex 取 key / 路由 / 1M 上下文窗口 → `docs/Codex-凭据与上下文窗口-实现约定.md`

改 `Manage/Hapi_Claude_Manage.sh` 里**凭据、`model_provider` 路由、`model_context_window`** 任一处之前，
先读那份文件（`env_key` 为什么不能用、第三方 Key 写哪里、auth.json 何时暂存/移除、1M 开关的删除语义、
以及对应的 D/I/L 测试组）。底线一句：第三方 provider 的 Key 只写在
`[model_providers.<id>].experimental_bearer_token` + `requires_openai_auth = false`；
`env_key` 只从进程环境变量取值，auth.json 不参与——这就是 `Missing environment variable` 的根因。

### Claude Code `settings.json` 语义

写盘只有一个入口：`hapi_write_claude_settings_file`（2026-09-23 重写）。

- **合并写盘，不是整文件重建**：读取现有 JSON → **保留所有未知顶层键**（`permissions` / `hooks` / `statusLine` /
  `enabledPlugins` …）→ 合并 `env` → 删除废弃/冲突键 → `JSON.stringify` 输出。
  旧版用 bash heredoc 重建整个文件，等于把用户的其它顶层配置整份丢掉（实测：`customTopLevel` 之类在 live 与 `.bak` 里同时消失）。
- **JSON 交给 node 生成，不要再用 bash heredoc 拼 JSON**：`hapi_json_escape` 只转义 `\` 与 `"`，
  token 里出现 TAB / 换行就会写出非法 JSON（实测 `JSON.parse` 直接失败；引号/反斜杠/`$`/反引号反而没事，别被这种正向用例误导）。
- 字段集合（依据 cc-switch `src-tauri/src/services/proxy.rs` 的 `CLAUDE_MODEL_OVERRIDE_ENV_KEYS` /
  `build_claude_takeover_model_fields`，与 `src/components/providers/forms/ClaudeFormFields.tsx` 的角色行）：
  - 四档角色 `ANTHROPIC_DEFAULT_{HAIKU,SONNET,OPUS,FABLE}_MODEL` **各自配一个 `*_MODEL_NAME` 显示名**
    （缺显示名会让 `/model` 菜单残留上一家供应商的名字——cc-switch 接管时必须同步写它，注释写明了原因）。
  - `ANTHROPIC_MODEL` = **兜底模型**（承接未落到角色档的请求，含 Claude Code 的 Haiku 后台子任务；
    中转端点不填会让这些请求带着原始 Claude 模型名透传而报错）。本脚本让它与 Sonnet 档**同串**，**包含 `[1M]` 声明**。
  - `[1M]` 只加在 `*_MODEL` 上，`*_MODEL_NAME` 一律剥掉；剥离只认**尾部**后缀且大小写不敏感。
    旧写法 `${model%%\[*}` 截到第一个 `[`，`a[b]c[1M]` 会被截成 `a`（错的）。
  - 认证键只留目标那一个（`ANTHROPIC_AUTH_TOKEN`）；`ANTHROPIC_API_KEY` / `OPENROUTER_API_KEY` / `OPENAI_API_KEY`
    必须删掉——同时存在会触发 Claude Code 的 "Both ANTHROPIC_AUTH_TOKEN and ANTHROPIC_API_KEY set"（cc-switch `proxy.rs` 注释 #4919）。
  - `ANTHROPIC_REASONING_MODEL` / `ANTHROPIC_SMALL_FAST_MODEL` 是 **legacy 已废弃**（cc-switch 只在清理/剥离列表里保留，
    v3.14.0 起从 Quick-Set 移除并清理旧值）——不要再写。
  - **不写「固定补齐项」**（2026-09-23 曾加过一版，同日整块撤销）：`CLAUDE_CODE_ATTRIBUTION_HEADER` /
    `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS` / `ANTHROPIC_SMALL_MODEL` / `CLAUDE_CODE_SUBAGENT_MODEL` /
    `*_SUPPORTED_CAPABILITIES` / 顶层 `hasCompletedOnboarding` 都**不由写盘器注入**。
    前两个仍留在可选的「Claude Code 额外参数」清单里（用户显式选 `y` 才写），这是它们原本的归属。
  - ⚠️ **`*_SUPPORTED_CAPABILITIES` 是 Claude Code 官方字段，但显式设置会禁用未列出的能力**——
    官方只接受：`effort` / `xhigh_effort` / `max_effort` / `thinking` / `adaptive_thinking` / `interleaved_thinking`。
    2026-09-23 采纳那版写了清单里不存在的 `temperature`，又漏了 `xhigh_effort` 与 `interleaved_thinking`，
    等于主动砍能力，因此整块撤销。而且**不能四档塞同一组**：官方列出的 effort 支持模型里有 Fable 5 / Opus 4.8，
    **没有 Sonnet 4.5 / Haiku 4.5**，官方另说这两个模型会拒绝 effort 参数。
    结论：标准 `claude-*` 模型 ID **一律不写**这个键——不设置时 Claude Code 按模型 ID 内建识别；
    该覆盖字段是给 Bedrock ARN / 自定义 deployment name 这类 Claude Code 认不出的 provider-specific ID 用的。
  - ⚠️ **`CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1` 是网关兼容开关，不是性能参数**：它会剥掉 beta header /
    beta tool schema，并且**禁用 MCP tool search（所有 MCP 工具改成 upfront load）**。cc-switch 只把它用在
    「平台明确要求禁用全部 beta 参数」的网关（`claudeProviderPresets.ts:960/968/980` 及 968 行注释）。
    所以**不做全局固定项**，只留在可选清单里（谁勾谁负责）。
    2026-09-23 我先写过「它会让 `[1m]` 失效」——那是**未经验证的猜测，已撤回**：能确定的是剥 beta 请求内容 +
    关 MCP tool search；`[1m]` 本身是 Claude Code 官方的模型后缀机制。
  - **预览（`hapi_show_claude_config`）自 2026-10-19 起改为明文**：用户明确要求「Key 要能直接看到，
    否则无法判断到底填进去了吗」。所以「查看配置」类入口（Claude live / Claude 配置库 / Codex live /
    Codex 配置库）**不再脱敏**；这是有意决定，不是回退。
    - 仍然打码的只有**校验/诊断输出**（`hapi_check_codex_auth_file`，一份 `isSensitiveKey` 副本）：
      它会进日志、会被贴进聊天窗口。判据：`api_key` / `apikey` / `token` / `secret` / `password` /
      `experimental_bearer_token`。
    - 旧的「先预览、后清理」问题不复存在（预览就是看明文），但**JSON 解析失败时仍然不回退打原文**。
    - ⚠️ 改回打码前先看 G 组：那里用「预览里不得出现 `******`」与「必须出现明文 Key」两组断言钉住了这个决定。
  - `hasCompletedOnboarding` **写 `~/.claude.json`，不是 `settings.json`**：由 `hapi_ensure_claude_onboarding` 负责，
    菜单 1（配置）与菜单 4（切换）写完 live settings 后各调一次，失败只打警告、不影响已写好的 settings.json。
    依据 cc-switch `src-tauri/src/claude_mcp.rs:148-173` `set_has_completed_onboarding`
    （注释原文「在 ~/.claude.json 根对象写入 hasCompletedOnboarding=true」「仅增量写入该字段，其他字段保持不变」）
    + `commands/plugin.rs:38-42` + 设置开关 `skipClaudeOnboarding`（`src/types.ts:368`）。逐条对齐：
    文件不存在按 `{}` 起手；根不是对象则报错；**已经是 true 就直接不碰文件**（幂等）；只加这一个键，
    **绝不重建 `.claude.json`**（里面还有项目历史 / `mcpServers` 等用户状态）；坏 JSON fail-closed。
    与 cc-switch 的唯一偏差：本脚本按仓库约定把该文件收紧到 **0600**（cc-switch 用普通 `atomic_write`）——
    `mcpServers[].env` 里可能带密钥。
    ⚠️ **参考实现自身文档与代码不一致（2026-09-23 复核）**：cc-switch v3.20.4 的**代码**走
    `~/.claude.json.hasCompletedOnboarding`（上面引的三个文件都是活的：设置开关 + 两条 Tauri 命令），
    但它的**用户手册**写的是「此选项会写入 `~/.claude/settings.json` 的 `skipIntroduction` 字段」
    （`docs/user-manual/zh/1-getting-started/1.4-quickstart.md:51`、`1.5-settings.md:80`，en/ja 同）。
    按仓库约定「冲突时以参考代码为准」，保留 `.claude.json` 那条；**`skipIntroduction` 未采纳**——
    它只出现在文档、代码里一次都没有，要写必须先确认真机认这个字段。
  - ⚠️ **`ANTHROPIC_SMALL_MODEL` 没有官方依据**：官方 model-config 文档只列 `ANTHROPIC_DEFAULT_HAIKU_MODEL`
    与 `CLAUDE_CODE_SUBAGENT_MODEL`，并明确 `ANTHROPIC_SMALL_FAST_MODEL` 已废弃改用
    `ANTHROPIC_DEFAULT_HAIKU_MODEL`。所以既不写 `ANTHROPIC_SMALL_MODEL`，也不把 legacy 名加回来；
    小模型档由 `ANTHROPIC_DEFAULT_HAIKU_MODEL` 承担（`CLAUDE_CODE_SUBAGENT_MODEL` 是正式字段，带 subagent 的场景可留）。
  - ⚠️ **`CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1`** 在 cc-switch 里用于「平台明确要求禁用全部 beta 参数」的网关
    （`claudeProviderPresets.ts:960/968/980` 及 968 行注释）。它与 `[1m]` 声明的 1M beta 头可能互斥——
    留在可选清单里，谁勾谁自己确认真机是否还有 1M。
  - 署名：**不再写 `includeCoAuthoredBy`**（旧写法，用户既有值原样保留，别再自动加/改）；
    「隐藏 AI 署名」开关写 `attribution = {commit:"", pr:"", sessionUrl:false}`（v3.20.4 起只清 commit/pr
    藏不住 claude.ai 会话链接），取消勾选 = 删掉整个 `attribution` 对象（会先提示「已有 attribution」）。
  - 「最大强度思考」的落点是 `env.CLAUDE_CODE_EFFORT_LEVEL = "max"`；关闭必须**显式删除该键**，不能留空串。
- **备份固定一份、每次覆盖，不按时间戳堆积**（2026-09-23 按用户明确要求收敛）：
  备份名一律是 `<原文件>.bak`（`~/.claude/settings.json.bak` / `~/.codex/auth.json.bak` /
  `~/.codex/config.toml.bak` / `~/.hapi/settings.json.bak`），由 `hapi_backup_or_fail` 覆盖写入。
  语义 = **「最近一次写入前」的状态**（随时能回退最近一步）。
  ⚠️ **不要再改回「唯一名」**：`mktemp "${settings_file}.bak.$(date +%Y%m%d_%H%M%S).XXXXXX"` 会**无限堆积**
  （每写一次多一个文件，用户得手工清理）。历史上为了「同一秒连跑两次不互相覆盖」加过唯一名，
  2026-09-23 被用户要求撤销——**两者不可兼得**：要不堆积，就得接受 `.bak` 被后续操作覆盖。
  想保留有限几代，必须由脚本自己轮转删除旧文件（**当前没做**，要做先跟用户确认删除策略与保留代数）。
  J2/J11 两条断言就是盯这件事：文件数为 1、且**没有** `settings.json.bak.<时间戳>` 这类残留。
- **备份 `cp` 失败必须立即中止，且统一走 `hapi_backup_or_fail`**（2026-09-23 起）：
  helper = `if ! cp -a "${source}" "${target}"; then 报「备份失败，已中止修改」; return 1; fi` + `chmod 600 "${target}"`；
  调用侧一律 `hapi_backup_or_fail <源> <目标> || return 1`。桩成 `cp(){ return 42; }` 的旧行为实测是
  **备份 0 个、却打印两条「已备份」、live auth/config 都已被覆盖、外层 rc=0** —— 正好击穿这条流程最重要的恢复保障（P1）。
  ⚠️ **不要再逐点复制 `if ! cp -a …`**：这条规则原本散在 12 处，2026-09-23 只修了 Claude 的两处、
  Codex 侧仍是旧写法，于是**同一个 P1 在 Codex 又活了一轮**（审查环境发现）。现在全部 12 处走 helper，
  `tests/Hapi_Claude_Manage/run.sh` 的 **G 组会扫源码**：helper 结构不对、或脚本里还残留裸 `cp -a`，直接红。
  菜单 7 移除后，「把 live 读进临时文件供编辑」这条非备份的 copy 也一并消失；现存所有 copy 都是备份，
  都必须走 helper。
  `hapi_prompt_add_extra_env` 是纯合并 helper，**内部禁止再备份**：历史上它用同一个 `settings.json.bak` 又备份一次，
  把原始备份覆盖成了刚写好的新配置 → 用户在「是否添加额外参数」选 `y` 时「live + 唯一 .bak」同时丢掉原配置
  （2026-09-23 用变异体实测复现：目录里只剩 `settings.json` + 内容已是新配置的 `settings.json.bak`）。
- **现有文件不是合法 JSON 时 fail-closed**：报错中止、不覆盖（别把用户手写但语法有问题的配置整份吃掉）。
  推论：**坏文件目前无法从菜单修**（预览只报错、写入器拒写）——这是有意为之的安全取舍；
  若将来要支持「整份重建」，必须单加一个显式确认，不能顺手放宽 fail-closed。
- **两处 Node 写盘的 `env` 判断必须一致**：`typeof [] === "object"`，只判 `typeof config.env !== "object"`
  会让 `{"env": []}` 变成「rc=0 但一个参数都没落盘」的静默失败。两处都要
  `!config.env || typeof config.env !== "object" || Array.isArray(config.env)`（2026-09-23 在 extra-env helper 修上）。
- **`hapi_prompt_add_extra_env` 的失败码必须 `|| return` 传播**（菜单 1 与菜单 4 两处）：它原本是函数体最后一句、
  失败自然冒泡；后来在它后面接了没有 `|| return` 的 onboarding 调用，失败码被那句 `echo` 擦成 0，
  外层函数于是报成功（P2 控制流回归，2026-09-23 审查环境用桩实跑证实：桩返回 7 时外层 rc=0）。
  规则：**在任何函数末尾追加"尽力而为"的步骤前，先确认前一步的失败码是否会被吃掉**。

### Claude 配置库（`~/.claude/hapi_config_profiles.json`）

- **预览必须与 live 预览同一套递归脱敏**（`hapi_show_claude_profile_by_index`）：菜单 4（切换）与菜单 5（删除）
  都是**先展示 profile、再 ask 确认**，所以这里泄漏的凭据一定会打到终端。旧实现只手工打码三个固定键，
  `OPENROUTER_API_KEY` / `OPENAI_API_KEY` / 任意 `*_SECRET` / `*_PASSWORD` / 嵌套与数组内的敏感键全部明文（P1）。
- **配置库损坏必须 fail-closed**（`hapi_save_claude_profile_from_file`）：旧实现 `try { … } catch {}` 把坏库当空库读，
  紧接着 `writeFileSync` 用「只有新 profile」的 `{profiles:[new]}` 覆盖整个旧库 → 截断/手改/异常写盘之后，
  下一次「储存当前配置」**静默吃掉全部历史配置**（P1 数据丢失，2026-09-23 实跑复现：rc=0、旧库被整份替换）。
  规则：读配置库**一律不许 `catch {}`**；解析失败 → 报错 + `exit 1`，顶层不是对象同样中止。
- **「损坏」包含 schema 级，不只是语法级**（2026-09-23 补）：`profiles` 不是数组也算损坏。
  旧写法 `if (!Array.isArray(store.profiles)) store.profiles = [];` 会把
  `{"profiles":{"legacy":{…}}}`（合法 JSON、顶层也是对象）**静默重置成空库**再写入新 profile，照样丢历史配置。
  正确写法：`profiles === undefined` 才补 `[]`，`!Array.isArray` 一律 `exit 1`；列表侧对应 `exit 2` + 明确报损坏。
- **写 live 的每个入口都要 plain-object 校验**（2026-09-23 补，P2）：`isPlainObject(v) = v!==null && typeof v==="object" && !Array.isArray(v)`。
  四处都要：writer 读旧 `settings.json`、`extra-env` 读 `settings.json`、profile save 的 `sourceFile`、profile switch 的 `profile.config`。
  空文件按 `{}` 处理，但非空的 `[]` / `null` / `"foo"` / `123` 一律 fail-closed。
  两个具体症状：① writer 会 `rc=0` 把 `[]` 重建成 `{}`；② 给数组设 `config.env` 运行时成立、但
  `JSON.stringify(array)` 不序列化命名属性 → 「rc=0、提示已添加、文件一个字节没变」。
- **「损坏」与「空库」必须区分**：`hapi_list_claude_profiles` 损坏时返回退出码 **2**，调用方据此打
  「配置库已损坏 + 请修复或删除」而不是「暂无已储存的配置」——后者会让用户以为「没配过」而不是「库坏了」。
- 输入一律 `hapi_trim` 后再判空：只敲空格的 `base_url` 要落回默认值，模型名两侧空格不能进 JSON。
- 交互值用 **NUL 分隔的临时文件**传给 node（`HAPI_CLAUDE_VALUES_TMP`，已挂 `hapi_install_sensitive_tmp_traps`）：
  bash 变量不可能含 NUL，故 TAB/换行可无损传递；**不要走环境变量或 argv**（会出现在 `/proc/<pid>/environ` / `ps`）。
  它的保密级别与既有 `HAPI_CODEX_AUTH_TMP` / `HAPI_CLAUDE_SETTINGS_TMP` 相同：**SIGKILL / 断电无法拦截**，
  极端情况下会留下含 token 的 `hapi_claude_values.*`（实测：宿主强杀进程树后残留 2 个）。
  想彻底消除，可改用 `node 9< <(printf '%s\0' …)` + `/dev/fd/9`（管道不进磁盘）——**尚未实测，别照抄**。
- 验证（2026-09-23 实测，均在「撤销固定补齐项」之后重跑）：
  - `bash -n Manage/Hapi_Claude_Manage.sh`；
  - ⚠️ **既有套件 A~I 不覆盖 Claude 写入器**（全是 Codex / 通用约定），改动后另做针对性回归：
    按内容锚点从脚本抽出**真实函数**建 harness（`HOME`/`TMPDIR` 指临时目录），`printf` 顺序喂 `read`。
    实测：全新文件 + 既有文件合并 **53 条全绿**（字段集合 11 键、`[1M]` 只加在 `*_MODEL`、
    `includeCoAuthoredBy` / `hasCompletedOnboarding` / `*_SUPPORTED_CAPABILITIES` **都不得出现**、
    未知顶层键保留、legacy 与冲突认证键清理、effort 与 attribution 开关）、
    菜单全流程 **33 条全绿**（含「撤销项不再写入」、单次备份且备份里是原配置、末尾接线到
    `~/.claude.json` 的 onboarding）、
    子集 **20 条全绿**（token 含 TAB 的控制字符 / 坏 JSON fail-closed / trim 与「只剥尾部 `[1M]`」）、
    预览脱敏 **14 条全绿**（escaped-quote token / `OPENROUTER_API_KEY` / `OPENAI_API_KEY` / 自定义 `*_SECRET` /
    `*_PASSWORD` / 嵌套 `deep_token` / 数组内 `item_api_key` 全部打码，非敏感字段保留，坏 JSON 不打原文）、
    onboarding 语义 **18 条全绿**（增量加键且保留其它字段与键序 / 已是 true 时字节不变（幂等）/
    坏 JSON 与「根非对象」fail-closed / 文件不存在时创建）、
    profile 路径 **28 条全绿**（profile 预览与 live 同一套脱敏 / 坏库保存 fail-closed 且旧库字节不变 /
    正常库保存仍保留旧 profile / 库不存在时报「暂无」不报「损坏」/ extra-env 失败码传播 7：
    失败时 fail-fast 不越过、成功时才调 onboarding）、
    本轮（2026-09-23 第二批）**31 条全绿**：`profiles` schema 损坏（保存中止 + 旧库字节不变、列表报损坏）/
    `cp` 失败注入（菜单 1 与 4 都中止、不谎报「已备份」、live 不变）/ 四处 plain-object 校验
    （writer、extra-env、save 的 source、switch 的 config）/ 固定 `date` 连跑两次得到两个不同备份且首个备份仍是原始配置
    （**该「唯一名」策略同日已被撤销**，见下）；
  - 仓库套件 **J 组**：审查环境已实跑 **J1~J6 = 51/51 PASS**，A~J 全量 **276/276 PASS**（正式基线，
    `225` 仅作 A~I 历史基线）；本机受 1 分钟规则限制未跑全量，仅限时 60s 跑到 J1~J2（32 条全绿）。
    上一轮又补 **J7~J11 = 20 条**（schema 损坏 / `cp` 失败注入 / `settings.json=[]` / profile `config=[]` / 备份名唯一）。
  - **本轮（2026-09-23 第三批）改了什么**：
    ① J2 备份名断言原来少写了 mktemp 随机后缀（只匹配到 `…_HHMMSS$`，真实名是 `…_HHMMSS.XXXXXX` → 必红）；
       J8 输入流少了开头的 `y\n`（`settings.json` 已存在时第一个 `read` 是「是否继续修改」，
       `sk-j8` 被吃成这个回答 → 走「已取消配置」并正常返回 0，writer 的根类型检查根本没执行）；
    ② 新增 **J12 = 4 条**（profile save 的 `source=[]`）、**K 组 = 51 条**（Codex 配置库 schema + 备份 fail-fast）；
    ③ **备份语义反转**：Claude 菜单 1/4 从「唯一名（时间戳 + 随机后缀）」改成**固定一份、每次覆盖**——
       唯一名每写一次多一个文件、要用户手工清理（用户明确要求「不要按时间戳无限备份下去」）。
       J2 改成断「只有 1 份 + 无时间戳残留」，J11 从「连跑两次要产生 2 个备份」反转成
       「连跑两次仍然 1 份，且 `.bak` 已被最近一次操作覆盖（不是最早那份）」。
    J 组合计 **77 条**（75 + J11 净增 2 条），A~K 全量 **需在服务器上重跑确认**：
    `bash tests/Hapi_Claude_Manage/run.sh --only J,K`（本机跑不完，见下）。
  - **本轮本机实测（自然结束，非截断）**：`--only K` = **pass=51 fail=0 skip=0**（K 组首次跑就全绿）。
    `--only G,J` 跑到 J1 全绿后被用户叫停（用户 2026-09-23 追加规则：**本机不要再跑测试，改到另一台服务器跑**），
    其中 G 组新断言「备份走 helper（内部 fail-fast + chmod 600）且脚本内无裸 cp -a」**已实测变绿**。
    因此 **K 组是唯一完整跑过的新分组**；G/J 的完整结果以服务器那一轮为准。
  - **新断言的「手工反例自证」本轮没做**（要跑测试才行，已按用户要求停在本机），
    留到服务器上连同 `--only J,K` 一起做。三个变异体（改完记得还原）：
    ① 把 `hapi_save_codex_profile_from_files` 的 `readStore` 退回
       `if (!Array.isArray(store.profiles)) store.profiles = [];` → **K1/K2/K3 必须变红**；
    ② 把任一 `hapi_backup_or_fail … || return 1` 退回裸 `cp -a` → **K5 与 G 组扫描必须变红**；
    ③ 删掉 `hapi_save_claude_profile_from_file` 里的 `if (!isPlainObject(config))` → **J12 必须变红**；
    ④ 把 Claude 备份名改回 `mktemp "$f.bak.$(date …).XXXXXX"` → **J2/J11 的「不堆积」断言必须变红**；
    ⑤ 把固定名改成「只在文件不存在时创建」（冻结最早那份）→ **J11 的「已被最近一次操作覆盖」必须变红**。
  - ⚠️ 自建 harness 也要**抽取自检**（缺函数就 `exit 2`）：踩过——漏抽 `hapi_ensure_claude_onboarding`，
    函数体内的调用静默变成空命令，断言「~/.claude.json 已创建」直接红，但看日志才知道是 harness 的问题。
    K 组新增 `hapi_backup_or_fail` / `hapi_list_codex_profiles` / `hapi_config_codex` /
    `hapi_toggle_codex_recommended_values` 到抽取自检清单，缺任一立即 exit 2。
  - 手工反例自证（唯一名时代的旧记录，作为「断言确实会红」的历史证据保留）：
    三处 `${settings_file}.bak.$(date …)` 退回 `${settings_file}.bak`
    + 把 `cp -a` 备份加回 `hapi_prompt_add_extra_env` → 「备份里是原始配置」等 3 条变红（实测）。
  - ⚠️ 按用户 2026-09-23 的规则：**本机只跑 1 分钟内的定向验证，且一律后台任务 + 日志**；
    整套针对性回归（6 例 ≈2min）与既有套件（≈9.5min）都**改到另一台服务器/审查环境跑**。

### Codex 配置库（`~/.codex/hapi_config_profiles.json`）

与 Claude 配置库同一套规则；2026-09-23 才补齐（此前只修了 Claude 侧，同一个 P1 在 Codex 侧原样存活）：

- **配置库损坏必须 fail-closed，且「损坏」包含 schema 级**：`readStore()` 里
  `if (!Array.isArray(store.profiles)) store.profiles = [];` 是**错的**——它会把
  `{"profiles":{"legacy":{…}}}`（合法 JSON、顶层也是对象）静默重置成空库，紧接着用
  「只有新 profile」的对象覆盖整个旧库 → 旧 profile 静默消失。
  正确写法：`isPlainObject(store)` 不成立 → 抛错；`store.profiles === undefined` 才补 `[]`；
  `!Array.isArray(store.profiles)` 一律抛错（错误信息里保留 `profiles 必须是数组` 便于检索）。
  **两份 `readStore` 实现必须同步**：`hapi_save_codex_profile_from_files`（菜单 2）与
  `hapi_create_codex_profile`（菜单 3）。
  实测：旧实现 `SAVE_RC=0` 且 `legacy` profile 保存后消失（审查环境用真实函数复现）；修后 rc=1、旧库字节不变。
- **列表三态**（`hapi_list_codex_profiles`）：`rc=2` = 库损坏（打「配置库已损坏 + 请修复或删除」），
  `rc=1` = 空库 / 文件不存在（打「暂无已储存的 Codex 配置」）。旧实现 `try { … } catch {}` +
  `Array.isArray(...) ? ... : []` 把坏库显示成「暂无」，用户会以为「没配过」而不是「库坏了」。
  bash 侧必须先判 `list_status -eq 2` 再判 `-ne 0`，两者都 `return 1`（调用方只需 `|| return`）。
- `hapi_switch_codex_profile` / `hapi_delete_codex_profile` 的第一句就是 `hapi_list_codex_profiles || return`，
  所以库损坏时它们先被打回；列表入口统一，不必各自再判一次。
- 尚未按同一规则收紧（都是**只读、不可能写盘**的路径，不构成数据丢失，留作 P3）：
  `hapi_show_codex_profile_by_index` 对坏库会抛原始栈（`JSON.parse` 没有 try），
  `hapi_extract_codex_profile_auth` 与切换 / 删除的内部对 `profiles` 非数组仍按空库处理
  （结果是「配置序号不存在」+ rc=1，不会写盘）。**要改就四处一起改**，别只改一处。

### 凭据文件与临时文件

- `auth.json` / `config.toml` / Codex 配置库 / `~/.claude/settings.json` / claude 配置库 / `cliApiToken`：**创建时就 0600**，
  不要只靠"写完再 chmod"（中间有可读窗口）。Node 侧 `fs.writeFileSync(file, data, { mode: 0o600 })` +
  `try { fs.chmodSync(file, 0o600) } catch {}`；shell 侧 heredoc 前置 `(umask 077; : > "${output_file}")` 占位。
- **备份也要收紧权限**：`chmod 600 "<备份>"` 现在由 `hapi_backup_or_fail` 统一保证（`cp -a` 成功后立刻 chmod **目标**）。
  `cp -a` 会保留源文件 mode，所以旧版本留下的 / 人工放进去的 0644 文件会在一次新版本运行后变成
  「正式文件 0600、备份 0644」——等于真正的 token 反而留在 `.bak` 里。2026-09-19 覆盖了当时的全部 `cp -a` 站点
  （claude settings、codex auth/config、含 `cliApiToken` 的 hapi settings；只含 listenHost/port 的纯配置不在此列但一并收紧）。
  2026-10-19 起共 **12 个备份站点**走 helper（Claude 菜单 1/4、Codex writer / 菜单 1 / 推荐值 / profile 切换、
  hapi settings 的 listen 与 cliApiToken），脚本里已没有「非备份的 copy」。
- 敏感临时文件：`mktemp` 生成不可预测路径（**不要** `${TMPDIR}/xxx_$$.json`），并挂 `hapi_install_sensitive_tmp_traps`
  （`hapi_cleanup_sensitive_tmp` 统一处理 `HAPI_CODEX_AUTH_TMP` / `HAPI_CLAUDE_SETTINGS_TMP`）。
  **故意不挂 INT**：vim 里 Ctrl+C 是退出插入模式的常用操作，挂上会在 vim 退出后连带删掉用户刚保存的内容。

### 编辑器流程（已随菜单 7 移除，2026-10-19）

- 菜单 7 删除后，脚本里**不再有任何文本编辑器调用**。不要再引入 `HAPI_EDITOR` / vim `-c` 那套流程：
  官方 auth.json 由 cc-switch 授权中心绑定，本脚本只负责第三方直连与登录态暂存。
- 仍然通用的经验照上节执行：`mktemp` 随机路径 + `hapi_install_sensitive_tmp_traps`（`HAPI_CODEX_AUTH_TMP` /
  `HAPI_CLAUDE_SETTINGS_TMP`），失败路径也要清理。

### 本脚本的验证方式

- **机械检查（秒级，改完先跑这一条）**：`bash tests/static-checks.sh`。
  它做三件事：全部受控 `*.sh` 的 `bash -n`、每个 `<<'NODE'` 块的 `node --check`、**行尾一致性**
  （同一目录的 `.sh` 必须同一种行尾；单文件内不许混用）。
  已挂到提交前：`.githooks/pre-commit` → `git config core.hooksPath .githooks`（本机已设好，换机器要重设一次）。
  ⚠️ 行尾与「按函数名删整块」的坑见 `AGENTS.md`「编辑与 EOL 约定」；`^}$` 会命中 heredoc 里的 JS，
  所以删函数要先跳过 `<<'NODE' … NODE` 正文再找列首 `}`（2026-10-19 在这上面连错两次）。
- 行为回归：`bash tests/Hapi_Claude_Manage/run.sh`（失败非零退出；`--only A,C` 只跑指定组，`--log FILE` 指定进度日志）。
  分组：~~**A** `last_refresh` 真 RFC3339~~ ／ ~~**B** `id_token` 严格 JWT envelope~~（2026-10-19 删除：只覆盖手写官方
  auth.json 的深度校验，而菜单 7 已移除）／ **C** `auth_mode` 解析 + `loadable` 级校验 ／
  **D** 写入器：第三方 Key 落点（段内 token / 无 env_key / requires_openai_auth=false / auth.json 移除 / 登录态暂存）
  与官方路由保护 ／ **E** 菜单 7 已移除（函数、菜单项、文案三处都不得复活）／ **F** 配置库旁路卡点 ／
  **G** 凭据 0600 与「查看配置」明文显示 Key（校验输出仍然打码）／ **H** 兼容性 ／
  **I** 路由自动收敛（官方剥离+暂存 / 第三方恢复 / 保留 id 不动 / 损坏暂存 fail-closed / 空配置走同一条流程；语义与反例清单见
  `tests/Hapi_Claude_Manage/路由自动收敛-测试文档.md`）／
  **J** Claude Code `settings.json` 写入语义（合并写盘保留未知顶层键 / 备份固定一份不堆积 / 不注入固定补齐项 / 预览明文 /
  配置库损坏 fail-closed（语法级 + schema 级）/ onboarding 幂等 / 写 live 四处 plain-object 校验）／
  **K** Codex 配置库 schema fail-closed（save / create / list 三态）+ 备份 fail-fast
  （writer / 菜单 1 / 推荐值 / profile 切换，每条都断言日志里出现「备份失败，已中止修改」，
  避免「因为别的卡点提前 return」造成的假绿）／
  **L** Codex 1M 上下文窗口（菜单 1 第 4 参数 + 菜单 3 共用的提问：写入 / **无条件删除** / 缺省 `keep` 不改动 /
  route-only **字节级**零改动 / 菜单 3 开启与关闭 / 1M 键必须在第一个 section 之前）
  + 默认模型名 `gpt-6-astra`（含「4 处必须同步」的源码断言）。
- **断言实现：不要再用 `$(grep -cE …)`**（2026-10-19 改）。Windows/MSYS 上最贵的是**进程创建**，
  旧写法 250 条断言 = 250 次 fork+exec。现在 `expect_count` / `expect_grep` / `expect_no_grep` 走
  `count_matches`：`mapfile` 读行 + bash 内建 `[[ =~ ]]`，零子进程。
  三条必须遵守的语义（都有踩坑记录）：
  ① 数的是**匹配的行数**（与 `grep -c` 一致）；
  ② 文件/管道不可读记 0（`<(cmd)` 的 `/dev/fd/N` 也算可读，别改成 `[ -f ]`）；
  ③ **正则写错直接判失败**，不许静默记 0 —— 旧实现里 `grep` 报错被 `|| true` 吞掉，
     `^fn() {`、`7) hapi_…`、`"${auth_file}"` 这三类 ERE 非法模式因此**一直是假绿**，
     换实现后才暴露出来。写带括号/花括号的模式时要转义：`\(` `\)` `\{` `\}`。
  ④ 仓库文件是 CRLF：`mapfile` 会留下行尾 `\r`，`…$` 锚点会假红，所以 `count_matches` 里先剥 `\r`。
  实测（2026-09-19，本机 Windows/MSYS）：**定向分组** `--only C` = 39 断言全绿、`--only E,F` = 35 断言全绿；A 组 ≈15s、C 组 ≈25s、E 组 ≈2min、E+F ≈3min（进程创建极慢，别指望秒级）。
- ⚠️ **全量套件在本机 Windows/MSYS 上超过默认 300s 上限**（2026-09-23 实测）：默认 `HARNESS_TIMEOUT=300` 会被
  `timeout` 杀掉，表现为 **`NOT OK - harness 超时（300s）`、rc=124、日志停在 G 组且没有任何 `NOT OK` 断言**
  （别把它误判成断言失败）。同一次改动加时长上限跑完：`HARNESS_TIMEOUT=1200` → **9m27s、pass=225 fail=0 skip=0、RESULT: PASS**
  （与 2026-09-19 基线一致）。想在本机跑全量就显式抬上限，否则只跑 `--only`。慢是本机进程创建开销，不是断言数量问题。
- ⚠️ 测试执行方式（2026-09-29 **用户结论：不要在本机跑**）：
  - **别在本机跑这套件——太慢**。实测（2026-09-29，Windows/MSYS）：`--only L` **单个分组**就要 **1m45s**，
    全量按老记录 9~10min 以上；中途硬杀的代价只是白等，所以**默认交服务器 / 审查环境**跑行为回归。
  - 本机只做**机械检查**：`bash tests/static-checks.sh`（`bash -n` + heredoc `node --check` + 行尾，见上节）。
    需要看真实产物时用「仓库副本 + awk 抽取函数体」的小探针**目视** config.toml 排版，不跑整组断言。
  - 全局规则仍然是「要跑就跑在**后台任务**里 + 日志文件」（不要前台等）；本机全量需显式 `HARNESS_TIMEOUT=1200`。
  - 推论：**新断言在本机默认处于"未实跑"状态**。汇报时必须写清"哪台机器、哪一轮"，不许把没跑过的一次说成通过。
    2026-09-29 这一轮的实际状态就是典型例子：
    - 本机实跑过：`--only L`（1m45s）= 34 条；全量**被中途硬杀**，没有数字。
    - 审查环境实跑（提交给审查的那一版，即 P1 修复**之前**）：`bash -n` ×2 PASS、24/24 `node --check` PASS、
      `--only G,L` = **51/0/0**、`--only D,G,I,K,L` = **209/0/0**、**全量 = 395 pass / 0 fail / 0 skip**。
    - 但那一版带 **1 个 P1**（TOML 脱敏例外过宽 → 三种场景真实明文泄露），385 条全绿也没抓到它——
      因为当时的 G 组只测了标准顶层 `900000`。**"全绿"不等于"没问题"，别用它替代反例设计。**
    - 修 P1 + 补 L9 之后（G 组 +13 条负向、L 组 +3 条源码断言）：**本机一条都没跑**，
      按算术全量应为 395 + 16 = 411 条；这个数字**未经任何一次实跑确认**，报之前必须自己跑。
  要报测试数字只能是「服务器上跑出来的」，或明确标注为本机某一轮的旧数字。
  全量套件**更早一次**实测是 **pass=128 fail=0**（给 C 组补 loadable 漏口断言之前/之后没重跑过全量），
  该数字**不代表当前代码**，要报数字必须自己跑一遍再写。
  该套件的新断言按仓库约定用**手工反例自证**过一次（旧的 A 组记录）：移除 `isValidRfc3339` 的日历天数判据后，
  A 组立刻报 2 条 `NOT OK`（`a_bad_feb31` / `a_bad_feb29_nonleap`），还原后恢复全绿。
  ⚠️ **路由自动收敛那一轮（同日稍晚）本地一条测试都没跑**（用户要求改由审查环境执行）。审查环境实跑 + 反馈：
  - 首版 `--only D,I` = pass=67 / **fail=4**（A~I = 185 / 4）：blocker 是 **I 组自己的 fixture 打架**——
    I2 后半段用了 `seed_live`（第一行 `rm -rf "$HOME/.codex"`），把 I1 刚写下的暂存路由删了，I3 的恢复链失去前提。
    已修：该子用例改为只覆盖 `auth.json`/`config.toml`，并在 I3 前加前置断言。**生产代码没动。**
  - 第二轮审查环境在**仓库版本**上实跑：`--only D,I` = pass=90 / fail=0、A~I = pass=208 / fail=0（**该轮**数字，已被下一轮取代）。
    同时又抓到第二个 blocker：**空配置 fast path 早于 `readStash()`** —— 只写了第三方路由的 config 被官方剥离后会变成
    空文件（脚本自己造出来的状态），此时填第三方 `base_url` 会绕过暂存静默建 generic custom。已按「空配置走同一条流程」统一，
    并补 I13（端到端现场）/ I14（预览规则同步）/ I9（近似域名）等断言。
  - 第三轮（封板轮）审查环境在**仓库版本**上实跑，P1/P2 清零、A~H 无回归：
    ```text
    bash tests/Hapi_Claude_Manage/run.sh --only I     →  pass=81  fail=0 skip=0
    bash tests/Hapi_Claude_Manage/run.sh --only D,I   →  pass=107 fail=0 skip=0
    bash tests/Hapi_Claude_Manage/run.sh              →  pass=225 fail=0 skip=0   RESULT: PASS
    ```
    **以上是当前正式基线**（先前记录过的 `--only C` 39 / `--only E,F` 35 / `pass=128` / `90` / `208` 都已被它取代）。
  - 手工反例（审查环境在**临时副本**上做，没动仓库原文）：#12（invalid stash 退化成 missing）= 8 条红、#15（I2 重新用 `seed_live`）
    = 5 条红（**I3 前置断言最先红**）、#16（空配置提前退出/旧式 generic）= 5 条红（正好是 I13 的核心恢复链）、
    #17（放宽 `stashProblem()`）= 3 条红 —— 断言有效；#18（只给 `readStash()` 加规则、不同步预览）实测 **81/0 不红**，
    确认「预览侧是第二份规则」这个缺口**真实存在**。其余反例未逐条实测。
  - 反例清单（**18 条**）与上述实测结果都在 `tests/Hapi_Claude_Manage/路由自动收敛-测试文档.md` 第 7 / 11 节。
- ⚠️ **本套件的路径必须用盘符形式（`C:/…` / `E:/…`）**：MSYS 会转换**命令行参数**里的类 POSIX 路径，但
  **不转换环境变量**，而 Windows 原生 node 会把 `/tmp/x` 解析成"当前盘符根 + `tmp\x`"（如 `E:\tmp\x`），
  与 bash 眼里的 `/tmp` **不是同一位置**。后果很隐蔽：夹具/配置被写到另一个目录 → **正向用例整片变红、反向用例反而假绿**。
  `run.sh` 用 `cygpath -m` 统一成盘符形式（实测 `mkdir`/`cp`/`rm`/`mktemp`/`chmod`/原生 node 都认），
  只有 `PATH` 例外——里面必须放 `cygpath -u` 的 POSIX 形式，否则 bash 找不到假编辑器。
- 两处防"假绿"的保险：① `auth_check` 在夹具缺失时返回专用码 **3**（否则"期望 rc=1"的断言会因为文件不存在而假绿）；
  ② 夹具数量 < 30 直接 `exit 2`（夹具没生成时整套反向断言都会假绿）。
- ⚠️ **夹具 helper 自己的副作用会打断后续用例**（2026-09-19 被审查环境抓到，blocker 级）：
  `seed_live()` 第一行是 `rm -rf "${HOME}/.codex"`，I2 里为了造一份"只有 model 行"的配置调用了它，
  于是把 I1 刚写下的**暂存路由**删了，I3 的恢复链失去前提 → 4 条断言全红，而生产代码其实没错。
  规则：① 需要保留**跨用例状态**（暂存文件、配置库、`*.bak`）时，不要用会 `rm -rf` 的 helper，
  改成只覆盖单个文件（`cp 夹具 → auth.json` + `printf → config.toml`）；
  ② 依赖前序状态的用例（如 I3 依赖 I1 的暂存）**前面必须加一条前置断言**把依赖钉死，
  否则以后再有人改动 fixture，红的是"恢复实现"这种误导性位置。
- 交互式菜单（`read` 驱动）的自动化办法：`run.sh` 用 awk 按**内容锚点**抽取（`^# 按任意键继续函数` → `^# 主循环函数`，
  颜色变量单独抽、守卫块与 `mainloop` 都丢掉），再用 `printf '1\n\ny\nn\n' | 函数名` 按顺序喂每个 `read`
  （`pause` / 确认提示也各吃一行），用假编辑器（把预置夹具 `cp` 到 `${@: -1}` 的目标路径）模拟"用户在 vim 里粘贴并保存"。
  ⚠️ 假编辑器/假 vim 是**子进程**，它要读的变量（`FAKE_EDITOR_SOURCE` / `FAKE_EDITOR_STATUS` / `FAKE_EDITOR_LOG`）
  **必须 `export`**，否则赋值只在父 shell 可见、分支永远不触发（踩过：编辑器失败分支"怎么都不生效"）。
- 断言注意：① 断言"临时目录已清理"前先确认该目录只放被测系统的产物，夹具自己的文件会被算成残留；
  ② `ls | grep` 这类计数断言要**锚定整名**（`^auth\.json$`）——`auth.json.bak` 会被 `auth.json` 匹配到（踩过）；
  ③ 不要用 JWT 前缀之类的子串做计数断言（同结构的 token 共用 header，计数会翻倍）。
