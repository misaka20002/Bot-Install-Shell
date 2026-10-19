# Codex 凭据 / 路由 / 1M 上下文窗口 —— 实现约定

> 由 `AGENTS.md` 的「Codex 专属约定」一节拆出（2026-10-19）。改动
> `Manage/Hapi_Claude_Manage.sh` 里任何与 Codex 凭据、`model_provider` 路由、
> `model_context_window` 有关的代码前，先读完本文。
> 对应回归：`tests/Hapi_Claude_Manage/run.sh --only D,I,L`。

### Codex 第三方 provider 的取 key 语义（2026-10-19，最重要的一条）

Codex 对自定义 provider 只认三种凭据来源（官方 config reference）：
`experimental_bearer_token`（直接写在表里）/ `env_key`（**只从进程环境变量取值**）/ `requires_openai_auth = true`
（走 OpenAI 认证，即 auth.json）。三者互斥，且 `env_key` 优先于 `experimental_bearer_token`。

- **`env_key` + 往 auth.json 塞 Key 是错的**：2026-10-19 的真实事故是
  `Codex error: Missing environment variable: OPENAI_API_KEY` —— 脚本写了 `env_key = "OPENAI_API_KEY"`
  又把 Key 写进 auth.json，而自定义 provider 根本不看 auth.json。hapi 拉起的 codex 进程里没有那个环境变量，
  于是必然报错。
- 现在第三方段一律写：
  `experimental_bearer_token = "<key>"` + `requires_openai_auth = false`，并**删掉已有的 `env_key` 行**
  （原位替换，保持字段顺序）。段内有 token 时必须显式 `false`：残留的 `true` 会让 ChatGPT 的 token 被发到第三方端点。
  ⚠️ **迁移时必须先删 `env_key` 再写 token**：`env_key` 的优先级高于 `experimental_bearer_token`，
  两者并存时刚写的 token 是死字段，Codex 仍旧报 Missing environment variable（2026-10-19 评审抓到，
  I15-A 用「env_key 与 token 并存」的夹具钉住）。
- Key 来源优先级（迁移时）：调用方传入 > 段内已有 token > auth.json 的 `OPENAI_API_KEY`。
  三者都没有 → 只警告，**不删 `env_key`**（那可能是用户真在用的环境变量），也**不动 auth.json**。
- `hapi_codex_current_value` 有两个相关字段：`OPENAI_API_KEY`（段内 token 优先、auth.json 兜底）与
  `CONFIG_BEARER_TOKEN`（只读段内 token）。自检用它区分「Key 到底从哪来」，**不要用 provider_id 是否存在来猜**。
- **第三方模式下 auth.json 必须不存在**（对齐 cc-switch `preserve_codex_official_auth_on_switch = false`）：
  - 写盘完成后按「当前 `model_provider` 指向自定义段 + 段内有 token」判定第三方模式；
  - 现有 auth.json 若是 **ChatGPT 登录态**（有 `tokens`，且 mode 为空/`chatgpt`/`chatgptAuthTokens`），整份存进
    `~/.codex/hapi_login_stash.json`（0600）后再删；纯 apikey 的 auth **不暂存**（Key 已在 config.toml）。
    ⚠️ 判定要用 `isChatgptLogin`，**不要用 `hasOfficialAccountMaterial`**——后者把 apikey 也算「官方材料」，
    会把中转 Key 搬进登录暂存，之后切回官方时覆盖用户新绑定的登录态（D 组有反例断言）。
  - 菜单 4 的迁移函数（`hapi_migrate_codex_provider_credential`）也有同一套「暂存 + 移除」逻辑：
    它是同一规则的第二份实现（两个 node 进程无法共享函数），改一处要同步另一处。
    并且它**不能**在「没有 env_key」时提前 exit——新式配置（只有 token）同样要移除 auth.json（I15-B 钉住）。
  - 切回官方（官方端点 + 没填 Key）时，**只在 auth.json 不存在时**把暂存放回，避免覆盖 cc-switch 刚绑定的新登录。
- **判定目标的一处补充**：没有登录材料、没有新 Key、但 `base_url` 明确是官方端点 → 判 `official`
  （旧逻辑判 `legacy`，会建一个没有凭据的 custom 段，也就永远走不到「恢复登录态」）。
