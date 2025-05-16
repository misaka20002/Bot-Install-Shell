export red="\033[31m"
export green="\033[32m"
export yellow="\033[33m"
export blue="\033[34m"
export purple="\033[35m"
export cyan="\033[36m"
export white="\033[37m"
export background="\033[0m"

if [ -d /usr/local/node/bin ];then
    PATH=$PATH:/usr/local/node/bin
    if [ ! -d $HOME/.local/share/pnpm ];then
        mkdir -p $HOME/.local/share/pnpm
    fi
    PATH=$PATH:/root/.local/share/pnpm
    PNPM_HOME=/root/.local/share/pnpm
fi

ChangeAccount(){
file="config/config/qq.yaml"
if [ ! -e ${file} ];then
    echo -e ${red}文件不存在${background}
    return
fi
echo -en ${cyan}请输入新QQ号: ${background}
read qqAccount
echo -en ${cyan}请输入新密码: ${background}
read qqPassword
OldAccount=$(grep "qq:" ${file})
NewAccount="qq: ${qqAccount}"
sed -i "s/${OldAccount}/${NewAccount}/g" ${file}
OldPassword=$(grep "pwd:" ${file})
NewPassword="pwd: ${qqPassword}"
sed -i "s/${OldPassword}/${NewPassword}/g" ${file}
echo -en ${green}修改完成 ${cyan}回车返回${background}
read
}

ChangeDevice(){
file="config/config/qq.yaml"
if [ ! -e ${file} ];then
    echo -e ${red}文件不存在${background}
    return
fi
#1:安卓手机、 2:aPad 、 3:安卓手表、 4:MacOS 、 5:iPad 、 6:Tim
echo -e ${white}"====="${green}呆毛版-Device${white}"====="${background}
echo -e ${green}请选择您的登录设备${background}
echo -e  ${green} 1. ${cyan}安卓手机${background}
echo -e  ${green} 2. ${cyan}aPad${background}
echo -e  ${green} 3. ${cyan}安卓手表${background}
echo -e  ${green} 4. ${cyan}MacOS${background}
echo -e  ${green} 5. ${cyan}iPad${background}
echo -e  ${green} 6. ${cyan}Tim${background}
echo "========================="
echo -en ${green}请输入您的选项: ${background};read num
case ${num} in
  1)
    DeviceNumber=1
    ;;
  2)
    DeviceNumber=2
    ;;
  3)
    DeviceNumber=3
    ;;
  4)
    DeviceNumber=4
    ;;
  5)
    DeviceNumber=5
    ;;
  6)
    DeviceNumber=6
    ;;
  *)
    echo -e ${red}输入错误${background}
    exit
    ;;
esac
OldDevice=$(grep "platform:" ${file})
NewDevice="platform: ${DeviceNumber}"
sed -i "s/${OldDevice}/${NewDevice}/g" ${file}
rm -rf data > /dev/null
echo -en ${green}修改完成 ${cyan}回车返回${background}
read
}

ChangeAdmin(){
file="config/config/other.yaml"
if [ ! -e ${file} ];then
    echo -e ${red}文件不存在${background}
    return
fi
echo -en ${cyan}请输入新主人账号: ${background}
read AdminAccount
NewAdminAccount=" - ${AdminAccount}"
line=$(cat -n ${file} | grep masterQQ: | awk '{print $1}')
line=$((${line}+1))
sed -i "${line}s/.*/${NewAdminAccount}/g" ${file}
}

