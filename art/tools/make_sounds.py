"""Genera los sonidos de prueba de B5.4 sin bibliotecas externas (arte propio, como make_palette.py).
Uso (fuera de Blender o desde él):  python make_sounds.py <carpeta de salida> [--v2]
Escribe build_place.wav (colocar: M1) y music_test.wav (bucle de 16 s, versión 2). Con --v2,
además las pruebas de B5.4 para escuchar.
Dónde tocar: frecuencias y duraciones en build_place(); acordes y tempo en music_test().
"""
import math, random, struct, sys, wave, os

RATE = 44100


def write_wav(path, samples):
    """Guarda muestras en [-1, 1] como WAV mono de 16 bits."""
    peak = max(1e-6, max(abs(s) for s in samples))
    gain = 0.89 / peak  # normalizado a -1 dB
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s * gain)) * 32767)) for s in samples))


def build_place():
    """«Clonc» de 0,4 s: golpe grave que baja de tono, toque de madera (ruido filtrado) y un ping metálico suave."""
    rng = random.Random(7)
    n = int(RATE * 0.4)
    out = []
    phase = 0.0
    low = 0.0
    for i in range(n):
        t = i / RATE
        freq = 70.0 + 90.0 * math.exp(-t * 30.0)          # golpe: 160 Hz que cae a 70
        phase += 2 * math.pi * freq / RATE
        thump = math.sin(phase) * math.exp(-t * 18.0)
        noise = rng.uniform(-1.0, 1.0)
        low += 0.25 * (noise - low)                          # ruido suavizado = madera
        knock = low * math.exp(-t * 60.0) * 1.6
        ping = (math.sin(2 * math.pi * 1760 * t) + 0.5 * math.sin(2 * math.pi * 2650 * t)) * math.exp(-t * 14.0) * 0.12
        attack = min(1.0, t / 0.002)
        out.append((thump + knock + ping) * attack)
    return out


def music_test():
    """Bucle de 8 s: cuatro acordes de 2 s (Do maj7, La m7, Fa maj7, Sol 6) en un colchón suave
    y un arpegio pulsado a 120 ppm. Todo se apaga y se enciende en los bordes para que el bucle no chasquee."""
    chords = [[48, 55, 64, 71], [45, 52, 60, 67], [41, 48, 57, 64], [43, 50, 59, 64]]
    seconds = 8.0
    n = int(RATE * seconds)
    out = [0.0] * n
    hz = lambda note: 440.0 * 2 ** ((note - 69) / 12)
    chord_len = seconds / len(chords)
    for c, notes in enumerate(chords):
        start = int(c * chord_len * RATE)
        length = int(chord_len * RATE)
        for i in range(length):
            t = i / RATE
            env = min(1.0, t / 0.25) * min(1.0, (chord_len - t) / 0.25)  # sube y baja 0,25 s
            v = 0.0
            for note in notes:
                f = hz(note)
                v += math.sin(2 * math.pi * f * t) + 0.3 * math.sin(2 * math.pi * f * 1.003 * t)
            out[start + i] += v * env * 0.08
        # Arpegio: una nota cada 0,25 s (corcheas a 120 ppm), una octava arriba.
        step = 0.25
        for k in range(int(chord_len / step)):
            note = notes[k % len(notes)] + 12
            s0 = start + int(k * step * RATE)
            for i in range(int(0.22 * RATE)):
                t = i / RATE
                env = min(1.0, t / 0.004) * math.exp(-t * 9.0)
                f = hz(note)
                out[s0 + i] += (math.sin(2 * math.pi * f * t) + 0.25 * math.sin(4 * math.pi * f * t)) * env * 0.12
    return out


# --- Versiones 2 (B5.4, a petición de César): música más elaborada y golpes más mecánicos ---

def _hz(note):
    return 440.0 * 2 ** ((note - 69) / 12)


def _add(out, start, samples):
    """Suma `samples` en `out` desde `start`; lo que pasa del final vuelve al principio (bucle sin cortes)."""
    n = len(out)
    for i, s in enumerate(samples):
        out[(start + i) % n] += s


def _clank(rng, length=0.35, low=95.0, metal=(880.0, 1390.0, 2210.0), decay=11.0, gain=1.0):
    """Golpe de metal pesado: tono grave que cae y parciales inarmónicos que resuenan."""
    out = []
    phase = 0.0
    for i in range(int(RATE * length)):
        t = i / RATE
        f = low + low * 1.2 * math.exp(-t * 40.0)
        phase += 2 * math.pi * f / RATE
        thump = math.sin(phase) * math.exp(-t * 22.0)
        ring = sum(math.sin(2 * math.pi * m * t + k) / (k + 1) for k, m in enumerate(metal)) * math.exp(-t * decay) * 0.35
        hit = rng.uniform(-1.0, 1.0) * math.exp(-t * 300.0) * 0.6
        out.append((thump + ring + hit) * min(1.0, t / 0.001) * gain)
    return out


def _click(rng, freq=2600.0, gain=0.5):
    """Clic seco de trinquete: chasquido de ruido y una resonancia muy corta."""
    out = []
    for i in range(int(RATE * 0.03)):
        t = i / RATE
        out.append((rng.uniform(-1.0, 1.0) * math.exp(-t * 500.0) + math.sin(2 * math.pi * freq * t) * math.exp(-t * 160.0)) * gain)
    return out


def build_place_ratchet():
    """A · Trinquete: tres clics rápidos y un cierre metálico pesado."""
    rng = random.Random(11)
    out = [0.0] * int(RATE * 0.55)
    for k in range(3):
        _add(out, int(RATE * 0.045 * k), _click(rng, 2400.0 + 300 * k, 0.45))
    _add(out, int(RATE * 0.15), _clank(rng, 0.4))
    return out


def build_place_piston(clank_gain=1.0):
    """B · Pistón: un soplido neumático corto y un golpe que asienta la máquina. `clank_gain` baja el golpe
    respecto al soplido (1 = como la primera versión)."""
    rng = random.Random(23)
    out = [0.0] * int(RATE * 0.6)
    hiss = []
    prev = 0.0
    for i in range(int(RATE * 0.18)):
        t = i / RATE
        noise = rng.uniform(-1.0, 1.0)
        high = noise - prev  # quitar graves: soplido
        prev = noise
        env = min(1.0, t / 0.02) * math.exp(-t * 14.0)
        hiss.append(high * env * 0.35)
    _add(out, 0, hiss)
    _add(out, int(RATE * 0.16), _clank(rng, 0.42, low=80.0, metal=(620.0, 1010.0, 1730.0), decay=9.0, gain=clank_gain))
    return out


