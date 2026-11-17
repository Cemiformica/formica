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


if __name__ == "__main__":
    folder = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(folder, exist_ok=True)
    # Elegidas por César (B5.4): M1 (zumbido, pistón y golpe; el golpe cae a los 0,2 s, como el rebote de
    # BuildingView.PLACE_GROW_TIME) y la música de 16 s. Las demás versiones siguen arriba por si acaso.
    write_wav(os.path.join(folder, "build_place.wav"), materialize_m1())
    write_wav(os.path.join(folder, "music_test.wav"), music_test_v2())
    if "--v2" in sys.argv:
        write_previews(folder)
    print("Sonidos escritos en", folder)
