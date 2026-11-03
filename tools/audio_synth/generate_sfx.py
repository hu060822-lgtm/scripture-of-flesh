#!/usr/bin/env python3
"""肉身聖典 程序合成音效產生器（A2）。

全部原創：每個音效都由雜訊、振盪器、共振峰與濾波器組成，沒有取樣素材。
亂數種子由 cue 名稱與變體編號決定，所以重新執行會得到一樣的檔案。

執行（在 repo 根目錄）：
    python3 tools/audio_synth/generate_sfx.py            # 全部產生
    python3 tools/audio_synth/generate_sfx.py sever ui_*  # 只產生指定 cue（可用萬用字元）
    python3 tools/audio_synth/generate_sfx.py --preview build/sfx_preview.wav

需要：Python 3.9+ 與 numpy。
輸出：audio/sfx/<cue_id>/<cue_id>_<n>.wav（22050 Hz、單聲道、16 位元）。
"""

from __future__ import annotations

import argparse
import fnmatch
import os
import sys
import wave
import zlib

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dsp import *  # noqa: E402,F401,F403
import dsp  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "audio", "sfx")

CUES: dict = {}


def cue(variants: int = 3, desc: str = ""):
    def deco(fn):
        CUES[fn.__name__] = (fn, variants, desc)
        return fn
    return deco


def U(rng, a, b):
    return float(rng.uniform(a, b))


# ======================================================================== 戰鬥

@cue(3, "刀風：雜訊經過上揚再回落的帶通，鐘形包絡")
def attack_swing(rng, v):
    d = U(rng, 0.24, 0.34)
    x = whoosh(d, rng, U(rng, 250, 350), U(rng, 1300, 2000), q=1.8, peak_at=U(rng, 0.4, 0.55))
    x += 0.25 * whoosh(d, rng, 120, 500, q=1.0)  # 低沉的布料與手臂
    return finish(x, -2.0)


@cue(3, "切割命中：高頻瞬態＋2–5 kHz 刮切＋濕黏層＋低頻悶擊")
def hit_cut(rng, v):
    d = 0.35
    click = impulse_burst(0.01, rng, U(rng, 3500, 5000), 0.002)
    slice_ = bandpass(white(0.12, rng), U(rng, 2500, 4200), 1.5) * env_exp(0.12, 0.03)
    wet = squelch(0.25, rng, U(rng, 600, 900)) * env_exp(0.25, 0.07)
    body = thump(0.15, 140, 70, 0.05, rng)
    x = mix((click, 0, 0.8), (norm(slice_), 0.002, 0.8), (wet, 0.01, 0.7), (body, 0, 0.3))
    return finish(softclip(norm(x), 1.5)[:n_samples(d)], -1.0)


@cue(3, "鈍擊命中：下滑低頻正弦＋低通雜訊體感＋少量骨頭喀擦")
def hit_blunt(rng, v):
    body = thump(0.3, U(rng, 120, 150), U(rng, 50, 65), 0.09, rng, click=0.5)
    flesh = lowpass(white(0.2, rng), U(rng, 700, 1000)) * env_exp(0.2, 0.04)
    crk = crackle(0.08, rng, 120, (1500, 3500)) * 0.5
    x = mix((body, 0, 1.0), (flesh, 0, 0.7), (crk, 0.005, 0.5))
    return finish(softclip(norm(x), 2.0), -4.0)


@cue(3, "穿刺命中：極短瞬態＋快速下掃的帶通＋濕黏收尾")
def hit_pierce(rng, v):
    d = 0.3
    click = impulse_burst(0.008, rng, 5000, 0.0015)
    sh = sweep_bandpass(white(0.09, rng), [(0, U(rng, 4000, 5000)), (0.09, U(rng, 1000, 1400))], 2.5)
    sh *= env_exp(0.09, 0.035)
    wet = squelch(0.2, rng, U(rng, 450, 700), bubbles=30) * env_exp(0.2, 0.05)
    x = mix((click, 0, 0.9), (sh, 0.001, 0.8), (wet, 0.03, 0.7), (thump(0.1, 180, 90, 0.03), 0, 0.3))
    return finish(norm(x)[:n_samples(d)], -1.0)


@cue(3, "灼燒命中：高通嘶聲＋爆裂串＋低沉的嘶嘶底噪")
def hit_burn(rng, v):
    d = U(rng, 0.55, 0.7)
    hiss = highpass(white(d, rng), 3000) * env_points(d, [(0, 0), (0.02, 1), (d, 0)]) ** 1.5
    pops = crackle(d, rng, [(0, 120), (d, 10)], (2000, 6000), 0.004)
    low = lowpass(brown(d, rng), 400) * env_exp(d, 0.2)
    x = mix((hiss, 0, 0.5), (pops, 0, 0.9), (low, 0, 0.4), (impulse_burst(0.02, rng, 2500, 0.004), 0, 0.6))
    return finish(x, -2.0)


@cue(3, "打到盔甲：老舊鐵器的非諧和分音（悶、短）＋喀擦")
def hit_armor(rng, v):
    f = U(rng, 380, 520)
    ring = partials(0.5, [f, f * 2.32, f * 3.86, f * 5.41, f * 7.1], [0.12, 0.08, 0.05, 0.03, 0.02],
                    [1, 0.6, 0.45, 0.3, 0.2], rng, detune=0.03)
    ring = lowpass(ring, 3500)
    click = impulse_burst(0.015, rng, 3000, 0.003)
    body = thump(0.12, 160, 90, 0.03)
    return finish(mix((ring, 0, 0.6), (click, 0, 1.0), (body, 0, 0.5)), -2.0)


