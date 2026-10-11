"""Build presentation-only ANM2s from native textures and authored effect art.

No vanilla texture or sound is copied into the mod. The clock PNG is an
original authored input; this generator never rewrites it. The thunder
strike, rain and the clock's tick, tock and bell are synthesized here from fixed seeds. Run from any working directory.
"""
from pathlib import Path
import math
import random
import struct
import wave
import xml.etree.ElementTree as ET
from PIL import Image

ROOT = Path(__file__).resolve().parent
DEST = ROOT / 'resources/gfx/effects'
SFX = ROOT / 'resources/sfx'
SAMPLE_RATE = 44100
CLOCK_PARTS = {
    # Atlas rectangles and pivots keep the centre open and each hand separate.
    'rim': ((56, 40, 590, 664, 295, 371), 100 * 42 / 584),
    'minute': ((292, 778, 104, 416, 52, 366), 100 * 15 / 360),
    'hour': ((852, 920, 116, 274, 58, 224), 100 * 11 / 218),
}


def actor(name, sheet, frames, strips=False, scale=100):
    root = ET.Element('AnimatedActor')
    ET.SubElement(root, 'Info', CreatedBy='ConchBlessing', Version='20', Fps='30')
    content = ET.SubElement(root, 'Content')
    ET.SubElement(ET.SubElement(content, 'Spritesheets'), 'Spritesheet', Id='0', Path=sheet)
    layers = ET.SubElement(content, 'Layers')
    for i in range(len(frames) if strips else 1):
        ET.SubElement(layers, 'Layer', Id=str(i), Name=f'Visual{i}' if strips else 'Visual', SpritesheetId='0')
    ET.SubElement(content, 'Nulls')
    ET.SubElement(content, 'Events')
    animations = ET.SubElement(root, 'Animations', DefaultAnimation='Idle')
    count = 1 if strips else len(frames)
    animation = ET.SubElement(animations, 'Animation', Name='Idle', FrameNum=str(count), Loop='true')
    common = dict(XPosition='0', YPosition='0', XScale='100', YScale='100',
                  Delay='1', Visible='true', RedTint='255', GreenTint='255', BlueTint='255',
                  AlphaTint='255', RedOffset='0', GreenOffset='0', BlueOffset='0',
                  Rotation='0', Interpolated='false')
    ET.SubElement(ET.SubElement(animation, 'RootAnimation'), 'Frame', **{**common, 'Delay': str(count)})
    animations = ET.SubElement(animation, 'LayerAnimations')
    layer = None
    for i, (x, y, w, h, px, py) in enumerate(frames):
        if strips or layer is None:
            layer = ET.SubElement(animations, 'LayerAnimation', LayerId=str(i if strips else 0), Visible='true')
        ET.SubElement(layer, 'Frame', **{**common, 'XScale': str(scale), 'YScale': str(scale)}, XCrop=str(x), YCrop=str(y), Width=str(w),
                      Height=str(h), XPivot=str(px), YPivot=str(py))
    ET.SubElement(animation, 'NullAnimations')
    ET.SubElement(animation, 'Triggers')
    ET.indent(root, space='  ')
    (DEST / f'conch_upgrade_{name}.anm2').write_text(ET.tostring(root, encoding='unicode') + '\n', encoding='utf-8')


def spotlight_mask():
    """Analytic alpha aperture, like the white line primitive, not authored art."""
    mask = Image.new('RGBA', (160, 160))
    pixels = []
    for y in range(160):
        for x in range(160):
            radius = math.hypot(x + 0.5 - 80, y + 0.5 - 80)
            p = max(0, min(1, (radius - 24) / 52))
            pixels.append((255, 255, 255, round(255 * p * p * (3 - 2 * p))))
    mask.putdata(pixels)
    mask.save(DEST / 'conch_upgrade_spotlight.png')
    actor('spotlight', 'conch_upgrade_spotlight.png', [(0, 0, 160, 160, 80, 80)])


