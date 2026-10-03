#!/usr/bin/env python3
"""从 kitchen/wood_pile.png 里拆出「斧头」和「单根柴」两个精灵。

柴垛是一张已经抠好透明底的图，斧头插在最上面那根柴上，两者只在刃口处相接。
所以做法是：先按 alpha>24 得到实心掩码，在刃口与柴的接缝处放一道闸门，
然后从斧头内部种子做连通域 = 斧头；把斧头像素挖掉后再从柴内部做连通域 = 柴。
"""
import sys
from collections import deque
from PIL import Image

SRC = "assets/art/kitchen/wood_pile.png"
ALPHA = 24


def load():
    im = Image.open(SRC).convert("RGBA")
    px = im.load()
    return im, px


def solid_map(px, w, h):
    return [[px[x, y][3] > ALPHA for y in range(h)] for x in range(w)]


def component(solid, gates, seeds):
    w, h = len(solid), len(solid[0])

    def open_(x, y):
        if not solid[x][y]:
            return False
        for g in gates:
            if g(x, y):
                return False
        return True

    seen = [[False for _ in range(h)] for _ in range(w)]
    q = deque()
    for s in seeds:
        if open_(*s) and not seen[s[0]][s[1]]:
            seen[s[0]][s[1]] = True
            q.append(s)
    n = 0
    while q:
        x, y = q.popleft()
        n += 1
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)):
            a, b = x + dx, y + dy
            if 0 <= a < w and 0 <= b < h and not seen[a][b] and open_(a, b):
                seen[a][b] = True
                q.append((a, b))
    return seen, n


def cut(im, mask, name, pad=2):
    w, h = im.size
    src = im.load()
    xs = []
    ys = []
    for x in range(w):
        for y in range(h):
            if mask[x][y]:
                xs.append(x)
                ys.append(y)
    if not xs:
        print("EMPTY", name)
        sys.exit(1)
    box = (max(0, min(xs) - pad), max(0, min(ys) - pad), min(w, max(xs) + 1 + pad), min(h, max(ys) + 1 + pad))
    out = Image.new("RGBA", (box[2] - box[0], box[3] - box[1]), (0, 0, 0, 0))
    dst = out.load()
    for x in range(box[0], box[2]):
        for y in range(box[1], box[3]):
            if mask[x][y]:
                dst[x - box[0], y - box[1]] = src[x, y]
    out.save(name)
    print("%s box=%s size=%s px=%d" % (name, box, out.size, len(xs)))


def main():
    im, px = load()
    w, h = im.size
    solid = solid_map(px, w, h)

    # 闸门：斧刃咬进柴里的那道接缝。柴面在 x<285 一带大致 y≈132~152，
    # 沿 x 线性抬高，保证刃口以下全部断开，而 x>285 的斧柄完全不受限。
    axe_gate = [lambda x, y: x < 288 and y > 131 + (288 - x) * 0.16]
    axe, n = component(solid, axe_gate, [(265, 40), (232, 100), (350, 90), (450, 150), (520, 190)])
    print("axe px", n)
    cut(im, axe, "assets/art/fx/axe.png")

    log_solid = [[solid[x][y] and not axe[x][y] for y in range(h)] for x in range(w)]
    # 柴的下方是第二层柴垛，接缝在 y≈248 左右；上方只被斧头挖了个槽。
    log_gate = [lambda x, y: y > 246]
    log, n2 = component(log_solid, log_gate, [(200, 190), (300, 190), (140, 210)])
    print("log px", n2)
    cut(im, log, "assets/art/fx/log.png")

    # 柴垛本体：把斧头像素抹掉，否则小游戏里会同时出现两把斧头。
    inv = [[not axe[x][y] for y in range(h)] for x in range(w)]
    # 刃口的高光被闸门切成了孤儿，留在柴面上像一道白斑，直接删掉。
    gone = 0
    for y in range(90, 150):
        for x in range(220, 350):
            if inv[x][y] and min(px[x, y][:3]) > 215 and px[x, y][3] > ALPHA:
                inv[x][y] = False
                gone += 1
    print("stack orphan px cleared", gone)
    cut(im, inv, "assets/art/kitchen/wood_stack.png", 0)


main()