@cue(3, "格擋：明亮的金屬撞擊、較長餘響、短刮擦")
def block(rng, v):
    f = U(rng, 620, 820)
    ring = partials(0.9, [f, f * 2.76, f * 4.07, f * 5.4, f * 8.9], [0.35, 0.22, 0.14, 0.09, 0.05],
                    [1, 0.55, 0.5, 0.3, 0.15], rng, detune=0.02)
    click = impulse_burst(0.012, rng, 4500, 0.002)
    scrape = bandpass(white(0.18, rng), U(rng, 3000, 4500), 3) * env_exp(0.18, 0.06)
    x = mix((ring, 0, 0.55), (click, 0, 1.0), (scrape, 0.01, 0.3))
    return finish(dsp.reverb(x, rng, 0.6, 0.18, 4000), -2.0)


@cue(2, "破防：重金屬撞擊加骨裂與低頻轟聲，分音往下掉")
def guard_break(rng, v):
    d = 1.0
    t = time(d)
    f = U(rng, 300, 380) * (1 - 0.08 * (1 - np.exp(-t / 0.15)))
    ring = np.zeros(len(t))
    for k, (r, dec, a) in enumerate([(1, .4, 1), (2.4, .25, .6), (3.9, .15, .5), (6.2, .08, .3)]):
        ring += a * np.sin(phase_from_freq(f * r)) * np.exp(-t / dec)
    boom = thump(1.0, 90, 38, 0.35, rng, click=0.8)
    crk = crackle(0.12, rng, 220, (1200, 3500)) * 0.8
    x = mix((ring, 0, 0.5), (boom, 0, 1.0), (crk, 0.01, 0.7), (impulse_burst(0.02, rng, 2500, 0.005), 0, 1))
    return finish(dsp.reverb(softclip(norm(x), 2.2), rng, 0.9, 0.2, 2500), -0.5)


@cue(3, "閃避：布料揮動（低沉柔和的風聲）＋腳底摩擦")
def dodge(rng, v):
    d = U(rng, 0.3, 0.4)
    cloth = whoosh(d, rng, 180, U(rng, 600, 900), q=1.0, peak_at=0.35)
    scuff = lowpass(white(0.12, rng), 2500) * env_points(0.12, [(0, 0), (0.02, 1), (0.12, 0)])
    return finish(mix((cloth, 0, 1.0), (scuff, d * 0.55, 0.35)), -3.0)


@cue(3, "踉蹌：沉重的踏步悶擊＋骨頭吱嘎")
def stagger(rng, v):
    stomp = thump(0.3, 110, 50, 0.08, rng, click=0.6)
    creak = stick_slip(0.35, rng, [(0, 40), (0.35, 15)], U(rng, 500, 800), q=5) * env_points(0.35, [(0, 0), (0.05, 1), (0.35, 0)])
    x = mix((stomp, 0, 1.0), (creak, 0.05, 0.5), (thump(0.25, 90, 45, 0.07, rng), 0.18, 0.6))
    return finish(x, -2.0)


@cue(3, "揮空：細而輕的風聲")
def miss(rng, v):
    d = U(rng, 0.2, 0.28)
    return finish(whoosh(d, rng, U(rng, 500, 700), U(rng, 2500, 3400), q=2.5, peak_at=0.5), -4.0)


# ======================================================================== 解剖

@cue(3, "斷肢：濕肉撕裂（越來越密的軟骨喀擦）＋黏液＋最後的爆開與滴濺")
def sever(rng, v):
    d = U(rng, 0.75, 0.95)
    tear_end = d * 0.7
    gristle = crackle(tear_end, rng, [(0, 20), (tear_end * 0.8, 260), (tear_end, 60)], (900, 3200), 0.008)
    rip = sweep_bandpass(white(tear_end, rng), [(0, 600), (tear_end, 2200)], 1.2)
    rip *= env_points(tear_end, [(0, 0), (tear_end * 0.85, 1), (tear_end, 0.2)]) ** 2
    wet = squelch(d, rng, U(rng, 500, 750), wobble=0.8, bubbles=24) * env_points(d, [(0, 0.2), (tear_end, 1), (d, 0)])
    pop = thump(0.2, 220, 70, 0.04, rng, click=1.0)
    drips = crackle(d - tear_end, rng, [(0, 40), (d - tear_end, 3)], (400, 1200), 0.02) * 0.6
    x = mix((gristle, 0, 0.8), (rip, 0, 0.5), (wet, 0, 0.9), (pop, tear_end, 1.0), (drips, tear_end + 0.04, 1.0))
    return finish(softclip(norm(x), 1.6), -0.5)


