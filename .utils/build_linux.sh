#!/bin/bash

# ============================================
# 构建产品信息
app_name="Streack Resourcepack"
app_productid="com.github.streackmc.streack-resourcepack"
app_output_name="streack_res"
# ============================================



## code
# 注入日志实现
trap 'errcode=$? ; printf "err: 无法完成编译，第 $LINENO 行的命令未正常执行，其返回了 $errcode 。\n" "$(date '+%H:%M:%S')" ; exit $errcode' ERR
set -euo pipefail
NC='\033[0m'
BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
BOLD='\033[1m'
BBLACK='\033[1;30m'
BRED='\033[1;31m'
BGREEN='\033[1;32m'
BYELLOW='\033[1;33m'
BBLUE='\033[1;34m'
BPURPLE='\033[1;35m'
BCYAN='\033[1;36m'
BWHITE='\033[1;37m'
UNDERLINE='\033[4m'
BG_BLACK='\033[40m'
BG_RED='\033[41m'
BG_GREEN='\033[42m'
BG_YELLOW='\033[43m'
BG_BLUE='\033[44m'
BG_PURPLE='\033[45m'
BG_CYAN='\033[46m'
BG_WHITE='\033[47m'
ts_log() {
  while IFS= read -r line; do
    local FONTC=${NC}[I]
    
    if [[ "$line" =~ (^|[^a-zA-Z])[Ee][Rr][Rr]([:：])?([Oo][Rr])?([:：])?([^a-zA-Z]|$) ]]; then
      FONTC=${BRED}[E]
    elif [[ "$line" =~ 错误 ]]; then
      FONTC=${BRED}[E]
    elif [[ "$line" =~ (^|[^a-zA-Z])[Ww][Aa][Rr][Nn]([:：])?([Ii][Nn][Gg])?([:：])?([^a-zA-Z]|$) ]]; then
      FONTC=${BYELLOW}[W]
    elif [[ "$line" =~ 警告 ]]; then
      FONTC=${BYELLOW}[W]
    elif [[ "$line" =~ (^|[^a-zA-Z])[Nn][Oo][Tt][Ee]([:：])?([Ss])?([:：])?([^a-zA-Z]|$) ]]; then
      FONTC=${BBLUE}[N]
    elif [[ "$line" =~ (^|[^a-zA-Z])[Tt][Ii][Pp]([:：])?([Ss])?([:：])?([^a-zA-Z]|$) ]]; then
      FONTC=${BBLUE}[N]
    elif [[ "$line" =~ 注意 ]]; then
      FONTC=${BBLUE}[N]
    elif [[ "$line" =~ 提示 ]]; then
      FONTC=${BBLUE}[N]
    fi
    
    printf "${NC}[%s]${FONTC} %s${NC}\n" "$(date '+%H:%M:%S')" "$line"
  done
}
exec > >(ts_log)
exec 2>&1

buildtool_ver="0.2.0"

echo -e "${BOLD}${BPURPLE}StreackMC Buildtool for ${UNDERLINE}MCPACK"
echo -e "${BCYAN}v${buildtool_ver}"
echo -e "${BCYAN}Copyright (C) 2026, kdxiaoyi & StreackMC. All rights reserved."
echo -e "${NC}准备构建${app_name} (${app_productid})"

echo -e "${NC}${BOLD}${CYAN}# 校验环境信息"
if ! command -v zip >/dev/null 2>&1; then
  echo -e "${BRED}err: 没有发现可用的 zip 软件包。请安装："
  echo -e "${YELLOW}> sudo apt install zip"
  exit 1
fi
if ! command -v git >/dev/null 2>&1; then
  echo -e "${BRED}err: 没有发现可用的 Git 软件包。请安装："
  echo -e "${YELLOW}> sudo apt install git"
  exit 1
fi
if [[ ! -d "./.git" ]]; then
  echo -e "${BRED}err: 无法读取版本信息。"
  echo -e "${BRED}err: 没有在 Git 仓库的${BOLD}根目录${NC}${RED}下运行此脚本，或当前 Git 仓库无法读取。"
  echo -e "${YELLOW}需要在项目根目录运行本脚本。"
  exit 1
fi
sysenv="Linux[$(uname -m)]_$(uname -r)@${1:-unknownOrigin}"
echo -e "${NC}当前构建环境信息：${sysenv}"
git_rev=$(git rev-parse --short HEAD)
git_branch=$(git rev-parse --short --abbrev-ref HEAD)
git_ver="${git_branch}@${git_rev}"
echo -e "${NC}当前 Git 指针位于：${git_ver}"

echo -e "${NC}${BOLD}${CYAN}# 准备工作目录"
ls ./target
echo -e "${BYELLOW}目录 ./target 下的上述文件将被永久删除。"
rm -rf target
mkdir -p target

echo -e "${NC}${BOLD}${CYAN}# 开始打包"
zip -r9 ./target/${app_output_name}-${git_ver}.zip \
  ./data/* \
  ./license.txt \
  ./pack.mcmeta \
  ./pack.png \
  "./README ‖ 读我.txt" \
  ./Reference_License.txt

echo -e "${NC}${BOLD}${CYAN}# 附加构建信息"
echo -e "${NC}${GREEN}正在生成构建信息："
echo "build-tool=Streack-mcpack_BuildTool
build-tool-version=${buildtool_ver}
build-env=${sysenv}
git-rev=${git_rev}
git-branch=${git_branch}
timestamp=$(date +%s)
time=$(date +%Y-%m-%d_%H:%M:%S_%Z)
product-name=${app_name}
product-id=${app_productid}" >> ./target/build.properties
cat ./target/build.properties
echo -e "${NC}${GREEN}生成构建信息完成"
zip -j9 ./target/${app_output_name}-${git_ver}.zip ./target/build.properties

echo -e "${NC}${BOLD}${BGREEN}打包完成产物已保存到 ./target/${app_output_name}-${git_ver}.zip"
exit 0