#!/usr/bin/env python3
"""《肉身聖典》音樂與環境音產生器（A3）。全部程序合成、原創，沒有第三方素材。

用法：python3 tools/music_synth/generate_music.py [輸出資料夾，預設 audio/music]
需求：python3 + numpy；輸出 .ogg 需要 ffmpeg（libvorbis）。沒有 ffmpeg 時輸出 .wav。
固定亂數種子：每次產生的結果相同。

設計（心理恐怖：美與殘酷的反差）
- 所有音樂分層（stem）同長、同速度（72 BPM，3/4 搖籃曲，16 小節 = 40 秒），同時播放並靠音量切換狀態。
- lullaby：原創 A 小調搖籃曲，八音盒音色，音準微偏 + 磁帶顫音（wow/flutter）；第 9 小節整小節靜默，
  第 14 小節有一個「錯的音」（D#）。美，但不對勁。
- lullaby_major：同旋律的 A 大調、無顫音版本（離院結局：灰色的天空）。
- pad：柔和的「啊」母音和聲。drone：低頻小二度拍頻 + 濾波噪音。breath：倒放式的人聲漸強與呼吸。
- heartbeat：每拍一次的心跳。perc：悶擊與金屬刮擦。
- hum：母親哼唱同一首搖籃曲（共振峰合成）；hum_broken：第二階段，音高下垂、走音、斷續。
- boss_low：更深的不協和低音群。death_sting：死亡時的一次性低鳴。
- tinnitus：自己的肢體被斷時的耳鳴；whispers：異化越高越常出現的低語（A4）。
- 環境音（30 秒循環）：ward、corridor、courtyard、library、sacristy、chapel。
所有濾波用 FFT（循環），因此每個循環的頭尾無縫。
"""
import os
import subprocess
import sys
import wave

import numpy as np

SR = 22050
BPM = 72.0
BEAT = 60.0 / BPM
BARS = 16
BEATS_PER_BAR = 3
LOOP = BARS * BEATS_PER_BAR * BEAT  # 40 秒
N = int(round(LOOP * SR))
RNG = np.random.default_rng(732)

# ---------------- 旋律（原創） ----------------
# (MIDI 音高 或 None=休止, 拍數)
MELODY = [
    [(76, 2), (74, 1)],
    [(72, 1), (71, 1), (69, 1)],
    [(71, 2), (64, 1)],
    [(69, 3)],
    [(72, 2), (74, 1)],
    [(76, 1), (77, 1), (76, 1)],
    [(74, 1.5), (72, 0.5), (71, 1)],
    [(64, 3)],
    [(None, 3)],                      # 靜默的一小節
    [(76, 2), (74, 1)],
    [(72, 1), (71, 1), (68, 1)],
    [(69, 3)],
    [(77, 2), (76, 1)],
    [(75, 2), (74, 1)],               # D# — 錯的音
    [(72, 1), (71, 1), (64, 1)],
    [(69, 2), (None, 1)],
]
# 每小節的和弦（MIDI 音高，pad 與低音用）
CHORDS = [
    [57, 60, 64], [57, 60, 64], [52, 56, 59], [57, 60, 64],
    [53, 57, 60], [48, 52, 55], [50, 53, 57], [52, 56, 59],
    None,         [57, 60, 64], [52, 56, 59], [57, 60, 64],
    [50, 53, 57], [51, 54, 57], [52, 56, 59], [57, 60, 64],
]
MAJOR_MAP = {72: 73, 77: 78, 65: 66, 60: 61, 53: 54, 48: 49, 75: 74}