@cue(3, "骨頭碎裂：30 ms 內 2–3 簇寬頻喀擦，1.5–3 kHz 共振，加低頻悶擊")
def bone_snap(rng, v):
    layers = [(thump(0.18, 160, 70, 0.04, rng, click=0.3), 0, 0.35)]
    t0 = 0.0
    for k in range(rng.integers(2, 4)):
        c = impulse_burst(0.03, rng, U(rng, 1500, 3200), U(rng, 0.003, 0.007))
        c += 0.5 * impulse_burst(0.03, rng, U(rng, 600, 1000), 0.006)
        layers.append((c, t0, 1.0 - 0.25 * k))
        t0 += U(rng, 0.006, 0.014)
    layers.append((crackle(0.06, rng, 300, (2000, 4500), 0.003) * 0.5, 0.01, 1))
    return finish(softclip(norm(mix(*layers)), 2.5), -0.5)


@cue(3, "部位失效：較沉的骨裂，接著斷續的吱嘎聲（肢體失去控制）")
def part_disabled(rng, v):
    d = 0.9
    crack = impulse_burst(0.05, rng, U(rng, 900, 1500), 0.01) + 0.6 * impulse_burst(0.05, rng, 2500, 0.005)
    body = thump(0.3, 120, 55, 0.08, rng)
    creak = stick_slip(0.6, rng, [(0, 35), (0.6, 8)], [(0, 700), (0.6, 420)], q=6, jitter=0.6)
    creak *= env_points(0.6, [(0, 0), (0.05, 1), (0.6, 0)])
    x = mix((crack, 0, 1.0), (body, 0, 0.8), (creak, 0.12, 0.45))
    return finish(x[:n_samples(d)], -1.0)


@cue(2, "致命部位失效：沉重心跳一擊，接著往下沉的音高和悶住的耳鳴")
def vital_fail(rng, v):
    d = 1.6
    beat = thump(0.25, 70, 42, 0.07) + 0.6 * thump(0.25, 60, 38, 0.06)
    beat = mix((beat, 0, 1.0), (thump(0.25, 65, 40, 0.06), 0.22, 0.7))
    sink = osc(d, [(0, 220), (d, 45)], "sine") * env_points(d, [(0, 0), (0.15, 0.7), (d, 0)])
    sink += 0.3 * osc(d, [(0, 224), (d, 44)], "sine") * env_points(d, [(0, 0), (0.15, 0.7), (d, 0)])
    ring = osc(d, U(rng, 5200, 6400)) * env_points(d, [(0, 0), (0.3, 0.12), (d, 0)])
    x = mix((beat, 0, 1.0), (lowpass(sink, 600), 0.05, 0.5), (ring, 0, 1.0))
    return finish(x, -1.0)


@cue(3, "敵人死亡：濕黏崩倒——身體重擊、黏液、帶共振峰的最後吐氣")
def death_enemy(rng, v):
    d = U(rng, 1.1, 1.4)
    fall = thump(0.4, 100, 40, 0.12, rng, click=0.8)
    fall2 = thump(0.3, 80, 38, 0.08, rng, click=0.5)
    wet = squelch(0.7, rng, U(rng, 400, 650), bubbles=14) * env_exp(0.7, 0.25)
    breath = formant_filter(pink(0.9, rng), [(0, VOWELS["a"]), (0.9, VOWELS["u"])])
    breath *= env_points(0.9, [(0, 0), (0.1, 1), (0.9, 0)])
    x = mix((breath, 0, 0.6), (fall, 0.25, 1.0), (wet, 0.3, 0.7), (fall2, 0.45, 0.6))
    return finish(dsp.reverb(x[:n_samples(d)], rng, 0.8, 0.2, 2000), -1.0)


@cue(2, "玩家死亡：兩下越來越慢的心跳、下沉的低音、尖銳耳鳴漸弱")
def death_player(rng, v):
    d = 3.0
    beats = mix((thump(0.3, 70, 40, 0.08), 0, 1.0), (thump(0.3, 62, 38, 0.07), 0.22, 0.7),
                (thump(0.3, 60, 36, 0.09), 1.1, 0.8), (thump(0.3, 55, 34, 0.07), 1.35, 0.5))
    drone = osc(d, [(0, 110), (d, 36)], "saw") + osc(d, [(0, 111.5), (d, 35)], "saw")
    drone = lowpass(drone, 500, 3) * env_points(d, [(0, 0), (0.4, 0.5), (2.2, 0.35), (d, 0)])
    ring = osc(d, U(rng, 6500, 7200)) * env_points(d, [(0, 0), (0.6, 0.15), (d, 0)])
    x = mix((beats, 0, 1.0), (drone, 0, 0.5), (ring, 0, 1.0))
    return finish(dsp.reverb(x, rng, 1.6, 0.3, 1800)[:n_samples(d + 0.8)], -1.0)


@cue(4, "石地腳步：短促喀擦＋低頻悶擊＋細砂摩擦")
def footstep(rng, v):
    heel = thump(0.08, U(rng, 140, 180), 80, 0.02, rng, click=0.7)
    click = impulse_burst(0.02, rng, U(rng, 1800, 3000), 0.003)
    grit = bandpass(white(0.06, rng), U(rng, 3000, 5000), 1.5) * env_exp(0.06, 0.015)
    x = mix((heel, 0, 1.0), (click, 0.002, 0.8), (norm(grit), U(rng, 0.02, 0.04), 0.35))
    return finish(dsp.reverb(x, rng, 0.35, 0.12, 3000), -2.0)


# ======================================================================== 縫合與移植

