#!/usr/bin/env bash
# 串行跑即梦批次：提交 → 等出图 → 收预览 → 拼联络表。
# 用法：bash tools/jmpipe.sh B2 C1 C2 C3
cd "$(dirname "$0")/.." || exit 1
for j in "$@"; do
  echo "=== [$j] submit $(date +%H:%M:%S)"
  python tools/jmkit.py submit "tools/jm/job_$j.json" 2>&1 \
    | grep -oE '"(tag|ok|err|bar)": "?[^,"}]*"?' | paste -sd' ' -
  echo "=== [$j] wait $(date +%H:%M:%S)"
  sleep 55
  echo "=== [$j] collect $(date +%H:%M:%S)"
  python tools/jmkit.py collect "tools/jm/job_$j.json" 2>&1 \
    | grep -oE '"(tag|got)": "?[^,"}]*"?' | paste -sd' ' -
  out=$(python -c "import json,sys;print(json.load(open('tools/jm/job_$j.json',encoding='utf-8'))['out'])")
  tags=$(python -c "import json;print(' '.join(b['tag'] for b in json.load(open('tools/jm/job_$j.json',encoding='utf-8'))['batches']))")
  python tools/sheet.py "$out" $tags
done
echo "=== done $(date +%H:%M:%S)"