OpenPluginLink(){
i=1
plugin=$(ls plugins -I example -I other -I system -I genshin)
echo -e ${white}"====="${green}呆毛版-Script${white}"====="${background}
echo -e ${green}请选择您要打开链接的插件[${Bot_Name}]${background}
for file in ${plugin}
do
    echo -e ${green}${i} ${cyan}${file}${background}
    i=$((${i}+1))
done
echo "========================="
echo -en ${green}请输入您的选项: ${background};read num
plugin=$(ls -1 plugins -I example -I other -I system -I genshin | sed -n "${num}p")
file="plugins/${plugin}/.git/config"
if [ -e ${file} ]
then
    Link=$(grep url ${file} | sed 's/url =//g' | sed -n "1p")
    echo -e ${cyan}请用浏览器打开此链接${background}
    echo -e ${green}${Link}${background}
    echo -en ${cyan}回车返回${background}
    read
else
    if [ ! -e ${file} ];then
        echo -e ${red}文件不存在${background}
        return
    fi
fi
}

InstallPackage(){
npm install -g npm@latest
pnpm install -g pnpm@latest
pnpm install -g pm2@latest
echo "Y" | pnpm install
pnpm install puppeteer@13.7.0 -w
pnpm install icqq@latest -w
echo -en ${green}安装完成 ${cyan}回车返回${background}
}

ReloadPackage(){
echo -e ${cyan}正在删除BOT依赖${background}
rm -rf node_modules > /dev/null 2>&1
rm -rf node_modules > /dev/null 2>&1
echo -e ${cyan}正在删除插件依赖${background}
plugin=$(ls plugins)
for file in ${plugin}
do
    if [ -d plugins/${file}/node_modules ];then
        rm -rf plugins/${file}/node_modules > /dev/null 2>&1
        rm -rf plugins/${file}/node_modules > /dev/null 2>&1
    fi
done
echo -e ${cyan}正在安装BOT依赖${background}
sed -i "s/\^5.1.6/5.1.6/g" package.json
until echo "Y" | pnpm install -P && echo "Y" | pnpm install
do
    echo -e ${red}依赖安装失败 ${green}正在重试${background}
    if [ "${i}" == "3" ];then
        echo -e ${red}错误次数过多 退出${background}
        exit 
    fi
    i=$((${i}+1))
done
pnpm install puppeteer@13.7.0 -w
pnpm install icqq@latest -w
echo -e ${cyan}正在安装插件依赖${background}
plugin=$(ls plugins)
for file in ${plugin}
do
    if [ -e plugins/${file}/package.json ];then
        cd plugins/${file}/
        pnpm install -P
        cd ../../
    fi
done
echo -en ${green}依赖重装完成 ${cyan}回车返回${background}
read
}

InstallThePackage(){
echo -e ${white}"====="${green}呆毛版-Script${white}"====="${background}
echo -en ${green}请输入将要安装的依赖名称: ${background};read Package
pnpm install
pnpm install ${Package} -w
echo -en ${green}安装完成 ${cyan}回车返回${background}
read
}

RepairSqlite3(){
pnpm uninstall sqlite3
pnpm install sqlite3@5.1.6 -w
}

LowerPptr(){
pnpm uninstall puppeteer
pnpm install puppeteer@13.7.0 -w
}

CheckAndInstallNvm() {
    if ! command -v nvm &> /dev/null; then
        echo -e ${yellow}未检测到 NVM，正在安装...${background}
        
        # 安装 NVM
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
        
        # 加载 NVM
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
        
        # 确认安装
        if command -v nvm &> /dev/null; then
            echo -e ${green}NVM 安装成功！${background}
        else
            echo -e ${red}NVM 安装失败，请手动安装后再试${background}
            echo -e ${cyan}可以访问 https://github.com/nvm-sh/nvm 获取安装指南${background}
            echo -en ${cyan}回车返回${background}
            read
            return 1
        fi
    fi
    return 0
}

