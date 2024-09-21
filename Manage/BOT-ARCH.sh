#!/bin/env bash
cd $HOME
export red="\033[31m"
export green="\033[32m"
export yellow="\033[33m"
export blue="\033[34m"
export purple="\033[35m"
export cyan="\033[36m"
export white="\033[37m"
export background="\033[0m"
case $(uname -m) in
    x86_64|amd64)
    export ARCH=x64
;;
    arm64|aarch64)
    export ARCH=arm64
;;
*)
    echo ${red}您的框架为${yellow}$(uname -m)${red},快提issue做适配.${background}
    exit
;;
esac