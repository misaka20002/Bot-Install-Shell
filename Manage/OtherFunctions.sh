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
if [ ${BotName} == "TRSS-Yunzai" ];then
    echo -e ${cyan}TRSS-Yunzai 修改 ${yellow}"需要在适配器中操作" ${background}
    echo -en ${cyan}回车返回${background};read
    return
fi
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
if [ ${BotName} == "TRSS-Yunzai" ];then
    echo -e ${cyan}TRSS-Yunzai 修改 ${yellow}"需要在适配器中操作" ${background}
    echo -en ${cyan}回车返回${background};read
    return
fi
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
if [ ${BotName} == "TRSS-Yunzai" ];then
    echo -e ${cyan}TRSS-Yunzai 修改 ${yellow}"在前台登陆的控制台 或 登陆后qq中发送：#设置主人 后查看控制台消息获取设置主人秘钥" ${background}
    echo -en ${cyan}回车返回${background};read
    return
fi
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

ReloadPackage(){
npm install -g npm@latest
pnpm install -g pnpm@latest
pnpm install -g pm2@latest
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
if [ ${BotName} == "Miao-Yunzai" ];then
    pnpm install icqq@latest -w
fi
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

RepairSqlite3(){
pnpm uninstall sqlite3
pnpm install sqlite3@5.1.6 -w
}

LowerPptr(){
pnpm uninstall puppeteer
pnpm install puppeteer@13.7.0 -w
}

CheckAndInstallNvm() {
    # 先尝试加载 NVM 环境
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
    
    # 然后检查是否可用
    if ! command -v nvm &> /dev/null; then
        echo -e ${yellow}未检测到 NVM，正在安装...${background}
        
        # 安装 NVM
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
        
        # 重新加载 NVM
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
if [ ${BotName} == "TRSS-Yunzai" ];then
    echo -e ${cyan}TRSS-Yunzai 不需要FFMPEG ${yellow}"需要在适配器中操作" ${background}
    echo -en ${cyan}回车继续${background};read
fi
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

# 获取git仓库列表
get_git_repos(){
    repos=()
    repo_paths=()
    
    # 检查当前目录的git仓库
    if [ -d ".git" ]; then
        current_url=$(git config --get remote.origin.url 2>/dev/null)
        if [ ! -z "$current_url" ]; then
            repos+=("主目录")
            repo_paths+=(".")
        fi
    fi
    
    # 检查plugins目录下的git仓库，排除指定文件夹
    if [ -d "plugins" ]; then
        for plugin_dir in plugins/*; do
            if [ -d "$plugin_dir" ]; then
                plugin_name=$(basename "$plugin_dir")
                # 排除指定的文件夹
                if [[ "$plugin_name" != "other" && "$plugin_name" != "system" && "$plugin_name" != "example" && "$plugin_name" != "adapter" ]]; then
                    if [ -d "$plugin_dir/.git" ]; then
                        plugin_url=$(cd "$plugin_dir" && git config --get remote.origin.url 2>/dev/null)
                        if [ ! -z "$plugin_url" ]; then
                            repos+=("$plugin_name")
                            repo_paths+=("$plugin_dir")
                        fi
                    fi
                fi
            fi
        done
    fi
}

# 显示git仓库列表
show_git_repos(){
    get_git_repos
    
    if [ ${#repos[@]} -eq 0 ]; then
        echo -e ${red}未找到任何git仓库${background}
        return 1
    fi
    
    echo -e ${white}"====="${green}Git 仓库列表${white}"====="${background}
    for i in "${!repos[@]}"; do
        repo_path="${repo_paths[$i]}"
        if [ "$repo_path" = "." ]; then
            current_url=$(git config --get remote.origin.url 2>/dev/null)
        else
            current_url=$(cd "$repo_path" && git config --get remote.origin.url 2>/dev/null)
        fi
        echo -e ${green}$((i+1)). ${cyan}${repos[$i]}${background}
        echo -e "   ${yellow}$current_url${background}"
    done
    echo "========================="
    return 0
}

# 修改单个仓库的代理
modify_single_repo(){
    if ! show_git_repos; then
        echo -en ${cyan}回车返回${background}
        read
        return
    fi
    
    echo -en ${green}请选择要修改的仓库 \(输入序号\): ${background}
    read repo_num
    
    if [[ ! $repo_num =~ ^[0-9]+$ ]] || [ $repo_num -lt 1 ] || [ $repo_num -gt ${#repos[@]} ]; then
        echo -e ${red}输入错误${background}
        echo -en ${cyan}回车返回${background}
        read
        return
    fi
    
    repo_index=$((repo_num-1))
    repo_name="${repos[$repo_index]}"
    repo_path="${repo_paths[$repo_index]}"
    
    # 获取当前URL
    if [ "$repo_path" = "." ]; then
        current_url=$(git config --get remote.origin.url 2>/dev/null)
    else
        current_url=$(cd "$repo_path" && git config --get remote.origin.url 2>/dev/null)
    fi
    
    echo -e ${cyan}当前仓库: ${green}$repo_name${background}
    echo -e ${cyan}当前地址: ${yellow}$current_url${background}
    echo ""
    echo -e ${green}请选择操作:${background}
    echo -e  ${green} 1. ${cyan}添加 ghfast.top 加速${background}
    echo -e  ${green} 2. ${cyan}添加 gh-proxy.com 加速${background}
    echo -e  ${green} 3. ${cyan}添加自定义加速前缀${background}
    echo -e  ${green} 4. ${cyan}删除加速 \(恢复原始地址\)${background}
    echo -e  ${green} 5. ${cyan}自定义修改地址${background}
    echo -e  ${green} 0. ${cyan}返回${background}
    echo "========================="
    echo -en ${green}请输入您的选项: ${background}
    read action
    
    case $action in
        1)
            new_url="https://ghfast.top/$current_url"
            # 移除已有的加速前缀
            new_url=$(echo "$new_url" | sed 's|https://ghfast.top/https://ghfast.top/|https://ghfast.top/|g')
            new_url=$(echo "$new_url" | sed 's|https://ghfast.top/https://gh-proxy.com/|https://ghfast.top/|g')
            # 移除自定义加速前缀（通用处理）
            new_url=$(echo "$new_url" | sed 's|https://[^/]*/https://ghfast.top/|https://ghfast.top/|g')
            ;;
        2)
            new_url="https://gh-proxy.com/$current_url"
            # 移除已有的加速前缀
            new_url=$(echo "$new_url" | sed 's|https://gh-proxy.com/https://ghfast.top/|https://gh-proxy.com/|g')
            new_url=$(echo "$new_url" | sed 's|https://gh-proxy.com/https://gh-proxy.com/|https://gh-proxy.com/|g')
            # 移除自定义加速前缀（通用处理）
            new_url=$(echo "$new_url" | sed 's|https://[^/]*/https://gh-proxy.com/|https://gh-proxy.com/|g')
            ;;
        3)
            echo -en ${cyan}请输入自定义加速前缀 \(例如: https://git.ppp.ac.cn\): ${background}
            read custom_prefix
            if [ -z "$custom_prefix" ]; then
                echo -e ${red}加速前缀不能为空${background}
                echo -en ${cyan}回车返回${background}
                read
                return
            fi
            # 自动补完末尾的斜杠
            if [[ "$custom_prefix" != */ ]]; then
                custom_prefix="${custom_prefix}/"
            fi
            # 确保前缀以 https:// 或 http:// 开头
            if [[ ! "$custom_prefix" =~ ^https?:// ]]; then
                custom_prefix="https://${custom_prefix}"
            fi
            echo -e ${green}使用的加速前缀: ${yellow}$custom_prefix${background}
            new_url="${custom_prefix}$current_url"
            # 移除已有的加速前缀
            new_url=$(echo "$new_url" | sed 's|https://ghfast.top/||g')
            new_url=$(echo "$new_url" | sed 's|https://gh-proxy.com/||g')
            # 移除重复的自定义前缀
            clean_url=$(echo "$current_url" | sed 's|https://ghfast.top/||g' | sed 's|https://gh-proxy.com/||g')
            new_url="${custom_prefix}${clean_url}"
            ;;
        4)
            # 删除加速前缀
            new_url=$(echo "$current_url" | sed 's|https://ghfast.top/||g')
            new_url=$(echo "$new_url" | sed 's|https://gh-proxy.com/||g')
            # 删除可能的自定义加速前缀（保留原始的github.com等地址）
            new_url=$(echo "$new_url" | sed 's|^https://[^/]*/\(https://\)|\1|g')
            ;;
        5)
            echo -en ${cyan}请输入新的git地址: ${background}
            read new_url
            if [ -z "$new_url" ]; then
                echo -e ${red}地址不能为空${background}
                echo -en ${cyan}回车返回${background}
                read
                return
            fi
            ;;
        0)
            return
            ;;
        *)
            echo -e ${red}输入错误${background}
            echo -en ${cyan}回车返回${background}
            read
            return
            ;;
    esac
    
    # 修改git地址
    if [ "$repo_path" = "." ]; then
        git remote set-url origin "$new_url"
    else
        (cd "$repo_path" && git remote set-url origin "$new_url")
    fi
    
    if [ $? -eq 0 ]; then
        echo -e ${green}修改成功${background}
        echo -e ${cyan}新地址: ${yellow}$new_url${background}
    else
        echo -e ${red}修改失败${background}
    fi
    
    echo -en ${cyan}回车返回${background}
    read
}

