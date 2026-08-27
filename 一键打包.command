#!/bin/zsh
# 双击本文件即可完成 App 构建和 DMG 打包。
set -euo pipefail

PROJECT_DIR="${0:A:h}"

finish() {
    local status=$?
    trap - EXIT
    set +e
    echo
    if [[ $status -eq 0 ]]; then
        echo "✅ 一键打包完成，安装包位于 dist 文件夹。"
        if [[ -t 0 ]]; then
            open "$PROJECT_DIR/dist"
        fi
    else
        echo "❌ 打包失败，请查看上方错误信息。"
    fi
    if [[ -t 0 ]]; then
        echo "按回车键关闭窗口…"
        read -r
    fi
    exit $status
}
trap finish EXIT

"$PROJECT_DIR/scripts/build-dmg.sh"
