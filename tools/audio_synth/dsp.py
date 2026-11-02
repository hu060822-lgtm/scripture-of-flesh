"""肉身聖典 音效合成用的小型 DSP 函式庫（只依賴 numpy）。

所有函式都處理 float64 單聲道陣列，取樣率固定為 SR。
濾波一律在頻域做（零相位），時變濾波用 STFT 疊加，
這樣不需要 scipy，也不需要逐取樣的 Python 迴圈。
"""

from __future__ import annotations

import numpy as np

SR = 22050


# ---------------------------------------------------------------- 基本訊號

def n_samples(dur: float) -> int:
    return max(1, int(round(dur * SR)))


def time(dur: float) -> np.ndarray:
    return np.arange(n_samples(dur)) / SR


def white(dur: float, rng: np.random.Generator) -> np.ndarray:
    return rng.uniform(-1.0, 1.0, n_samples(dur))


def colored(dur: float, rng: np.random.Generator, slope: float) -> np.ndarray:
    """slope=0.5 為粉紅雜訊，1.0 為棕色雜訊。"""
    n = n_samples(dur)
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1.0 / SR)
    f[0] = f[1] if n > 1 else 1.0
    spec /= f ** slope
    x = np.fft.irfft(spec, n)
    return x / (np.max(np.abs(x)) + 1e-12)


def pink(dur, rng):
    return colored(dur, rng, 0.5)


def brown(dur, rng):
    return colored(dur, rng, 1.0)


def as_curve(v, n: int) -> np.ndarray:
    """常數、陣列或 [(t, value), ...] 斷點都轉成長度 n 的曲線。"""
    if isinstance(v, (int, float)):
        return np.full(n, float(v))
    if isinstance(v, np.ndarray):
        if len(v) == n:
            return v
        return np.interp(np.linspace(0, 1, n), np.linspace(0, 1, len(v)), v)
    pts = list(v)
    ts = np.array([p[0] for p in pts], dtype=float)
    vs = np.array([p[1] for p in pts], dtype=float)
    return np.interp(np.arange(n) / SR, ts, vs)


def phase_from_freq(freq: np.ndarray) -> np.ndarray:
    return 2.0 * np.pi * np.cumsum(freq) / SR


def osc(dur: float, freq, shape: str = "sine", phase0: float = 0.0) -> np.ndarray:
    n = n_samples(dur)
    ph = phase_from_freq(as_curve(freq, n)) + phase0
    if shape == "sine":
        return np.sin(ph)
    frac = (ph / (2 * np.pi)) % 1.0
    if shape == "saw":
        return 2.0 * frac - 1.0
    if shape == "square":
        return np.where(frac < 0.5, 1.0, -1.0)
    if shape == "tri":
        return 4.0 * np.abs(frac - 0.5) - 1.0
    raise ValueError(shape)


def glottal(dur: float, f0, rng: np.random.Generator, jitter: float = 0.01,
            shimmer: float = 0.1, open_q: float = 0.6) -> np.ndarray:
    """聲門脈衝列（Rosenberg 近似），帶抖動，給人聲共振峰濾波用。"""
    n = n_samples(dur)
    f = as_curve(f0, n)
    # 每週期的抖動用慢速隨機曲線近似
    wob = np.interp(np.arange(n), np.linspace(0, n, 64), rng.standard_normal(64))
    f = f * (1.0 + jitter * wob)
    frac = (np.cumsum(f) / SR) % 1.0
    rise = np.clip(frac / (open_q * 0.66), 0, 1)
    pulse = np.where(frac < open_q * 0.66, 0.5 * (1 - np.cos(np.pi * rise)),
                     np.where(frac < open_q,
                              np.cos(0.5 * np.pi * (frac - open_q * 0.66) / (open_q * 0.34)),
                              0.0))
    amp = 1.0 + shimmer * np.interp(np.arange(n), np.linspace(0, n, 48), rng.standard_normal(48))
    src = np.diff(pulse, prepend=0.0) * amp  # 微分後近似唇部輻射
    return src / (rms(src) + 1e-12)  # 以 RMS 正規化，方便和氣聲按比例混合


# ---------------------------------------------------------------- 包絡

def rms(x: np.ndarray) -> float:
    return float(np.sqrt(np.mean(x ** 2)))


def env_exp(dur: float, decay: float, attack: float = 0.001) -> np.ndarray:
    t = time(dur)
    a = np.clip(t / max(attack, 1e-5), 0, 1)
    return a * np.exp(-t / max(decay, 1e-5))


def env_points(dur: float, pts) -> np.ndarray:
    return as_curve(pts, n_samples(dur))


