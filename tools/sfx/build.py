# Сборка новых звуков выстрелов и попаданий из слоёв (исходники — assets/incoming, см. CREDITS).
# Страница сравнения: python -P tools/sfx/make_page.py ПАПКА. Нужны numpy, scipy, Pillow, ffmpeg.
import sys, os, json, glob
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sfxlab import *

P = "C:/Users/Lenkin/Клод_проекты/mech_fighters/"
FA = P + "assets/sounds/oga_free_firearms/"
I = P + "assets/incoming/oga_sounds2/"
MB = I + "x_shots/shots/"            # Michel Baradari, CC-BY 3.0
ML = I + "x_launches/launches/"      # Michel Baradari, CC-BY 3.0
BL = I + "x_27-Metal-Audio-Samples-blacklodgegames.com_/27-Metal-Audio-Samples-blacklodgegames.com/"
LK = P + "assets/incoming/itch_lentikula/x/"
JC = P + "assets/sounds/jc_scifi_vol1/"
KI = P + "assets/sounds/kenney_impact-sounds/"
OI = P + "assets/sounds/oga_impacts/"
RW = P + "assets/incoming/oga_sounds2/x_100-CC0-wood-metal-SFX/"   # rubberduck 100 CC0 metal and wood
RB = P + "assets/incoming/oga_sounds2/x_sfx_breaking_and_falling/"   # rubberduck 75 CC0 breaking/falling/hit
FS = P + "assets/incoming/freesound/"   # freesound.org, CC0 (авторы — _sources.json там же)

_cache = {}


def L(path):
    if path not in _cache:
        _cache[path] = load(path)
    return _cache[path]


def shot(path, which=0, length=0.6, pre=0.002):
    # вырезать один выстрел: от начала атаки самого громкого удара (или which-го по счёту)
    x = L(path)
    e = env_db(x, 0.002); top = e.max()
    peaks = []; i = 0
    while i < len(e):
        if e[i] > top - 6:
            j = i + int(np.argmax(e[i:i + int(0.05 * SR)])); peaks.append(j); i = j + int(0.4 * SR)
        else:
            i += 1
    pk = peaks[min(which, len(peaks) - 1)]
    s = pk
    while s > 0 and e[s] > e[pk] - 30:
        s -= 1
    s = max(0, s - int(pre * SR))
    return fade(x[s:s + int(length * SR)], 0.0005, 0.04)


def whole(path, start=0.0, length=None):
    x = trim(L(path), -50)
    x = cut(x, start, length)
    return fade(x, 0.0005, 0.03)


def finish(x, drive=1.6, thr=-16, ratio=3.0, tail_keep=None, tail_ms=None, fo=0.06, hpf=28, target=None, push=7.0):
    x = hp(x, hpf, 2)
    if target:
        x = tilt_to(x, TARGETS[target])
    if tail_keep is not None:
        x = tail_shape(x, tail_keep, tail_ms)
    x = norm(x, -3)
    x = sat(x, drive)
    x = comp(x, thr, ratio, att=0.004, rel=0.09)
    x = limit(norm(x, -0.8), push)
    x = trim(x, -62)
    return norm(fade(x, 0.0005, fo), -0.8)


def crackle(dur=0.25, density=300, decay_ms=90, seed=3):
    # искры: редкие короткие щелчки в верхах, гаснут
    rng = np.random.default_rng(seed)
    n = int(dur * SR); y = np.zeros(n)
    for t in rng.integers(0, n, int(density * dur)):
        k = int(rng.integers(20, 90))
        y[t:t + k] += rng.standard_normal(min(k, n - t)) * rng.uniform(0.3, 1.0)
    y = hp(y, 3500, 2) * env_decay(n, decay_ms)
    return y / (np.abs(y).max() + 1e-9)


def tube_pop(f=170, dur=0.25, seed=5):
    # «пумп» трубы гранатомёта: резонанс + низкочастотный шум
    n = int(dur * SR); t = np.arange(n) / SR
    y = np.sin(2 * np.pi * (f * (1 + 0.6 * np.exp(-t / 0.02))) * t) * env_decay(n, 55)
    y += 0.7 * noise_burst(dur, 90, 700, 40, seed)
    return y / np.abs(y).max()


R = {}   # имя -> функция сборки


def recipe(name):
    def d(f):
        R[name] = f
        return f
    return d