UpdateNodeJS(){
    echo -e ${white}"====="${green}呆毛版-NVM管理${white}"====="${background}
    
    # 检查并安装 NVM
    if ! CheckAndInstallNvm; then
        return
    fi
    
    echo -e ${green}请选择您的操作${background}
    echo -e  ${green} 1. ${cyan}查看当前 Node.js 版本${background}
    echo -e  ${green} 2. ${cyan}查看可用的 Node.js 版本${background}
    echo -e  ${green} 3. ${cyan}查看已安装的 Node.js 版本${background}
    echo -e  ${green} 4. ${cyan}安装指定版本的 Node.js${background}
    echo -e  ${green} 5. ${cyan}切换 Node.js 版本${background}
    echo -e  ${green} 6. ${cyan}卸载指定版本的 Node.js${background}
    echo -e  ${green} 0. ${cyan}返回上级菜单${background}
    echo "========================="
    echo -en ${green}请输入您的选项: ${background};read num
    case ${num} in
      0)
        return
        ;;
      1)
        CheckCurrentNodeVersion
        ;;
      2)
        CheckAvailableNodeVersions
        ;;
      3)
        CheckInstalledNodeVersions
        ;;
      4)
        InstallNodeVersion
        ;;
      5)
        SwitchNodeVersion
        ;;
      6)
        UninstallNodeVersion
        ;;
      *)
        echo -e ${red}输入错误${background}
        echo -en ${cyan}回车返回${background}
        read
        UpdateNodeJS
        ;;
    esac
}

CheckCurrentNodeVersion(){
    # 检查并安装 NVM
    if ! CheckAndInstallNvm; then
        UpdateNodeJS
        return
    fi
    
    echo -e ${cyan}当前 Node.js 版本:${background}
    node -v
    echo -en ${cyan}回车返回${background}
    read
    UpdateNodeJS
}

CheckAvailableNodeVersions(){
    # 检查并安装 NVM
    if ! CheckAndInstallNvm; then
        UpdateNodeJS
        return
    fi
    
    echo -e ${cyan}可用的 Node.js 版本:${background}
    nvm ls-remote
    echo -en ${cyan}回车返回${background}
    read
    UpdateNodeJS
}

CheckInstalledNodeVersions(){
    # 检查并安装 NVM
    if ! CheckAndInstallNvm; then
        UpdateNodeJS
        return
    fi
    
    echo -e ${cyan}已安装的 Node.js 版本:${background}
    nvm ls
    echo -en ${cyan}回车返回${background}
    read
    UpdateNodeJS
}

InstallNodeVersion(){
    # 检查并安装 NVM
    if ! CheckAndInstallNvm; then
        UpdateNodeJS
        return
    fi
    
    echo -e ${white}"====="${green}安装 Node.js 版本${white}"====="${background}
    echo -e ${green}请选择要安装的版本${background}
    echo -e  ${green} 1. ${cyan}Node.js v18 LTS${background}
    echo -e  ${green} 2. ${cyan}Node.js v19${background}
    echo -e  ${green} 3. ${cyan}Node.js v20 LTS${background}
    echo -e  ${green} 4. ${cyan}Node.js v21${background}
    echo -e  ${green} 5. ${cyan}Node.js v22${background}
    echo -e  ${green} 6. ${cyan}Node.js v23${background}
    echo -e  ${green} 7. ${cyan}Node.js v24${background}
    echo -e  ${green} 8. ${cyan}安装其他版本${background}
    echo -e  ${green} 0. ${cyan}返回上级菜单${background}
    echo "========================="
    echo -en ${green}请输入您的选项: ${background};read num
    case ${num} in
      0)
        UpdateNodeJS
        ;;
      1)
        nvm install 18
        ;;
      2)
        nvm install 19
        ;;
      3)
        nvm install 20
        ;;
      4)
        nvm install 21
        ;;
      5)
        nvm install 22
        ;;
      6)
        nvm install 23
        ;;
      7)
        nvm install 24
        ;;
      8)
        echo -en ${cyan}请输入要安装的 Node.js 版本 \(例如: 16.14.2\): ${background}
        read version
        nvm install ${version}
        ;;
      *)
        echo -e ${red}输入错误${background}
        echo -en ${cyan}回车返回${background}
        read
        InstallNodeVersion
        ;;
    esac
    echo -e ${green}安装完成${background}
    echo -en ${cyan}回车返回${background}
    read
    UpdateNodeJS
}