def midi_hz(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def notes(melody=MELODY):
    """展開成 (開始秒, 長度秒, midi)。"""
    out = []
    t = 0.0
    for bar in melody:
        for m, beats in bar:
            if m is not None:
                out.append((t, beats * BEAT, m))
            t += beats * BEAT
    return out


def buf(extra=6.0):
    return np.zeros(N + int(extra * SR))


def fold(x):
    """把超過循環長度的尾巴加回開頭 → 無縫循環。"""
    y = x[:N].copy()
    tail = x[N:]
    i = 0
    while i < len(tail):
        k = min(N, len(tail) - i)
        y[:k] += tail[i:i + k]
        i += k
    return y


def t_axis(n):
    return np.arange(n) / SR


def add(dst, start_s, sig):
    i = int(start_s * SR)
    if i < 0:  # 從循環尾端開始（之後 fold 會接回開頭）
        i += N
    j = min(len(dst), i + len(sig))
    dst[i:j] += sig[:j - i]


def fft_filter(x, lo=None, hi=None, peaks=None):
    """循環 FFT 濾波。lo/hi：高通與低通截止（柔和斜率）。peaks：[(中心Hz, 寬度Hz, 增益)] 共振峰。"""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    g = np.ones_like(f)
    if hi is not None:
        g *= 1.0 / (1.0 + (f / hi) ** 4)
    if lo is not None:
        g *= 1.0 / (1.0 + (lo / np.maximum(f, 1e-3)) ** 4)
    if peaks:
        p = np.zeros_like(f)
        for c, w, gain in peaks:
            p += gain * np.exp(-0.5 * ((f - c) / w) ** 2)
        g *= p
    return np.fft.irfft(X * g, len(x))


def lfo(freq_cycles_per_loop, n=N, phase=0.0):
    """整數圈數的 LFO，循環無縫。"""
    return np.sin(2 * np.pi * freq_cycles_per_loop * np.arange(n) / N + phase)


def wow(x, depth_cents=14.0, flutter_cents=4.0):
    """磁帶顫音：以可變延遲重新取樣（循環）。"""
    n = len(x)
    i = np.arange(n, dtype=float)
    # 位移（樣本）＝ 頻率偏移的積分
    slow = 20  # 每循環 20 圈 ≈ 0.5 Hz
    fast = 240  # ≈ 6 Hz
    a_slow = (2 ** (depth_cents / 1200) - 1) * N / (2 * np.pi * slow)
    a_fast = (2 ** (flutter_cents / 1200) - 1) * N / (2 * np.pi * fast)
    disp = a_slow * np.sin(2 * np.pi * slow * i / N) + a_fast * np.sin(2 * np.pi * fast * i / N)
    pos = (i + disp) % n
    xp = np.concatenate([x, x[:1]])
    return np.interp(pos, np.arange(n + 1), xp)


def normalize(x, peak=0.8):
    m = np.max(np.abs(x))
    return x * (peak / m) if m > 0 else x


# ---------------- 音色 ----------------

def music_box_note(hz, dur, detune_cents=0.0):
    length = dur + 2.5
    t = t_axis(int(length * SR))
    hz = hz * 2 ** (detune_cents / 1200)
    # 八音盒：基音 + 不和諧泛音（簧片的 3.9、6.8 倍），快速衰減 + 敲擊雜音
    s = (np.sin(2 * np.pi * hz * t) * np.exp(-t * 2.2)
         + 0.35 * np.sin(2 * np.pi * hz * 3.93 * t) * np.exp(-t * 6.0)
         + 0.12 * np.sin(2 * np.pi * hz * 6.8 * t) * np.exp(-t * 11.0))
    click = RNG.standard_normal(len(t)) * np.exp(-t * 400) * 0.15
    attack = np.minimum(1.0, t / 0.002)
    return (s + click) * attack


def vowel_voice(hz, dur, formants, vibrato=5.0, vib_cents=18.0, attack=0.25, release=0.6,
                glide_cents=0.0, breath=0.05, partials=24):
    """共振峰合成的人聲（加法合成：每個泛音依共振峰包絡加權）。"""
    length = dur + release
    n = int(length * SR)
    t = t_axis(n)
    vib = vib_cents * np.sin(2 * np.pi * vibrato * t + RNG.uniform(0, 6.28)) * np.minimum(1, t / 0.6)
    glide = glide_cents * np.minimum(1.0, t / max(dur, 1e-3))
    f0 = hz * 2 ** ((vib + glide) / 1200)
    phase = 2 * np.pi * np.cumsum(f0) / SR
    s = np.zeros(n)
    for k in range(1, partials + 1):
        fk = hz * k
        if fk > SR / 2 - 500:
            break
        amp = sum(g * np.exp(-0.5 * ((fk - c) / w) ** 2) for c, w, g in formants) + 0.02 / k
        s += amp * np.sin(k * phase)
    env = np.minimum(1.0, t / attack) * np.clip((length - t) / release, 0, 1)
    noise = RNG.standard_normal(n) * breath
    return (s + noise) * env


AH = [(700, 130, 1.0), (1220, 160, 0.5), (2600, 250, 0.15)]
OO = [(320, 80, 1.0), (800, 120, 0.35), (2400, 250, 0.05)]
MM = [(260, 70, 1.0), (1000, 200, 0.08)]


# ---------------- 分層 ----------------

def stem_lullaby(major=False, wobble=True):
    x = buf()
    for start, dur, m in notes():
        if major:
            m = MAJOR_MAP.get(m, m)
        det = 0.0 if not wobble else RNG.normal(0, 7)
        add(x, start, 0.5 * music_box_note(midi_hz(m), dur, det))
        # 八音盒的低八度伴奏：每小節第一拍
    for bi, ch in enumerate(CHORDS):
        if ch is None:
            continue
        for k, m in enumerate(ch):
            if major:
                m = MAJOR_MAP.get(m, m)
            add(x, bi * 3 * BEAT + k * BEAT, 0.22 * music_box_note(midi_hz(m), BEAT, RNG.normal(0, 5) if wobble else 0))
    y = fold(x)
    if wobble:
        y = wow(y)
    y = fft_filter(y, lo=120, hi=5500)
    return normalize(y, 0.7)


def stem_pad():
    x = buf()
    for bi, ch in enumerate(CHORDS):
        if ch is None:
            continue
        for m in ch:
            add(x, bi * 3 * BEAT - 0.4, 0.3 * vowel_voice(midi_hz(m - 12), 3 * BEAT + 0.6, AH, vibrato=4.3,
                                                         vib_cents=8, attack=1.2, release=1.5, breath=0.01))
    y = fft_filter(fold(x), lo=80, hi=3000)
    return normalize(y, 0.6)


def stem_drone():
    t = t_axis(N)
    a, bb, e = 55.0, 58.27, 82.41
    # 頻率取最接近「整數圈數」的值 → 無縫
    def q(f):
        return round(f * LOOP) / LOOP
    s = (np.sin(2 * np.pi * q(a) * t) + 0.8 * np.sin(2 * np.pi * q(bb) * t)
         + 0.4 * np.sin(2 * np.pi * q(e) * t) + 0.25 * np.sin(2 * np.pi * q(a * 2) * t))
    s *= 0.7 + 0.3 * lfo(3)
    noise = fft_filter(RNG.standard_normal(N), peaks=[(180, 60, 1.0), (420, 90, 0.4)])
    noise = noise / np.max(np.abs(noise)) * (0.35 + 0.25 * lfo(5, phase=1.0))
    return normalize(s * 0.6 + noise, 0.65)


def stem_breath():
    x = buf()
    # 每兩小節一次：倒放式漸強（指數上升後突然截斷）
    for bi in range(0, BARS, 2):
        m = CHORDS[bi] or CHORDS[0]
        v = vowel_voice(midi_hz(m[1]), 2 * 3 * BEAT, OO, vibrato=3.0, vib_cents=25, attack=0.05,
                        release=0.05, breath=0.2)
        tt = t_axis(len(v))
        env = (tt / tt[-1]) ** 3
        add(x, bi * 3 * BEAT, 0.6 * v * env)
    y = fold(x)
    br = fft_filter(RNG.standard_normal(N), lo=300, hi=2500)
    br = br / np.max(np.abs(br)) * np.maximum(0, lfo(8)) ** 2 * 0.4  # 8 次呼吸 / 循環
    return normalize(fft_filter(y, lo=150, hi=4000) + br, 0.6)


def heartbeat_hit(strength=1.0):
    t = t_axis(int(0.25 * SR))
    f = 55 * np.exp(-t * 8) + 35
    ph = 2 * np.pi * np.cumsum(f) / SR
    return strength * np.sin(ph) * np.exp(-t * 22) * np.minimum(1, t / 0.004)


def stem_heartbeat():
    x = buf(1.0)
    for b in range(BARS * BEATS_PER_BAR):
        add(x, b * BEAT, heartbeat_hit(1.0))
        add(x, b * BEAT + 0.22, heartbeat_hit(0.6))
    y = fft_filter(fold(x), hi=400)
    return normalize(y, 0.85)


def metal(dur=1.6):
    t = t_axis(int(dur * SR))
    s = np.zeros_like(t)
    for r, d in [(1.0, 3), (2.76, 5), (5.4, 8), (8.93, 12)]:
        s += np.sin(2 * np.pi * 310 * r * t + RNG.uniform(0, 6)) * np.exp(-t * d) / r
    scrape = fft_filter(RNG.standard_normal(len(t)), lo=1500, hi=5000) * np.exp(-t * 6) * 0.3
    return s + scrape


def thud():
    t = t_axis(int(0.5 * SR))
    n = fft_filter(RNG.standard_normal(len(t)), hi=180) * 3
    f = 70 * np.exp(-t * 10) + 40
    return (n + np.sin(2 * np.pi * np.cumsum(f) / SR)) * np.exp(-t * 9)


def stem_perc():
    x = buf(2.0)
    for bar in range(BARS):
        add(x, bar * 3 * BEAT, 0.9 * thud())
        if bar % 2 == 1:
            add(x, bar * 3 * BEAT + 2 * BEAT, 0.35 * metal())
        if bar % 4 == 3:
            add(x, bar * 3 * BEAT + 1.5 * BEAT, 0.5 * thud())
    return normalize(fold(x), 0.8)


def stem_hum(broken=False):
    x = buf()
    for start, dur, m in notes():
        hz = midi_hz(m - 12)
        if broken:
            # 走音：每個音往下垂、偶爾落到小二度，第二層在三全音處低聲重疊，部分音被吞掉
            if RNG.random() < 0.18:
                continue
            glide = -RNG.uniform(60, 220)
            v = vowel_voice(hz * 2 ** (RNG.normal(0, 30) / 1200), dur, MM, vibrato=6.5, vib_cents=45,
                            attack=0.08, release=0.5, glide_cents=glide, breath=0.12)
            v2 = vowel_voice(hz * 2 ** (6 / 12), dur, OO, vibrato=7.3, vib_cents=60, attack=0.3,
                             release=0.4, glide_cents=glide * 1.5, breath=0.1)
            add(x, start, 0.5 * v)
            add(x, start, 0.18 * v2)
        else:
            v = vowel_voice(hz, dur, MM, vibrato=5.2, vib_cents=16, attack=0.12, release=0.5, breath=0.03)
            add(x, start, 0.5 * v)
    y = fold(x)
    y = wow(y, depth_cents=30 if broken else 10, flutter_cents=8 if broken else 3)
    return normalize(fft_filter(y, lo=90, hi=3500), 0.7)


def stem_boss_low():
    t = t_axis(N)
    def q(f):
        return round(f * LOOP) / LOOP
    s = np.zeros(N)
    for f, a in [(41.2, 1.0), (43.65, 0.8), (61.74, 0.5), (87.3, 0.35), (116.5, 0.2)]:
        # 類鋸齒（6 個泛音）
        for k in range(1, 7):
            s += a / k * np.sin(2 * np.pi * q(f) * k * t + k)
    s = fft_filter(s, hi=500)
    s *= 0.6 + 0.4 * np.maximum(0, lfo(16)) ** 2  # 每小節一次的沉重脈動
    return normalize(s, 0.7)


def death_sting():
    n = int(7.0 * SR)
    t = t_axis(n)
    s = np.zeros(n)
    for f in [55.0, 58.27, 77.78, 110.0 * 2 ** (1 / 12)]:
        s += np.sin(2 * np.pi * f * t * (1 - 0.01 * t))
    env = np.minimum(1, t / 2.5) * np.exp(-np.maximum(0, t - 2.5) * 0.9)
    v = vowel_voice(midi_hz(57), 3.0, OO, vibrato=3, vib_cents=30, attack=2.0, release=2.0,
                    glide_cents=-400, breath=0.15)
    out = s * env * 0.3
    out[:len(v)] += 0.4 * v
    return normalize(fft_filter(out, hi=2000), 0.7)


def tinnitus():
    """A4：自己的肢體被斷時的耳鳴（不循環）。"""
    n = int(5.0 * SR)
    t = t_axis(n)
    s = np.sin(2 * np.pi * 3700 * t) + 0.3 * np.sin(2 * np.pi * 3707 * t)
    env = np.minimum(1, t / 0.05) * np.exp(-t * 0.7)
    return normalize(s * env, 0.35)


VOWELS = [AH, OO, MM, [(400, 90, 1.0), (2000, 200, 0.4)], [(550, 100, 1.0), (1800, 200, 0.5)]]


def whisper(seed):
    """A4：異化低語。噪音通過隨機的母音共振峰，形成像說話的音節（聽不清楚的字）。"""
    r = np.random.default_rng(seed)
    n = int(3.0 * SR)
    x = np.zeros(n)
    t = 0.15
    while t < 2.6:
        syl = r.uniform(0.09, 0.22)
        m = int(syl * SR)
        v = VOWELS[r.integers(0, len(VOWELS))]
        noise = fft_filter(r.standard_normal(m), peaks=[(c * r.uniform(0.9, 1.1), w * 1.5, g) for c, w, g in v] + [(4500, 900, 0.25)])
        env = np.sin(np.pi * np.arange(m) / m) ** 1.5
        i = int(t * SR)
        x[i:i + m] += noise * env * r.uniform(0.5, 1.0)
        t += syl + r.uniform(0.0, 0.12)
    if seed % 2 == 1:
        x = x[::-1]  # 一半是倒放的低語
    return normalize(fft_filter(x, lo=300, hi=6000), 0.5)


# ---------------- 環境音（30 秒循環） ----------------
AMB_LEN = 30.0


def amb_noise(lo, hi, n):
    x = fft_filter(RNG.standard_normal(n), lo=lo, hi=hi)
    return x / np.max(np.abs(x))


def drips(n, count, base=1800.0):
    x = np.zeros(n + SR)
    for _ in range(count):
        i = RNG.integers(0, n)
        t = t_axis(int(0.15 * SR))
        f = base * RNG.uniform(0.8, 1.3) * (1 + 0.6 * np.exp(-t * 40))
        d = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 35) * RNG.uniform(0.3, 1.0)
        x[i:i + len(d)] += d
    y = x[:n].copy()
    y[:SR] += x[n:n + SR]
    return y


