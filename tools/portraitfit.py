"""算 UiKit.PORTRAIT_HEAD 的锚点：焦点=头中心，缩放取"所有头部像素都落在圆内"的最大值。

  python tools/portraitfit.py [图片路径 ...]

为什么要有这个脚本：圆框人像的 focus/zoom 是三个互相牵连的量 —— 焦点往下挪能露出脸，
但缩放一大，耳朵尖就掉到圆外被切掉（用户报的"抠图漏了耳朵"就是这个）。
以前这几个数是画网格目测的，目测看不出"哪个角差几个像素"。
这里按 draw_texture_circle 的真实映射逐像素验：
  s = min(W,H)/zoom;  uw = s/W;  vh = s/H
  窗口 (u0..u0+uw, v0..v0+vh) 铺满圆的外切正方形，
  纹理点 uv 落在圆内 ⟺ ((uv.x-u0)/uw - 0.5)^2 + ((uv.y-v0)/vh - 0.5)^2 <= 0.5^2
"""
import os
import sys

import numpy as np
from PIL import Image

DEFAULTS = [
    "assets/art/characters/chef_smirk.png",
    "assets/art/characters/chef_side.png",
    "assets/art/characters/chef_shock.png",
    "assets/art/characters/avatar_chef.png",
]

# 头占整张立绘的多高：再往下就是肩膀/围裙，把它们算进来会把人缩得太小
# ⚠ 这条对"脸特别长"的方头像不成立：avatar_chef 的口鼻一直伸到 alpha 高度的 0.85，
# 按 0.52 截会把下半张脸当成身体，算出来的焦点偏高（那张的锚点是目测 + 用户过目的，
# 不要拿本脚本的结果覆盖它）。要动那张就先把 HEAD_FRAC 按张调，再肉眼复验。
HEAD_FRAC = 0.52
# 留一点余量，别让耳朵尖正好压在圆弧上
SAFE = 0.475


def head_points(path):
    a = np.asarray(Image.open(path).convert("RGBA")).astype(int)
    al, h, w = a[..., 3], a.shape[0], a.shape[1]
    ys, xs = np.nonzero(al > 24)
    if len(xs) == 0:
        return None
    top, bot = ys.min(), ys.max()
    cut = top + (bot - top) * HEAD_FRAC
    keep = ys <= cut
    hx, hy = xs[keep].astype(float), ys[keep].astype(float)
    return w, h, hx / w, hy / h


def fits(u0, v0, uw, vh, hx, hy):
    qx = (hx - u0) / uw - 0.5
    qy = (hy - v0) / vh - 0.5
    return float(np.max(qx * qx + qy * qy)) <= SAFE * SAFE


def solve(path):
    got = head_points(path)
    if got is None:
        return None
    w, h, hx, hy = got
    cx = (hx.min() + hx.max()) / 2.0
    cy = (hy.min() + hy.max()) / 2.0
    lo, hi = 1.0, 4.0
    best = 1.0
    for _ in range(40):
        mid = (lo + hi) / 2.0
        s = min(w, h) / mid
        uw, vh = s / w, s / h
        u0 = min(max(cx - uw / 2.0, 0.0), 1.0 - uw)
        v0 = min(max(cy - vh / 2.0, 0.0), 1.0 - vh)
        if fits(u0, v0, uw, vh, hx, hy):
            best = mid
            lo = mid
        else:
            hi = mid
    # 焦点取头心，但窗口不能越界，越界时按 draw_texture_circle 的 clamp 反推有效焦点
    s = min(w, h) / best
    uw, vh = s / w, s / h
    fx = min(max(cx, uw / 2.0), 1.0 - uw / 2.0)
    fy = min(max(cy, vh / 2.0), 1.0 - vh / 2.0)
    return {"focus": (round(fx, 3), round(fy, 3)), "zoom": round(best, 2),
            "head_w": round(float(hx.max() - hx.min()), 3),
            "head_h": round(float(hy.max() - hy.min()), 3)}


def main():
    paths = sys.argv[1:] or DEFAULTS
    print("%-26s %-22s %s" % ("sprite", "锚点 [fx, fy, zoom]", "头部占图 / 建议"))
    for p in paths:
        if not os.path.exists(p):
            print("%-26s 文件不存在" % os.path.basename(p))
            continue
        r = solve(p)
        if r is None:
            print("%-26s 全透明？" % os.path.basename(p))
            continue
        print("%-26s [%s, %s, %s]   头宽 %.2f 头高 %.2f  <- %s" % (
            os.path.basename(p), r["focus"][0], r["focus"][1], r["zoom"],
            r["head_w"], r["head_h"],
            '"characters/%s": [%s, %s, %s],' % (
                os.path.basename(p).replace(".png", ""),
                r["focus"][0], r["focus"][1], r["zoom"])))


if __name__ == "__main__":
    main()