def build_place_gear():
    """C · Engranaje y cerrojo: un motorcito que gira subiendo de tono y dos golpes de cerrojo."""
    rng = random.Random(37)
    out = [0.0] * int(RATE * 0.62)
    whir = []
    phase = 0.0
    for i in range(int(RATE * 0.2)):
        t = i / RATE
        f = 220.0 + 380.0 * (t / 0.2)
        phase += f / RATE
        saw = 2.0 * (phase % 1.0) - 1.0
        teeth = 1.0 if (phase * 4) % 1.0 < 0.5 else 0.6  # dientes del engranaje
        whir.append(saw * teeth * min(1.0, t / 0.02) * min(1.0, (0.2 - t) / 0.03) * 0.18)
    _add(out, 0, whir)
    _add(out, int(RATE * 0.2), _clank(rng, 0.2, low=120.0, metal=(1500.0, 2300.0), decay=20.0, gain=0.6))
    _add(out, int(RATE * 0.27), _clank(rng, 0.35, low=90.0))
    return out


def _tone(freq, length, partials, decay, attack=0.004):
    out = []
    for i in range(int(RATE * length)):
        t = i / RATE
        env = min(1.0, t / attack) * math.exp(-t * decay)
        out.append(sum(a * math.sin(2 * math.pi * freq * m * t) for m, a in partials) * env)
    return out


def music_test_v2():
    """Bucle de 16 s a 120 ppm (8 compases de 2 s), con el mismo estilo suave que music_test():
    colchón de acordes, arpegio, bajo, una melodía de marimba en la segunda mitad y percusión ligera
    (bombo suave y shaker) que entra en el compás 3. Las colas que pasan del final vuelven al principio."""
    rng = random.Random(5)
    bar = 2.0
    chords = [[48, 55, 64, 71], [45, 52, 60, 67], [41, 48, 57, 64], [43, 50, 59, 62],
              [48, 55, 64, 71], [40, 47, 55, 62], [41, 48, 57, 64], [43, 50, 55, 60]]
    n = int(RATE * bar * len(chords))
    out = [0.0] * n
    beat = bar / 4
    eighth = beat / 2
    for c, notes in enumerate(chords):
        start = int(c * bar * RATE)
        # Colchón
        pad = []
        for i in range(int(bar * RATE)):
            t = i / RATE
            env = min(1.0, t / 0.3) * min(1.0, (bar - t) / 0.3)
            v = sum(math.sin(2 * math.pi * _hz(m) * t) + 0.3 * math.sin(2 * math.pi * _hz(m) * 1.003 * t) for m in notes)
            pad.append(v * env * 0.055)
        _add(out, start, pad)
        # Bajo: tónica en los tiempos 1 y 3, y la quinta en el 4 «y».
        root_note = notes[0] - 12
        for when, note in ((0.0, root_note), (2 * beat, root_note), (3.5 * beat, root_note + 7)):
            _add(out, start + int(when * RATE), _tone(_hz(note), 0.45, ((1, 1.0), (2, 0.35), (3, 0.12)), 6.0, 0.01))
        # Arpegio: subida y bajada en corcheas; más suave en la primera mitad.
        pattern = [0, 1, 2, 3, 2, 1, 2, 3]
        arp_gain = 0.08 if c < 4 else 0.06
        for k, idx in enumerate(pattern):
            _add(out, start + int(k * eighth * RATE),
                 [s * arp_gain for s in _tone(_hz(notes[idx] + 12), 0.22, ((1, 1.0), (2, 0.25)), 9.0)])
        # Percusión desde el compás 3: bombo suave en 1 y 3, shaker en corcheas con acento a contratiempo.
        if c >= 2:
            for when in (0.0, 2 * beat):
                kick = []
                ph = 0.0
                for i in range(int(RATE * 0.25)):
                    t = i / RATE
                    ph += 2 * math.pi * (50 + 70 * math.exp(-t * 35)) / RATE
                    kick.append(math.sin(ph) * math.exp(-t * 14) * 0.35)
                _add(out, start + int(when * RATE), kick)
            for k in range(8):
                g = 0.05 if k % 2 else 0.025
                shake = []
                prev = 0.0
                for i in range(int(RATE * 0.06)):
                    t = i / RATE
                    nz = rng.uniform(-1.0, 1.0)
                    shake.append((nz - prev) * math.exp(-t * 70) * g)
                    prev = nz
                _add(out, start + int(k * eighth * RATE), shake)
    # Melodía de marimba en los compases 5–8 (pentatónica de Do), con notas de los acordes en los tiempos fuertes.
    melody = [  # (compás, tiempo, nota MIDI, duración en tiempos)
        (4, 0, 76, 1), (4, 1, 79, 1), (4, 2, 76, 0.5), (4, 2.5, 74, 0.5), (4, 3, 72, 1),
        (5, 0, 74, 1.5), (5, 1.5, 76, 0.5), (5, 2, 79, 2),
        (6, 0, 81, 1), (6, 1, 79, 0.5), (6, 1.5, 76, 0.5), (6, 2, 77, 1), (6, 3, 76, 1),
        (7, 0, 74, 1), (7, 1, 72, 1), (7, 2, 74, 2),
    ]
    for c, b, note, dur in melody:
        s = _tone(_hz(note), max(0.3, dur * beat + 0.15), ((1, 1.0), (4, 0.25), (10, 0.06)), 5.0, 0.002)
        _add(out, int((c * bar + b * beat) * RATE), [x * 0.16 for x in s])
    return out


def write_previews(folder):
    """Escribe las versiones 2 para escucharlas antes de elegir."""
    os.makedirs(folder, exist_ok=True)
    write_wav(os.path.join(folder, "build_place_a_ratchet.wav"), build_place_ratchet())
    write_wav(os.path.join(folder, "build_place_b_piston.wav"), build_place_piston())
    write_wav(os.path.join(folder, "build_place_c_gear.wav"), build_place_gear())
    write_wav(os.path.join(folder, "music_test_v2.wav"), music_test_v2())


# --- Variantes del pistón (B5.4, segunda ronda con César): más protagonismo del soplido u orden inverso ---

def _hiss(rng, length, gain=0.4, attack=0.015, decay=10.0, bright_start=0.55, bright_end=0.25):
    """Soplido neumático: ruido filtrado en banda cuyo brillo va de `bright_start` a `bright_end`
    (0–1: más alto = más agudo). Con brillo que baja suena a «tsss» que se apaga."""
    out = []
    low = 0.0
    low2 = 0.0
    n = int(RATE * length)
    for i in range(n):
        t = i / RATE
        k = bright_start + (bright_end - bright_start) * (i / n)
        noise = rng.uniform(-1.0, 1.0)
        low += k * (noise - low)          # quita lo más agudo
        low2 += 0.04 * (low - low2)       # parte grave, para restarla
        band = low - low2
        env = min(1.0, t / attack) * math.exp(-t * decay)
        out.append(band * env * gain)
    return out


