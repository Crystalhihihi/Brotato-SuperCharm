#!/bin/bash
# SuperCharm 打包+安装脚本
# 用法：在 Git Bash 里运行 ./pack.sh（游戏必须先关闭，否则 zip 被占用写入失败）
# 仓库根目录即 mod 源码，打包时拼出 mods-unpacked/Crystalhihihi-SuperCharm/ 内部结构
# 产出 publish/RomanceCharm.zip 与「超级魅惑 SuperCharm.zip」（后者文件名=工坊条目标题），
# 并覆盖本地工坊文件夹 3796762706（该文件夹里只能有这一个 zip，同名覆盖）
set -e
cd "$(dirname "$0")"
ROOT="$(pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/mods-unpacked/Crystalhihihi-SuperCharm"
cp -r manifest.json mod_main.gd icon.png content effects "$STAGE/mods-unpacked/Crystalhihihi-SuperCharm/"
rm -f publish/RomanceCharm.zip
(cd "$STAGE" && zip -r -q "$ROOT/publish/RomanceCharm.zip" mods-unpacked -x "*.DS_Store")
cp publish/RomanceCharm.zip "publish/超级魅惑 SuperCharm.zip"
cp "publish/超级魅惑 SuperCharm.zip" "/d/SteamLibrary/steamapps/workshop/content/1942280/3796762706/超级魅惑 SuperCharm.zip"
echo "OK -> publish/ + workshop 3796762706"
