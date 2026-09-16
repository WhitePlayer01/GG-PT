#!/bin/sh
# 此入口将固定动作交给本地发布服务，不需要逐步调用模型。
# 跨机器使用时通过 XHS_PUBLISHER_DIR 指向服务目录；不在技能中保存登录信息。
set -eu
publisher_dir=${XHS_PUBLISHER_DIR:-'/Users/mw/Desktop/探索/红薯项目/项目1/tools/xiaohongshu-publisher'}
if [ ! -f "$publisher_dir/src/cli.mjs" ]; then
  echo '找不到发布服务，请设置 XHS_PUBLISHER_DIR 指向 xiaohongshu-publisher 目录。' >&2
  exit 1
fi
exec node "$publisher_dir/src/cli.mjs" "$@"