def fade(x: np.ndarray, fin: float = 0.002, fout: float = 0.01) -> np.ndarray:
    x = x.copy()
    a, b = min(len(x), n_samples(fin)), min(len(x), n_samples(fout))
    if a > 1:
        x[:a] *= np.linspace(0, 1, a)
    if b > 1:
        x[-b:] *= np.linspace(1, 0, b)
    return x


# ---------------------------------------------------------------- 濾波

def g_lowpass(f, fc, order=2):
    return 1.0 / np.sqrt(1.0 + (f / max(fc, 1.0)) ** (2 * order))


def g_highpass(f, fc, order=2):
    f = np.maximum(f, 1e-3)
    return 1.0 / np.sqrt(1.0 + (max(fc, 1.0) / f) ** (2 * order))


def g_peak(f, fc, bw):
    """共振峰：高斯形狀的頻帶增益。"""
    return np.exp(-0.5 * ((f - fc) / max(bw, 1.0)) ** 2)


def g_resonance(f, fc, bw):
    """二階共振的幅度響應（裙邊比高斯寬，人聲比較自然）。"""
    q = fc / max(bw, 1.0)
    f = np.maximum(f, 1.0)
    return 1.0 / np.sqrt(1.0 + (q * (f / fc - fc / f)) ** 2)


def g_bandpass(f, fc, q=2.0):
    bw = fc / max(q, 0.1)
    return g_peak(f, fc, bw * 0.6)


def fft_filter(x: np.ndarray, gain_fn) -> np.ndarray:
    n = len(x)
    pad = 1 << int(np.ceil(np.log2(n + 2048)))
    spec = np.fft.rfft(x, pad)
    f = np.fft.rfftfreq(pad, 1.0 / SR)
    return np.fft.irfft(spec * gain_fn(f), pad)[:n]


def lowpass(x, fc, order=2):
    return fft_filter(x, lambda f: g_lowpass(f, fc, order))


def highpass(x, fc, order=2):
    return fft_filter(x, lambda f: g_highpass(f, fc, order))


def bandpass(x, fc, q=2.0):
    return fft_filter(x, lambda f: g_bandpass(f, fc, q))


def stft_filter(x: np.ndarray, gain_fn, frame: int = 512) -> np.ndarray:
    """時變濾波：gain_fn(t_seconds, freqs) -> 增益陣列。"""
    hop = frame // 4
    n = len(x)
    pad = np.concatenate([np.zeros(frame), x, np.zeros(frame)])
    win = np.hanning(frame)
    out = np.zeros_like(pad)
    norm = np.zeros_like(pad)
    f = np.fft.rfftfreq(frame, 1.0 / SR)
    for start in range(0, len(pad) - frame, hop):
        seg = pad[start:start + frame] * win
        t = (start + frame / 2 - frame) / SR
        spec = np.fft.rfft(seg) * gain_fn(max(t, 0.0), f)
        out[start:start + frame] += np.fft.irfft(spec, frame) * win
        norm[start:start + frame] += win ** 2
    out /= np.maximum(norm, 1e-6)
    return out[frame:frame + n]


def sweep_bandpass(x, fc_pts, q=2.0):
    dur = len(x) / SR
    fc = env_points(dur, fc_pts) if not isinstance(fc_pts, (int, float)) else None

    def g(t, f):
        c = fc[min(len(fc) - 1, int(t * SR))] if fc is not None else fc_pts
        return g_bandpass(f, c, q)
    return stft_filter(x, g)


def sweep_lowpass(x, fc_pts, order=2):
    fc = env_points(len(x) / SR, fc_pts)

    def g(t, f):
        return g_lowpass(f, fc[min(len(fc) - 1, int(t * SR))], order)
    return stft_filter(x, g)


def formant_filter(x, vowel_pts, bw_scale=1.0):
    """vowel_pts: [(t, [(f1,bw1,amp1), (f2,...), ...]), ...]，在斷點之間線性插值。"""
    ts = np.array([p[0] for p in vowel_pts])
    tables = np.array([p[1] for p in vowel_pts], dtype=float)  # (k, nform, 3)

    def g(t, f):
        if t <= ts[0]:
            tab = tables[0]
        elif t >= ts[-1]:
            tab = tables[-1]
        else:
            i = int(np.searchsorted(ts, t)) - 1
            a = (t - ts[i]) / (ts[i + 1] - ts[i])
            tab = tables[i] * (1 - a) + tables[i + 1] * a
        out = np.full_like(f, 0.02)  # 共振峰之間的底，避免聽起來像幾支口哨
        for fc, bw, amp in tab:
            out += amp * g_resonance(f, fc, bw * bw_scale)
        return out
    return stft_filter(x, g, frame=1024)


