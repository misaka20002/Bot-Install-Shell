# `Manage/meme_generator.sh` 专属约定

> 本文件是 `AGENTS.md` 的细节分册。失败路径、镜像源、编辑与 EOL 等通用规则仍在 `AGENTS.md`「通用 Bash 约定」。

### 自更新

- `SCRIPT_VERSION` 是自更新的唯一开关：**改动这个脚本后必须让它高于上一个 commit 的版本号**（只要比已提交的高即可，不必刻意再 +1），否则已安装副本（`/usr/local/bin/meme_generator.sh`）会认为"已是最新"，根本不会下载本轮修复。
  ⚠️ **这条现在没有任何测试守着**（2026-09-13 起）：原先的「工作区版本必须高于 HEAD」断言已删除——那种"拿工作区跟 HEAD 比"的断言与**提交流程耦合**（刚 commit 完工作区 == HEAD，必然判红，是假警报），为它再加一堆"有没有未提交改动"的判断等于把测试变成流程检查器，收益不值得。
  所以它是**纯人工约定**：改完脚本、**提交前**自查——① 版本号高于上一个提交；② 别忘了这次加固的提交。忘记提版本时**不会有任何红灯提醒**。
  前提是**未 commit 的内容绝不会被远端源分发**；`download_script` 另外校验"下载版本 == 当前版本"，所以即使镜像滞后也不会被写回旧版本。
- `main()` 里 `$0` 命中 `/dev/fd/` 或 `bash` 时（即 `bash <(curl …)` 首次执行）会调 `ensure_script_saved`；**失败只提示、不把首次启动变成致命错误**（真正严格拦截的是创建 cron 的路径）。
- `ensure_script_saved` 的同版本 fast path 也要确认文件**可用**（非空 + 可执行 + `bash -n` 通过），否则被截坏的同版本脚本会被当成"已是最新"。
- `download_script` 必须校验**下载到的版本 == 当前 `SCRIPT_VERSION`**，否则换下一个源：镜像滞后时把旧版本当成功写回会造成"越更新越旧"。
- 文件末尾：`auto_update_meme_generator; exit $?`——**不能写 `exit 0`**，否则前面所有 `return 1` 都被吞掉，cron 永远认为成功。

### 安装状态与修复模式

- 两个判据不要混用：`is_meme_repo_installed`（`.git` 存在 = 克隆过）与 `is_meme_install_complete`（仓库 + 可用 venv + 配置文件 + **包真的装进 venv**）。
  安装入口用后者决定"已安装"；前者只用于决定"要不要跳过克隆"。
- 「安装完成」必须证明 `pip install .` 成功，不能只看文件在不在：`is_meme_install_complete` 额外要求
  `venv/bin/python` 可执行且 `python -m pip show meme-generator` 通过。
  **反例（必须防住）**：以前装好过、配置也在 → venv 被删/损坏 → 再选安装进修复模式 → 重建 venv（activate 又有了）→ pip 失败 →
  此时 `.git` + `activate` + `config` 三样齐备，只看它们就会报「您已安装」，把用户**永久**挡在修复流程外。
- clone 成功但 venv / pip / 配置失败后，用户再选「安装」必须进入**修复模式**（跳过克隆、复用仓库、重建 venv、**不覆盖已有配置**），不能报"您已安装"把人挡在外面。
- 菜单状态机是**三态**，别把修复模式的半成品显示成「未启动」（会误导用户去点启动）：
  `!repo → [未安装]`、`repo && !install_complete → [安装未完成]`、`install_complete` 再按进程分「运行中 / 未启动」。
  `start_meme_generator` 的入口守卫用 `is_meme_install_complete`，不是「仓库在 + activate 在」。

### 强制覆盖本地（用户明确要求）

- 用户诉求：表情包仓库的维护者经常 `git push -f` 改写历史，不能让用户"卡住"在无法 `pull` 的状态。
- 因此 `git_update` 一律：`git fetch --prune --force origin` + `git reset --hard origin/<branch>`。
  用 `origin` 而不是 `--all`：用户可能额外挂了 `upstream` / `backup`，其中任何一个坏掉都会让本次候选 URL 白白失败。
  **不要**改成 `git pull`（可能拉到另一个 upstream），也不要"保留本地改动"。
- 语义边界（**明确指出不保护**，已实测确认）：我们**不主动执行 `git clean`**，所以与远端不冲突的未跟踪文件会留下来；
  但若远端新版本把某个同名路径变成了 tracked，`reset --hard`（退出码 0）**会直接覆盖那个文件**，用户放在仓库目录里的内容就没了。
  因此**不要把"用户自定义文件一定安全"写进文档或承诺**；要在仓库目录里放自定义表情包，请改为放到仓库外的目录并写进 `meme_dirs`。
  G 组里曾有用例断言这一点（`future` 同名冲突），但**G 组自 2026-09-13 起默认不跑（未维护）**——
  所以这条语义**以本节文字为准，别当成"有测试保护"**；改动 `git_update` 时请显式 `--with-git` 跑一次。
