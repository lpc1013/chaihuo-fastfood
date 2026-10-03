"""把全屏背景提到显示分辨率，并做一层适合厚涂插画的锐化。

即梦的高清原件对 16:9 只给到 1080x608，落位时被插值成了 1536x864。
运行时若窗口是高分屏（125%/150% 缩放）再放大一次，两级插值叠起来就是"糊"。
这里离线一次 Lanczos 提到 1920 宽 + 非锐化掩膜，让 GPU 那一步变成**缩小采样**，
观感上比运行时放大干净得多。只动 RGB，alpha 原样保留。

  python tools/crisp.py assets/art/backgrounds/bg_play_full.png ...
  python tools/crisp.py --to 2048 --amount 0.5 --radius 2.0 a.png
"""
import argparse
import shutil
from pathlib import Path

from PIL import Image, ImageFilter


def crisp(path: str, to_w: int, amount: float, radius: float) -> str:
    p = Path(path)
    im = Image.open(p).convert("RGBA")
    w, h = im.size
    if w >= to_w:
        return "跳过（已经 %dx%d >= %d）" % (w, h, to_w)
    nh = int(round(h * to_w / float(w)))
    rgb = im.convert("RGB").resize((to_w, nh), Image.LANCZOS)
    blur = rgb.filter(ImageFilter.GaussianBlur(radius))
    sharp = ImageFilter.UnsharpMask(radius=radius, percent=int(amount * 100), threshold=2)
    rgb = rgb.filter(sharp)
    out = Image.merge("RGBA", (*rgb.split(), im.split()[3].resize((to_w, nh), Image.LANCZOS)))
    bak = Path("assets/incoming/_bak_crisp")
    bak.mkdir(parents=True, exist_ok=True)
    if not (bak / p.name).exists():
        shutil.copy(p, bak / p.name)
    out.save(p, optimize=True)
    return "%dx%d -> %dx%d" % (w, h, to_w, nh)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--to", type=int, default=1920, help="目标宽度（默认 1920，覆盖 150%% 缩放的 1280 窗口）")
    ap.add_argument("--amount", type=float, default=0.45, help="锐化强度 0~1")
    ap.add_argument("--radius", type=float, default=2.0)
    n = ap.parse_args()
    for f in n.files:
        print("%-46s %s" % (f, crisp(f, n.to, n.amount, n.radius)))


if __name__ == "__main__":
    main()
