# AGENTS.md

给 AI Agent 的仓库指南。本文件描述 **Yunzai-Bot-Shell**（呆毛版 Yunzai Bot 一键部署与管理脚本集）的结构、约定与注意事项。

## 项目概览

- 纯 **Bash** 脚本集合：无构建步骤、无包管理、无自动化测试框架。目标环境是 **Debian 系 Linux**（Ubuntu / Debian 等），运行要求 **root**。
- 用户入口链路：`install.sh`（装 dialog/curl，下载 `Manage/Main.sh` 校验后装为 `/usr/local/bin/xdm`）→ 用户执行 `xdm` → `Main.sh` 主菜单 → 各功能脚本。
- **每个 `Manage/*.sh` 都是「独立整包」**：主菜单用 `bash <(curl -sL ${URL}/xxx.sh)` 现场从远端拉取再执行。
  因此单个脚本必须自包含、能被 `bash <(curl …)` 直接跑；**不要 `source` 仓库内其他脚本，也不要假设自己旁边还有别的文件**。
- 国内/国外分流：脚本顶部用 `curl https://ipinfo.io` 取国家码；`CN` 时 `GitMirror=gitee.com`、`GithubMirror_1/2` 设为 GitHub 加速代理，否则留空表示直连。
- 依赖：**Shell 脚本自身的前置工具**（`curl` / `git` / `tmux` / `cron` / `python3-venv` 等）通过系统包安装；
  **被管理的应用**允许在自己的 venv 里 `pip install` 自身依赖。两者不要混为一谈。

## 目录结构

| 路径 | 说明 |
| --- | --- |
| `install.sh` | 引导安装器：装依赖 → 下载 `Manage/Main.sh` → 校验后装为 `/usr/local/bin/xdm` |
| `Manage/Main.sh` | xdm 主菜单（TUI），分发到下面各功能脚本，并负责自身更新 |
| `Manage/meme_generator.sh` | meme 表情包生成器管理（本仓库当前最复杂的脚本，约定见 `docs/agents/meme-generator.md`） |
| `Manage/Hapi_Claude_Manage.sh` | Hapi / Claude Code / Codex / opencode 管理（含 Codex 第三方凭据写入与官方登录态暂存，约定见 `docs/agents/hapi-claude-manage.md`） |
| `Manage/*.sh` | 其余功能脚本：`SYS_Manage.sh`、`NapCat.sh`、`Sayu_Bot.sh`、`Lagrange_OneBot.sh`、`BOT-*.sh`、`BOT_INSTALL.sh`、`GitBot.sh`、`QSignServer.sh`、`OtherFunctions.sh` |
| `Linux/Bot-Install-*.sh` | 各发行版的系统级引导脚本 |
| `Manage/用户协议.txt` | 安装前需用户同意的协议 |
| `Markdown/`、`img/` | 使用文档与截图 |
| `tests/` | 回归测试（`tests/<脚本名>/run.sh`）。只在仓库内跑，不随功能脚本分发 |
| `version` | 仓库版本（`version:` / `date:` / `help:`），由 `install.sh` 读取 |

## 通用 Bash 约定（所有 Manage 脚本适用）

### 脚本骨架

```bash
#!/usr/bin/env bash
set -o pipefail                 # 失败路径必须可察觉；脚本不使用 set -e

export red="\033[31m" ... export background="\033[0m"

# 平台守卫：Android 拒绝 → 非 Linux 拒绝 → 非 root 拒绝 → 非 Debian 系拒绝
...
main(){ ...菜单... }
function mainbak(){ while true; do main; done; }
mainbak
```

- `mainbak` 这个名字是 **`Manage/Main.sh` 专属约束**：`install.sh` 用 `grep -q "function mainbak"` 校验下载到的 xdm 是否完整，所以 **Main.sh 里不能改名或删除它**。其它功能脚本不需要这个入口。

### 失败路径（本项目最重要的一条）

历史故障绝大多数来自「失败了却继续往下跑，最后宣告成功」。改动任何脚本时按下面执行：