@cue(3, "開始縫合：針尖刺入的細小喀擦，接著縫線穿過皮肉的摩擦吱聲（音高上揚）")
def suture_start(rng, v):
    d = 0.6
    pierce = mix((impulse_burst(0.01, rng, 5000, 0.0015), 0, 1.0), (squelch(0.08, rng, 900) * env_exp(0.08, 0.02), 0, 0.5))
    pull = stick_slip(0.45, rng, [(0, 50), (0.45, 140)], [(0, 1100), (0.45, 1900)], q=3, jitter=0.4)
    pull *= env_points(0.45, [(0, 0), (0.05, 1), (0.38, 1), (0.45, 0)])
    return finish(mix((norm(pierce), 0, 0.7), (pull, 0.1, 0.8))[:n_samples(d)], -2.0)


@cue(3, "縫線斷裂：高而短的撥弦彈響＋小小的濕黏聲")
def suture_break(rng, v):
    tw = pluck(0.4, U(rng, 900, 1300), rng, 0.993, 0.6) * env_exp(0.4, 0.12)
    snap = impulse_burst(0.01, rng, 4500, 0.0015)
    wet = squelch(0.15, rng, 800) * env_exp(0.15, 0.04)
    return finish(mix((snap, 0, 0.6), (norm(tw), 0, 1.0), (wet, 0.01, 0.4)), -2.0)


@cue(3, "縫合完成：最後一拉收緊，接一聲輕柔的八音盒叮聲（美與醜的反差）")
def stitch_done(rng, v):
    pull = stick_slip(0.25, rng, [(0, 80), (0.25, 160)], 1500, q=7) * env_points(0.25, [(0, 0), (0.03, 1), (0.25, 0)])
    note = [1046.5, 1174.7, 1318.5][v % 3]
    ding = partials(1.2, [note, note * 2.0, note * 4.95], [0.5, 0.25, 0.08], [1, 0.25, 0.12], rng, 0.003)
    return finish(dsp.reverb(mix((pull, 0, 0.6), (ding, 0.22, 0.6)), rng, 1.0, 0.25, 5000), -3.0)


@cue(2, "移植：長的濕黏塞入聲、一下心跳、低頻湧起")
def transplant(rng, v):
    d = 1.6
    wet = squelch(1.1, rng, U(rng, 380, 520), wobble=0.9, bubbles=16) * env_points(1.1, [(0, 0), (0.3, 1), (1.1, 0)])
    beat = mix((thump(0.3, 75, 42, 0.08), 0, 1.0), (thump(0.3, 68, 40, 0.07), 0.2, 0.7))
    swell = lowpass(osc(d, [(0, 55), (d, 62)], "saw") + osc(d, [(0, 82.4), (d, 92)], "saw"), 300, 3)
    swell *= env_points(d, [(0, 0), (1.0, 0.6), (d, 0)])
    return finish(dsp.reverb(mix((wet, 0, 0.9), (beat, 0.9, 1.0), (swell, 0, 0.5)), rng, 1.0, 0.2, 2000), -1.0)


@cue(2, "排斥：濕黏的抽搐、刺耳的三全音和弦、喀擦")
def transplant_reject(rng, v):
    d = 1.4
    wet = squelch(0.8, rng, 600, wobble=1.0, bubbles=35) * env_exp(0.8, 0.3)
    f = U(rng, 140, 170)
    chord = sum(osc(d, [(0, f * r), (d, f * r * 0.94)], "saw") for r in (1.0, 1.414, 1.02, 2.83))
    chord = lowpass(chord, 1800) * env_points(d, [(0, 0), (0.05, 0.6), (0.6, 0.4), (d, 0)])
    crk = crackle(0.5, rng, [(0, 150), (0.5, 20)], (1000, 3000))
    return finish(softclip(norm(mix((wet, 0, 0.8), (chord, 0, 0.45), (crk, 0.03, 0.5))), 1.8), -3.5)


@cue(1, "祭壇休息：小調的八音盒琶音（輕微走音）＋溫暖低音漸弱")
def altar_rest(rng, v):
    d = 3.2
    notes = [440.0, 523.25, 659.25, 880.0, 783.99]  # A 小調：A C E A G
    layers = []
    for i, fn in enumerate(notes):
        fn *= 1 + 0.004 * (rng.random() - 0.5)
        layers.append((partials(2.0, [fn, fn * 2.0, fn * 4.95], [0.7, 0.3, 0.1], [1, 0.25, 0.1], rng), i * 0.28, 0.45))
    drone = lowpass(osc(d, 110, "saw") + osc(d, 110.6, "saw"), 350, 3) * env_points(d, [(0, 0), (0.8, 0.4), (d, 0)])
    layers.append((drone, 0, 0.5))
    return finish(dsp.reverb(mix(*layers), rng, 1.8, 0.35, 4000), -3.0)


@cue(3, "撿起物品：骨頭喀啦輕響＋小鈴聲")
def pickup(rng, v):
    rattle = mix(*[(impulse_burst(0.03, rng, U(rng, 1500, 3000), 0.004), k * U(rng, 0.03, 0.05), 1 - 0.2 * k)
                   for k in range(3)])
    fn = [1568.0, 1760.0, 1396.9][v % 3]
    bell = partials(0.6, [fn, fn * 2.76], [0.25, 0.1], [1, 0.3], rng)
    return finish(mix((rattle, 0, 0.8), (bell, 0.08, 0.35)), -3.0)