- **写入后自检**：菜单 1 与菜单 4 都会调用 `hapi_report_codex_credential`，回读并打印
  「Codex 会用的 Key（来源 + 长度）」。读不到 Key 且不是官方登录态时报红——这正是当年
  「明明填了 Key 却报 Missing environment variable」时最缺的一条反馈。
- 菜单 7（写入/编辑官方 auth.json）**已移除**：官方登录改由 cc-switch 的授权中心绑定。
  不要把编辑器流程再加回来——本脚本只负责「第三方直连 + 官方登录态暂存」，不负责登录本身。

### Codex 1M 上下文窗口（2026-09-29 加，2026-10-19 调整）

- 提问抽成 `hapi_ask_codex_context_window`（输出只有 `1m` / `off`，提示语走 stderr），
  菜单 1 与菜单 3「新建配置（不切换）」共用。**不要各写一份 case 分支**——菜单 3 曾经整块漏掉这一问，
  产物和菜单 1 不一致。
- 菜单 1 把答案作为**第 4 个位置参数**传给 `hapi_write_codex_current_config`（`"1m"` / `"off"`）。
  ⚠️ 该参数缺省值必须是 `keep`（=不改动）**不是** `off`：`hapi_sync_codex_route` 的 `route-only` 与其它旧调用点
  只传 3 个参数，缺省成 `off` 会让它们顺手删掉用户的 1M 声明（L7 钉住）。
- 语义对齐 cc-switch：`src/components/providers/forms/CodexConfigSections.tsx` 的 `contextWindow1M` 开关 +
  `src/utils/providerConfigUtils.ts` 的 `extractCodexTopLevelInt` / `setCodexTopLevelInt` / `removeCodexTopLevelField`。
  - 开启 → 顶层 `model_context_window = 1000000`；`model_auto_compact_token_limit` **缺失时**才补 900000（已有值不覆盖）。
  - 关闭 → **无条件删除**这两个顶层键（2026-10-19 用户明确要求对齐 cc-switch；旧版「只删自己写的默认值、
    保留用户自填的 200000/150000」已废弃）。取舍：1M 是一个开关，不是一个用户字段——要保留自定义值就不要回答「否」。
  - 只认**顶层**（第一个 section header 之前）的字段；section 内的同名 key 不动（与 cc-switch 只扫顶层区域一致）。
- 菜单 3 生成的配置里，两个 1M 键必须落在**第一个 section 之前**（否则 Codex 会把它们当成
  `[model_providers.custom]` 的字段）——L8b 用 node 校验位置，L8c 断言回答「否」时不写任何 1M 键。
- **不参与路由暂存**：1M 字段是顶层全局设置，`readStash` / `writeStash` 只搬 `model_provider` 行与
  `[model_providers.*]` 段，所以官方剥离 / 第三方恢复都不会顺手动它们。`route-only` 更是零改动（L6 按字节断言）。
- 菜单 1 的默认答案跟随现状：`hapi_codex_context_window_state` 读顶层 `model_context_window`，是 1000000 → `[Y/n]`，
  否则 `[y/N]`。探测失败 / 文件不存在 / 值带引号或非纯整数 → 按"没有 1M"处理（默认落在不开启一侧）。
- 默认模型名统一为 `gpt-6-astra`：菜单 1 与菜单 3 的 `local default_model`
  **加**两个 node heredoc 的兜底值（`process.env.CODEX_MODEL ||`），共 4 处，必须一起改。
  ⚠️ 「4 处必须同步」**光靠 L1/L8 钉不住**（那两个用例走的是 shell 已填好的默认值，命中不到 Node fallback），
  现由 L9 三条**源码断言**兜底。
- 回归：`tests/Hapi_Claude_Manage/run.sh --only L`（菜单 1 / 菜单 3 全链路 + 写入语义）。
- 预览已改为明文（见上节），因此「1M 数字阈值不能被打码」这个脱敏例外**不再需要**，
  相关的 `isSensitiveKey` 副本与 `sanitizeToml` 一起删掉了。