1. 带管道的命令（如 `git clone … | tee -a log`）**必须**取 `${PIPESTATUS[0]}`。只判断 `if` 的返回值会被 `tee` 的 0 骗过。
   本项目同时保留文件顶部的 `set -o pipefail` 作为兜底，但**显式 `${PIPESTATUS[0]}` 才是主手段**——不要只依赖全局 shell option。
2. 每个 `cd` 都不能"裸奔"：**函数内**用 `|| return 1`，**顶层代码**用 `|| exit 1`（顶层不能 `return`）。
   `cd` 失败后 shell 会继续在**原目录**执行后续命令，这是静默错跑的主要来源。
3. 封装函数必须**如实返回**：禁止写成「调用子函数后无条件 `return 0`」。
   典型：`stop_meme_service` 只要还有残留进程就 `return 1`，调用方（更新 / 重装 / 卸载 / 重启）必须 `if ! …; then 中止; fi`。
   写配置同理：`config_set` 在 key 不存在或 `mv` 失败时返回 1，调用方要检查。
   真实事故（2026-09-13）：`setup_auto_update` 的**关闭分支**只在失败时 `echo` 一句红字，没有 `return 1`，于是函数返回 0
   （最后一条语句是 `echo`）——违反本条。**它特别隐蔽**：调用点 `Tmux_Start` 的分支最后一句也是 `echo`，返回值在那一层被吃掉，
   所以端到端用例永远看不出问题，只能**直接断言函数返回码**（见 `tests/` 的 F9）。修这类 bug 时顺手加一条**正向对照**
   （成功路径必须返回 0），否则容易修成"一律返回 1"。
4. **登记"我正在干什么"要在准备动作全部成功之后**：写 PID 文件、建 cron、改配置这类"声明状态"的动作，必须放在所有可能失败的准备（`cd`、激活 venv、依赖安装）**之后**。
   真实事故：`Foreground_Start` 先写 PID 文件再激活 venv，venv 损坏时留下一个指向**管理 Shell 自己**的有效身份文件，之后"卸载"会把当前管理进程 kill 掉。
5. 下载 / 自更新必须：`mktemp` 临时文件 → `curl -fL --connect-timeout … --max-time … --retry …`（`-f` 让 4xx/5xx 变成失败）→ 内容校验（**自维护文件**：`bash -n` + 关键标记 + **版本一致性**；**上游第三方脚本**：`bash -n` + 首行 `#!`，理由见下）→ 原子替换（同目录 `.new.$$` 再 `mv -f`）。
   反面教材：`curl -sL url > "$目标文件"` 会**先截断**目标文件，断网时把可用脚本清成 0 字节，并把错误页当脚本装上去。
   ⚠️ **上游脚本只认结构、不认内容**：拿对方的函数写法当标记，人家改一次写法就永久误报（2026-10-22
   `install_linuxqq_rootless` 从 `{` 改成 `()`，安装一直报「下载失败或校验未通过」，文件其实好的）。
   首行 `#!` 挡的是「能通过 `bash -n` 的拦截页」；版本号这类自己要用的数据在用到的地方按需读。
   细节与两次误报的判据见 `docs/验证方式.md`（tests/NapCat 段）与 `Manage/NapCat.sh` 的 `download_napcat_installer` 注释。
6. 关键安装步骤失败要**中止**并返回 1；确实非致命的步骤（资源下载、字体复制）可以继续，但提示语必须写清「核心已成功，某步骤失败」，不能统一打印「安装完成」。
   中断后必须能**重新进入修复流程**：判据要区分"仓库已存在"与"安装已完成"，不能因为 `.git` 在就把用户挡在"已安装"外面。