def _variant(parts, length):
    out = [0.0] * int(RATE * length)
    for start, samples in parts:
        _add(out, int(RATE * start), samples)
    return out


def piston_b1():
    """B1 · Soplido protagonista: un «tsss» más largo y fuerte y un golpe más discreto al final."""
    rng = random.Random(41)
    return _variant([(0.0, _hiss(rng, 0.32, 0.9, decay=5.0)),
                     (0.26, _clank(rng, 0.38, low=80.0, metal=(620.0, 1010.0, 1730.0), decay=10.0, gain=0.55))], 0.7)


def piston_b2():
    """B2 · Al revés: el golpe primero y después el soplido, como si la máquina se asentara y soltara aire."""
    rng = random.Random(43)
    return _variant([(0.0, _clank(rng, 0.38, low=80.0, metal=(620.0, 1010.0, 1730.0), decay=10.0, gain=0.8)),
                     (0.09, _hiss(rng, 0.45, 0.8, attack=0.03, decay=5.5, bright_start=0.45, bright_end=0.15))], 0.65)


def piston_b3():
    """B3 · Pistón completo: clic de válvula, soplido, golpe y un suspiro final más grave."""
    rng = random.Random(47)
    return _variant([(0.0, _click(rng, 1900.0, 0.35)),
                     (0.02, _hiss(rng, 0.2, 0.8, decay=9.0)),
                     (0.18, _clank(rng, 0.35, low=85.0, metal=(700.0, 1150.0, 1900.0), decay=11.0, gain=0.7)),
                     (0.3, _hiss(rng, 0.35, 0.45, attack=0.04, decay=7.0, bright_start=0.3, bright_end=0.1))], 0.75)


def piston_b4():
    """B4 · Golpe y doble resoplido corto («tss-tss»), más juguetón."""
    rng = random.Random(53)
    return _variant([(0.0, _clank(rng, 0.32, low=90.0, metal=(760.0, 1240.0, 2050.0), decay=13.0, gain=0.75)),
                     (0.1, _hiss(rng, 0.12, 0.75, attack=0.005, decay=20.0, bright_start=0.6, bright_end=0.4)),
                     (0.24, _hiss(rng, 0.2, 0.65, attack=0.005, decay=12.0, bright_start=0.5, bright_end=0.2))], 0.55)


def piston_b5():
    """B5 · Pistón grave y pesado: el soplido más oscuro, a la vez que el golpe, y una cola de aire."""
    rng = random.Random(59)
    return _variant([(0.0, _hiss(rng, 0.5, 0.85, attack=0.01, decay=4.5, bright_start=0.35, bright_end=0.12)),
                     (0.05, _clank(rng, 0.45, low=65.0, metal=(480.0, 790.0, 1330.0), decay=8.0, gain=0.7))], 0.7)


def write_piston_previews(folder):
    os.makedirs(folder, exist_ok=True)
    for name, make in (("b1_hiss_lead", piston_b1), ("b2_clank_then_hiss", piston_b2), ("b3_full_piston", piston_b3),
                       ("b4_double_puff", piston_b4), ("b5_heavy", piston_b5)):
        write_wav(os.path.join(folder, "build_place_%s.wav" % name), make())


# --- Tercera ronda (B5.4): materializar y asentar, con estilo propio (idea de César a partir de Satisfactory) ---

def _shimmer(length=0.2, f_start=520.0, f_end=1560.0, gain=0.35, sparkle=True):
    """Zumbido de materialización: un tono que sube (glissando) con parciales de campanita y, si `sparkle`,
    unos destellos agudos. Sube de golpe y se corta suave justo antes del golpe."""
    out = []
    phase = 0.0
    n = int(RATE * length)
    for i in range(n):
        t = i / RATE
        x = i / n
        f = f_start * (f_end / f_start) ** (x * x)  # sube despacio y acelera al final
        phase += 2 * math.pi * f / RATE
        tone = math.sin(phase) + 0.35 * math.sin(2 * phase) + 0.15 * math.sin(3.01 * phase)
        wobble = 1.0 + 0.25 * math.sin(2 * math.pi * 28.0 * t)  # leve trémolo eléctrico
        env = min(1.0, t / 0.02) * min(1.0, (length - t) / 0.03) * (0.4 + 0.6 * x)
        out.append(tone * wobble * env * gain)
    if sparkle:
        for k in range(5):  # cinco destellos en la segunda mitad
            start = int(n * (0.45 + 0.1 * k))
            f = 3000.0 + 400.0 * k
            for i in range(int(RATE * 0.04)):
                t = i / RATE
                if start + i < n:
                    out[start + i] += math.sin(2 * math.pi * f * t) * math.exp(-t * 90.0) * gain * 0.4
    return out


def _boom(rng, length=0.5, low=55.0, gain=1.0, metal_gain=0.25):
    """Golpe grave al asentarse: un «bum» redondo que cae de tono, con un poco de metal y de tierra."""
    out = []
    phase = 0.0
    dirt = 0.0
    for i in range(int(RATE * length)):
        t = i / RATE
        f = low + low * 1.6 * math.exp(-t * 28.0)
        phase += 2 * math.pi * f / RATE
        body = (math.sin(phase) + 0.3 * math.sin(2 * phase)) * math.exp(-t * 9.0)
        ring = (math.sin(2 * math.pi * 690.0 * t) + 0.6 * math.sin(2 * math.pi * 1130.0 * t)) * math.exp(-t * 14.0) * metal_gain
        dirt += 0.2 * (rng.uniform(-1.0, 1.0) - dirt)
        thud = dirt * math.exp(-t * 35.0) * 1.2
        out.append((body + ring + thud) * min(1.0, t / 0.002) * gain)
    return out


def materialize_m1():
    """M1 · Zumbido que sube, pistón corto y golpe grave suave."""
    rng = random.Random(71)
    return _variant([(0.0, _shimmer(0.2)),
                     (0.17, _hiss(rng, 0.18, 0.55, decay=14.0)),
                     (0.2, _boom(rng, 0.45, gain=0.85))], 0.7)


def materialize_m2():
    """M2 · Zumbido que sube y un «bum» grave y pesado, sin pistón."""
    rng = random.Random(73)
    return _variant([(0.0, _shimmer(0.22, 440.0, 1320.0)),
                     (0.22, _boom(rng, 0.55, low=48.0, gain=1.0, metal_gain=0.35))], 0.8)


def materialize_m3():
    """M3 · Zumbido más corto y juguetón, golpe de madera y metal y un suspiro de aire al final."""
    rng = random.Random(79)
    return _variant([(0.0, _shimmer(0.15, 700.0, 2100.0, 0.3)),
                     (0.15, _boom(rng, 0.35, low=70.0, gain=0.7, metal_gain=0.45)),
                     (0.22, _hiss(rng, 0.3, 0.4, attack=0.03, decay=7.0, bright_start=0.35, bright_end=0.12))], 0.65)