# ----------------------------- ВЫСТРЕЛЫ -----------------------------
# Основа — записи крупного калибра и сай-фай оружия с freesound.org (CC0, список в assets/incoming/freesound/_sources.json).
# Без эха: удар и короткое тело, дальше быстрое затухание.

REF = {}   # имя рецепта -> (id записи, время выстрела, длина) — показывается на странице как исходник


def fsf(i):
    return glob.glob(FS + f"{i}_*")[0]


def at(i, t, length, pre=0.003):
    # один выстрел из записи i: начало атаки рядом с секундой t
    x = L(fsf(i)); s = int(t * SR)
    a = max(0, s - int(0.01 * SR))
    e = env_db(x[a:s + int(0.03 * SR)], 0.001); pk = int(np.argmax(e)); st = pk
    while st > 0 and e[st] > e[pk] - 24:
        st -= 1
    st = max(0, a + st - int(pre * SR))
    return fade(x[st:st + int(length * SR)], 0.0005, min(0.03, length / 4))


def src(name, i, t, length):
    REF.setdefault(name, (i, t, length))
    return at(i, t, length)


def snap(dur=0.01, lo=2500, hi=14000, seed=0):
    # короткий щелчок-вспышка в самом начале
    return noise_burst(dur, lo, hi, 3, seed)


def emag(f0=6000, f1=700, dur=0.07, seed=0):
    # электромагнитный «вжик»: тон вниз + искры, очень коротко
    z = zap(f0, f1, dur, dur * 250, harm=(1, 0.6, 0.4, 0.3), fm=0.08)
    return mix((z, 0, 0), (crackle(dur, 900, dur * 350, seed), -4, 0))


def punch(layers, keep, decay, drive=2.0, thr=-15, push=9.0, target="sharp", hpf=30):
    # сборка: слои → баланс полос → короткий хвост → насыщение, компрессор, лимитер → снова короткий хвост
    # (после компрессора хвост поднимается — второй проход держит быстрое затухание)
    x = hp(mix(*layers), hpf, 2)
    if target:
        x = tilt_to(x, TARGETS[target])
    x = tail_shape(x, keep, decay)
    x = sat(norm(x, -3), drive)
    x = comp(x, thr, 3.0, att=0.003, rel=0.05)
    x = limit(norm(x, -0.8), push)
    x = trim(tail_shape(x, keep, decay), -60)
    return norm(fade(x, 0.0005, min(0.04, len(x) / SR / 4)), -0.8)


def boom_of(x, k=0.5, lpf=1400):
    # тот же выстрел, замедленный: даёт «бум» вместо хлопка
    return lp(speed(x, k), lpf, 2)


# --- автопушка (3,5 выстрела в секунду) ---

@recipe("shot_A")
def _():
    s = src("shot_A", 854186, 0.008, 0.26)   # 30-мм автопушка
    return punch([(speed(s, 0.92), 0, 0), (boom_of(s, 0.65, 1800), -3, 0), (thump(95, 42, 0.25, 15, 60), -7, 0),
                  (snap(0.008, 3000, 14000, 1), -14, 0)], 0.04, 55)


@recipe("shot_B")
def _():
    s = src("shot_B", 183656, 1.912, 0.3)    # пулемёт 12,7 мм (M2), одиночный
    clank = speed(whole(RW + "metal_hit_01.ogg"), 0.9)
    return punch([(speed(s, 0.9), 0, 0), (boom_of(s, 0.6, 1600), -2, 0), (thump(85, 40, 0.3, 18, 70), -7, 0), (clank, -18, 12)], 0.035, 60)


@recipe("shot_C")
def _():
    s = src("shot_C", 122103, 0.037, 0.11)   # ДШК, опущен ниже — крупнее калибр, как КПВТ
    s2 = at(239138, 0.128, 0.11)
    return punch([(speed(s, 0.82), 0, 0), (boom_of(s, 0.55, 1500), -2, 0), (hp(s2, 1200), -8, 0), (thump(75, 36, 0.3, 20, 85), -6, 0)], 0.04, 65)


@recipe("shot_D")
def _():
    s = src("shot_D", 183656, 0.059, 0.25)   # 12,7 мм + электромагнитный разгон + звон ствола
    return punch([(speed(s, 0.95), 0, 0), (boom_of(s, 0.6, 1600), -3, 0), (emag(6000, 700, 0.07, 2), -9, 0),
                  (ring([1180, 1730, 2590, 3410], 0.25, 45), -15, 4), (thump(90, 40, 0.25, 15, 60), -7, 0)], 0.03, 50)