# 批量操作所有仓库
batch_modify_repos(){
    get_git_repos
    
    if [ ${#repos[@]} -eq 0 ]; then
        echo -e ${red}未找到任何git仓库${background}
        echo -en ${cyan}回车返回${background}
        read
        return
    fi
    
    echo -e ${white}"====="${green}批量操作${white}"====="${background}
    echo -e ${green}请选择批量操作:${background}
    echo -e  ${green} 1. ${cyan}为所有GitHub仓库添加 ghfast.top 加速${background}
    echo -e  ${green} 2. ${cyan}为所有GitHub仓库添加 gh-proxy.com 加速${background}
    echo -e  ${green} 3. ${cyan}为所有GitHub仓库添加自定义加速前缀${background}
    echo -e  ${green} 4. ${cyan}删除所有仓库的加速${background}
    echo -e  ${green} 0. ${cyan}返回${background}
    echo "========================="
    echo -en ${green}请输入您的选项: ${background}
    read action
    
    case $action in
        1|2|3|4)
            # 获取自定义加速前缀（如果选择了选项3）
            if [ $action -eq 3 ]; then
                echo -en ${cyan}请输入自定义加速前缀 \(例如: https://git.ppp.ac.cn\): ${background}
                read custom_prefix
                if [ -z "$custom_prefix" ]; then
                    echo -e ${red}加速前缀不能为空${background}
                    echo -en ${cyan}回车返回${background}
                    read
                    return
                fi
                # 自动补完末尾的斜杠
                if [[ "$custom_prefix" != */ ]]; then
                    custom_prefix="${custom_prefix}/"
                fi
                # 确保前缀以 https:// 或 http:// 开头
                if [[ ! "$custom_prefix" =~ ^https?:// ]]; then
                    custom_prefix="https://${custom_prefix}"
                fi
                echo -e ${green}使用的加速前缀: ${yellow}$custom_prefix${background}
            fi
            
            # 筛选GitHub仓库
            github_repos=()
            github_repo_paths=()
            for i in "${!repos[@]}"; do
                repo_path="${repo_paths[$i]}"
                if [ "$repo_path" = "." ]; then
                    current_url=$(git config --get remote.origin.url 2>/dev/null)
                else
                    current_url=$(cd "$repo_path" && git config --get remote.origin.url 2>/dev/null)
                fi
                
                # 检查是否为GitHub仓库，同时排除SSH协议
                if [[ "$current_url" == *"github.com"* ]] && [[ "$current_url" != git@* ]] && [[ "$current_url" != ssh://* ]]; then
                    github_repos+=("${repos[$i]}")
                    github_repo_paths+=("$repo_path")
                fi
            done
            
            if [ ${#github_repos[@]} -eq 0 ]; then
                echo -e ${red}未找到任何GitHub仓库${background}
                echo -en ${cyan}回车返回${background}
                read
                return
            fi
            
            if [ $action -eq 4 ]; then
                echo -e ${cyan}即将对以下仓库进行批量操作\(删除加速\):${background}
                for i in "${!repos[@]}"; do
                    echo -e ${green}$((i+1)). ${cyan}${repos[$i]}${background}
                done
            else
                echo -e ${cyan}即将对以下GitHub仓库进行批量操作:${background}
                for i in "${!github_repos[@]}"; do
                    echo -e ${green}$((i+1)). ${cyan}${github_repos[$i]}${background}
                done
            fi
            echo -en ${yellow}确认继续吗? \(y/N\): ${background}
            read confirm
            if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
                echo -e ${cyan}操作已取消${background}
                echo -en ${cyan}回车返回${background}
                read
                return
            fi
            ;;
        0)
            return
            ;;
        *)
            echo -e ${red}输入错误${background}
            echo -en ${cyan}回车返回${background}
            read
            return
            ;;
    esac
    
    success_count=0
    fail_count=0
    skip_count=0
    
    # 根据操作类型选择要处理的仓库
    if [ $action -eq 4 ]; then
        # 删除加速操作处理所有仓库
        process_repos=("${repos[@]}")
        process_repo_paths=("${repo_paths[@]}")
    else
        # 添加加速操作只处理GitHub仓库
        process_repos=("${github_repos[@]}")
        process_repo_paths=("${github_repo_paths[@]}")
    fi
    
    for i in "${!process_repos[@]}"; do
        repo_name="${process_repos[$i]}"
        repo_path="${process_repo_paths[$i]}"
        
        # 获取当前URL
        if [ "$repo_path" = "." ]; then
            current_url=$(git config --get remote.origin.url 2>/dev/null)
        else
            current_url=$(cd "$repo_path" && git config --get remote.origin.url 2>/dev/null)
        fi
        
        # 对于添加加速操作，再次检查是否为GitHub仓库（双重保险）
        # 同时排除SSH协议的仓库
        if [[ $action -eq 1 || $action -eq 2 || $action -eq 3 ]]; then
            if [[ "$current_url" != *"github.com"* ]]; then
                echo -e ${yellow}跳过非GitHub仓库: ${green}$repo_name${background}
                skip_count=$((skip_count+1))
                continue
            elif [[ "$current_url" == git@* ]] || [[ "$current_url" == ssh://* ]]; then
                echo -e ${yellow}跳过SSH协议仓库: ${green}$repo_name${background}
                skip_count=$((skip_count+1))
                continue
            fi
        fi
        
        case $action in
            1)
                new_url="https://ghfast.top/$current_url"
                # 移除已有的加速前缀
                new_url=$(echo "$new_url" | sed 's|https://ghfast.top/https://ghfast.top/|https://ghfast.top/|g')
                new_url=$(echo "$new_url" | sed 's|https://ghfast.top/https://gh-proxy.com/|https://ghfast.top/|g')
                # 移除自定义加速前缀（通用处理）
                new_url=$(echo "$new_url" | sed 's|https://[^/]*/https://ghfast.top/|https://ghfast.top/|g')
                ;;
            2)
                new_url="https://gh-proxy.com/$current_url"
                # 移除已有的加速前缀
                new_url=$(echo "$new_url" | sed 's|https://gh-proxy.com/https://ghfast.top/|https://gh-proxy.com/|g')
                new_url=$(echo "$new_url" | sed 's|https://gh-proxy.com/https://gh-proxy.com/|https://gh-proxy.com/|g')
                # 移除自定义加速前缀（通用处理）
                new_url=$(echo "$new_url" | sed 's|https://[^/]*/https://gh-proxy.com/|https://gh-proxy.com/|g')
                ;;
            3)
                # 使用自定义加速前缀
                # 移除已有的加速前缀
                clean_url=$(echo "$current_url" | sed 's|https://ghfast.top/||g' | sed 's|https://gh-proxy.com/||g')
                # 移除可能的自定义加速前缀（保留原始的github.com等地址）
                clean_url=$(echo "$clean_url" | sed 's|^https://[^/]*/\(https://\)|\1|g')
                new_url="${custom_prefix}${clean_url}"
                ;;
            4)
                # 删除加速前缀
                new_url=$(echo "$current_url" | sed 's|https://ghfast.top/||g')
                new_url=$(echo "$new_url" | sed 's|https://gh-proxy.com/||g')
                # 删除可能的自定义加速前缀（保留原始的github.com等地址）
                new_url=$(echo "$new_url" | sed 's|^https://[^/]*/\(https://\)|\1|g')
                ;;
        esac
        
        # 修改git地址
        echo -e ${cyan}正在处理: ${green}$repo_name${background}
        if [ "$repo_path" = "." ]; then
            git remote set-url origin "$new_url" 2>/dev/null
        else
            (cd "$repo_path" && git remote set-url origin "$new_url" 2>/dev/null)
        fi
        
        if [ $? -eq 0 ]; then
            echo -e ${green}  ✓ 修改成功${background}
            success_count=$((success_count+1))
        else
            echo -e ${red}  ✗ 修改失败${background}
            fail_count=$((fail_count+1))
        fi
    done
    
    echo ""
    echo -e ${green}批量操作完成${background}
    if [ $skip_count -gt 0 ]; then
        echo -e ${cyan}成功: $success_count 个，失败: $fail_count 个，跳过: $skip_count 个${background}
    else
        echo -e ${cyan}成功: $success_count 个，失败: $fail_count 个${background}
    fi
    echo -en ${cyan}回车返回${background}
    read
}

# 配置GitHub SSH端口
configure_github_ssh_port(){
    echo -e ${white}"====="${green}GitHub SSH 端口配置${white}"====="${background}
    echo -e ${green}请选择操作${background}
    echo -e  ${green} 1. ${cyan}配置使用443端口 \(应急\)${background}
    echo -e  ${green} 2. ${cyan}配置使用22端口 \(默认\)${background}
    echo -e  ${green} 3. ${cyan}查看当前SSH配置${background}
    echo -e  ${green} 4. ${cyan}测试SSH连接${background}
    echo -e  ${green} 0. ${cyan}返回${background}
    echo "========================="
    echo -en ${green}请输入您的选项: ${background}
    read ssh_action
    
    case $ssh_action in
        1)
            configure_ssh_443
            ;;
        2)
            configure_ssh_22
            ;;
        3)
            show_ssh_config
            ;;
        4)
            test_ssh_connection
            ;;
        0)
            return
            ;;
        *)
            echo -e ${red}输入错误${background}
            echo -en ${cyan}回车返回${background}
            read
            configure_github_ssh_port
            ;;
    esac
}

