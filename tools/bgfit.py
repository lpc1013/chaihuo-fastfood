"""把 play.gd 里 ly() 的工位框叠到任意底图上，用眼睛量版式，不再靠猜。

  python tools/bgfit.py assets/incoming/AB_v13b/bg_play_v13b_2.png
  python tools/bgfit.py <png> --boxes "0.014,0.177;0.199,0.145;..."

为什么要这个：换一版底图就要重量六个工位的横向范围、台面行带、食材架行带。
之前食材架和背景木格差了 12px 没人发现，就是因为没有一张"框压在图上"的对照图。
boxes 的默认值抄自 scripts/screens/play.gd 的 ly()，改那边记得改这里。
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw

W, H = 1280, 720
# 抄自 play.gd:ly()
NAMES = ["fire", "grill", "fryer", "asm", "tray", "drink"]
# 每个工位带自己的 y/h（v12：砖砌台身 + 单排六件，每件高度差很大，共用一条 y 会飘）。
# 抄自 play.gd:ly() 的 boxes，改那边记得改这里。
BOXES = [(0.010, 0.185, 0.475, 0.270), (0.195, 0.150, 0.585, 0.160),
         (0.345, 0.145, 0.505, 0.255), (0.488, 0.162, 0.615, 0.150),
         (0.650, 0.175, 0.575, 0.190), (0.820, 0.175, 0.465, 0.260)]
ROW_Y, ROW_H = 0.48, 0.28
SHELF_Y, SHELF_H = 0.828, 0.105
# 食材格隔条（抄 play.gd:_shelf_metrics）：7 格、pitch 0.1305、首格中心 0.1055
SHELF_PITCH, SHELF_FIRST, SHELF_N = 0.1305, 0.1055, 7
COUNTER_Y = 0.44
SLOTS = [0.36, 0.52, 0.68, 0.84]
LEDGE = (0.005, 0.738, 0.295, 0.050)
COLS = ["#ff4d4d", "#ff9f1c", "#ffe14d", "#5dff7a", "#4dd2ff", "#c77dff"]


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        print(__doc__)
        return 1
    src = Path(args[0])
    if not src.exists():
        print("missing", src)
        return 1
    boxes = BOXES
    for i, a in enumerate(sys.argv):
        if a == "--boxes" and i + 1 < len(sys.argv):
            boxes = [tuple(float(v) for v in p.split(",")) for p in sys.argv[i + 1].split(";")]
    im = Image.open(src).convert("RGB")
    if im.size != (W, H):
        im = im.resize((W, H), Image.LANCZOS)
    ov = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    # 台面行带和食材架行带：这两条错了，六个工位会一起飘
    d.rectangle([0, ROW_Y * H, W, (ROW_Y + ROW_H) * H], outline=(255, 255, 255, 120), width=2)
    d.rectangle([0, SHELF_Y * H, W, (SHELF_Y + SHELF_H) * H], outline=(0, 255, 255, 150), width=2)
    d.line([(0, COUNTER_Y * H), (W, COUNTER_Y * H)], fill=(255, 255, 0, 150), width=2)
    d.rectangle([LEDGE[0] * W, LEDGE[1] * H, (LEDGE[0] + LEDGE[2]) * W, (LEDGE[1] + LEDGE[3]) * H],
                outline=(255, 255, 255, 90), width=1)
    for s in SLOTS:
        d.line([(s * W, COUNTER_Y * H - 40), (s * W, COUNTER_Y * H + 40)], fill=(255, 255, 0, 150), width=2)
    # 食材格的隔条与格心：图标要落在格心，差十几像素就骑在木梁上
    for i in range(SHELF_N + 1):
        x = int((SHELF_FIRST + (i - 0.5) * SHELF_PITCH) * W)
        d.line([(x, SHELF_Y * H), (x, H)], fill=(0, 255, 255, 210), width=2)
    for i in range(SHELF_N):
        cx = int((SHELF_FIRST + i * SHELF_PITCH) * W)
        d.line([(cx - 7, (SHELF_Y + SHELF_H * 0.5) * H), (cx + 7, (SHELF_Y + SHELF_H * 0.5) * H)],
               fill=(255, 0, 255, 230), width=3)
    for i in range(13):
        x = i * W / 20.0
        d.line([(x, 0), (x, H)], fill=(255, 255, 255, 26), width=1)
        d.text((x + 2, 2), "%.3f" % (i / 20.0), fill=(255, 255, 255, 190))
    for i, bx in enumerate(boxes):
        bxi, bw, by, bh = (float(v) for v in bx)
        c = COLS[i % len(COLS)] + "cc"
        r = [bxi * W, by * H, (bxi + bw) * W, (by + bh) * H]
        d.rectangle(r, outline=c, width=3)
        d.rectangle([r[0], SHELF_Y * H, r[2], (SHELF_Y + SHELF_H) * H], outline=c, width=1)
        d.text((r[0] + 4, r[1] + 4), NAMES[i] if i < len(NAMES) else "?", fill=c)
        d.text((r[0] + 4, r[1] + 22), "%.3f,%.3f,%.3f,%.3f" % (bxi, bw, by, bh), fill=c)
    out = Image.alpha_composite(im.convert("RGBA"), ov).convert("RGB")
    # 一定要写到 assets 外面：落在 assets/art/ 里会被 Godot 当资源导入并打进发布包
    dst = Path("tools/_scratch") / (src.stem + "_fit.png")
    out.save(dst)
    print("fit ->", dst)
    return 0


sys.exit(main())