7. `cron` 类功能：先用 `command -v crontab` 确认可用，并对 `| crontab -` 的写入结果做判断；**删除 cron 失败时不得继续删除它依赖的系统脚本**（会留下每天报错的 root 定时任务）；卸载时同步移除对应条目。
8. **crontab 的读取与写入都必须走统一入口，不要各写一遍 `crontab -l 2>/dev/null | grep ...`**。两个原因：
   ① 删除时：当 meme 那一条是用户**唯一**的 cron，`grep -v` 无输出 → grep 返回 1，而脚本顶部有 `set -o pipefail`，
      整条 pipeline 因此返回 1 —— cron 其实**已经删成功**，脚本却报「删除失败」，进而拒绝删系统脚本（uninstall）或误报 cron 仍在（toggle）。
   ② 更危险的是**读取失败**：`2>/dev/null` 丢掉 stderr 后，"permission denied 这种真错误"会呈现为「非零 + stdout 为空」，
      于是被当成"用户没有 crontab / 没有该任务"。后果：卸载以为 cron 已清掉（转而允许删系统脚本）；
      开启自动更新以为"尚无该任务"，用 `(crontab -l; echo 新行) | crontab -` 重建 ——
      那个 subshell 里 `crontab -l` 失败、`echo` 成功、退出码仍是 0，**用户整份 crontab 会被覆盖成一行**。
   现在统一为三层：
   - `read_current_crontab <文件>`：**保留 stderr** 读一次。返回 0 = 读到（内容可能为空）；1 = 读取失败。
     判据不是"stdout 是否为空"，而是 stderr 里的明确文案：`no crontab for` → 确认没有 crontab（返回 0、内容置空）；
     其它任何非零（含 stderr 为空、以及 permission denied）→ 返回 1。
   - `meme_cron_present`：**三态** 0=存在 / 1=确认不存在 / **2=读取失败**；调用方必须单独处理 2，绝不能当成 1。
   - `append_meme_cron` / `remove_meme_cron`：读取失败一律不写、返回 1；写入判据只有最后 `crontab -` 的退出码；
     空内容写空（不写只有换行的 crontab）。
   四个调用点（uninstall / setup 的开启与关闭 / toggle / 主菜单状态显示）都只操作这一次安全读取出来的内容。
   回归断言：唯一一条 cron 必须删成功、无该任务幂等、**stderr-only 读取错误必须失败**、读不到时 append/toggle 拒绝写入；
   对应变异：`grep -v | crontab -` 老写法，以及把「非零」一律当成「没有 crontab」。

### 镜像源与「现场拉取再执行」入口（gitee 451 事件：2026-09-29 / 2026-10-01）

分发方式是 `bash <(curl -sL ${URL}/xxx.sh)`——**没有 `-f`、没有内容校验**，所以只要远端返回 4xx 的**纯文本 body**，
bash 就会把它当脚本执行。这个坑已经踩过两次，症状一模一样：

```text
root@hcss-ecs-bb6f:~# xdm cc     # 2026-09-29
root@hcss-ecs-bb6f:~# xdm sys    # 2026-10-01
/dev/fd/63: line 1: The: command not found
```

原因：gitee raw 对该文件返回 **HTTP 451**，body 只有一行
`The content may contain violation information`（45 字节、无换行）→ `bash` 把第一个词 `The` 当成了命令。

**实测拦截面（两次实测，master 路径）**：

| 文件 | 2026-09-29 | 2026-10-01 | 处置 |
| --- | --- | --- | --- |
| `Manage/Hapi_Claude_Manage.sh` | 最新提交 **451**，更早三个 200 | master **451** | 入口固定走 GitHub 源（`xdm cc` + 主菜单 `H`） |
| `Manage/OtherFunctions.sh` | 新、旧提交均 **451** | master **451** | 入口固定走 GitHub 源（主菜单 → BOT → 其他功能） |
| `Manage/BOT-PlugIn.sh` | 新、旧提交均 **451** | master **451** | 仓库内**零引用**（孤儿文件），未处理 |
| `Manage/SYS_Manage.sh` | 200 | 23:37 **451** → 23:46 同一 blob **200** | 入口固定走 GitHub 源（`xdm sys` + 主菜单 `S`） |
| `AGENTS.md` | **451** | **200** | 无脚本引用它，只影响 gitee 网页端打开文档 |
| `Main.sh` 实际取用的其余 10 个目标 | 200 | **全部 200** | 保持走 gitee 不动 |

「其余 10 个目标」= `version` + `Manage/Main.sh` 自身 + 8 个功能脚本（meme_generator / BOT_INSTALL / Sayu_Bot /
Lagrange_OneBot / NapCat / BOT-PKG / BOT-NODE.JS / GitBot）。

