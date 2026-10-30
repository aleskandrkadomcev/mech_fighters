# Набор для звуков: загрузка, анализ, спектрограммы, обработка, синтез слоёв.
import subprocess, wave, os
import numpy as np
from scipy import signal
from PIL import Image, ImageDraw, ImageFont

SR = 48000


def load(path, sr=SR):
    out = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(sr), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(out, dtype=np.float32).astype(np.float64)


def save_wav(path, x, sr=44100, src_sr=SR):
    if sr != src_sr:
        x = signal.resample_poly(x, sr, src_sr)
    x = np.clip(x, -1.0, 1.0)
    if os.path.dirname(path): os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
        w.writeframes((x * 32767).astype("<i2").tobytes())


def save_mp3(path, wav_path):
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", wav_path, "-b:a", "192k", path], check=True)


# ---------------- анализ ----------------

BANDS = [("sub", 20, 80), ("low", 80, 250), ("lowmid", 250, 1000), ("mid", 1000, 4000), ("high", 4000, 10000), ("air", 10000, 20000)]


def trim(x, db=-60.0):
    a = np.abs(x)
    thr = a.max() * 10 ** (db / 20)
    idx = np.where(a > thr)[0]
    if len(idx) == 0:
        return x
    return x[max(0, idx[0] - 48):idx[-1] + 1]


def env_db(x, win=0.005):
    n = max(1, int(win * SR))
    e = np.sqrt(np.convolve(x * x, np.ones(n) / n, mode="same") + 1e-12)
    return 20 * np.log10(e + 1e-12)


def analyze(x):
    x = trim(x)
    peak = np.abs(x).max() + 1e-12
    e = env_db(x)
    top = e.max()
    t_peak = int(np.argmax(e))
    above = np.where(e > top - 40)[0]
    dur = (above[-1] - above[0]) / SR if len(above) else 0.0
    above20 = np.where(e > top - 20)[0]
    body = (above20[-1] - above20[0]) / SR if len(above20) else 0.0
    f, P = signal.welch(x, SR, nperseg=4096)
    tot = P.sum() + 1e-20
    bands = {}
    for name, lo, hi in BANDS:
        m = (f >= lo) & (f < hi)
        bands[name] = 10 * np.log10(P[m].sum() / tot + 1e-12)
    cent = float((f * P).sum() / tot)
    rms = np.sqrt(np.mean(x[:int(0.3 * SR)] ** 2)) + 1e-12
    return {"dur": dur, "body": body, "attack_ms": t_peak / SR * 1000, "centroid": cent,
            "crest_db": 20 * np.log10(peak / rms), "bands": bands, "peak": peak}


def band_profile(x, n=48, fmin=30, fmax=16000):
    # средний спектр по логарифмическим полосам (для сравнения формы спектра), дБ, нормирован к максимуму
    f, P = signal.welch(trim(x), SR, nperseg=4096)
    edges = np.geomspace(fmin, fmax, n + 1)
    out = []
    for i in range(n):
        m = (f >= edges[i]) & (f < edges[i + 1])
        out.append(P[m].mean() if m.any() else 1e-20)
    out = 10 * np.log10(np.array(out) + 1e-20)
    return out - out.max(), np.sqrt(edges[:-1] * edges[1:])


def profile_distance(a, b):
    pa, _ = band_profile(a); pb, _ = band_profile(b)
    pa = np.maximum(pa, -60); pb = np.maximum(pb, -60)
    return float(np.sqrt(np.mean((pa - pb) ** 2)))


# ---------------- спектрограмма ----------------

def _lut():
    # тёмно-синий -> фиолетовый -> оранжевый -> жёлтый -> белый
    stops = [(0.0, (8, 8, 20)), (0.25, (60, 15, 100)), (0.5, (170, 40, 90)), (0.72, (240, 120, 30)), (0.9, (252, 220, 80)), (1.0, (255, 255, 230))]
    lut = np.zeros((256, 3), np.uint8)
    for i in range(256):
        t = i / 255
        for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
            if t0 <= t <= t1:
                k = (t - t0) / (t1 - t0)
                lut[i] = [int(c0[j] + (c1[j] - c0[j]) * k) for j in range(3)]
                break
    return lut