def biquad(samples, kind, freq, q=0.7071):
    """RBJ low/high-pass section; cascade two for a 24 dB/oct slope."""
    w = 2 * math.pi * freq / SAMPLE_RATE
    c, alpha = math.cos(w), math.sin(w) / (2 * q)
    sign = 1 if kind == 'low' else -1
    b0 = b2 = (1 - sign * c) / 2
    b1 = sign * (1 - sign * c)
    a0, a1, a2 = 1 + alpha, -2 * c, 1 - alpha
    out, x1, x2, y1, y2 = [], 0.0, 0.0, 0.0, 0.0
    for x in samples:
        y = (b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0
        x2, x1, y2, y1 = x1, x, y1, y
        out.append(y)
    return out


def normalized(samples):
    peak = max(abs(v) for v in samples) or 1
    return [v / peak for v in samples]


def thunder_strike(seconds=2.6, seed=0x7C0C4):
    """A nearby strike: crack, low boom, then rolls that fade out.

    The vanilla thunder samples swell slowly like distant thunder, and the
    lightning samples are a bright electric buzz. This keeps the crack under
    ~3 kHz so it lands hard without the sharp hiss.
    """
    rng = random.Random(seed)
    n = int(SAMPLE_RATE * seconds)

    def noise():
        return rng.random() * 2 - 1

    def clicks(target, start, stop, spacing, amplitude, tau):
        t = start
        while t < stop:
            begin, decay = int(t * SAMPLE_RATE), tau()
            amp = amplitude(t)
            for i in range(int(decay * 7 * SAMPLE_RATE)):
                if 0 <= begin + i < n:
                    # A 0.3 ms ramp keeps each click from starting on a hard step.
                    ramp = min(1, i / (0.0003 * SAMPLE_RATE))
                    target[begin + i] += amp * noise() * ramp * math.exp(-i / (decay * SAMPLE_RATE))
            t += spacing(t)

    # The nearest channel tears first: dense clicks thinning out over 0.2 s.
    tear = [0.0] * n
    clicks(tear, 0.0, 0.2, lambda t: (0.0012 + 0.009 * (t / 0.2) ** 2) * (0.5 + rng.random()),
           lambda t: (0.4 + 0.6 * rng.random()) * (1 - t / 0.2) ** 1.3,
           lambda: 0.0002 + 0.0007 * rng.random())
    tear = normalized(biquad(biquad(biquad(tear, 'high', 300), 'low', 5200), 'low', 5200))
    clap = [noise() * min(1, i / (0.002 * SAMPLE_RATE)) * math.exp(-i / (0.025 * SAMPLE_RATE))
            if i < 0.09 * SAMPLE_RATE else 0.0 for i in range(n)]
    clap = normalized(biquad(biquad(clap, 'low', 2600), 'high', 120))
    boom = normalized(biquad(biquad([noise() for _ in range(n)], 'low', 160), 'low', 160))
    for i in range(n):
        x = i / SAMPLE_RATE
        chirp = math.sin(2 * math.pi * (66 * x - 8 * x * x)) * math.exp(-x / 0.28) * min(1, x / 0.012)
        boom[i] = boom[i] * min(1, x / 0.015) * math.exp(-x / 0.33) + chirp * 0.15
    boom = normalized(boom)
    # Farther segments arrive later as separate rolls with soft crackle.
    rolls = [(0.22, 0.12, 1.0), (0.48, 0.15, 0.75), (0.82, 0.2, 0.5), (1.2, 0.26, 0.32), (1.62, 0.3, 0.18)]
    last, rumble = 0.0, []
    for _ in range(n):
        last = 0.98 * last + 0.2 * noise()
        rumble.append(last)
    rumble = normalized(biquad(biquad(rumble, 'low', 420), 'high', 35))
    for i in range(n):
        x = i / SAMPLE_RATE
        roll = sum(a * math.exp(-((x - c) / w) ** 2) for c, w, a in rolls)
        fade = 1.0 if x < seconds - 0.6 else 0.5 + 0.5 * math.cos(math.pi * (x - seconds + 0.6) / 0.6)
        rumble[i] *= min(1, x / 0.08) * (0.3 + roll) * math.exp(-x / 1.25) * fade
    rumble = normalized(rumble)
    crackle = [0.0] * n
    for c, w, a in rolls:
        clicks(crackle, c - w, c + w * 1.2, lambda t: 0.004 + 0.03 * rng.random(),
               lambda t, c=c, w=w, a=a: a * (0.3 + 0.7 * rng.random()) * math.exp(-((t - c) / w) ** 2),
               lambda: 0.0004 + 0.0015 * rng.random())
    crackle = normalized(biquad(biquad(crackle, 'low', 1400), 'high', 150))
    mix = [tear[i] * 0.5 + clap[i] * 0.7 + boom[i] * 0.95 + rumble[i] * 0.6 + crackle[i] * 0.21
           for i in range(n)]
    # Two short, darker reflections place it nearby instead of far away.
    for delay, gain in ((0.06, 0.25), (0.15, 0.14)):
        d = int(delay * SAMPLE_RATE)
        for i, v in enumerate(biquad(mix[:n - d], 'low', 2000)):
            mix[i + d] += v * gain
    # No saturation: soft clipping thickened the boom but made it sound
    # broken. Sub-bass below ~45 Hz only distorts small speakers.
    return [v * 0.85 for v in normalized(biquad(biquad(mix, 'high', 45), 'high', 45))]


def rain_shower(seconds=5.8, seed=0x2A1B):
    """Steady rain for the rain upgrades: a soft hiss under many small drops.

    Vanilla has no rain sound effect (Downpour's rain lives in its music), so
    this is synthesized. It fades in with the drops and out with the flood.
    """
    rng = random.Random(seed)
    n = int(SAMPLE_RATE * seconds)

    def noise():
        return rng.random() * 2 - 1

    hiss = normalized(biquad(biquad(biquad([noise() for _ in range(n)], 'high', 500), 'low', 4500), 'low', 4500))
    for i in range(n):
        x = i / SAMPLE_RATE
        hiss[i] *= 1 + .15 * math.sin(2 * math.pi * .37 * x) + .1 * math.sin(2 * math.pi * .91 * x + 1.3)
    drops = [0.0] * n
    t = 0.0
    while t < seconds:
        begin, amp = int(t * SAMPLE_RATE), .2 + .8 * rng.random() ** 2
        decay = .002 + .006 * rng.random()
        for i in range(int(decay * 6 * SAMPLE_RATE)):
            if begin + i < n:
                drops[begin + i] += amp * noise() * math.exp(-i / (decay * SAMPLE_RATE))
        if rng.random() < .12:  # an occasional larger plip on a puddle
            tone, length = 1400 + 1600 * rng.random(), int(.03 * SAMPLE_RATE)
            for i in range(length):
                if begin + i < n:
                    drops[begin + i] += amp * .6 * math.sin(2 * math.pi * tone * i / SAMPLE_RATE) \
                        * math.exp(-i / (.012 * SAMPLE_RATE))
        t += -math.log(1 - rng.random()) / 38  # about 38 drops per second
    drops = normalized(biquad(biquad(drops, 'high', 900), 'low', 6000))
    mix = []
    for i in range(n):
        x = i / SAMPLE_RATE
        fade_in = min(1, x / .7)
        fade_out = 1 if x < seconds - 1 else max(0, (seconds - x) / 1)
        envelope = (fade_in * fade_in * (3 - 2 * fade_in)) * (fade_out * fade_out * (3 - 2 * fade_out))
        mix.append((hiss[i] * .45 + drops[i] * .75) * envelope)
    return [v * .8 for v in normalized(mix)]


def escapement_strike(out, start, amp, rng, partials):
    """One strike of a clock escapement: a sub-millisecond broadband snap that
    rings a few inharmonic metal and case partials for only a few milliseconds."""
    n = len(out)
    s0 = int(start * SAMPLE_RATE)
    for i in range(int(.0007 * SAMPLE_RATE)):
        if s0 + i < n:
            out[s0 + i] += amp * 1.6 * (rng.random() * 2 - 1) * math.exp(-i / (.00025 * SAMPLE_RATE))
    for freq, decay, level in partials:
        phase = rng.random() * 2 * math.pi
        for i in range(int(decay * 7 * SAMPLE_RATE)):
            if s0 + i >= n:
                break
            x = i / SAMPLE_RATE
            out[s0 + i] += amp * level * math.sin(2 * math.pi * freq * x + phase) * math.exp(-x / decay)


def clock_click(seed, partials, second_strike, high_pass):
    """One escapement click: the pallet strikes, then the wheel drops onto the
    next pallet a few milliseconds later, ringing metal and case partials."""
    rng = random.Random(seed)
    out = [0.0] * int(SAMPLE_RATE * .09)
    for start, amp in ((0.0, 1.0), second_strike):
        escapement_strike(out, start, amp, rng, partials)
    out = biquad(out, 'high', high_pass)
    # Light saturation gives the snap the density of a real click.
    out = [math.tanh(2.2 * v) for v in normalized(out)]
    fade = int(.008 * SAMPLE_RATE)
    for i in range(fade):
        out[len(out) - 1 - i] *= i / fade
    return [v * .95 for v in normalized(out)]


def clock_tick(seed=0x71C):
    """째: the bright, sharp half of a mechanical clock's tick-tock."""
    metal = [(3100, .0030, .6), (4700, .0024, .45), (6400, .0018, .35), (8200, .0013, .2)]
    case = [(900, .0040, .15)]
    return clock_click(seed, metal + case, (.007, .4), 600)


def clock_tock(seed=0x70C):
    """깍: the lower, hollower half, with more of the clock case in it."""
    metal = [(1900, .0045, .5), (2900, .0035, .4), (4200, .0026, .25)]
    case = [(520, .0080, .35), (1050, .0050, .25)]
    return clock_click(seed, metal + case, (.009, .45), 250)


def clock_bell(seed=0xB31):
    """댕: a grandfather clock striking 12 on its coiled gong. Heavy, not a
    light bell: a deep fundamental (C3) and the gong's inharmonic partials ring
    for seconds with slow beating, a padded hammer thuds into the steel, and
    the wooden case booms underneath. Vanilla has no clock strike."""
    rng = random.Random(seed)
    n = int(SAMPLE_RATE * 4.5)
    f0 = 130.8
    partials = [  # ratio to the fundamental, level, decay seconds
        (1.0, .80, 3.6), (1.0 + .35 / 130.8, .35, 3.6),
        (2.02, .30, 2.6),
        (2.76, .62, 2.3), (2.76 + .8 / 130.8, .25, 2.3),
        (3.91, .30, 1.5), (5.40, .28, .95), (6.62, .14, .6), (8.93, .12, .32),
    ]
    out = [0.0] * n
    for ratio, level, decay in partials:
        w = 2 * math.pi * f0 * ratio / SAMPLE_RATE
        phase, step, amp = rng.random() * 2 * math.pi, math.exp(-1 / (decay * SAMPLE_RATE)), level
        for i in range(n):
            out[i] += amp * math.sin(w * i + phase)
            amp *= step
    for i in range(int(.6 * SAMPLE_RATE)):
        x = i / SAMPLE_RATE
        out[i] += .55 * math.sin(2 * math.pi * 98 * x) * math.exp(-x / .18)
    thud = [(rng.random() * 2 - 1) * math.exp(-i / (.0025 * SAMPLE_RATE)) for i in range(int(.012 * SAMPLE_RATE))]
    for i, v in enumerate(biquad(biquad(thud, 'low', 2200), 'high', 120)):
        out[i] += 1.1 * v
    attack = int(.003 * SAMPLE_RATE)
    for i in range(attack):
        out[i] *= i / attack
    fade = int(.6 * SAMPLE_RATE)
    for i in range(fade):
        out[n - 1 - i] *= (i / fade) ** 2
    return [v * .95 for v in normalized(out)]


def write_wav(path, samples):
    with wave.open(str(path), 'wb') as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(SAMPLE_RATE)
        out.writeframes(b''.join(struct.pack('<h', max(-32767, min(32767, round(v * 32767))))
                                 for v in samples))


if __name__ == '__main__':
    DEST.mkdir(parents=True, exist_ok=True)
    SFX.mkdir(parents=True, exist_ok=True)
    write_wav(SFX / 'conch_upgrade_thunder_strike.wav', thunder_strike())
    write_wav(SFX / 'conch_upgrade_rain.wav', rain_shower())
    write_wav(SFX / 'conch_upgrade_clock_tick.wav', clock_tick())
    write_wav(SFX / 'conch_upgrade_clock_tock.wav', clock_tock())
    write_wav(SFX / 'conch_upgrade_clock_bell.wav', clock_bell())
    Image.new('RGBA', (1, 1), (255, 255, 255, 255)).save(DEST / 'conch_upgrade_pixel.png')
    actor('pixel', 'conch_upgrade_pixel.png', [(0, 0, 1, 1, 0, 0)])
    spotlight_mask()
    # Replaced with ItemConfig.GfxFileName before drawing; placeholder is owned art.
    actor('icon', '../items/collectibles/void_dagger.png', [(0, 0, 32, 32, 16, 16)])
    actor('smoke', 'effect_088_darksmoke.png', [(0, 0, 48, 48, 24, 24)])
    for name, sheet in [('fire', 'effect_005_fire.png'), ('ice', 'effect_005_fire_blue.png')]:
        actor(name, sheet, [(i % 5 * 48, i // 5 * 48, 48, 48, 24, 40) for i in range(6)])
    actor('floor', '../backdrop/14_the drowned caves.png', [(96, 64, 40, 40, 20, 20)])
    actor('halo', '../items/collectibles/collectibles_101_thehalo.png', [(0, 0, 32, 32, 16, 16)])
    for part, (frame, scale) in CLOCK_PARTS.items():
        actor('clock_' + part, 'conch_upgrade_clock.png', [frame], scale=scale)
