#!/bin/bash
# 把 resources/{node,dsh} 装配成 Xcode 能打包的资源目录
set -e
cd "$(dirname "$0")/.."

echo "==> 装配 node 二进制"
mkdir -p DashHarness/node
cp resources/node DashHarness/node/node
chmod +x DashHarness/node/node

echo "==> 装配 dsh(node_modules 树)"
rm -rf DashHarness/dsh
cp -R resources/dsh DashHarness/dsh

# 清理占体积/无用的大目录
rm -rf DashHarness/dsh/node_modules/.cache 2>/dev/null || true
find DashHarness/dsh/node_modules -name "*.md" -delete 2>/dev/null || true

echo "==> 资源体积"
du -sh DashHarness/dsh DashHarness/node 2>/dev/null