LUT = _lut()


def spectro_png(x, path, dur=1.5, w=600, h=200, fmin=30, fmax=20000, rng=80):
    x = trim(x)
    n = int(dur * SR)
    x = np.pad(x[:n], (0, max(0, n - len(x))))
    nfft, hop = 2048, max(1, n // w)
    f, t, Z = signal.stft(x, SR, nperseg=nfft, noverlap=nfft - hop, boundary=None, padded=False)
    S = 20 * np.log10(np.abs(Z) + 1e-9)
    S -= S.max()
    ys = np.geomspace(fmin, fmax, h)[::-1]
    cols = min(w, S.shape[1])
    img = np.zeros((h, w), np.float64) - rng
    idx = np.clip(np.searchsorted(f, ys), 0, len(f) - 1)
    img[:, :cols] = S[idx][:, :cols]
    v = np.clip((img + rng) / rng, 0, 1)
    rgb = LUT[(v * 255).astype(int)]
    # огибающая громкости сверху тонкой линией
    im = Image.fromarray(rgb, "RGB")
    d = ImageDraw.Draw(im)
    for fl in (100, 1000, 10000):
        y = int((np.log(fmax) - np.log(fl)) / (np.log(fmax) - np.log(fmin)) * h)
        d.line([(0, y), (6, y)], fill=(200, 200, 200))
        d.text((8, y - 6), {100: "100", 1000: "1k", 10000: "10k"}[fl], fill=(200, 200, 200))
    for ts in np.arange(0.25, dur, 0.25):
        xx = int(ts / dur * w)
        d.line([(xx, h - 5), (xx, h)], fill=(200, 200, 200))
    if os.path.dirname(path): os.makedirs(os.path.dirname(path), exist_ok=True)
    im.save(path)


def wave_png(x, path, dur=1.5, w=600, h=50):
    x = trim(x)
    n = int(dur * SR)
    x = np.pad(x[:n], (0, max(0, n - len(x))))
    step = n // w
    seg = np.abs(x[:step * w]).reshape(w, step).max(axis=1)
    im = Image.new("RGB", (w, h), (18, 18, 26))
    d = ImageDraw.Draw(im)
    for i, v in enumerate(seg):
        a = int(min(1.0, v) * (h / 2 - 1))
        d.line([(i, h // 2 - a), (i, h // 2 + a)], fill=(120, 190, 255))
    im.save(path)


# ---------------- обработка ----------------

def hp(x, fc, order=2):
    return signal.sosfilt(signal.butter(order, fc, "highpass", fs=SR, output="sos"), x)


def lp(x, fc, order=2):
    return signal.sosfilt(signal.butter(order, fc, "lowpass", fs=SR, output="sos"), x)


def bp(x, lo, hi, order=2):
    return signal.sosfilt(signal.butter(order, [lo, hi], "bandpass", fs=SR, output="sos"), x)


def peq(x, fc, gain_db, q=1.0):
    A = 10 ** (gain_db / 40); w0 = 2 * np.pi * fc / SR; al = np.sin(w0) / (2 * q)
    b = [1 + al * A, -2 * np.cos(w0), 1 - al * A]; a = [1 + al / A, -2 * np.cos(w0), 1 - al / A]
    return signal.lfilter(b, a, x)


def shelf(x, fc, gain_db, high=False):
    A = 10 ** (gain_db / 40); w0 = 2 * np.pi * fc / SR; al = np.sin(w0) / 2 * np.sqrt(2)
    c = np.cos(w0); sA = 2 * np.sqrt(A) * al
    if not high:
        b = [A * ((A + 1) - (A - 1) * c + sA), 2 * A * ((A - 1) - (A + 1) * c), A * ((A + 1) - (A - 1) * c - sA)]
        a = [(A + 1) + (A - 1) * c + sA, -2 * ((A - 1) + (A + 1) * c), (A + 1) + (A - 1) * c - sA]
    else:
        b = [A * ((A + 1) + (A - 1) * c + sA), -2 * A * ((A - 1) + (A + 1) * c), A * ((A + 1) + (A - 1) * c - sA)]
        a = [(A + 1) - (A - 1) * c + sA, 2 * ((A - 1) - (A + 1) * c), (A + 1) - (A - 1) * c - sA]
    return signal.lfilter(b, a, x)


def speed(x, k):
    # «варишпид»: k<1 — ниже и длиннее (тяжелее), k>1 — выше и короче
    if abs(k - 1) < 1e-4:
        return x.copy()
    from fractions import Fraction
    fr = Fraction(1 / k).limit_denominator(200)
    return signal.resample_poly(x, fr.numerator, fr.denominator)


def sat(x, drive=2.0):
    return np.tanh(x * drive) / np.tanh(drive)


def comp(x, thr_db=-18, ratio=4.0, att=0.002, rel=0.08, makeup=0.0):
    a_att = np.exp(-1 / (att * SR)); a_rel = np.exp(-1 / (rel * SR))
    lvl = np.abs(x)
    env = np.zeros_like(x); e = 0.0
    for i in range(len(x)):
        v = lvl[i]
        e = a_att * e + (1 - a_att) * v if v > e else a_rel * e + (1 - a_rel) * v
        env[i] = e
    edb = 20 * np.log10(env + 1e-9)
    gr = np.minimum(0, (thr_db - edb) * (1 - 1 / ratio))
    return x * 10 ** ((gr + makeup) / 20)


def fade(x, fin=0.001, fout=0.05):
    x = x.copy()
    a = int(fin * SR); b = int(fout * SR)
    if a > 0:
        x[:a] *= np.linspace(0, 1, a)
    if b > 0 and b < len(x):
        x[-b:] *= np.linspace(1, 0, b) ** 2
    return x


def cut(x, start=0.0, length=None):
    s = int(start * SR)
    return x[s:] if length is None else x[s:s + int(length * SR)]


def env_decay(n, t_ms):
    return np.exp(-np.arange(n) / (t_ms / 1000 * SR))


def tail_shape(x, keep=0.05, decay_ms=120):
    # оставить начало как есть, дальше гасить экспонентой: укоротить хвост
    k = int(keep * SR)
    g = np.ones(len(x))
    g[k:] = env_decay(len(x) - k, decay_ms)
    return x * g


def reverb(x, size=0.6, decay=0.35, mix=0.2, tone=4000, seed=1):
    rng = np.random.default_rng(seed)
    n = int(size * SR)
    ir = rng.standard_normal(n) * env_decay(n, decay * 1000 / 3)
    ir = lp(ir, tone)
    ir[: int(0.008 * SR)] *= np.linspace(0, 1, int(0.008 * SR))
    ir /= np.sqrt((ir ** 2).sum())
    dry = np.pad(x, (0, n))
    wet = pad_to(signal.fftconvolve(x, ir), len(dry))
    return dry + mix * wet * (np.abs(dry).max() / (np.abs(wet).max() + 1e-9))


def pad_to(x, n):
    return np.pad(x, (0, max(0, n - len(x))))[:n] if n else x


def mix(*layers):
    # layers: (сигнал, громкость_дБ, задержка_мс)
    n = max(len(s) + int(d / 1000 * SR) for s, g, d in layers)
    out = np.zeros(n)
    for s, g, d in layers:
        o = int(d / 1000 * SR)
        out[o:o + len(s)] += s / (np.abs(s).max() + 1e-12) * 10 ** (g / 20)
    return out


def norm(x, peak_db=-1.0):
    return x / (np.abs(x).max() + 1e-12) * 10 ** (peak_db / 20)


def loudness(x):
    # грубая громкость: RMS первых 300 мс после К-подобного фильтра, дБ
    y = hp(shelf(trim(x), 1500, 4, high=True), 60)
    seg = y[: int(0.3 * SR)]
    return 10 * np.log10(np.mean(seg ** 2) + 1e-12)


# ---------------- синтез слоёв ----------------

def thump(f0=60, f1=38, dur=0.35, drop_ms=60, decay_ms=110):
    # саб-удар: синус с быстрым падением высоты (как бочка), даёт «пинок» в грудь
    n = int(dur * SR); t = np.arange(n) / SR
    f = f1 + (f0 - f1) * np.exp(-t / (drop_ms / 1000))
    ph = 2 * np.pi * np.cumsum(f) / SR
    y = np.sin(ph) * env_decay(n, decay_ms)
    y[: int(0.002 * SR)] *= np.linspace(0, 1, int(0.002 * SR))
    return y


def noise_burst(dur=0.1, lo=200, hi=8000, decay_ms=30, seed=0, color=0.0):
    rng = np.random.default_rng(seed)
    n = int(dur * SR)
    y = rng.standard_normal(n)
    if color:
        y = np.cumsum(y); y -= np.convolve(y, np.ones(200) / 200, mode="same")
    y = bp(y, lo, min(hi, SR / 2 - 100))
    y *= env_decay(n, decay_ms)
    return y / (np.abs(y).max() + 1e-9)


def zap(f0=3000, f1=200, dur=0.25, decay_ms=80, harm=(1, 0.5, 0.33), fm=0.0, seed=0):
    # энергетический «пиу»: тон с падением высоты + гармоники + лёгкая модуляция
    n = int(dur * SR); t = np.arange(n) / SR
    f = f1 + (f0 - f1) * np.exp(-t / (dur / 4))
    if fm:
        f = f * (1 + fm * np.sin(2 * np.pi * 37 * t))
    ph = 2 * np.pi * np.cumsum(f) / SR
    y = sum(a * np.sin(ph * (i + 1)) for i, a in enumerate(harm))
    return y * env_decay(n, decay_ms)


def ring(freqs, dur=0.6, decay_ms=200, amps=None, seed=0):
    # металлический звон: набор неровных частот (не гармоник), как у листа брони
    n = int(dur * SR); t = np.arange(n) / SR
    rng = np.random.default_rng(seed)
    y = np.zeros(n)
    amps = amps or [1.0] * len(freqs)
    for f, a in zip(freqs, amps):
        y += a * np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * env_decay(n, decay_ms * (0.6 + 0.8 * rng.random()))
    return y / (np.abs(y).max() + 1e-9)


# ---------------- подгонка тембра под референс ----------------

def _oct_smooth(f, db, frac=3):
    out = np.empty_like(db)
    for i, fc in enumerate(f):
        if fc <= 0:
            out[i] = db[i]; continue
        m = (f >= fc * 2 ** (-0.5 / frac)) & (f <= fc * 2 ** (0.5 / frac))
        out[i] = 10 * np.log10(np.mean(10 ** (db[m] / 10)))
    return out


def match_curve(x, ref, fmin=250, max_db=9, strength=1.0):
    f, Px = signal.welch(trim(x), SR, nperseg=4096)
    _, Pr = signal.welch(trim(ref), SR, nperseg=4096)
    dx = _oct_smooth(f, 10 * np.log10(Px + 1e-20)); dr = _oct_smooth(f, 10 * np.log10(Pr + 1e-20))
    d = dr - dx
    m0 = (f >= fmin) & (f < fmin * 2)
    d = d - np.mean(d[m0])
    g = np.where(f < fmin, 0.0, np.clip(d * strength, -max_db, max_db))
    # плавный вход у fmin
    w = np.clip((np.log2(np.maximum(f, 1)) - np.log2(fmin * 0.7)) / np.log2(1 / 0.7), 0, 1)
    g = g * w
    g[f > 18000] = g[np.searchsorted(f, 18000)]
    return f, g


def match_eq(x, ref, fmin=250, max_db=9, strength=1.0):
    f, g = match_curve(x, ref, fmin, max_db, strength)
    taps = signal.firwin2(4095, f / (SR / 2), 10 ** (2 * g / 20))   # квадрат: minimum_phase берёт корень
    h = signal.minimum_phase(taps, method="homomorphic")
    return signal.fftconvolve(x, h)[: len(x)]


def hi_distance(a, b, fmin=250):
    # насколько тембр выше fmin отличается (дБ, среднее отклонение формы)
    f, Pa = signal.welch(trim(a), SR, nperseg=4096); _, Pb = signal.welch(trim(b), SR, nperseg=4096)
    da = _oct_smooth(f, 10 * np.log10(Pa + 1e-20)); db = _oct_smooth(f, 10 * np.log10(Pb + 1e-20))
    m = (f >= fmin) & (f <= 14000)
    d = (da - db)[m]
    return float(np.sqrt(np.mean((d - d.mean()) ** 2)))


TARGETS = {
    "gun":    {"sub": -5, "low": -4, "lowmid": -4, "mid": -6, "high": -11, "air": -18},
    "heavy":  {"sub": -3, "low": -3, "lowmid": -5, "mid": -8, "high": -14, "air": -22},
    "armor":  {"sub": -15, "low": -6, "lowmid": -4, "mid": -5, "high": -9, "air": -16},
    "ground": {"sub": -10, "low": -5, "lowmid": -4, "mid": -6, "high": -10, "air": -18},
}


def tilt_to(x, target, max_db=8, iters=2):
    # выровнять баланс полос к целевому (плавная кривая, минимальная фаза)
    centers = {"sub": 45, "low": 140, "lowmid": 500, "mid": 2000, "high": 6300, "air": 14000}
    for _ in range(iters):
        b = analyze(x)["bands"]
        diff = {k: target[k] - b[k] for k in target}
        mean = np.mean(list(diff.values()))
        pts = sorted((centers[k], np.clip(diff[k] - mean, -max_db, max_db)) for k in diff)
        f = np.linspace(0, SR / 2, 2049)
        lf = np.log(np.maximum(f, 20))
        g = np.interp(lf, [np.log(p[0]) for p in pts], [p[1] for p in pts])
        taps = signal.firwin2(4095, f / (SR / 2), 10 ** (2 * g / 20))
        h = signal.minimum_phase(taps, method="homomorphic")
        x = signal.fftconvolve(x, h)[: len(x)]
    return x


# ---------------- громкость на слух и лимитер ----------------

def _a_sos():
    f1, f2, f3, f4 = 20.598997, 107.65265, 737.86223, 12194.217
    z = [0, 0, 0, 0]
    p = [-2 * np.pi * f1] * 2 + [-2 * np.pi * f2, -2 * np.pi * f3] + [-2 * np.pi * f4] * 2
    k = (2 * np.pi * f4) ** 2 * 10 ** (1.9997 / 20)
    zd, pd, kd = signal.bilinear_zpk(z, p, k, SR)
    return signal.zpk2sos(zd, pd, kd)


A_SOS = _a_sos()


def loudness(x):
    # громкость «на слух»: А-фильтр (низ ухо слышит хуже), самые громкие 100 мс
    y = signal.sosfilt(A_SOS, trim(x))
    n = int(0.1 * SR)
    if len(y) <= n:
        return 10 * np.log10(np.mean(y ** 2) + 1e-12)
    c = np.convolve(y ** 2, np.ones(n) / n, mode="valid")
    return 10 * np.log10(c.max() + 1e-12)


def limit(x, push_db=6.0, ceil_db=-0.8, look_ms=2.0, rel_ms=20):
    # лимитер с заглядыванием вперёд: поднимает тело, пики не выше потолка
    x = x * 10 ** (push_db / 20)
    c = 10 ** (ceil_db / 20)
    la = int(look_ms / 1000 * SR)
    a = np.abs(x)
    from scipy.ndimage import maximum_filter1d
    pk = maximum_filter1d(a, size=2 * la + 1)
    g = np.minimum(1.0, c / (pk + 1e-12))
    r = np.exp(-1 / (rel_ms / 1000 * SR))
    out = np.empty_like(g); cur = 1.0
    for i in range(len(g)):
        cur = g[i] if g[i] < cur else r * cur + (1 - r) * g[i]
        out[i] = cur
    out = np.convolve(out, np.ones(la) / la, mode="same")
    y = x * np.minimum(out, g * 1.0 + (1 - g) * 0 + 1e9)
    return np.clip(y, -c, c)