⚠️ **451 不是「某个 blob 被永久拉黑」，状态会在分钟级来回翻**。2026-10-01 实测：同一个文件 10 分钟内从 451 变回 200；
而 2026-09-29 记着是 200 的**旧** blob，当天再测反而变成了 451。两条推论：

- 别因为一次 451 就断言「gitee 上这个仓库废了」——**正确动作是换源**，不是等它恢复；
- 也别因为一次 200 就断言「已经修好了」——**入口一旦改走 GitHub 源就不要改回来**（判定阈值是"曾经被拦过"，不是"此刻是否 200"）。

镜像/代理本身的可用性实测快照见 `docs/GitHub加速镜像与源可用性-实测记录-2026-09-29.md`（该文件是**带日期的快照**，不是长期结论）。

**取件点全清单（改源前先看这张表）**——`Manage/Main.sh` 里从 gitee 取件的地方一共 **4 类**，
上面那版「grep `GitMirror}/raw/master/Manage`」的老脚本**只能覆盖第 1、2 类**，第 3、4 类会漏掉：

| # | 位置 | 取什么 | 现状（2026-10-01） |
| --- | --- | --- | --- |
| 1 | `xdm <子命令>` 入口：`sys` / `meme` / `SWPKG` / `sayu` / `lag` / 临时 `NapCat` | `Manage/*.sh` | 除 `sys` 外走 gitee |
| 2 | 主菜单分发：`H` / `S` / `N` / `E` / 早柚 / 其他功能 | `Manage/*.sh` | 除 `H` / `S` / 其他功能外走 gitee |
| 3 | **批量安装**（两处：`BOT-PKG.sh BOT_INSTALL.sh BOT-NODE.JS.sh`，另一处再加 `GitBot.sh`） | `URL=` 按 `ping gitee` 二选一 | 走 gitee（4 个文件当前都 200） |
| 4 | **自更新 `UPDATE()`** | 远端 `version` + `Manage/Main.sh` | 走 gitee（当前都 200） |

复测脚本（覆盖全部 4 类）：

```sh
GITEE=https://gitee.com/Misaka21011/Yunzai-Bot-Shell/raw/master
for f in version install.sh AGENTS.md README.md \
         Manage/Main.sh Manage/SYS_Manage.sh Manage/meme_generator.sh \
         Manage/BOT_INSTALL.sh Manage/Sayu_Bot.sh Manage/Lagrange_OneBot.sh \
         Manage/NapCat.sh Manage/BOT-PKG.sh Manage/BOT-NODE.JS.sh Manage/GitBot.sh \
         Manage/Hapi_Claude_Manage.sh Manage/OtherFunctions.sh Manage/BOT-PlugIn.sh; do
    printf '%-30s %s\n' "$f" "$(curl -sL -o /dev/null -w '%{http_code}' --max-time 20 "$GITEE/$f")"
done
```

**写新入口的规则**：目标文件在 gitee 不是 200，就固定写成
`bash <(curl -sL ${Git_proxy}https://raw.githubusercontent.com/misaka20002/Bot-Install-Shell/master/Manage/xxx.sh)`，
但 **`MirrorCheck` 仍必须调用**——它负责设置 `Git_proxy`（CN / 探测失败 = `https://gh-proxy.com/`，海外 = 空串直连）。
`git clone` 类走 `GithubMirror_*`，与本条无关。

⚠️ **第 3、4 类没有 GitHub 兜底（当前最大的残留风险）**：它们写的是
`if ping -c 1 gitee.com … then <gitee 源> elif ping -c 1 github.com … then <GitHub 源> fi`，
**只要 gitee 能 ping 通就只试 gitee**，返回 451 时不会自动回落到 GitHub：

- **第 3 类（批量安装）**：`bash <(curl …)` 执行到拦截页 → 退出码非 0 → 被 `until` 捕获重试，**试满 3 次后 `exit`**（连 xdm 一起退出）；
- **第 4 类（自更新）**：`UPDATE()` 的四重校验（`HTTP_CODE=200` + 文件非空 + `grep -q "old_version="` +
  `bash <temp> help` 输出含「呆毛版」）会把 451 挡下来，**不会把拦截页装成 `/usr/local/bin/xdm`**；
  但它只会打印「更新失败，已跳过更新」并**停在旧版**，不会去试 GitHub。

