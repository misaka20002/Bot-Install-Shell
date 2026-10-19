# QQ 缓存清理：自己删文件，不调 `clean_cache`，也不依赖官方清理插件

`Manage/NapCat.sh` 的「qq缓存清理」用手写的 `find` + `mtime` 递归删除，而不是调 NapCat 的
`clean_cache` OneBot 接口、也没让用户去装 `napcat-plugin-cleaner`。

## 为什么不用 NapCat 自带的 `clean_cache`

`CleanCache.ts` 把数据目录硬编码成 Windows 布局 `{dataPath}/{uin}/nt_qq/nt_data`，而 Linux 是
`{dataPath}/nt_qq_<hash>/nt_data`；`readdir` 失败被 `catch(() => null)` 静默跳过，所以在 Linux 上这个接口
基本只清了 `NapCat/temp`。就算路径对上，它对每个子目录只做一层 `readdir` + `unlink`，而 `Pic`/`Ptt`/`Video`/`File`
下面是日期目录与 `Ori`/`Thumb` 子目录，`unlink` 遇到目录会抛错——结果是一条条「删除失败」，却不影响返回 0。

注：`clean_cache` 是唯一入口这一点也意味着它**没有任何定时任务**，`nt_data` 不会自己收敛。

## 为什么不让用户装官方清理插件

插件本身做得不错（`retainDays` 按 `mtime`、`scanCache` 先算后删、清理后删空目录），但作为本脚本的依赖不合适：

- 它的安全模型是「路径拼死 + 用户勾选」，**没有** `realpath` 越界校验；根目录若是符号链接会被跟随进入。
- 删除失败只写 `warn`，前端仍是「清理完成」，失败数对用户不可见。
- 它按 `YYYY-MM` 深度 1 通配日期目录，且 `Pic/<date>/Thumb` 根本不在清单里——目录命名一变就静默什么都不清。
- 多账号时拿不到 hash 会「取第一个 `nt_qq_*`」，多实例下可能清到别的号。

这些都是「装个插件还得盯着它别乱删」的成本，而我们需要的能力只是「递归 + 按 mtime 过滤 + 如实报错」。

## 我们自己的约束

- **不用 `uid → md5` 猜账号**：目录名 `md5(md5(uid) + "nt_kernel")` 是逆向出来的实现细节，直接 `nt_qq_*` 通配逐个枚举，显示 hash 前缀 + 最近写入时间。
- **递归、不假设层级**：只按文件类型与 `mtime` 过滤，`Pic/<date>/Thumb`、日期目录下的平铺文件都能覆盖。
- **不跟随符号链接**：顶层目录是 symlink 时只显示、标 `skip`，不进入；删除只针对 `-type f`/`-type l` 本身，并带 `-xdev` 不跨文件系统。
- **失败如实上报**：`find -delete` 的 stderr 非空即视为未清干净，逐目录汇总失败数并返回非零；不打印「清理完成」蒙混过去。
- **日志类整清、媒体类按天数**：`log`/`log-cache`/`nt_temp`/`NapCat/temp`/`NapCat/logs` 是纯诊断与临时数据；`Pic`/`Ptt`/`Video`/`File` 走保留天数。
- **`File` 单独确认**：接收文件可能是唯一一份本地副本，默认包含但每次都要问一句。
- **不做定时清理**：清理是有损操作，无人值守出问题没人拦；要做 cron 需另起一轮，按本项目「crontab 三层读取 + 三态」的约定实现。

## 后果

- 清理范围集中在 `~/.config/QQ` 与 NapCat 目录，**不碰** `nt_db`（聊天记录库）与 `NapCat/db_<uin>`；总览里显式写了这句，避免用户以为「清完还很占」是没清干净。
- 只显示、不清理的项：NapCat 安装目录。`{NapCat目录}/cache`（解密库副本）经调研无法确认是否可安全删除，未纳入。
- 「卸载」不删除 `~/.config/QQ`（既有行为，本次不改），只在卸载完成后提示缓存仍在占盘并指向主菜单 3。
- `nt_qq_<hash>/nt_temp` **未纳入**：官方插件会清它，但它不在本次约定的清理清单里，调研也要求"先实测确认存在与体积"再决定。
  将来要加，应先在一台真实机器上量它的大小与增长，再作为独立一条进清单，而不是顺手并进媒体缓存。