def link_pneumatic():
    """Acople neumático: clic seco y un soplido muy corto (al conectar una cinta a un puerto)."""
    rng = random.Random(83)
    return _variant([(0.0, _click(rng, 2100.0, 0.6)), (0.01, _hiss(rng, 0.1, 0.45, attack=0.003, decay=30.0))], 0.15)


def link_electric():
    """Acople eléctrico: dos notas cortas que suben, como un «blip» de confirmación (al tender un cable)."""
    return _variant([(0.0, [x * 0.5 for x in _tone(1320.0, 0.07, ((1, 1.0), (2, 0.2)), 40.0, 0.002)]),
                     (0.06, [x * 0.5 for x in _tone(1980.0, 0.1, ((1, 1.0), (2, 0.2)), 30.0, 0.002)])], 0.2)


def write_materialize_previews(folder):
    os.makedirs(folder, exist_ok=True)
    for name, make in (("build_place_m1_shimmer_piston_boom", materialize_m1), ("build_place_m2_shimmer_boom", materialize_m2),
                       ("build_place_m3_short_toy", materialize_m3), ("link_pneumatic", link_pneumatic),
                       ("link_electric", link_electric)):
        write_wav(os.path.join(folder, name + ".wav"), make())


# --- Mover construcciones (C2b, César): sonidos propios para levantar y soltar, sin el zumbido de materializar ---

def _sweep(start, end, length, gain, curve=1.0):
    """Tono que sube (o baja) de `start` a `end` Hz en `length` s, con ataque corto y caída."""
    out = []
    phase = 0.0
    for i in range(int(RATE * length)):
        t = i / RATE
        f = start + (end - start) * (t / length) ** curve
        phase += 2 * math.pi * f / RATE
        env = min(1.0, t / 0.004) * math.exp(-t * 3.0 / length)
        out.append(math.sin(phase) * env * gain)
    return out


def _knock(rng, freq, gain, length=0.12):
    """Toque de madera: ruido suavizado muy corto y una resonancia que se apaga enseguida."""
    out = []
    low = 0.0
    for i in range(int(RATE * length)):
        t = i / RATE
        low += 0.3 * (rng.uniform(-1.0, 1.0) - low)
        out.append((low * math.exp(-t * 70.0) * 1.4 + math.sin(2 * math.pi * freq * t) * math.exp(-t * 45.0) * 0.6) * gain)
    return out


def move_lift_pneumatic():
    """A · Levantar, neumático: el cerrojo se suelta (clic) y un soplido que sube, como una ventosa que tira."""
    rng = random.Random(51)
    out = [0.0] * int(RATE * 0.3)
    _add(out, 0, _click(rng, 3000.0, 0.35))
    suck = []
    prev = 0.0
    length = 0.2
    for i in range(int(RATE * length)):
        t = i / RATE
        noise = rng.uniform(-1.0, 1.0)
        high = noise - prev
        prev = noise
        env = math.sin(math.pi * t / length)
        suck.append(high * env * 0.25)
    _add(out, int(RATE * 0.02), suck)
    _add(out, int(RATE * 0.02), _sweep(320.0, 1000.0, 0.2, 0.25, 1.5))
    return out


def move_drop_pneumatic():
    """A · Soltar, neumático: un soplido corto y un golpe ligero, más agudo y corto que el de construir."""
    rng = random.Random(53)
    out = [0.0] * int(RATE * 0.4)
    hiss = []
    prev = 0.0
    for i in range(int(RATE * 0.08)):
        t = i / RATE
        noise = rng.uniform(-1.0, 1.0)
        hiss.append((noise - prev) * min(1.0, t / 0.01) * math.exp(-t * 30.0) * 0.3)
        prev = noise
    _add(out, 0, hiss)
    _add(out, int(RATE * 0.06), _clank(rng, 0.3, low=130.0, metal=(1200.0, 1900.0, 2700.0), decay=16.0, gain=0.6))
    return out


def move_lift_toy():
    """B · Levantar, de juguete: un «bup» que sube y otro más agudo, como coger una pieza."""
    rng = random.Random(57)
    out = [0.0] * int(RATE * 0.25)
    _add(out, 0, _click(rng, 2200.0, 0.2))
    _add(out, 0, _sweep(420.0, 980.0, 0.09, 0.5))
    _add(out, int(RATE * 0.07), _sweep(700.0, 1300.0, 0.08, 0.3))
    return out


def move_drop_toy():
    """B · Soltar, de juguete: dos toques de madera, el segundo más suave (la pieza se asienta)."""
    rng = random.Random(59)
    out = [0.0] * int(RATE * 0.3)
    _add(out, 0, _knock(rng, 520.0, 1.0))
    _add(out, int(RATE * 0.07), _knock(rng, 640.0, 0.45))
    return out


def write_move_sounds(assets_folder, preview_folder=None, choice="a"):
    """Escribe move_lift.wav y move_drop.wav (la versión `choice`) y, si se da, las dos versiones para escuchar."""
    versions = {"a": (move_lift_pneumatic, move_drop_pneumatic), "b": (move_lift_toy, move_drop_toy)}
    lift, drop = versions[choice]
    write_wav(os.path.join(assets_folder, "move_lift.wav"), lift())
    write_wav(os.path.join(assets_folder, "move_drop.wav"), drop())
    if preview_folder:
        os.makedirs(preview_folder, exist_ok=True)
        for key, (lift, drop) in versions.items():
            write_wav(os.path.join(preview_folder, "move_%s_lift.wav" % key), lift())
            write_wav(os.path.join(preview_folder, "move_%s_drop.wav" % key), drop())



# --- Herramientas y trabajo (C3, César): mordedora, barrena, veta, árbol ---

def _noise_band(rng, n, bright, low_cut=0.04):
    """Ruido en banda de `n` muestras: `bright` (0–1) quita lo agudo y `low_cut` lo grave."""
    out = []
    low = low2 = 0.0
    for _ in range(n):
        low += bright * (rng.uniform(-1.0, 1.0) - low)
        low2 += low_cut * (low - low2)
        out.append(low - low2)
    return out


def biter_bite():
    """Mordisco de la mordedora (0,22 s): zumbido corto del servo y el «clac» de las mandíbulas al cerrarse."""
    rng = random.Random(81)
    out = [0.0] * int(RATE * 0.22)
    _add(out, 0, _sweep(320.0, 640.0, 0.07, 0.18))
    _add(out, int(RATE * 0.06), _clank(rng, 0.15, low=180.0, metal=(1900.0, 2750.0, 3600.0), decay=32.0, gain=0.8))
    return out


