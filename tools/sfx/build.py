# Сборка новых звуков выстрелов и попаданий из слоёв (исходники — assets/incoming, см. CREDITS).
# Страница сравнения: python -P tools/sfx/make_page.py ПАПКА. Нужны numpy, scipy, Pillow, ffmpeg.
import sys, os, json
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

REF = {}   # имя рецепта -> референс, под который подгоняли тембр


def gun(layers, dense_keep, dense_ms, tail=(0.8, 0.6, 0.16, 2600), drive=1.8, thr=-16, fo=0.12, seed=1, ref=None, strength=1.0, target="gun", push=8.0):
    # layers: (сигнал, дБ, задержка мс). Плотная часть коротко, потом хвост эха потише.
    # ref: настоящая запись — тембр выше 250 Гц подгоняется под неё, низ остаётся свой
    x = mix(*layers)
    x = tail_shape(x, dense_keep, dense_ms)
    x = reverb(x, *tail, seed=seed)
    if ref is not None:
        x = match_eq(x, ref, 250, 9, strength)
    return finish(x, drive, thr=thr, fo=fo, target=target, push=push)


def ref_of(name, path, which=0, length=0.3, is_shot=True):
    REF[name] = (path, which, length, is_shot)
    return shot(path, which, length) if is_shot else whole(path, 0, length)


def boom_of(x, k=0.5, lpf=1400):
    # тот же выстрел, замедленный: даёт «бум» вместо хлопка
    return lp(speed(x, k), lpf, 2)


@recipe("shot_A")
def _():
    ak = shot(FA + "ak_47_single_near.ogg", 0, 0.12)
    crack = speed(ak, 0.85)
    body = boom_of(ak, 0.5, 1500)
    clank = speed(whole(RW + "metal_hit_01.ogg"), 0.8)
    return gun([(crack, 0, 0), (body, -2, 0), (thump(85, 45, 0.3, 25, 75), -9, 0), (clank, -15, 18)],
               0.07, 80, (0.9, 0.7, 0.2, 2600), 1.8, ref=ref_of("shot_A", FA + "ak_47_single_near.ogg"), push=10.5)


@recipe("shot_B")
def _():
    cg = shot(FA + "carl_gustav_m45_single_near.ogg", 0, 0.12)
    crack = speed(cg, 0.8)
    body = boom_of(shot(FA + "1917_single_near.ogg", 0, 0.12), 0.45, 1200)
    bar = speed(whole(MB + "cg1.wav", 0, 0.25), 0.8)
    return gun([(crack, 0, 0), (body, -1, 0), (bar, -6, 0), (thump(75, 40, 0.32, 30, 85), -9, 0)],
               0.08, 90, (0.9, 0.7, 0.2, 2400), 2.0, seed=2, ref=ref_of("shot_B", FA + "carl_gustav_m45_single_near.ogg"))


@recipe("minigun_A")
def _():
    pp = shot(FA + "ppsh_single_near.ogg", 0, 0.06)
    crack = speed(pp, 0.9)
    body = boom_of(pp, 0.6, 1800)
    return gun([(crack, 0, 0), (body, -3, 0), (thump(115, 62, 0.12, 10, 30), -11, 0)],
               0.035, 35, (0.4, 0.3, 0.14, 3000), 1.8, fo=0.04, seed=3, ref=ref_of("minigun_A", FA + "ppsh_single_near.ogg", 0, 0.2), push=10.5)


@recipe("minigun_B")
def _():
    ar = shot(FA + "ar_15_single_near.ogg", 0, 0.06)
    cg = speed(whole(MB + "cg1.wav", 0, 0.12), 1.0)
    return gun([(cg, 0, 0), (hp(ar, 1500), -7, 0), (boom_of(ar, 0.6, 1600), -4, 0), (thump(120, 65, 0.1, 10, 26), -12, 0)],
               0.03, 32, (0.4, 0.3, 0.12, 3000), 1.8, fo=0.04, seed=4, ref=ref_of("minigun_B", FA + "ar_15_single_near.ogg", 0, 0.2), push=10.5)


@recipe("cannon_A")
def _():
    s17 = shot(FA + "1917_single_near.ogg", 0, 0.15)
    crack = speed(s17, 0.75)
    body = boom_of(s17, 0.38, 900)
    boom = whole(I + "cannon_fire_0.ogg", 0, 0.6)
    ringm = speed(whole(KI + "impactPlate_heavy_000.ogg"), 0.7)
    return gun([(crack, 0, 0), (body, -1, 0), (boom, -3, 0), (thump(58, 30, 0.7, 45, 220), -8, 0), (ringm, -15, 8)],
               0.25, 260, (1.6, 1.3, 0.28, 2200), 1.9, thr=-18, fo=0.3, seed=5, ref=ref_of("cannon_A", FA + "1917_single_near.ogg", 0, 0.4), strength=0.8, target="heavy", push=10)


@recipe("cannon_B")
def _():
    tk = shot(FA + "tikka_single_near.ogg", 0, 0.15)
    mo = shot(FA + "mosin_nagant_single_near.ogg", 0, 0.15)
    crack = speed(mo, 0.7)
    body = boom_of(tk, 0.35, 800)
    return gun([(crack, 0, 0), (body, 0, 0), (boom_of(mo, 0.5, 1500), -4, 0), (thump(52, 28, 0.8, 50, 250), -7, 0),
                (noise_burst(0.02, 2500, 12000, 4), -12, 0)],
               0.22, 240, (1.6, 1.3, 0.3, 2000), 2.0, thr=-18, fo=0.3, seed=6, ref=ref_of("cannon_B", FA + "mosin_nagant_single_near.ogg", 0, 0.4), strength=0.8, target="heavy", push=10)


