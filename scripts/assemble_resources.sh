#!/bin/bash
# 装配：把 resources/{node,dsh} 备好（注入 .app 的动作在 build_ipa.sh 里做）
set -e
cd "$(dirname "$0")/.."

echo "==> 检查资源"
test -f resources/node || { echo "!! resources/node 缺失"; exit 1; }
test -d resources/dsh/node_modules || { echo "!! resources/dsh 缺失"; exit 1; }

echo "==> 清理大文件"
rm -rf resources/dsh/node_modules/.cache 2>/dev/null || true
find resources/dsh/node_modules -name "*.md" -delete 2>/dev/null || true

echo "==> 资源体积"
du -sh resources/dsh resources/node 2>/dev/null