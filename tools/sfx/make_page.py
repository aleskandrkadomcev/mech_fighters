# Страница сравнения: было / референс / новые варианты, спектрограммы, очереди.
import sys, os, html
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build import *

OUT = sys.argv[1]
WAV = os.path.join(OUT, "wav"); IMG = os.path.join(OUT, "img")
os.makedirs(WAV, exist_ok=True); os.makedirs(IMG, exist_ok=True)
OLD = P + "sounds/"

G = [
    ("shot", "Автопушка", "shot.wav", ["shot_A", "shot_B", "shot_C", "shot_D"], 0.8,
     "Сейчас: глухой низкий «тук» без щелчка. Этот же звук у крипов и у гатлинга."),
    ("minigun", "Гатлинг", "shot.wav", ["minigun_A", "minigun_B", "minigun_C"], 0.4,
     "Сейчас гатлинг играет звук автопушки, только тише. Свой звук — новый файл и одна строчка в коде."),
    ("cannon", "Тяжёлое орудие", "cannon.wav", ["cannon_A", "cannon_B", "cannon_C", "cannon_D"], 1.0,
     "Сейчас: гудящий низ без верхов, обрывается «стеной» на 0,7 с."),
    ("shotgun", "Дробовик (залп картечью)", "shotgun.wav", ["shotgun_A", "shotgun_B"], 0.8,
     "Сейчас: ровный шум плюс низ, обрывается разом."),
    ("rail", "Рельсотрон", "rail.wav", ["rail_A", "rail_B", "rail_C", "rail_D", "rail_E"], 1.0,
     "Сейчас: тонкий писк и низ, середины нет."),
    ("blaster", "Бластер", "blaster.wav", ["blaster_A", "blaster_B", "blaster_C", "blaster_D", "blaster_E", "blaster_F"], 0.6,
     "Сейчас: «пиу» без удара и низа."),
    ("grenade", "Гранатомёт", "grenade.wav", ["grenade_A", "grenade_B"], 0.8,
     "Сейчас: один низкий «бум» без щелчка и механики."),
    ("laser", "Лазер (гул луча, играет по кругу)", "laser.wav", ["laser_A", "laser_B"], 1.5,
     "Сейчас: ровный синтетический гул."),
    ("hit", "Попадание по броне (мехи, постройки)", "hit.wav", ["hit_A", "hit_B", "hit_C"], 0.6,
     "Сейчас: два чистых «бипа» без удара, звона и искр. Варианты те же, что в прошлый раз (эха в них и не было)."),
    ("wall", "Попадание в стену и землю", "wall.wav", ["wall_A", "wall_B"], 0.6,
     "Сейчас: щелчок на 0,1 с. Варианты те же, что в прошлый раз."),
]

