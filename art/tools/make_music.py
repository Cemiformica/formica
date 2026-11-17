# Música de prueba del vertical slice (C1.8, César): tres temas tranquilos de ~1 min y medio que suenan
# por turnos, con silencios entre ellos (los alterna `MusicPlayer` en Godot). Sustituye al bucle de 16 s.
# Cada tema tiene partes (intro, A, A con variación, B, A final, cierre) para que no se haga repetitivo.
# Uso: python make_music.py <carpeta>  → escribe music_alba.wav, music_galerias.wav, music_engranajes.wav.
# Solo necesita numpy (también corre dentro de Blender). Dónde tocar: la tabla TRACKS (tempo, acordes,
# melodías y qué instrumentos entran en cada parte).
import math
import os
import random
import struct
import sys

import numpy as np

RATE = 44100
PEAK = 0.7  # pico máximo de cada tema; el volumen final lo pone el bus «Music»
TARGET_RMS = 0.085  # mismo volumen medio en los tres temas


def hz(midi: float) -> float:
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


# --- Instrumentos: devuelven un array mono ---

def tone(freq, length, partials, decay, attack=0.005, release=0.08, vibrato=0.0):
    n = int(RATE * length)
    t = np.arange(n) / RATE
    phase_mod = vibrato * np.sin(2 * math.pi * 4.5 * t) if vibrato else 0.0
    out = np.zeros(n)
    for ratio, gain in partials:
        # los parciales altos se apagan antes, como en un instrumento de verdad
        out += gain * np.sin(2 * math.pi * freq * ratio * t + phase_mod) * np.exp(-t * decay * (1 + 0.15 * (ratio - 1)))
    env = np.minimum(1.0, t / attack) * np.minimum(1.0, (length - t) / release)
    return out * np.clip(env, 0, 1)


def kalimba(freq, length):
    return tone(freq, length + 0.8, ((1, 1.0), (2.0, 0.12), (5.4, 0.08), (11.1, 0.02)), 3.2, 0.003, 0.3)


def marimba(freq, length):
    return tone(freq, length + 0.5, ((1, 1.0), (4, 0.22), (10, 0.05)), 4.0, 0.002, 0.25)


def music_box(freq, length):
    return tone(freq, length + 1.0, ((1, 1.0), (3, 0.18), (6.3, 0.05)), 2.4, 0.002, 0.4)


def bass(freq, length):
    return tone(freq, length, ((1, 1.0), (2, 0.3), (3, 0.08)), 1.2, 0.02, 0.15)


def pad(notes, length, brightness=0.25):
    n = int(RATE * length)
    t = np.arange(n) / RATE
    out = np.zeros(n)
    for m in notes:
        f = hz(m)
        for detune in (0.997, 1.0, 1.003):
            out += np.sin(2 * math.pi * f * detune * t) + brightness * np.sin(2 * math.pi * 2 * f * detune * t)
    swell = 0.85 + 0.15 * np.sin(2 * math.pi * t / length - math.pi / 2)  # respira dentro del compás
    attack, release = min(1.2, length / 3), min(1.2, length / 3)
    env = np.minimum(1.0, t / attack) * np.minimum(1.0, (length - t) / release)
    return out * env * swell / (len(notes) * 3)


def tick(rng, gain):
    # Tic de madera y metal muy suave: el «reloj» de las máquinas, sin ser percusión de baile.
    n = int(RATE * 0.05)
    t = np.arange(n) / RATE
    noise = np.array([rng.uniform(-1, 1) for _ in range(n)])
    knock = np.sin(2 * math.pi * 1800 * t) * 0.5 + np.sin(2 * math.pi * 2650 * t) * 0.3
    return (noise * 0.4 + knock) * np.exp(-t * 120) * gain


def add(out, start_s, samples):
    i = int(start_s * RATE)
    if i >= len(out):
        return
    j = min(len(out), i + len(samples))
    out[i:j] += samples[: j - i]


