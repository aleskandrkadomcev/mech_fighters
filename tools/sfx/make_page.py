# Страница сравнения: было / референс / новые варианты, спектрограммы, очереди.
import sys, os, html
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build import *

OUT = sys.argv[1]
WAV = os.path.join(OUT, "wav"); IMG = os.path.join(OUT, "img")
os.makedirs(WAV, exist_ok=True); os.makedirs(IMG, exist_ok=True)
OLD = P + "sounds/"

G = [
    ("shot", "Автопушка", "shot.wav", ["shot_A", "shot_B"], 1.2,
     "Сейчас: глухой низкий «тук» без щелчка, обрывается за 0,2 с. Этот же звук у крипов и у гатлинга."),
    ("minigun", "Гатлинг", "shot.wav", ["minigun_A", "minigun_B"], 0.6,
     "Сейчас гатлинг играет звук автопушки, только тише. Свой звук — новый файл и одна строчка в коде."),
    ("cannon", "Тяжёлое орудие", "cannon.wav", ["cannon_A", "cannon_B"], 2.0,
     "Сейчас: гудящий низ без верхов, обрывается «стеной» на 0,7 с."),
    ("shotgun", "Дробовик", "shotgun.wav", ["shotgun_A", "shotgun_B"], 1.5,
     "Сейчас: ровный шум плюс низ, обрывается разом."),
    ("rail", "Рельсотрон", "rail.wav", ["rail_A", "rail_B"], 2.0,
     "Сейчас: тонкий писк и низ, середины нет."),
    ("grenade", "Гранатомёт", "grenade.wav", ["grenade_A", "grenade_B"], 1.2,
     "Сейчас: один низкий «бум» без щелчка и механики."),
    ("blaster", "Бластер", "blaster.wav", ["blaster_A", "blaster_B"], 1.0,
     "Сейчас: «пиу» без удара и низа."),
    ("laser", "Лазер (гул луча, играет по кругу)", "laser.wav", ["laser_A", "laser_B"], 1.5,
     "Сейчас: ровный синтетический гул."),
    ("hit", "Попадание по броне (мехи, постройки)", "hit.wav", ["hit_A", "hit_B", "hit_C"], 0.6,
     "Сейчас: два чистых «бипа» без удара, звона и искр."),
    ("wall", "Попадание в стену и землю", "wall.wav", ["wall_A", "wall_B"], 0.6,
     "Сейчас: щелчок на 0,1 с."),
]

DESC = {
    "shot_A": "АК-47 (настоящая запись) чуть ниже + он же вдвое медленнее — «бум» + саб-удар + лязг затвора + хвост эха.",
    "shot_B": "Carl Gustav (запись) ниже + винтовка 1917 вдвое медленнее — «бум» + очередь пулемёта + саб + хвост эха.",
    "minigun_A": "ППШ: только хлопок 35 мс + короткий «бум» + саб. Хвост 0,3 с — в очереди сливается в рёв.",
    "minigun_B": "Пулемёт + щелчок AR-15 + «бум» + саб, ещё суше.",
    "cannon_A": "Винтовка 1917 ниже + она же в 2,6 раза медленнее + выстрел пушки (запись) + саб 58→30 Гц + звон ствола + длинное эхо.",
    "cannon_B": "Мосинка ниже + Tikka в 3 раза медленнее + саб + щелчок + длинное эхо. Темнее и тяжелее A.",
    "shotgun_A": "Mossberg + Model 12 замедленный + дробовик + саб + лязг перезарядки через 0,33 с + эхо.",
    "shotgun_B": "Nova + она же замедленная + дробовик + саб + эхо, без перезарядки.",
    "rail_A": "Сверхзвуковой щелчок + «бум» + энерговыстрел + свист вниз 6000→90 Гц + треск искр + саб + длинное эхо.",
    "rail_B": "Разряд «пушки судного дня» + щелчок + «бум» + саб; с поющим тоном в хвосте.",
    "grenade_A": "Запуск снаряда + «пумп» трубы + саб + лязг + эхо.",
    "grenade_B": "Запуск ракеты, обрезан + «пумп» трубы + саб; шипения больше.",
    "blaster_A": "Лазерный пистолет + саб-удар + свист вниз + искра + эхо.",
    "blaster_B": "Энерговыстрел + саб-удар + искра; ярче и суше.",
    "laser_A": "Луч, середина зациклена без шва + гул 55 Гц.",
    "laser_B": "Другой луч, ниже и мягче + гул 48 Гц.",
    "hit_A": "Глухой удар по металлу + короткий пинок + щелчок + искры. Плотный «бдыщ».",
    "hit_B": "Звонкий удар по металлу + звон + пинок + искры. Звонче, лучше слышен в шуме боя.",
    "hit_C": "Удар по металлу + кулачный удар + лист брони + щелчок. Самый короткий и тупой.",
    "wall_A": "Удар + осыпь камня + глухой удар. Сухо, «бетон».",
    "wall_B": "Попадание пули + осыпь бетона + глухой удар. Пыльнее, с хвостиком.",
}

