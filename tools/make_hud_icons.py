# Значки-заглушки интерфейса боя: абилки (по полю "ability" модуля в parts.gd), рывок, телепорт и статусы меха.
# Белые с чёрной обводкой на прозрачном фоне — игра красит их сама (статусы: вредные красным, полезные зелёным).
# Запуск: python tools/make_hud_icons.py [лист.png]   (пишет assets/ui/hud/*.png, потом godot --headless --path . --import;
# с аргументом ещё и собирает все значки на один лист для просмотра)
import math
import os
import sys
from PIL import Image, ImageDraw, ImageFilter

S = 512          # рисуем крупно и уменьшаем — так края гладкие
OUT = 128
OUTLINE = 29     # толщина чёрной обводки (на крупном холсте, нечётное)
HERE = os.path.dirname(os.path.abspath(__file__))
DST = os.path.join(HERE, "..", "assets", "ui", "hud")
C = 256


def rot(pts, ang, cx=C, cy=C):
    # повернуть точки (заданы вокруг нуля) на ang радиан и сдвинуть в (cx, cy)
    ca, sa = math.cos(ang), math.sin(ang)
    return [(cx + x * ca - y * sa, cy + x * sa + y * ca) for x, y in pts]


def circ(d, x, y, r, f=255):
    d.ellipse((x - r, y - r, x + r, y + r), fill=f)


def ring(d, x, y, r, w, f=255):
    d.ellipse((x - r, y - r, x + r, y + r), outline=f, width=w)


def arrow(d, x0, y0, x1, y1, w=44, head=110, f=255):
    a = math.atan2(y1 - y0, x1 - x0)
    bx, by = x1 - math.cos(a) * head * 0.8, y1 - math.sin(a) * head * 0.8
    d.line((x0, y0, bx, by), fill=f, width=w)
    hx, hy = math.cos(a + math.pi / 2) * head * 0.7, math.sin(a + math.pi / 2) * head * 0.7
    d.polygon([(x1, y1), (x1 - math.cos(a) * head + hx, y1 - math.sin(a) * head + hy),
               (x1 - math.cos(a) * head - hx, y1 - math.sin(a) * head - hy)], fill=f)


def bolt(d, cx=C, cy=C, k=1.0, f=255):
    pts = [(30, -200), (-110, 30), (-10, 30), (-50, 200), (110, -40), (10, -40), (60, -200)]
    d.polygon([(cx + x * k, cy + y * k) for x, y in pts], fill=f)


def slash(d, f=0, w=46):
    d.line((110, 110, 402, 402), fill=f, width=w)


def eye(d, slit=False):
    pts = []
    for i in range(33):
        t = math.pi * i / 32
        pts.append((C - 200 * math.cos(t), C - 120 * math.sin(t)))
    for i in range(33):
        t = math.pi * i / 32
        pts.append((C + 200 * math.cos(t), C + 120 * math.sin(t)))
    d.polygon(pts, fill=255)
    circ(d, C, C, 78, 0)
    circ(d, C, C, 44)


def shield_pts(scale=1.0):
    def bez(p0, p1, p2, n=16):
        return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
                 (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]) for t in [k / n for k in range(n + 1)]]
    pts = bez((106, 100), (256, 52), (406, 100)) + [(406, 250)]
    pts += bez((406, 250), (400, 396), (256, 470))[1:]
    pts += bez((256, 470), (112, 396), (106, 250))[1:]
    return [(C + (x - C) * scale, 270 + (y - 270) * scale) for x, y in pts]


def bullet(d, cx, cy, ang, L=200, W=70):
    body = [(-W / 2, L / 2), (-W / 2, -L / 2 + W * 0.6), (0, -L / 2), (W / 2, -L / 2 + W * 0.6), (W / 2, L / 2)]
    d.polygon(rot(body, ang, cx, cy), fill=255)


def rocket(d, cx, cy, ang, L=330, W=74):
    body = [(-W / 2, L / 2 - 40), (-W / 2, -L / 2 + 80), (0, -L / 2), (W / 2, -L / 2 + 80), (W / 2, L / 2 - 40)]
    d.polygon(rot(body, ang, cx, cy), fill=255)
    for s in (-1, 1):
        fin = [(s * W / 2, L / 2 - 120), (s * (W / 2 + 46), L / 2), (s * W / 2, L / 2 - 20)]
        d.polygon(rot(fin, ang, cx, cy), fill=255)