- 失败时把 `origin` 恢复成权威地址（绝不留下相对路径 / 残缺 URL）。

### 仓库地址与镜像

- 主仓库权威地址写死在 `MAIN_REPO_URL`；额外仓库集中在 `EXTRA_REPOS`，字段用 **`|`** 分隔：`"文件夹名|表情包子目录|Git 地址|分支名"`。
- **禁止用 `:` 做字段分隔符**：URL 本身含冒号，`${repo_info##*:}` 取的是最后一个冒号之后，会把 `https://` 吃掉，写出 `//github.com/...`。
- **禁止从当前 origin 反解析权威地址**：`${remote_url#*//*/}` 会剥掉 `https://`，国外环境（`GithubMirror_*` 为空）甚至会把 origin 改成相对路径。
  代理 URL 一律由权威地址拼接：`${GithubMirror_1}${canonical_url}`，且镜像变量本身以 `/` 结尾。
- 「已安装」判据见上文"安装状态与修复模式"；额外仓库用 `is_extra_repo_installed`。
  例外：`uninstall_meme_generator` 用目录判据是为了"能清理残骸"，属于有意为之。
- 写进配置的仓库路径必须是**本地真实存在**的（`get_installed_meme_dirs` 会校验到表情包子目录）；单仓库启用前也要校验 `"${repo_path}/${repo_subdir}"` 存在。

### 目录所有权（防数据丢失）

- `git_clone` 进入时若 `target_dir` **已存在且非空**，直接拒绝并返回 1，**不删除**；只有真正为空的目录才接管（`rmdir` 成功才继续）。
- 函数内用 `cleanup_allowed` 记录"这个目录是本轮创建的"，失败重试前才允许 `rm -rf`；**最后一次失败也要清理**，否则残留 `.git` 会被误判成已安装、非空无 `.git` 又会被自己拒绝接管。
- 推论：**不能用"没有 `.git`"推断"这个目录是刚才失败的 clone 创建的"**——用户可能手工往里面放过文件。

### 服务状态与停止

- **HTTP 健康 ≠ 进程存活**：服务死锁、端口配错、HTTP 未就绪时进程仍在。停止 / 更新 / 看日志 / 重装依赖一律按「进程是否存活」判断（`meme_pid` → `is_meme_process_running`）。
  `is_meme_http_responding` 只回答「HTTP 端口是否已有服务应答」，并且**故意不加 `curl -f`**：应用根路径返回 404/500 也算"已起来"，加 `-f` 会让 `tmux_gauge` 永远超时。
- 「查看日志」在服务异常时最需要，不能要求 HTTP 通。
- **`is_meme_process_running` 必须把"前台 watchdog 还活着"也算作运行中**（判据第一项就是 `foreground_pid_alive`）：
  前台 watchdog 在「python 崩了 → sleep 2 → 再拉起」的间隙里既没有 python PID 也没有 tmux 会话，只看这两项会把这 2 秒误判成"未运行"，
  于是停止/更新就可能在 watchdog 眼皮底下改 Git/venv，2 秒后旧 watchdog 又把 python 拉起来。
- **停止必须按顺序**：立停止标志 → 杀前台守护循环 → 停 tmux 会话（`tmux -L <name> kill-server`）→ 清理残留 python 进程。只杀 python 会被守护循环在 2 秒后重新拉起（停止标志是这条链的兜底：即使没 kill 掉循环，循环也会自行退出）。
- **停止必须 fail-closed，身份文件的生命周期同样如此**：能确认身份才 kill，并且要**等到确认它真的退出**才删除 PID 文件；
  身份校验不过、但文件里的 PID 仍活着（旧版一行式 / PID 被复用）时：**不 kill、不删除**，最终 `return 1` 让人工处理。
  绝不能在确认退出前就把身份文件删掉——删了 `is_meme_process_running` 就再也看不见这个 watchdog，
  残留循环会在 2 秒后把 python 拉起来，而我们却已经宣告「停止成功」。
- **已经安全停止过的路径只能调 `start_meme_generator`，绝不能调 `restart_meme_generator`**。
  `restart_meme_generator` 的入口守卫是「当前没在运行就无法重启」，而"重装依赖 / 更新"这类流程刚刚**主动停过**服务，
  此刻必然没有运行 —— 于是"重新启动"只会打印「未启动，无法重启」，**服务根本不会被拉起来**（用户以为恢复了，实际是停的）。
  同理 `update_meme_generator` 的两条分支都直接调 `start_meme_generator`。
