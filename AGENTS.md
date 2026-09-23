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
| `Manage/meme_generator.sh` | meme 表情包生成器管理（本仓库当前最复杂的脚本，见下文专属约定） |
| `Manage/Hapi_Claude_Manage.sh` | Hapi / Claude Code / Codex / opencode 管理（含 Codex `auth.json` 编辑器，见下文专属约定） |
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
5. 下载 / 自更新必须：`mktemp` 临时文件 → `curl -fL --connect-timeout … --max-time … --retry …`（`-f` 让 4xx/5xx 变成失败）→ 内容校验（`bash -n` + 关键标记 + **版本一致性**）→ 原子替换（同目录 `.new.$$` 再 `mv -f`）。
   反面教材：`curl -sL url > "$目标文件"` 会**先截断**目标文件，断网时把可用脚本清成 0 字节，并把错误页当脚本装上去。
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

### 系统级改动：默认不做

- **不要改写 `/etc/resolv.conf`**：会破坏 systemd-resolved / Docker / 内网 DNS，且卸载不恢复。访问 GitHub 走镜像变量。
- **不要覆盖 `$HOME/.pip/pip.conf` 等全局 pip 配置**：pip 镜像只写进本项目的 venv（`venv/pip.conf`，pip 会优先读它）。
- root 写的含密钥文件（如 `config.toml`）创建后 `chmod 600`；`/tmp` 下的临时脚本用 `mktemp` 独占路径（`chmod 700`），避免被其他本地用户抢占路径或构造符号链接。
- 删除任何目录前先确认**所有权**：只能删「本轮自己创建/接管」的目录，见下方 meme_generator 专属约定。

### 交互提示约定

- 提示一律**中文**，配色沿用 `echo -e ${green}…${background}` 风格。
- `[Y/n]` = 默认 **是**（`case` 里 `N|n)` 走否分支，其余含直接回车走是）；`[y/N]` = 默认 **否**。两者不要混用。
- **未加引号的 `echo` 里不要出现 ASCII 括号**：`echo -e ... (1-65535): ...` 会让 bash 报 `syntax error near unexpected token '('`。要么加引号，要么改全角括号。
- 密钥输入用 `read -rsp`（不回显），不要用 `read -p` 把密钥留在终端和历史里。

### 编辑与 EOL 约定

- **按文件保持它原有的 EOL**：不要无意归一化。2026-09-19 实测基线：
  `Manage/meme_generator.sh`（2642 行 / 2642 CRLF）、`Manage/SYS_Manage.sh`（1128 / 1128）、`Manage/Main.sh`（1107 / 1107）、
  `Manage/NapCat.sh`（3281 / 3281）都是**全 CRLF**；`Manage/Hapi_Claude_Manage.sh` 现在是**全 LF**（4114 行 / 0 CRLF，2026-09-19 实测；
  这个行数每次改动都会变，**判据看 `crlf=0`**，行数只是用来发现"整文件被归一化"的异常）。
  ⚠️ `Hapi_Claude_Manage.sh` 原先记录为"已知历史例外（混行）"，**该状态已不存在**：2026-09-19 实测工作区副本已是全 LF。
  仓库里（对象库）本来就是纯 LF（`git show HEAD:Manage/Hapi_Claude_Manage.sh` 实测 0 CRLF），
  所以 `git diff` 不会出现整文件假 diff；目标平台是 Linux，全 LF 是**正确状态，不要"修回"CRLF**。
  CRLF 的那几个文件改完仍要复核没被整体归一（判据见下）。
  `tests/**/*.sh` 反过来必须是 **LF**：CRLF 会让 `bash tests/...` 直接报 `\r` 相关错误（`$'\r': command not found`）。
  **已由 `.gitattributes` 钉住（2026-09-19 实测：仓库根该文件存在，内容只有一行 `tests/**/*.sh text eol=lf`）**：
  `git check-attr text eol -- tests/meme_generator/run.sh` 返回 `text: set` / `eol: lf`。
  （历史：曾有一段时间仓库里没有这个文件，于是 Windows 上重新 checkout 后 `run.sh` 会变回 CRLF、测试直接报
  `$'\r': command not found`。现在这条已修好——判断时以 `git check-attr` 为准，别再手抄"有没有 .gitattributes"。）
  注意它**只覆盖 `tests/**/*.sh`**：`Manage/*.sh` 没有 `text`/`eol` 属性，走 `core.autocrlf=true`（本机实测为 `true`），
  即**对象库里是 LF、Windows 工作区 checkout 出来是 CRLF**，所以 `git diff` 的警告是正常的，不是"你改坏了行尾"。
- 编辑时优先**定点替换**，不要整文件重写（会产生全量 diff 假象）。改完确认同文件没有出现新的混行：
  ```sh
  node -e "const s=require('fs').readFileSync(process.argv[1],'utf8');const nl=(s.match(/\n/g)||[]).length,crlf=(s.match(/\r\n/g)||[]).length;console.log(crlf===nl?'全 CRLF':(crlf===0?'全 LF':'混行!'));" Manage/xxx.sh
  ```
  判据写成 `crlf === 0 || crlf === nl`（全 LF 也是合法状态）。
- 函数内变量尽量 `local`；避免用全局变量在函数间传参（历史上 `Tmux_Name` / `repo_path` / `original_url` 都因此互相覆盖过）。

### 验证方式

