#!/bin/bash
# RomanceCharm 打包+安装脚本
# 用法：在 Git Bash 里运行 ./pack.sh（游戏必须先关闭，否则 zip 被占用）
set -e
cd "$(dirname "$0")"
TARGET="/d/SteamLibrary/steamapps/workshop/content/1942280/3790215220/RomanceCharm.zip"
rm -f "$TARGET"
zip -r "$TARGET" mods-unpacked
echo "OK -> $TARGET"