def lfo_n(cycles, n, phase=0.0):
    return np.sin(2 * np.pi * cycles * np.arange(n) / n + phase)


def amb(name):
    n = int(AMB_LEN * SR)
    t = t_axis(n)
    if name == "ward":  # 白色產房：日光燈嗡鳴、極遠的滴水、幾乎無聲
        hum = sum(np.sin(2 * np.pi * 60 * k * t) / k for k in range(1, 6)) * 0.05
        return normalize(hum + 0.04 * amb_noise(200, 4000, n) + 0.25 * drips(n, 6), 0.35)
    if name == "corridor":  # 縫合迴廊：低沉的風、偶爾的木頭吱嘎
        wind = amb_noise(60, 500, n) * (0.5 + 0.4 * lfo_n(3, n))
        creak = np.zeros(n + 2 * SR)
        for _ in range(4):
            i = RNG.integers(0, n)
            tt = t_axis(int(1.2 * SR))
            f = 180 + 120 * np.sin(2 * np.pi * 0.7 * tt)
            c = np.sign(np.sin(2 * np.pi * np.cumsum(f) / SR)) * np.sin(np.pi * tt / tt[-1]) * 0.12
            creak[i:i + len(c)] += c
        cr = creak[:n].copy()
        cr[:2 * SR] += creak[n:]
        return normalize(wind * 0.6 + fft_filter(cr, lo=150, hi=1500), 0.45)
    if name == "courtyard":  # 庭院：較亮的風、遠方鐘聲
        wind = amb_noise(150, 1800, n) * (0.4 + 0.4 * lfo_n(2, n, 1.0)) ** 2
        bell = np.zeros(n + 8 * SR)
        for start in (3.0, 18.0):
            tt = t_axis(int(7 * SR))
            b = sum(np.sin(2 * np.pi * 196 * r * tt) * np.exp(-tt * d) / (k + 1)
                    for k, (r, d) in enumerate([(0.5, 0.4), (1.0, 0.6), (1.19, 0.8), (1.5, 1.0), (2.0, 1.3), (2.74, 2.0)]))
            i = int(start * SR)
            bell[i:i + len(b)] += b * 0.2
        bl = bell[:n].copy()
        bl[:8 * SR] += bell[n:]
        return normalize(wind * 0.6 + fft_filter(bl, hi=2500), 0.45)
    if name == "library":  # 藏書室：時鐘滴答、紙頁窸窣、空氣
        x = 0.05 * amb_noise(100, 3000, n)
        for s in range(int(AMB_LEN)):
            tt = t_axis(int(0.04 * SR))
            tick = np.sin(2 * np.pi * (2400 if s % 2 else 2000) * tt) * np.exp(-tt * 200) * 0.12
            add_at = int(s * SR)
            x[add_at:add_at + len(tick)] += tick
        for _ in range(5):
            i = RNG.integers(0, n - SR)
            r = amb_noise(1500, 6000, SR) * np.sin(np.pi * np.arange(SR) / SR) ** 4 * 0.12
            x[i:i + SR] += r
        return normalize(x, 0.35)
    if name == "sacristy":  # 聖器室：滴水、鎖鏈輕響、低嗡
        hum = np.sin(2 * np.pi * round(48 * AMB_LEN) / AMB_LEN * t) * 0.08
        chain = np.zeros(n + SR)
        for _ in range(7):
            i = RNG.integers(0, n)
            tt = t_axis(int(0.3 * SR))
            c = sum(np.sin(2 * np.pi * f * tt) for f in RNG.uniform(2500, 5000, 3)) * np.exp(-tt * 25) * 0.08
            chain[i:i + len(c)] += c
        ch = chain[:n].copy()
        ch[:SR] += chain[n:]
        return normalize(hum + ch + 0.3 * drips(n, 10, 1400) + 0.04 * amb_noise(80, 1500, n), 0.4)
    if name == "chapel":  # 禮拜堂：遠方管風琴持續音、牆在呼吸
        def q(f):
            return round(f * AMB_LEN) / AMB_LEN
        organ = sum(np.sin(2 * np.pi * q(f) * t) * a for f, a in [(110, 0.5), (164.8, 0.35), (220, 0.25), (261.6, 0.15), (329.6, 0.1)])
        organ *= 0.5 + 0.3 * lfo_n(1, n)
        organ = fft_filter(organ, hi=900)
        breath = amb_noise(80, 700, n) * np.maximum(0, lfo_n(6, n)) ** 3  # 每 5 秒一次呼吸
        return normalize(organ * 0.5 + breath * 0.5, 0.45)
    raise ValueError(name)