# --- гатлинг (14 выстрелов в секунду, каждый звук короче 0,12 с) ---

@recipe("minigun_A")
def _():
    s = src("minigun_A", 160355, 0.820, 0.062)   # счетверённый 12,7 мм (Avenger), одиночный хлопок
    return punch([(s, 0, 0), (boom_of(s, 0.7, 2200), -4, 0), (thump(120, 60, 0.1, 8, 25), -9, 0)], 0.02, 25, push=8)


@recipe("minigun_B")
def _():
    s = src("minigun_B", 239138, 0.008, 0.1)     # 12,7 мм из очереди
    return punch([(speed(s, 1.05), 0, 0), (boom_of(s, 0.7, 2000), -4, 0), (thump(115, 58, 0.1, 8, 25), -9, 0)], 0.018, 28, push=8)


@recipe("minigun_C")
def _():
    p = src("minigun_C", 169775, 0.024, 0.05)    # импульсная винтовка + хлопок 12,7 — «энергопулемёт»
    return punch([(p, 0, 0), (hp(at(160355, 0.731, 0.05), 800), -6, 0), (thump(130, 60, 0.08, 6, 20), -9, 0)], 0.015, 25, push=8)


# --- тяжёлое орудие (0,7 выстрела в секунду) ---

@recipe("cannon_A")
def _():
    s = src("cannon_A", 239135, 0.024, 0.6)   # танковое орудие
    return punch([(speed(s, 0.9), 0, 0), (boom_of(s, 0.6, 1200), -2, 0), (thump(62, 30, 0.6, 35, 150), -5, 0),
                  (snap(0.01, 2500, 12000, 2), -12, 0)], 0.07, 140, thr=-17, target="heavy")


@recipe("cannon_B")
def _():
    s = src("cannon_B", 175430, 0.018, 0.65)   # гаубица + тяжёлый артвыстрел
    return punch([(s, 0, 0), (at(441373, 0.010, 0.45), -3, 0), (boom_of(s, 0.55, 1000), -3, 0), (thump(58, 28, 0.7, 40, 170), -5, 0)],
                 0.07, 150, thr=-17, target="heavy")


@recipe("cannon_C")
def _():
    s = src("cannon_C", 865990, 0.109, 0.5)    # Barrett 12,7 мм, опущен — как противотанковое ружьё
    return punch([(speed(s, 0.8), 0, 0), (boom_of(s, 0.5, 1200), -2, 0), (at(853281, 0.051, 0.5), -4, 0), (thump(66, 30, 0.5, 30, 130), -6, 0)],
                 0.05, 120, thr=-17, target="heavy")


@recipe("cannon_D")
def _():
    s = src("cannon_D", 127845, 0.011, 0.6)    # танковый выстрел + электромагнитный разряд и искры
    return punch([(s, 0, 0), (hp(at(183656, 4.950, 0.2), 600), -6, 0), (emag(5000, 400, 0.12, 3), -10, 0),
                  (crackle(0.3, 300, 90, 4), -16, 10), (thump(60, 28, 0.6, 35, 150), -5, 0)], 0.06, 130, thr=-17, target="heavy")


# --- дробовик (8 дробин разом) — у меха это залп картечью ---

@recipe("shotgun_A")
def _():
    s1 = src("shotgun_A", 183656, 0.059, 0.25)   # три выстрела 12,7 мм почти разом + шум картечи
    s2 = at(183656, 1.912, 0.25); s3 = at(183656, 4.950, 0.25)
    return punch([(s1, 0, 0), (s2, -2, 9), (s3, -3, 17), (boom_of(s1, 0.55, 1400), -3, 0),
                  (noise_burst(0.12, 300, 9000, 40, 5), -6, 0), (thump(80, 38, 0.35, 25, 90), -5, 0)], 0.05, 80)


@recipe("shotgun_B")
def _():
    s = src("shotgun_B", 441373, 0.010, 0.4)     # тяжёлый артвыстрел + зенитный залп
    return punch([(s, 0, 0), (at(701491, 0.114, 0.3), -3, 0), (boom_of(s, 0.6, 1300), -3, 0), (thump(78, 36, 0.35, 25, 95), -5, 0)], 0.05, 90)


# --- рельсотрон (заряд 1 с, выстрел раз в 2 с) ---

@recipe("rail_A")
def _():
    s = src("rail_A", 162260, 0.036, 0.8)     # запись испытаний рейлгана + разряд и искры
    return punch([(s, 0, 0), (emag(7000, 500, 0.1, 5), -10, 0), (crackle(0.35, 320, 110, 6), -15, 8), (thump(58, 28, 0.6, 35, 150), -6, 0)],
                 0.08, 150, thr=-17, target="heavy")


