#!/usr/bin/env python3
# One-off icon asset generator (Pillow based).
# Produces:
#  - white-bell foreground PNGs (recolored from existing blue bell) at 5 densities for adaptive icons
#  - legacy full launcher PNGs (solid accent rounded square + white bell) for two accent colors
import os
from PIL import Image

RES = os.path.dirname(os.path.abspath(__file__))

# legacy mipmap densities and square edge sizes
DENS = [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)]
# adaptive foreground densities and sizes (match existing ic_launcher_foreground)
FG_DENS = [("mdpi", 108), ("hdpi", 162), ("xhdpi", 216), ("xxhdpi", 324), ("xxxhdpi", 432)]

# accent color -> (R, G, B)
ACCENTS = {
    "blue": (0, 122, 255),    # #007AFF
    "purple": (175, 82, 222),  # #AF52DE
}


def recolor_white(src_path):
    im = Image.open(src_path).convert("RGBA")
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a > 8:
                px[x, y] = (255, 255, 255, a)
    return im


def ensure_dir(path):
    d = os.path.dirname(path)
    if not os.path.exists(d):
        os.makedirs(d)


def main():
    # 1) white bell foreground for adaptive icons (recolor existing blue bell)
    for d, _sz in FG_DENS:
        src = os.path.join(RES, f"drawable-{d}", "ic_launcher_foreground.png")
        out = os.path.join(RES, f"drawable-{d}", "ic_launcher_foreground_white.png")
        ensure_dir(out)
        recolor_white(src).save(out, "PNG")
        print("white fg ->", out)

    # high-res white bell for legacy composition
    bell = recolor_white(
        os.path.join(RES, "drawable-xxxhdpi", "ic_launcher_foreground.png")
    )

    # 2) legacy colored full launcher icons
    for name, (cr, cg, cb) in ACCENTS.items():
        for d, sz in DENS:
            canvas = Image.new("RGBA", (sz, sz), (cr, cg, cb, 255))
            bw = max(1, int(round(sz * 0.6)))
            b = bell.resize((bw, bw), Image.LANCZOS)
            x0 = (sz - bw) // 2
            y0 = (sz - bw) // 2
            canvas.alpha_composite(b, (x0, y0))
            out = os.path.join(RES, f"mipmap-{d}", f"ic_launcher_{name}.png")
            ensure_dir(out)
            canvas.save(out, "PNG")
            print(f"legacy {name} ->", out)

    print("DONE")


if __name__ == "__main__":
    main()