def drill_loop():
    """Motor de la barrena en bucle (1 s): tono de 110 Hz con armónicos, un silbido agudo y un leve vaivén
    de 8 Hz. Frecuencias enteras: el bucle empalma sin chasquido."""
    rng = random.Random(83)
    n = RATE
    out = [0.0] * n
    hiss = _noise_band(rng, n, 0.5, 0.08)
    for i in range(n):
        t = i / RATE
        motor = sum(math.sin(2 * math.pi * 110.0 * k * t) / k for k in range(1, 7)) * 0.35
        whine = math.sin(2 * math.pi * 1320.0 * t) * 0.08
        wobble = 1.0 + 0.12 * math.sin(2 * math.pi * 8.0 * t)
        out[i] = (motor + whine + hiss[i] * 0.12) * wobble
    return out


def vein_grind_loop():
    """La veta perforada, en bucle (1 s): rumor de roca y granitos que crujen al azar."""
    rng = random.Random(85)
    n = RATE
    out = [v * 0.5 for v in _noise_band(rng, n, 0.25, 0.02)]
    for _ in range(34):
        _add(out, rng.randrange(n), _knock(rng, rng.uniform(900.0, 2200.0), rng.uniform(0.15, 0.35), 0.04))
    return out


def _pebble(rng, gain):
    """Trozo de piedra que choca: un clic seco y brillante de unos milisegundos, sin tono."""
    length = rng.uniform(0.012, 0.03)
    out = []
    for i, v in enumerate(_noise_band(rng, int(RATE * length), rng.uniform(0.7, 0.95), 0.15)):
        t = i / RATE
        out.append(v * math.exp(-t * rng.uniform(180.0, 320.0)) * gain)
    return out


def vein_yield():
    """La veta suelta un mineral (0,3 s) (César: trozos de roca rotos que caen y chocan, corto): un primer
    choque más fuerte con algo de cuerpo y unos cuantos trozos que rebotan cada vez más flojo."""
    rng = random.Random(97)
    out = [0.0] * int(RATE * 0.3)
    body = _noise_band(rng, int(RATE * 0.05), 0.3, 0.03)
    _add(out, 0, [v * math.exp(-i / RATE * 70.0) * 1.2 for i, v in enumerate(body)])
    _add(out, 0, _pebble(rng, 1.3))
    at = 0.0
    for k in range(7):
        at += rng.uniform(0.018, 0.045)
        _add(out, int(RATE * at), _pebble(rng, 0.9 - k * 0.11))
    return out


def biter_loop():
    """Motor de la mordedora en bucle (1 s), como una sierra eléctrica pequeña (César): zumbido áspero de
    180 Hz con armónicos, un silbido agudo y el traqueteo de los dientes (ruido que late a 45 Hz).
    Frecuencias enteras: el bucle empalma sin chasquido."""
    rng = random.Random(93)
    n = RATE
    out = [0.0] * n
    chain = _noise_band(rng, n, 0.6, 0.1)
    for i in range(n):
        t = i / RATE
        buzz = sum(math.sin(2 * math.pi * 180.0 * k * t) / (k ** 0.8) for k in range(1, 9)) * 0.22
        whine = math.sin(2 * math.pi * 2340.0 * t) * 0.05
        teeth = 0.5 + 0.5 * math.sin(2 * math.pi * 45.0 * t)
        out[i] = buzz * (0.85 + 0.15 * teeth) + whine + chain[i] * teeth * teeth * 0.3
    return out


def wood_saw_loop():
    """El árbol cortado por la mordedora, en bucle (1 s): raspado de madera que late con los dientes
    (45 Hz) y un vaivén lento, sin golpes (César: no quería golpes metálicos)."""
    rng = random.Random(89)
    n = RATE
    out = [0.0] * n
    rasp = _noise_band(rng, n, 0.45, 0.06)
    dust = _noise_band(rng, n, 0.15, 0.02)
    for i in range(n):
        t = i / RATE
        teeth = (0.5 + 0.5 * math.sin(2 * math.pi * 45.0 * t)) ** 2
        sway = 0.75 + 0.25 * math.sin(2 * math.pi * 3.0 * t)
        out[i] = (rasp[i] * teeth * 0.9 + dust[i] * 0.35) * sway
    return out


def _crack(rng, length, gain, bright=0.85):
    """Chasquido de madera que se parte: ruido muy corto y brillante con un poco de cuerpo grave."""
    out = []
    low = 0.0
    body = _noise_band(rng, int(RATE * length), bright, 0.05)
    for i, v in enumerate(body):
        t = i / RATE
        low += 0.08 * (v - low)
        out.append((v * math.exp(-t * 140.0) + low * math.exp(-t * 40.0) * 1.5) * gain)
    return out


def tree_fall():
    """El árbol se parte y cae (1,8 s) (César: más como partir un tronco y menos digital): chasquidos que
    se aceleran mientras la madera cede, un crujido fuerte al partirse, el aire, el golpe sordo contra el
    suelo a los 1,05 s (FallingTree.FALL_TIME) y las hojas."""
    rng = random.Random(95)
    out = [0.0] * int(RATE * 1.8)
    count = 26
    for k in range(count):
        at = 0.55 * (k / count) ** 0.55 + rng.uniform(-0.01, 0.01)
        _add(out, int(RATE * max(0.0, at)), _crack(rng, rng.uniform(0.015, 0.05), 0.25 + 0.55 * k / count))
    _add(out, int(RATE * 0.58), _crack(rng, 0.18, 1.3, 0.7))
    _add(out, int(RATE * 0.62), _crack(rng, 0.09, 0.8, 0.9))
    _add(out, int(RATE * 0.6), _hiss(rng, 0.5, gain=0.25, attack=0.35, decay=1.5, bright_start=0.1, bright_end=0.35))
    # Golpe contra el suelo, seco y crujiente (César: sin el «bum» con tono, que sonaba digital): un golpe de
    # ruido grave muy corto y, encima, ramas que crujen y se parten.
    thud = _noise_band(rng, int(RATE * 0.18), 0.2, 0.02)
    _add(out, int(RATE * 1.05), [v * min(1.0, i / 25.0) * math.exp(-i / RATE * 28.0) * 2.0 for i, v in enumerate(thud)])
    _add(out, int(RATE * 1.05), _crack(rng, 0.07, 1.0, 0.6))
    at = 1.06
    for k in range(10):
        at += rng.uniform(0.006, 0.02)
        _add(out, int(RATE * at), _crack(rng, rng.uniform(0.01, 0.03), 0.6 - k * 0.04, rng.uniform(0.7, 0.95)))
    for k in range(5):
        _add(out, int(RATE * (1.08 + k * 0.05)), _crack(rng, 0.02, 0.25 - k * 0.04))
    leaves = _noise_band(rng, int(RATE * 0.6), 0.7, 0.1)
    _add(out, int(RATE * 1.08), [v * math.exp(-i / RATE * 5.0) * 0.3 for i, v in enumerate(leaves)])
    return out