@cue(1, "大門開啟：低沉的石磨隆隆聲、門軸的吱嘎、最後一聲重響")
def gate_open(rng, v):
    d = 2.8
    grind = lowpass(brown(d, rng), 600) * (0.6 + 0.4 * np.abs(lowpass(white(d, rng), 8)) * 20)
    grind *= env_points(d, [(0, 0), (0.3, 1), (2.2, 0.8), (2.4, 0)])
    creak = stick_slip(2.0, rng, [(0, 25), (1.0, 60), (2.0, 20)], [(0, 380), (1.2, 620), (2.0, 450)], q=4, jitter=0.5)
    creak *= env_points(2.0, [(0, 0), (0.2, 1), (1.8, 0.8), (2.0, 0)])
    clunk = thump(0.6, 80, 35, 0.2, rng, click=1.0)
    x = mix((norm(grind), 0, 0.6), (creak, 0.2, 0.6), (clunk, 2.35, 1.0))
    return finish(dsp.reverb(x, rng, 1.6, 0.3, 2000), -1.0)


# ======================================================================== Boss：行走的母親

def _voice(d, f0_pts, vowel_pts, rng, vib_rate=5.5, vib_depth=0.02, breath=0.25, jitter=0.02):
    n = n_samples(d)
    f0 = env_points(d, f0_pts)
    vib = 1 + vib_depth * np.sin(2 * np.pi * vib_rate * time(d) + rng.random() * 6)
    src = glottal(d, f0 * vib, rng, jitter=jitter, shimmer=0.15)
    src = src + breath * 3.0 * highpass(white(d, rng), 1500)
    return formant_filter(src, vowel_pts)[:n]


@cue(2, "產聲：共振峰合成的女性哭嚎，音高上揚、母音 a→o→u，低八度的分身略走音【暫代】")
def boss_birth_cry(rng, v):
    d = 2.8
    f0 = [(0, 260), (0.4, 420), (1.4, 520), (2.2, 470), (d, 300)]
    vow = [(0, VOWELS["ae"]), (0.8, VOWELS["a"]), (1.8, VOWELS["o"]), (d, VOWELS["u"])]
    main = _voice(d, f0, vow, rng, vib_rate=6.2, vib_depth=0.025, jitter=0.03)
    low = _voice(d, [(t, f * 0.5 * 1.013) for t, f in f0], vow, rng, vib_rate=4.1, vib_depth=0.03, breath=0.4)
    rough = _voice(d, [(t, f * 1.5) for t, f in f0], vow, rng, breath=0.1) * 0.2  # 不和諧的五度泛音
    env = env_points(d, [(0, 0), (0.15, 0.8), (1.5, 1.0), (2.4, 0.7), (d, 0)])
    x = (main * 1.0 + low * 0.55 + rough) * env
    return finish(dsp.reverb(x, rng, 2.2, 0.45, 3000, 0.04), -1.0)


@cue(1, "跪伏：巨大的重擊、骨頭吱嘎、濕黏的落定")
def boss_kneel(rng, v):
    d = 2.0
    creak = stick_slip(0.7, rng, [(0, 20), (0.7, 70)], [(0, 300), (0.7, 520)], q=6, jitter=0.5)
    creak *= env_points(0.7, [(0, 0), (0.1, 1), (0.7, 0.6)])
    boom = thump(1.2, 70, 28, 0.4, rng, click=1.0)
    crk = crackle(0.2, rng, 200, (800, 2500))
    wet = squelch(0.9, rng, 350, bubbles=10) * env_exp(0.9, 0.35)
    x = mix((creak, 0, 0.5), (boom, 0.65, 1.0), (crk, 0.66, 0.6), (wet, 0.75, 0.6))
    return finish(dsp.reverb(softclip(norm(x), 1.8), rng, 1.8, 0.35, 1500)[:n_samples(d + 1.0)], -0.5)


@cue(2, "召喚：低沉的「嗚」哼唱（顫音）＋氣聲低語")
def boss_summon(rng, v):
    d = 2.2
    f = U(rng, 95, 115)
    hum = _voice(d, [(0, f), (1.2, f * 1.12), (d, f * 0.95)], [(0, VOWELS["u"]), (d, VOWELS["o"])], rng,
                 vib_rate=3.0, vib_depth=0.04, breath=0.15)
    whisper = formant_filter(highpass(white(d, rng), 900), [(0, VOWELS["i"]), (1.0, VOWELS["a"]), (d, VOWELS["u"])])
    whisper *= 0.5 + 0.5 * np.abs(np.sin(2 * np.pi * 2.3 * time(d)))
    env = env_points(d, [(0, 0), (0.5, 1), (1.7, 0.8), (d, 0)])
    return finish(dsp.reverb((hum + whisper * 0.4) * env, rng, 2.0, 0.4, 2500, 0.05), -2.0)