# 母音共振峰（女聲，大致值）：(頻率, 頻寬, 振幅)
VOWELS = {
    "a": [(850, 90, 1.0), (1220, 110, 0.6), (2810, 170, 0.25)],
    "o": [(560, 80, 1.0), (920, 100, 0.5), (2830, 170, 0.15)],
    "u": [(370, 70, 1.0), (950, 100, 0.3), (2670, 160, 0.1)],
    "e": [(600, 80, 1.0), (2060, 130, 0.5), (2850, 170, 0.25)],
    "i": [(310, 60, 1.0), (2790, 150, 0.4), (3310, 200, 0.25)],
    "ae": [(870, 100, 1.0), (1700, 130, 0.5), (2600, 170, 0.2)],
}


# ---------------------------------------------------------------- 效果

def reverb(x: np.ndarray, rng: np.random.Generator, tail: float = 1.5,
           wet: float = 0.35, damp: float = 3500.0, predelay: float = 0.02) -> np.ndarray:
    """衰減雜訊脈衝響應做卷積，模擬石造空間。輸出會加長 tail 秒。"""
    ir_len = n_samples(tail)
    t = np.arange(ir_len) / SR
    ir = rng.standard_normal(ir_len) * np.exp(-6.9 * t / tail)
    ir = lowpass(ir, damp)
    ir = np.concatenate([np.zeros(n_samples(predelay)), ir])
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-12
    n = len(x) + len(ir)
    pad = 1 << int(np.ceil(np.log2(n)))
    y = np.fft.irfft(np.fft.rfft(x, pad) * np.fft.rfft(ir, pad), pad)[:n]
    dry = np.concatenate([x, np.zeros(len(ir))])
    return dry * (1 - wet) + y * wet * 1.5


def softclip(x: np.ndarray, drive: float = 1.0) -> np.ndarray:
    return np.tanh(x * drive) / np.tanh(drive)