def mineral_a():
    """A · Roca que se desprende: chasquido de piedra, un «toc» grave y sordo del trozo que cae y dos
    piedrecitas que ruedan (0,35 s)."""
    rng = random.Random(101)
    out = [0.0] * int(RATE * 0.35)
    _add(out, 0, _crack(rng, 0.04, 0.9, 0.8))
    _add(out, int(RATE * 0.02), _knock(rng, 150.0, 1.2, 0.14))
    tok = _noise_band(rng, int(RATE * 0.1), 0.15, 0.02)
    _add(out, int(RATE * 0.02), [v * math.exp(-i / RATE * 40.0) * 1.6 for i, v in enumerate(tok)])
    _add(out, int(RATE * 0.14), _pebble(rng, 0.5))
    _add(out, int(RATE * 0.2), _pebble(rng, 0.3))
    return out


def mineral_b():
    """B · Cristal: un toque de piedra y un «cling» suave y cálido de mineral, que suena a premio sin ser
    metálico (dos notas de marimba, como la música) (0,5 s)."""
    rng = random.Random(103)
    out = [0.0] * int(RATE * 0.5)
    _add(out, 0, _pebble(rng, 0.7))
    for start, note in ((0.0, 84), (0.07, 91)):
        f = _hz(note)
        tone = []
        for i in range(int(RATE * 0.4)):
            t = i / RATE
            v = (math.sin(2 * math.pi * f * t) + 0.25 * math.sin(2 * math.pi * f * 4.0 * t) * math.exp(-t * 30.0))
            tone.append(v * min(1.0, t / 0.003) * math.exp(-t * 11.0) * 0.45)
        _add(out, int(RATE * start), tone)
    return out


def mineral_c():
    """C · «Plop» de recogida: una burbuja corta que sube de tono, como al guardar algo en la mochila,
    con un clic de piedra delante (0,25 s)."""
    rng = random.Random(105)
    out = [0.0] * int(RATE * 0.25)
    _add(out, 0, _pebble(rng, 0.6))
    blip = []
    phase = 0.0
    for i in range(int(RATE * 0.16)):
        t = i / RATE
        f = 330.0 + 900.0 * (t / 0.16) ** 0.7
        phase += 2 * math.pi * f / RATE
        blip.append(math.sin(phase) * min(1.0, t / 0.004) * math.exp(-t * 18.0) * 0.8)
    _add(out, int(RATE * 0.015), blip)
    return out


def mineral_d():
    """D · Dos piedras: «toc-toc» de dos trozos de roca que chocan entre sí, el segundo más agudo y flojo,
    como al guardarlos juntos (0,25 s)."""
    rng = random.Random(107)
    out = [0.0] * int(RATE * 0.25)
    for start, freq, gain in ((0.0, 820.0, 1.0), (0.085, 1150.0, 0.6)):
        knock = []
        body = _noise_band(rng, int(RATE * 0.06), 0.5, 0.06)
        for i, v in enumerate(body):
            t = i / RATE
            knock.append((v * math.exp(-t * 120.0) + math.sin(2 * math.pi * freq * t) * math.exp(-t * 90.0) * 0.5) * gain)
        _add(out, int(RATE * start), knock)
    return out


def _stone_knock(rng, freq, gain, length=0.12, bright=0.35, ring=0.5):
    """Choque de piedra grave: ruido apagado (poco brillante) y una resonancia corta en `freq`."""
    out = []
    body = _noise_band(rng, int(RATE * length), bright, 0.02)
    for i, v in enumerate(body):
        t = i / RATE
        out.append((v * math.exp(-t * 45.0) * 1.3 + math.sin(2 * math.pi * freq * t) * math.exp(-t * 30.0) * ring) * gain)
    return out


def mineral_e():
    """E · Dos piedras, grave (la D, mucho más grave, César): «toc-toc» de dos trozos grandes que chocan (0,35 s)."""
    rng = random.Random(109)
    out = [0.0] * int(RATE * 0.35)
    _add(out, 0, _stone_knock(rng, 190.0, 1.0, 0.16))
    _add(out, int(RATE * 0.1), _stone_knock(rng, 250.0, 0.65, 0.14))
    return out


def mineral_f():
    """F · Losa que se parte: un crujido grave y apagado, el «crac» de la losa al abrirse con un rumor corto
    de piedra que roza, y los dos trozos que golpean el suelo (0,6 s)."""
    rng = random.Random(111)
    out = [0.0] * int(RATE * 0.6)
    _add(out, 0, _crack(rng, 0.09, 1.0, 0.35))
    rumble = _noise_band(rng, int(RATE * 0.18), 0.12, 0.01)
    _add(out, int(RATE * 0.01), [v * min(1.0, i / 200.0) * math.exp(-i / RATE * 14.0) * 1.8 for i, v in enumerate(rumble)])
    _add(out, int(RATE * 0.16), _stone_knock(rng, 120.0, 1.1, 0.2, 0.25, 0.6))
    _add(out, int(RATE * 0.24), _stone_knock(rng, 150.0, 0.7, 0.18, 0.25, 0.5))
    return out


def mineral_g():
    """G · Losa seca: un solo chasquido grave y fuerte, como la piedra que cede de golpe, con una cola corta
    de rumor que se apaga (0,45 s)."""
    rng = random.Random(113)
    out = [0.0] * int(RATE * 0.45)
    _add(out, 0, _crack(rng, 0.12, 1.4, 0.4))
    _add(out, 0, _stone_knock(rng, 95.0, 0.9, 0.25, 0.15, 0.7))
    tail = _noise_band(rng, int(RATE * 0.35), 0.1, 0.01)
    _add(out, int(RATE * 0.03), [v * math.exp(-i / RATE * 9.0) * 0.8 for i, v in enumerate(tail)])
    return out


def mineral_h():
    """H · Losa que se raja y se separa: un crujido largo y grave que se abre (la grieta corriendo) y un
    «toc» hondo cuando el trozo se suelta (0,55 s)."""
    rng = random.Random(115)
    out = [0.0] * int(RATE * 0.55)
    at = 0.0
    for k in range(9):
        _add(out, int(RATE * at), _crack(rng, rng.uniform(0.02, 0.04), 0.35 + k * 0.08, 0.3))
        at += 0.022
    _add(out, int(RATE * 0.22), _stone_knock(rng, 105.0, 1.2, 0.22, 0.2, 0.7))
    _add(out, int(RATE * 0.22), _crack(rng, 0.05, 0.6, 0.45))
    return out