# ---------------- абилки ----------------
def i_rockets(d):
    rocket(d, 175, 290, 0.25, 300, 70)
    rocket(d, 330, 230, 0.25, 300, 70)


def i_emp(d):
    circ(d, C, C, 60)
    ring(d, C, C, 135, 34)
    for a0 in (20, 110, 200, 290):
        d.arc((C - 215, C - 215, C + 215, C + 215), a0, a0 + 50, fill=255, width=34)


def i_cloak(d):
    eye(d)
    slash(d, 0, 70)
    d.line((110, 110, 402, 402), fill=255, width=30)


def i_repair(d):
    # гаечный ключ по диагонали
    d.line((150, 362, 330, 182), fill=255, width=70)
    circ(d, 350, 162, 92)
    d.polygon(rot([(-38, -120), (38, -120), (38, 10), (-38, 10)], math.pi / 4, 350, 162), fill=0)
    circ(d, 150, 362, 50)


def i_airstrike(d):
    # бомба падает на перекрестье
    ring(d, C, 380, 92, 26)
    d.line((C - 140, 380, C + 140, 380), fill=255, width=20)
    body = [(-56, -90), (56, -90), (56, 30), (0, 110), (-56, 30)]
    d.polygon([(C + x, 170 + y) for x, y in body], fill=255)
    d.rectangle((C - 16, 40, C + 16, 90), fill=255)
    d.polygon([(C - 80, 30), (C + 80, 30), (C + 50, 70), (C - 50, 70)], fill=255)


def i_shield(d):
    # энергетический пузырь
    ring(d, C, C, 180, 44)
    d.arc((C - 120, C - 120, C + 120, C + 120), 200, 260, fill=255, width=34)


def i_mine(d):
    for k in range(8):
        a = k * math.pi / 4
        d.polygon(rot([(-24, -200), (24, -200), (24, -100), (-24, -100)], a), fill=255)
    circ(d, C, C, 135)
    circ(d, C, C, 40, 0)


def i_blink(d):
    ring(d, 140, C, 70, 18)
    for x in (230, 300):
        d.line((x, C - 70, x + 50, C, x, C + 70), fill=255, width=34, joint="curve")
    circ(d, 400, C, 78)


def i_bolas(d):
    d.arc((90, 120, 420, 440), 200, 340, fill=255, width=26)
    circ(d, 120, 250, 72)
    circ(d, 392, 250, 72)
    circ(d, C, 380, 60)
    d.line((C, 125, C, 330), fill=255, width=24)


def i_jammer(d):
    bullet(d, C, C, 0, 290, 100)
    ring(d, C, C, 200, 40)
    d.line((115, 115, 397, 397), fill=0, width=80)
    d.line((115, 115, 397, 397), fill=255, width=40)


def i_napalm(d):
    d.polygon([(256, 50), (330, 160), (385, 260), (380, 350), (335, 420), (256, 448), (177, 420), (132, 350),
               (130, 262), (168, 190), (196, 236), (210, 140)], fill=255)
    d.ellipse((C - 62, 300, C + 62, 430), fill=0)
    d.line((70, 470, 442, 470), fill=255, width=26)


def i_emp_shell(d):
    ring(d, C, C, 200, 34)
    bolt(d, k=0.8)


def i_probe(d):
    circ(d, C, 330, 70)
    d.line((C, 330, C, 470), fill=255, width=30)
    for r in (140, 220):
        d.arc((C - r, 330 - r, C + r, 330 + r), 225, 315, fill=255, width=32)


def i_barricade(d):
    for row in range(3):
        y = 150 + row * 90
        off = 0 if row % 2 == 0 else 60
        for k in range(-1, 4):
            x = 70 + off + k * 120
            x0, x1 = max(x, 70), min(x + 108, 442)
            if x1 - x0 > 20:
                d.rectangle((x0, y, x1, y + 78), fill=255)


def i_drone(d):
    for sx, sy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        d.line((C, C, C + sx * 130, C + sy * 130), fill=255, width=34)
        ring(d, C + sx * 140, C + sy * 140, 70, 22)
    d.rectangle((C - 62, C - 62, C + 62, C + 62), fill=255)
    d.rectangle((C - 14, C - 42, C + 14, C + 42), fill=0)
    d.rectangle((C - 42, C - 14, C + 42, C + 14), fill=0)