def reverb(x, seconds, seed):
    # Reverberación por convolución con una cola de ruido que se apaga (sala cálida, sin metales).
    rng = np.random.default_rng(seed)
    n = int(RATE * seconds)
    t = np.arange(n) / RATE
    ir = rng.uniform(-1, 1, n) * np.exp(-t * 6.9 / seconds)
    ir = np.convolve(ir, np.ones(24) / 24, mode="same")  # quita brillo
    ir[: int(RATE * 0.02)] = 0.0  # pequeño retardo antes de la cola
    ir /= np.sqrt(np.sum(ir ** 2))
    size = 1 << int(math.ceil(math.log2(len(x) + n)))
    y = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[: len(x) + n]
    return y


# --- Melodía: motivos de 2 compases en grados de la escala, con variaciones ---

def degree_to_midi(scale, root, degree):
    octave, idx = divmod(degree, len(scale))
    return root + 12 * octave + scale[idx]


def vary(motif, rng, shift=0):
    out = []
    for k, (beat, deg, dur) in enumerate(motif):
        if rng.random() < 0.35 and k not in (0, len(motif) - 1):
            deg += rng.choice((-1, 1))
        out.append((beat, deg + shift, dur))
    return out


def phrase(motif, rng):
    """8 compases: motivo, motivo variado, motivo una nota más arriba y cierre que baja a la tónica."""
    m2 = vary(motif, rng)
    m3 = vary(motif, rng, 1)
    cadence = [(b, d, l) for b, d, l in vary(motif, rng)][:-1] + [(motif[-1][0], 0, 4.0)]
    notes = []
    for k, m in enumerate((motif, m2, m3, cadence)):
        notes += [(beat + 8 * k, deg, dur) for beat, deg, dur in m]
    return notes


TRACKS = {
    # Amanecer en Isla Alba: Re mayor, kalimba sobre un colchón suave. Lo más luminoso.
    "alba": dict(
        bpm=72, root=62, scale=(0, 2, 4, 7, 9), lead=kalimba, lead_gain=0.22, lead_octave=12, seed=11,
        chords=[[50, 57, 62, 66, 69], [47, 54, 59, 62, 66], [43, 50, 55, 59, 62], [45, 52, 57, 61, 64]],
        motif_a=[(0, 2, 1), (1, 4, 1), (2, 3, 1.5), (3.5, 2, 0.5), (4, 1, 2), (6, 2, 2)],
        motif_b=[(0, 4, 2), (2, 5, 1), (3, 4, 1), (4, 3, 3), (7, 1, 1)],
        arp=music_box, arp_gain=0.05, tick=False,
    ),
    # Galerías del hormiguero: La dórico, más lento y cálido, marimba grave.
    "galerias": dict(
        bpm=64, root=57, scale=(0, 2, 3, 7, 9), lead=marimba, lead_gain=0.2, lead_octave=0, seed=23,
        chords=[[45, 52, 57, 60, 64, 67], [50, 57, 62, 66, 69], [41, 48, 53, 57, 64], [43, 50, 55, 59, 62]],
        motif_a=[(0, 0, 1.5), (1.5, 1, 0.5), (2, 2, 2), (4, 4, 1), (5, 3, 1), (6, 2, 2)],
        motif_b=[(0, 5, 1), (1, 4, 1), (2, 3, 2), (4, 2, 1.5), (5.5, 1, 0.5), (6, 2, 2)],
        arp=kalimba, arp_gain=0.04, tick=False,
    ),
    # Engranajes suaves: Fa lidio, caja de música y un tictac de máquina muy bajito.
    "engranajes": dict(
        bpm=84, root=65, scale=(0, 2, 4, 6, 7, 9, 11), lead=marimba, lead_gain=0.18, lead_octave=12, seed=37,
        chords=[[41, 53, 57, 60, 64], [43, 55, 59, 62, 65], [40, 52, 55, 59, 62], [45, 52, 57, 60, 64]],
        motif_a=[(0, 4, 1), (1, 6, 1), (2, 7, 1), (3, 6, 1), (4, 4, 2), (6, 3, 1), (7, 4, 1)],
        motif_b=[(0, 7, 2), (2, 6, 1), (3, 4, 1), (4, 5, 2), (6, 4, 2)],
        arp=music_box, arp_gain=0.06, tick=True,
    ),
}