这 4 个文件当前都是 200，所以没动。**但凡改动 `Manage/Main.sh`，必须连带复测第 3、4 类** —— 自更新尤其致命：
它一旦被拦，等于「修复已经推上去了，但服务器永远刷不到」（再叠加下面那条版本门槛）。

**代理变量**：全局代理已由 `ghfast.top` 换成 **`https://gh-proxy.com/`**（`MirrorCheck` 的 CN 分支与
「探测失败」兜底分支各一处；`install.sh` 的手动选项 2 同样是 gh-proxy.com）。
换代理必须**全仓库一起换**（`grep -rn "ghfast" .` 除了注释文字应为空），别只改一处。

⚠️ **更根治的做法（尚未做）**：这些 `bash <(curl -sL …)` 本身违反下面「失败路径」第 5 条——
没有 `-f`（4xx 会被当成功继续）、没有 `bash -n` / 关键标记校验（空文件、拦截页面会被直接执行）。
要修就统一成 `mktemp` + `curl -fL --connect-timeout … --max-time … --retry …` + 内容校验 + 失败明确报错；
注意**只加 `-f` 反而更糟**：body 变成空，bash 什么都不执行、退出码 0，失败被静默吞掉，
必须同时补一条明确的失败提示（或回退到另一个源）。

⚠️ **推到服务器还有版本门槛**：见下文「`Manage/Main.sh` 专属约定 → 版本号」——改了 `Manage/Main.sh`
却不提版本，服务器上的 `/usr/local/bin/xdm` 自更新判据（远端 `version` ≠ `old_version`）永远不成立，
改动根本不会滚过去。镜像决定能不能下到，版本决定要不要下，少一半都不行。

### 系统级改动：默认不做

- **不要改写 `/etc/resolv.conf`**：会破坏 systemd-resolved / Docker / 内网 DNS，且卸载不恢复。访问 GitHub 走镜像变量。
- **不要覆盖 `$HOME/.pip/pip.conf` 等全局 pip 配置**：pip 镜像只写进本项目的 venv（`venv/pip.conf`，pip 会优先读它）。
- root 写的含密钥文件（如 `config.toml`）创建后 `chmod 600`；`/tmp` 下的临时脚本用 `mktemp` 独占路径（`chmod 700`），避免被其他本地用户抢占路径或构造符号链接。
- 删除任何目录前先确认**所有权**：只能删「本轮自己创建/接管」的目录，判据见 `docs/agents/meme-generator.md`「目录所有权」。

### 交互提示约定

- 提示一律**中文**，配色沿用 `echo -e ${green}…${background}` 风格。
- `[Y/n]` = 默认 **是**（`case` 里 `N|n)` 走否分支，其余含直接回车走是）；`[y/N]` = 默认 **否**。两者不要混用。
- **未加引号的 `echo` 里不要出现 ASCII 的括号或尖括号**：`echo -e ... (1-65535): ...` 会让 bash 报
  `syntax error near unexpected token '('`；`echo -e ... db_<uin> ...` 里的 `<` 会被当成**输入重定向**，
  报 `uin: No such file or directory` 并让**整行静默不输出**（2026-10-20 踩过）。要么给整串加引号，要么改全角括号。
- 密钥输入用 `read -rsp`（不回显），不要用 `read -p` 把密钥留在终端和历史里。

### 编辑与 EOL 约定

- **行尾：对象库统一 LF，工作区随平台落地；单个文件内不许混用。**
  `.gitattributes` 现在有两行：`* text=auto`（任何系统提交都归一化成 LF）+
  `tests/**/*.sh text eol=lf`（测试脚本强制 LF，否则 `bash tests/...` 直接报 CR 相关错误）。
  本机 `core.autocrlf=true`，所以 **Windows 工作区里 `Manage/*.sh`、`install.sh` 是 CRLF，`tests/**` 与 `.md` 是 LF**
  ——两种都合法，`git diff` 里那句 "LF will be replaced by CRLF" 警告是正常的。
