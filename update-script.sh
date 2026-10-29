#!/usr/bin/env bash
# 拉取上游最新面板脚本（raw 优先，jsDelivr 兜底），并校验体积。
set -euo pipefail

cd "$(dirname "$0")"
TARGET="script/zeeho_box_enhanced.js"
RAW="https://raw.githubusercontent.com/cluck798/ZEEHO/refs/heads/main/script/zeeho_box_enhanced.js"
CDN="https://cdn.jsdelivr.net/gh/cluck798/ZEEHO@main/script/zeeho_box_enhanced.js"

tmp="$(mktemp)"
ok=0
for url in "$RAW" "$CDN"; do
  echo "→ 尝试 $url"
  if curl -fsSL --connect-timeout 10 --max-time 120 "$url" -o "$tmp"; then
    size=$(wc -c <"$tmp" | tr -d ' ')
    if [ "$size" -gt 200000 ]; then
      ok=1
      break
    fi
    echo "  文件过小（${size}B），视为失败"
  fi
done

if [ "$ok" -ne 1 ]; then
  echo "✗ 下载失败，保留原脚本不动" >&2
  rm -f "$tmp"
  exit 1
fi

mkdir -p script
cp "$tmp" "$TARGET"
rm -f "$tmp"

ver=$(grep -m1 -oE '#!version=[0-9]+\.[0-9]+\.[0-9]+' "$TARGET" | cut -d= -f2 || true)
echo "✓ 已更新 $TARGET  版本 ${ver:-unknown}  大小 $(wc -c <"$TARGET" | tr -d ' ')B"
echo "  重启生效：docker compose restart"