@cue(3, "臍帶斷裂：緊繃的吱嘎、粗厚的橡膠彈響、濕黏甩動")
def cord_snap(rng, v):
    tension = stick_slip(0.3, rng, [(0, 30), (0.3, 120)], [(0, 250), (0.3, 450)], q=6) * env_points(0.3, [(0, 0), (0.3, 1)])
    snap = mix((thump(0.15, 400, 120, 0.03, rng, click=1.0), 0, 1.0), (impulse_burst(0.02, rng, 1800, 0.004), 0, 1.0))
    tw = pluck(0.5, U(rng, 150, 220), rng, 0.97, 0.5) * env_exp(0.5, 0.12)
    wet = squelch(0.4, rng, 500, bubbles=25) * env_exp(0.4, 0.12)
    x = mix((tension, 0, 0.35), (norm(snap), 0.3, 1.0), (tw, 0.3, 0.6), (wet, 0.32, 0.6))
    return finish(softclip(norm(x), 1.5), -1.0)


@cue(1, "Boss 死亡：長長的下沉哭嚎，聲音破裂，最後只剩氣息【暫代】")
def boss_defeated(rng, v):
    d = 3.5
    f0 = [(0, 420), (0.6, 380), (1.6, 240), (2.6, 150), (d, 110)]
    vow = [(0, VOWELS["a"]), (1.5, VOWELS["o"]), (2.6, VOWELS["u"]), (d, VOWELS["u"])]
    main = _voice(d, f0, vow, rng, vib_rate=5.0, vib_depth=0.04, breath=0.3, jitter=0.05)
    # 聲音破裂：中段隨機掉成次諧波
    sub = _voice(d, [(t, f * 0.5) for t, f in f0], vow, rng, breath=0.5, jitter=0.08)
    gate = (lowpass(white(d, rng), 6) > 0).astype(float)
    gate = lowpass(gate, 30)
    breath = formant_filter(pink(d, rng), vow) * env_points(d, [(0, 0), (2.4, 0.2), (3.0, 0.6), (d, 0)])
    env = env_points(d, [(0, 0), (0.1, 1), (2.0, 0.7), (3.0, 0.2), (d, 0)])
    x = (main * (1 - 0.6 * gate) + sub * 0.6 * gate) * env + breath * 0.5
    return finish(dsp.reverb(x, rng, 2.5, 0.45, 2500, 0.05), -1.0)


# ======================================================================== 精英：連體修女

def _step_curve(d, notes):
    """notes: [(起點秒, 頻率)]，回傳以短滑音連接的階梯音高曲線（給 _voice 用）。"""
    pts = []
    for i, (t, f) in enumerate(notes):
        if i > 0:
            pts.append((max(0.0, t - 0.06), notes[i - 1][1]))
        pts.append((t, f))
    pts.append((d, notes[-1][1]))
    return pts


@cue(2, "雙聲聖歌：兩個女聲用同一口氣哼搖籃曲，第二個聲音慢半拍、高一個小二度（不和諧），氣聲很重")
def twin_hymn(rng, v):
    d = 3.9
    base = U(rng, 300, 330)
    # 下行的搖籃曲片段（兩種變體）
    steps = [1.0, 0.89, 0.84, 0.75, 0.84] if v == 0 else [0.84, 1.0, 0.89, 0.75, 0.67]
    notes = [(i * 0.72, base * k) for i, k in enumerate(steps)]
    vow = [(0, VOWELS["u"]), (1.4, VOWELS["o"]), (2.6, VOWELS["u"]), (d, VOWELS["u"])]
    a = _voice(d, _step_curve(d, notes), vow, rng, vib_rate=5.2, vib_depth=0.012, breath=0.35, jitter=0.015)
    lag = 0.09
    b_notes = [(t + lag, f * 1.059 * 1.004) for t, f in notes]  # 小二度、再走音一點
    b = _voice(d, _step_curve(d, b_notes), vow, rng, vib_rate=4.7, vib_depth=0.018, breath=0.45, jitter=0.02)
    env = env_points(d, [(0, 0), (0.3, 0.8), (3.1, 0.7), (d, 0)])
    x = (a * 0.9 + b * 0.7) * env
    return finish(dsp.reverb(lowpass(x, 3200), rng, 2.4, 0.5, 2500, 0.05), -4.0)


@cue(2, "分裂：粗縫線一根根崩斷、濕黏的撕裂，然後兩聲重疊的尖叫（一高一低、互相走音）")
def twin_split(rng, v):
    d = 2.6
    pops = mix(*[(thump(0.06, U(rng, 600, 900), 200, 0.015, rng, click=1.0), 0.05 + i * U(rng, 0.05, 0.08), 0.6) for i in range(6)])
    tear = stick_slip(0.55, rng, [(0, 40), (0.55, 140)], [(0, 400), (0.55, 900)], q=4, jitter=0.6)
    tear *= env_points(0.55, [(0, 0), (0.1, 1), (0.55, 0.4)])
    wet = squelch(0.9, rng, 420, bubbles=30) * env_exp(0.9, 0.3)
    shriek_d = 1.8
    f1 = [(0, 520), (0.25, 880), (1.0, 760), (shriek_d, 420)]
    s1 = _voice(shriek_d, f1, [(0, VOWELS["a"]), (1.0, VOWELS["ae"]), (shriek_d, VOWELS["a"])], rng, vib_rate=7.0, vib_depth=0.03, breath=0.3, jitter=0.05)
    f2 = [(t, f * 0.71) for t, f in f1]  # 低一個增四度：最刺耳的音程
    s2 = _voice(shriek_d, f2, [(0, VOWELS["e"]), (1.0, VOWELS["a"]), (shriek_d, VOWELS["o"])], rng, vib_rate=5.5, vib_depth=0.04, breath=0.4, jitter=0.06)
    senv = env_points(shriek_d, [(0, 0), (0.08, 1), (1.2, 0.7), (shriek_d, 0)])
    x = mix((norm(pops), 0, 0.5), (tear, 0.1, 0.6), (wet, 0.45, 0.7), (s1 * senv, 0.5, 0.8), (s2 * senv, 0.58, 0.7))
    return finish(dsp.reverb(softclip(norm(x), 1.4), rng, 1.8, 0.4, 2800, 0.04)[:n_samples(d + 1.0)], -0.5)