def write_mineral_previews_2(folder):
    """La segunda tanda (C3, César: «como una gran losa partirse», la D pero más grave)."""
    os.makedirs(folder, exist_ok=True)
    for key, make in (("e_dos_piedras_grave", mineral_e), ("f_losa_se_parte", mineral_f), ("g_losa_seca", mineral_g),
                      ("h_losa_se_raja", mineral_h)):
        write_wav(os.path.join(folder, "mineral_%s.wav" % key), make())


def _rumble(rng, length, bright, gain, decay, attack=0.004):
    """Golpe sordo de roca: ruido muy grave (`bright` bajo = más grave) con ataque corto y caída."""
    out = []
    level = 1.0 / math.sqrt(bright / 2.0)   # el ruido tan filtrado queda muy flojo: se iguala su volumen
    for i, v in enumerate(_noise_band(rng, int(RATE * length), bright, 0.002)):
        t = i / RATE
        out.append(v * level * min(1.0, t / attack) * math.exp(-t * decay) * gain)
    return out


def _boulder(rng, seconds, impact, rolls, roll_gain, clatter):
    """Roca grande que se suelta y rueda, a partir de la referencia de César (un «heavy boulder thud»):
    un chasquido corto de piedra en medios, el golpe grave del bloque (más flojo que en la referencia, como
    pidió César) y luego `rolls` tumbos graves cada vez más flojos y separados al azar, con algo de gravilla."""
    out = [0.0] * int(RATE * seconds)
    _add(out, 0, _crack(rng, 0.035, 0.3 * clatter + 0.2, 0.55))
    _add(out, int(RATE * 0.008), _rumble(rng, 0.3, 0.008, 0.9 * impact, 12.0))
    _add(out, int(RATE * 0.008), _rumble(rng, 0.18, 0.025, 0.45 * impact, 22.0))
    at = 0.12
    for k in range(rolls):
        at += rng.uniform(0.05, 0.11)
        level = roll_gain * (1.0 - k / (rolls + 1)) * rng.uniform(0.7, 1.0)
        _add(out, int(RATE * at), _rumble(rng, 0.14, rng.uniform(0.012, 0.03), 0.6 * level, 30.0, 0.01))
        if rng.random() < clatter:
            _add(out, int(RATE * at), _pebble(rng, 0.35 * level))
    return out


def mineral_i():
    """I · Roca que rueda (la más parecida a la referencia, con el golpe más suave): 0,9 s."""
    return _boulder(random.Random(121), 0.9, impact=0.7, rolls=6, roll_gain=0.7, clatter=0.4)


def mineral_j():
    """J · Roca que cae y se asienta (más corta, menos tumbos): 0,55 s."""
    return _boulder(random.Random(123), 0.55, impact=0.8, rolls=3, roll_gain=0.6, clatter=0.3)


def mineral_k():
    """K · Roca que rueda con gravilla (golpe aún más flojo y más piedrecitas): 0,8 s."""
    return _boulder(random.Random(125), 0.8, impact=0.5, rolls=5, roll_gain=0.55, clatter=0.9)


def write_mineral_previews_3(folder):
    """La tercera tanda (C3), a partir de la referencia de César."""
    os.makedirs(folder, exist_ok=True)
    for key, make in (("i_roca_rueda", mineral_i), ("j_roca_se_asienta", mineral_j), ("k_roca_y_gravilla", mineral_k)):
        write_wav(os.path.join(folder, "mineral_%s.wav" % key), make())


def _dry_hit(rng, impact, depth):
    """Primer golpe seco de la roca (C3, César: la J sonaba «enlatada»): sin resonancias en medios; un
    chasquido muy corto de ruido ancho y un golpe grave que se corta enseguida. `depth`: 0 = menos grave."""
    out = [0.0] * int(RATE * 0.12)
    click = _noise_band(rng, int(RATE * 0.012), 0.9, 0.2)
    _add(out, 0, [v * math.exp(-i / RATE * 400.0) * 0.5 for i, v in enumerate(click)])
    _add(out, 0, _rumble(rng, 0.12, 0.006 + 0.006 * (1.0 - depth), 0.9 * impact, 38.0, 0.002))
    return out


def _dust(rng, length, gain, grains):
    """Polvo y arenilla que caen tras el golpe: un siseo suave y apagado que se va y unos granitos
    sueltos muy flojos (`grains`)."""
    out = [0.0] * int(RATE * length)
    hiss = _noise_band(rng, len(out), 0.35, 0.08)
    for i, v in enumerate(hiss):
        t = i / RATE
        out[i] += v * min(1.0, t / 0.03) * math.exp(-t * 7.0) * gain
    for _ in range(grains):
        at = rng.uniform(0.0, length * 0.7)
        _add(out, int(RATE * at), _pebble(rng, gain * rng.uniform(0.25, 0.6)))
    return out


def mineral_l():
    """L · Golpe seco y polvo suave: 0,5 s."""
    rng = random.Random(131)
    out = [0.0] * int(RATE * 0.5)
    _add(out, 0, _dry_hit(rng, 1.0, 0.6))
    _add(out, int(RATE * 0.03), _dust(rng, 0.45, 0.18, 4))
    return out


def mineral_m():
    """M · Golpe seco y polvo con más arenilla: 0,5 s."""
    rng = random.Random(133)
    out = [0.0] * int(RATE * 0.5)
    _add(out, 0, _dry_hit(rng, 1.0, 0.6))
    _add(out, int(RATE * 0.03), _dust(rng, 0.45, 0.14, 12))
    return out


def mineral_n():
    """N · Golpe seco más grave y polvo corto: 0,4 s."""
    rng = random.Random(135)
    out = [0.0] * int(RATE * 0.4)
    _add(out, 0, _dry_hit(rng, 1.0, 1.0))
    _add(out, int(RATE * 0.025), _dust(rng, 0.35, 0.16, 6))
    return out


def write_mineral_previews_4(folder):
    """La cuarta tanda (C3): la J con el primer golpe más seco y polvo que cae en lugar de tumbos."""
    os.makedirs(folder, exist_ok=True)
    for key, make in (("l_seco_polvo", mineral_l), ("m_seco_arenilla", mineral_m), ("n_seco_grave", mineral_n)):
        write_wav(os.path.join(folder, "mineral_%s.wav" % key), make())


def mineral_o():
    """O · El primer golpe de la J y el polvo con arenilla de la M (César): 0,5 s. Se rehacen con sus
    mismas semillas, así que suenan igual que en las dos pruebas."""
    hit = _boulder(random.Random(123), 0.2, impact=0.8, rolls=0, roll_gain=0.6, clatter=0.3)
    rng = random.Random(133)
    _dry_hit(rng, 1.0, 0.6)   # gasta los mismos números al azar que la M antes de su polvo
    dust = _dust(rng, 0.45, 0.14, 12)
    out = [0.0] * int(RATE * 0.5)
    _add(out, 0, hit)
    _add(out, int(RATE * 0.03), dust)
    return out