# ---------------- 輸出 ----------------

def write(path_noext, x, use_ogg):
    pcm = np.clip(x, -1, 1)
    pcm16 = (pcm * 32767).astype(np.int16)
    wav_path = path_noext + ".wav"
    with wave.open(wav_path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm16.tobytes())
    if use_ogg:
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav_path, "-c:a", "libvorbis", "-q:a", "3",
                        path_noext + ".ogg"], check=True)
        os.remove(wav_path)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "..", "audio", "music")
    out = os.path.abspath(out)
    os.makedirs(os.path.join(out, "stems"), exist_ok=True)
    os.makedirs(os.path.join(out, "ambience"), exist_ok=True)
    os.makedirs(os.path.join(out, "stingers"), exist_ok=True)
    use_ogg = subprocess.run(["which", "ffmpeg"], capture_output=True).returncode == 0
    stems = {
        "lullaby": lambda: stem_lullaby(),
        "lullaby_major": lambda: stem_lullaby(major=True, wobble=False),
        "pad": stem_pad,
        "drone": stem_drone,
        "breath": stem_breath,
        "heartbeat": stem_heartbeat,
        "perc": stem_perc,
        "hum": lambda: stem_hum(False),
        "hum_broken": lambda: stem_hum(True),
        "boss_low": stem_boss_low,
    }
    for name, fn in stems.items():
        x = fn()
        assert len(x) == N, (name, len(x))
        write(os.path.join(out, "stems", name), x, use_ogg)
        print("stem", name)
    for name in ["ward", "corridor", "courtyard", "library", "sacristy", "chapel"]:
        write(os.path.join(out, "ambience", name), amb(name), use_ogg)
        print("ambience", name)
    write(os.path.join(out, "stingers", "death"), death_sting(), use_ogg)
    write(os.path.join(out, "stingers", "tinnitus"), tinnitus(), use_ogg)
    os.makedirs(os.path.join(out, "whispers"), exist_ok=True)
    for i in range(4):
        write(os.path.join(out, "whispers", "whisper_%d" % i), whisper(100 + i), use_ogg)
    print("stingers + whispers")


if __name__ == "__main__":
    main()