def i_jump(d):
    d.arc((70, 120, 442, 560), 190, 350, fill=255, width=40)
    arrow(d, 400, 230, 430, 380, 40, 120)
    d.line((60, 450, 200, 450), fill=255, width=24)


def i_stance(d):
    d.rectangle((120, 200, 392, 440), fill=255)
    for x in (120, 216, 312):
        d.rectangle((x, 120, x + 80, 200), fill=255)
    d.rectangle((216, 330, 296, 440), fill=0)


def i_gravity(d):
    circ(d, C, C, 54)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        x0, y0 = C + math.cos(a) * 225, C + math.sin(a) * 225
        x1, y1 = C + math.cos(a) * 100, C + math.sin(a) * 100
        arrow(d, x0, y0, x1, y1, 34, 90)


def i_repulse(d):
    circ(d, C, C, 54)
    for k in range(4):
        a = k * math.pi / 2
        arrow(d, C + math.cos(a) * 90, C + math.sin(a) * 90, C + math.cos(a) * 230, C + math.sin(a) * 230, 34, 90)


def i_dome(d):
    d.pieslice((70, 110, 442, 482), 180, 360, fill=255)
    d.pieslice((120, 160, 392, 432), 180, 360, fill=0)
    d.rectangle((50, 296, 462, 330), fill=255)
    circ(d, C, 270, 30)


def i_turret(d):
    d.polygon([(130, 440), (382, 440), (330, 360), (182, 360)], fill=255)
    d.rectangle((170, 220, 342, 360), fill=255)
    d.rectangle((300, 250, 470, 296), fill=255)
    d.rectangle((210, 250, 260, 300), fill=0)


def i_roller(d):
    circ(d, 236, 300, 140)
    circ(d, 186, 260, 30, 0)
    d.line((330, 200, 380, 140), fill=255, width=30)
    for a in range(0, 360, 60):
        r = math.radians(a)
        d.line((400 + math.cos(r) * 22, 110 + math.sin(r) * 22, 400 + math.cos(r) * 64, 110 + math.sin(r) * 64), fill=255, width=16)


def i_marker(d):
    for sx, sy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        x, y = C + sx * 190, C + sy * 190
        d.line((x, y, x - sx * 100, y), fill=255, width=34)
        d.line((x, y, x, y - sy * 100), fill=255, width=34)
    d.polygon([(C, C - 80), (C + 80, C), (C, C + 80), (C - 80, C)], fill=255)


def i_slug(d):
    bullet(d, 300, C, math.pi / 2, 300, 150)
    for y, x0 in ((C - 60, 60), (C, 30), (C + 60, 60)):
        d.line((x0, y, 130, y), fill=255, width=26)


def i_purge(d):
    d.arc((90, 90, 422, 422), 300, 230 + 360, fill=255, width=52)
    a = math.radians(300)
    x, y = C + math.cos(a) * 166, C + math.sin(a) * 166
    d.polygon([(x - 80, y - 20), (x + 70, y - 60), (x + 30, y + 90)], fill=255)


def hexagon(r, cx=C, cy=C):
    return [(cx + math.cos(math.pi / 6 + k * math.pi / 3) * r, cy + math.sin(math.pi / 6 + k * math.pi / 3) * r) for k in range(6)]


def i_matrix(d):
    d.polygon(hexagon(210), fill=255)
    d.polygon(hexagon(160), fill=0)
    d.polygon(hexagon(100), fill=255)
    d.polygon(hexagon(56), fill=0)


def i_overdrive(d):
    for x in (110, 250):
        d.line((x, 100, x + 140, C, x, 412), fill=255, width=60, joint="curve")


def i_rapid(d):
    for x in (130, C, 382):
        bullet(d, x, C, 0, 300, 82)


def i_periscope(d):
    # труба перископа и линза
    d.rectangle((330, 110, 400, 450), fill=255)
    d.rectangle((190, 110, 400, 180), fill=255)
    d.polygon([(190, 90), (190, 200), (130, 230), (130, 60)], fill=255)
    d.rectangle((270, 420, 460, 460), fill=255)
    for r in (50, 95):
        d.arc((110 - r, 145 - r, 110 + r, 145 + r), 145, 215, fill=255, width=22)