SwitchNodeVersion(){
    # 检查并安装 NVM
    if ! CheckAndInstallNvm; then
        UpdateNodeJS
        return
    fi
    
    echo -e ${cyan}已安装的 Node.js 版本:${background}
    nvm ls
    echo -en ${cyan}请输入要切换的 Node.js 版本 \(例如: 18 或 v18.17.1\): ${background}
    read version
    nvm use ${version}
    echo -e ${green}当前 Node.js 版本:${background}
    node -v
    echo -en ${cyan}回车返回${background}
    read
    UpdateNodeJS
}

UninstallNodeVersion(){
    # 检查并安装 NVM
    if ! CheckAndInstallNvm; then
        UpdateNodeJS
        return
    fi
    
    echo -e ${cyan}已安装的 Node.js 版本:${background}
    nvm ls
    echo -en ${cyan}请输入要卸载的 Node.js 版本 \(例如: 18 或 v18.17.1\): ${background}
    read version
    nvm uninstall ${version}
    echo -e ${green}卸载完成${background}
    echo -en ${cyan}回车返回${background}
    read
    UpdateNodeJS
}

FfmpegPath(){
file="config/config/bot.yaml"
if [ ! -e ${file} ];then
    echo -e ${red}文件不存在${background}
    return
fi
echo -en ${cyan}请输入ffmpeg路径: ${background}
read NewFfmpegPath
echo -en ${cyan}请输入ffprobe路径: ${background}
read NewFfprobePath
if ! $(echo ${NewFfmpegPath} | grep -q '/');then
    echo -en ${cyan}回车返回${background}
    read
    return
fi
if ! $(echo ${NewFfprobePath} | grep -q .*.exe);then
    echo -e ${red}请以.exe结尾${background}
    echo -en ${cyan}回车返回${background}
    read
    return
fi
NewFfmpegPath="ffmpeg_path: ${NewFfmpegPath}"
NewFfprobePath="ffprobe_path: ${NewFfprobePath}"
OldFfmpegPath=$(grep "ffmpeg_path:" ${file})
OldFfprobePath=$(grep "ffprobe_path:" ${file})
sed -i "s/${OldFfmpegPath}/${NewFfmpegPath}/g" ${file}
sed -i "s/${OldFfprobePath}/${NewFfprobePath}/g" ${file}
echo -en ${green}修改完成 ${cyan}回车返回${background}
}

BrowserPath(){
file="config/config/bot.yaml"
if [ ! -e ${file} ];then
    echo -e ${red}文件不存在${background}
    return
fi
echo -en ${cyan}请输入浏览器路径: ${background}
read NewBrowserPath
if ! $(echo ${NewBrowserPath} | grep -q '/');then
    echo -e ${red}请输入路径${background}
    echo -en ${cyan}回车返回${background}
    read
    return
fi
NewBrowserPath="chromium_path: ${NewFfmpegPath}"
OldBrowserPath=$(grep "chromium_path:" ${file})
sed -i "s/${OldBrowserPath}/${NewBrowserPath}/g" ${file}
echo -en ${green}修改完成 ${cyan}回车返回${background}
}

QuitGroupChat(){
file="config/config/other.yaml"
if [ ! -e ${file} ];then
    echo -e ${red}文件不存在${background}
    return
fi
echo -e ${cyan}当被好友拉进群时,群人数小于配置值自动退出.${background}
echo -e ${cyan}默认为50，0则不处理${background}
echo -en ${cyan}请输入人数: ${background}
read NewAutoQuit
if [[ ! ${NewAutoQuit} =~ ^[0-9]+$ ]];then
    echo -e ${red}请输入数字!!!${background}
    echo -en ${cyan}回车返回${background}
    read
    return
fi
NewAutoQuit="autoQuit: ${NewAutoQuit}"
OldAutoQuit=$(grep "autoQuit:" ${file})
sed -i "s/${OldAutoQuit}/${NewAutoQuit}/g" ${file}
echo -en ${green}修改完成 ${cyan}回车返回${background}
read
}

