"""把 assets/art 下的素材铺在棋盘格上出检查表，用来验抠图边缘与透明区。

  python tools/checkart.py                 # 全量
  python tools/checkart.py kitchen        # 只看某个子目录
  python tools/checkart.py --dir assets/incoming/X --key green
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw

CELL = 190


def checker(size, sq=12, light=(206, 200, 192), dark=(150, 144, 138)):
    im = Image.new("RGB", size, light)
    dr = ImageDraw.Draw(im)
    for y in range(0, size[1], sq):
        for x in range(0, size[0], sq):
            if ((x // sq) + (y // sq)) % 2:
                dr.rectangle([x, y, x + sq - 1, y + sq - 1], fill=dark)
    return im


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    root = Path(args[0]) if args else Path("assets/art")
    files = sorted(p for p in root.rglob("*.png") if "_sheet" not in p.name)
    cols = 6
    rows = (len(files) + cols - 1) // cols
    out = Image.new("RGB", (cols * CELL, rows * (CELL + 20)), (26, 24, 22))
    dr = ImageDraw.Draw(out)
    for i, p in enumerate(files):
        im = Image.open(p).convert("RGBA")
        im.thumbnail((CELL - 8, CELL - 8))
        plate = checker((CELL - 8, CELL - 8))
        plate.paste(im, ((plate.size[0] - im.size[0]) // 2, (plate.size[1] - im.size[1]) // 2), im)
        x, y = (i % cols) * CELL, (i // cols) * (CELL + 20)
        out.paste(plate, (x + 4, y + 18))
        dr.text((x + 5, y + 5), f"{p.parent.name}/{p.stem} {im.size[0]}x{im.size[1]}", fill=(245, 228, 195))
    f = Path("assets/incoming/_check_art.png")
    f.parent.mkdir(parents=True, exist_ok=True)
    out.save(f)
    print(f, len(files), "张")
    return 0


if __name__ == "__main__":
    sys.exit(main())
