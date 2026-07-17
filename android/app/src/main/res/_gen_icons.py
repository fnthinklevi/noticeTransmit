# -*- coding: utf-8 -*-
"""
生成可选应用图标资源（default + 16 色）。
- 每色: mipmap-{d}/ic_launcher_{key}.png (48/72/96/144/192) 彩底+白铃 legacy 兜底
- 每色: mipmap-anydpi-v26/ic_launcher_{key}.xml adaptive（彩底 + 共享白铃前景）
- values/colors.xml 写入所有 ic_launcher_{key}_bg 颜色
- assets/icons/bell_white.png、bell_blue.png 供 Flutter 真实预览（裁剪自实际前景字形）
运行: D:/python/anaconda/python.exe _gen_icons.py
"""
import os
from PIL import Image, ImageDraw

RES = r"D:\fnthinklevi\flutter\noticeTransmit\android\app\src\main\res"
ASSETS = r"D:\fnthinklevi\flutter\noticeTransmit\assets\icons"

# key, 中文标签, 背景色
PALETTE = [
    ("blue",     "蓝色",   "#007AFF"),
    ("cyan",     "天蓝",   "#32ADE6"),
    ("teal",     "青色",   "#30B0C7"),
    ("mint",     "薄荷",   "#00C7BE"),
    ("green",    "绿色",   "#34C759"),
    ("yellow",   "黄色",   "#FFCC00"),
    ("orange",   "橙色",   "#FF9500"),
    ("red",      "红色",   "#FF3B30"),
    ("pink",     "粉色",   "#FF2D55"),
    ("rose",     "玫红",   "#E91E63"),
    ("purple",   "紫色",   "#AF52DE"),
    ("indigo",   "靛蓝",   "#5856D6"),
    ("brown",    "棕色",   "#A2845E"),
    ("gray",     "灰色",   "#8E8E93"),
    ("graphite", "深灰",   "#48484A"),
    ("black",    "墨黑",   "#1C1C1E"),
]

# legacy 启动图标标准尺寸
DENSITIES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}


def hex_rgb(h):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def rounded_mask(size, radius):
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return m


def load_glyph_cropped(path):
    """加载前景 PNG 并裁剪到不透明字形的外接框。"""
    im = Image.open(path).convert("RGBA")
    bbox = im.getbbox()
    return im.crop(bbox) if bbox else im


def make_legacy(color_rgb, glyph, size):
    """彩色圆角方底 + 居中白铃 legacy 图标。"""
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bg = Image.new("RGBA", (size, size), color_rgb + (255,))
    canvas.paste(bg, (0, 0), rounded_mask(size, int(size * 0.20)))
    # 铃铛缩放到高度约 52% 居中
    target_h = int(size * 0.52)
    ratio = target_h / glyph.height
    target_w = max(1, int(glyph.width * ratio))
    g = glyph.resize((target_w, target_h), Image.LANCZOS)
    ox = (size - target_w) // 2
    oy = (size - target_h) // 2
    canvas.paste(g, (ox, oy), g)
    return canvas


def main():
    white_glyph = load_glyph_cropped(
        os.path.join(RES, "drawable-xxxhdpi", "ic_launcher_foreground_white.png")
    )
    # 蓝铃（默认图标前景）用于 Flutter 默认预览
    blue_glyph = load_glyph_cropped(
        os.path.join(RES, "drawable-xxxhdpi", "ic_launcher_foreground.png")
    )

    # 1) legacy PNG
    png_count = 0
    for key, _label, hx in PALETTE:
        rgb = hex_rgb(hx)
        for d, size in DENSITIES.items():
            outdir = os.path.join(RES, d)
            os.makedirs(outdir, exist_ok=True)
            img = make_legacy(rgb, white_glyph, size)
            img.save(os.path.join(outdir, f"ic_launcher_{key}.png"))
            png_count += 1
    print(f"[legacy] wrote {png_count} PNGs")

    # 2) adaptive XML
    anydpi = os.path.join(RES, "mipmap-anydpi-v26")
    os.makedirs(anydpi, exist_ok=True)
    for key, _label, _hx in PALETTE:
        xml = (
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            f'    <background android:drawable="@color/ic_launcher_{key}_bg"/>\n'
            '    <foreground>\n'
            '        <inset\n'
            '            android:drawable="@drawable/ic_launcher_foreground_white"\n'
            '            android:inset="24%" />\n'
            '    </foreground>\n'
            '</adaptive-icon>\n'
        )
        with open(os.path.join(anydpi, f"ic_launcher_{key}.xml"), "w", encoding="utf-8") as f:
            f.write(xml)
    print(f"[adaptive] wrote {len(PALETTE)} XMLs")

    # 3) colors.xml
    lines = ['<?xml version="1.0" encoding="utf-8"?>', "<resources>",
             '    <color name="ic_launcher_background">#ffffff</color>',
             '    <color name="ic_launcher_background_dark">#1c1c1e</color>']
    for key, _label, hx in PALETTE:
        lines.append(f'    <color name="ic_launcher_{key}_bg">{hx}</color>')
    lines.append("</resources>")
    with open(os.path.join(RES, "values", "colors.xml"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print("[colors] wrote values/colors.xml")

    # 4) Flutter 预览铃铛资源
    os.makedirs(ASSETS, exist_ok=True)
    white_glyph.save(os.path.join(ASSETS, "bell_white.png"))
    blue_glyph.save(os.path.join(ASSETS, "bell_blue.png"))
    print(f"[assets] bell_white {white_glyph.size}, bell_blue {blue_glyph.size}")

    # 5) 打印接线片段
    print("\n--- Dart options ---")
    for key, label, hx in PALETTE:
        print(f"    IconOption('{key}', '{label}', 0xFF{hx.lstrip('#').upper()}),")
    print("\n--- Kotlin map ---")
    for key, _l, _h in PALETTE:
        cap = key[0].upper() + key[1:]
        print(f'            "{key}" to ComponentName(packageName, "$packageName.Launcher{cap}"),')


if __name__ == "__main__":
    main()