# 配置SSH使用443端口
configure_ssh_443(){
    echo -e ${cyan}正在配置GitHub SSH使用443端口...${background}
    
    # 确保.ssh目录存在
    if [ ! -d "$HOME/.ssh" ]; then
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
    fi
    
    ssh_config_file="$HOME/.ssh/config"
    
    # 备份现有配置文件
    if [ -f "$ssh_config_file" ]; then
        cp "$ssh_config_file" "${ssh_config_file}.backup.$(date +%Y%m%d_%H%M%S)"
        echo -e ${green}已备份现有SSH配置文件${background}
    fi
    
    # 检查是否已有GitHub配置
    if grep -q "Host github.com" "$ssh_config_file" 2>/dev/null; then
        echo -e ${yellow}检测到已有GitHub SSH配置，正在更新...${background}
        # 删除现有的github.com配置段
        sed -i '/^Host github\.com$/,/^$/d' "$ssh_config_file" 2>/dev/null
    fi
    
    # 添加新的GitHub SSH配置
    cat >> "$ssh_config_file" << EOF

Host github.com
    HostName ssh.github.com
    User git
    Port 443
    PreferredAuthentications publickey
    IdentityFile ~/.ssh/id_rsa
EOF
    
    # 设置正确的权限
    chmod 600 "$ssh_config_file"
    
    echo -e ${green}GitHub SSH 443端口配置完成！${background}
    echo -e ${cyan}配置内容：${background}
    echo -e ${yellow}Host github.com${background}
    echo -e ${yellow}    HostName ssh.github.com${background}
    echo -e ${yellow}    User git${background}
    echo -e ${yellow}    Port 443${background}
    echo -e ${yellow}    PreferredAuthentications publickey${background}
    echo -e ${yellow}    IdentityFile ~/.ssh/id_rsa${background}
    
    # 配置Git全局设置
    echo -e ${cyan}正在配置Git全局URL重写...${background}
    git config --global url."ssh://git@ssh.github.com:443".insteadOf "ssh://git@github.com"
    echo -e ${green}Git全局配置完成！${background}
    
    echo -e ${cyan}建议运行测试以确认配置正确${background}
    echo -en ${cyan}回车返回${background}
    read
    configure_github_ssh_port
}