# откуда взяты исходники (для подписи под референсом)
SRC = {
    FA: "The Free Firearm Sound Library, CC0",
    MB: "Michel Baradari, CC-BY 3.0",
    ML: "Michel Baradari, CC-BY 3.0",
    LK: "Lentikula, CC0",
    JC: "JC Sounds, CC-BY 4.0",
    BL: "blacklodgegames, CC0",
    RW: "rubberduck, CC0",
    RB: "rubberduck, CC0",
    OI: "OGA «Impacts», CC0",
    I: "OpenGameArt, CC0",
}

EXTRA_REF = {
    "blaster": [(LK + "Laser Pistol 4.wav", 0, 0.5, False), (JC + "single_energy_shot_v1_01.ogg", 0, 0.5, False)],
    "laser": [(LK + "Laser Beam 1.wav", 0, 1.5, False)],
    "hit": [(BL + "dull_metal_collision_01_44k_32bit_stereo.wav", 0, 0.35, False), (RW + "metal_hit_03.ogg", 0, 0.3, False)],
    "wall": [(RB + "bfh1_rock_breaking_01.ogg", 0, 0.4, False), (OI + "impact_gun_1.ogg", 0, 0.5, False)],
    "rail": [(LK + "Laser Rifle 2.wav", 0, 1.2, False)],
    "grenade": [(ML + "flaunch.wav", 0, 0.6, False)],
}

NICE = {"ak_47_single_near.ogg": "АК-47", "carl_gustav_m45_single_near.ogg": "Carl Gustav M45", "ppsh_single_near.ogg": "ППШ",
        "ar_15_single_near.ogg": "AR-15", "1917_single_near.ogg": "винтовка M1917", "mosin_nagant_single_near.ogg": "Мосинка",
        "mossberg_single_near.ogg": "Mossberg", "nova_single_near.ogg": "Benelli Nova", "Laser Rifle 2.wav": "Laser Rifle 2",
        "flaunch.wav": "flaunch (запуск)", "Laser Pistol 4.wav": "Laser Pistol 4", "single_energy_shot_v1_01.ogg": "energy shot",
        "Laser Beam 1.wav": "Laser Beam 1", "dull_metal_collision_01_44k_32bit_stereo.wav": "dull metal collision",
        "metal_hit_03.ogg": "metal hit 03", "bfh1_rock_breaking_01.ogg": "rock breaking", "impact_gun_1.ogg": "impact gun 1"}

BAND_RU = [("sub", "саб"), ("low", "низ"), ("lowmid", "тело"), ("mid", "сер"), ("high", "щелч"), ("air", "возд")]


def src_of(path):
    best = ""
    for k, v in SRC.items():
        if path.startswith(k) and len(k) > len(best):
            best = k
    return SRC.get(best, "")


def ref_clip(r):
    path, which, length, is_shot = r
    return shot(path, which, length) if is_shot else whole(path, 0, length)


GT = {"shot": "gun", "minigun": "gun", "shotgun": "gun", "cannon": "heavy", "rail": "heavy", "grenade": "heavy", "hit": "armor", "wall": "ground"}


def bal(x, tg):
    # насколько баланс шести полос отличается от целевого (дБ, среднее)
    b = analyze(x)["bands"]; t = TARGETS[tg]
    d = np.array([b[k] - t[k] for k in t]); d -= d.mean()
    return float(np.sqrt(np.mean(d ** 2)))


def to_loud(x, target_l):
    # подогнать громкость (как слышит ухо) под старый звук, но без перегруза
    g = 10 ** ((target_l - loudness(x)) / 20)
    y = x * g
    pk = np.abs(y).max()
    if pk > 0.92:
        y *= 0.92 / pk
    return y