- 编辑时**按文件当前的行尾定点替换**，不要整文件重写：
  - 用 node/python 改文件时先看该文件用 `\r\n` 还是 `\n`，按原样切分/拼回；
  - 一次性 `read → join("\n") → write` 会把整份文件的行尾换掉；`git diff --stat` 里出现「整份文件 +N/-N」就是这个症状
    （2026-10-19 真踩过：4888 行新增 + 4888 行删除），用 `git checkout -- <file>` 重来，别硬提交。
- 改完确认没有混行：`bash tests/static-checks.sh <file>`（混行会让 bash 在 CR 处报错，这个检查会直接点名）。
- **用 node 改文本时用 `split` / `join` 定点插入，不要 `String.replace`**：替换串里的 `$&`、`$'`
  以及「`$` 紧跟反引号」都会被展开成"匹配位置前后/附近的原文"。2026-10-20 就是替换串里带了
  `` `^}$` `` 这一段，把 `AGENTS.md` 的整份正文写成了两份（症状：`git diff --stat` 显示 +803 行）。
  现在 `tests/static-checks.sh` 会检查 `.md` 的重复同级标题，专挡这种「整段写两遍」。
- 函数内变量尽量 `local`；避免用全局变量在函数间传参（历史上 `Tmux_Name` / `repo_path` / `original_url` 都因此互相覆盖过）。

### 验证方式

改完任何 `Manage/*.sh` 的最低要求：`bash tests/static-checks.sh`（`bash -n` + heredoc 里的 node 语法 + 行尾一致 + `.md` 重复标题 + **本文档体积上限 40KB**，秒级）。
行为回归：`bash tests/<脚本名>/run.sh`（默认全组；`--only A,B` 只跑指定组；`--log FILE` 指定进度日志）。NapCat 全量 42 条约 80s，可以直接跑。
超过 150s 时套件会自己提示是慢在宿主的 `rm` 包装还是断言里的 fork，见 `docs/验证方式.md`。
**本文档超过 40KB 会被 `static-checks` 挡下**：细节写进 `docs/agents/` 分册，这里只留 1-2 行指针。

各组断言覆盖什么、`tests/meme_generator/run.sh` 的 G 组为什么默认停跑、`--mutate` 为什么不再使用、
以及各脚本的实测耗时，见 `docs/验证方式.md`。

## `Manage/Main.sh` 专属约定

### 版本号（改 Main.sh **必须**一起提版本）

- ⚠️ **凡改动 `Manage/Main.sh`，必须同时 bump 版本号**，两处一起改、且必须**相等**：
  1. 仓库根 `version` 文件的 `version:` 行（顺手把 `date:` 改成当天；它只在安装界面显示，不参与判定）；
  2. `Manage/Main.sh` **第 1 行**的 `old_version="…"`。
- 原因（`UPDATE()` 的判据）：`xdm` 每次启动都会拉远端 `version`，**只有 `new_version != old_version`** 才去下载
  新的 `Manage/Main.sh` 覆盖 `/usr/local/bin/xdm`。两处相等 = "已是最新" = **服务器永远拿不到本轮修复**，
  而且**不会有任何红灯**（`install.sh` 也不比版本，它只把远端 `version:` 打印成 `v1.1.106 (date: 20260929)`）。
  所以「改了 Main.sh 却没提版本」= 改了个只存在于仓库里的版本。
- 分发链路见本节「分发方式」与上文「镜像源与『现场拉取再执行』入口」——两者是同一件事的两半：
  **镜像决定能不能下到，版本决定要不要下**。
- `install.sh` 里**没有**硬编码版本号（版本一律来自远端 `version` 文件），所以提版本只需动上面两处。
- 历史约定：`version` 与 `date` 一直是一起改的（`git log --format=… -- version` 可核对，如 `1.1.105 / 20260618`）。

### 分发方式（现场拉取再执行）

- `xdm <子命令>`（`cc` / `meme` / `sys` / `sayu` / `lag` / …）与主菜单里的每一项，都是
  `bash <(curl -sL ${URL}/xxx.sh)`——**现场拉取、不落地**。推论：① 每个 `Manage/*.sh` 必须自包含；
  ② 拉取源的选择按上文那张 gitee 451 表来（非 200 的固定走 GitHub 源 + `${Git_proxy}`）；
  ③ 这些 `bash <(curl …)` 没有 `-f`、没有校验，远端返回错误页会被当脚本执行。