def write_mineral_previews(folder):
    """Las cuatro versiones del sonido de conseguir un mineral, para escucharlas y elegir (C3)."""
    os.makedirs(folder, exist_ok=True)
    for key, make in (("a_roca", mineral_a), ("b_cristal", mineral_b), ("c_plop", mineral_c), ("d_dos_piedras", mineral_d)):
        write_wav(os.path.join(folder, "mineral_%s.wav" % key), make())


def write_tool_sounds(assets_folder):
    """Escribe los sonidos de C3 en assets/audio. Los que acaban en _loop se repiten mientras se trabaja."""
    # El mineral: la versión O, elegida por César tras cuatro tandas de pruebas (mineral_o).
    sounds = {"biter_loop": biter_loop, "drill_loop": drill_loop, "vein_grind_loop": vein_grind_loop,
              "vein_yield": mineral_o, "wood_saw_loop": wood_saw_loop, "tree_fall": tree_fall}
    for name, make in sounds.items():
        write_wav(os.path.join(assets_folder, name + ".wav"), make())
    return sorted(sounds)


# --- Fuego (C5.5, D-191): el fogón y el candil del refugio ---

def _crackle(rng, gain=0.5, low=900.0, high=2600.0):
    """Chasquido de leña: un clic de ruido muy corto con una resonancia al azar entre `low` y `high` Hz."""
    n = int(RATE * 0.035)
    freq = rng.uniform(low, high)
    out = []
    for i in range(n):
        t = i / RATE
        out.append((rng.uniform(-1.0, 1.0) * math.exp(-t * 1100.0) * 0.6 + math.sin(2 * math.pi * freq * t) * math.exp(-t * 180.0)) * gain)
    return out


def _snap(rng, gain=0.3, bright=0.7):
    """Chasquido seco de leña, solo ruido y sin tono (con tono sonaban a burbujas de agua hirviendo, César): un golpe
    de ruido de unos milisegundos, más o menos brillante."""
    n = int(RATE * rng.uniform(0.004, 0.012))
    out = []
    low = 0.0
    for i in range(n):
        t = i / RATE
        low += bright * (rng.uniform(-1.0, 1.0) - low)
        out.append(low * math.exp(-t * 500.0) * gain)
    return out


def _flutter(rng, n, gain):
    """Rumor de llama: ruido muy grave (sin siseo) que sube y baja despacio, como una llama que respira."""
    out = []
    low = low2 = 0.0
    wobble = rng.uniform(0, 6.28)
    for i in range(n):
        t = i / RATE
        low += 0.006 * (rng.uniform(-1.0, 1.0) - low)
        low2 += 0.03 * (low - low2)
        breath = 0.6 + 0.4 * math.sin(2 * math.pi * 0.7 * t + wobble) * math.sin(2 * math.pi * 0.23 * t)
        out.append(low2 * breath * gain)
    return out


def fire_light():
    """Prender (sesión 23, más suave: César lo oía como un soplete): un «fup» grave y corto de la llama que prende y
    unos chasquidos de la leña. 0,8 s."""
    rng = random.Random(311)
    n = int(RATE * 0.8)
    out = [0.0] * n
    air = _flutter(rng, n, 9.0)
    for i in range(n):
        t = i / RATE
        env = min(1.0, t / 0.05) * math.exp(-max(0.0, t - 0.05) * 6.0)
        thump = math.sin(2 * math.pi * (55.0 + 40.0 * math.exp(-t * 18.0)) * t) * math.exp(-t * 12.0) * 0.35
        out[i] = air[i] * env + thump
    for k in range(7):
        _add(out, int(RATE * rng.uniform(0.12, 0.7)), _snap(rng, rng.uniform(0.2, 0.45), rng.uniform(0.4, 0.9)))
    return out


def fire_out():
    """Apagar: un soplo corto y un siseo que se va, como brasas tapadas, con algún chasquido suelto. 1 s."""
    rng = random.Random(312)
    n = int(RATE * 1.0)
    out = [0.0] * n
    hiss = _noise_band(rng, n, 0.6, 0.08)
    puff = _noise_band(rng, n, 0.12, 0.01)
    for i in range(n):
        t = i / RATE
        out[i] = hiss[i] * min(1.0, t / 0.03) * math.exp(-t * 3.2) * 0.5 + puff[i] * math.exp(-t * 18.0) * 1.2
    for k in range(3):
        _add(out, int(RATE * rng.uniform(0.15, 0.6)), _snap(rng, rng.uniform(0.1, 0.25), rng.uniform(0.4, 0.9)))
    return out


def fire_crackle_loop():
    """Fuego encendido, 4 s en bucle (sesión 23: sin siseo, César lo oía como un soplete): chasquidos secos de leña (sin tono:
    con tono sonaban a agua hirviendo) repartidos al azar, de muy suaves a algo más fuertes, sobre un rumor grave y bajito que respira. Lo que pasa del final vuelve
    al principio, así que el bucle no se nota."""
    rng = random.Random(313)
    n = int(RATE * 4.0)
    out = [0.0] * n
    rumble = _flutter(rng, n + RATE // 2, 1.8)
    fade = RATE // 2   # el principio y el final del rumor se funden para cerrar el bucle
    for i in range(n):
        v = rumble[i]
        if i < fade:
            v = v * (i / fade) + rumble[n + i] * (1.0 - i / fade)
        out[i] = v
    # Pocos y espaciados (César: con 50 en 4 s sonaba muy rápido): unos 4 por segundo, suaves y más apagados.
    for k in range(14):
        _add(out, rng.randrange(n), _snap(rng, rng.uniform(0.06, 0.18), rng.uniform(0.2, 0.55)))
    for k in range(3):   # algún chasquido algo más fuerte y sordo (un nudo que revienta)
        _add(out, rng.randrange(n), _snap(rng, rng.uniform(0.3, 0.45), 0.2))
    return out


def write_fire_sounds(assets_folder):
    """Escribe los sonidos del fuego en assets/audio (C5.5)."""
    sounds = {"fire_light": fire_light, "fire_out": fire_out, "fire_crackle_loop": fire_crackle_loop}
    for name, make in sounds.items():
        write_wav(os.path.join(assets_folder, name + ".wav"), make())
    return sorted(sounds)


if __name__ == "__main__":
    folder = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(folder, exist_ok=True)
    # Elegidas por César (B5.4): M1 (zumbido, pistón y golpe; el golpe cae a los 0,2 s, como el rebote de
    # BuildingView.PLACE_GROW_TIME). Las demás versiones siguen arriba por si acaso. La música ya no sale de
    # aquí, sino de make_music.py (C1.8); music_test_v2() queda solo como referencia.
    write_wav(os.path.join(folder, "build_place.wav"), materialize_m1())
    if "--v2" in sys.argv:
        write_previews(folder)
    print("Sonidos escritos en", folder)