GuoBaCheck(){
export file=$(find plugins -name application.yaml | grep config)
if [ -z ${file} ]
then
    echo -e ${red}未能找到锅巴插件的配置文件${background}
    echo -e ${red}请确认已安装或已初始化锅巴插件${background}
    echo -en ${cyan}回车返回${background}
    return 1
else
    return 0
fi
}

ChangePort(){
if ! GuoBaCheck
then
    read
    return
fi
echo -en ${cyan}请输入端口号: ${background}
read NewPort
if [[ ! ${NewPort} =~ ^[0-9]+$ ]];then
    echo -e ${red}请输入数字!!!${background}
    echo -en ${cyan}回车返回${background}
    read
    return
fi
NewPort="port: ${NewPort}"
OldPort=$(grep "port:" ${file})
sed -i "s/${OldPort}/  ${NewPort}/g" ${file}
echo -en ${green}修改完成 ${cyan}回车返回${background}
read
}

ChangeHost(){
if ! GuoBaCheck
then
    read
    return
fi
echo -en ${cyan}请输入端口: ${background}
read NewHost
if ! $(echo ${NewHost} | grep -q '.');then
    echo -e ${red}请输入IP或者域名${background}
    echo -en ${cyan}回车返回${background}
    read
    return
fi
NewHost="host: ${NewHost}"
OldHost=$(grep "host:" ${file})
sed -i "s/${OldHost}/  ${NewHost}/g" ${file}
echo -en ${green}修改完成 ${cyan}回车返回${background}
read
}

BotBackup(){
date=$(date +"%Y-%m-%d-%H-%M-%S")
if [ ! -d "$HOME/BotBackup" ];then
  mkdir $HOME/BotBackup
fi
cp -rf data $HOME/BotBackup/data
cp -rf config $HOME/BotBackup/config

}

echo -e ${white}"====="${green}呆毛版-Script${white}"====="${background}
echo -e ${green}请选择您的操作[${Bot_Name}]${background}
echo -e  ${green} 1. ${cyan}修改登录账号${background}
echo -e  ${green} 2. ${cyan}修改登录设备${background}
echo -e  ${green} 3. ${cyan}修改主人账号${background}
echo -e  ${green} 4. ${cyan}打开插件链接${background}
echo -e  ${green} 5. ${cyan}安装依赖文件${background}
echo -e  ${green} 6. ${cyan}重装依赖文件${background}
echo -e  ${green} 7. ${cyan}安装指定依赖${background}
echo -e  ${green} 8. ${cyan}修复监听错误${background}
echo -e  ${green} 9. ${cyan}降级pptr版本${background}
echo -e  ${green}10. ${cyan}更新NodeJS版本${background}
echo -e  ${green}11. ${cyan}修改ffmpeg路径${background}
echo -e  ${green}12. ${cyan}修改浏览器路径${background}
echo -e  ${green}13. ${cyan}设置自动退群人数${background}
echo -e  ${green}14. ${cyan}修改锅巴插件端口${background}
echo -e  ${green}15. ${cyan}修改锅巴插件地址${background}
echo "========================="
echo -en ${green}请输入您的选项: ${background};read num
case ${num} in
  1)
    ChangeAccount
    ;;
  2)
    ChangeDevice
    ;;
  3)
    ChangeAdmin
    ;;
  4)
    OpenPluginLink
    ;;
  5)
    InstallPackage
    ;;
  6)
    ReloadPackage
    ;;
  7)
    InstallThePackage
    ;;
  8)
    RepairSqlite3
    ;;
  9)
    LowerPptr
    ;;
  10)
    UpdateNodeJS
    ;;
  11)
    FfmpegPath
    ;;
  12)
    BrowserPath
    ;;
  13)
    QuitGroupChat
    ;;
  14)
    ChangePort
    ;;
  15)
    ChangeHost
    ;;
  16)
    BotBackup
    ;;
  *)
    echo -e ${red}输入错误${background}
    exit
    ;;
esac