# ======================================================================== 追逐戰：母親破牆

@cue(2, "破牆：石牆被撞碎的巨響——低頻轟擊、碎石崩落的喀擦串、肉被扯開的濕黏聲")
def mother_wall_burst(rng, v):
    d = 2.6
    boom = thump(1.6, 90, 30, 0.5, rng, click=1.2)
    crash = crackle(1.2, rng, [(0, 400), (0.4, 120), (1.2, 10)], (600, 3500)) * env_exp(1.2, 0.45)
    rubble = lowpass(white(1.8, rng), 900) * env_points(1.8, [(0, 0), (0.05, 1), (0.6, 0.5), (1.8, 0)])
    rip = squelch(0.8, rng, 420, bubbles=18) * env_exp(0.8, 0.3)
    x = mix((boom, 0, 1.0), (crash, 0.01, 0.8), (norm(rubble), 0.02, 0.6), (rip, 0.25, 0.7))
    return finish(dsp.reverb(softclip(norm(x), 2.0), rng, 2.0, 0.4, 1800)[:n_samples(d)], -0.5)


@cue(3, "重踏：高蹺般的腿砸在石地上——沉重悶擊、骨頭咯吱、一點碎石")
def mother_stomp(rng, v):
    hit = thump(0.5, U(rng, 75, 95), 34, 0.18, rng, click=0.9)
    creak = stick_slip(0.18, rng, [(0, 40), (0.18, 15)], U(rng, 350, 520), q=7) * env_exp(0.18, 0.06)
    grit = bandpass(white(0.15, rng), U(rng, 2200, 3500), 1.4) * env_exp(0.15, 0.04)
    x = mix((hit, 0, 1.0), (creak, 0.03, 0.35), (norm(grit), 0.01, 0.25))
    return finish(dsp.reverb(softclip(norm(x), 1.6), rng, 0.8, 0.25, 1600), -1.0)


@cue(2, "尖嚎：撲擊前的尖叫——共振峰人聲急升到破音，夾著低八度的嘶吼【暫代】")
def mother_shriek(rng, v):
    d = 1.1
    f0 = [(0, 300), (0.25, 780), (0.7, 860), (d, 520)]
    vow = [(0, VOWELS["a"]), (0.4, VOWELS["ae"]), (0.8, VOWELS["e"]), (d, VOWELS["i"])]
    main = _voice(d, f0, vow, rng, vib_rate=9.0, vib_depth=0.04, breath=0.35, jitter=0.06)
    low = _voice(d, [(t, f * 0.5 * 1.02) for t, f in f0], vow, rng, vib_rate=7.0, vib_depth=0.05, breath=0.5, jitter=0.08)
    env = env_points(d, [(0, 0), (0.08, 1), (0.8, 0.85), (d, 0)])
    x = softclip((main + 0.6 * low) * env, 2.5)
    return finish(dsp.reverb(x, rng, 1.4, 0.35, 3500, 0.03), -1.0)


@cue(3, "呼吸：貼在背後的濕重吸氣與吐氣，喉嚨裡有痰的咯咯聲")
def mother_breath(rng, v):
    d = 1.4
    inh = formant_filter(pink(0.6, rng), [(0, VOWELS["o"]), (0.6, VOWELS["u"])]) * env_points(0.6, [(0, 0), (0.45, 1), (0.6, 0.2)])
    exh = formant_filter(pink(0.8, rng), [(0, VOWELS["a"]), (0.8, VOWELS["o"])]) * env_points(0.8, [(0, 0), (0.1, 1), (0.8, 0)])
    gurgle = squelch(0.5, rng, U(rng, 180, 260), bubbles=14) * env_exp(0.5, 0.2)
    x = mix((norm(inh), 0, 0.7), (norm(exh), 0.6, 1.0), (gurgle, 0.62, 0.35))
    return finish(lowpass(x, 3200)[:n_samples(d)], -2.0)


@cue(2, "拖行：身體被拖過石地——長長的摩擦、布料與皮膚的吱嘎、指甲刮地")
def body_drag(rng, v):
    d = 1.0
    scrape = bandpass(pink(d, rng), U(rng, 500, 800), 1.2) * env_points(d, [(0, 0), (0.15, 1), (0.8, 0.8), (d, 0)])
    squeak = stick_slip(d, rng, [(0, 30), (d, 60)], [(0, 900), (d, 1300)], q=5) * 0.3
    nails = stick_slip(0.4, rng, 90, U(rng, 2500, 3500), q=9) * env_exp(0.4, 0.15)
    x = mix((norm(scrape), 0, 1.0), (squeak, 0, 0.5), (nails, U(rng, 0.2, 0.5), 0.25))
    return finish(x, -3.0)


