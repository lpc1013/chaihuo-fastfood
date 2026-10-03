"""把 assets/incoming/<dir>/<tag>_N.png 拼成带标签的联络表，便于一次性肉眼验收。

  python tools/sheet.py <dir> <tag1> <tag2> ...
输出 <dir>/_sheet_<tag>.png（每张候选等比缩到 460 宽）
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw


def sheet(d: Path, tag: str, cols: int = 2, cell: int = 460) -> Path:
    paths = sorted(d.glob(f"{tag}_*.png"), key=lambda p: int(p.stem.rsplit("_", 1)[1]))
    paths = [p for p in paths if p.exists()]
    if not paths:
        return None
    n = len(paths)
    rows = (n + cols - 1) // cols
    cw, ch = cell, int(cell * 9 / 16) + 26
    out = Image.new("RGB", (cols * cw, rows * ch), (24, 22, 20))
    dr = ImageDraw.Draw(out)
    for i, p in enumerate(paths):
        im = Image.open(p).convert("RGB")
        im.thumbnail((cw - 8, ch - 34))
        x, y = (i % cols) * cw, (i // cols) * ch
        out.paste(im, (x + 4, y + 24))
        dr.text((x + 6, y + 6), f"{tag} #{p.stem.rsplit('_', 1)[1]}  {im.size[0]}x{im.size[1]}", fill=(240, 220, 180))
    f = d / f"_sheet_{tag}.png"
    out.save(f)
    return f


def main() -> int:
    d = Path(sys.argv[1])
    for tag in sys.argv[2:]:
        f = sheet(d, tag)
        print(f or f"(none for {tag})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