@recipe("rail_B")
def _():
    s = src("rail_B", 785380, 0.028, 0.8)
    return punch([(s, 0, 0), (snap(0.012, 3000, 15000, 7), -10, 0), (thump(62, 30, 0.6, 35, 140), -6, 0)], 0.08, 140, thr=-17, target=None)


@recipe("rail_C")
def _():
    s = src("rail_C", 699655, 0.224, 0.8)     # глухой сай-фай рейлган + щелчок 12,7 сверху
    return punch([(s, 0, 0), (hp(at(183656, 1.912, 0.15), 1200), -5, 0), (snap(0.012, 3000, 15000, 8), -10, 0),
                  (thump(60, 28, 0.6, 35, 140), -7, 0)], 0.07, 140, thr=-17, target=None)


@recipe("rail_D")
def _():
    s = src("rail_D", 155790, 0.196, 0.7)     # корабельный рейлган + сверхзвуковой щелчок
    return punch([(s, 0, 0), (hp(at(183656, 0.059, 0.15), 1000), -6, 0), (thump(60, 28, 0.6, 35, 140), -6, 0)], 0.07, 130, thr=-17, target="heavy")


@recipe("rail_E")
def _():
    s = src("rail_E", 183656, 4.950, 0.2)     # синтез: щелчок 12,7 + магнитный свист вниз + треск + звон
    return punch([(hp(s, 800), 0, 0), (zap(9000, 300, 0.35, 90, harm=(1, 0.5, 0.3, 0.2), fm=0.03), -6, 0),
                  (noise_burst(0.03, 1500, 14000, 8, 9), -6, 0), (crackle(0.3, 300, 100, 10), -14, 5),
                  (ring([2300, 3170, 4410], 0.4, 120), -14, 0), (thump(60, 28, 0.6, 35, 140), -5, 0)], 0.05, 120, thr=-17, target=None)


# --- бластер (3 выстрела в секунду) ---

def blaster(name, i, t, length=0.35, sub=-10, extra=(), keep=0.05, decay=70):
    s = src(name, i, t, length)
    return punch([(s, 0, 0), (thump(130, 55, 0.15, 12, 40), sub, 0), *extra], keep, decay, drive=1.7, target=None)


R["blaster_A"] = lambda: blaster("blaster_A", 466868, 0.023)
R["blaster_B"] = lambda: blaster("blaster_B", 702000, 0.017)
R["blaster_C"] = lambda: blaster("blaster_C", 475142, 0.018)
R["blaster_D"] = lambda: blaster("blaster_D", 569901, 0.027, 0.3, -14, ((at(584198, 0.024, 0.15), -4, 0),))
R["blaster_E"] = lambda: blaster("blaster_E", 861535, 0.954, 0.4)
R["blaster_F"] = lambda: blaster("blaster_F", 450768, 0.040)


# --- гранатомёт (звук запуска, взрыв — отдельно) ---

@recipe("grenade_A")
def _():
    fl = speed(whole(ML + "flaunch.wav"), 0.85)
    clank = speed(whole(RW + "metal_hit_01.ogg"), 0.7)
    return punch([(fl, 0, 0), (tube_pop(165, 0.25), -5, 0), (thump(95, 45, 0.3, 20, 85), -7, 0), (clank, -14, 30)], 0.1, 110, target="heavy")


@recipe("grenade_B")
def _():
    rl = whole(ML + "rlaunch.wav", 0, 0.8)
    return punch([(rl, 0, 0), (tube_pop(140, 0.3, 7), -6, 0), (thump(85, 40, 0.35, 25, 100), -7, 0)], 0.1, 120, target="heavy")


# ----------------------------- ПОПАДАНИЯ -----------------------------

@recipe("hit_A")
def _():
    m = speed(whole(BL + "dull_metal_collision_01_44k_32bit_stereo.wav", 0, 0.35), 0.85)
    x = mix((m, 0, 0), (thump(150, 75, 0.12, 10, 40), -9, 0), (noise_burst(0.012, 2500, 12000, 3, 21), -10, 0),
            (crackle(0.25, 320, 80, 22), -16, 5))
    return finish(x, 1.8, tail_keep=0.06, tail_ms=80, fo=0.04, hpf=60, target="armor", push=9.5)