- ⚠️ **同一脚本常有两处入口**：`xdm cc` 与主菜单 `H. Hapi/Claude 管理` 拉的是同一个
  `Hapi_Claude_Manage.sh`；`OtherFunctions.sh` 在主菜单 → BOT → 其他功能。**改拉取源时两处都要改**，
  否则会出现"命令行好了、菜单里还是坏的"（2026-09-29 就是这么先漏了一处的）。

## `Manage/meme_generator.sh` 专属约定

自更新、安装状态判定与修复模式、强制覆盖、仓库与镜像地址、目录所有权、服务停止、配置文件读写——
改这些行为前先读 `docs/agents/meme-generator.md`。

## `Manage/Hapi_Claude_Manage.sh` 专属约定

Codex `auth.json` / Claude `settings.json` 语义、两套配置库、凭据与临时文件、本脚本的验证方式——
改这些行为前先读 `docs/agents/hapi-claude-manage.md`（含 cc-switch 参考实现与反向教训）。

## 常见坑

- **`read` 的退出码表示「读到 EOF 了吗」，不是「读到了内容」**：`IFS= read -r x < f && 用 $x` 在文件末行没有换行符时返回非 0，
  于是「文件明明有内容」被当成失败。要取内容就直接读、只判变量本身（`read -r x < f || true` 或 `$(<f)`）；
  2026-10-22 用 `read` 校验首行，差点把正常的安装脚本判成下载失败。

- **内联 heredoc 里带运算符的 `${...}` 会被外层 shell 先展开**（2026-09-19 实测）：`cat > f <<'EOF'` 里写 `${endIndex - startIndex}`，
  即使引号包住了定界符也会报 `Bad substitution: endIndex`（普通 `${var}` 不受影响）。
  含 `${...}` 算术/表达式或反引号的脚本**先用 Write 工具落盘再执行**；往大文件里插入大段内容时，用「唯一标记 + 小段 node 脚本替换」
  （校验标记唯一 → 替换 → `bash -n` 复检），比手写超长 old_string 稳。