def i_dash(d):
    d.line((250, 110, 400, C, 250, 402), fill=255, width=60, joint="curve")
    for y, x0 in ((C - 90, 90), (C, 50), (C + 90, 90)):
        d.line((x0, y, 230, y), fill=255, width=30)


def i_teleport(d):
    d.polygon([(C, 80), (440, 250), (390, 250), (390, 440), (122, 440), (122, 250), (72, 250)], fill=255)
    d.rectangle((216, 320, 296, 440), fill=0)


# ---------------- статусы (свои значки; остальные статусы берут значок абилки) ----------------
def star(d, cx, cy, r1, r2, n=4, f=255):
    pts = []
    for k in range(n * 2):
        a = -math.pi / 2 + k * math.pi / n
        r = r1 if k % 2 == 0 else r2
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    d.polygon(pts, fill=f)


def i_stun(d):
    star(d, C, 290, 190, 60)
    star(d, 120, 120, 80, 26)
    star(d, 400, 130, 64, 22)


def i_slow(d):
    # песочные часы
    d.rectangle((110, 70, 402, 110), fill=255)
    d.rectangle((110, 402, 402, 442), fill=255)
    d.polygon([(140, 110), (372, 110), (276, C), (372, 402), (140, 402), (236, C)], fill=255)
    d.polygon([(185, 140), (327, 140), (256, 225)], fill=0)
    d.polygon([(256, 300), (340, 372), (172, 372)], fill=0)
    d.polygon([(256, 320), (300, 372), (212, 372)], fill=255)


def i_tired(d):
    # пустая батарея
    d.rectangle((70, 150, 410, 362), outline=255, width=40)
    d.rectangle((410, 210, 460, 302), fill=255)
    d.rectangle((120, 200, 170, 312), fill=255)


def i_invuln(d):
    d.polygon(shield_pts(), fill=255)
    p = shield_pts(0.64)
    d.line(p + [p[0]], fill=0, width=22, joint="curve")


def i_brace(d):
    d.rectangle((166, 110, 346, 230), fill=255)
    d.line((200, 230, 100, 430), fill=255, width=44)
    d.line((312, 230, 412, 430), fill=255, width=44)
    d.line((256, 230, 256, 430), fill=255, width=44)
    d.rectangle((50, 420, 462, 456), fill=255)


def plus(d, cx, cy, r=70, w=40):
    d.rectangle((cx - w / 2, cy - r, cx + w / 2, cy + r), fill=255)
    d.rectangle((cx - r, cy - w / 2, cx + r, cy + w / 2), fill=255)


def i_arsenal(d):
    bullet(d, 190, 290, 0, 330, 120)
    plus(d, 370, 170, 80, 46)


def i_reactor(d):
    bolt(d, 200, 280, 0.95)
    plus(d, 380, 160, 80, 46)


def i_noregen(d):
    bolt(d, k=1.05)
    d.line((90, 90, 422, 422), fill=0, width=80)
    d.line((90, 90, 422, 422), fill=255, width=36)


ICONS = {n[2:]: f for n, f in list(globals().items()) if n.startswith("i_") and callable(f)}


def build(fn):
    m = Image.new("L", (S, S), 0)
    fn(ImageDraw.Draw(m))
    ring_ = m.filter(ImageFilter.MaxFilter(OUTLINE))
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    img.paste(Image.new("RGBA", (S, S), (0, 0, 0, 235)), (0, 0), ring_)
    img.paste(Image.new("RGBA", (S, S), (255, 255, 255, 255)), (0, 0), m)
    return img.resize((OUT, OUT), Image.LANCZOS)


os.makedirs(DST, exist_ok=True)
done = []
for name, fn in ICONS.items():
    img = build(fn)
    img.save(os.path.join(DST, "%s.png" % name))
    done.append((name, img))
print("значков:", len(done))
if len(sys.argv) > 1:
    cols = 8
    rows = (len(done) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * 140, rows * 140), (60, 66, 74, 255))
    for k, (name, img) in enumerate(done):
        sheet.alpha_composite(img, ((k % cols) * 140 + 6, (k // cols) * 140 + 6))
    sheet.save(sys.argv[1])