```sh
# 1) 语法检查（必备，每次改完都要跑）
bash -n Manage/xxx.sh

# 2) 行为回归：跑仓库内的测试（tests/<脚本名>/run.sh），它从脚本里抽出函数体、再造数据跑断言（不需要 root、不联网）
#     bash tests/meme_generator/run.sh              # 默认：A~F + H 断言（**G 组已默认跳过**）
#     bash tests/meme_generator/run.sh --only A,B   # 只跑指定分组（日常最常用）
#     bash tests/meme_generator/run.sh --with-git   # 只有确实改了 git_clone / git_update 才用（G 组已停跑，见下）
#     --log FILE 指定进度日志（默认自动生成）；每条断言即时 append，超时/被杀也能看出停在哪
#    ⚠️ **测试范围已收窄（2026-09-13，用户决定）**：
#      · **不再跑 G 组**（真实 git 行为：造裸仓库 + 多次 push + force-push）。默认已跳过，要跑必须显式 `--with-git`；
#        G 组断言仍在代码里，但**不再随日常回归执行**，属于**未维护**状态（别把它当成"有保护"）。
#      · **不再跑变异验证**（`--mutate`）。参数保留（代码没删），但**不要跑、也不要再提议**。
#      随之而来的唯一代价：新断言的"有效性"不再由变异自动证明，所以**新断言必须手工拿反例自证**
#      （临时改坏对应生产代码 → 跑一次确认变红 → 改回），否则就是"看起来对"的断言。
#    当前 meme_generator.sh 的断言覆盖（run.sh 里按 A~H 分组，--only 可单独跑；**G 组已默认停跑/未维护**）：
#      A 运行判据      is_meme_process_running 把前台 watchdog 算作"运行中"（覆盖 sleep 2 间隙）
#      B 前台身份      PID 身份 fail-closed；register_foreground_watchdog 取不到 boot_id 必须失败且不落地文件；
#                      Foreground_Start 准备阶段失败时不登记身份（用标记文件测**登记时机**，不是测文件残留）；
#                      stop_meme_service 在「watchdog 仍存活」或「身份不可信但 PID 还活着」时都必须报失败且保留 PID 文件
#      C 安装状态      is_meme_install_complete 必须证明 pip 包真的装进 venv（venv 文件在 ≠ 装好了）；
#                      修复模式下 pip 再次失败后，再选「安装」仍能重进修复（不能被「您已安装」挡住）；
#                      重装依赖成功后选「重新启动」必须真的走到 start_meme_generator（不能撞上 restart 的
#                      「未启动无法重启」而根本没启动）；install 用例不得越界到「安装字体」写 /usr/share/fonts
#      D 配置写入      write_default_config 原子写入 + 权限收紧；rewrite_config 备份失败必须中止且不动原配置；
#                      rewrite_config 的「接线」（真的调用 helper）也被验证——只测 helper 会漏掉接线被删
#      E 配置读写      config_get/config_set 段内定位、注释保留、未命中 key/section 返回非零；
#                      config_set_string 的 \ 与 " 转义形式（断言的是转义结果，不是"能被 TOML 解析器读回"）；
#                      meme_dirs 增删链路
#      F 自更新/版本   ⛔ **「SCRIPT_VERSION 必须高于 HEAD」那条断言已删除**（2026-09-13 用户决定）：
#                      它与提交流程耦合——刚 commit 完工作区 == HEAD，必然判红，是假警报；
#                      该约定改为**纯文档**（见「自更新」小节：改脚本要提版本，提交前自查，没有红灯提醒）。
#                      仍在跑的是：同版本但内容损坏的系统脚本必须重下；
#                      镜像返回旧版本必须跳下一个源；全源版本不符必须失败且不覆盖现有脚本。
#                      （F 组编号从 F2 起、**故意不重排**：本文多处引用 F5~F9。）
#      F cron          `read_current_crontab` 统一读取层：确认「no crontab」→ 幂等成功；**非零读取错误
#                      （含只有 stderr 的 permission denied）必须 fail-closed**；`remove_meme_cron` 在
#                      「meme 是唯一一条 cron」时必须删成功（pipefail 老坑）；读不到时 append / toggle /
#                      setup（启用分支）三个调用点都必须拒绝写入（否则会把用户整份 crontab 覆盖成一行）；
#                      F9 `setup_auto_update` **关闭分支**失败时必须**如实返回非零**（读取失败 / 删不掉各一条），
#                      并带一条正向对照（正常关闭必须返回 0）。为什么必须直接断言返回码、端到端抓不到：
#                      它的调用点 `Tmux_Start` 那个分支最后一条语句是 `echo`，返回值在那一层被吃掉
#      H 公网 IP       is_valid_ipv4 拒绝超段/缺段/多段/HTML/空白等垃圾输入；load_public_ip_cache 只读缓存
#                      文件（零网络），缺失/损坏/TTL 过期一律拒绝且清空 PUBLIC_IP；refresh_public_ip_bg 只有
#                      合法 IPv4 才原子写缓存（错误页绝不落盘，POST ip.3322.net → GET api.ipify.org 兜底）；
#                      init_public_ip 缓存新鲜时绝不触发后台获取（「不要每次进主菜单都 POST」的保证）、
#                      缓存缺失/过期才补一发（curl 桩掉，不联网）。2026-09-13 新增，三条变异反例已自证
#      G Git 边界      ⛔ **默认不跑（未维护）**：只有确实改了 git 相关代码时才 `--with-git` 跑一次。内容是——
#                      git_clone 目录所有权（已存在非空目录必须被拒绝且不删文件）；
#                      git_update 面对**真正的非快进改写**（上游 reset 回 A、再造 C、强推）仍能对齐远端 HEAD；
#                      已知边界：与远端新增 tracked 同名的未跟踪文件会被覆盖（断言它确实被覆盖），不冲突的保留；
#                      git_update 全部地址失败后 origin 被恢复为权威地址
#    实现要点：用函数桩替换 curl 与进程探测函数；git 用本地裸仓库（不依赖网络）
#    - ⛔ **变异验证已停用（2026-09-13，用户决定）**：不要再跑 `--mutate`，也不要再提议。参数与下面的清单**保留**，
#      作为历史记录 / "将来若真要恢复该怎么做"的参考。新增或修改断言的有效性，改由**手工反例自证**
#      （临时改坏对应生产代码 → 跑一次看到变红 → 改回）。理由：这个脚本文件本来就小，G 组 + 变异矩阵的耗时
#      （本机 ≈1 小时）与收益不成比例。
#    - 变异验证（设计意图：每条关键断言都要能在注入对应 bug 后失败，否则就是「恒真断言」）。
#      当前 14 条（**以代码为准，别手抄**：`grep -c 'run_mutation "' tests/meme_generator/run.sh`——本节数字漂过好几次）。
#      `run_mutation name old new <groups>` 让每条只跑它涉及的分组，比跑全部组显著快；但**不是"秒级"**：
#      本机（Windows/MSYS，进程创建极慢）实测**≈4 分钟/条**，只有换到正常 Linux 才可能降到秒级。
#      ⚠️ 下表除标注「已实测」的那几条外都是**预期映射，不是实测结论**。换到正常 Linux / CI 跑 `--mutate` 才能把 14 条全部验完。
#      A  去掉 is_meme_process_running 的前台判据      → 「sleep 2 间隙算运行中」失败   ← 已实测会被抓住
#      B  把 watchdog 登记挪到 cd/激活 venv 之前       → 「venv 失败前未写 PID」失败       （预期）
#      B  stop_meme_service 改回「先删身份再确认退出」  → 「仍存活时误报停止成功」失败     （预期）
#      B  去掉「身份不可信就不算停止成功」              → 「旧式一行 PID 被删掉」失败       （预期）
#      C  安装判据退回只看 .git                        → 「进修复模式 / 未被误判为已安装」失败（预期）
#      C  去掉 pip 包判据                              → 「包没装上却判为已完成」失败       （预期）
#      D  rewrite_config 备份失败仍继续覆盖             → 「备份失败仍继续执行」失败         （预期）
#      D  rewrite_config 丢掉 write_default_config 接线 → 「原内容已被替换」失败             （预期）
#      C  重装依赖后回调 restart_meme_generator         → 「真的走到 start / 未出现未启动无法重启」失败（预期）
#      F  remove_meme_cron 退回 `grep -v | crontab -`   → 「唯一一条 cron 删掉却报失败」失败 ← 已实测（1 条断言判红）
#      F  read_current_crontab 把「非零」当成「没有 crontab」→「stderr-only 读取错误被当成没有」失败 ← 已实测（7 条判红）
#      F  download_script 去掉版本一致性校验            → 「写回旧版本 / 全源不符却成功」失败 ← 已实测（3 条判红）
#      F  setup_auto_update 关闭分支去掉两个如实返回    → 「读不到 / 删不掉却返回 0」失败      （预期）
#      G  git_update 把 reset --hard 改 --soft          → 「本地未对齐被改写后的远端」失败   （预期）
#    已实测结果（2026-09-13，**本轮实跑**，被测 = 上面那 14 条变异 + 本轮的 cron / case / rm / setup 返回码 修复）：
#      - `bash tests/meme_generator/run.sh`（= 旧 `--fast`；现在**默认就跳过 G 组**）：**pass=62 fail=0 skip=2，rc=0**
#        （删掉 F1 版本断言后由 63 → 62）；两个 skip = Windows 不强制 POSIX 权限位 + G 组默认不跑。
#        （同日在 Linux 上由用户复跑：pass=59 fail=0 skip=1——Linux 能跑权限断言，所以多 1 pass、少 1 skip；
#        当时还没有 F9 的 5 条。跨平台对比请看 pass/fail 而非绝对值。）
#      - ⛔ 2026-09-13 起 **G 组与变异验证停跑**（用户决定，见上面「测试策略」）。上面这次是**最后一次含 A~F 的实测**；
#        G 组自此**没有任何实测记录**，其断言视为**未维护**，不要引用为"已验证"。
#        本机跑法（PATH 里的 `bash` 是坏 shim，必须用真实 bash 并把它的 bin 目录放进 PATH）：
#          PATH="/c/Users/<user>/.workbuddy/binaries/PortableGit/versions/<ver>/usr/bin:/c/Users/<user>/.workbuddy/binaries/PortableGit/versions/<ver>/bin:$PATH" \
#            HARNESS_TIMEOUT=600 bash tests/meme_generator/run.sh --log /tmp/mg.log   # 默认即 A~F
#      - **含 git 组的全量 + `--mutate` 全量变异矩阵（长任务：本机 ≈4 分钟/条 × 14 条 ≈ 1 小时）本轮没有跑**——
#        按项目约定"长任务先问"，且用户已明确表示小脚本没必要跑这么久，**不要再主动提议**。
#        已跑的是**最小范围的定向变异**：`--fast --only F --mutate` → **caught=3 missed=0**（当时 F 组 3 条全被抓住，
#        分别报了 1 / 7 / 3 条 `NOT OK`；耗时 11m49s）。F 组现在 4 条，新增的那条**还没实测**。
#        于是下表里 A（早先实测）与 F 的前三条（实测）是**实测结论**；其余 10 条
#        （B×3 / C×3 / D×2 / F×1（新增）/ G×1）仍**只是预期映射，不是实测结论**。
#        变异 harness 的"超时 / 崩溃"负向分支（rc=124、rc≠1）也还没实测
#        （要故意构造才会触发，属已知未覆盖项）。
#        （历史记录：加固前跑过一次含 git 的全量，pass=55 fail=0 skip=1。）
#      - 教训：本节一度写着"F 组已验证"，而实际上是空的——F8 的 `case` 模式带空格（语法错误）让整个 harness
#        构建失败，**F 组从来没执行过**。所以清单里的每个"已验证"都必须能对应到一次真实运行的数字。
#    - **变异的分组隔离必须自检**：harness 的 prelude 会把 `ONLY` / `LOG_FILE` 的默认值**写进生成的文件**，
#      所以 `run_mutation` 用 `ONLY=<groups> LOG_FILE= cmd` 覆盖时，prelude 必须"只在未设置时才填默认值"
#      （用 `${VAR+x}` 判断，**不能用 `:-`**——变异故意要传空 `LOG_FILE`，`:-` 会把空串也当成没设置）。
#      只改这一处还不够，`run_mutation` 里另加三条硬校验：① 变异 harness 必须**退出码 1**（= 有断言失败地正常收尾；
#      124 = 超时、其它码 = 基础设施崩坏）且输出里有完整的 `TOTAL: ... fail=<非零>`——否则"中途超时/崩坏 +
#      之前碰巧打印过一个 `NOT OK`"就会被误判成 caught；② 变异输出里不得出现未选中分组的标题
#      （"别的组里某条 `NOT OK`"同样会造成**假 caught**）；③ 变异运行不得让主进度日志行数变化。
#    脚手架坑（都踩过）：
#    - ⚠️ **删断言前先查它顺带建立的 fixture**：断言块经常顺手定义后面用例要用的变量 / 桩 / 现场。
#      真实事故（2026-09-13）：删掉「版本必须高于 HEAD」那条断言时，连带删了它定义的版本变量，
#      而 F2/F3 正拿这个变量造 curl 桩 → 立刻 4 条 `NOT OK`（pass=58 fail=4），**跑一遍才发现**。
#      规则：① 删之前 `grep` 一遍该块定义的所有名字；② 删完**必须跑对应分组**；
#      ③ 共享 fixture 在定义处标注「别删 + 谁在用」。（当时已把该变量改名为 `cur_ver` 并加了说明。）
#    - 不要 `source` 整个被测脚本：顶层守卫遇非 Linux 会 `exit` 掉测试进程，末尾 `mainbak` 会死循环。
#      抽取一律**按内容定位**：守卫起点 `cd "$HOME" || exit 1` → 探测块起点 `^URL=` → 正文起点 `^config=`
#      → 终点 `^function mainbak`。**不要写死行号**——脚本持续插函数，行号一漂就静默取错范围。
#    - `Foreground_Start` 是嵌在 `start_meme_generator` 里的嵌套定义，主菜单里直接调不了；
#      抽函数体时按「函数体内各行都缩进、闭合 `}` 在行首」来切，比数花括号可靠（体内满是 `${}` 展开）。
#    - 「不得留下 PID 文件」这类断言不能用「跑完后 `[ ! -f PID ]`」判断：
#      `trap ... EXIT` 会在子 Shell 退出时把文件删掉、把 bug 掩盖掉。要在 `activate_meme_venv` 的桩里
#      检查「此刻 PID 文件是否已存在」（写标记文件），才真正测到登记时机。
#    - 抽不到函数时 `if <函数名>` 会因「command not found」而**假绿**（被当成"未运行/未完成"）：
#      harness 开头必须前置自检，关键函数/变量缺一个就直接 FAIL 退出。
#    - 变异要施加在**源脚本副本**上再重新抽取：只改"抽出来的库"会漏掉嵌套的 Foreground_Start。
#    - 变异字面量匹配前先 `tr -d '\r'`：Windows 工作区是 CRLF，按 LF 写的多行字面量永远匹配不上。
#    - git 类断言每次运行前必须重建裸仓库：上一轮 `reset --hard` 已经改掉现场，
#      否则 `reset --soft` 这类变异会因工作区早就是远端内容而抓不住。
#    - ⚠️ **`case` 的模式里只要含空格就必须加引号**：`case "${out}" in *无法读取当前 crontab*)` 是**语法错误**
#      （bash 报 `syntax error near unexpected token 'crontab*'`；把模式换成 ASCII 的 `*a b*` 一样报），
#      正确写法是 `*"无法读取当前 crontab"*)`。踩到的后果不是"这条断言红了"，而是**整个 harness 构建失败**
#      （`build_harness` 末尾的 `bash -n "$2"` 挡住），表现为只打印一句「harness 生成失败」，退出 2 ——
#      也就是说加上这段断言的那一轮，F 组（含 F8）**从来没被执行过**。
#      教训：`bash -n` 通过 ≠ 断言真的跑过；**新增断言后必须至少跑一次对应分组**（`--only F`），
#      否则"文档声称有保护、实际从未执行"会一直躺着。
#    - ⚠️ **prelude 用的是未加引号的 heredoc**（它本来就需要 `WORK` / `ONLY` / `LOG` 在这里展开），
#      于是正文里**反引号是命令替换、会真的执行**，`${...}` 也会被展开：
#      在注释里写一对反引号包住的内容，就会看到 `run.sh: line 159: groups: No such file or directory`
#      并把注释文字替换成空。要写字面量必须转义（写成 `\`` 与 `\${VAR+x}`）；同理，别指望这个 heredoc 里的
#      注释能原样保留 `$` 和反引号。