def bars_svg(x):
    b = analyze(x)["bands"]
    w, h = 132, 44
    parts = [f'<svg class="bars" viewBox="0 0 {w} {h + 12}" width="{w}" height="{h + 12}">']
    for i, (k, ru) in enumerate(BAND_RU):
        v = max(0.0, min(1.0, (b[k] + 30) / 30))
        bh = max(1, int(v * h))
        parts.append(f'<rect x="{i * 22 + 2}" y="{h - bh}" width="18" height="{bh}" rx="2"/>')
        parts.append(f'<text x="{i * 22 + 11}" y="{h + 10}">{ru}</text>')
    parts.append("</svg>")
    return "".join(parts)


def item(key, label, x, dur, note="", sub="", cls=""):
    wp = os.path.join(WAV, key + ".wav")
    save_wav(wp, x)
    spectro_png(x, os.path.join(IMG, key + ".png"), dur=dur, w=600, h=150)
    a = analyze(x)
    return f'''<div class="item {cls}">
  <div class="meta"><div class="lab">{html.escape(label)}</div><div class="sub">{html.escape(sub)}</div>
  <audio controls preload="none" src="wav/{key}.wav"></audio>
  <div class="num">длина {a["dur"]:.2f} с</div>{note}</div>
  <img class="spec" src="img/{key}.png" alt="">
  {bars_svg(x)}
</div>'''


def seq_shots(snd, rate, count, pitch=0.06, hit=None, hit_db=-7, hit_delay=0.22, seed=1):
    rng = np.random.default_rng(seed)
    layers = []
    for i in range(count):
        layers.append((speed(snd, 1 + rng.uniform(-pitch, pitch)), 0, i * 1000 / rate))
        if hit is not None:
            layers.append((speed(hit, 1 + rng.uniform(-0.12, 0.12)), hit_db + rng.uniform(-2, 0), i * 1000 / rate + hit_delay * 1000))
    y = mix(*layers)
    return norm(y, -1.5)


def pellets(hit, n=8, seed=2):
    rng = np.random.default_rng(seed)
    return norm(mix(*[(speed(hit, 1 + rng.uniform(-0.12, 0.12)), rng.uniform(-4, 0), rng.uniform(0, 45)) for _ in range(n)]), -1.5)


sections = []
built = {}
for gkey, title, oldf, vars_, dur, problem in G:
    old = load(OLD + oldf)
    if gkey == "minigun":
        old = old * 10 ** (-4 / 20)
    target = loudness(old)
    rows = [item(gkey + "_old", "Сейчас в игре", old, dur, sub=f"sounds/{oldf}", cls="old")]
    # референсы
    refs = []
    for v in vars_:
        if v in REF and REF[v] not in refs:
            refs.append(REF[v])
    for r in EXTRA_REF.get(gkey, []):
        if r not in refs:
            refs.append(r)
    for i, r in enumerate(refs[:2]):
        rc = to_loud(ref_clip(r), target)
        nm = NICE.get(os.path.basename(r[0]), os.path.basename(r[0]))
        rows.append(item(f"{gkey}_ref{i + 1}", f"Референс: {nm}", rc, dur, sub=src_of(r[0]), cls="ref"))
    # варианты
    for v in vars_:
        x = to_loud(R[v](), target)
        built[v] = x
        note = ""
        tg = GT.get(gkey)
        if tg:
            note += f'<div class="cmp">баланс полос против цели: было {bal(old, tg):.1f} дБ → стало <b>{bal(x, tg):.1f} дБ</b></div>'
        if v in REF:
            note += f'<div class="cmp">тембр против записи: <b>{hi_distance(x, ref_clip(REF[v])):.1f} дБ</b></div>'
        rows.append(item(v, "Вариант " + v[-1], x, dur, note=note, sub=DESC.get(v, ""), cls="new"))
    sections.append((gkey, title, problem, rows))

