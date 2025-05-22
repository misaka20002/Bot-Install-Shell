![](https://socialify.git.ci/misaka20002/Bot-Install-Shell/image?custom_description=A+Bot-Install-Shell+for+Yunzai.&description=1&font=KoHo&forks=1&issues=1&language=1&name=1&owner=1&pattern=Circuit+Board&pulls=1&stargazers=1&theme=Auto)

# A Bot-Install-Shell for Yunzai 🍓

- 一站式 Yunzai Bot 部署执行脚本

### 适配系统
- [x] Android
- [x] Arch
- [ ] Centos
- [x] Debian
- [x] Ubuntu

### 特点
- [x] 一键化部署
- [x] 多BOT支持
- [x] 多系统支持
- [x] 轻量无冗杂
- [x] 机器人账密修改
- [x] 配置文件方便更改
- [x] 插件的安装/更新/卸载
- [x] ffmpeg 安装
- [x] ~~签名服务器部署~~
- [x] 拉格朗日 管理
- [x] NapCat 管理
- [x] meme 表情包生成器管理

## 安装

> 注意: 如果您 **已经** 使用其他脚本部署过机器人,那么安装呆毛版脚本后,请第一时间执行 `xdm SWPKG` 来检查软件包依赖,防止出现某些错误。
>
> 安装前需要 `同意` [用户协议](https://gitee.com/Misaka21011/Yunzai-Bot-Shell/blob/master/Manage/用户协议.txt)

<details ><summary>① 服务器安装方法</summary>

##### 服务器安装命令

```sh
su
bash <(curl -sL https://gitee.com/Misaka21011/Yunzai-Bot-Shell/raw/master/install.sh)
# 或
bash <(curl -sL https://github.com/misaka20002/Bot-Install-Shell/raw/master/install.sh)
```

</details>

<details ><summary>② Android手机安装命令</summary>

##### 安卓手机

 ###### 按照此文档部署

> [部署文档地址](./Markdown/Tmoe.md)
> 
> [文件管理文档地址](./Markdown/MT-Termux.md)

</details>

<details ><summary>③ 已安装容器的安装方法</summary>

##### 已安装容器

###### 注意:除非您知道您在干什么,否则请不要使用该项!!!

```
bash <(curl -sL https://gitee.com/Misaka21011/Yunzai-Bot-Shell/raw/master/install.sh)
# 或
bash <(curl -sL https://github.com/misaka20002/Bot-Install-Shell/raw/master/install.sh)
```

</details>

## 使用

<details ><summary>展开/收起</summary>

- 打开呆毛版脚本的命令
    ```
    xdm
    ```
- 获取呆毛版脚本帮助的命令
    ```
    xdm help
    ```
- 修复呆毛版脚本打不开的命令
    ```
    bash <(curl -sL https://gitee.com/Misaka21011/Yunzai-Bot-Shell/raw/master/install.sh)
    #或
    bash <(curl -sL https://github.com/misaka20002/Bot-Install-Shell/raw/master/install.sh)
    ```
- 删除呆毛版脚本的命令
    ```
    rm /usr/local/bin/xdm
    ```

</details>

## LICENSE

- [MIT License](./LICENSE)


## 致谢

| Nickname | Github | Contribution |
| :--------: | :--------: | :--------: |
| 白狐脚本 | [☞Gitee](https://gitee.com/baihu433/Yunzai-Bot-Shell) | 云崽自动化部署及管理脚本 |
| Lagrange | [☞GitHub](https://github.com/LagrangeDev/Lagrange.Core) | An Implementation of NTQQ Protocol, with Pure C#, Derived from Konata.Core |
| NapCat | [☞GitHub](https://napneko.github.io/) | 现代化的基于 NTQQ 的 Bot 协议端实现 |