@recipe("hit_B")
def _():
    m = whole(RW + "metal_hit_03.ogg", 0, 0.3)
    cl = speed(whole(I + "clink1_0.wav", 0, 0.3), 0.9)
    x = mix((m, 0, 0), (cl, -9, 0), (thump(140, 70, 0.12, 10, 38), -9, 0), (crackle(0.2, 300, 70, 23), -16, 4))
    return finish(x, 1.7, tail_keep=0.07, tail_ms=90, fo=0.04, hpf=60, target="armor")


@recipe("hit_C")
def _():
    m = speed(whole(RB + "bfh1_metal_hit_01.ogg"), 0.8)
    p = whole(KI + "impactPunch_heavy_000.ogg", 0, 0.2)
    pl = speed(whole(KI + "impactPlate_heavy_000.ogg", 0, 0.3), 1.2)
    x = mix((m, 0, 0), (p, -9, 0), (pl, -9, 0), (noise_burst(0.01, 3000, 12000, 3, 24), -10, 0))
    return finish(x, 1.8, tail_keep=0.06, tail_ms=85, fo=0.04, hpf=55, target="armor", push=9.5)


@recipe("wall_A")
def _():
    deb = whole(RB + "bfh1_rock_breaking_01.ogg", 0, 0.35)
    cr = whole(RB + "bfh1_hit_03.ogg", 0, 0.2)
    x = mix((cr, 0, 0), (deb, -4, 10), (thump(100, 50, 0.15, 12, 50), -10, 0))
    return finish(x, 1.6, tail_keep=0.06, tail_ms=90, fo=0.05, hpf=50, target="ground")


@recipe("wall_B")
def _():
    im = whole(OI + "impact_gun_1.ogg", 0, 0.5)
    deb = speed(whole(I + "cannon_hit_wall_0.ogg", 0, 0.4), 1.3)
    x = mix((im, 0, 0), (deb, -6, 0), (thump(95, 48, 0.15, 12, 45), -10, 0))
    return finish(x, 1.6, tail_keep=0.06, tail_ms=95, fo=0.05, hpf=50, target="ground")


# ----------------------------- ЛАЗЕР (гул по кругу) -----------------------------

def seamless(x, length, xf=0.12):
    # кусок length секунд, конец плавно перетекает в начало — играет по кругу без щелчка
    n = int(length * SR); f = int(xf * SR)
    seg = x[: n + f].copy()
    out = seg[:n].copy()
    k = np.linspace(0, 1, f)
    out[:f] = seg[:f] * np.sqrt(k) + seg[n:n + f] * np.sqrt(1 - k)
    return out


def hum(dur, f0=55, seed=0):
    n = int(dur * SR); t = np.arange(n) / SR
    rng = np.random.default_rng(seed)
    y = sum(a * np.sin(2 * np.pi * f0 * h * t * (1 + 0.003 * np.sin(2 * np.pi * 3 * t)) + rng.uniform(0, 6))
            for h, a in [(1, 1.0), (2, 0.5), (3, 0.35), (5, 0.2), (8, 0.08)])
    return y / np.abs(y).max()


def loop_finish(x, target):
    x = hp(x, 35, 2)
    x = tilt_to(x, TARGETS[target]) if target else x
    x = norm(x, -3)
    x = sat(x, 1.4)
    return norm(x, -1.5)


@recipe("laser_A")
def _():
    b = trim(L(LK + "Laser Beam 1.wav"), -40)
    mid = b[int(0.6 * SR): int(2.4 * SR)]
    body = seamless(mid, 1.5)
    return loop_finish(mix((body, 0, 0), (hum(1.5, 55, 1), -10, 0)), None)


@recipe("laser_B")
def _():
    b = trim(L(LK + "Laser Beam 5.wav"), -40)
    mid = b[int(1.5 * SR): int(3.5 * SR)]
    body = seamless(mid, 1.5)
    return loop_finish(mix((body, 0, 0), (hum(1.5, 48, 2), -9, 0)), None)


if __name__ == "__main__":
    out = sys.argv[1]
    only = sys.argv[2:]
    os.makedirs(out, exist_ok=True)
    for name, f in R.items():
        if only and name not in only:
            continue
        x = f()
        np.save(os.path.join(out, name + ".npy"), x)
        a = analyze(x)
        print(f"{name:12s} dur{a['dur']:5.2f} cen{a['centroid']:6.0f} " + " ".join(f"{k}{v:6.1f}" for k, v in a["bands"].items()))