# Partes de cada tema (compases): qué suena en cada una.
SECTIONS = [
    dict(name="intro", bars=2, bass=False, arp=False, melody=None, tick=False),
    dict(name="A", bars=8, bass=True, arp=False, melody="a", tick=True),
    dict(name="A2", bars=8, bass=True, arp=True, melody="a2", tick=True),
    dict(name="B", bars=8, bass=False, arp=True, melody="b", tick=False),
    dict(name="A3", bars=8, bass=True, arp=False, melody="a3", tick=True),
    dict(name="outro", bars=2, bass=False, arp=False, melody=None, tick=False),
]


def render(spec):
    rng = random.Random(spec["seed"])
    beat = 60.0 / spec["bpm"]
    bar = beat * 4
    total_bars = sum(s["bars"] for s in SECTIONS)
    length = total_bars * bar + 4.0
    dry = np.zeros(int(RATE * length))
    lead = np.zeros_like(dry)
    phrases = {"a": phrase(spec["motif_a"], rng), "a2": phrase(spec["motif_a"], rng),
               "b": phrase(spec["motif_b"], rng), "a3": phrase(spec["motif_a"], rng)}
    bar_index = 0
    for section in SECTIONS:
        for k in range(section["bars"]):
            start = bar_index * bar
            chord = spec["chords"][bar_index % len(spec["chords"])]
            add(dry, start, pad(chord, bar + 0.6) * 0.5)
            if section["bass"]:
                root = chord[0] - 12 if chord[0] > 45 else chord[0]
                add(dry, start, bass(hz(root), beat * 2.2) * 0.3)
                add(dry, start + beat * 2.5, bass(hz(root + 7), beat * 1.2) * 0.18)
            if section["arp"]:
                pattern = (1, 2, 3, 4, 3, 2) if spec["bpm"] < 80 else (1, 3, 2, 4, 3, 2, 4, 3)
                step = bar / len(pattern)
                for i, idx in enumerate(pattern):
                    note = chord[min(idx, len(chord) - 1)] + 12
                    add(dry, start + i * step, spec["arp"](hz(note), step) * spec["arp_gain"])
            if spec["tick"] and section["tick"]:
                for i in range(4):
                    add(dry, start + i * beat, tick(rng, 0.05 if i % 2 == 0 else 0.03))
            bar_index += 1
        if section["melody"]:
            first = (bar_index - section["bars"]) * bar
            for b, deg, dur in phrases[section["melody"]]:
                midi = degree_to_midi(spec["scale"], spec["root"] + spec["lead_octave"], deg)
                swing = rng.uniform(-0.012, 0.012)  # que no suene a máquina
                add(lead, first + b * beat + swing, spec["lead"](hz(midi), dur * beat) * spec["lead_gain"] * rng.uniform(0.85, 1.0))
    mix = dry + lead
    # Cierre: baja el volumen en los dos últimos compases y deja sonar la reverberación.
    end = int(total_bars * bar * RATE)
    fade = int(2 * bar * RATE)
    mix[end - fade:end] *= np.linspace(1.0, 0.0, fade) ** 1.5
    mix[end:] = 0.0
    left = mix * 0.75 + reverb(mix, 3.2, spec["seed"])[: len(mix)] * 0.45
    right = mix * 0.75 + reverb(mix, 3.2, spec["seed"] + 1)[: len(mix)] * 0.45
    stereo = np.stack([left, right], axis=1)
    stereo *= TARGET_RMS / np.sqrt(np.mean(stereo[: end] ** 2))
    peak = np.max(np.abs(stereo))
    if peak > PEAK:
        stereo *= PEAK / peak
    return stereo


def write_wav(path, stereo):
    data = (np.clip(stereo, -1, 1) * 32767).astype("<i2").tobytes()
    with open(path, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", 36 + len(data)) + b"WAVEfmt ")
        f.write(struct.pack("<IHHIIHH", 16, 1, 2, RATE, RATE * 4, 4, 16))
        f.write(b"data" + struct.pack("<I", len(data)) + data)


def main(folder):
    os.makedirs(folder, exist_ok=True)
    for name, spec in TRACKS.items():
        stereo = render(spec)
        write_wav(os.path.join(folder, "music_%s.wav" % name), stereo)
        print("music_%s.wav  %.0f s" % (name, len(stereo) / RATE))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