- **动作名（"启动"/"重启"）用参数 + `local` 传递，不要用全局变量**：`Start_Stop_Restart` 曾经是全局赋值，
  一次 restart 之后会在同一个管理 Shell 生命周期内粘住，之后普通启动也显示"重启成功"。
  现在是 `start_meme_generator "${1:-启动}"`（`local`），嵌套定义的 `Tmux_Start` 靠 bash 动态作用域拿到它。
- **前台守护循环的 PID 文件有三行**（PID / boot_id / starttime），`foreground_pid_alive` 是 **fail-closed**：三项缺一不可、必须逐项匹配才 kill；旧版一行式 PID 文件一律视为不可信。
  宁可让调用方报「停止失败，请人工处理」，也绝不猜着 kill 掉拿了同一 PID 的无关 root 进程。
  并且**这个 PID 文件只能在 cd / 激活 venv 都成功之后才登记**（见"通用约定 · 失败路径"第 4 条），否则会留下指向管理 Shell 自己的身份文件。
- **登记本身必须是可失败的事务**（`register_foreground_watchdog`）：`boot_id` / `starttime` 先在变量里取全并校验非空，
  再写同目录临时文件、成功后原子 `mv`。任一步失败（目录不可写、磁盘满、`/proc/.../boot_id` 读不到）都 `return 1`，
  **绝不能因此进入 watchdog 循环**——否则 watchdog 真活着、`foreground_pid_alive` 却永远 fail-closed，
  上面那条「sleep 2 间隙算运行中」的保护会当场失效。
  `export Boolean=false` 这种写法**无效**：它只改当前新进程自己的环境变量，原循环看不见。
- `meme_pid` 的匹配已收紧：只认 `python[3.x] … -m meme_generator.app` 的命令行，并在拿得到时校验 `/proc/<pid>/cwd` 就是主仓库目录，避免无关进程被误杀。
- **当前 Shell 内统一用 `activate_meme_venv`**（内部 `. venv/bin/activate` 并返回真实结果）：调用方必须检查，否则 venv 缺失/损坏时 `python` / `pip` 会落到 root 的系统 Python 上。
  独立子 Shell 无法调用父 Shell 的函数（tmux 的启动命令串、自动更新写到 `/tmp` 的启动脚本），那里可以直接 `source venv/bin/activate`，但**必须**放进 `&&` 链或写成 `|| exit 1`。
- 脚本从不执行 `pm2 start`，PM2 遗留分支已全部移除；tmux 守护是要保留的行为。

### 配置文件读写

- 三个入口：`config_get(section, key, file)`、`config_set(section, key, value, file)`、`config_set_string(section, key, text, file)`。全部**段内定位**、剥行尾注释、保留原行注释。
- `config_set` 的第三个参数是**完整的 TOML value 表达式**，本函数不做类型猜测：字符串必须自带引号（用 `config_set_string`），数组写 `["/a/b"]`，布尔写 `true`。
  **给字符串用 `config_set` 会写出非法 TOML**（`key = abc123`），清空时更会变成 `key =`。
- `config_set_string` 收「字符串内容」，自动加引号并转义 `\` 与 `"`（因此值里的这些字符不会破坏 TOML）。
  它**当前不处理换行 / tab / 控制字符**，只用于单行字符串（端口、host、百度密钥都是单行）；要支持多行得补齐完整 TOML basic-string 转义。
- `config_set` 用 `ENVIRON`（不是 `-v`、更不是 sed）传值；**找不到 key/section、或 `mv` 失败都返回 1**，调用方必须检查——"什么都没改却说成功"会把界面提示变成假消息。临时文件建在目标文件同目录，保证 `mv` 是同文件系统内的原子替换。
- `config_get` 是**文本读取，不解 TOML 转义**：只剥"整体包裹"的引号（`"0.0.0.0"` → `0.0.0.0`），数组值 `["/a/b"]` 的引号必须保留（否则按引号增删路径的逻辑会失效）。
  所以它只用于端口 / host / 路径列表 / 字母数字密钥这类无转义内容，**别拿它读任意字符串**（含 `\` `"` 的值读回来是转义形式）。
- `meme_port()` / `meme_host()` 只读 `[server]` 段；`meme_dirs_value()` 返回去掉外层 `[]` 的列表，`remove_dir_from_list()` 负责增删单项。
- 端口必须校验范围 **1..65535**（只判「纯数字」会放过 0 / 65536 / 999999）。
