# Значки меток (пингов) для игры: восклицательный знак (внимание), пин (иду сюда), прицел (атака), щит (помогите).
# Белые с чёрной обводкой на прозрачном фоне — игра красит их в цвет метки.
# Запуск: python tools/make_ping_icons.py   (пишет assets/ui/ping_*.png, потом godot --headless --path . --import)
import math
import os
from PIL import Image, ImageDraw, ImageFilter, ImageChops

S = 512          # рисуем крупно и уменьшаем — так края гладкие
OUT = 128
OUTLINE = 33     # толщина чёрной обводки (на крупном холсте, нечётное)
HERE = os.path.dirname(os.path.abspath(__file__))
DST = os.path.join(HERE, "..", "assets", "ui")


def blank():
    return Image.new("L", (S, S), 0)


def attention():
    m = blank()
    d = ImageDraw.Draw(m)
    d.polygon([(206, 50), (306, 50), (290, 330), (222, 330)], fill=255)
    d.ellipse((206, 50 - 50, 306, 50 + 50), fill=255)       # скругление сверху
    d.ellipse((256 - 52, 420 - 52, 256 + 52, 420 + 52), fill=255)
    return m


def pin():
    m = blank()
    d = ImageDraw.Draw(m)
    cx, cy, r = 256, 200, 140
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
    # касательные от острия к кругу
    tip = (256, 476)
    dist = tip[1] - cy
    a = math.asin(r / dist)
    tl = (cx - r * math.cos(a), cy + r * math.sin(a))
    tr = (cx + r * math.cos(a), cy + r * math.sin(a))
    d.polygon([tl, tr, tip], fill=255)
    d.ellipse((cx - 56, cy - 56, cx + 56, cy + 56), fill=0)   # дырка
    return m


def crosshair():
    m = blank()
    d = ImageDraw.Draw(m)
    c = 256
    d.ellipse((c - 158, c - 158, c + 158, c + 158), fill=255)
    d.ellipse((c - 116, c - 116, c + 116, c + 116), fill=0)
    w = 22
    for (x0, y0, x1, y1) in [(c - w, 40, c + w, 170), (c - w, 342, c + w, 472), (40, c - w, 170, c + w), (342, c - w, 472, c + w)]:
        d.rectangle((x0, y0, x1, y1), fill=255)
    d.ellipse((c - 30, c - 30, c + 30, c + 30), fill=255)
    return m


def shield_pts(scale=1.0):
    # верх слегка выпуклый, бока прямые, низ сходится плавными дугами к острию
    def bez(p0, p1, p2, n=16):
        return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
                 (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]) for t in [k / n for k in range(n + 1)]]
    pts = bez((96, 92), (256, 40), (416, 92))
    pts += [(416, 250)]
    pts += bez((416, 250), (410, 400), (256, 478))[1:]
    pts += bez((256, 478), (102, 400), (96, 250))[1:]
    cx, cy = 256, 270
    return [(cx + (x - cx) * scale, cy + (y - cy) * scale) for x, y in pts]


def shield():
    m = blank()
    d = ImageDraw.Draw(m)
    d.polygon(shield_pts(), fill=255)
    return m


def shield_inner(img):
    # тонкий тёмный контур внутри щита — чтобы читался как щит, а не как клякса
    d = ImageDraw.Draw(img)
    p = shield_pts(0.68)
    d.line(p + [p[0]], fill=(0, 0, 0, 255), width=16, joint="curve")


def build(mask):
    ring = mask.filter(ImageFilter.MaxFilter(OUTLINE))
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    black = Image.new("RGBA", (S, S), (0, 0, 0, 235))
    white = Image.new("RGBA", (S, S), (255, 255, 255, 255))
    img.paste(black, (0, 0), ring)
    img.paste(white, (0, 0), mask)
    return img


os.makedirs(DST, exist_ok=True)
for name, fn in [("attention", attention), ("going", pin), ("attack", crosshair), ("help", shield)]:
    img = build(fn())
    if name == "help":
        shield_inner(img)
    img = img.resize((OUT, OUT), Image.LANCZOS)
    img.save(os.path.join(DST, "ping_%s.png" % name))
    print("ping_%s.png" % name)