@recipe("blaster_A")
def _():
    las = whole(LK + "Laser Pistol 4.wav", 0, 0.5)
    return gun([(las, 0, 0), (thump(125, 55, 0.2, 18, 55), -9, 0), (zap(2600, 280, 0.2, 70), -14, 0),
                (noise_burst(0.015, 3000, 12000, 3), -14, 0)],
               0.14, 120, (0.6, 0.45, 0.16, 5000), 1.5, seed=7, target=None)


@recipe("blaster_B")
def _():
    las = whole(JC + "single_energy_shot_v1_01.ogg", 0, 0.5)
    return gun([(las, 0, 0), (thump(110, 50, 0.22, 20, 60), -9, 0), (noise_burst(0.012, 2500, 10000, 3), -14, 0)],
               0.14, 130, (0.6, 0.45, 0.14, 4500), 1.6, seed=8, target=None)


@recipe("shotgun_A")
def _():
    mb = shot(FA + "mossberg_single_near.ogg", 0, 0.14)
    m12 = shot(FA + "model_12_single_near.ogg", 0, 0.14)
    pump = speed(whole(RW + "metal_hit_03.ogg"), 0.75)
    return gun([(speed(mb, 0.8), 0, 0), (boom_of(m12, 0.45, 1300), -1, 0), (speed(whole(MB + "shotgun.wav", 0, 0.3), 0.85), -6, 0),
                (thump(78, 38, 0.45, 35, 130), -8, 0), (pump, -15, 330)],
               0.12, 150, (1.2, 0.9, 0.24, 2800), 2.0, thr=-17, fo=0.2, seed=9, ref=ref_of("shotgun_A", FA + "mossberg_single_near.ogg", 0, 0.4))


@recipe("shotgun_B")
def _():
    nv = shot(FA + "nova_single_near.ogg", 0, 0.14)
    sg = whole(MB + "shotgun.wav", 0, 0.4)
    return gun([(speed(nv, 0.75), 0, 0), (boom_of(nv, 0.42, 1200), -1, 0), (sg, -4, 0), (thump(70, 36, 0.45, 35, 140), -8, 0)],
               0.12, 150, (1.2, 0.9, 0.22, 2600), 2.2, thr=-17, fo=0.2, seed=10, ref=ref_of("shotgun_B", FA + "nova_single_near.ogg", 0, 0.4))


@recipe("rail_A")
def _():
    ar = shot(FA + "ar_15_single_near.ogg", 0, 0.12)
    las = whole(LK + "Laser Rifle 2.wav", 0, 0.9)
    sweep = zap(6000, 90, 0.6, 200, harm=(1, 0.4, 0.25, 0.15), fm=0.04)
    return gun([(hp(ar, 700), -2, 0), (boom_of(ar, 0.4, 1000), -3, 0), (las, -2, 0), (sweep, -12, 0),
                (thump(68, 30, 0.7, 40, 230), -8, 0), (crackle(0.5, 260, 150), -16, 15)],
               0.3, 260, (1.6, 1.2, 0.26, 4000), 1.7, thr=-18, fo=0.3, seed=11, ref=ref_of("rail_A", LK + "Laser Rifle 2.wav", 0, 0.9, False), strength=0.6, target="heavy")


@recipe("rail_B")
def _():
    dd = trim(L(I + "doomsday_laser_cannon_short.wav"), -50)
    e = env_db(dd, 0.003); pk = int(np.argmax(e))
    dis = fade(dd[max(0, pk - int(0.03 * SR)): pk + int(1.0 * SR)], 0.002, 0.2)
    s11 = shot(FA + "1911_single_near.ogg", 0, 0.12)
    return gun([(dis, 0, 0), (hp(s11, 900), -5, 25), (boom_of(s11, 0.4, 1000), -4, 25), (thump(60, 28, 0.8, 45, 250), -8, 25)],
               0.35, 280, (1.5, 1.1, 0.22, 3500), 1.6, thr=-18, fo=0.3, seed=12, target="heavy")


@recipe("grenade_A")
def _():
    fl = speed(whole(ML + "flaunch.wav"), 0.85)
    clank = speed(whole(RW + "metal_hit_01.ogg"), 0.7)
    return gun([(fl, 0, 0), (tube_pop(165, 0.25), -5, 0), (thump(95, 45, 0.3, 20, 85), -7, 0), (clank, -14, 30)],
               0.15, 150, (0.8, 0.6, 0.16, 2500), 1.7, seed=13, ref=ref_of("grenade_A", ML + "flaunch.wav", 0, 0.6, False), strength=0.7, target="heavy")


@recipe("grenade_B")
def _():
    rl = whole(ML + "rlaunch.wav", 0, 0.8)
    return gun([(rl, 0, 0), (tube_pop(140, 0.3, 7), -6, 0), (thump(85, 40, 0.35, 25, 100), -7, 0)],
               0.18, 170, (0.8, 0.6, 0.14, 2500), 1.8, seed=14, target="heavy")


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