@cue(3, "肉在長：濕黏的蠕動、細小的肉芽爆開聲")
def flesh_grow(rng, v):
    d = 0.9
    wet = squelch(d, rng, U(rng, 300, 600), wobble=0.9, bubbles=int(U(rng, 18, 30))) * env_points(d, [(0, 0), (0.2, 1), (d, 0)])
    pops = crackle(d, rng, 25, (700, 1800)) * env_exp(d, 0.35)
    x = mix((wet, 0, 1.0), (pops, 0.05, 0.4))
    return finish(lowpass(x, 4000), -3.0)


@cue(2, "燈熄滅：燭火被掐滅的嘶聲與一下小小的爆裂")
def light_die(rng, v):
    hiss = highpass(white(0.35, rng), 2500) * env_exp(0.35, 0.1)
    pop = impulse_burst(0.03, rng, U(rng, 1500, 2500), 0.004)
    puff = lowpass(white(0.2, rng), 600) * env_exp(0.2, 0.06)
    x = mix((norm(pop), 0, 0.8), (norm(hiss), 0.01, 0.5), (norm(puff), 0.0, 0.4))
    return finish(dsp.reverb(x, rng, 0.5, 0.15, 3000), -4.0)


# ======================================================================== UI

@cue(2, "滑過選項：很小的骨頭輕敲聲")
def ui_hover(rng, v):
    c = impulse_burst(0.04, rng, U(rng, 2200, 2800), 0.003)
    c += 0.4 * partials(0.04, [U(rng, 1800, 2100)], [0.008], [1])
    return finish(c, -6.0, bits=10)


@cue(2, "確認：兩聲八音盒叮聲（上行）")
def ui_confirm(rng, v):
    a, b = [(880.0, 1318.5), (987.8, 1318.5)][v]
    da = partials(0.8, [a, a * 2, a * 4.95], [0.35, 0.15, 0.05], [1, 0.25, 0.1], rng)
    db = partials(0.9, [b, b * 2, b * 4.95], [0.4, 0.15, 0.05], [1, 0.25, 0.1], rng)
    return finish(dsp.reverb(mix((da, 0, 0.7), (db, 0.07, 0.8)), rng, 0.6, 0.18, 5000), -3.0, bits=10)


@cue(2, "開啟選單：兩聲骨頭輕敲＋柔和的低音湧起")
def ui_open(rng, v):
    ticks = mix((impulse_burst(0.03, rng, 2000, 0.003), 0, 1.0), (impulse_burst(0.03, rng, 2600, 0.003), 0.06, 0.8))
    swell = lowpass(osc(0.4, [(0, 110), (0.4, 165)], "tri"), 600) * env_points(0.4, [(0, 0), (0.15, 1), (0.4, 0)])
    return finish(mix((ticks, 0, 1.0), (swell, 0, 0.2)), -4.0, bits=10)


@cue(2, "關閉選單：下行的骨頭輕敲＋低音回落")
def ui_close(rng, v):
    ticks = mix((impulse_burst(0.03, rng, 2600, 0.004), 0, 0.8), (impulse_burst(0.03, rng, 1700, 0.005), 0.06, 1.0))
    fall = lowpass(osc(0.35, [(0, 165), (0.35, 98)], "tri"), 600) * env_points(0.35, [(0, 0), (0.05, 1), (0.35, 0)])
    return finish(mix((ticks, 0, 1.0), (fall, 0, 0.2)), -4.0, bits=10)


# ======================================================================== 輸出

def write_wav(path: str, x: np.ndarray) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(dsp.SR)
        w.writeframes(data.tobytes())


def render(name: str, variant: int) -> np.ndarray:
    fn, _, _ = CUES[name]
    seed = zlib.crc32(f"{name}:{variant}".encode())
    x = fn(np.random.default_rng(seed), variant)
    if not np.all(np.isfinite(x)):
        raise RuntimeError(f"{name} #{variant}: NaN/Inf")
    return x


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cues", nargs="*", help="只產生這些 cue（可用萬用字元）")
    ap.add_argument("--out", default=OUT_DIR)
    ap.add_argument("--preview", help="另外把所有變體串成一個試聽檔")
    ap.add_argument("--list", action="store_true", help="列出 cue 與說明（Markdown 表格）")
    args = ap.parse_args()

    names = list(CUES)
    if args.cues:
        names = [n for n in names if any(fnmatch.fnmatch(n, p) for p in args.cues)]
    if args.list:
        for n in names:
            print(f"| `{n}` | {CUES[n][1]} | {CUES[n][2]} |")
        return 0

    preview = []
    gap = np.zeros(int(0.6 * dsp.SR))
    for n in names:
        _, variants, _ = CUES[n]
        d = os.path.join(args.out, n)
        if os.path.isdir(d):
            for f in os.listdir(d):
                if f.startswith(n + "_") and f.endswith(".wav"):
                    os.remove(os.path.join(d, f))
        for v in range(variants):
            x = render(n, v)
            write_wav(os.path.join(d, f"{n}_{v + 1}.wav"), x)
            preview += [x, gap[: len(gap) // 2]]
            print(f"{n}_{v + 1}.wav  {len(x) / dsp.SR:.2f}s")
        preview.append(gap)
    if args.preview:
        write_wav(args.preview, np.concatenate(preview))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