# очереди «как в бою»
demo = []
oldshot, oldhit = load(OLD + "shot.wav"), load(OLD + "hit.wav")
demo.append(("demo_auto_old", "Автопушка + попадания — сейчас", seq_shots(oldshot, 3.5, 7, hit=oldhit)))
demo.append(("demo_auto_A", "Автопушка A + попадание A", seq_shots(built["shot_A"], 3.5, 7, hit=built["hit_A"])))
demo.append(("demo_auto_B", "Автопушка B + попадание B", seq_shots(built["shot_B"], 3.5, 7, hit=built["hit_B"])))
demo.append(("demo_mini_old", "Гатлинг, 14 выстрелов/с — сейчас", seq_shots(oldshot, 14, 28)))
demo.append(("demo_mini_A", "Гатлинг A", seq_shots(built["minigun_A"], 14, 28)))
demo.append(("demo_mini_B", "Гатлинг B", seq_shots(built["minigun_B"], 14, 28)))
demo.append(("demo_pel_old", "Дробь по броне (8 дробин разом) — сейчас", pellets(oldhit)))
for v in ["hit_A", "hit_B", "hit_C"]:
    demo.append((f"demo_pel_{v[-1]}", f"Дробь по броне — попадание {v[-1]}", pellets(built[v])))
oldcan = load(OLD + "cannon.wav")
demo.append(("demo_can_old", "Тяжёлое орудие, 2 выстрела — сейчас", seq_shots(oldcan, 0.7, 2, pitch=0.04)))
demo.append(("demo_can_A", "Тяжёлое орудие A", seq_shots(built["cannon_A"], 0.7, 2, pitch=0.04)))
demo.append(("demo_can_B", "Тяжёлое орудие B", seq_shots(built["cannon_B"], 0.7, 2, pitch=0.04)))
loop_old = load(OLD + "laser.wav");
demo.append(("demo_las_old", "Лазер, 3 с по кругу — сейчас", norm(np.tile(loop_old, 3), -3)))
demo.append(("demo_las_A", "Лазер A по кругу (проверка шва)", norm(np.tile(built["laser_A"], 2), -3)))
demo.append(("demo_las_B", "Лазер B по кругу", norm(np.tile(built["laser_B"], 2), -3)))
demo_rows = []
for key, lab, x in demo:
    save_wav(os.path.join(WAV, key + ".wav"), x)
    demo_rows.append(f'<div class="demo"><div class="lab">{html.escape(lab)}</div><audio controls preload="none" src="wav/{key}.wav"></audio></div>')

CSS = """
:root{--bg:#101217;--panel:#181b22;--line:#2a2f3a;--text:#e6e8ee;--dim:#9aa1b0;--old:#c96a5a;--ref:#7f8ea8;--new:#5fbf7f;--acc:#f0b54a}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:15px/1.45 system-ui,Segoe UI,Arial,sans-serif}
.wrap{max-width:1180px;margin:0 auto;padding:24px 16px 80px}
h1{font-size:26px;margin:0 0 6px}h2{font-size:20px;margin:0}
.lead{color:var(--dim);max-width:900px}
.box{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:14px 16px;margin:16px 0}
.box b{color:var(--acc)}
nav{display:flex;flex-wrap:wrap;gap:6px;margin:14px 0}nav a{color:var(--text);text-decoration:none;background:var(--panel);border:1px solid var(--line);padding:4px 10px;border-radius:20px;font-size:13px}
section{margin-top:34px;border-top:1px solid var(--line);padding-top:18px}
.prob{color:var(--old);margin:4px 0 12px;font-size:14px}
.item{display:grid;grid-template-columns:300px 1fr 140px;gap:14px;align-items:center;background:var(--panel);border:1px solid var(--line);border-left:4px solid var(--line);border-radius:8px;padding:10px 12px;margin:8px 0}
.item.old{border-left-color:var(--old)}.item.ref{border-left-color:var(--ref)}.item.new{border-left-color:var(--new)}
.lab{font-weight:600}.item.new .lab{color:var(--new)}.item.old .lab{color:var(--old)}.item.ref .lab{color:var(--ref)}
.sub{color:var(--dim);font-size:12.5px;margin:2px 0 6px}
.num{color:var(--dim);font-size:12px;margin-top:4px}.cmp{font-size:12.5px;margin-top:3px;color:var(--dim)}.cmp b{color:var(--new)}
audio{width:100%;height:34px}
.spec{width:100%;max-width:600px;height:auto;border-radius:4px;display:block;image-rendering:auto}
.bars rect{fill:#6f86b8}.item.new .bars rect{fill:var(--new)}.item.old .bars rect{fill:var(--old)}
.bars text{fill:#8b93a5;font-size:8px;text-anchor:middle}
.demos{display:grid;grid-template-columns:repeat(auto-fill,minmax(330px,1fr));gap:8px}
.demo{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:8px 10px}.demo .lab{font-size:13.5px;margin-bottom:4px}
.legend{display:grid;grid-template-columns:auto 1fr;gap:4px 12px;font-size:13.5px;color:var(--dim)}
@media(max-width:820px){.item{grid-template-columns:1fr}.bars{display:none}}
"""