DESC = {
    "shot_A": "30-мм автопушка (запись) чуть ниже + она же замедленная — «бум» + саб-удар + щелчок-вспышка.",
    "shot_B": "Крупнокалиберный пулемёт 12,7 мм (M2), одиночный, ниже + «бум» + саб + тихий лязг затвора.",
    "shot_C": "ДШК, опущен на треть ниже — калибр «как у КПВТ» + «бум» + щелчок второго пулемёта + саб.",
    "shot_D": "Сай-фай: 12,7 мм + электромагнитный «вжик» разгона + звон ствола + саб.",
    "minigun_A": "Счетверённый 12,7 мм (зенитный Avenger): один хлопок 60 мс + короткий «бум» + саб.",
    "minigun_B": "12,7 мм из очереди, чуть выше и суше.",
    "minigun_C": "Сай-фай: импульсная винтовка + хлопок 12,7 мм — «энергопулемёт», самый короткий.",
    "cannon_A": "Танковое орудие (запись) ниже + «бум» + саб 62→30 Гц + щелчок-вспышка.",
    "cannon_B": "Гаубица + тяжёлый артвыстрел + «бум» + саб 58→28 Гц. Самый плотный.",
    "cannon_C": "Barrett 12,7 мм, опущен — как противотанковое ружьё + глубокий «бум» пушки + саб. Резче, суше.",
    "cannon_D": "Сай-фай: танковый выстрел + щелчок 12,7 + электромагнитный разряд + искры + саб.",
    "shotgun_A": "Три выстрела 12,7 мм почти разом (разброс 17 мс) + «бум» + шум картечи + саб.",
    "shotgun_B": "Тяжёлый артвыстрел + зенитный залп + «бум» + саб.",
    "rail_A": "Запись испытаний рейлгана + электромагнитный разряд + искры + саб.",
    "rail_B": "Сай-фай рейлган, яркий и шипящий + щелчок + саб.",
    "rail_C": "Глухой тяжёлый сай-фай рейлган + щелчок 12,7 мм сверху + саб.",
    "rail_D": "Корабельный рейлган + сверхзвуковой щелчок 12,7 мм + саб.",
    "rail_E": "Синтез: щелчок 12,7 мм + магнитный свист вниз + треск + звон + саб. Самый «электрический».",
    "blaster_A": "Бластер с низким «пиу» вниз + саб.",
    "blaster_B": "Тяжёлый бластер, звонкий + саб.",
    "blaster_C": "Бластер «бзыщ», плотная середина + саб.",
    "blaster_D": "Плазма: низкий «вуп» + яркий щелчок плазмы сверху.",
    "blaster_E": "Дизайнерский выстрел (лазер-импульс) + саб.",
    "blaster_F": "Плазменный пистолет: мягкий, с низом.",
    "grenade_A": "Запуск снаряда + «пумп» трубы + саб + лязг. Без эха, короче прошлого.",
    "grenade_B": "Запуск ракеты + «пумп» трубы + саб. Без эха.",
    "laser_A": "Луч, середина зациклена без шва + гул 55 Гц.",
    "laser_B": "Другой луч, ниже и мягче + гул 48 Гц.",
    "hit_A": "Глухой удар по металлу + короткий пинок + щелчок + искры. Плотный «бдыщ».",
    "hit_B": "Звонкий удар по металлу + звон + пинок + искры. Звонче, лучше слышен в шуме боя.",
    "hit_C": "Удар по металлу + кулачный удар + лист брони + щелчок. Самый короткий и тупой.",
    "wall_A": "Удар + осыпь камня + глухой удар. Сухо, «бетон».",
    "wall_B": "Попадание пули + осыпь бетона + глухой удар. Пыльнее, с хвостиком.",
}

# названия исходных записей freesound (автор берётся из assets/incoming/freesound/_sources.json)
FSN = {854186: "30-мм автопушка", 183656: "пулемёт 12,7 мм M2", 122103: "ДШК", 239138: "пулемёт 12,7 мм, очередь",
       160355: "зенитный Avenger 12,7 мм", 169775: "импульсная винтовка", 239135: "танковое орудие", 175430: "гаубица Excalibur",
       441373: "тяжёлый артвыстрел", 865990: "Barrett 12,7 мм", 853281: "глубокий выстрел пушки", 127845: "танковый выстрел (сведённый)",
       701491: "зенитный залп", 162260: "испытания рейлгана", 785380: "рейлган", 699655: "рейлган X", 155790: "корабельный рейлган",
       466868: "бластер", 702000: "тяжёлый бластер", 475142: "бластер", 569901: "плазменный бластер", 584198: "выстрел плазмы",
       861535: "лазер-импульс", 450768: "плазменный пистолет"}
FSA = {int(r["id"]): r["user"] for r in json.load(open(FS + "_sources.json", encoding="utf-8"))}

BAND_RU = [("sub", "саб"), ("low", "низ"), ("lowmid", "тело"), ("mid", "сер"), ("high", "щелч"), ("air", "возд")]


