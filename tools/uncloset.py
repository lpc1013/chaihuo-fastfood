"""抠掉「被透明像素包住的实心底色块」。

绿幕泛洪只能从画面四边起手，所以生图里那种「食物摆在一张米色纸/白底方块上」的
情况会留下一整块不透明的封闭底色。这里从贴着透明的边界环起手，在封闭的同色区域里
再泛洪一次，只吃连通的底色，食物内部的高光同色块因为被轮廓包住不会漏。

  python tools/uncloset.py a.png b.png ...            # 自动取边界主色
  python tools/uncloset.py --tol 34 a.png
"""
import argparse
import sys
from collections import Counter, deque
from pathlib import Path

import numpy as np
from PIL import Image


def edge_key(a):
    """贴着透明区的那一圈不透明像素里最常见的颜色就是残留底色。"""
    al = a[..., 3]
    opaque = al > 0
    empty = al == 0
    nbr_empty = np.zeros_like(opaque)
    for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        nbr_empty |= np.roll(empty, (dy, dx), axis=(0, 1))
    ring = opaque & nbr_empty
    px = a[ring][:, :3]
    if px.size == 0:
        return None
    q = (px // 6 * 6)
    c = Counter(map(tuple, q))
    return np.array(c.most_common(1)[0][0], dtype=np.int16)


def flood(a, key, tol):
    rgb = a[:, :, :3].astype(np.int16)
    d = np.abs(rgb - key).max(axis=2)
    cand = (a[..., 3] > 0) & (d <= tol)
    empty = a[..., 3] == 0
    nbr_empty = np.zeros_like(cand)
    for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        nbr_empty |= np.roll(empty, (-dy, -dx), axis=(0, 1))
    seeds = np.argwhere(cand & nbr_empty)
    seen = np.zeros_like(cand)
    q = deque(map(tuple, seeds))
    for p in q:
        seen[p] = True
    h, w = cand.shape
    while q:
        y, x = q.popleft()
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and cand[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                q.append((ny, nx))
    return seen


def run(path, tol, pad):
    im = Image.open(path).convert("RGBA")
    a = np.array(im)
    if a[..., 3].min() > 0:
        print("  跳过：整图不透明，没有可起手的外轮廓", path)
        return
    key = edge_key(a)
    if key is None:
        print("  跳过：找不到边界主色", path)
        return
    holes = flood(a, key, tol)
    share = float(holes.sum()) / max(1.0, float((a[..., 3] > 0).sum()))
    if share < 0.06:
        print("  干净（封闭底色只占 %.1f%%）%s" % (share * 100, path))
        return
    a[holes, 3] = 0
    ys, xs = np.nonzero(a[..., 3] > 0)
    y0, y1 = ys.min(), ys.max() + 1
    x0, x1 = xs.min(), xs.max() + 1
    crop = a[y0:y1, x0:x1]
    out = Image.fromarray(crop)
    out.save(path)
    print("  清掉 %.1f%% 底色，%s -> %dx%d" % (share * 100, path, out.size[0], out.size[1]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--tol", type=int, default=28)
    ap.add_argument("--pad", type=int, default=0)
    n = ap.parse_args()
    for f in n.files:
        p = Path(f)
        if not p.exists():
            print("缺文件", p, file=sys.stderr)
            continue
        run(p, n.tol, n.pad)


if __name__ == "__main__":
    main()
