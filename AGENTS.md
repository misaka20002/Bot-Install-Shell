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
| `Manage/*.sh` | 其余功能脚本：`Hapi_Claude_Manage.sh`、`SYS_Manage.sh`、`NapCat.sh`、`Sayu_Bot.sh`、`Lagrange_OneBot.sh`、`BOT-*.sh`、`BOT_INSTALL.sh`、`GitBot.sh`、`QSignServer.sh`、`OtherFunctions.sh` |
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

- **按文件保持它原有的 EOL**：不要无意归一化。当前 `Manage/meme_generator.sh` 的基线是**全 CRLF**；`Manage/Hapi_Claude_Manage.sh` 是已知历史例外（混行）。
  `tests/**/*.sh` 反过来必须是 **LF**：CRLF 会让 `bash tests/...` 直接报 `\r` 相关错误（`$'\r': command not found`）。
  曾经用一个 `.gitattributes`（`tests/**/*.sh text eol=lf`）钉住这件事；**如果那个文件不在仓库里，就要在提交前手动确认
  `tests/` 下的脚本仍是 LF**（`git add` 时 `core.autocrlf=true` 会把 CRLF 转成 LF 存进对象库，但 **Windows 上重新 checkout
  会变回 CRLF**，届时测试就跑不起来；Linux 目标环境 checkout 得到的是 LF，不受影响）。
  **现状（2026-09-13）：仓库里没有 `.gitattributes`**，而 `tests/meme_generator/run.sh` 已被跟踪（对象库里是纯 LF）。
  所以 `git add` 时 git 会警告 `LF will be replaced by CRLF the next time Git touches it` —— 一旦你在 Windows 上
  `git checkout` / `git restore` / 换工作区，`run.sh` 会变回 CRLF 且测试直接跑不起来。
  两种处理：① 补一个 `.gitattributes` 写 `tests/**/*.sh text eol=lf`（推荐，一劳永逸）；② 每次 checkout 后用
  `node -e` 把 `tests/` 下的脚本归一成 LF（见下）。Linux 上不受影响。
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
#     bash tests/meme_generator/run.sh              # 默认：A~F 断言（**G 组已默认跳过**）
#     bash tests/meme_generator/run.sh --only A,B   # 只跑指定分组（日常最常用）
#     bash tests/meme_generator/run.sh --with-git   # 只有确实改了 git_clone / git_update 才用（G 组已停跑，见下）
#     --log FILE 指定进度日志（默认自动生成）；每条断言即时 append，超时/被杀也能看出停在哪
#    ⚠️ **测试范围已收窄（2026-09-13，用户决定）**：
#      · **不再跑 G 组**（真实 git 行为：造裸仓库 + 多次 push + force-push）。默认已跳过，要跑必须显式 `--with-git`；
#        G 组断言仍在代码里，但**不再随日常回归执行**，属于**未维护**状态（别把它当成"有保护"）。
#      · **不再跑变异验证**（`--mutate`）。参数保留（代码没删），但**不要跑、也不要再提议**。
#      随之而来的唯一代价：新断言的"有效性"不再由变异自动证明，所以**新断言必须手工拿反例自证**
#      （临时改坏对应生产代码 → 跑一次确认变红 → 改回），否则就是"看起来对"的断言。
#    当前 meme_generator.sh 的断言覆盖（run.sh 里按 A~G 分组，--only 可单独跑；**G 组已默认停跑/未维护**）：
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

## 常见坑

- `if git clone … | tee -a log` 后面**忘了 `then`**（或误跟另一个 `if`）会让整个脚本语法错误。真实事故：改到一半留下 `if … | tee` 紧跟 `if [ "${PIPESTATUS[0]}" -eq 0 ]; then …`，`bash -n` 报 `syntax error near unexpected token 'else'`。**改完务必 `bash -n`**。
- **一行多段 sed 极易写错**：`sed "s|, \"$p\"|; s|\"$p\", ||g; s|\"$p\"||g"` 是畸形的（第一个 `s` 的替换段变成 `; s`，其余被当成 flag），GNU sed 直接报 ``unknown option to `s'``。真实事故：`toggle_single_repo` 的「禁用单个仓库」因此从来没生效。多段替换改用专门的 bash 函数（`remove_dir_from_list`），不要硬写 sed。
- **`awk -v` 传值会解释转义序列**（`\t`、`\\`）；要传**字面值**请用 `ENVIRON`。写 TOML 字符串时同理：不用 `config_set_string` 就会产出非法 TOML。
- **`git reset --hard` 不是"只丢改动"**：它会覆盖/删除与目标 commit 路径冲突的未跟踪文件（见"强制覆盖本地 · 语义边界"）。别把它当成"用户文件绝对安全"的保证。
- `Manage/meme_generator.sh` 里 `log_file` 既是函数名又是变量名（bash 中两者命名空间独立），重命名要一起改。
- 主菜单允许直接进入「尚未安装」的功能项（如按 5 更新）：每个入口函数都要自己加「是否已安装」guard，不要依赖菜单显示。
- tmux 会话使用独立 socket（`tmux -L <name>`）；清理时要连 `kill-server` 和 `/tmp/tmux-$(id -u)/<name>` 一起处理，否则会留下坏 socket。
- `git_clone` / `git_update` 失败后可能留下半成品目录（有目录无 `.git`）——**只能清理由本轮操作创建的目录**；已存在的目录不得按"半成品"推断后删除。