# 3) 确认没有整文件重写导致的换行/全量 diff
git diff --stat && git diff --check
```

- **可复用的测试必须写进这个 Git 仓库**，不要只留在系统临时目录：测试是交付物的一部分，要能被审查、能随被测脚本一起演进。
  只有一次性的探针（例如只为确认某条 Git / 系统真实行为的临时实验）可以放临时目录、用完即删。
  教训：前几轮把断言写在临时目录、用完就删，结果没人能复核「到底测了什么、还测不测得动」。
- 测试的存放与运行约定：
  - **位置**：仓库根下 `tests/`，按被测脚本分子目录，如 `tests/meme_generator/`。
  - **入口**：每个套件一个 `tests/<脚本名>/run.sh`，用 `bash tests/<脚本名>/run.sh` 跑完并打印 `pass/fail` 汇总，
    **失败必须以非零退出码返回**（这样能直接接 CI，或串进 `&&` 链）。
  - **自包含**：不引入新依赖，只用 bash + 系统已有工具（`git` / `sed` / `awk` / `node` 等按需）。
  - **断言质量**：每条核心断言都要带负向对照，并且能用「注入对应 bug 的变异」证明它会失败（见上文"变异验证"）。
  - **路径**：测试里一切仓库路径都要能按仓库实际位置推导，不要写死开发机的绝对路径。
- **测试不要放进 `Manage/`**：`Manage/*.sh` 是「独立整包」，会被 `bash <(curl …)` 现场拉取执行；
  测试放那里既会被用户当成功能脚本，也会白白增加下载体积。测试只在仓库内跑，不随功能脚本分发。
- 没有测试框架，不要假设仓库里已有，也不要为了测试给 `Manage/*.sh` 加"测试模式"分支——
  「从源码抽函数体 + 函数桩」（见上文脚手架坑）已经够用。
- **测试策略（别误读；这条被误解过两次，其中一次很严重）**：
  - **必须做、不用问**：**快速 / 定向验证是交付的一部分，改完就该跑**——`bash -n` + `bash tests/meme_generator/run.sh`
    （默认 A~F，G 组已跳过），或按改动范围 `--only <组>`。本机实测耗时：A~F 全量 ≈6 分钟，单组也有 ≈4 分钟
    （进程创建极慢，别指望秒级）。**做 review 的那一轮同样要跑**：审查方只做静态阅读就给出"通过 / 不通过 / 可以收尾"
    的结论，是不合格的交付方式（见下面"审查回合的硬要求"）。
  - ⛔ **已停用：G 组与变异验证都不再跑**（2026-09-13 用户决定）。这是**用户的明确取舍**，不是"我懒得跑"：
    · **G 组**（真实 git 行为）默认已跳过；只有**确实改了 `git_clone` / `git_update`** 时才显式 `--with-git` 跑一次。
      停在代码里的 G 组断言属于**未维护**状态，别把它算进"有保护"。
    · **变异验证**（`--mutate`）**不要跑、也不要再提议**：本机 ≈4 分钟/条 × 14 条 ≈ 1 小时，用户原话"这么小的脚本
      没必要跑这么久的验证"。替代做法：新断言用**手工反例**自证（临时改坏 → 看红 → 改回）。
    · 万一真要跑变异：只跑涉及分组（`--only F --mutate`）、必须后台 + `--log` 落盘，并先问一句。
  - 停用前实测的耗时（留作参考，别再拿它当"要跑"的理由）：**单条变异 ≈4 分钟**、`--only F --mutate`（3 条）≈11m49s、
    14 条全量 ≈1 小时。条数一律现数，别手抄：`grep -c 'run_mutation "' tests/meme_generator/run.sh`。
  - ⚠️ **不要把"停跑 G 组 / 停跑变异"误解成"不用跑测试"**。真实事故：有一轮把整轮验证省成"我按你的要求没有运行任何测试，
    只做静态审查"，被用户明确判为**不符合**——用户原话是"其他测试还是要做的，然后审查模型也应该做测试"。
    **A~F 断言照跑，它是交付的一部分**；停掉的只有 G 组与变异这两块。
  - **结论必须标注验证级别**：任何交付里的判断都要说清哪些是**实测**（附命令与 `pass/fail` 数字）、哪些只是**静态阅读**。
    不要把静态推断写成"已验证"，也不要把"没跑"包装成"按要求"。
- **审查回合的硬要求**（评审别人（或自己）改动时）：
  1. **先跑再判**：至少 `bash -n Manage/<脚本>.sh` + `bash tests/meme_generator/run.sh`（A~F；被审改动涉及 git 才加 `--with-git`），
     或按改动范围用 `--only <组>`；用实际结果校正判断。静态阅读只用来**定位**要看的地方，不用来替代验证。
  2. **发现"文档声称有保护、测试实际没保护"时按 blocker 处理**：先跑出反例（或指出缺哪条断言），再谈改法。
  3. **本机跑测试的调用姿势**（否则会误报失败）：系统 PATH 里的 `bash` 是坏 shim（直接报 `bash: command not found`），
     harness 内部还会再 `bash "${WORK}/harness.sh"`，所以必须先用**真实 bash 的绝对路径**并把它所在目录放进 `PATH`：
     ```sh
     export PATH="/c/Users/<user>/.workbuddy/binaries/PortableGit/versions/<ver>/usr/bin:/c/Users/<user>/.workbuddy/binaries/PortableGit/versions/<ver>/bin:$PATH"
     HARNESS_TIMEOUT=600 bash tests/meme_generator/run.sh --log /tmp/mgtest.log; echo "EXIT=$?"
     ```
     长一点的运行一律 `run_in_background` + 轮询 `--log`；前台干等必然被工具超时打断。
- **测试必须"不会卡住"**，三条硬保证缺一不可（都踩过：一次前台跑长套件看起来像死循环，实际是被超时杀掉 + 输出缓冲丢失）：
  1. harness 开头 `exec 0< /dev/null`：任何漏写重定向的 `read` 立刻 EOF，绝不因 stdin 是未关闭的管道而永久阻塞；
  2. 每次 harness 运行都套 `timeout`（`HARNESS_TIMEOUT`，默认 300s）并把 rc=124 明确报成「超时，可能有死循环」。
     **本机没有可用的 `timeout` 必须直接失败退出**，绝不能悄悄退化成"无限运行"——那等于没有这条保证。
     能力探测要**真的超时一次**（`timeout 1 sh -c 'sleep 5'` 后校验 rc=124）：只跑 `timeout 1 true` 只能证明
     "有个叫 timeout 的程序能跑通 true"，证明不了它真会终止超时的子进程——而"有界"靠的恰恰是这一点；
  3. 每条断言**即时追加**到 `--log` 指定的日志（`printf ... >> log`，追加写=不缓冲），进程被外部杀掉也能看出停在哪一步。
     默认日志**故意放在 `WORK` 之外**（`/tmp/meme_generator_test.<pid>.log`）：`WORK` 会被 EXIT trap 整个删掉，
     日志跟着消失就失去了"被杀了也能看进度"的意义。成功才删默认日志，失败 / 超时 / 被杀一律保留；
     `--log` 指向不可写路径要立刻报错退出，别静默把这条保证丢掉。
- **凡是会碰"系统级副作用"的生产函数，测试里都必须显式 stub**（进程 / tmux socket / cron / 网络 / 系统目录）。
  **只把 `HOME` 指到临时目录不等于隔离**：tmux socket 名与 `/tmp/tmux-<uid>/<name>` 都不受 `HOME` 影响——
  不 stub `tmux_kill_session`，跑一次回归就可能把开发机上真正在跑的那个 meme 服务停掉。
  当前 harness 固定 stub：`proc_boot_id` / `proc_starttime` / `meme_pid` / `meme_curl` / `tmux` / `tmux_ls` / `tmux_new` / `tmux_kill_session`；
  用例内按需再 stub `curl`（自更新）、`crontab`（cron）、`cp`（备份失败）。
- **测试绝不允许在真实机器上产生"安装 / 系统级写入"**。这是结构性要求，不能靠"碰巧没跑到那一步"：
  1. **所有指向系统绝对路径的全局变量都要钉到临时目录**。最典型的是 `SCRIPT_SYSTEM_PATH`（生产默认
     `/usr/local/bin/meme_generator.sh`）：harness 里必须覆盖成临时文件，否则任何一条误调
     `ensure_script_saved` / `setup_auto_update` / `toggle_auto_update` 的用例，都会真的下载并替换系统脚本。
     `install_path` / `config` / PID 文件都以 `$HOME` 为根，靠 HOME 重定向即可覆盖；
     但 **`/usr/share/fonts`（字体安装）没有变量可钉**——所以 harness 里对 `mkdir` / `cp` 做了 **fail-closed 保险桩**：
     参数命中 `/usr/share/fonts` 就返回 97 并打 `BLOCKED_SYSTEM_WRITE`，其余参数用 `command` 原样透传；`fc-cache` 直接 stub。
     这样即使将来 production 真的越过"pip 失败点"走到字体安装，也是**先被拦住**而不是先写坏开发机；
     同时保留一条输出断言（一旦输出出现「安装字体」就报错）来暴露越界。只靠"事后检查输出"是不够的——那时系统写入已经发生了。
  2. **harness 开头 fail-closed 校验隔离前置条件**：`HOME` 不在本次运行的临时目录里就直接 `exit 2` 拒绝运行，
     而不是假定"已经隔离好了"。
  实测结论（2026-09-13，跑完整套件后核对）：`~/.config/meme_generator`、`~/memeGenerator`、
  `usr/local/bin/meme_generator.sh`、`~/.pip`、tmux socket、crontab 条目**全部不存在 / 未被改动**，
  `~/.gitconfig` 与 `~/.config` 的 mtime 未变——即**本机没有被安装任何东西**。
- **绝不要在测试/被测脚本正在运行时编辑它们**：bash 是**边执行边按偏移增量读取**脚本的，
  边跑边改会让它从错乱偏移继续读，报出莫名的 `syntax error near unexpected token '}'`，甚至把 heredoc 正文当命令执行。
  要改就先等进程结束，或改完再从新副本起跑。
- **慢盘 / 模拟文件系统（例如 Windows 上经 MSYS 跑）**：一次进程创建可能几百毫秒，整套要几分钟。这**不是卡死**。
  做法：后台跑 + 轮询 `--log`；用 `--only A,B` 把范围切到最小逐组验证；配合 `HARNESS_TIMEOUT=900` 放宽上限。
- **平台差异要写进断言，别把平台限制报成生产 bug**：
  - POSIX 权限位在 Windows（MSYS/Cygwin）上不生效（`chmod 600` 后 `stat` 仍报 644）——权限类断言先做**能力探测**，不支持就 SKIP。
  - **给 git 的一切路径（含仓库地址）都先用 `cygpath -m` 转成 `C:/...`**（`git.exe` 不认 `/tmp/...` 形式的 POSIX 路径，`-C` 也要转）。
    实测结论：`C:/.../bare.git` 作为 clone 源、`remote set-url`、`fetch` 全部正常（被当成本地路径）；
    **不要加 `file:///` 前缀**——MSYS 版 git 会把它解析成 `/C:/...` 而失败。
    另外，bash 的 `/tmp/...` 与 git 看到的 `/tmp` 可能**不是同一个位置**，所以测试现场先 `cygpath -m` 再交给 git。
- **分组运行必须自带 fixture**：`--only D` 时 C 组不会跑，D 依赖的 `.git` / venv / config 必须由 D 自己建立；
  否则被测函数会在第一道守卫（`is_meme_repo_installed`）处**静默 return**，看起来像是"莫名其妙跳过了"。
- 在本机（Windows）验证时：`bash` / `sed` / `wc` 等命令可能不在 PATH（精简 shim），可用绝对路径的 `bash.exe -n` 做语法检查，用 `node -e` 做文件与字符串检查。
- **MSYS 的路径转换规则（2026-09-19 实测）**：MSYS 会转换**命令行参数**里的类 POSIX 路径，但**不转换环境变量**。
  Windows 原生 `node` 把 `/tmp/x` 解析成"当前盘符根 + `tmp\x`"（如 `E:\tmp\x`），与 Bash 眼里的 `/tmp` **不是同一位置**。
  所以：给 node 传路径一律用 `C:/Users/...` 这种带盘符的前向斜杠形式（不要用 `/tmp/...`，否则读写会落到另一个目录）；
  而往 `PATH` 里追加目录必须用 POSIX 形式（`/c/Users/...`），写成 Windows 形式不生效、会 `command not found`
  —— "假编辑器 / 假 vim 放进 PATH 却没被找到"就是踩了这个。
- ⚠️ **本机 `rm` 是宿主包装的"回收站版"，在 Windows 形式路径上会 fail-closed 地"删不掉"**（2026-09-13 实测）：
  `type rm` 显示它是经 `BASH_ENV` 注入的**函数**（`${CODEBUDDY_SAFE_DELETE_BIN_DIR}/rm`）；当路径写成
  `C:\Users\...\Temp/xxx` 这种 Windows 形式时，它 CanonicalizePath 失败，stderr 打出
  `[safe-delete][SAFE_DELETE_FAIL_CLOSED] ... "reason":"trash-failed"`，**而且文件真的还在原地**。
  本机默认 `TMPDIR` 恰好就是 `C:\Users\...\Temp` 形式，于是 harness 里所有 `rm -f` 静默失效
  （`reset_pid_file` 删不掉身份文件、`cleanup` 删不掉 WORK），A2「无身份时报运行中」、
  B1「venv 失败前已写身份文件」、B2「取不到 boot_id 却登记成功」会连着变红 ——
  而这三条的现象都能被解释成"生产 bug"，极具误导性（实测：同一套件在 `TMPDIR=/tmp` 下全绿）。
  **已修**：`run.sh` 在建 `WORK` 之前用 `cygpath -u` 把 Windows 形式的 `TMPDIR` 归一到 POSIX 形式。
  判据：stderr 出现 safe-delete 文案，或出现"删了却还在"→ 先怀疑 `rm` 被包装，不要先去改生产代码。

### Git 约定

- **不要主动 `git add` / `commit` / `push`。** 改完把改动留在工作区并汇报；用户明确说「提交 / 推送」才执行。
- commit message 风格：`fix: 中文描述` / `feat: 中文描述`。

## `Manage/meme_generator.sh` 专属约定

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

## `Manage/Hapi_Claude_Manage.sh` 专属约定

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
  - `official`（默认，菜单 7 写官方 auth.json 用）额外要求：模式解析为 `chatgpt`/`chatgptAuthTokens`，且三个 token
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
  - **预览（`hapi_show_claude_config`）必须用 Node 递归脱敏，禁止再用 sed 正则**：旧实现只认三个固定键，
    ① token 里带 JSON escaped quote 时后半段明文泄漏；② `OPENROUTER_API_KEY` / `OPENAI_API_KEY` /
    任意 `*_SECRET` / `*_PASSWORD` 全部明文打印。更糟的是它是「先预览、后清理」——旧配置里残留的认证键
    会先被打印出来（P1，2026-09-23 审查环境实跑证实）。JSON 解析失败时**不回退打原文**，只报
    「不是合法 JSON，为避免泄露敏感字段，不显示原始内容」。
    ⚠️ `isSensitiveKey` 在脚本里有 **5 份副本**（Claude live 预览 / Claude profile 预览 / Codex 的 3 处），
    **改一处必须同步其余四处**——2026-09-23 就踩过两次：① 只改了一份（另外几份首行写法不同，
    `replace_all` 没匹配到），`password` 条款漏了出去；② 漏掉了 profile 预览这条路径，
    它在菜单 4/5 的**确认之前**就会打印，属于真实可达泄漏（P1）。
    统一判据：`api_key` / `apikey` / `token` / `secret` / `password` / `experimental_bearer_token`
    （`password` 是本次新加的：`settings.json.env` 是任意用户环境变量，MCP server 常有 `*_PASSWORD`）。
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
  **唯一非备份的例外**是「把 live 读进临时文件供编辑」（菜单 7 `existing` 分支）：它仍是 copy，
  但**同样必须检查返回值**——临时文件是空文件，载入失败还继续就是让用户在空白内容上编辑，
  保存后写回一份没有凭据的 auth.json（等于清空官方登录态）。
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
  2026-09-23 收敛后共 **12 个备份站点**走 helper（Claude 菜单 1/4、Codex writer / 菜单 1 / 推荐值 / profile 切换 / 菜单 7、
  hapi settings 的 listen 与 cliApiToken），另有 1 处「把 live 读进临时文件供编辑」用同样检查返回值的 `if ! cp -a`。
- 敏感临时文件：`mktemp` 生成不可预测路径（**不要** `${TMPDIR}/xxx_$$.json`），并挂 `hapi_install_sensitive_tmp_traps`
  （`hapi_cleanup_sensitive_tmp` 统一处理 `HAPI_CODEX_AUTH_TMP` / `HAPI_CLAUDE_SETTINGS_TMP`）。
  **故意不挂 INT**：vim 里 Ctrl+C 是退出插入模式的常用操作，挂上会在 vim 退出后连带删掉用户刚保存的内容。

### 编辑器流程（Codex 菜单 7「写入/编辑官方 auth.json」）

- 编辑器探测顺序：`HAPI_EDITOR` → `VISUAL` → `EDITOR` → 自动探测 `vim vi nano emacs`；**配置的编辑器不可用要回退**，不要硬用。
- vim 系加 `-c 'set paste' -c 'set nobackup nowritebackup noswapfile noundofile viminfo='`
  （paste 防自动缩进破坏 JSON；其余防 token 落进 `~/.vim/undo`、`.swp`、`~`、viminfo）。
  `vi` 不一定是 vim：`hapi_editor_is_vim_like` 先探测（`--version` 里含 vim）再决定加不加 `-c`。
- **编辑器退出码非 0 必须拦住**（默认中止、清理临时文件），否则 existing 模式下"编辑失败但旧内容仍然合法"会被静默写回。

### 本脚本的验证方式

- 每次改完最低要求：`bash -n Manage/Hapi_Claude_Manage.sh`。
- **内嵌 node 段的语法 `bash -n` 检查不到**（`local x=$(...)` 之外，`node <<'NODE' … NODE` 里的 JS 只在运行时才炸）：
  本脚本有 **23 个** `node <<'NODE'` 块（2026-09-23 实测 `grep -c "<<'NODE'"`；曾记为 16，属于文档漂移），改过其中一个就把它们全部抽出来逐个 `node --check`——
  做法：按 `<<.NODE.` / 单独一行 `NODE` 切块，各写一个临时 `.js`（路径用盘符形式给 node），再 `for f in ...; do node --check "$f"; done`。
  几秒钟能拦住 heredoc 里的手滑，比等测试跑到一半才报错划算。
- 行为回归：`bash tests/Hapi_Claude_Manage/run.sh`（失败非零退出；`--only A,C` 只跑指定组，`--log FILE` 指定进度日志）。
  分组：**A** `last_refresh` 真 RFC3339 ／ **B** `id_token` 严格 JWT envelope ／ **C** `auth_mode` 解析 + official/loadable 两级校验 ／
  **D** 写入器路由保护 ／ **E** 菜单 7 编辑器流程（含 SIGTERM 清理）／ **F** 配置库旁路卡点 ／ **G** 凭据 0600 与预览脱敏 ／ **H** 兼容性 ／
  **I** 路由自动收敛（官方剥离+暂存 / 第三方恢复 / 保留 id 不动 / 损坏暂存 fail-closed / 空配置走同一条流程，81 条断言；语义与反例清单见
  `tests/Hapi_Claude_Manage/路由自动收敛-测试文档.md`）／
  **J** Claude Code `settings.json` 写入语义（合并写盘保留未知顶层键 / 备份固定一份不堆积 / 不注入固定补齐项 / 预览递归脱敏 /
  配置库损坏 fail-closed（语法级 + schema 级）/ onboarding 幂等 / 写 live 四处 plain-object 校验）／
  **K** Codex 配置库 schema fail-closed（save / create / list 三态）+ 备份 fail-fast
  （writer / 菜单 1 / 推荐值 / profile 切换 / 菜单 7 粘贴 / 菜单 7 载入现有 auth，每条都断言日志里出现「备份失败，已中止修改」，
  避免「因为别的卡点提前 return」造成的假绿）。
  实测（2026-09-19，本机 Windows/MSYS）：**定向分组** `--only C` = 39 断言全绿、`--only E,F` = 35 断言全绿；A 组 ≈15s、C 组 ≈25s、E 组 ≈2min、E+F ≈3min（进程创建极慢，别指望秒级）。
- ⚠️ **全量套件在本机 Windows/MSYS 上超过默认 300s 上限**（2026-09-23 实测）：默认 `HARNESS_TIMEOUT=300` 会被
  `timeout` 杀掉，表现为 **`NOT OK - harness 超时（300s）`、rc=124、日志停在 G 组且没有任何 `NOT OK` 断言**
  （别把它误判成断言失败）。同一次改动加时长上限跑完：`HARNESS_TIMEOUT=1200` → **9m27s、pass=225 fail=0 skip=0、RESULT: PASS**
  （与 2026-09-19 基线一致）。想在本机跑全量就显式抬上限，否则只跑 `--only`。慢是本机进程创建开销，不是断言数量问题。
- ⚠️ 用户规则（2026-09-23）：**本机不再跑超过 1 分钟的测试**，且**任何测试一律后台任务 + 日志文件**。
  全量套件与其它长验证统一交到**另一台服务器 / 审查环境**执行；本机只保留秒级到 1 分钟内的定向用例。
  ⚠️ **同日追加（更严）**：改完**本机干脆不要跑测试**——由用户自己在服务器上跑。
  本机只做**秒级静态检查**：`bash -n` ×2（生产脚本 + run.sh）+ 把 23 个 `node <<'NODE'` 块逐个 `node --check`。
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

## 常见坑

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
- `Linux/Bot-Install-*.sh` 那批系统安装脚本只装文泉驿（CentOS 走 `groupinstall fonts`），**没有 Noto 系列**——需要 CJK/emoji 覆盖时记得同步这四处。
