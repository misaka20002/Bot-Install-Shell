# Yunzai-Bot-Shell

Debian 系 Linux 上部署与管理 Yunzai / NapCat 的 Bash 脚本集。这份词表只收**本项目自己会混淆**的概念，
尤其是 QQ 客户端与 NapCat 各自那套「日志、临时、缓存」——它们名字相似、归属不同、能不能删也完全不同。

## 语言

### QQ 客户端侧

**缓存目录（`nt_data`）**:
`~/.config/QQ/nt_qq_<hash>/nt_data`，QQ 客户端写入的可再生数据（`Pic`、`Ptt`、`Video`、`File`、`log`、`log-cache`）。
没有容量上限，也没有任何自动清理机制，只能手动清。
_Avoid_: 聊天记录、QQ 数据目录

**账号目录（`nt_qq_<hash>`）**:
每个账号一个的数据根，`<hash>` = `md5(md5(uid) + "nt_kernel")`，由内部 uid 派生，**无法反推 QQ 号**。
界面上一律显示 hash 前缀 + 最近写入时间，不假装能标出账号。
_Avoid_: QQ 号目录、uin 目录

**接收文件（`File`）**:
对方发来的文件缓存，可能是唯一一份本地副本（发送方补发不了）。因此清理时单独问一句，不与其他缓存同级对待。
_Avoid_: 下载目录、附件

**聊天记录库（`nt_db`）**:
消息与数据库所在目录，**不是缓存**，任何清理动作都不碰。体检时若「清完还很占」，先看这里。
_Avoid_: 缓存、日志

### NapCat 侧

**NapCat 日志（`logs`）**:
NapCat 自身运行日志，写在 `$NAPCAT_WORKDIR/logs`，未设置该变量时是 NapCat 目录下的 `logs`。
它**会**自动收敛：启动时删 7 天前的文件，当前文件按 5MB × 5 轮转。与 QQ 的 `log` 是两回事。
_Avoid_: QQ 日志、运行日志

**NapCat 临时目录（`NapCat/temp`）**:
在 QQ 数据根下（`~/.config/QQ/NapCat/temp`），不是安装目录里的 `temp`——后者通常不存在。
_Avoid_: 缓存目录、安装目录临时文件

### 清理动作

**整清**:
不看文件新旧，把目录内文件全部删除，但保留目录自身（下次 QQ 启动还要往里写）。
用于纯诊断/临时数据：`log`、`log-cache`、`NapCat/temp`、`NapCat/logs`。
_Avoid_: 清空、全清

**保留天数**:
以文件 `mtime` 判定「旧到可以删」的天数（默认 7，另有 30 与自定义）。只作用于媒体缓存
（`Pic`、`Ptt`、`Video`、`File`）；日志类不受它影响，始终整清。
判定维度是**文件时间**，不是目录名里的日期——目录命名一变也不会整片误删。
_Avoid_: 过期时间、TTL
