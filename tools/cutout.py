"""绿幕/键色抠图：边缘泛洪去底 + 去溢色 + 裁边 + 统一高度。

  python tools/cutout.py in.png out.png [--key green|magenta|white|auto] [--h 512] [--pad 6]
  python tools/cutout.py --batch map.json        # {"in.png": "out.png", ...}

泛洪只从画面四边起手，所以物体内部同色区域（比如饮料机里的绿色果汁）不会被误删。
"""
import argparse
import json
import sys
from collections import deque
from pathlib import Path

from PIL import Image


def detect_key(px, w, h):
    """按四边主色猜键色。"""
    from collections import Counter
    c = Counter()
    for x in range(0, w, max(1, w // 40)):
        for y in (0, h - 1):
            c[px[x, y][:3]] += 1
    for y in range(0, h, max(1, h // 40)):
        for x in (0, w - 1):
            c[px[x, y][:3]] += 1
    r, g, b = max(c, key=c.get)
    return (r, g, b)


def key_test(kind, rgb):
    r, g, b = rgb[:3]
    if kind == "green":
        return g > 110 and g > r + 35 and g > b + 35
    if kind == "magenta":
        return r > 110 and b > 75 and r > g + 40 and b > g + 12
    if kind == "white":
        return r > 228 and g > 228 and b > 228
    return False


def cutout(src: Path, dst: Path, kind="green", height=None, pad=6, shrink=1, holes=False):
    im = Image.open(src).convert("RGBA")
    w, h = im.size
    px = im.load()
    if kind == "auto":
        k = detect_key(px, w, h)
        r, g, b = k
        kind = "green" if (g > r and g > b) else ("magenta" if (r > g and b > g) else "white")
        test = lambda c: abs(c[0] - r) < 46 and abs(c[1] - g) < 46 and abs(c[2] - b) < 46
    else:
        test = lambda c: key_test(kind, c)

    gone = bytearray(w * h)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            q.append((x, y))
    while q:
        x, y = q.popleft()
        i = y * w + x
        if gone[i]:
            continue
        c = px[x, y]
        if c[3] == 0 or test(c):
            gone[i] = 1
            if x: q.append((x - 1, y))
            if x < w - 1: q.append((x + 1, y))
            if y: q.append((x, y - 1))
            if y < h - 1: q.append((x, y + 1))

    if holes:
        # 边框泛洪够不到的封闭键色区（圆环中间的洞）：按连通块清掉大块，保留小片绿叶之类的前景
        comp = bytearray(w * h)
        for y in range(h):
            for x in range(w):
                i = y * w + x
                if gone[i] or not test(px[x, y]):
                    continue
                q2 = deque([(x, y)])
                blob = []
                while q2:
                    bx, by = q2.popleft()
                    j = by * w + bx
                    if gone[j] or comp[j] or not test(px[bx, by]):
                        continue
                    comp[j] = 1
                    blob.append(j)
                    if bx: q2.append((bx - 1, by))
                    if bx < w - 1: q2.append((bx + 1, by))
                    if by: q2.append((bx, by - 1))
                    if by < h - 1: q2.append((bx, by + 1))
                if len(blob) > 0.08 * w * h:
                    for j in blob:
                        gone[j] = 1

    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    op = out.load()
    for y in range(h):
        for x in range(w):
            i = y * w + x
            if gone[i]:
                continue
            r, g, b, a = px[x, y]
            near = False
            for dy in (-2, -1, 0, 1, 2):
                yy = y + dy
                if yy < 0 or yy >= h:
                    continue
                for dx in (-2, -1, 0, 1, 2):
                    xx = x + dx
                    if 0 <= xx < w and gone[yy * w + xx]:
                        near = True
                        break
                if near:
                    break
            edge = ((y > 0 and gone[i - w]) or (y < h - 1 and gone[i + w])
                    or (x > 0 and gone[i - 1]) or (x < w - 1 and gone[i + 1]))
            if near:  # 去溢色只处理贴着背景的两圈，否则绿色食材会被整体压成橄榄褐
                if kind == "green" and g > r and g > b:
                    g = min(r, b) + int((g - min(r, b)) * 0.45)
                elif kind == "magenta":
                    r = min(g, b) + int((r - min(g, b)) * 0.45)
                    b = min(g, b) + int((b - min(g, b)) * 0.45)
            op[x, y] = (r, g, b, 140 if edge and shrink else 255)

    if shrink:
        bbox = out.getbbox()
        if bbox:
            out = out.crop(bbox)
    if height:
        r = height / out.size[1]
        out = out.resize((max(1, int(out.size[0] * r)), height), Image.LANCZOS)
    if pad:
        canvas = Image.new("RGBA", (out.size[0] + pad * 2, out.size[1] + pad * 2), (0, 0, 0, 0))
        canvas.paste(out, (pad, pad), out)
        out = canvas
    dst.parent.mkdir(parents=True, exist_ok=True)
    out.save(dst)
    return out.size


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src", nargs="?")
    ap.add_argument("dst", nargs="?")
    ap.add_argument("--key", default="green")
    ap.add_argument("--h", type=int, default=None)
    ap.add_argument("--pad", type=int, default=6)
    ap.add_argument("--holes", action="store_true")
    ap.add_argument("--batch")
    a = ap.parse_args()
    if a.batch:
        m = json.loads(Path(a.batch).read_text(encoding="utf-8"))
        for s, d in m.items():
            print(s, "->", cutout(Path(s), Path(d), a.key, a.h, a.pad, holes=a.holes))
        return 0
    print(cutout(Path(a.src), Path(a.dst), a.key, a.h, a.pad, holes=a.holes))
    return 0


if __name__ == "__main__":
    sys.exit(main())