# 配置SSH使用22端口（默认）
configure_ssh_22(){
    echo -e ${cyan}正在配置GitHub SSH使用22端口...${background}
    
    ssh_config_file="$HOME/.ssh/config"
    
    # 备份现有配置文件
    if [ -f "$ssh_config_file" ]; then
        cp "$ssh_config_file" "${ssh_config_file}.backup.$(date +%Y%m%d_%H%M%S)"
        echo -e ${green}已备份现有SSH配置文件${background}
    fi
    
    # 删除GitHub相关配置
    if grep -q "Host github.com" "$ssh_config_file" 2>/dev/null; then
        echo -e ${yellow}正在删除现有GitHub SSH配置...${background}
        sed -i '/^Host github\.com$/,/^$/d' "$ssh_config_file" 2>/dev/null
    fi
    
    # 删除Git全局URL重写
    echo -e ${cyan}正在清除Git全局URL重写配置...${background}
    git config --global --unset url."ssh://git@ssh.github.com:443".insteadOf 2>/dev/null
    
    echo -e ${green}GitHub SSH 22端口配置完成！${background}
    echo -e ${cyan}现在将使用默认的22端口连接GitHub${background}
    
    echo -e ${cyan}建议运行测试以确认配置正确${background}
    echo -en ${cyan}回车返回${background}
    read
    configure_github_ssh_port
}

