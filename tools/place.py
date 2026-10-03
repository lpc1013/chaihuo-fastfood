"""把选定的即梦成品落位成 assets/art 槽位。

  python tools/place.py tools/place_map.json

map 格式（key=none 表示不抠图，只等比裁到目标尺寸）：
{
 "assets/art/backgrounds/band_dining.png": {"src": ".../hd/band_dining_1.png", "key": "none", "w": 1600},
 "assets/art/kitchen/st_grill.png":        {"src": ".../st_grill_2.png",       "key": "green", "h": 300}
}
"""
import json
import sys
from pathlib import Path
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cutout import cutout


def fit(im: Image.Image, w=None, h=None) -> Image.Image:
    if not w and not h:
        return im
    src = im.size
    s = (w / src[0]) if w else (h / src[1])
    if w and h:
        s = max(w / src[0], h / src[1])
        im = im.resize((int(src[0] * s + 0.5), int(src[1] * s + 0.5)), Image.LANCZOS)
        x, y = (im.size[0] - w) // 2, (im.size[1] - h) // 2
        return im.crop((x, y, x + w, y + h))
    return im.resize((max(1, int(src[0] * s)), max(1, int(src[1] * s))), Image.LANCZOS)


def main() -> int:
    m = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    tmp = Path("tools/_scratch/place")
    tmp.mkdir(parents=True, exist_ok=True)
    for dst, spec in m.items():
        d = Path(dst)
        d.parent.mkdir(parents=True, exist_ok=True)
        src = Path(spec["src"])
        key = spec.get("key", "green")
        if key == "none":
            im = Image.open(src).convert("RGBA")
            im = fit(im, spec.get("w"), spec.get("h"))
            im.save(d)
        else:
            mid = tmp / (d.stem + ".png")
            cutout(src, mid, key, spec.get("h"), spec.get("pad", 6), holes=spec.get("holes", False))
            if spec.get("w"):
                im = Image.open(mid).convert("RGBA")
                im = fit(im, spec["w"], spec.get("h"))
                im.save(d)
            else:
                mid.replace(d)
        print(f"{d}  <-  {src.name}  {Image.open(d).size}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
