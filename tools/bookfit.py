"""把 ov_menu.gd 的 PAGES 纸面框叠到 ui/book_bg.png 上量版式。

  python tools/bookfit.py                 # 用脚本里抄来的当前 PAGES
  python tools/bookfit.py --pages "0.165,0.115,0.305,0.680;0.545,..."

为什么要有这张图：ov_menu 的配方链是按 PAGES 矩形算"一行摆几个、能摆几行"的，
而 book_bg 那张画里纸面比矩形小得多（四周是封面、书脊、卷边和花角）。
矩形一放宽，第七层那颗胚子就掉到书面外面——这页已经为这件事返工过三次，
别再靠肉眼估，直接看叠了框的原图。
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "assets/art/ui/book_bg.png"
OUT = ROOT / "tools/_scratch/book_fit.png"
VW, VH = 1280.0, 720.0

# 抄自 scripts/components/ov_menu.gd 的 PAGES，改那边记得改这里
PAGES = [(0.198, 0.115, 0.272, 0.625), (0.547, 0.115, 0.273, 0.625)]
HEAD_H = 52.0     # 页顶标题往下才是正文
ROW_TOP = 38.0    # 每格里名字占掉的上沿
ROW_BOT = 13.0    # 行间分隔线


def main() -> int:
    pages = PAGES
    args = sys.argv[1:]
    for i, a in enumerate(args):
        if a == "--pages" and i + 1 < len(args):
            pages = [tuple(float(v) for v in p.split(",")) for p in args[i + 1].split(";")]
    im = Image.open(ART).convert("RGB").resize((int(VW), int(VH)), Image.LANCZOS)
    d = ImageDraw.Draw(im)
    for p in pages:
        x0, y0 = p[0] * VW, p[1] * VH
        x1, y1 = (p[0] + p[2]) * VW, (p[1] + p[3]) * VH
        d.rectangle([x0, y0, x1, y1], outline=(255, 40, 40), width=3)
        # 正文可用高度：三格一行时每格的 room（配方链能占的竖向空间）
        row_h = (y1 - y0 - 70.0) / 3.0
        for r in range(3):
            top = y0 + HEAD_H + r * row_h
            room = row_h - ROW_TOP - ROW_BOT
            d.rectangle([x0 + 10, top + ROW_TOP, x1 - 18, top + ROW_TOP + room],
                        outline=(0, 220, 120), width=1)
    for y in range(0, 105, 5):
        d.line([(0, y / 100.0 * VH), (VW, y / 100.0 * VH)], fill=(30, 90, 220), width=1)
        d.text((2, y / 100.0 * VH), "%d" % y, fill=(0, 0, 255))
    for x in range(0, 105, 5):
        d.line([(x / 100.0 * VW, 0), (x / 100.0 * VW, VH)], fill=(255, 70, 70), width=1)
        d.text((x / 100.0 * VW + 2, 2), "%d" % x, fill=(200, 0, 0))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    im.save(OUT)
    print("fit ->", OUT)
    return 0


if __name__ == "__main__":
    sys.exit(main())