def crush(x: np.ndarray, bits: int = 12, hold: int = 1) -> np.ndarray:
    """PS1 式低保真：降位元、可選降取樣（取樣保持）。"""
    if hold > 1:
        idx = (np.arange(len(x)) // hold) * hold
        x = x[idx]
    q = 2 ** (bits - 1)
    return np.round(x * q) / q


def mix(*layers) -> np.ndarray:
    """layers: (訊號, 起始秒, 增益)。"""
    end = max(n_samples(at) + len(sig) for sig, at, _ in layers)
    out = np.zeros(end)
    for sig, at, g in layers:
        s = n_samples(at) if at > 0 else 0
        out[s:s + len(sig)] += fade(sig, 0.0, 0.004) * g  # 尾端淡出，避免頻譜上的硬切邊
    return out


def trim_tail(x: np.ndarray, floor_db: float = -54.0, hold: float = 0.05) -> np.ndarray:
    """切掉殘響之後低於 floor_db（相對峰值）的尾巴，保留 hold 秒緩衝。"""
    thr = np.max(np.abs(x)) * 10 ** (floor_db / 20.0)
    idx = np.flatnonzero(np.abs(x) > thr)
    if len(idx) == 0:
        return x
    return x[:min(len(x), idx[-1] + n_samples(hold))]


def norm(x: np.ndarray, peak: float = 1.0) -> np.ndarray:
    return x * (peak / (np.max(np.abs(x)) + 1e-12))


def finish(x: np.ndarray, peak_db: float = -1.0, bits: int = 12, hold: int = 1,
           hp: float = 35.0) -> np.ndarray:
    x = highpass(x, hp, 2)
    x = norm(x, 1.0)
    x = trim_tail(x)
    x = crush(x, bits, hold)
    x = fade(x, 0.001, 0.015)
    return norm(x, 10 ** (peak_db / 20.0))


# ---------------------------------------------------------------- 常用素材

def impulse_burst(dur: float, rng, color: float = 3000.0, decay: float = 0.004) -> np.ndarray:
    """短促的雜訊爆裂（一次喀擦）。"""
    x = white(dur, rng) * env_exp(dur, decay, 0.0002)
    return norm(bandpass(x, color, 1.2))


def crackle(dur: float, rng, rate, color=(1500, 4000), click_len: float = 0.006,
            amp_jitter: float = 0.7) -> np.ndarray:
    """稀疏的喀擦串（軟骨、骨頭、撕裂）。rate 可為 [(t, 每秒次數)] 斷點。"""
    n = n_samples(dur)
    r = as_curve(rate, n)
    hits = rng.random(n) < (r / SR)
    out = np.zeros(n + n_samples(click_len) + 1)
    for i in np.flatnonzero(hits):
        c = impulse_burst(click_len, rng, rng.uniform(*color), click_len / rng.uniform(3, 6))
        a = 1.0 - amp_jitter * rng.random()
        out[i:i + len(c)] += c * a
    return norm(out[:n])


def squelch(dur: float, rng, center: float = 700.0, wobble: float = 0.6,
            bubbles: float = 18.0) -> np.ndarray:
    """濕黏的肉聲：低通雜訊經過游移的共振，振幅被隨機氣泡調變。"""
    n = n_samples(dur)
    base = pink(dur, rng)
    k = max(4, int(dur * bubbles))
    mod = np.interp(np.arange(n), np.linspace(0, n, k), rng.random(k)) ** 2
    pts = [(i * dur / 6, center * (1 + wobble * (rng.random() - 0.5) * 2)) for i in range(7)]
    fc = env_points(dur, pts)

    def g(t, f):
        c = fc[min(n - 1, int(t * SR))]
        return 0.4 * g_lowpass(f, c * 1.6, 2) + g_peak(f, c, c * 0.25) + 0.5 * g_peak(f, c * 2.3, c * 0.3)
    return norm(stft_filter(base * (0.3 + mod), g))


def thump(dur: float, f_start: float, f_end: float, decay: float, rng=None,
          click: float = 0.3) -> np.ndarray:
    """低頻撞擊：下滑的正弦加一點雜訊瞬態。"""
    t = time(dur)
    f = f_end + (f_start - f_end) * np.exp(-t / (decay * 0.4))
    body = np.sin(phase_from_freq(f)) * env_exp(dur, decay, 0.001)
    if rng is not None and click > 0:
        body += click * lowpass(white(dur, rng), 1200) * env_exp(dur, 0.008, 0.0002)
    return body


def partials(dur: float, freqs, decays, amps, rng=None, detune: float = 0.0) -> np.ndarray:
    """非諧和的金屬／鐘聲分音。"""
    t = time(dur)
    out = np.zeros(len(t))
    for f, d, a in zip(freqs, decays, amps):
        if rng is not None and detune:
            f *= 1 + detune * (rng.random() - 0.5)
        out += a * np.sin(2 * np.pi * f * t + (rng.random() * 6.28 if rng is not None else 0)) * np.exp(-t / d)
    return out


def whoosh(dur: float, rng, f_lo: float, f_hi: float, q: float = 1.5,
           peak_at: float = 0.45) -> np.ndarray:
    n = n_samples(dur)
    x = white(dur, rng) * 0.6 + pink(dur, rng) * 0.4
    fc = [(0, f_lo), (dur * peak_at, f_hi), (dur, f_lo * 0.8)]
    env = env_points(dur, [(0, 0), (dur * peak_at, 1), (dur, 0)]) ** 1.6
    return norm(sweep_bandpass(x, fc, q) * env[:n])


def stick_slip(dur: float, rng, rate, fc, q: float = 6.0, jitter: float = 0.3) -> np.ndarray:
    """摩擦聲（縫線拉扯、門軸吱嘎）：一串固定共振的微脈衝。rate=每秒脈衝數。"""
    n = n_samples(dur)
    r = as_curve(rate, n) * (1 + jitter * np.interp(np.arange(n), np.linspace(0, n, 40), rng.standard_normal(40)))
    r = np.maximum(r, 1.0)
    ph = np.cumsum(r / SR)
    pulses = np.diff(np.floor(ph), prepend=0.0)
    pulses *= 0.5 + rng.random(n)
    # 每個脈衝帶一小段摩擦雜訊，讓聲音是「吱嘎」而不是純音
    grain = np.convolve(pulses, np.exp(-np.arange(64) / 12.0), mode="same") * white(dur, rng)
    exc = pulses + 1.5 * grain + 0.02 * white(dur, rng)
    if isinstance(fc, (int, float)):
        return norm(bandpass(exc, fc, q))
    return norm(sweep_bandpass(exc, fc, q))


def pluck(dur: float, f0: float, rng, damp: float = 0.996, bright: float = 0.5) -> np.ndarray:
    """Karplus-Strong 撥弦（縫線、臍帶的彈響）。"""
    n = n_samples(dur)
    p = max(2, int(SR / f0))
    buf = rng.uniform(-1, 1, p)
    out = np.zeros(n)
    # 以週期為單位向量化：每圈做一次平均濾波
    i = 0
    while i < n:
        k = min(p, n - i)
        out[i:i + k] = buf[:k]
        buf = damp * (bright * buf + (1 - bright) * np.roll(buf, 1))
        i += p
    return norm(out)
