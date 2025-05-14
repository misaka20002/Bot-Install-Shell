<h1 align="center">呆毛版-Script-Wiki<h1/>
<hr/>
<h6>ps:可怜的呆毛版终于想起要写wiki了<h6/>
<hr/>

##### ~~PS: 实在看不懂的可以拿这个文档去群里问人~~

### 快捷命令使用方法
```bash
bh #打开呆毛版脚本
```

```bash
bh help #获取呆毛版脚本快捷命令帮助
```

```bash
bh QS #打开签名服务器管理脚本
```

```bash
bh PI #打开插件安装脚本
```

```bash
bh SWPKG #检查软件包依赖
```


<hr/>

#### 进入BOT文件夹

##### bh在此提供了三个内建对象:

##### Yunzai-Bot: `yz`

##### Miao-Yunzai: `mz`

##### TRSS-Yunzai: `tz`
##### 需要执行的命令是:
```bash
bh *对象* #进入项目根目录（白话：机器人所在文件夹）
```
##### 现在开始操作，例如我们需要进入已经安装好的Yunzai-Bot的项目根目录:
```bash
bh yz
```
##### 这样我们就进入到Yunzai-Bot相应的文件夹内了
<hr>

#### 操作BOT

##### 同样的，`bh`提供了三个内建对象:

##### Yunzai-Bot: `YZ`

##### Miao-Yunzai: `MZ`

##### TRSS-Yunzai: `TZ`

##### 当然，还可以是一个路径，例如:
```bash
/root/Yunzai-Bot
```

##### 现在开始操作，例如我们想要在前台启动已经安装好的Yunzai-Bot:
```bash
bh YZ n
```

##### 或者启动位于`/root/Node.js/RoBot/Yunzai-Bot`的项目:
```bash
bh /root/Node.js/RoBot/Yunzai-Bot n
```

#### 以下是`bh`对项目控制的操作，请将`*对象*`替换成以上三个内建对象之一或项目路径
```bash
bh *对象* n #前台启动
```

```bash
bh *对象* start #后台启动
```

```bash
bh *对象* log #打开后台日志
```

```bash
bh *对象* stop #停止后台运行
```

```bash
bh *对象* login #重新配置账号
```

```bash
bh *对象* install [依赖名] #安装NPM依赖包
```

```bash
bh *对象* up bot #更新项目
```

```bash
bh *对象* up pkg #更新NPM依赖包
```

```bash
bh *对象* fix pkg #重新安装NPM依赖包
```

<hr/>

<details markdown='2'><summary>报错提示: 参数错误</summary>
 - 是否已安装相应BOT<br>
 - 名称是否拼写错误<br>
 - 大小写是否混用<br>
 - 是否更改过文件夹路径或名称<br>
<hr/>
</details>
<br>