# 显示当前SSH配置
show_ssh_config(){
    echo -e ${cyan}当前SSH配置：${background}
    ssh_config_file="$HOME/.ssh/config"
    
    if [ -f "$ssh_config_file" ]; then
        if grep -A 10 "Host github.com" "$ssh_config_file" 2>/dev/null; then
            echo ""
        else
            echo -e ${yellow}未找到GitHub相关配置，使用默认设置${background}
        fi
    else
        echo -e ${yellow}SSH配置文件不存在，使用默认设置${background}
    fi
    
    echo ""
    echo -e ${cyan}Git全局URL重写配置：${background}
    git_rewrite=$(git config --global --get url."ssh://git@ssh.github.com:443".insteadOf 2>/dev/null)
    if [ ! -z "$git_rewrite" ]; then
        echo -e ${green}已配置：ssh://git@ssh.github.com:443 -> $git_rewrite${background}
    else
        echo -e ${yellow}未配置Git全局URL重写${background}
    fi
    
    echo -en ${cyan}回车返回${background}
    read
    configure_github_ssh_port
}

# 测试SSH连接
test_ssh_connection(){
    echo -e ${cyan}正在测试GitHub SSH连接...${background}
    echo -e ${yellow}请稍等，正在连接...${background}
    
    # 测试SSH连接
    ssh_output=$(ssh -T git@github.com 2>&1)
    ssh_exit_code=$?
    
    echo ""
    echo -e ${cyan}SSH测试结果：${background}
    echo -e ${yellow}$ssh_output${background}
    echo ""
    
    if [[ "$ssh_output" == *"You've successfully authenticated"* ]]; then
        echo -e ${green}✓ SSH连接测试成功！${background}
        echo -e ${green}GitHub SSH配置正常工作${background}
    elif [[ "$ssh_output" == *"Permission denied"* ]]; then
        echo -e ${red}✗ SSH连接失败：权限被拒绝${background}
        echo -e ${yellow}可能原因：${background}
        echo -e ${yellow}1. SSH密钥未添加到GitHub账户${background}
        echo -e ${yellow}2. SSH密钥路径不正确${background}
        echo -e ${yellow}3. SSH密钥权限设置错误${background}
    elif [[ "$ssh_output" == *"Connection timed out"* ]] || [[ "$ssh_output" == *"Network is unreachable"* ]]; then
        echo -e ${red}✗ SSH连接失败：网络连接问题${background}
        echo -e ${yellow}可能原因：${background}
        echo -e ${yellow}1. 网络防火墙阻止了SSH连接${background}
        echo -e ${yellow}2. ISP阻止了GitHub的SSH端口${background}
        echo -e ${yellow}建议尝试使用443端口配置${background}
    else
        echo -e ${yellow}⚠ SSH连接状态未知${background}
        echo -e ${yellow}请检查上述输出信息${background}
    fi
    
    echo -en ${cyan}回车返回${background}
    read
    configure_github_ssh_port
}