GT = {"shot": "sharp", "minigun": "sharp", "shotgun": "sharp", "cannon": "heavy", "grenade": "heavy", "hit": "armor", "wall": "ground"}


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


def item(key, label, x, dur, note="", sub="", cls="", src=None):
    wp = os.path.join(WAV, key + ".wav")
    save_wav(wp, x)
    if src is not None:
        sx, sname = src
        save_wav(os.path.join(WAV, key + "_src.wav"), sx)
        note += f'<div class="srcl">исходная запись: {html.escape(sname)}</div><audio class="srca" controls preload="none" src="wav/{key}_src.wav"></audio>'
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
    for v in vars_:
        x = to_loud(R[v](), target)
        built[v] = x
        note = ""
        tg = GT.get(gkey)
        if tg:
            note += f'<div class="cmp">баланс полос против цели: было {bal(old, tg):.1f} дБ → стало <b>{bal(x, tg):.1f} дБ</b></div>'
        sr = None
        if v in REF:
            i, t, ln = REF[v]
            raw = at(i, t, max(ln, 0.3 if gkey == "minigun" else 0.6))
            sr = (to_loud(raw, target), f"{FSN.get(i, i)} — {FSA.get(i, '')}, freesound, CC0")
        rows.append(item(v, "Вариант " + v.split("_")[1], x, dur, note=note, sub=DESC.get(v, ""), cls="new", src=sr))
    sections.append((gkey, title, problem, rows))

# очереди «как в бою»
demo = []
oldshot, oldhit = load(OLD + "shot.wav"), load(OLD + "hit.wav")
demo.append(("demo_auto_old", "Автопушка + попадания — сейчас", seq_shots(oldshot, 3.5, 7, hit=oldhit)))
for v in ["shot_A", "shot_B", "shot_C", "shot_D"]:
    demo.append((f"demo_auto_{v[-1]}", f"Автопушка {v[-1]} + попадание A", seq_shots(built[v], 3.5, 7, hit=built["hit_A"])))
demo.append(("demo_mini_old", "Гатлинг, 14 выстрелов/с — сейчас", seq_shots(oldshot, 14, 28)))
for v in ["minigun_A", "minigun_B", "minigun_C"]:
    demo.append((f"demo_mini_{v[-1]}", f"Гатлинг {v[-1]}", seq_shots(built[v], 14, 28)))
oldcan = load(OLD + "cannon.wav")
demo.append(("demo_can_old", "Тяжёлое орудие, 2 выстрела — сейчас", seq_shots(oldcan, 0.7, 2, pitch=0.04)))
for v in ["cannon_A", "cannon_B", "cannon_C", "cannon_D"]:
    demo.append((f"demo_can_{v[-1]}", f"Тяжёлое орудие {v[-1]}", seq_shots(built[v], 0.7, 2, pitch=0.04)))
oldbl = load(OLD + "blaster.wav")
demo.append(("demo_bl_old", "Бластер, 3 выстрела/с — сейчас", seq_shots(oldbl, 3, 6)))
for v in ["blaster_A", "blaster_B", "blaster_C", "blaster_D", "blaster_E", "blaster_F"]:
    demo.append((f"demo_bl_{v[-1]}", f"Бластер {v[-1]}", seq_shots(built[v], 3, 6)))
demo.append(("demo_pel_old", "Дробь по броне (8 дробин разом) — сейчас", pellets(oldhit)))
for v in ["hit_A", "hit_B", "hit_C"]:
    demo.append((f"demo_pel_{v[-1]}", f"Дробь по броне — попадание {v[-1]}", pellets(built[v])))
