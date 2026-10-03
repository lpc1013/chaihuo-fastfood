#!/usr/bin/env python3
"""把三张老柴头像补一圈留白、让「狗头」落在画布正中。

原图把头画满了整张正方画布（耳尖甚至被上沿切掉），而 draw_texture_circle 是把
正方画布内切进圆里的 —— 于是圆一裁，耳尖和两腮必然被啃掉，脸看着压在圆框下半部。
这里不重画美术，只做两件事：
  1. 只统计「头部」范围（画布上沿到 78% 高）的墨迹，围巾和肩膀不参与定心；
  2. 新建一张更大的正方画布，把头部中心对到画布中心，边长取头部外接圆直径 ×1.06，
     这样内切圆刚好把耳朵整个包住。
"""
import os
import shutil
from PIL import Image

NAMES = ["avatar_chef", "avatar_shock", "avatar_side"]
HEAD_FRAC = 0.78
MARGIN = 1.06
ALPHA = 40
ART = "assets/art/characters"
BAK = "assets/incoming/_bak_av_tight"


def head_metrics(px, w, h):
    """返回头部墨迹的 bbox 与它绕自身中心的外接圆半径。只算头部那条带，围巾不算。"""
    xs = []
    ys = []
    for y in range(h):
        for x in range(w):
            if px[x, y][3] > ALPHA:
                xs.append(x)
                ys.append(y)
    if not xs:
        raise SystemExit("empty sprite")
    top = min(ys)
    hy1 = min(max(ys), top + int(h * HEAD_FRAC))
    hx0, hx1 = min(xs), max(xs)
    cx = (hx0 + hx1) / 2.0
    cy = (top + hy1) / 2.0
    r = 0.0
    for y in range(top, hy1 + 1):
        for x in range(w):
            if px[x, y][3] > ALPHA:
                d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
                if d > r:
                    r = d
    return (hx0, top, hx1, hy1), cx, cy, r


def main():
    if not os.path.isdir(BAK):
        os.makedirs(BAK)
    for n in NAMES:
        src = "%s/%s.png" % (ART, n)
        bak = "%s/%s.png" % (BAK, n)
        if not os.path.exists(bak):
            shutil.copy2(src, bak)
        im = Image.open(src).convert("RGBA")
        w, h = im.size
        box, cx, cy, r = head_metrics(im.load(), w, h)
        side = int((2 * r * MARGIN + 8) // 2 * 2) + 2
        out = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        out.alpha_composite(im, (int(round(side / 2 - cx)), int(round(side / 2 - cy))))
        out.save(src)
        print("%-14s %dx%d -> %dx%d  head bbox=%s center=(%.0f,%.0f) R=%.0f" % (
            n, w, h, side, side, box, cx, cy, r))


main()