- `if git clone … | tee -a log` 后面**忘了 `then`**（或误跟另一个 `if`）会让整个脚本语法错误。真实事故：改到一半留下 `if … | tee` 紧跟 `if [ "${PIPESTATUS[0]}" -eq 0 ]; then …`，`bash -n` 报 `syntax error near unexpected token 'else'`。**改完务必 `bash -n`**。
- **一行多段 sed 极易写错**：`sed "s|, \"$p\"|; s|\"$p\", ||g; s|\"$p\"||g"` 是畸形的（第一个 `s` 的替换段变成 `; s`，其余被当成 flag），GNU sed 直接报 ``unknown option to `s'``。真实事故：`toggle_single_repo` 的「禁用单个仓库」因此从来没生效。多段替换改用专门的 bash 函数（`remove_dir_from_list`），不要硬写 sed。
- **`awk -v` 传值会解释转义序列**（`\t`、`\\`）；要传**字面值**请用 `ENVIRON`。写 TOML 字符串时同理：不用 `config_set_string` 就会产出非法 TOML。
- **`git reset --hard` 不是"只丢改动"**：它会覆盖/删除与目标 commit 路径冲突的未跟踪文件（见"强制覆盖本地 · 语义边界"）。别把它当成"用户文件绝对安全"的保证。
- `Manage/meme_generator.sh` 里 `log_file` 既是函数名又是变量名（bash 中两者命名空间独立），重命名要一起改。
- 主菜单允许直接进入「尚未安装」的功能项（如按 5 更新）：每个入口函数都要自己加「是否已安装」guard，不要依赖菜单显示。
- tmux 会话使用独立 socket（`tmux -L <name>`）；清理时要连 `kill-server` 和 `/tmp/tmux-$(id -u)/<name>` 一起处理，否则会留下坏 socket。
- `git_clone` / `git_update` 失败后可能留下半成品目录（有目录无 `.git`）——**只能清理由本轮操作创建的目录**；已存在的目录不得按"半成品"推断后删除。
- **`SYS_Manage.sh` 的「安装常用字体」各发行版包名不同，别照抄**：CJK 是 `fonts-noto-cjk`（apt）/ `google-noto-sans-cjk-fonts`（yum、dnf）/ `noto-fonts-cjk`（pacman）；emoji 是 `fonts-noto-color-emoji`（apt）/ `noto-fonts-emoji`（pacman）。RPM 系**改过名**：EL9 及更早是 `google-noto-emoji-color-fonts`，EL10 起是 `google-noto-color-emoji-fonts`，要写成 `dnf install A || dnf install B` 两条命令试——写进一条里时只要有一个包不存在，dnf 会 `Unable to find a match` 让**整条事务失败**。⚠️ **`google-noto-emoji-fonts` 是黑白 emoji**，装错包不报错但表情仍是方块。装完必须按 `fc-list :lang=zh` / `fc-list | grep -i emoji` 复核：字体装失败是**静默**的，只有 fc-list 能戳破（2026-09-14：`chatgpt-plugin` 的列表图在服务器上整片中文变方块，根因就是宿主没装 CJK 字体）。
- **云崽日志清理只 truncate，不删 `error.log`**：`cleanup_yunzai_logs` 处理 `$HOME/{TRSS,Miao}-Yunzai/logs`，`command.<日期>.log[.zst|.gz]` 按**文件名日期**保留 7 天；`error.log` 用 `truncate -s 0` 原地清空（log4js `file` appender 持有 append 流，`rm` 后 bot 会一直写已删除的 inode），文件不存在时**不要新建**。细节与回归命令见 `docs/开发环境清理.md`。
- `Linux/Bot-Install-*.sh` 那批系统安装脚本只装文泉驿（CentOS 走 `groupinstall fonts`），**没有 Noto 系列**——需要 CJK/emoji 覆盖时记得同步这四处。

- **`tests/<脚本>/run.sh` 只抽函数体，顶层的 `VAR="..."` 不会跟着走**：它用 awk 按 `name() {` 到 `^}$` 逐段抽取，
  所以函数里引用的顶层变量（目录清单、配置数组）在测试里是**空值**，表现是「函数静默什么都不做」而不是报错。
  这类常量要么写进函数体（`local dirs="..."`），要么在 run.sh 里显式造一份。2026-10-20 的缓存清理用例就踩了这个：
  枚举只出了 3 条，因为 `QQ_CACHE_MEDIA_DIRS` 在抽取后是空的。
- **Windows/MSYS 上每个 fork ≈ 0.25s，而 `rm -rf` 走安全网关 ≈3.7s**（2026-10-20 实测）。测试断言里少起进程：
  数行用 `mapfile` + `${#arr[@]}`，匹配用 `case "$var" in *pat*)`，读输出用 `$(< file)`；
  不要用 `grep -c` / `wc -l` / `basename` / `cut` / `date`。夹具用 `mktemp -d`（新建即空），别在开头再 `rm -rf` 一遍。
  脚本侧同理，见 `Manage/NapCat.sh` 的缓存清理：一个目录只 `find` 一次，格式化走 bash 内建。
- **`cmd | grep -q` 在 `set -o pipefail` 下会「假红」**：grep 命中即退出，写端拿到 SIGPIPE（141），pipeline 整体非零，
  断言就把「匹配成功」判成失败。要判串就先把输出抓进变量再 `case` 匹配。

## Agent skills

### Issue tracker

本地 markdown：issue / spec / tickets 都在 `.scratch/<feature-slug>/`（未经确认不要往 gitee / GitHub 开 issue）。See `docs/agents/issue-tracker.md`.

### Triage labels

五个规范角色，标签字符串与角色名相同（`needs-triage` / `needs-info` / `ready-for-agent` / `ready-for-human` / `wontfix`）。See `docs/agents/triage-labels.md`.

### Domain docs

单上下文：仓库根 `GLOSSARY.md` + `docs/adr/`（2026-10-20 起已存在）。See `docs/agents/domain.md`.