loop_old = load(OLD + "laser.wav")
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
.srcl{font-size:12px;color:var(--ref);margin-top:6px}audio.srca{height:28px;opacity:.85}
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
<h1>Звуки выстрелов — вторая попытка</h1>
<p class="lead">Переделано по замечаниям: <b style="color:var(--acc)">эха нет совсем</b>, калаши и винтовки убраны. Основа — записи крупного калибра:
пулемёты 12,7 мм (M2, ДШК, зенитный Avenger), 30-мм автопушка, танк, гаубица, Barrett; для рейлганов и бластеров — сай-фай записи.
Каждый выстрел: резкий щелчок-вспышка, короткое тело, саб-удар снизу и быстрое затухание (автопушка гаснет за 0,2 с, орудие — за 0,5 с).
У каждого варианта под описанием есть исходная запись — слышно, из чего собрано. Все записи — freesound.org, лицензия CC0 (можно в игру без указания автора).
Громкость выровнена под нынешние звуки.</p>
<div class="box"><b>Как выбрать:</b> напиши, например: «автопушка C, гатлинг A, орудие B, рельса A, бластер D». Можно разным пушкам разные типы —
например, одна автопушка «КПВТ», другая «масс-драйвер». Не нравится — скажи чем: ниже, звонче, короче, больше «электричества».
Лучше слушать в наушниках или на колонках с басом.</div>
<div class="box legend"><div><b>Цвета</b></div><div><span style="color:var(--old)">красный</span> — сейчас в игре, <span style="color:var(--ref)">серо-синий</span> — исходная запись под вариантом, <span style="color:var(--new)">зелёный</span> — новый вариант.</div>
<div><b>Картинка</b></div><div>спектрограмма: слева направо время, снизу вверх частота (100 Гц, 1 кГц, 10 кГц). Ярче — громче. У хорошего выстрела яркая вертикальная «вспышка» сверху донизу в начале и плавно гаснущий хвост.</div>
<div><b>Столбики</b></div><div>сколько энергии в полосах: саб (удар в грудь), низ, тело, середина, щелчок, воздух.</div>
<div><b>«Баланс против цели»</b></div><div>насколько соотношение саба, тела и щелчка отличается от того, что звучит сочно в играх (много низа и тела, внятный щелчок, немного воздуха). 0 — точно в цели, больше 6 — сильный перекос.</div>
</div>
<nav>{nav}</nav>"""]
for gkey, title, problem, rows in sections:
    body.append(f'<section id="{gkey}"><h2>{html.escape(title)}</h2><div class="prob">{html.escape(problem)}</div>' + "".join(rows) + "</section>")
body.append('<section id="demo"><h2>Как звучит в бою</h2><div class="prob" style="color:var(--dim)">Очереди с темпом стрельбы из игры и разбросом высоты, как в игре. Попадание — через 0,22 с после выстрела.</div><div class="demos">' + "".join(demo_rows) + "</div></section>")
used = sorted({REF[v][0] for v in REF} | {183656, 239138, 160355, 441373, 853281, 701491, 584198})
fsl = " · ".join(f'{html.escape(FSN.get(i, str(i)))} — {html.escape(FSA.get(i, ""))} (freesound {i})' for i in used)
body.append(f"""<section><h2>Откуда звуки</h2><div class="lead" style="font-size:13.5px">
Выстрелы: freesound.org, CC0 — {fsl}.<br>
Гранатомёт: Michel Baradari, apollo-music.de — «4 projectile launches» (CC-BY 3.0). Лазер: Lentikula — Sci-Fi Weapon Shots (CC0).
Попадания: blacklodgegames — 27 Metal Audio Samples (CC0) · rubberduck — 100 CC0 metal and wood SFX, 75 CC0 breaking/falling/hit SFX (CC0) · Kenney — Impact Sounds (CC0) · OGA «Impacts» (CC0) · thimras — Cannon hit wall (CC0).
Саб-удары, щелчки, свисты, искры и гул синтезированы.</div></section></div></body></html>""")
with open(os.path.join(OUT, "звуки.html"), "w", encoding="utf-8") as f:
    f.write("\n".join(body))
print("ok", len(os.listdir(WAV)), "wav")