ChangeLogLevel(){
file="config/config/bot.yaml"
if [ ! -e ${file} ];then
    echo -e ${red}文件不存在${background}
    echo -en ${cyan}回车返回${background}
    read
    return
fi

# 读取并显示当前日志等级
current_log_level=$(grep "log_level:" ${file} | awk '{print $2}')
if [ -z "${current_log_level}" ]; then
    current_log_level="未设置"
fi

echo -e ${white}"====="${green}日志等级${white}"====="${background}
echo -e ${cyan}当前日志等级: ${yellow}${current_log_level}${background}
echo ""
echo -e ${green}请选择日志等级${background}
echo -e  ${green} 1. ${cyan}trace${background}
echo -e  ${green} 2. ${cyan}debug${background}
echo -e  ${green} 3. ${cyan}info ${yellow}\(默认\)${background}
echo -e  ${green} 4. ${cyan}mark ${yellow}\(不显示聊天记录\)${background}
echo -e  ${green} 5. ${cyan}warn${background}
echo -e  ${green} 6. ${cyan}fatal${background}
echo -e  ${green} 7. ${cyan}error${background}
echo -e  ${green} 8. ${cyan}off${background}
echo "========================="
echo -en ${green}请输入您的选项: ${background};read num
case ${num} in
  1)
    LogLevel="trace"
    ;;
  2)
    LogLevel="debug"
    ;;
  3)
    LogLevel="info"
    ;;
  4)
    LogLevel="mark"
    ;;
  5)
    LogLevel="warn"
    ;;
  6)
    LogLevel="fatal"
    ;;
  7)
    LogLevel="error"
    ;;
  8)
    LogLevel="off"
    ;;
  *)
    echo -e ${red}输入错误${background}
    echo -en ${cyan}回车返回${background}
    read
    return
    ;;
