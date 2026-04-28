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
- [x] ~~拉格朗日 多开管理~~
- [x] NapCat 多开管理
- [x] meme 表情包生成器管理
- [x] 早柚核心管理

## 安装

> 注意: 如果您 **已经** 使用其他脚本部署过机器人,那么安装呆毛版脚本后,请第一时间执行 `xdm SWPKG` 来检查软件包依赖,防止出现某些错误。
>
> 安装前需要 `同意` [用户协议](./Manage/用户协议.txt)

<details ><summary>① 服务器安装方法</summary>


<details ><summary>购买服务器</summary>

- 纯小白推荐买一个 38元/年的2核2GB 或 188元/年的2核4GB 的[华为云（该链接无任何推广AFF）](https://activity.huaweicloud.com/discount_area_v5/index.html?utm_adplace=ecs-xsfwq_guanggao1)，使用Ubuntu24+镜像开机后，学习[使用SSH登陆服务器](https://www.bing.com/search?q=Termius%E4%BD%BF%E7%94%A8SSH%E7%99%BB%E9%99%86%E6%9C%8D%E5%8A%A1%E5%99%A8)然后输入以下命令：

</details>



##### 服务器安装命令

```sh
su
bash <(curl -sL https://gitee.com/Misaka21011/Yunzai-Bot-Shell/raw/master/install.sh)
# 或
bash <(curl -sL https://raw.githubusercontent.com/misaka20002/Bot-Install-Shell/master/install.sh)
```

- 使用 `xdm` 命令打开呆毛版脚本
- 选择 `TRSS-Yunzai` 并 `回车` 来安装TRSS崽
- 返回主页，选择 `NapCat` 安装、配置接口后启动 `NapCat` 
- 首次启动使用前台启动 `TRSS-Yunzai` ，成功连接上bot之后发送 `#设置主人`，待稳定运行后按 `ctrl+c` 退出前台，从 `xdm` 中使用后台启动。（前台启动不能关闭控制台，否则机器人会关闭，所以稳定运行后，改用后台启动）
- 在后台正常启动后，可以选择自己喜欢的插件安装啦~

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

```sh
bash <(curl -sL https://gitee.com/Misaka21011/Yunzai-Bot-Shell/raw/master/install.sh)
# 或
bash <(curl -sL https://raw.githubusercontent.com/misaka20002/Bot-Install-Shell/master/install.sh)
```

</details>

## 使用

<details ><summary>展开/收起</summary>

- 打开呆毛版脚本的命令
    ```sh
    xdm
    ```
- 获取呆毛版脚本帮助的命令
    ```sh
    xdm help
    ```
- 修复呆毛版脚本打不开的命令
    ```sh
    bash <(curl -sL https://gitee.com/Misaka21011/Yunzai-Bot-Shell/raw/master/install.sh)
    #或
    bash <(curl -sL https://raw.githubusercontent.com/misaka20002/Bot-Install-Shell/master/install.sh)
    ```
- 删除呆毛版脚本的命令
    ```sh
    rm /usr/local/bin/xdm
    ```

</details>

## 脚本中使用的呆毛版插件链接

- [TRSS-Yunzai-NapC](https://github.com/AIGC-Yunzai/TRSS-Yunzai-NapC)
- [椰奶v2-misaka-fork](https://github.com/misaka20002/yenai-plugin/tree/v2)
- [chatgpt-misaka-fork](https://github.com/misaka20002/chatgpt-plugin)
- [ap-plugin-misaka-fork](https://github.com/misaka20002/ap-plugin)
- [xiaofei-plugin-misaka-fork](https://github.com/misaka20002/xiaofei-plugin)
- [paimonnai-plugin](https://github.com/misaka20002/paimonnai-plugin)
- [sf插件](https://github.com/AIGC-Yunzai/siliconflow-plugin)

## LICENSE

- [MIT License](./LICENSE)


## 致谢

| Nickname | Github | Contribution |
| :--------: | :--------: | :--------: |
| 白狐脚本 | [☞Gitee](https://gitee.com/baihu433/Yunzai-Bot-Shell) | 云崽自动化部署及管理脚本 |
| Lagrange | [☞GitHub](https://github.com/LagrangeDev/Lagrange.Core) | An Implementation of NTQQ Protocol, with Pure C#, Derived from Konata.Core |
| NapCat | [☞GitHub](https://napneko.github.io/) | 现代化的基于 NTQQ 的 Bot 协议端实现 |

---

<div align="center">

### 🎨 让创意永不枯竭！✨

**[📚 查看插件主页](/) | [💬 加入交流群1](https://qm.qq.com/q/unjAw930RO) [💬 加入交流群2](https://qm.qq.com/q/tEqFnH0kTe) | [⭐ 给个Star](/)**

</div>