nav = "".join(f'<a href="#{k}">{html.escape(t.split(" (")[0])}</a>' for k, t, *_ in G) + '<a href="#demo">Как звучит в бою</a>'
body = [f"""<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Звуки выстрелов</title><style>{CSS}</style></head><body><div class="wrap">
<h1>Звуки выстрелов и попаданий — было и новые варианты</h1>
<p class="lead">Новые звуки собраны слоями из бесплатных записей (CC0 и CC-BY): настоящий выстрел даёт щелчок,
он же, замедленный в 2–3 раза, даёт «бум», снизу добавлен саб-удар, сверху лязг механизма, в конце хвост эха.
Тембр выше 250 Гц подогнан под настоящую запись (референс), низ — свой. Громкость каждого варианта выровнена под нынешний звук,
так что сравнивать честно, а в игре громкости в коде менять не придётся.</p>
<div class="box"><b>Как выбрать:</b> послушай «Сейчас», потом варианты. Напиши, что брать, например: «автопушка A, орудие B, попадание B».
Если ни один не нравится — скажи, чего не хватает (больше низа, звонче, короче, длиннее хвост), переделаю.
Лучше слушать в наушниках или на колонках с басом: саб-удар на ноутбучных динамиках почти не слышен.</div>
<div class="box legend"><div><b>Цвета</b></div><div><span style="color:var(--old)">красный</span> — сейчас в игре, <span style="color:var(--ref)">серо-синий</span> — референс (исходная запись), <span style="color:var(--new)">зелёный</span> — новый вариант.</div>
<div><b>Картинка</b></div><div>спектрограмма: слева направо время, снизу вверх частота (100 Гц, 1 кГц, 10 кГц). Ярче — громче. У хорошего выстрела яркая вертикальная «вспышка» сверху донизу в начале и плавно гаснущий хвост.</div>
<div><b>Столбики</b></div><div>сколько энергии в полосах: саб (удар в грудь), низ, тело, середина, щелчок, воздух.</div>
<div><b>«Баланс против цели»</b></div><div>насколько соотношение саба, тела и щелчка отличается от того, что звучит сочно в играх (много низа и тела, внятный щелчок, немного воздуха). 0 — точно в цели, больше 6 — сильный перекос.</div>
<div><b>«Тембр против записи»</b></div><div>насколько форма спектра выше 250 Гц отличается от настоящей записи-референса. До 3 дБ — на слух почти тот же характер.</div></div>
<nav>{nav}</nav>"""]
for gkey, title, problem, rows in sections:
    body.append(f'<section id="{gkey}"><h2>{html.escape(title)}</h2><div class="prob">{html.escape(problem)}</div>' + "".join(rows) + "</section>")
body.append('<section id="demo"><h2>Как звучит в бою</h2><div class="prob" style="color:var(--dim)">Очереди с темпом стрельбы из игры и разбросом высоты, как в игре. Попадание — через 0,22 с после выстрела.</div><div class="demos">' + "".join(demo_rows) + "</div></section>")
body.append("""<section><h2>Откуда звуки</h2><div class="lead" style="font-size:13.5px">
The Free Firearm Sound Library (CC0) · Michel Baradari, apollo-music.de — «Chaingun, pistol, rifle, shotgun shots», «4 projectile launches» (CC-BY 3.0) ·
Lentikula — Sci-Fi Weapon Shots (CC0, itch.io) · JC Sounds — Sci-Fi Pack Vol 1 (CC-BY 4.0) · thimras — Cannon fire (CC0) · tad — Doomsday Laser Cannon (CC0) ·
blacklodgegames — 27 Metal Audio Samples (CC0) · rubberduck — 100 CC0 metal and wood SFX, 75 CC0 breaking/falling/hit SFX (CC0) · Kenney — Impact Sounds (CC0) · OGA «Impacts» (CC0).
Саб-удары, свисты, искры, гул и эхо синтезированы.</div></section></div></body></html>""")
with open(os.path.join(OUT, "звуки.html"), "w", encoding="utf-8") as f:
    f.write("\n".join(body))
print("ok", len(os.listdir(WAV)), "wav")