esac
OldLogLevel=$(grep "log_level:" ${file})
NewLogLevel="log_level: ${LogLevel}"
sed -i "s/${OldLogLevel}/${NewLogLevel}/g" ${file}
echo -e ${green}日志等级已修改为: ${cyan}${LogLevel}${background}
echo -en ${green}修改完成 ${cyan}回车返回${background}
read
}

# GitHub加速主函数
change_github_proxy(){
    while true; do
        echo -e ${white}"====="${green}GitHub 加速管理${white}"====="${background}
        echo -e ${green}请选择您的操作${background}
        echo -e  ${green} 1. ${cyan}查看所有git仓库地址${background}
        echo -e  ${green} 2. ${cyan}修改单个仓库加速${background}
        echo -e  ${green} 3. ${cyan}批量操作所有仓库${background}
        echo -e  ${green} 4. ${cyan}配置GitHub SSH端口${background}
        echo -e  ${green} 0. ${cyan}返回上级菜单${background}
        echo "========================="
        echo -en ${green}请输入您的选项: ${background}
        read num
        
        case $num in
            1)
                if show_git_repos; then
                    echo -en ${cyan}回车返回${background}
                    read
                fi
                ;;
            2)
                modify_single_repo
                ;;
            3)
                batch_modify_repos
                ;;
            4)
                configure_github_ssh_port
                ;;
            0)
                return
                ;;
            *)
                echo -e ${red}输入错误${background}
                echo -en ${cyan}回车继续${background}
                read
                ;;
        esac
    done
}

echo -e ${white}"====="${green}呆毛版-Script${white}"====="${background}
echo -e ${green}请选择您的操作[${Bot_Name}]${background}
echo -e  ${green} 1. ${cyan}修改登录账号${background}
echo -e  ${green} 2. ${cyan}修改登录设备${background}
echo -e  ${green} 3. ${cyan}修改主人账号${background}
echo -e  ${green} 4. ${cyan}重装依赖文件${background}
echo -e  ${green} 5. ${cyan}修复监听错误${background}
echo -e  ${green} 6. ${cyan}降级pptr版本${background}
echo -e  ${green} 7. ${cyan}更新NodeJS版本${background}
echo -e  ${green} 8. ${cyan}修改ffmpeg路径${background}
echo -e  ${green} 9. ${cyan}修改浏览器路径${background}
echo -e  ${green}10. ${cyan}修改锅巴插件端口${background}
echo -e  ${green}11. ${cyan}修改锅巴插件地址${background}
echo -e  ${green}12. ${cyan}修改日志等级${background}
echo -e  ${green}13. ${cyan}插件GitHub加速${background}
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
    ReloadPackage
    ;;
  5)
    RepairSqlite3
    ;;
  6)
    LowerPptr
    ;;
  7)
    UpdateNodeJS
    ;;
  8)
    FfmpegPath
    ;;
  9)
    BrowserPath
    ;;
  10)
    ChangePort
    ;;
  11)
    ChangeHost
    ;;
  12)
    ChangeLogLevel
    ;;
  13)
    change_github_proxy
    ;;
#   99)
#     BotBackup
#     ;;
  *)
    echo -e ${red}输入错误${background}
    exit
    ;;
esac